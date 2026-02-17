import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var calculator: UsageCalculator
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if let summary = calculator.summary {
                fiveHourSection(summary.fiveHour)
                Divider()
                weeklySection(summary)
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
                    showSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    calculator.recalculate()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
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
        .sheet(isPresented: $showSettings) {
            SettingsView(calculator: calculator)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "cloud.fill")
                .foregroundStyle(.blue)
            Text("Claude Usage Monitor")
                .font(.headline)
            Spacer()
        }
    }

    private func fiveHourSection(_ window: WindowSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("5-Hour Window", systemImage: "clock")
                    .font(.subheadline.bold())
                Spacer()
                if let resetStr = window.resetsInFormatted {
                    Text("resets in \(resetStr)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            usageBar(percentage: window.percentage)
        }
    }

    private func weeklySection(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Weekly", systemImage: "calendar")
                    .font(.subheadline.bold())
                Spacer()
                if let resetStr = summary.weekly.resetsInFormatted {
                    Text("resets in \(resetStr)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            usageBar(percentage: summary.weekly.percentage)

            // Model-specific breakdowns
            VStack(alignment: .leading, spacing: 4) {
                if let opus = summary.weeklyOpus {
                    modelWeeklyRow(name: "Opus", window: opus)
                }
                if let sonnet = summary.weeklySonnet {
                    modelWeeklyRow(name: "Sonnet", window: sonnet)
                }
            }
        }
    }

    private func modelWeeklyRow(name: String, window: WindowSummary) -> some View {
        HStack(spacing: 6) {
            Text("\(name):")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorForPercentage(window.percentage))
                        .frame(width: max(0, geo.size.width * window.percentage))
                }
            }
            .frame(height: 8)

            Text("\(Int(window.percentage * 100))%")
                .font(.caption.bold())
                .foregroundStyle(colorForPercentage(window.percentage))
                .frame(width: 35, alignment: .trailing)
        }
    }

    private func usageBar(percentage: Double) -> some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorForPercentage(percentage))
                        .frame(width: max(0, geo.size.width * percentage))
                }
            }
            .frame(height: 12)

            HStack {
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(colorForPercentage(percentage))
            }
        }
    }

    private func footerInfo(_ summary: UsageSummary) -> some View {
        HStack {
            Text("Updated: \(summary.lastUpdated.formatted(.dateTime.hour().minute().second()))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(summary.source.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private func colorForPercentage(_ p: Double) -> Color {
        if p >= 0.8 { return .red }
        if p >= 0.5 { return .orange }
        return .green
    }
}
