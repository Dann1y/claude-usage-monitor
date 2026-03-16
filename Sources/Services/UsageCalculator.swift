import Foundation
import Combine

@MainActor
final class UsageCalculator: ObservableObject {
    @Published var summary: UsageSummary?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var rateLimitWarning: String?
    @Published var tokenStatus: TokenStatus?
    @Published var isCachedData = false

    enum TokenStatus {
        case expired
        case authFailed

        var message: String {
            switch self {
            case .expired:
                return "Token expired — use Claude Code to refresh"
            case .authFailed:
                return "Auth failed — run 'claude' in terminal"
            }
        }
    }

    private let apiClient = APIClient()
    private var refreshTimer: Timer?
    private var fileWatcher: FileWatcher?
    private var debounceWorkItem: DispatchWorkItem?
    private var currentTask: Task<Void, Never>?

    // Rate limit backoff
    private var rateLimitBackoffUntil: Date?
    private var consecutiveRateLimits: Int = 0
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 45 // seconds between requests

    // Disk cache keys
    private static let cacheKey = "cachedUsageResponse"
    private static let cacheTimestampKey = "cachedUsageTimestamp"

    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            setupTimer()
        }
    }

    init() {
        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        // Migrate removed 15s/30s intervals to 60s
        if let interval = RefreshInterval(rawValue: stored) {
            self.refreshInterval = interval
        } else {
            self.refreshInterval = .sixty
            UserDefaults.standard.set(RefreshInterval.sixty.rawValue, forKey: "refreshInterval")
        }

        // Load cached data on init
        loadCachedSummary()
    }

    func start() {
        recalculate()
        setupTimer()
        setupFileWatcher()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        fileWatcher?.stop()
        fileWatcher = nil
        currentTask?.cancel()
        currentTask = nil
    }

    func recalculate(force: Bool = false) {
        // Skip if in backoff period (unless forced by manual refresh)
        if !force, let backoffUntil = rateLimitBackoffUntil, Date() < backoffUntil {
            return
        }

        // Skip if too soon since last request (unless forced)
        if !force, let lastRequest = lastRequestTime,
           Date().timeIntervalSince(lastRequest) < minimumRequestInterval {
            return
        }

        currentTask?.cancel()
        isLoading = true
        lastError = nil

        currentTask = Task {
            do {
                self.lastRequestTime = Date()
                let response = try await apiClient.fetchUsage()
                guard !Task.isCancelled else { return }

                // Reset backoff on success
                self.consecutiveRateLimits = 0
                self.rateLimitBackoffUntil = nil
                self.rateLimitWarning = nil
                self.tokenStatus = nil
                self.isCachedData = false

                let newSummary = self.buildSummary(from: response)
                self.summary = newSummary
                self.saveSummaryToCache(response)
                self.isLoading = false
            } catch let apiError as APIClient.APIError {
                guard !Task.isCancelled else { return }

                switch apiError {
                case .tokenExpired:
                    self.handleTokenIssue(.expired)
                case .httpError(401), .httpError(403):
                    self.handleTokenIssue(.authFailed)
                case .rateLimited:
                    self.handleRateLimit()
                    if self.summary != nil {
                        self.rateLimitWarning = apiError.localizedDescription
                        self.isLoading = false
                        return
                    }
                    self.lastError = apiError.localizedDescription
                default:
                    self.lastError = apiError.localizedDescription
                }
                self.isLoading = false
            } catch let decodingError as DecodingError {
                guard !Task.isCancelled else { return }
                self.lastError = UsageCalculator.describeDecodingError(decodingError)
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func handleTokenIssue(_ status: TokenStatus) {
        self.tokenStatus = status
        // Keep existing summary (from memory or disk cache) — don't clear it
        if self.summary != nil {
            self.isCachedData = true
            self.lastError = nil
        } else {
            self.lastError = status.message
        }
    }

    private func handleRateLimit() {
        consecutiveRateLimits += 1
        // Exponential backoff: 30s, 60s, 120s, 240s (max ~4 min)
        let backoffSeconds = min(30.0 * pow(2.0, Double(consecutiveRateLimits - 1)), 240.0)
        rateLimitBackoffUntil = Date().addingTimeInterval(backoffSeconds)
        let backoffDisplay = Int(backoffSeconds)
        self.lastError = "Rate limited. Retrying in \(backoffDisplay)s."
    }

    // MARK: - Summary Building

    private func buildSummary(from response: UsageAPIResponse) -> UsageSummary {
        let fiveHour = WindowSummary(
            percentage: min((response.fiveHour?.utilization ?? 0) / 100.0, 1.0),
            resetsAt: parseISO8601(response.fiveHour?.resetsAt)
        )

        let weekly = WindowSummary(
            percentage: min((response.sevenDay?.utilization ?? 0) / 100.0, 1.0),
            resetsAt: parseISO8601(response.sevenDay?.resetsAt)
        )

        let weeklyOpus: WindowSummary? = if let opus = response.sevenDayOpus {
            WindowSummary(
                percentage: min(opus.utilization / 100.0, 1.0),
                resetsAt: parseISO8601(opus.resetsAt)
            )
        } else {
            nil
        }

        let weeklySonnet: WindowSummary? = if let sonnet = response.sevenDaySonnet {
            WindowSummary(
                percentage: min(sonnet.utilization / 100.0, 1.0),
                resetsAt: parseISO8601(sonnet.resetsAt)
            )
        } else {
            nil
        }

        return UsageSummary(
            fiveHour: fiveHour,
            weekly: weekly,
            weeklyOpus: weeklyOpus,
            weeklySonnet: weeklySonnet,
            lastUpdated: Date()
        )
    }

    // MARK: - Disk Cache

    private func saveSummaryToCache(_ response: UsageAPIResponse) {
        if let data = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cacheTimestampKey)
        }
    }

    private func loadCachedSummary() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return }
        guard let response = try? JSONDecoder().decode(UsageAPIResponse.self, from: data) else { return }

        let cachedTimestamp = UserDefaults.standard.double(forKey: Self.cacheTimestampKey)
        let cachedDate = Date(timeIntervalSince1970: cachedTimestamp)

        self.summary = UsageSummary(
            fiveHour: WindowSummary(
                percentage: min((response.fiveHour?.utilization ?? 0) / 100.0, 1.0),
                resetsAt: parseISO8601(response.fiveHour?.resetsAt)
            ),
            weekly: WindowSummary(
                percentage: min((response.sevenDay?.utilization ?? 0) / 100.0, 1.0),
                resetsAt: parseISO8601(response.sevenDay?.resetsAt)
            ),
            weeklyOpus: response.sevenDayOpus.map {
                WindowSummary(percentage: min($0.utilization / 100.0, 1.0), resetsAt: parseISO8601($0.resetsAt))
            },
            weeklySonnet: response.sevenDaySonnet.map {
                WindowSummary(percentage: min($0.utilization / 100.0, 1.0), resetsAt: parseISO8601($0.resetsAt))
            },
            lastUpdated: cachedDate
        )
        self.isCachedData = true
    }

    // MARK: - Helpers

    private func parseISO8601(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "Missing field '\(key.stringValue)' in API response."
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for '\(path)': expected \(type)."
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Null value for '\(path)': expected \(type)."
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Corrupted data at '\(path)': \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func setupTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval.rawValue, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recalculate()
            }
        }
    }

    private func setupFileWatcher() {
        fileWatcher?.stop()
        fileWatcher = FileWatcher { [weak self] in
            self?.debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.recalculate()
                }
            }
            self?.debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
        }
        fileWatcher?.start()
    }
}
