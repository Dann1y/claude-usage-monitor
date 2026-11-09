import Foundation

struct UsageAPIResponse: Codable {
    let fiveHour: WindowData?
    let sevenDay: WindowData?
    let sevenDayOpus: WindowData?
    let sevenDaySonnet: WindowData?
    let sevenDayClaudeDesign: WindowData?
    /// Unified list of plan limits (weekly overall + per-model caps).
    let limits: [LimitData]?
    let weeklyScopedShares: [ScopedShare]?
    /// Where this week's usage went (Claude Code, Chats, Cowork, ...).
    let sevenDayBreakdown: Breakdown?
    let spend: Spend?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        // Claude Design is named "omelette" in the API for historical reasons.
        case sevenDayClaudeDesign = "seven_day_omelette"
        case limits
        case weeklyScopedShares = "weekly_scoped_shares"
        case sevenDayBreakdown = "seven_day_breakdown"
        case spend
    }

    // Every field is decoded leniently: the endpoint is undocumented and keeps
    // growing, so one field changing shape must never break the whole popover.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? c.decodeIfPresent(WindowData.self, forKey: .fiveHour)
        sevenDay = try? c.decodeIfPresent(WindowData.self, forKey: .sevenDay)
        sevenDayOpus = try? c.decodeIfPresent(WindowData.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try? c.decodeIfPresent(WindowData.self, forKey: .sevenDaySonnet)
        sevenDayClaudeDesign = try? c.decodeIfPresent(WindowData.self, forKey: .sevenDayClaudeDesign)
        limits = (try? c.decodeIfPresent([Lossy<LimitData>].self, forKey: .limits))?.compactMap(\.value)
        weeklyScopedShares = (try? c.decodeIfPresent([Lossy<ScopedShare>].self, forKey: .weeklyScopedShares))?.compactMap(\.value)
        sevenDayBreakdown = try? c.decodeIfPresent(Breakdown.self, forKey: .sevenDayBreakdown)
        spend = try? c.decodeIfPresent(Spend.self, forKey: .spend)
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

    struct LimitData: Codable {
        let kind: String?        // "weekly_all", "weekly_scoped", ...
        let group: String?       // "weekly", ...
        let percent: Double?     // 0-100
        let severity: String?    // "normal", ...
        let resetsAt: String?
        let scope: Scope?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case kind, group, percent, severity, scope
            case resetsAt = "resets_at"
            case isActive = "is_active"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try? c.decodeIfPresent(String.self, forKey: .kind)
            group = try? c.decodeIfPresent(String.self, forKey: .group)
            percent = try? c.decodeIfPresent(Double.self, forKey: .percent)
            severity = try? c.decodeIfPresent(String.self, forKey: .severity)
            resetsAt = try? c.decodeIfPresent(String.self, forKey: .resetsAt)
            scope = try? c.decodeIfPresent(Scope.self, forKey: .scope)
            isActive = try? c.decodeIfPresent(Bool.self, forKey: .isActive)
        }

        struct Scope: Codable {
            let model: Named?
            let surface: Named?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                model = try? c.decodeIfPresent(Named.self, forKey: .model)
                surface = try? c.decodeIfPresent(Named.self, forKey: .surface)
            }

            enum CodingKeys: String, CodingKey { case model, surface }
        }

        /// Accepts either a bare string or an object with `display_name` / `id`.
        struct Named: Codable {
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case id
            }

            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer().decode(String.self) {
                    displayName = single
                    return
                }
                let c = try decoder.container(keyedBy: CodingKeys.self)
                displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName))
                    ?? (try? c.decodeIfPresent(String.self, forKey: .id))
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(displayName, forKey: .displayName)
            }
        }
    }

    struct ScopedShare: Codable {
        let limitIndex: Int
        let allowancePercentOfWeekly: Double?

        enum CodingKeys: String, CodingKey {
            case limitIndex = "limit_index"
            case allowancePercentOfWeekly = "allowance_percent_of_weekly"
        }
    }

    struct Breakdown: Codable {
        let windowStartedAt: String?
        let rows: [Row]

        enum CodingKeys: String, CodingKey {
            case windowStartedAt = "window_started_at"
            case rows
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            windowStartedAt = try? c.decodeIfPresent(String.self, forKey: .windowStartedAt)
            rows = (try? c.decodeIfPresent([Lossy<Row>].self, forKey: .rows))?.compactMap(\.value) ?? []
        }

        struct Row: Codable {
            let key: String
            let displayName: String
            let percent: Double

            enum CodingKeys: String, CodingKey {
                case key, percent
                case displayName = "display_name"
            }
        }
    }

    struct Spend: Codable {
        let enabled: Bool?
        let used: Money?
        let limit: Money?
        let percent: Double?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
            used = try? c.decodeIfPresent(Money.self, forKey: .used)
            limit = try? c.decodeIfPresent(Money.self, forKey: .limit)
            percent = try? c.decodeIfPresent(Double.self, forKey: .percent)
        }

        enum CodingKeys: String, CodingKey { case enabled, used, limit, percent }

        struct Money: Codable {
            let amountMinor: Int
            let currency: String
            let exponent: Int

            enum CodingKeys: String, CodingKey {
                case currency, exponent
                case amountMinor = "amount_minor"
            }
        }
    }
}

/// Decodes an element if possible, otherwise yields nil instead of failing the array.
struct Lossy<T: Codable>: Codable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try value?.encode(to: encoder)
    }
}

final class APIClient {
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let keychainService = "Claude Code-credentials"

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
        do {
            return try await performUsageRequest(token: token)
        } catch let error as APIError {
            // Server may invalidate a token before our local expiry check fires
            // (e.g. revoked from another device). Try one transparent refresh.
            if case .httpError(let code) = error, code == 401 || code == 403 {
                let refreshed = try await refreshAndPersist()
                return try await performUsageRequest(token: refreshed.claudeAiOauth.accessToken)
            }
            throw error
        }
    }

    private func performUsageRequest(token: String) async throws -> UsageAPIResponse {
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

    private func getAccessToken() async throws -> String {
        let credentials = try readCredentials()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let bufferMs: Int64 = 60_000
        if credentials.claudeAiOauth.expiresAt - bufferMs <= nowMs {
            // Refresh transparently using the stored refresh_token so the user
            // doesn't have to keep `claude` running in a terminal just to keep
            // the access token alive when they use Claude Desktop instead.
            let refreshed = try await refreshAndPersist()
            return refreshed.claudeAiOauth.accessToken
        }

        return credentials.claudeAiOauth.accessToken
    }

    // MARK: - Keychain

    private func readCredentials() throws -> OAuthCredentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

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

    /// Read the keychain item's account name so the rewrite uses the same
    /// (service, account) tuple — otherwise `add-generic-password -U` would
    /// create a duplicate entry instead of updating the existing one.
    private func readCredentialsAccount() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return NSUserName()
        }

        guard process.terminationStatus == 0 else { return NSUserName() }

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        // Output contains a line like:  "acct"<blob>="danny"
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\"acct\"") else { continue }
            if let range = line.range(of: #"="[^"]+""#, options: .regularExpression) {
                let match = line[range]
                let value = match.dropFirst(2).dropLast()
                return String(value)
            }
        }
        return NSUserName()
    }

    private func saveCredentials(_ credentials: OAuthCredentials, account: String) throws {
        let data = try JSONEncoder().encode(credentials)
        guard let json = String(data: data, encoding: .utf8) else {
            throw APIError.keychainWriteFailed
        }

        // -U updates the (service, account) item in place if it exists, or
        // creates it otherwise. This is atomic — there is no window where the
        // item is missing, so the Claude Code CLI never sees the entry vanish
        // mid-rotation (which is what caused the earlier "logout" regression).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password",
            "-U",
            "-s", keychainService,
            "-a", account,
            "-w", json,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw APIError.keychainWriteFailed
        }
    }

    // MARK: - Token refresh

    private func refreshAndPersist() async throws -> OAuthCredentials {
        let credentials = try readCredentials()
        let account = readCredentialsAccount()
        let refreshed = try await refreshAccessToken(credentials)
        try saveCredentials(refreshed, account: account)
        return refreshed
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

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                print("⚠️ Token refresh failed: \(raw)")
            }
            throw APIError.tokenRefreshFailed
        }

        let tokenResponse: TokenRefreshResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
        } catch {
            throw APIError.tokenRefreshFailed
        }

        var updated = credentials
        updated.claudeAiOauth.accessToken = tokenResponse.accessToken
        updated.claudeAiOauth.expiresAt =
            Int64(Date().timeIntervalSince1970 * 1000) + Int64(tokenResponse.expiresIn) * 1000
        if let newRefresh = tokenResponse.refreshToken {
            updated.claudeAiOauth.refreshToken = newRefresh
        }
        return updated
    }

    enum APIError: LocalizedError {
        case noCredentials
        case corruptedCredentials
        case invalidResponse
        case emptyResponse
        case httpError(Int)
        case rateLimited(retryAfter: TimeInterval?)
        case tokenRefreshFailed
        case keychainWriteFailed

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
                return "Authentication failed. Sign in to Claude Code (terminal or Desktop) to refresh."
            case .httpError(429):
                return "Rate limited. Try again in a moment."
            case .httpError(let code):
                return "HTTP error \(code). Please try again later."
            case .rateLimited(let retryAfter):
                if let seconds = retryAfter, seconds > 0 {
                    return "Rate limited. Retrying in \(Int(seconds))s."
                }
                return "Rate limited. Try again in a moment."
            case .tokenRefreshFailed:
                return "Couldn't refresh credentials. Sign in to Claude Code to re-authenticate."
            case .keychainWriteFailed:
                return "Failed to update credentials in Keychain."
            }
        }
    }
}
