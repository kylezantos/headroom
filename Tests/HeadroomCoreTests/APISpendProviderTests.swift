import Testing
import Foundation
@testable import HeadroomCore

struct APISpendProviderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(_ provider: APIKeyProvider, key: String? = "key") -> CredentialStore {
        var keys: [APIKeyProvider: String] = [:]
        if let key { keys[provider] = key }
        return CredentialStore(
            codexReader: MockCodexReader(credential: nil),
            apiKeyStore: MockAPIKeyStore(keys: keys)
        )
    }

    @Test func openAISumsCostBuckets() async {
        let json = """
        { "object": "page", "data": [
          { "object": "bucket", "results": [
            { "object": "organization.costs.result", "amount": { "value": 0.06, "currency": "usd" } }
          ]},
          { "object": "bucket", "results": [
            { "object": "organization.costs.result", "amount": { "value": 1.25, "currency": "usd" } }
          ]}
        ] }
        """
        let fetcher = MockFetcher(status: 200, body: json)
        let provider = OpenAIAPISpendProvider(credentials: store(.openAI), http: fetcher, now: { now })
        let snap = await provider.fetchSpend(period: .currentMonth)
        #expect(snap.freshness == .live)
        #expect(snap.amount == 1.31)
        #expect(snap.currency == "usd")
        #expect(fetcher.lastHeaders["Authorization"] == "Bearer key")
        #expect(fetcher.lastURL?.query?.contains("bucket_width=1d") == true)
    }

    @Test func anthropicConvertsFractionalCentsToDollars() async {
        let json = """
        { "data": [
          { "results": [
            { "amount": "123.45", "currency": "USD" }
          ]}
        ], "has_more": false }
        """
        let fetcher = MockFetcher(status: 200, body: json)
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })
        let snap = await provider.fetchSpend(period: .rolling30Days)
        #expect(snap.freshness == .live)
        #expect(snap.amount == 1.2345)
        #expect(snap.currency == "USD")
        #expect(fetcher.lastHeaders["x-api-key"] == "key")
        #expect(fetcher.lastHeaders["anthropic-version"] == "2023-06-01")
        #expect(fetcher.lastURL?.query?.contains("starting_at=") == true)
    }

    @Test func anthropicSendsRFC3339CostReportBounds() async {
        let fetcher = MockFetcher(status: 200, body: #"{"data":[],"has_more":false}"#)
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })

        _ = await provider.fetchSpend(period: .rolling30Days)

        let components = fetcher.lastURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(query["starting_at"] == "2026-12-16T08:00:00Z")
        #expect(query["ending_at"] == "2027-01-15T08:00:00Z")
        #expect(query["bucket_width"] == "1d")
        #expect(query["limit"] == "31")
    }

    @Test func anthropicSumsEveryCostReportPage() async {
        let firstPage = #"{"data":[{"results":[{"amount":"100.00","currency":"USD"}]}],"has_more":true,"next_page":"page-2"}"#
        let secondPage = #"{"data":[{"results":[{"amount":"200.00","currency":"USD"}]}],"has_more":false,"next_page":null}"#
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(firstPage.utf8))),
            .success(HTTPResult(status: 200, body: Data(secondPage.utf8))),
        ])
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.amount == 3)
        #expect(fetcher.requestCount == 2)
        let queries = fetcher.requestedURLs.map { url in
            Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
        }
        #expect(queries[1]["page"] == "page-2")
        #expect(queries[1]["starting_at"] == queries[0]["starting_at"])
        #expect(queries[1]["ending_at"] == queries[0]["ending_at"])
        #expect(queries[1]["bucket_width"] == queries[0]["bucket_width"])
        #expect(queries[1]["limit"] == queries[0]["limit"])
    }

    @Test func anthropicFailsClosedWhenPaginationTokenIsMissing() async {
        let body = #"{"data":[{"results":[{"amount":"100.00","currency":"USD"}]}],"has_more":true}"#
        let fetcher = MockFetcher(status: 200, body: body)
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        #expect(snapshot.freshness == .stale(.decode("Couldn't read Anthropic cost response")))
        #expect(snapshot.amount == nil)
        #expect(fetcher.requestCount == 1)
    }

    @Test func anthropicFailsClosedWhenHasMoreIsMissing() async {
        let body = #"{"data":[{"results":[{"amount":"100.00","currency":"USD"}]}]}"#
        let fetcher = MockFetcher(status: 200, body: body)
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        #expect(snapshot.freshness == .stale(.decode("Couldn't read Anthropic cost response")))
        #expect(snapshot.amount == nil)
        #expect(fetcher.requestCount == 1)
    }

    @Test(arguments: [
        #"{"has_more":false}"#,
        #"{"data":{},"has_more":false}"#,
    ])
    func anthropicDoesNotPublishPartialSpendWhenLaterPageDataIsMissingOrMalformed(secondPage: String) async {
        let firstPage = #"{"data":[{"results":[{"amount":"100.00","currency":"USD"}]}],"has_more":true,"next_page":"page-2"}"#
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(firstPage.utf8))),
            .success(HTTPResult(status: 200, body: Data(secondPage.utf8))),
        ])
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        #expect(snapshot.freshness == .stale(.decode("Couldn't read Anthropic cost response")))
        #expect(snapshot.amount == nil)
        #expect(fetcher.requestCount == 2)
    }

    @Test func anthropicDoesNotPublishPartialSpendWhenLaterPageFails() async {
        let firstPage = #"{"data":[{"results":[{"amount":"100.00","currency":"USD"}]}],"has_more":true,"next_page":"page-2"}"#
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(firstPage.utf8))),
            .failure(.transient("Network unavailable")),
        ])
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        #expect(snapshot.freshness == .stale(.transient("Network unavailable")))
        #expect(snapshot.amount == nil)
        #expect(fetcher.requestCount == 2)
    }

    @Test func missingAPIKeyIsPermanentStale() async {
        let provider = OpenAIAPISpendProvider(credentials: store(.openAI, key: nil), http: MockFetcher(status: 200, body: "{}"), now: { now })
        let snap = await provider.fetchSpend(period: .currentMonth)
        guard case .stale(let reason) = snap.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason.isPermanent)
    }

    @Test func explicitEmptyCostReportsAreZero() async {
        let openAI = OpenAIAPISpendProvider(
            credentials: store(.openAI),
            http: MockFetcher(status: 200, body: #"{"object":"page","data":[]}"#),
            now: { now }
        )
        let anthropic = AnthropicAPISpendProvider(
            credentials: store(.anthropic),
            http: MockFetcher(status: 200, body: #"{"data":[],"has_more":false}"#),
            now: { now }
        )

        let openAISnap = await openAI.fetchSpend(period: .currentMonth)
        let anthropicSnap = await anthropic.fetchSpend(period: .currentMonth)
        #expect(openAISnap.freshness == .live)
        #expect(openAISnap.amount == 0)
        #expect(anthropicSnap.freshness == .live)
        #expect(anthropicSnap.amount == 0)
    }

    @Test func permissionErrorsAreTyped() async {
        let provider = AnthropicAPISpendProvider(
            credentials: store(.anthropic),
            http: MockFetcher([.success(HTTPResult(status: 403, body: Data("secret body".utf8)))]),
            now: { now }
        )
        let snap = await provider.fetchSpend(period: .currentMonth)
        guard case .stale(let reason) = snap.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason == .scopeDenied("Anthropic key lacks cost report access"))
    }

    @Test func mixedCurrenciesDecodeAsStale() async {
        let json = """
        { "data": [ { "results": [
          { "amount": { "value": 1, "currency": "usd" } },
          { "amount": { "value": 1, "currency": "eur" } }
        ] } ] }
        """
        let provider = OpenAIAPISpendProvider(credentials: store(.openAI), http: MockFetcher(status: 200, body: json), now: { now })
        let snap = await provider.fetchSpend(period: .currentMonth)
        guard case .stale(let reason) = snap.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason == .decode("Couldn't read OpenAI cost response"))
    }

    @Test func xAIPrepaidBalanceUsesValidatedTeamAndCachesIt() async {
        let validation = #"{"scope":"SCOPE_TEAM","scopeId":"team-123"}"#
        let balance = #"{"changes":[],"total":{"val":"-4210"}}"#
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(validation.utf8))),
            .success(HTTPResult(status: 200, body: Data(balance.utf8))),
            .success(HTTPResult(status: 200, body: Data(balance.utf8))),
        ])
        let provider = XAIAPISpendProvider(credentials: store(.xAI), http: fetcher, now: { now })

        let first = await provider.fetchSpend(period: .currentMonth)
        let second = await provider.fetchSpend(period: .rolling30Days)

        #expect(first.freshness == .live)
        #expect(first.kind == .balance)
        #expect(first.amount == 42.10)
        #expect(first.currency == "usd")
        #expect(first.periodLabel == "Prepaid balance")
        #expect(second == first)
        #expect(fetcher.requestedURLs.map(\.path) == [
            "/auth/management-keys/validation",
            "/v1/billing/teams/team-123/prepaid/balance",
            "/v1/billing/teams/team-123/prepaid/balance",
        ])
        #expect(fetcher.lastHeaders["Authorization"] == "Bearer key")
    }

    @Test func xAIPostpaidInvoiceUsesPeriodSpendWhenPrepaidIsEmpty() async {
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(#"{"teamId":"team-legacy"}"#.utf8))),
            .success(HTTPResult(status: 200, body: Data(#"{"total":{"val":"0"}}"#.utf8))),
            .success(HTTPResult(status: 200, body: Data(#"{"coreInvoice":{"amountAfterVat":"1234"}}"#.utf8))),
        ])
        let provider = XAIAPISpendProvider(credentials: store(.xAI), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .rolling30Days)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.kind == .periodSpend)
        #expect(snapshot.amount == 12.34)
        #expect(snapshot.periodLabel == "Current billing period")
        #expect(fetcher.lastURL?.path == "/v1/billing/teams/team-legacy/postpaid/invoice/preview")
    }

    @Test func xAIPostpaidFailureKeepsKnownZeroPrepaidBalance() async {
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(#"{"scope":"SCOPE_TEAM","scopeId":"team-123"}"#.utf8))),
            .success(HTTPResult(status: 200, body: Data(#"{"total":{"val":"0"}}"#.utf8))),
            .success(HTTPResult(status: 503, body: Data())),
        ])
        let provider = XAIAPISpendProvider(credentials: store(.xAI), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        #expect(snapshot.amount == 0)
        #expect(snapshot.currency == "usd")
        #expect(snapshot.kind == .balance)
        #expect(snapshot.periodLabel == "Prepaid balance")
        #expect(snapshot.capturedAt == now)
        guard case .stale = snapshot.freshness else {
            Issue.record("expected stale")
            return
        }
    }

    @Test func xAITeamCacheIsInvalidatedWhenManagementKeyChanges() async {
        let keyStore = MockAPIKeyStore(keys: [.xAI: "first-key"])
        let credentials = CredentialStore(
            codexReader: MockCodexReader(credential: nil),
            apiKeyStore: keyStore
        )
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(#"{"scope":"SCOPE_TEAM","scopeId":"team-one"}"#.utf8))),
            .success(HTTPResult(status: 200, body: Data(#"{"total":{"val":"-100"}}"#.utf8))),
            .success(HTTPResult(status: 200, body: Data(#"{"scope":"SCOPE_TEAM","scopeId":"team-two"}"#.utf8))),
            .success(HTTPResult(status: 200, body: Data(#"{"total":{"val":"-200"}}"#.utf8))),
        ])
        let provider = XAIAPISpendProvider(credentials: credentials, http: fetcher, now: { now })

        let first = await provider.fetchSpend(period: .currentMonth)
        _ = await credentials.saveAPIKey("second-key", for: .xAI)
        let second = await provider.fetchSpend(period: .currentMonth)

        #expect(first.amount == 1)
        #expect(second.amount == 2)
        #expect(fetcher.requestedURLs.map(\.path) == [
            "/auth/management-keys/validation",
            "/v1/billing/teams/team-one/prepaid/balance",
            "/auth/management-keys/validation",
            "/v1/billing/teams/team-two/prepaid/balance",
        ])
        #expect(fetcher.lastHeaders["Authorization"] == "Bearer second-key")
    }

    @Test func xAIOrganizationScopedKeyFailsClosedWithoutGuessingATeam() async {
        let fetcher = MockFetcher(status: 200, body: #"{"scope":"SCOPE_ORGANIZATION","scopeId":"org-123"}"#)
        let provider = XAIAPISpendProvider(credentials: store(.xAI), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        guard case .stale(let reason) = snapshot.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason == .scopeDenied("xAI management key must target one team"))
        #expect(fetcher.requestCount == 1)
    }

    @Test func xAIBillingPermissionErrorsAreTyped() async {
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 200, body: Data(#"{"scope":"SCOPE_TEAM","scopeId":"team-123"}"#.utf8))),
            .success(HTTPResult(status: 403, body: Data("ignored".utf8))),
        ])
        let provider = XAIAPISpendProvider(credentials: store(.xAI), http: fetcher, now: { now })

        let snapshot = await provider.fetchSpend(period: .currentMonth)

        guard case .stale(let reason) = snapshot.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason == .scopeDenied("xAI key lacks billing read access"))
    }

    /// Copy resolves the credential from a `ProviderID` (the widget payloads carry nothing
    /// else), so the registry must agree with what each provider declares — otherwise the
    /// card could ask for a credential the endpoints never accept.
    @Test func declaredCredentialsMatchTheProviderIDRegistry() {
        let anthropic = AnthropicAPISpendProvider(credentials: store(.anthropic), http: MockFetcher(status: 200, body: "{}"))
        let openAI = OpenAIAPISpendProvider(credentials: store(.openAI), http: MockFetcher(status: 200, body: "{}"))
        let xAI = XAIAPISpendProvider(credentials: store(.xAI), http: MockFetcher(status: 200, body: "{}"))

        #expect(anthropic.credential == .anthropicAdminKey)
        #expect(openAI.credential == .openAIAdminKey)
        #expect(xAI.credential == .xAIManagementKey)

        for provider in [anthropic as any APISpendProvider, openAI, xAI] {
            #expect(provider.credential == APISpendCredentialDescriptor.forProvider(provider.id))
        }

        #expect(anthropic.credential.credentialNoun == "an admin key")
        #expect(xAI.credential.credentialNoun == "a management key")
    }

    /// The missing-key failure names the credential, not "a <vendor> admin API key" — that
    /// wording produced "Add a Anthropic…" and asked xAI for the wrong kind of key.
    @Test func missingKeyFailureNamesTheDeclaredCredential() async {
        let credentials = CredentialStore(
            codexReader: MockCodexReader(credential: nil),
            apiKeyStore: MockAPIKeyStore(keys: [:])
        )

        #expect(await credentials.apiKey(for: .anthropic).failureReason == .notLoggedIn("Add an admin key in Settings"))
        #expect(await credentials.apiKey(for: .openAI).failureReason == .notLoggedIn("Add an admin key in Settings"))
        #expect(await credentials.apiKey(for: .xAI).failureReason == .notLoggedIn("Add a management key in Settings"))
    }
}

private extension Result where Failure == FailureReason {
    var failureReason: FailureReason? {
        guard case .failure(let reason) = self else { return nil }
        return reason
    }
}
