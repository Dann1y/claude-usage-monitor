import Foundation
import Combine

@MainActor
final class UsageCalculator: ObservableObject {
    @Published var summary: UsageSummary?
    @Published var isLoading = false
    @Published var lastError: String?

    private let apiClient = APIClient()
    private var refreshTimer: Timer?
    private var fileWatcher: FileWatcher?
    private var debounceWorkItem: DispatchWorkItem?
    private var currentTask: Task<Void, Never>?

    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            setupTimer()
        }
    }

    init() {
        self.refreshInterval = RefreshInterval(rawValue: UserDefaults.standard.double(forKey: "refreshInterval")) ?? .thirty
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

    func recalculate() {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        currentTask?.cancel()
        currentTask = Task {
            do {
                let response = try await apiClient.fetchUsage()

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

                self.summary = UsageSummary(
                    fiveHour: fiveHour,
                    weekly: weekly,
                    weeklyOpus: weeklyOpus,
                    weeklySonnet: weeklySonnet,
                    lastUpdated: Date()
                )
                self.isLoading = false
            } catch {
                self.lastError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func parseISO8601(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
        }
        fileWatcher?.start()
    }
}
