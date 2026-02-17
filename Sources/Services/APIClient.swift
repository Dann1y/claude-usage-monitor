import Foundation

struct UsageAPIResponse: Decodable {
    let fiveHour: WindowData?
    let sevenDay: WindowData?
    let sevenDayOpus: WindowData?
    let sevenDaySonnet: WindowData?
    let extraUsage: ExtraUsageData?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }

    struct WindowData: Decodable {
        let utilization: Double // 0-100
        let resetsAt: String // ISO 8601

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct ExtraUsageData: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
        }
    }
}

final class APIClient {
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct OAuthCredentials: Decodable {
        let claudeAiOauth: OAuthToken

        struct OAuthToken: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Int64
            let scopes: [String]
        }
    }

    func fetchUsage() async throws -> UsageAPIResponse {
        let token = try getAccessToken()

        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
    }

    private func getAccessToken() throws -> String {
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

        let credentials = try JSONDecoder().decode(OAuthCredentials.self, from: Data(json.utf8))
        return credentials.claudeAiOauth.accessToken
    }

    enum APIError: LocalizedError {
        case noCredentials
        case invalidResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "No Claude Code credentials found in Keychain. Run 'claude' CLI first."
            case .invalidResponse:
                return "Invalid response from API"
            case .httpError(let code, let body):
                return "HTTP \(code): \(body)"
            }
        }
    }
}
