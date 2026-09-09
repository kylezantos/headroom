import Foundation
import Testing
@testable import HeadroomCore

/// A real-shaped `.claude.json`: the official CLI writes `oauthAccount.emailAddress`
/// alongside a large amount of unrelated state, none of which Headroom decodes.
private let claudeAccountFileFixture = """
{
  "numStartups": 412,
  "installMethod": "native",
  "oauthAccount": {
    "accountUuid": "00000000-0000-0000-0000-000000000000",
    "emailAddress": "personal@example.com",
    "organizationName": "Personal"
  },
  "projects": { "/Users/test/repo": { "allowedTools": [] } }
}
"""

/// `tokens.id_token` from `~/.codex/auth.json`, header/payload/signature. The payload
/// segment is base64url with its padding stripped, exactly as a real JWT ships it.
private let codexIDTokenFixture =
    "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"
    + ".eyJzdWIiOiJ1c2VyLTEyMyIsImVtYWlsIjoid29ya0BleGFtcGxlLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlfQ"
    + ".sig-not-verified"

/// Same token shape with no `email` claim.
private let codexIDTokenWithoutEmailFixture =
    "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyJ9.sig-not-verified"

private let usagePanel = """
Current session
██████ 12% used
Resets 10:10am (America/Los_Angeles)
Current week (all models)
███████████ 38% used
Resets Jul 2 at 10am (America/Los_Angeles)
"""

struct ClaudeAccountEmailTests {
    @Test func decodesOAuthAccountEmail() {
        #expect(ClaudeAccountBlob.email(in: Data(claudeAccountFileFixture.utf8)) == "personal@example.com")
    }

    @Test func missingOrBlankEmailYieldsNil() {
        for json in [
            "{}",                                        // no oauthAccount at all
            #"{ "oauthAccount": {} }"#,                  // signed out / key absent
            #"{ "oauthAccount": { "emailAddress": "  " } }"#,
            #"{ "oauthAccount": { "emailAddress": 42 } }"#,
            "not json at all",
        ] {
            #expect(ClaudeAccountBlob.email(in: Data(json.utf8)) == nil)
        }
    }

    @Test func fileReaderReturnsNilWhenFileIsMissing() {
        let reader = ClaudeAccountEmailFileReader(
            path: URL(fileURLWithPath: "/redacted/.claude.json"),
            readData: { _ in throw CocoaError(.fileNoSuchFile) }
        )
        #expect(reader.readAccountEmail() == nil)
    }

    @Test func fileReaderReadsTheAccountFileAtTheConfigHomeRoot() {
        // Built-in account: `~/.claude.json` at the home root, NOT inside `~/.claude/`.
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(
            ClaudeAccountEmailFileReader.accountFileURL(configDirectory: nil, userHome: home).path
                == "/Users/test/.claude.json"
        )
        // Extra account: the root of its own CLAUDE_CONFIG_DIR.
        let configDirectory = URL(fileURLWithPath: "/Users/test/Accounts/claude/work/config")
        #expect(
            ClaudeAccountEmailFileReader.accountFileURL(configDirectory: configDirectory).path
                == "/Users/test/Accounts/claude/work/config/.claude.json"
        )
    }

    @Test func forAccountRoutesPrimaryToHomeRootAndExtrasToTheirConfigHome() {
        // `forAccount` is the one production resolver (ClaudeProvider's default
        // emailSource) — the branch below decides which account's email shows on
        // which card, so both sides are pinned.
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(
            ClaudeAccountEmailFileReader.forAccount(.primary).accountFilePath
                == home.appendingPathComponent(".claude.json").path
        )
        let extra = ClaudeAccountEmailFileReader.forAccount(AccountID("claude-work")).accountFilePath
        #expect(extra.hasSuffix("/Headroom/Accounts/claude/claude-work/config/.claude.json"))
    }

    @Test func providerPopulatesAccountEmailOnLiveSnapshots() async {
        let provider = ClaudeProvider(
            source: MockClaudeSource(result: .panel(text: usagePanel, planHint: "Max")),
            emailSource: StubClaudeEmailSource(email: "personal@example.com"),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.accountEmail == "personal@example.com")
    }

    @Test func providerStillReportsUsageWhenTheEmailIsUnreadable() async {
        let provider = ClaudeProvider(
            source: MockClaudeSource(result: .panel(text: usagePanel, planHint: "Max")),
            emailSource: StubClaudeEmailSource(email: nil),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.accountEmail == nil)
    }

    @Test func failedCaptureCarriesNoEmail() async {
        let provider = ClaudeProvider(
            source: MockClaudeSource(result: .loginRequired),
            emailSource: StubClaudeEmailSource(email: "personal@example.com")
        )
        #expect(await provider.fetchSnapshot().accountEmail == nil)
    }
}

struct ClaudeDuplicateLoginTests {
    @Test func decodesOAuthAccountUUID() {
        #expect(
            ClaudeAccountBlob.accountUUID(in: Data(claudeAccountFileFixture.utf8))
                == "00000000-0000-0000-0000-000000000000"
        )
    }

    @Test func missingOrBlankUUIDYieldsNil() {
        for json in [
            "{}",
            #"{ "oauthAccount": {} }"#,
            #"{ "oauthAccount": { "accountUuid": "  " } }"#,
            #"{ "oauthAccount": { "accountUuid": 42 } }"#,
            "not json at all",
        ] {
            #expect(ClaudeAccountBlob.accountUUID(in: Data(json.utf8)) == nil)
        }
    }

    @Test func sameUpstreamLoginBadgesTheLaterRow() {
        let main = ProviderAccount.builtIn(for: .claude)
        let extra = ProviderAccount(id: AccountID("extra-1"), providerID: .claude, label: "New")
        let detector = ClaudeDuplicateLoginDetector(readAccountUUID: { _ in "same-uuid" })
        // Registry order decides the original: the earlier row keeps its plain
        // identity, the later duplicate carries the badge.
        #expect(detector.duplicateLabels(for: [main, extra]) == [extra.key: "Main"])
    }

    @Test func distinctLoginsProduceNoBadges() {
        let main = ProviderAccount.builtIn(for: .claude)
        let extra = ProviderAccount(id: AccountID("extra-1"), providerID: .claude, label: "New")
        let detector = ClaudeDuplicateLoginDetector(
            readAccountUUID: { $0 == .primary ? "uuid-a" : "uuid-b" }
        )
        #expect(detector.duplicateLabels(for: [main, extra]).isEmpty)
    }

    @Test func unreadableIdentityNeverBadges() {
        let main = ProviderAccount.builtIn(for: .claude)
        let extra = ProviderAccount(id: AccountID("extra-1"), providerID: .claude, label: "New")
        // A missing/unreadable `.claude.json` (signed out, fresh config home) must fail
        // safe to "no claim", never to "same account".
        let detector = ClaudeDuplicateLoginDetector(readAccountUUID: { _ in nil })
        #expect(detector.duplicateLabels(for: [main, extra]).isEmpty)
    }

    @Test func uuidComparisonIsCaseInsensitive() {
        let main = ProviderAccount.builtIn(for: .claude)
        let extra = ProviderAccount(id: AccountID("extra-1"), providerID: .claude, label: "New")
        let detector = ClaudeDuplicateLoginDetector(
            readAccountUUID: { $0 == .primary ? "ABC-123" : "abc-123" }
        )
        #expect(detector.duplicateLabels(for: [main, extra]) == [extra.key: "Main"])
    }

    @Test func nonClaudeAccountsAreIgnored() {
        let codexMain = ProviderAccount.builtIn(for: .codex)
        let codexExtra = ProviderAccount(id: AccountID("extra-1"), providerID: .codex, label: "Work")
        let detector = ClaudeDuplicateLoginDetector(readAccountUUID: { _ in "same-uuid" })
        #expect(detector.duplicateLabels(for: [codexMain, codexExtra]).isEmpty)
    }

    @Test func threeWayDuplicatesAllPointAtTheFirstRow() {
        let main = ProviderAccount.builtIn(for: .claude)
        let second = ProviderAccount(id: AccountID("extra-1"), providerID: .claude, label: "New")
        let third = ProviderAccount(id: AccountID("extra-2"), providerID: .claude, label: "Newer")
        let detector = ClaudeDuplicateLoginDetector(readAccountUUID: { _ in "same-uuid" })
        #expect(detector.duplicateLabels(for: [main, second, third])
                == [second.key: "Main", third.key: "Main"])
    }
}

struct CodexAccountEmailTests {
    @Test func decodesEmailClaimFromIDToken() throws {
        let json = """
        { "auth_mode": "chatgpt",
          "tokens": { "access_token": "at", "id_token": "\(codexIDTokenFixture)",
                      "refresh_token": "rt", "account_id": "acc" } }
        """
        let credential = try CodexAuthBlob.parse(Data(json.utf8))
        #expect(credential.accessToken == "at")
        #expect(credential.email == "work@example.com")
    }

    @Test func malformedOrClaimlessTokensYieldNilWithoutFailingTheCredential() throws {
        for token in [
            codexIDTokenWithoutEmailFixture,   // valid JWT, no email claim
            "not-a-jwt",                       // no segments
            "only.two",                        // wrong segment count
            "aaa.!!!not-base64!!!.bbb",        // payload isn’t base64url
            "aaa.bm90IGpzb24.bbb",             // payload decodes but isn’t JSON
            "aaa..bbb",                        // empty payload
        ] {
            let json = """
            { "tokens": { "access_token": "at", "id_token": "\(token)" } }
            """
            let credential = try CodexAuthBlob.parse(Data(json.utf8))
            #expect(credential.accessToken == "at")
            #expect(credential.email == nil)
        }
    }

    @Test func absentIDTokenYieldsNilEmail() throws {
        let credential = try CodexAuthBlob.parse(
            Data(#"{ "tokens": { "access_token": "at" } }"#.utf8)
        )
        #expect(credential.email == nil)
    }

    @Test func credentialStoreExposesEmailAlongsideTheToken() async {
        let store = CredentialStore(
            codexReader: MockCodexReader(
                credential: CodexCredential(
                    accessToken: "at", refreshToken: "rt", accountID: "acc",
                    lastRefresh: nil, email: "work@example.com"
                )
            )
        )
        #expect(
            await store.codexSession()
                == .success(CodexSession(accessToken: "at", accountEmail: "work@example.com"))
        )
        #expect(await store.codexAccessToken() == .success("at"))
    }

    @Test func providerPopulatesAccountEmailOnLiveSnapshots() async {
        let body = """
        { "plan_type": "prolite",
          "rate_limit": { "primary_window": { "used_percent": 10, "limit_window_seconds": 18000,
                                              "reset_at": 1783023708 } } }
        """
        let provider = CodexProvider(
            credentials: CredentialStore(
                codexReader: MockCodexReader(
                    credential: CodexCredential(
                        accessToken: "at", refreshToken: nil, accountID: nil,
                        lastRefresh: nil, email: "work@example.com"
                    )
                )
            ),
            http: MockFetcher(status: 200, body: body),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.accountEmail == "work@example.com")
    }
}

struct AccountEmailContinuityTests {
    private let key = AccountKey(providerID: .claude, accountID: .primary)
    private let capturedAt = Date(timeIntervalSince1970: 2_000_000)

    private func priorSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            providerID: .claude,
            windows: [
                UsageWindow(
                    kind: .weekly,
                    utilization: 40,
                    resetsAt: Date(timeIntervalSince1970: 2_500_000),
                    resetLabel: "Resets Jul 2 at 10am"
                ),
            ],
            planLabel: "Max",
            accountEmail: "personal@example.com",
            capturedAt: capturedAt,
            freshness: .live
        )
    }

    @Test func staleMergePreservesLastKnownEmail() {
        let merged = UsageContinuityPolicy.mergedSnapshot(
            .stale(for: .claude, reason: .transient("Couldn’t reach Claude")),
            with: priorSnapshot(),
            at: capturedAt.addingTimeInterval(300)
        )

        #expect(merged.planLabel == "Max")
        #expect(merged.accountEmail == "personal@example.com")
        #expect(merged.windows.count == 1)
    }

    /// Pins the settled semantics: identity mirrors `planLabel` exactly, so a live
    /// capture is always authoritative — a nil email on a good capture clears the
    /// line (rather than carrying a possibly signed-out address forward), and a
    /// fresh email always replaces the prior one.
    @Test func liveCaptureIsAuthoritativeForEmail() {
        let liveWithNilEmail = UsageSnapshot(
            providerID: .claude,
            windows: priorSnapshot().windows,
            planLabel: "Max",
            accountEmail: nil,
            capturedAt: capturedAt.addingTimeInterval(300),
            freshness: .live
        )
        let mergedNil = UsageContinuityPolicy.mergedSnapshot(
            liveWithNilEmail, with: priorSnapshot(), at: capturedAt.addingTimeInterval(300)
        )
        #expect(mergedNil.accountEmail == nil)

        let liveWithNewEmail = UsageSnapshot(
            providerID: .claude,
            windows: priorSnapshot().windows,
            planLabel: "Max",
            accountEmail: "work@example.com",
            capturedAt: capturedAt.addingTimeInterval(300),
            freshness: .live
        )
        let mergedNew = UsageContinuityPolicy.mergedSnapshot(
            liveWithNewEmail, with: priorSnapshot(), at: capturedAt.addingTimeInterval(300)
        )
        #expect(mergedNew.accountEmail == "work@example.com")
    }

    @Test func markedStalePreservesEmail() {
        #expect(priorSnapshot().markedStale(.transient("retrying")).accountEmail == "personal@example.com")
    }

    @Test func launchRestorationPreservesEmail() {
        let restored = UsageContinuityPolicy.restoredSnapshot(
            priorSnapshot(),
            for: .claude,
            at: capturedAt.addingTimeInterval(600)
        )
        #expect(restored.accountEmail == "personal@example.com")
    }

    @Test func cacheRoundTripPreservesEmail() {
        let defaults = UserDefaults(suiteName: "AccountEmailContinuityTests-\(UUID().uuidString)")!
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(priorSnapshot(), for: key)

        #expect(UsageContinuityCache(defaults: defaults).load()[key]?.accountEmail == "personal@example.com")
    }

    /// The widget schema stays single-account and identity-free: adding an email to
    /// `UsageSnapshot` must not leak into the exported widget payload.
    @Test func widgetProjectionCarriesNoEmail() throws {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.claude: priorSnapshot()],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true
        )
        let encoded = try JSONEncoder().encode(envelope)

        #expect(envelope.providers.first?.planLabel == "Max")
        #expect(!String(decoding: encoded, as: UTF8.self).contains("personal@example.com"))
    }
}

// MARK: - Grok

/// A real-shaped `auth.json`: the official `grok` CLI keys each session record by
/// issuer + account uuid and writes `email` beside the token material. Addresses and
/// token values here are redacted placeholders.
private let grokAuthFileFixture = """
{
  "xai::api_key": { "key": "unrelated-api-key", "user_id": "unrelated" },
  "https://auth.x.ai::00000000-0000-0000-0000-000000000000": {
    "auth_mode": "oidc",
    "user_id": "user-123",
    "email": "personal@example.com",
    "first_name": "Redacted",
    "key": "redacted-access-token",
    "refresh_token": "redacted-refresh-token"
  }
}
"""

/// A valid Grok billing payload, so the email assertions run against a live snapshot.
private let grokBillingBody = Data("""
{"config":{"creditUsagePercent":12,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",
"start":"2026-07-01T00:00:00Z","end":"2026-07-08T00:00:00Z"}},"subscriptionTier":"SuperGrok"}
""".utf8)

struct GrokAccountEmailTests {
    @Test func decodesEmailFromTheSelectedSessionRecord() throws {
        let credential = try GrokAuthBlob.parse(Data(grokAuthFileFixture.utf8))
        #expect(credential.accessToken == "redacted-access-token")
        #expect(credential.email == "personal@example.com")
    }

    @Test func missingOrMalformedEmailYieldsNilWithoutFailingTheCredential() throws {
        for record in [
            #""auth_mode":"oidc","key":"k","user_id":"u""#,                        // no email key
            #""auth_mode":"oidc","key":"k","user_id":"u","email":"  ""#,           // blank
            #""auth_mode":"oidc","key":"k","user_id":"u","email":42"#,             // not a string
            #""auth_mode":"oidc","key":"k","user_id":"u","email":null"#,           // explicit null
        ] {
            let json = #"{ "https://auth.x.ai::a": { \#(record) } }"#
            let credential = try GrokAuthBlob.parse(Data(json.utf8))
            #expect(credential.accessToken == "k")
            #expect(credential.email == nil)
        }
    }

    /// The email must always belong to the account whose token the billing call uses.
    /// Selection is the existing one — first-party issuer scopes, sorted by key, first
    /// wins — so both values come out of the same record.
    @Test func emailComesFromTheSameRecordTheTokenDoesWhenSeveralSessionsExist() throws {
        let json = """
        {
          "https://auth.x.ai::11111111": { "auth_mode": "oidc", "key": "first-token",
                                           "user_id": "u1", "email": "personal@example.com" },
          "https://auth.x.ai::22222222": { "auth_mode": "oidc", "key": "second-token",
                                           "user_id": "u2", "email": "work@example.com" }
        }
        """
        let credential = try GrokAuthBlob.parse(Data(json.utf8))
        #expect(credential.accessToken == "first-token")
        #expect(credential.email == "personal@example.com")
    }

    @Test func readerReturnsNilWhenTheAuthFileIsUnreadable() {
        let missing = GrokCredentialEmailReader(
            authReader: ThrowingGrokAuthReader(error: CredentialError.notLoggedIn)
        )
        let malformed = GrokCredentialEmailReader(
            authReader: ThrowingGrokAuthReader(error: CredentialError.malformed)
        )
        #expect(missing.readAccountEmail() == nil)
        #expect(malformed.readAccountEmail() == nil)
    }

    @Test func readerReadsTheFileTheBillingPathAlreadyResolved() {
        // One resolver: the same `GrokAuthFileReader` the HTTP fallback uses, so an
        // extra account's GROK_HOME is honoured without a parallel path mechanism.
        let reader = GrokCredentialEmailReader(
            authReader: GrokAuthFileReader(
                path: URL(fileURLWithPath: "/Accounts/grok/work/auth.json"),
                readData: { url in
                    #expect(url.path == "/Accounts/grok/work/auth.json")
                    return Data(grokAuthFileFixture.utf8)
                },
                permissionsAreSafe: { _ in true }
            )
        )
        #expect(reader.readAccountEmail() == "personal@example.com")
    }

    /// Pins the review outcome on the init default: NO account — primary included —
    /// reads a real credential file when `emailSource` is omitted. A default-built
    /// provider is identity-less; composition injects the account-scoped reader.
    @Test func defaultInitializerNeverReadsARealAuthFile() async {
        for accountID in [AccountID.primary, AccountID("grok-work")] {
            let provider = GrokProvider(
                source: MockGrokSource(result: .payload(grokBillingBody, transport: .http)),
                accountID: accountID,
                now: { Date(timeIntervalSince1970: 1_000_000) }
            )
            let snapshot = await provider.fetchSnapshot()
            #expect(snapshot.freshness == .live)
            #expect(snapshot.accountEmail == nil)
        }
    }

    @Test func providerPopulatesAccountEmailOnLiveSnapshots() async {
        let provider = GrokProvider(
            source: MockGrokSource(result: .payload(grokBillingBody, transport: .http)),
            emailSource: StubGrokEmailSource(email: "personal@example.com"),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.accountEmail == "personal@example.com")
    }

    @Test func providerStillReportsUsageWhenTheEmailIsUnreadable() async {
        let provider = GrokProvider(
            source: MockGrokSource(result: .payload(grokBillingBody, transport: .http)),
            emailSource: StubGrokEmailSource(email: nil),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.accountEmail == nil)
    }

    @Test func failedFetchCarriesNoEmail() async {
        let provider = GrokProvider(
            source: MockGrokSource(result: .authAbsent),
            emailSource: StubGrokEmailSource(email: "personal@example.com")
        )
        #expect(await provider.fetchSnapshot().accountEmail == nil)
    }
}

// MARK: - Cursor

/// A real-shaped `cursor-agent status --format json` report, redacted. Only
/// `userInfo.email` is ever decoded.
private let cursorStatusFixture = """
{
  "status": "authenticated",
  "version": "2026.07.30-abcdef",
  "userInfo": {
    "email": "personal@example.com",
    "name": "Redacted"
  }
}
"""

struct CursorAccountEmailTests {
    private func usagePanel() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "cursor-usage", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func decodesUserInfoEmail() {
        #expect(CursorStatusBlob.email(in: Data(cursorStatusFixture.utf8)) == "personal@example.com")
    }

    @Test func everyFailureShapeYieldsNil() {
        for json in [
            #"{ "status": "unauthenticated" }"#,                   // signed out: no userInfo
            #"{ "status": "authenticated", "userInfo": {} }"#,     // no email key
            #"{ "status": "authenticated", "userInfo": { "email": "  " } }"#,
            #"{ "status": "authenticated", "userInfo": { "email": 42 } }"#,
            #"{ "status": "authenticated", "userInfo": null }"#,
            "cursor-agent: command failed",                        // non-zero exit output
            "",                                                    // timeout / no output
        ] {
            #expect(CursorStatusBlob.email(in: Data(json.utf8)) == nil)
        }
    }

    @Test func probeReturnsNilWhenTheCLIIsMissing() async {
        let probe = CursorStatusEmailProbe(cursorPath: nil)
        #expect(await probe.readAccountEmail() == nil)

        let absent = CursorStatusEmailProbe(cursorPath: "/redacted/does-not-exist/cursor-agent")
        #expect(await absent.readAccountEmail() == nil)
    }

    @Test func providerPopulatesAccountEmailOnLiveSnapshots() async throws {
        let provider = CursorProvider(
            source: StubCursorPanelSource(result: .panel(try usagePanel())),
            emailSource: StubCursorEmailSource(email: "personal@example.com"),
            now: { ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z")! }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.accountEmail == "personal@example.com")
    }

    @Test func providerStillReportsUsageWhenTheEmailSourceFails() async throws {
        let provider = CursorProvider(
            source: StubCursorPanelSource(result: .panel(try usagePanel())),
            emailSource: StubCursorEmailSource(email: nil),
            now: { ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z")! }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.planLabel == "Pro+")
        #expect(snapshot.accountEmail == nil)
    }

    @Test func failedCaptureCarriesNoEmail() async {
        let provider = CursorProvider(
            source: StubCursorPanelSource(result: .loginRequired),
            emailSource: StubCursorEmailSource(email: "personal@example.com")
        )
        #expect(await provider.fetchSnapshot().accountEmail == nil)
    }

    /// The Grok/Cursor snapshots must not push identity into the widget/iCloud payload.
    @Test func widgetProjectionCarriesNoEmailForTheNewProviders() throws {
        let snapshot = { (id: ProviderID) in
            UsageSnapshot(
                providerID: id,
                windows: [UsageWindow(kind: .weekly, utilization: 40, resetsAt: Date())],
                planLabel: "SuperGrok",
                accountEmail: "personal@example.com",
                capturedAt: Date(),
                freshness: .live
            )
        }
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.grok: snapshot(.grok), .cursor: snapshot(.cursor)],
            providerOrder: [.grok, .cursor],
            displayNames: [.grok: "Grok", .cursor: "Cursor"],
            renewalDate: { _ in nil },
            widgetsEnabled: true
        )
        let encoded = try JSONEncoder().encode(envelope)

        #expect(envelope.providers.count == 2)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("personal@example.com"))
    }
}

// MARK: - Normalization

/// Same address, as each CLI happens to have stored it. `.claude.json` keeps the casing
/// the user typed at login; Codex's `id_token` claim arrives already lowercased. Before
/// normalization the Accounts pane showed "Kylezantos@gmail.com" for Claude next to
/// "kylezantos@gmail.com" for Codex.
private let mixedCaseAddress = "Kylezantos@Gmail.COM"
private let normalizedAddress = "kylezantos@gmail.com"

/// `tokens.id_token` whose `email` claim is `Kylezantos@Gmail.COM`.
private let codexMixedCaseIDTokenFixture =
    "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"
    + ".eyJzdWIiOiJ1c2VyLTEyMyIsImVtYWlsIjoiS3lsZXphbnRvc0BHbWFpbC5DT00ifQ"
    + ".sig-not-verified"

struct AccountEmailNormalizationTests {
    @Test func normalizationTrimsAndLowercases() {
        #expect(AccountEmail.normalized("  \(mixedCaseAddress) \n") == normalizedAddress)
        #expect(AccountEmail.normalized(normalizedAddress) == normalizedAddress)
    }

    @Test func nothingDisplayableYieldsNil() {
        #expect(AccountEmail.normalized(nil) == nil)
        #expect(AccountEmail.normalized("") == nil)
        #expect(AccountEmail.normalized("   ") == nil)
    }

    @Test func claudeAccountFileEmailIsNormalized() {
        let json = #"{ "oauthAccount": { "emailAddress": " \#(mixedCaseAddress) " } }"#
        #expect(ClaudeAccountBlob.email(in: Data(json.utf8)) == normalizedAddress)
    }

    @Test func codexIDTokenEmailIsNormalized() throws {
        let json = """
        { "tokens": { "access_token": "at", "id_token": "\(codexMixedCaseIDTokenFixture)" } }
        """
        #expect(try CodexAuthBlob.parse(Data(json.utf8)).email == normalizedAddress)
    }

    @Test func grokAuthFileEmailIsNormalized() throws {
        let json = #"""
        { "https://auth.x.ai::a": { "auth_mode": "oidc", "key": "k", "user_id": "u",
                                    "email": " \#(mixedCaseAddress) " } }
        """#
        #expect(try GrokAuthBlob.parse(Data(json.utf8)).email == normalizedAddress)
    }

    @Test func grokEmailReaderNormalizesWhateverTheAuthReaderReturns() {
        let reader = GrokCredentialEmailReader(
            authReader: StubGrokAuthReader(
                credential: GrokCredential(accessToken: "k", userID: "u", email: mixedCaseAddress)
            )
        )
        #expect(reader.readAccountEmail() == normalizedAddress)
    }

    @Test func cursorStatusEmailIsNormalized() {
        let json = #"{ "status": "authenticated", "userInfo": { "email": " \#(mixedCaseAddress) " } }"#
        #expect(CursorStatusBlob.email(in: Data(json.utf8)) == normalizedAddress)
    }

    /// The whole point: one address read from two different CLIs renders as one string,
    /// so the Accounts pane no longer shows the same login twice with different casing.
    @Test func claudeAndCodexAgreeOnTheSameAddress() async throws {
        let claudeJSON = #"{ "oauthAccount": { "emailAddress": "\#(mixedCaseAddress)" } }"#
        let codexJSON = """
        { "tokens": { "access_token": "at", "id_token": "\(codexMixedCaseIDTokenFixture)" } }
        """
        let claudeProvider = ClaudeProvider(
            source: MockClaudeSource(result: .panel(text: usagePanel, planHint: "Max")),
            emailSource: StubClaudeEmailSource(
                email: ClaudeAccountBlob.email(in: Data(claudeJSON.utf8))
            ),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let codexProvider = CodexProvider(
            credentials: CredentialStore(
                codexReader: MockCodexReader(credential: try CodexAuthBlob.parse(Data(codexJSON.utf8)))
            ),
            http: MockFetcher(status: 200, body: """
            { "plan_type": "prolite",
              "rate_limit": { "primary_window": { "used_percent": 10, "limit_window_seconds": 18000,
                                                  "reset_at": 1783023708 } } }
            """),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )

        let claudeEmail = await claudeProvider.fetchSnapshot().accountEmail
        let codexEmail = await codexProvider.fetchSnapshot().accountEmail
        #expect(claudeEmail == normalizedAddress)
        #expect(claudeEmail == codexEmail)
    }
}

private struct StubGrokAuthReader: GrokAuthReading {
    let credential: GrokCredential
    func readGrokCredential() throws -> GrokCredential { credential }
}

/// Claude email-source double — keeps the provider tests off the real `.claude.json`.
private struct StubClaudeEmailSource: ClaudeAccountEmailReading {
    let email: String?
    func readAccountEmail() -> String? { email }
}

private struct StubGrokEmailSource: GrokAccountEmailReading {
    let email: String?
    func readAccountEmail() -> String? { email }
}

private struct ThrowingGrokAuthReader: GrokAuthReading {
    let error: CredentialError
    func readGrokCredential() throws -> GrokCredential { throw error }
}

/// Cursor email-source double — keeps the provider tests off the real `cursor-agent`.
private struct StubCursorEmailSource: CursorAccountEmailReading {
    let email: String?
    func readAccountEmail() async -> String? { email }
}

private struct StubCursorPanelSource: CursorUsageSource {
    let result: CursorPanelResult
    func capturePanel() async -> CursorPanelResult { result }
}
