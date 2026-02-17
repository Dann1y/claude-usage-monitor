import Foundation

struct UsageAPIResponse: Decodable {
    let fiveHour: WindowData?
    let sevenDay: WindowData?
    let sevenDayOpus: WindowData?
    let sevenDaySonnet: WindowData?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    struct WindowData: Decodable {
        let utilization: Double // 0-100
        let resetsAt: String // ISO 8601

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}

final class APIClient {
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let refreshURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private let clientId = "b8a4d0e0-e773-4ad3-9fdd-a6949e1d9e1c"

    struct OAuthCredentials: Codable {
        var claudeAiOauth: OAuthToken

        struct OAuthToken: Codable {
            var accessToken: String
            var refreshToken: String
            var expiresAt: Int64
            var scopes: [String]
        }
    }

    private struct TokenRefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    func fetchUsage() async throws -> UsageAPIResponse {
        let token = try await getAccessToken()

        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
    }

    private func getAccessToken() async throws -> String {
        var credentials = try readCredentials()

        let now = Int64(Date().timeIntervalSince1970)
        let bufferSeconds: Int64 = 60
        if credentials.claudeAiOauth.expiresAt - bufferSeconds <= now {
            credentials = try await refreshAccessToken(credentials)
        }

        return credentials.claudeAiOauth.accessToken
    }

    private func readCredentials() throws -> OAuthCredentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw APIError.noCredentials
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty else {
            throw APIError.noCredentials
        }

        return try JSONDecoder().decode(OAuthCredentials.self, from: Data(json.utf8))
    }

    private func refreshAccessToken(_ credentials: OAuthCredentials) async throws -> OAuthCredentials {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": credentials.claudeAiOauth.refreshToken,
            "client_id": clientId,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

        var updated = credentials
        updated.claudeAiOauth.accessToken = tokenResponse.accessToken
        updated.claudeAiOauth.expiresAt = Int64(Date().timeIntervalSince1970) + Int64(tokenResponse.expiresIn)
        if let newRefresh = tokenResponse.refreshToken {
            updated.claudeAiOauth.refreshToken = newRefresh
        }

        try saveCredentials(updated)
        return updated
    }

    private func saveCredentials(_ credentials: OAuthCredentials) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        guard let json = String(data: data, encoding: .utf8) else { return }

        let deleteProcess = Process()
        deleteProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        deleteProcess.arguments = ["delete-generic-password", "-s", "Claude Code-credentials"]
        deleteProcess.standardOutput = Pipe()
        deleteProcess.standardError = Pipe()
        try? deleteProcess.run()
        deleteProcess.waitUntilExit()

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        addProcess.arguments = ["add-generic-password", "-s", "Claude Code-credentials", "-w", json]
        addProcess.standardOutput = Pipe()
        addProcess.standardError = Pipe()
        try addProcess.run()
        addProcess.waitUntilExit()

        guard addProcess.terminationStatus == 0 else {
            throw APIError.keychainWriteFailed
        }
    }

    enum APIError: LocalizedError {
        case noCredentials
        case invalidResponse
        case httpError(Int)
        case tokenRefreshFailed
        case keychainWriteFailed

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "No Claude Code credentials found in Keychain. Run 'claude' in terminal first."
            case .invalidResponse:
                return "Invalid response from API."
            case .httpError(401):
                return "Authentication failed. Run 'claude' in terminal to refresh your credentials."
            case .httpError(403):
                return "Access denied. Check your Claude subscription status."
            case .httpError(429):
                return "Rate limited. Try again in a moment."
            case .httpError(let code):
                return "HTTP error \(code). Please try again later."
            case .tokenRefreshFailed:
                return "Failed to refresh token. Run 'claude' in terminal to re-authenticate."
            case .keychainWriteFailed:
                return "Failed to update credentials in Keychain."
            }
        }
    }
}
