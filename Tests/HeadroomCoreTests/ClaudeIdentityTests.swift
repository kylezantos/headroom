import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U1, U2 and U4, Claude half: identity from `.claude.json`
/// (`oauthAccount.accountUuid` + `organizationUuid`), the before-and-after read on every
/// fetch, and what the store then does with it. Fixtures, temporary directories and
/// injected readers only; no test touches a real config home, the network or the Keychain.

private let accountA = "aaaaaaaa-1111-4111-8111-000000000001"
private let accountB = "bbbbbbbb-2222-4222-8222-000000000002"
private let personalOrg = "0a0a0a0a-3333-4333-8333-000000000003"
private let teamOrg = "0b0b0b0b-4444-4444-8444-000000000004"

private func claudeFile(account: String?, organization: String?? = .some(personalOrg), email: String? = "a@example.com") -> Data {
    var block: [String: Any] = [:]
    if let account { block["accountUuid"] = account }
    switch organization {
    case .none: break
    case .some(.none): block["organizationUuid"] = NSNull()
    case .some(.some(let org)): block["organizationUuid"] = org
    }
    if let email { block["emailAddress"] = email }
    let root: [String: Any] = ["numStartups": 3, "oauthAccount": block, "projects": [:] as [String: Any]]
    return try! JSONSerialization.data(withJSONObject: root)
}

private func identity(_ account: String, _ organization: String? = personalOrg) -> AccountIdentity {
    AccountIdentity.claude(accountUUID: account, organizationUUID: organization)!
}

private func read(_ account: String, email: String? = nil) -> AccountIdentityRead {
    .identity(identity(account), email: email ?? "\(account.prefix(8))@example.com")
}

private let livePanel = """
Current session
██████ 12% used
Resets 10:10am (America/Los_Angeles)
Current week (all models)
███████████ 38% used
Resets Jul 2 at 10am (America/Los_Angeles)
"""

// MARK: Doubles

/// Order log shared by a Claude source double and an account-file double, so a test can
/// see when the account file is read relative to the `/usage` capture.
final class ClaudeReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var events: [String] { lock.withLock { entries } }
}

/// A `/usage` source whose result and inherited-token signal a test can change.
final class ScriptedClaudeSource: ClaudeUsageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var result: ClaudePanelResult
    private var inherits: Bool
    private var captures = 0
    let log: ClaudeReadLog?

    init(_ result: ClaudePanelResult = .panel(text: livePanel, planHint: nil), inheritsToken: Bool = false, log: ClaudeReadLog? = nil) {
        self.result = result
        self.inherits = inheritsToken
        self.log = log
    }

    func set(_ result: ClaudePanelResult) { lock.withLock { self.result = result } }
    var captureCount: Int { lock.withLock { captures } }
    var launchesWithInheritedOAuthToken: Bool { lock.withLock { inherits } }

    func capturePanel() async -> ClaudePanelResult {
        log?.append("capture")
        return lock.withLock {
            captures += 1
            return result
        }
    }
}

/// Returns its reads in order, repeating the last one (or cycling, for a file that never
/// settles).
final class ScriptedClaudeIdentity: ClaudeAccountEmailReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [AccountIdentityRead]
    private let cycles: Bool
    private var count = 0
    let log: ClaudeReadLog?

    init(_ reads: [AccountIdentityRead], cycles: Bool = false, log: ClaudeReadLog? = nil) {
        self.reads = reads
        self.cycles = cycles
        self.log = log
    }

    func set(_ reads: [AccountIdentityRead]) { lock.withLock { self.reads = reads } }
    var readCount: Int { lock.withLock { count } }

    func readAccountEmail() -> String? { readAccountIdentity().email }

    func readAccountIdentity() -> AccountIdentityRead {
        log?.append("identity")
        return lock.withLock {
            count += 1
            if cycles {
                let next = reads.removeFirst()
                reads.append(next)
                return next
            }
            return reads.count > 1 ? reads.removeFirst() : reads[0]
        }
    }
}

private func temporaryDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("headroom-claude-identity-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: U1. Model and reader

struct ClaudeIdentityModelTests {
    @Test func aFileWithBothIdsYieldsAStrongIdentityAndItsEmail() throws {
        let result = ClaudeAccountBlob.identityRead(in: claudeFile(account: accountA, email: " A@Example.com "))
        let found = try #require(result.identity)
        #expect(found == identity(accountA))
        #expect(found.providerID == .claude)
        #expect(found.strength == .strong)
        #expect(found.digestVersion == AccountIdentity.currentDigestVersion)
        #expect(result.email == "a@example.com")
    }

    @Test func oneAccountInTwoOrganizationsIsTwoIdentities() {
        let personal = ClaudeAccountBlob.identityRead(in: claudeFile(account: accountA, organization: personalOrg)).identity
        let team = ClaudeAccountBlob.identityRead(in: claudeFile(account: accountA, organization: teamOrg)).identity
        #expect(personal != nil)
        #expect(team != nil)
        #expect(personal != team)
    }

    @Test func aNullOrAbsentOrganizationIsAValueNotAFailure() throws {
        let null = try #require(ClaudeAccountBlob.identityRead(in: claudeFile(account: accountA, organization: .some(nil))).identity)
        let absent = try #require(ClaudeAccountBlob.identityRead(in: claudeFile(account: accountA, organization: .none)).identity)
        #expect(null == absent)
        #expect(null.strength == .strong)
        // No organization is its own value, never equal to one with an organization.
        #expect(null != identity(accountA))
        #expect(AccountIdentity.claude(accountUUID: accountA, organizationUUID: "  ") == null)
    }

    @Test func aHandEditedIdYieldsNoIdentity() {
        for bad in ["", "   ", "same-account", "not-a-uuid", "11111111-2222-3333-4444"] {
            #expect(AccountIdentity.claude(accountUUID: bad, organizationUUID: personalOrg) == nil)
            #expect(ClaudeAccountBlob.identityRead(in: claudeFile(account: bad)) == .absent)
            // A non-UUID organization is a hand-edit too, unless it is blank (no organization).
            if !bad.trimmingCharacters(in: .whitespaces).isEmpty {
                #expect(AccountIdentity.claude(accountUUID: accountA, organizationUUID: bad) == nil)
            }
        }
        #expect(AccountIdentity.claude(accountUUID: nil, organizationUUID: personalOrg) == nil)
    }

    @Test func aSignedOutFileIsAbsentAndAnUndecodableOneIsUnreadable() {
        // Gate V1: after `claude auth logout` the `oauthAccount` block is gone.
        #expect(ClaudeAccountBlob.identityRead(in: Data(#"{"numStartups": 4}"#.utf8)) == .absent)
        #expect(ClaudeAccountBlob.identityRead(in: Data(#"{"oauthAccount": {}}"#.utf8)) == .absent)
        #expect(ClaudeAccountBlob.identityRead(in: Data(#"{"oauthAccount": null}"#.utf8)) == .absent)
        #expect(ClaudeAccountBlob.identityRead(in: claudeFile(account: nil)) == .absent)
        // Half-written or hand-broken.
        #expect(ClaudeAccountBlob.identityRead(in: Data("{ \"oauthAccount\": { \"accountUu".utf8)) == .unreadable)
        #expect(ClaudeAccountBlob.identityRead(in: Data(#"{"oauthAccount": {"accountUuid": 42}}"#.utf8)) == .unreadable)
        #expect(ClaudeAccountBlob.identityRead(in: Data()) == .unreadable)
    }

    @Test func aMissingFileIsAbsentAnUnreadableOneIsUnreadableAndNeitherThrows() throws {
        func reader(_ error: Error) -> ClaudeAccountEmailFileReader {
            ClaudeAccountEmailFileReader(path: URL(fileURLWithPath: "/redacted/.claude.json"), readData: { _ in throw error })
        }
        #expect(reader(CocoaError(.fileReadNoSuchFile)).readAccountIdentity() == .absent)
        #expect(reader(CocoaError(.fileNoSuchFile)).readAccountIdentity() == .absent)
        #expect(reader(POSIXError(.ENOENT)).readAccountIdentity() == .absent)
        #expect(reader(CocoaError(.fileReadNoPermission)).readAccountIdentity() == .unreadable)
        #expect(reader(POSIXError(.EIO)).readAccountIdentity() == .unreadable)

        // The real file path, on a temporary config home the CLI has not written yet.
        let home = try temporaryDirectory("missing")
        defer { try? FileManager.default.removeItem(at: home) }
        let real = ClaudeAccountEmailFileReader(configDirectory: home)
        #expect(real.readAccountIdentity() == .absent)
        try Data("{ not json".utf8).write(to: home.appendingPathComponent(".claude.json"))
        #expect(real.readAccountIdentity() == .unreadable)
        try claudeFile(account: accountA).write(to: home.appendingPathComponent(".claude.json"))
        #expect(real.readAccountIdentity().identity == identity(accountA))
    }

    /// KTD1: the canonical input is fixed. Changing it needs a new digest version.
    @Test func theGoldenVectorFixesTheClaudeDigest() throws {
        #expect(AccountIdentity.currentDigestVersion == 1)
        #expect(identity(accountA, personalOrg).digest
            == "49c78d66911bf773cd82a67a2c4ddbb43031593a38aeeadf0c2ee0e0b28af0c0")
        #expect(identity(accountA, nil).digest
            == "9ecceef3eb270a6cfc3e49a5d5e67c41fa5eb428a5a7362bc7efc0baaf7d27f4")
    }

    @Test func uuidCaseAndSurroundingWhitespaceDoNotChangeTheDigest() {
        #expect(AccountIdentity.claude(accountUUID: "  \(accountA.uppercased())\n", organizationUUID: " \(personalOrg.uppercased()) ")
            == identity(accountA))
    }

    @Test func theDigestNeverContainsTheRawIdsOrEmail() throws {
        let read = ClaudeAccountBlob.identityRead(in: claudeFile(account: accountA, email: "work@example.com"))
        let found = try #require(read.identity)
        let encoded = String(decoding: try JSONEncoder().encode(found), as: UTF8.self)
        for raw in [accountA, personalOrg, "aaaaaaaa", "0a0a0a0a", "work@example.com"] {
            #expect(!encoded.contains(raw))
        }
    }

    @Test func theSameUUIDUnderCodexIsAnotherIdentity() {
        #expect(AccountIdentity.codex(accountID: accountA) != AccountIdentity.claude(accountUUID: accountA, organizationUUID: nil))
    }

    /// KTD1: the badge and the default-login records key on one value, read through the
    /// same file reader. Personal home, two Team homes, all one `accountUuid`.
    @Test func theDuplicateBadgeAndTheIdentityKeyAgreeOnAPersonalPlusTeamFixture() throws {
        let base = try temporaryDirectory("badge")
        defer { try? FileManager.default.removeItem(at: base) }
        let accounts = [
            ProviderAccount.builtIn(for: .claude),
            ProviderAccount(id: AccountID("team-1"), providerID: .claude, label: "Team"),
            ProviderAccount(id: AccountID("team-2"), providerID: .claude, label: "Team copy"),
        ]
        let files: [AccountID: Data] = [
            .primary: claudeFile(account: accountA, organization: personalOrg, email: "me@example.com"),
            AccountID("team-1"): claudeFile(account: accountA, organization: teamOrg, email: "me@example.com"),
            AccountID("team-2"): claudeFile(account: accountA, organization: teamOrg, email: "me@example.com"),
        ]
        var readers: [AccountID: ClaudeAccountEmailFileReader] = [:]
        for (id, data) in files {
            let home = base.appendingPathComponent(id.raw, isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try data.write(to: home.appendingPathComponent(".claude.json"))
            readers[id] = ClaudeAccountEmailFileReader(configDirectory: home)
        }
        let identities = readers.mapValues { $0.readAccountIdentity().identity }
        let detector = ClaudeDuplicateLoginDetector(readIdentity: { identities[$0] ?? nil })
        let badges = detector.duplicateLabels(for: accounts)

        // The email is the same everywhere; only the identity decides.
        #expect(badges == [AccountKey(providerID: .claude, accountID: AccountID("team-2")): "Team"])
        for (index, account) in accounts.enumerated() {
            let earlierMatch = accounts[..<index].contains { identities[$0.id] == identities[account.id] }
            #expect((badges[account.key] != nil) == earlierMatch)
        }
    }
}

// MARK: U2. Before-and-after identity on every fetch

struct ClaudeIdentityFetchTests {
    private func provider(
        _ reads: [AccountIdentityRead]?,
        source: ScriptedClaudeSource = ScriptedClaudeSource(),
        accountID: AccountID = .primary
    ) -> ClaudeProvider {
        ClaudeProvider(
            source: source,
            accountID: accountID,
            emailSource: reads.map { ScriptedClaudeIdentity($0) },
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    /// Characterization was taken first against the old code (email read once, after a
    /// live capture only); this is the replacement contract.
    @Test func theAccountFileIsReadBeforeAndAfterALiveCaptureAndOnlyBeforeAFailedOne() async {
        let log = ClaudeReadLog()
        let live = await ClaudeProvider(
            source: ScriptedClaudeSource(log: log),
            emailSource: ScriptedClaudeIdentity([read(accountA, email: "a@example.com")], log: log),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        ).fetchResult()
        #expect(log.events == ["identity", "capture", "identity"])
        #expect(live.snapshot.accountEmail == "a@example.com")

        let failedLog = ClaudeReadLog()
        let failed = await ClaudeProvider(
            source: ScriptedClaudeSource(.loginRequired, log: failedLog),
            emailSource: ScriptedClaudeIdentity([read(accountA)], log: failedLog)
        ).fetchResult()
        #expect(failedLog.events == ["identity", "capture"])
        #expect(failed.snapshot.accountEmail == nil)
        #expect(failed.snapshot.identity == nil)
        #expect(failed.discard == nil)
    }

    @Test func aBeforeAndAAfterIsKnownWithTheEmailFromThatPair() async {
        let result = await provider([read(accountA, email: "a@example.com"), read(accountA, email: "a@example.com")]).fetchResult()
        #expect(result.discard == nil)
        #expect(result.capability == .available)
        #expect(result.snapshot.freshness == .live)
        #expect(result.snapshot.identity == .known(identity(accountA)))
        #expect(result.snapshot.accountEmail == "a@example.com")
    }

    /// Covers AE6 at the provider.
    @Test func aBeforeAndBAfterIsRefused() async {
        let result = await provider([read(accountA), read(accountB)]).fetchResult()
        #expect(result.discard == .identityUnreadable)
        #expect(result.snapshot.freshness != .live)
        #expect(result.snapshot.windows.isEmpty)
    }

    @Test func noAccountBlockOnEitherSideIsAbsentAndTheReadingIsKept() async {
        let result = await provider([.absent, .absent]).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.freshness == .live)
        #expect(result.snapshot.identity == .absent)
        #expect(result.snapshot.accountEmail == nil)
    }

    @Test func aFileUnreadableOrSignedOutOnOneSideIsRefused() async {
        for pair in [
            [AccountIdentityRead.unreadable, read(accountA)],
            [read(accountA), .unreadable],
            [.absent, read(accountA)],
            [read(accountA), .absent],
            [.unreadable, .absent],
        ] {
            #expect(await provider(pair).fetchResult().discard == .identityUnreadable)
        }
    }

    /// Unlike Grok, Claude's file is the one its CLI reads, so a file present but
    /// undecodable on both sides is refused and left to the refusal bound (KTD2 as written).
    @Test func aFileUndecodableOnBothSidesIsRefused() async {
        #expect(await provider([.unreadable, .unreadable]).fetchResult().discard == .identityUnreadable)
    }

    @Test func anInheritedOAuthTokenIsAbsentForEveryRowAndReadsNoFile() async {
        for accountID in [AccountID.primary, AccountID("claude-work")] {
            let reader = ScriptedClaudeIdentity([read(accountA)])
            let result = await ClaudeProvider(
                source: ScriptedClaudeSource(inheritsToken: true),
                accountID: accountID,
                emailSource: reader
            ).fetchResult()
            #expect(result.discard == nil)
            #expect(result.snapshot.freshness == .live)
            #expect(result.snapshot.identity == .absent)
            #expect(result.snapshot.accountEmail == nil)
            #expect(reader.readCount == 0)
        }
    }

    /// The signal comes from the launch environment the probe builds, extras included;
    /// only the variable's presence is checked.
    @Test func theProbeReportsAnInheritedTokenForTheBuiltInAndForExtras() {
        let inherited = ["CLAUDE_CODE_OAUTH_TOKEN": "x", "HOME": "/Users/test"]
        #expect(ClaudeUsageCLIProbe.carriesOAuthToken(inherited: inherited, overrides: [:]))
        #expect(ClaudeUsageCLIProbe.carriesOAuthToken(inherited: inherited, overrides: ["CLAUDE_CONFIG_DIR": "/tmp/x"]))
        #expect(!ClaudeUsageCLIProbe.carriesOAuthToken(inherited: ["HOME": "/Users/test"], overrides: [:]))
        #expect(!ClaudeUsageCLIProbe.carriesOAuthToken(
            inherited: ["CLAUDE_CONFIG_DIR": "/elsewhere"], overrides: ["CLAUDE_CONFIG_DIR": "/tmp/x"]
        ))
        #expect(MockClaudeSource(result: .transientCapture).launchesWithInheritedOAuthToken == false)
    }

    @Test func withNoReaderWiredTheProviderReportsNoIdentityAndNoEmail() async {
        let result = await provider(nil).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.freshness == .live)
        #expect(result.snapshot.identity == nil)
        #expect(result.snapshot.accountEmail == nil)
    }

    /// Each row reads its own file: the built-in `~/.claude.json`, an extra the root of
    /// the `CLAUDE_CONFIG_DIR` its probe is handed.
    @Test func anExtraRowReadsItsOwnConfigHomesFileNotTheDefaultOne() async throws {
        let home = try temporaryDirectory("home")
        let base = try temporaryDirectory("accounts")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: base)
        }
        let extra = ProviderAccount(id: AccountID("claude-work"), providerID: .claude, label: "Work")
        let builtInConfig = ProviderAccountConfiguration.make(for: .builtIn(for: .claude), userHome: home, accountsBase: base)
        let extraConfig = ProviderAccountConfiguration.make(for: extra, userHome: home, accountsBase: base)
        let extraDirectory = try #require(extraConfig.claudeConfigDirectory)
        try FileManager.default.createDirectory(at: extraDirectory, withIntermediateDirectories: true)
        try claudeFile(account: accountA, email: "home@example.com").write(to: home.appendingPathComponent(".claude.json"))
        try claudeFile(account: accountB, email: "work@example.com").write(to: extraDirectory.appendingPathComponent(".claude.json"))

        let builtInReader = ClaudeAccountEmailFileReader(configDirectory: builtInConfig.claudeConfigDirectory, userHome: home)
        let extraReader = ClaudeAccountEmailFileReader(configDirectory: extraDirectory, userHome: home)
        #expect(builtInReader.accountFile.path == home.appendingPathComponent(".claude.json").path)
        #expect(extraReader.accountFile.deletingLastPathComponent().path == extraDirectory.path)

        let builtIn = await ClaudeProvider(source: ScriptedClaudeSource(), emailSource: builtInReader).fetchResult()
        let work = await ClaudeProvider(source: ScriptedClaudeSource(), accountID: extra.id, emailSource: extraReader).fetchResult()
        #expect(builtIn.snapshot.identity == .known(identity(accountA)))
        #expect(builtIn.snapshot.accountEmail == "home@example.com")
        #expect(work.snapshot.identity == .known(identity(accountB)))
        #expect(work.snapshot.accountEmail == "work@example.com")
    }
}

// MARK: U2 at the store: refusal, bound and handoff

@MainActor
struct ClaudeIdentityRefusalTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    private func defaults() -> UserDefaults {
        let suite = "headroom.claude-identity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func store(_ provider: ClaudeProvider, clock: MutableDateSource, reliability: SessionReliabilityRecord? = nil) -> UsageStore {
        UsageStore(
            providers: [provider],
            preferences: Preferences(defaults: defaults()),
            accounts: [.builtIn(for: .claude)],
            sessionReliabilityRecord: reliability,
            now: clock.now
        )
    }

    /// Covers AE6: refused, backoff unchanged, row not dimmed, reliability not noted.
    @Test func aReadingTakenAcrossAClaudeLoginChangeIsRefusedAndReadAgain() async {
        let clock = MutableDateSource(t0)
        let source = ScriptedClaudeSource()
        let reader = ScriptedClaudeIdentity([read(accountA), read(accountA)])
        let provider = ClaudeProvider(source: source, emailSource: reader, now: clock.now)
        let reliability = SessionReliabilityRecord(defaults: defaults(), now: clock.now)
        let store = store(provider, clock: clock, reliability: reliability)
        await store.refreshAll()
        let before = store.snapshot(for: .claude)
        #expect(before.identity == .known(identity(accountA)))
        let observations = reliability.days.map(\.observations).reduce(0, +)

        // The next timer probe meets a change mid-read (A before, B after), then reads
        // B on both sides.
        reader.set([read(accountA), read(accountB), read(accountB), read(accountB)])
        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await store.waitForAccountProbesToFinish()

        #expect(source.captureCount == 3)
        #expect(store.snapshot(for: .claude).freshness == .live)
        #expect(store.snapshot(for: .claude).identity == .known(identity(accountB)))
        #expect(reliability.days.map(\.observations).reduce(0, +) == observations + 1)
        #expect(store.scheduler.identityRefusalTotals[AccountKey(providerID: .claude, accountID: .primary)] == 1)
    }

    @Test func aRefusedReadingLeavesTheRowUntouchedAndDueAtOnce() async {
        let clock = MutableDateSource(t0)
        let source = ScriptedClaudeSource()
        let reader = ScriptedClaudeIdentity([read(accountA), read(accountA)])
        let store = store(ClaudeProvider(source: source, emailSource: reader, now: clock.now), clock: clock)
        await store.refreshAll()
        let before = store.snapshot(for: .claude)

        // Only the very next probe straddles a change; the file then settles on A.
        reader.set([read(accountA), read(accountB), read(accountA)])
        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await store.waitForAccountProbesToFinish()

        // Serial lane: the refused probe is followed at once by a good one. Nothing
        // dimmed in between, and no backoff after.
        #expect(source.captureCount == 3)
        #expect(store.snapshot(for: .claude).freshness == .live)
        #expect(store.snapshot(for: .claude).windows.map(\.utilization) == before.windows.map(\.utilization))
        #expect(store.scheduler.wakeDelay() > 60)
        #expect(store.scheduler.wakeDelay() <= 5 * 60 + 1)
    }

    /// A present but undecodable file: refused twice, then an ordinary transient failure
    /// with normal backoff, and the row goes stale.
    @Test func anUndecodableFileIsRefusedTwiceThenGoesStaleWithBackoff() async {
        let clock = MutableDateSource(t0)
        let source = ScriptedClaudeSource()
        let reader = ScriptedClaudeIdentity([read(accountA), read(accountA)])
        let store = store(ClaudeProvider(source: source, emailSource: reader, now: clock.now), clock: clock)
        await store.refreshAll()

        reader.set([.unreadable])
        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await store.waitForAccountProbesToFinish()

        #expect(source.captureCount == 1 + AccountProbeScheduler.identityRefusalBound + 1)
        #expect(store.snapshot(for: .claude).freshness == .stale(UsageProviderFetchResult.identityUnconfirmedReason))
        #expect(store.snapshot(for: .claude).windows.count == 2)
        #expect(store.scheduler.wakeDelay() > 60)
    }

    /// A handoff is exactly when `.claude.json` is being rewritten; a refusal must never
    /// read as retry exhaustion.
    @Test func aRefusedReadingDuringASignInHandoffDoesNotFailTheSetupSession() async {
        let clock = MutableDateSource(t0)
        let account = ProviderAccount.builtIn(for: .claude)
        let source = ScriptedClaudeSource()
        let reader = ScriptedClaudeIdentity([read(accountA), read(accountB)], cycles: true)
        let store = store(ClaudeProvider(source: source, emailSource: reader, now: clock.now), clock: clock)
        let coordinator = SetupSessionCoordinator(
            retryDelays: [.seconds(60)],
            prepare: { account, mode in .success(PreparedSetupHandoff(accountKey: account.key, mode: mode)) },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
        store.attachSetupCoordinator(coordinator)
        coordinator.begin(for: account)
        for _ in 0..<20 where coordinator.state(for: account.key) != .waiting(attempt: 0) {
            await Task.yield()
        }

        await store.refreshAll()

        // The serial Claude lane re-reads a refused account at once, so a file that never
        // settles reaches the refusal bound inside this refresh and its third reading
        // merges as an ordinary transient failure. The session keeps waiting either way.
        #expect(source.captureCount == 1 + AccountProbeScheduler.identityRefusalBound)
        #expect(store.scheduler.identityRefusalTotals[account.key] == AccountProbeScheduler.identityRefusalBound + 1)
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    /// End to end through the real provider: a Claude default-login change relabels the
    /// built-in row and keeps the previous account as a remembered row.
    @Test func aRealProviderCarriesAClaudeLoginChangeIntoTheRecords() async {
        let rig = DefaultLoginRig(provider: .claude)
        let source = ScriptedClaudeSource()
        let reader = ScriptedClaudeIdentity([read(accountA, email: "work@example.com")])
        let provider = ClaudeProvider(source: source, emailSource: reader, now: rig.clock.now)
        await rig.read(await provider.fetchResult().snapshot)
        rig.store.renameAccount(rig.key, to: "Work")
        #expect(rig.slot?.binding == identity(accountA))

        reader.set([read(accountB, email: "me@gmail.example")])
        rig.advance(120)
        await rig.read(await provider.fetchResult().snapshot)

        #expect(rig.label == "Main")
        #expect(rig.snapshot.accountEmail == "me@gmail.example")
        #expect(rig.store.rememberedAccounts(for: .claude).map(\.label) == ["Work"])
        #expect(rig.store.rememberedAccounts(for: .claude).first?.email == "work@example.com")
    }
}

// MARK: Store level, Claude (R2, R3, R4, R6-R14) with no store changes

@MainActor
struct ClaudeDefaultLoginStoreTests {
    private func boundToWork(_ rig: DefaultLoginRig = DefaultLoginRig(provider: .claude)) async -> DefaultLoginRig {
        await rig.read(rig.reading("work", weeklyUsed: 90))
        rig.store.renameAccount(rig.key, to: "Work")
        return rig
    }

    private func modelRowReading(_ rig: DefaultLoginRig, _ account: String?, fable: Double?) -> UsageSnapshot {
        let base = rig.reading(account, weeklyUsed: 20)
        guard let fable else { return base }
        let row = UsageWindow(
            kind: .other("Weekly (Fable)"),
            utilization: fable,
            resetsAt: DefaultLoginRig.start.addingTimeInterval(5 * 24 * 3_600)
        )
        return base.replacingWindows(base.windows + [row])
    }

    private func fable(_ snapshot: UsageSnapshot) -> UsageWindow? {
        snapshot.windows.first { $0.kind == .other("Weekly (Fable)") }
    }

    /// R2: A to B relabels and keeps no A history; R6: A is remembered with its last reading.
    @Test func aChangeOfClaudeAccountRelabelsAndRemembersTheOldOne() async {
        let rig = await boundToWork()
        let workCapture = rig.clock.now()
        rig.advance(120)
        await rig.read(rig.reading("gmail", weeklyUsed: 3))

        #expect(rig.label == "Main")
        #expect(rig.snapshot.windows.last?.utilization == 3)
        #expect(rig.slot?.binding == rig.identity("gmail"))
        let rows = rig.store.rememberedAccounts(for: .claude)
        #expect(rows.map(\.label) == ["Work"])
        #expect(rows.first?.snapshot?.windows.last?.utilization == 90)
        #expect(rows.first?.lastReadAt == workCapture)
        #expect(rows.first?.key.providerID == .claude)
        #expect(rig.store.displayAccounts(for: .claude).map(\.label) == ["Main", "Work"])
    }

    /// R10: return to A restores its name and retires its remembered row.
    @Test func returningToTheClaudeAccountRestoresIt() async {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading("gmail", weeklyUsed: 3))
        rig.advance(120)
        await rig.read(rig.reading("work", weeklyUsed: 91))

        #expect(rig.label == "Work")
        #expect(rig.snapshot.windows.last?.utilization == 91)
        #expect(rig.store.rememberedAccounts(for: .claude).map(\.label) == ["Account 2"])
    }

    /// R4: a live reading with no readable identity shows under the default name with no
    /// history from the known account, which returns when its identity does.
    @Test func anAbsentClaudeIdentityShowsUnderTheDefaultNameUntilTheAccountReturns() async {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(nil, weeklyUsed: 50))
        #expect(rig.label == "Main")
        #expect(rig.snapshot.windows.last?.utilization == 50)

        rig.advance(120)
        await rig.read(rig.reading("work", weeklyUsed: 92))
        #expect(rig.label == "Work")
    }

    /// R13/R14: the built-in shows as one row with an extra that reads the same Claude
    /// account (Claude's identity is strong).
    @Test func theBuiltInMergesWithAnExtraReadingTheSameClaudeAccount() async {
        let rig = DefaultLoginRig(provider: .claude, extraLabels: ["Account 2"])
        let extraKey = AccountKey(providerID: .claude, accountID: AccountID("account 2"))
        rig.extras[0].set(rig.reading("gmail", weeklyUsed: 31))
        await rig.read(rig.reading("work", weeklyUsed: 90))
        rig.store.renameAccount(rig.key, to: "Esper Labs")
        rig.advance(120)
        await rig.read(rig.reading("gmail", weeklyUsed: 32))

        #expect(rig.store.displayProjection(for: .claude).mergeMap == [rig.key: extraKey])
        let rows = rig.store.displayAccounts(for: .claude)
        #expect(rows.map(\.label) == ["Account 2", "Esper Labs"])
        #expect(rows.map(\.kind) == [.engine, .remembered])
        #expect(rig.store.accounts(for: .claude).map(\.key) == [rig.key, extraKey])
    }

    /// The `BUGS.md` case, in memory: a Claude login switch followed by a partial capture
    /// shows no model row from the previous login.
    @Test func aPartialCaptureAfterAClaudeSwitchKeepsNoModelRowFromThePreviousLogin() async {
        let rig = DefaultLoginRig(provider: .claude)
        await rig.read(modelRowReading(rig, "work", fable: 62))
        #expect(fable(rig.snapshot)?.utilization == 62)

        rig.advance(120)
        await rig.read(modelRowReading(rig, "gmail", fable: nil))
        #expect(fable(rig.snapshot) == nil)
        #expect(rig.snapshot.freshness == .live)

        // What Claude did before its reader was wired: readings with no identity at all,
        // so the switch was invisible and the previous login's row was kept (the bug).
        let unwired = DefaultLoginRig(provider: .claude)
        await unwired.read(modelRowReading(unwired, "work", fable: 62).withIdentity(nil))
        unwired.advance(120)
        await unwired.read(modelRowReading(unwired, "gmail", fable: nil).withIdentity(nil))
        #expect(fable(unwired.snapshot)?.utilization == 62)
    }

    /// Control: the same account's partial capture still keeps its model row, stale.
    @Test func aPartialCaptureOfTheSameClaudeAccountKeepsItsModelRowStale() async {
        let rig = DefaultLoginRig(provider: .claude)
        await rig.read(modelRowReading(rig, "work", fable: 62))
        rig.advance(120)
        await rig.read(modelRowReading(rig, "work", fable: nil))
        let row = fable(rig.snapshot)
        #expect(row?.utilization == 62)
        if case .stale = row?.freshness {} else { Issue.record("expected a stale model row, got \(String(describing: row?.freshness))") }
    }

    /// The `BUGS.md` case across a relaunch: the continuity record from the previous
    /// login lends the new login no model row.
    @Test func aPartialCaptureAfterAClaudeSwitchAcrossARelaunchKeepsNoModelRow() async {
        let rig = DefaultLoginRig(provider: .claude)
        await rig.read(modelRowReading(rig, "work", fable: 62))
        rig.launch()
        #expect(fable(rig.snapshot)?.utilization == 62)

        rig.advance(120)
        await rig.read(modelRowReading(rig, "gmail", fable: nil))
        #expect(fable(rig.snapshot) == nil)

        // And the same account after a relaunch still keeps it.
        let same = DefaultLoginRig(provider: .claude)
        await same.read(modelRowReading(same, "work", fable: 62))
        same.launch()
        same.advance(120)
        await same.read(modelRowReading(same, "work", fable: nil))
        #expect(fable(same.snapshot)?.utilization == 62)
    }
}
