import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var calculator: UsageCalculator
    @ObservedObject var updateChecker: UpdateChecker
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.bold())

            // Refresh Interval
            GroupBox("Refresh") {
                Picker("Interval", selection: $calculator.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .padding(4)
            }

            // Launch at Login
            GroupBox("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
                    .padding(4)
            }

            // Info
            GroupBox("Data Source") {
                Text("Usage data is fetched from Anthropic's OAuth API using your Claude Code credentials stored in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(4)
            }

            GroupBox("About") {
                VStack(spacing: 6) {
                    HStack {
                        Text("Version")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(updateChecker.currentVersion)
                            .font(.caption)
                    }
                    .padding(4)

                    if let update = updateChecker.updateAvailable {
                        HStack {
                            Text("Update available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Link("v\(update.version)", destination: update.url)
                                .font(.caption)
                        }
                        .padding(4)
                    }

                    HStack {
                        Text("GitHub")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link("claude-usage-monitor", destination: URL(string: "https://github.com/Dann1y/claude-usage-monitor")!)
                            .font(.caption)
                    }
                    .padding(4)
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
