import Foundation

public struct OpenAIAPISpendProvider: APISpendProvider {
    public let id = ProviderID.codex
    public let displayName = "OpenAI API"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://api.openai.com/v1/organization/costs")!

    public init(
        credentials: CredentialStore,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.now = now
    }

    public func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        let range = period.range(now: now())
        switch await credentials.apiKey(for: .openAI) {
        case .failure(let reason):
            return stale(range, reason)
        case .success(let key):
            switch await http.get(url: Self.endpoint.withOpenAICostQuery(range), headers: ["Authorization": "Bearer \(key)"]) {
            case .failure(let reason):
                return stale(range, reason)
            case .success(let result):
                switch result.status {
                case 200:
                    return decode(result.body, range: range)
                case 401:
                    return stale(range, .needsReauth("OpenAI admin key rejected"))
                case 403:
                    return stale(range, .scopeDenied("OpenAI key lacks organization cost access"))
                default:
                    return stale(range, UsageWindowBuilder.genericFailure(for: result.status))
                }
            }
        }
    }

    private func decode(_ body: Data, range: APISpendRange) -> APISpendSnapshot {
        guard let dto = try? JSONDecoder().decode(OpenAICostsDTO.self, from: body),
              let total = CostAccumulator.total(from: dto.data.flatMap(\.results), emptyIsZero: true)
        else { return stale(range, .decode("Couldn't read OpenAI cost response")) }
        return APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: total.amount,
            currency: total.currency,
            periodLabel: range.label,
            capturedAt: now(),
            freshness: .live
        )
    }

    private func stale(_ range: APISpendRange, _ reason: FailureReason) -> APISpendSnapshot {
        .stale(providerID: id, displayName: displayName, periodLabel: range.label, reason: reason)
    }
}

public struct AnthropicAPISpendProvider: APISpendProvider {
    public let id = ProviderID.claude
    public let displayName = "Anthropic API"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://api.anthropic.com/v1/organizations/cost_report")!

    public init(
        credentials: CredentialStore,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.now = now
    }

    public func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        let range = period.range(now: now())
        switch await credentials.apiKey(for: .anthropic) {
        case .failure(let reason):
            return stale(range, reason)
        case .success(let key):
            let headers = [
                "x-api-key": key,
                "anthropic-version": "2023-06-01",
            ]
            return await fetchReport(range: range, headers: headers)
        }
    }

    private func fetchReport(range: APISpendRange, headers: [String: String]) async -> APISpendSnapshot {
        var url = Self.endpoint.withAnthropicCostQuery(range)
        var results: [CostResultDTO] = []
        var seenPageTokens: Set<String> = []

        for _ in 0..<3 {
            guard !Task.isCancelled else {
                return stale(range, .transient("Anthropic cost report cancelled"))
            }
            switch await http.get(url: url, headers: headers) {
            case .failure(let reason):
                return stale(range, reason)
            case .success(let result):
                switch result.status {
                case 200:
                    guard let dto = try? JSONDecoder().decode(AnthropicCostReportDTO.self, from: result.body)
                    else { return stale(range, .decode("Couldn't read Anthropic cost response")) }
                    results.append(contentsOf: dto.data.flatMap(\.results))
                    guard dto.hasMore else {
                        return snapshot(from: results, range: range)
                    }
                    guard let nextPage = dto.nextPage?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !nextPage.isEmpty,
                          seenPageTokens.insert(nextPage).inserted
                    else { return stale(range, .decode("Couldn't read Anthropic cost response")) }
                    url = url.withAnthropicPage(nextPage)
                case 401:
                    return stale(range, .needsReauth("Anthropic admin key rejected"))
                case 403:
                    return stale(range, .scopeDenied("Anthropic key lacks cost report access"))
                default:
                    return stale(range, UsageWindowBuilder.genericFailure(for: result.status))
                }
            }
        }

        return stale(range, .decode("Couldn't read Anthropic cost response"))
    }

    private func snapshot(
        from results: [CostResultDTO],
        range: APISpendRange
    ) -> APISpendSnapshot {
        guard let total = CostAccumulator.total(from: results, emptyIsZero: true)
        else { return stale(range, .decode("Couldn't read Anthropic cost response")) }
        return APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: total.amount / 100,
            currency: total.currency,
            periodLabel: range.label,
            capturedAt: now(),
            freshness: .live
        )
    }

    private func stale(_ range: APISpendRange, _ reason: FailureReason) -> APISpendSnapshot {
        .stale(providerID: id, displayName: displayName, periodLabel: range.label, reason: reason)
    }
}

public struct XAIAPISpendProvider: APISpendProvider {
    public let id = ProviderID.grok
    public let displayName = "xAI API"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date
    private let context = XAIManagementContext()

    static let validationEndpoint = URL(string: "https://management-api.x.ai/auth/management-keys/validation")!
    static let billingTeamsEndpoint = URL(string: "https://management-api.x.ai/v1/billing/teams")!

    public init(
        credentials: CredentialStore,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.now = now
    }

    public func fetchSpend(period _: APISpendPeriod) async -> APISpendSnapshot {
        switch await credentials.apiKey(for: .xAI) {
        case .failure(let reason):
            return stale("API balance", reason)
        case .success(let key):
            let headers = ["Authorization": "Bearer \(key)"]
            let teamResult = await context.teamID(
                apiKey: key,
                validationEndpoint: Self.validationEndpoint,
                headers: headers,
                http: http
            )
            switch teamResult {
            case .failure(let reason):
                return stale("API balance", reason)
            case .success(let teamID):
                return await fetchBilling(teamID: teamID, headers: headers)
            }
        }
    }

    private func fetchBilling(teamID: String, headers: [String: String]) async -> APISpendSnapshot {
        let teamURL = Self.billingTeamsEndpoint.appendingPathComponent(teamID)
        let balanceURL = teamURL
            .appendingPathComponent("prepaid")
            .appendingPathComponent("balance")
        switch await http.get(url: balanceURL, headers: headers) {
        case .failure(let reason):
            return stale("Prepaid balance", reason)
        case .success(let result):
            switch result.status {
            case 200:
                guard let dto = try? JSONDecoder().decode(XAIPrepaidBalanceDTO.self, from: result.body),
                      let signedCents = dto.total?.val
                else { return stale("Prepaid balance", .decode("Couldn't read xAI prepaid balance")) }
                // The documented ledger represents available prepaid credit as a
                // negative liability (for example -1000 means $10 remaining).
                let remainingCents = max(0, -signedCents)
                if remainingCents > 0 {
                    return live(amount: remainingCents / 100, label: "Prepaid balance", kind: .balance)
                }
            case 401:
                return stale("Prepaid balance", .needsReauth("xAI management key rejected"))
            case 403:
                return stale("Prepaid balance", .scopeDenied("xAI key lacks billing read access"))
            default:
                return stale("Prepaid balance", UsageWindowBuilder.genericFailure(for: result.status))
            }
        }

        let previewURL = teamURL
            .appendingPathComponent("postpaid")
            .appendingPathComponent("invoice")
            .appendingPathComponent("preview")
        switch await http.get(url: previewURL, headers: headers) {
        case .failure(let reason):
            return zeroPrepaidBalance(reason: reason)
        case .success(let result):
            switch result.status {
            case 200:
                guard let dto = try? JSONDecoder().decode(XAIInvoicePreviewDTO.self, from: result.body),
                      let cents = dto.coreInvoice?.amountAfterVAT ?? dto.coreInvoice?.totalWithCorrections?.val
                else { return stale("Current billing period", .decode("Couldn't read xAI invoice preview")) }
                return live(amount: max(0, cents) / 100, label: "Current billing period", kind: .periodSpend)
            case 401:
                return zeroPrepaidBalance(reason: .needsReauth("xAI management key rejected"))
            case 403:
                return zeroPrepaidBalance(reason: .scopeDenied("xAI key lacks billing read access"))
            default:
                return zeroPrepaidBalance(reason: UsageWindowBuilder.genericFailure(for: result.status))
            }
        }
    }

    private func live(amount: Double, label: String, kind: APISpendKind) -> APISpendSnapshot {
        APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: amount,
            currency: "usd",
            periodLabel: label,
            kind: kind,
            capturedAt: now(),
            freshness: .live
        )
    }

    private func stale(_ label: String, _ reason: FailureReason) -> APISpendSnapshot {
        .stale(providerID: id, displayName: displayName, periodLabel: label, reason: reason)
    }

    /// The prepaid request already proved the balance is zero. Preserve that known
    /// value when the optional postpaid preview fails so continuity cannot resurrect
    /// an older positive balance.
    private func zeroPrepaidBalance(reason: FailureReason) -> APISpendSnapshot {
        APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: 0,
            currency: "usd",
            periodLabel: "Prepaid balance",
            kind: .balance,
            capturedAt: now(),
            freshness: .stale(reason)
        )
    }
}

private actor XAIManagementContext {
    private var cachedTeam: (apiKey: String, teamID: String)?

    func teamID(
        apiKey: String,
        validationEndpoint: URL,
        headers: [String: String],
        http: UsageFetching
    ) async -> Result<String, FailureReason> {
        if let cachedTeam, cachedTeam.apiKey == apiKey {
            return .success(cachedTeam.teamID)
        }
        switch await http.get(url: validationEndpoint, headers: headers) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let result):
            switch result.status {
            case 200:
                guard let dto = try? JSONDecoder().decode(XAIManagementKeyValidationDTO.self, from: result.body)
                else { return .failure(.decode("Couldn't validate xAI management key")) }
                let teamID: String?
                switch dto.scope?.uppercased() {
                case "SCOPE_TEAM":
                    teamID = dto.scopeID ?? dto.teamID
                case nil, "SCOPE_UNSPECIFIED":
                    teamID = dto.teamID
                default:
                    teamID = nil
                }
                guard let teamID, !teamID.isEmpty else {
                    return .failure(.scopeDenied("xAI management key must target one team"))
                }
                cachedTeam = (apiKey, teamID)
                return .success(teamID)
            case 401:
                return .failure(.needsReauth("xAI management key rejected"))
            case 403:
                return .failure(.scopeDenied("xAI key lacks management read access"))
            default:
                return .failure(UsageWindowBuilder.genericFailure(for: result.status))
            }
        }
    }
}

private struct XAIManagementKeyValidationDTO: Decodable {
    let teamID: String?
    let scope: String?
    let scopeID: String?

    enum CodingKeys: String, CodingKey {
        case teamID = "teamId"
        case scope
        case scopeID = "scopeId"
    }
}

private struct XAIPrepaidBalanceDTO: Decodable {
    let total: XAICentsDTO?
}

private struct XAIInvoicePreviewDTO: Decodable {
    struct CoreInvoice: Decodable {
        let amountAfterVAT: Double?
        let totalWithCorrections: XAICentsDTO?

        enum CodingKeys: String, CodingKey {
            case amountAfterVAT = "amountAfterVat"
            case totalWithCorrections = "totalWithCorr"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amountAfterVAT = container.flexibleDouble(forKey: .amountAfterVAT)
            totalWithCorrections = try? container.decode(XAICentsDTO.self, forKey: .totalWithCorrections)
        }
    }

    let coreInvoice: CoreInvoice?
}

private struct XAICentsDTO: Decodable {
    let val: Double?

    enum CodingKeys: String, CodingKey { case val }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        val = container.flexibleDouble(forKey: .val)
    }
}

private extension KeyedDecodingContainer {
    func flexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

private extension URL {
    func withOpenAICostQuery(_ range: APISpendRange) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(Int(range.start.timeIntervalSince1970))"),
            URLQueryItem(name: "end_time", value: "\(Int(range.end.timeIntervalSince1970))"),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]
        return components.url ?? self
    }

    func withAnthropicCostQuery(_ range: APISpendRange) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: DateFormatting.apiTimestamp(range.start)),
            URLQueryItem(name: "ending_at", value: DateFormatting.apiTimestamp(range.end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        return components.url ?? self
    }

    func withAnthropicPage(_ page: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems?.removeAll { $0.name == "page" }
        components.queryItems?.append(URLQueryItem(name: "page", value: page))
        return components.url ?? self
    }
}

private enum DateFormatting {
    static func apiTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
