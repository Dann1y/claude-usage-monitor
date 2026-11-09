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
    private var currentTask: Task<Void, Never>?

    // On-demand protection: skip if last fetch was within 30 seconds
    private var lastFetchTime: Date?
    private let onDemandCooldown: TimeInterval = 30

    // Fixed 30-minute background refresh interval
    private let backgroundInterval: TimeInterval = 30 * 60

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
            } catch let apiError as APIClient.APIError {
                guard !Task.isCancelled else { return }

                switch apiError {
                case .tokenRefreshFailed:
                    self.handleTokenIssue(.expired)
                case .httpError(401), .httpError(403):
                    self.handleTokenIssue(.authFailed)
                case .rateLimited:
                    // With 30-min intervals, just wait for next cycle
                    if self.summary != nil {
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

    private func setupTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: backgroundInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recalculate()
            }
        }
    }
}
