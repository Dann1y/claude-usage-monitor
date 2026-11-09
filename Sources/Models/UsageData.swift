import Foundation

struct WindowSummary {
    let percentage: Double // 0.0 ~ 1.0
    let resetsAt: Date?
    var severity: String? = nil

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

    var remaining: Double { max(0, 1 - percentage) }
}

/// A per-model (or per-surface) cap inside the weekly limit, e.g. "Fable".
struct ScopedLimit: Identifiable {
    let id: String
    let name: String
    let window: WindowSummary
    /// How much of the overall weekly limit this scope may use (0.0 ~ 1.0), if known.
    let allowanceOfWeekly: Double?
}

/// Share of this week's usage that came from one surface (Claude Code, Chats, ...).
struct UsageShare: Identifiable {
    let id: String
    let name: String
    let share: Double // 0.0 ~ 1.0
}

struct SpendSummary {
    let used: String
    let limit: String?
    let percentage: Double?
}

struct UsageSummary {
    let weekly: WindowSummary
    let weekStartedAt: Date?
    let fiveHour: WindowSummary?
    let scopedLimits: [ScopedLimit]
    let breakdown: [UsageShare]
    let spend: SpendSummary?
    let lastUpdated: Date

    /// Fraction of the current weekly window that has elapsed (0.0 ~ 1.0).
    var weekElapsed: Double? {
        guard let end = weekly.resetsAt else { return nil }
        let start = weekStartedAt ?? end.addingTimeInterval(-7 * 86400)
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return nil }
        return min(max(Date().timeIntervalSince(start) / total, 0), 1)
    }
}

// MARK: - Building from the API response

extension UsageSummary {
    init(response: UsageAPIResponse, lastUpdated: Date) {
        let limits = response.limits ?? []
        let weeklyAll = limits.first { $0.kind == "weekly_all" }

        if let weeklyAll {
            weekly = WindowSummary(
                percentage: Self.fraction(weeklyAll.percent),
                resetsAt: Self.parseISO8601(weeklyAll.resetsAt),
                severity: weeklyAll.severity
            )
        } else {
            weekly = WindowSummary(
                percentage: Self.fraction(response.sevenDay?.utilization),
                resetsAt: Self.parseISO8601(response.sevenDay?.resetsAt)
            )
        }

        weekStartedAt = Self.parseISO8601(response.sevenDayBreakdown?.windowStartedAt)

        // The 5-hour window is gone for most plans (API returns null); only show it if present.
        fiveHour = response.fiveHour.map {
            WindowSummary(percentage: Self.fraction($0.utilization), resetsAt: Self.parseISO8601($0.resetsAt))
        }

        var scoped: [ScopedLimit] = []
        for (index, limit) in limits.enumerated() where limit.kind != "weekly_all" && limit.group == "weekly" {
            let name = limit.scope?.model?.displayName
                ?? limit.scope?.surface?.displayName
                ?? limit.kind?.replacingOccurrences(of: "_", with: " ").capitalized
                ?? "Scoped"
            let allowance = response.weeklyScopedShares?
                .first { $0.limitIndex == index }?
                .allowancePercentOfWeekly
                .map { $0 / 100 }
            scoped.append(ScopedLimit(
                id: "\(index)-\(name)",
                name: name,
                window: WindowSummary(
                    percentage: Self.fraction(limit.percent),
                    resetsAt: Self.parseISO8601(limit.resetsAt),
                    severity: limit.severity
                ),
                allowanceOfWeekly: allowance
            ))
        }

        // Older API responses: fall back to the legacy per-model fields.
        if response.limits == nil {
            let legacy: [(String, UsageAPIResponse.WindowData?)] = [
                ("Opus", response.sevenDayOpus),
                ("Sonnet", response.sevenDaySonnet),
                ("Design", response.sevenDayClaudeDesign),
            ]
            for (name, data) in legacy {
                guard let data else { continue }
                scoped.append(ScopedLimit(
                    id: name,
                    name: name,
                    window: WindowSummary(
                        percentage: Self.fraction(data.utilization),
                        resetsAt: Self.parseISO8601(data.resetsAt)
                    ),
                    allowanceOfWeekly: nil
                ))
            }
        }
        scopedLimits = scoped

        breakdown = (response.sevenDayBreakdown?.rows ?? [])
            .filter { $0.percent > 0 }
            .sorted { $0.percent > $1.percent }
            .map { UsageShare(id: $0.key, name: $0.displayName, share: Self.fraction($0.percent)) }

        if let spend = response.spend, spend.enabled == true, let used = spend.used {
            self.spend = SpendSummary(
                used: Self.formatMoney(used),
                limit: spend.limit.map(Self.formatMoney),
                percentage: spend.percent.map { Self.fraction($0) }
            )
        } else {
            spend = nil
        }

        self.lastUpdated = lastUpdated
    }

    private static func fraction(_ percent: Double?) -> Double {
        min(max((percent ?? 0) / 100.0, 0), 1)
    }

    private static func formatMoney(_ money: UsageAPIResponse.Spend.Money) -> String {
        let amount = Double(money.amountMinor) / pow(10, Double(money.exponent))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currency
        formatter.maximumFractionDigits = money.exponent
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(money.currency)"
    }

    static func parseISO8601(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: str) { return date }
        // The API sends microseconds (".102189"), which some macOS versions reject.
        let trimmed = str.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return formatter.date(from: trimmed)
    }
}
