import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var calculator: UsageCalculator
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                SettingsView(
                    calculator: calculator,
                    updateChecker: updateChecker,
                    onDone: { showSettings = false }
                )
            } else {
                mainContent
            }
        }
        // MenuBarExtra keeps this view alive between openings, so onAppear only
        // fires the first time. Refresh every time the popover window is shown.
        .background(WindowShownObserver {
            calculator.recalculate()
        })
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if let status = calculator.tokenStatus {
                tokenStatusBanner(status)
            }

            if let summary = calculator.summary {
                weeklySection(summary)

                if !summary.scopedLimits.isEmpty || summary.fiveHour != nil {
                    Divider()
                    limitsSection(summary)
                }

                if !summary.breakdown.isEmpty {
                    Divider()
                    breakdownSection(summary.breakdown)
                }

                if let spend = summary.spend {
                    Divider()
                    spendSection(spend)
                }

                Divider()
                footerInfo(summary)
            } else if calculator.isLoading {
                ProgressView("Fetching usage...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let error = calculator.lastError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            }

            HStack {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    calculator.recalculate(force: true)
                } label: {
                    HStack(spacing: 4) {
                        if calculator.isLoading {
                            TimelineView(.animation) { context in
                                Image(systemName: "arrow.clockwise")
                                    .rotationEffect(.degrees(
                                        context.date.timeIntervalSinceReferenceDate
                                            .truncatingRemainder(dividingBy: 1.0) * 360
                                    ))
                            }
                            .transition(.identity)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .transition(.identity)
                        }
                        Text("Refresh")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkle")
                .foregroundStyle(UsageStyle.accent)
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if let update = updateChecker.updateAvailable {
                Button {
                    NSWorkspace.shared.open(update.url)
                } label: {
                    Text("v\(update.version)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(UsageStyle.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Update available - click to download")
            }
        }
    }

    // MARK: - Weekly (primary limit)

    private func weeklySection(_ summary: UsageSummary) -> some View {
        let weekly = summary.weekly
        let color = UsageStyle.color(for: weekly)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly limit")
                        .font(.subheadline.bold())
                    if let resetStr = weekly.resetsInFormatted {
                        Text("Resets in \(resetStr)\(resetDayText(weekly.resetsAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(Int((weekly.percentage * 100).rounded()))%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            paceBar(percentage: weekly.percentage, elapsed: summary.weekElapsed, color: color)

            paceCaption(weekly: weekly, elapsed: summary.weekElapsed)
        }
    }

    private func paceBar(percentage: Double, elapsed: Double?, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(width: max(0, geo.size.width * percentage))
                if let elapsed {
                    // Where usage "should" be if spread evenly across the week.
                    Rectangle()
                        .fill(.primary.opacity(0.55))
                        .frame(width: 2, height: 18)
                        .offset(x: min(max(geo.size.width * elapsed - 1, 0), geo.size.width - 2))
                }
            }
        }
        .frame(height: 12)
        .help("Marker shows how much of the week has passed")
    }

    @ViewBuilder
    private func paceCaption(weekly: WindowSummary, elapsed: Double?) -> some View {
        let remaining = Int((weekly.remaining * 100).rounded())
        HStack(spacing: 4) {
            if let elapsed {
                let diff = weekly.percentage - elapsed
                Image(systemName: diff > 0.05 ? "hare.fill" : "tortoise.fill")
                    .foregroundStyle(diff > 0.05 ? Color.orange : Color.secondary)
                Text(diff > 0.05
                     ? "Ahead of pace · \(Int((elapsed * 100).rounded()))% of week elapsed"
                     : "On pace · \(Int((elapsed * 100).rounded()))% of week elapsed")
            }
            Spacer()
            Text("\(remaining)% left")
                .bold()
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        if let perDay = dailyBudget(weekly: weekly) {
            Text("≈ \(perDay)% per day for the rest of the week")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func dailyBudget(weekly: WindowSummary) -> Int? {
        guard let resetsAt = weekly.resetsAt else { return nil }
        let daysLeft = resetsAt.timeIntervalSinceNow / 86400
        guard daysLeft >= 1 else { return nil }
        return Int((weekly.remaining * 100 / daysLeft).rounded())
    }

    private func resetDayText(_ date: Date?) -> String {
        guard let date else { return "" }
        return " · " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    // MARK: - Model caps & session window

    private func limitsSection(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Limits")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(summary.scopedLimits) { limit in
                limitRow(
                    name: limit.name,
                    window: limit.window,
                    help: limit.allowanceOfWeekly.map {
                        "\(limit.name) can use up to \(Int(($0 * 100).rounded()))% of your weekly limit"
                    }
                )
            }

            if let fiveHour = summary.fiveHour {
                limitRow(name: "5-hour", window: fiveHour, help: fiveHour.resetsInFormatted.map { "Resets in \($0)" })
            }
        }
    }

    private func limitRow(name: String, window: WindowSummary, help: String?) -> some View {
        let color = UsageStyle.color(for: window)
        return HStack(spacing: 8) {
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * window.percentage))
                }
            }
            .frame(height: 6)

            Text("\(Int((window.percentage * 100).rounded()))%")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 36, alignment: .trailing)
        }
        .help(help ?? "")
    }

    // MARK: - Where usage went

    private func breakdownSection(_ shares: [UsageShare]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This week by app")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        Rectangle()
                            .fill(UsageStyle.segmentColor(index))
                            .frame(width: max(2, (geo.size.width - CGFloat(shares.count - 1) * 2) * share.share))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 6)

            HStack(spacing: 10) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(UsageStyle.segmentColor(index))
                            .frame(width: 6, height: 6)
                        Text("\(share.name) \(Int((share.share * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Extra usage

    private func spendSection(_ spend: SpendSummary) -> some View {
        HStack {
            Label("Extra usage", systemImage: "creditcard")
                .font(.caption)
            Spacer()
            Text(spend.limit.map { "\(spend.used) / \($0)" } ?? spend.used)
                .font(.caption.bold())
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private func footerInfo(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = calculator.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let age = context.date.timeIntervalSince(summary.lastUpdated)
                HStack(spacing: 4) {
                    Text("Updated: \(summary.lastUpdated.formatted(.dateTime.hour().minute().second()))")
                    if age >= 10 * 60 {
                        Text("(\(Int(age / 60)) min ago)")
                            .foregroundStyle(.orange)
                    } else if calculator.isCachedData {
                        Text("(Cached)")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func tokenStatusBanner(_ status: UsageCalculator.TokenStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "key.fill")
                .font(.caption2)
            Text(status.message)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

enum UsageStyle {
    /// Claude's coral accent.
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    static func color(for window: WindowSummary) -> Color {
        switch window.severity?.lowercased() {
        case "critical", "exceeded", "blocked", "limited":
            return .red
        case "warning", "elevated", "high":
            return window.percentage >= 0.8 ? .red : .orange
        default:
            return color(for: window.percentage)
        }
    }

    static func color(for p: Double) -> Color {
        if p >= 0.8 { return .red }
        if p >= 0.5 { return .orange }
        return .green
    }

    static func segmentColor(_ index: Int) -> Color {
        let palette: [Color] = [accent, .blue, .teal, .purple, .gray]
        return palette[index % palette.count]
    }
}

/// Calls `onShow` each time the hosting window becomes key, i.e. each time the
/// menu bar popover is opened.
private struct WindowShownObserver: NSViewRepresentable {
    let onShow: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onShow = onShow
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onShow = onShow
    }

    final class ObserverView: NSView {
        var onShow: (() -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onShow?()
            }
            if window.isKeyWindow || window.isVisible { onShow?() }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
