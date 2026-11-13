import Foundation
import Combine

@MainActor
final class UsageCalculator: ObservableObject {
    @Published var summary: UsageSummary?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var tokenStatus: TokenStatus?
    @Published var isCachedData = false

    enum TokenStatus {
        case expired
        case authFailed

        var message: String {
            switch self {
            case .expired:
                return "Couldn't refresh token — sign in to Claude Code"
            case .authFailed:
                return "Auth failed — sign in to Claude Code"
            }
        }
    }

    private let apiClient = APIClient()
    private var refreshTimer: Timer?
    private var followUpTimer: Timer?
    private var currentTask: Task<Void, Never>?

    // On-demand protection: skip if last fetch was within 15 seconds
    private var lastFetchTime: Date?
    private let onDemandCooldown: TimeInterval = 15

    // Background refresh. Weekly limits move fast near the cap and can be
    // reset at any time from Claude's settings, so poll every few minutes.
    private let backgroundInterval: TimeInterval = 5 * 60

    // Disk cache keys
    private static let cacheKey = "cachedUsageResponse"
    private static let cacheTimestampKey = "cachedUsageTimestamp"

    init() {
        loadCachedSummary()
    }

    func start() {
        recalculate()
        setupTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        followUpTimer?.invalidate()
        followUpTimer = nil
        currentTask?.cancel()
        currentTask = nil
    }

    func recalculate(force: Bool = false) {
        // On-demand protection: skip if too soon (unless forced by manual refresh button)
        if !force, let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < onDemandCooldown {
            return
        }

        currentTask?.cancel()
        isLoading = true
        lastError = nil

        currentTask = Task {
            do {
                self.lastFetchTime = Date()
                let response = try await apiClient.fetchUsage()
                guard !Task.isCancelled else { return }

                self.tokenStatus = nil
                self.isCachedData = false

                let newSummary = UsageSummary(response: response, lastUpdated: Date())
                self.summary = newSummary
                self.saveSummaryToCache(response)
                self.isLoading = false
                self.scheduleFollowUp(at: newSummary.weekly.resetsAt.map { $0.addingTimeInterval(15) })
            } catch let apiError as APIClient.APIError {
                guard !Task.isCancelled else { return }

                switch apiError {
                case .tokenRefreshFailed:
                    self.handleTokenIssue(.expired)
                case .httpError(401), .httpError(403):
                    self.handleTokenIssue(.authFailed)
                case .rateLimited(let retryAfter):
                    // Say so instead of silently showing old numbers, and try again soon.
                    let delay = min(max(retryAfter ?? 60, 30), self.backgroundInterval)
                    self.lastError = "Rate limited — retrying in \(Int(delay))s"
                    self.scheduleFollowUp(at: Date().addingTimeInterval(delay))
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
        if self.summary != nil {
            self.isCachedData = true
            self.lastError = nil
        } else {
            self.lastError = status.message
        }
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

        self.summary = UsageSummary(response: response, lastUpdated: cachedDate)
        self.isCachedData = true
    }

    // MARK: - Helpers

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

    /// One-shot refresh: right after the weekly window resets, or after a rate-limit back-off.
    /// Only the earliest pending follow-up is kept.
    private func scheduleFollowUp(at date: Date?) {
        guard let date, date > Date(), date.timeIntervalSinceNow < backgroundInterval * 2 else { return }
        if let pending = followUpTimer?.fireDate, pending > Date(), pending <= date { return }
        followUpTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.followUpTimer = nil
                self?.recalculate(force: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        followUpTimer = timer
    }

    private func setupTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: backgroundInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recalculate()
            }
        }
    }
}
