import Foundation

struct WindowSummary {
    let percentage: Double // 0.0 ~ 1.0
    let resetsAt: Date?
    let totalMessages: Int // from local JSONL (supplementary)

    var resetsInFormatted: String? {
        guard let resetsAt = resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSinceNow
        guard seconds > 0 else { return nil }

        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct UsageSummary {
    let fiveHour: WindowSummary
    let weekly: WindowSummary
    let weeklyOpus: WindowSummary?
    let weeklySonnet: WindowSummary?
    let lastUpdated: Date
    let source: DataSource

    enum DataSource: String {
        case api = "API"
        case local = "Local"
    }
}

enum RefreshInterval: Double, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .fifteen: return "15 seconds"
        case .thirty: return "30 seconds"
        case .sixty: return "1 minute"
        }
    }
}
