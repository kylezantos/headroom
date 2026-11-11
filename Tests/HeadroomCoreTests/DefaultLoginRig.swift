import Foundation
@testable import HeadroomCore

/// Provider double for the default-login suites: returns whatever snapshot the test set.
final class ScriptedAccountProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    private let lock = NSLock()
    private var snapshot: UsageSnapshot

    init(id: ProviderID, accountID: AccountID = .primary) {
        self.id = id
        self.accountID = accountID
        self.displayName = id.displayName
        self.snapshot = .pending(for: id)
    }

    func set(_ snapshot: UsageSnapshot) { lock.withLock { self.snapshot = snapshot } }
    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { snapshot } }
}

private struct RigAccountStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .success(()) }
}

/// One Codex install across launches: a real registry, continuity cache, reminder stores
/// and record store over one throwaway defaults suite. `launch()` builds a new store on
/// the same suite, which is a relaunch; `launch(records: false)` is an older build.
@MainActor
final class DefaultLoginRig {
    static let start = Date(timeIntervalSince1970: 1_790_355_600)

    let defaults: UserDefaults
    let clock = MutableDateSource(DefaultLoginRig.start)
    let poster = RecordingNotificationPoster()
    let primary = ScriptedAccountProvider(id: .codex)
    let extras: [ScriptedAccountProvider]
    let registry: AccountRegistry
    let ledger: UseItUpLedger
    let baseline: BankedResetNotificationBaseline
    let acknowledgements: BankedResetAcknowledgements
    let continuity: UsageContinuityCache
    let records: DefaultLoginRecordStore
    private(set) var store: UsageStore!
    private(set) var coordinator: NotificationCoordinator!

    let key = AccountKey(providerID: .codex, accountID: .primary)

    init(extraLabels: [String] = [], banked: Bool = false) {
        let suite = "headroom.default-login.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        self.defaults = defaults
        registry = AccountRegistry(defaults: defaults)
        ledger = UseItUpLedger(defaults: defaults)
        baseline = BankedResetNotificationBaseline(defaults: defaults)
        acknowledgements = BankedResetAcknowledgements(defaults: defaults)
        continuity = UsageContinuityCache(defaults: defaults)
        records = DefaultLoginRecordStore(defaults: defaults)
        let extraAccounts = extraLabels.map {
            ProviderAccount(id: AccountID($0.lowercased()), providerID: .codex, label: $0)
        }
        if !extraAccounts.isEmpty { registry.seed([.builtIn(for: .codex)] + extraAccounts) }
        extras = extraAccounts.map { ScriptedAccountProvider(id: .codex, accountID: $0.id) }
        let preferences = Preferences(defaults: defaults)
        preferences.useItUpRemindersEnabled = true
        preferences.bankedResetNotificationsEnabled = banked
        launch()
    }

    func launch(records usesRecords: Bool = true) {
        coordinator = NotificationCoordinator(poster: poster, useItUpLedger: ledger, bankedResetBaseline: baseline)
        store = UsageStore(
            providers: [primary] + extras,
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: RigAccountStorage(),
            providerFactory: { [primary] _ in primary },
            continuityCache: continuity,
            defaultLoginRecords: usesRecords ? records : nil,
            bankedResetAcknowledgements: acknowledgements,
            notificationCoordinator: coordinator,
            now: clock.now
        )
    }

    /// One poll: `snapshot` is what the built-in row's provider returns.
    func read(_ snapshot: UsageSnapshot) async {
        primary.set(snapshot)
        await store.refreshAll()
        await coordinator.waitForPendingPosts()
    }

    func advance(_ seconds: TimeInterval) { clock.set(clock.now().addingTimeInterval(seconds)) }

    var label: String { store.accounts(for: .codex).first { $0.key == key }?.label ?? "" }
    var snapshot: UsageSnapshot { store.snapshot(for: key) }
    var state: DefaultLoginRecordsState { store.defaultLoginState ?? DefaultLoginRecordsState() }
    var slot: SlotRecord? { state.slot(for: key) }
    /// Remembered accounts that have a row.
    var rows: [RememberedAccount] { state.remembered.filter(\.hasRow) }

    // MARK: Fixtures

    static func identity(_ account: String) -> AccountIdentity {
        AccountIdentity.codex(accountID: account)!
    }

    /// A live Codex reading for `account` (nil: the file names no account). Its weekly
    /// reset is days away, so no use-it-up reminder is due.
    func reading(
        _ account: String?,
        weeklyUsed: Double = 10,
        banked: Int? = nil,
        email: String?? = nil,
        identity: AccountIdentityOutcome?? = nil,
        weeklyResetIn: TimeInterval = 5 * 24 * 3_600
    ) -> UsageSnapshot {
        let now = clock.now()
        let outcome: AccountIdentityOutcome? = identity ?? (account.map { .known(Self.identity($0)) } ?? .absent)
        return UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(kind: .fiveHour, utilization: 99, resetsAt: Self.start.addingTimeInterval(4 * 3_600)),
                UsageWindow(kind: .weekly, utilization: weeklyUsed, resetsAt: Self.start.addingTimeInterval(weeklyResetIn)),
            ],
            planLabel: "plus",
            accountEmail: email ?? account.map { "\($0)@example.com" },
            bankedResets: banked,
            capturedAt: now,
            freshness: .live,
            identity: outcome
        )
    }

    /// Weekly at 27% left with 5 hours to its reset: the default 6 hour / 25% rule fires.
    func dueReading(_ account: String?) -> UsageSnapshot {
        reading(account, weeklyUsed: 73, weeklyResetIn: 5 * 3_600)
    }

    /// What a build from before identities wrote: no identity on the reading.
    func legacyReading(email: String?, weeklyUsed: Double = 10) -> UsageSnapshot {
        reading(nil, weeklyUsed: weeklyUsed, email: .some(email), identity: .some(nil))
    }

    var signedOut: UsageSnapshot { .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)) }
    var blip: UsageSnapshot { .stale(for: .codex, reason: .transient("blip")) }
}
