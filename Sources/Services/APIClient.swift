import Foundation

struct UsageAPIResponse: Codable {
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

    struct WindowData: Codable {
        let utilization: Double // 0-100
        let resetsAt: String? // ISO 8601

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.utilization = try container.decodeIfPresent(Double.self, forKey: .utilization) ?? 0
            self.resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(utilization, forKey: .utilization)
            try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
        }
    }
}

final class APIClient {
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct OAuthCredentials: Codable {
        var claudeAiOauth: OAuthToken

        struct OAuthToken: Codable {
            var accessToken: String
            var refreshToken: String
            var expiresAt: Int64
            var scopes: [String]
        }
    }

    func fetchUsage() async throws -> UsageAPIResponse {
        let token = try getAccessToken()

        var request = URLRequest(url: usageURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { TimeInterval($0) }
            throw APIError.rateLimited(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw APIError.emptyResponse
        }

        do {
            return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
        } catch {
            if let rawString = String(data: data, encoding: .utf8) {
                print("⚠️ Failed to decode API response. Raw data: \(rawString)")
            }
            throw error
        }
    }

    private func getAccessToken() throws -> String {
        let credentials = try readCredentials()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let bufferMs: Int64 = 60_000
        if credentials.claudeAiOauth.expiresAt - bufferMs <= nowMs {
            throw APIError.tokenExpired
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

        do {
            return try JSONDecoder().decode(OAuthCredentials.self, from: Data(json.utf8))
        } catch {
            print("⚠️ Failed to decode credentials from Keychain. Raw data: \(json)")
            throw APIError.corruptedCredentials
        }
    }

    enum APIError: LocalizedError {
        case noCredentials
        case corruptedCredentials
        case invalidResponse
        case emptyResponse
        case httpError(Int)
        case rateLimited(retryAfter: TimeInterval?)
        case tokenExpired

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "No Claude Code credentials found in Keychain. Run 'claude' in terminal first."
            case .corruptedCredentials:
                return "Claude Code credentials are corrupted. Run 'claude' in terminal to re-authenticate."
            case .invalidResponse:
                return "Invalid response from API."
            case .emptyResponse:
                return "API returned empty response. Please try again later."
            case .httpError(401), .httpError(403):
                return "Authentication failed. Run 'claude' in terminal to refresh your credentials."
            case .httpError(429):
                return "Rate limited. Try again in a moment."
            case .httpError(let code):
                return "HTTP error \(code). Please try again later."
            case .rateLimited(let retryAfter):
                if let seconds = retryAfter, seconds > 0 {
                    return "Rate limited. Retrying in \(Int(seconds))s."
                }
                return "Rate limited. Try again in a moment."
            case .tokenExpired:
                return "Token expired — use Claude Code to refresh."
            }
        }
    }
}
