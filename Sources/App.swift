import SwiftUI

@main
struct ClaudeUsageMonitorApp: App {
    @StateObject private var calculator = UsageCalculator()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(calculator: calculator, updateChecker: updateChecker)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "cloud.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(menuBarColor)

            if let summary = calculator.summary {
                Text("\(Int(summary.fiveHour.percentage * 100))%")
                    .monospacedDigit()
            } else {
                Text("--")
            }
        }
        .onAppear {
            calculator.start()
            updateChecker.checkForUpdates()
        }
    }

    private var menuBarColor: Color {
        guard let summary = calculator.summary else { return .secondary }
        let p = summary.fiveHour.percentage
        if p >= 0.8 { return .red }
        if p >= 0.5 { return .orange }
        return .green
    }
}
