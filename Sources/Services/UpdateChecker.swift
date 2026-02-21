import Foundation

struct UpdateInfo {
    let version: String
    let url: URL
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var updateAvailable: UpdateInfo?

    private let repo = "Dann1y/claude-usage-monitor"
    private let checkInterval: TimeInterval = 86400 // 24 hours
    private let lastCheckKey = "lastUpdateCheck"
    private let dismissedVersionKey = "dismissedUpdateVersion"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    func checkForUpdates(force: Bool = false) {
        if !force {
            let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
            if lastCheck > 0, Date().timeIntervalSince1970 - lastCheck < checkInterval {
                return
            }
        }

        Task {
            await performCheck()
        }
    }

    private func performCheck() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            if isNewer(latestVersion, than: currentVersion) {
                let dismissed = UserDefaults.standard.string(forKey: dismissedVersionKey)
                if dismissed != latestVersion {
                    self.updateAvailable = UpdateInfo(
                        version: latestVersion,
                        url: release.htmlURL
                    )
                }
            } else {
                self.updateAvailable = nil
            }
        } catch {
            // Silently ignore - update check is best-effort
        }
    }

    func dismissUpdate() {
        if let version = updateAvailable?.version {
            UserDefaults.standard.set(version, forKey: dismissedVersionKey)
        }
        updateAvailable = nil
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
