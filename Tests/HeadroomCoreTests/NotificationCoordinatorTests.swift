import Foundation
import Testing
@testable import HeadroomCore

/// U4: the coordinator wired into `UsageStore.merge` (KTD1, KTD2, KTD6) — fresh results
/// only, ledgers written only after an accepted post, and purged with the account.
@MainActor
struct NotificationCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_790_355_600)
    private let codexBuiltIn = AccountKey(providerID: .codex, accountID: .primary)

    private struct Harness {
        let store: UsageStore
        let poster: RecordingNotificationPoster
        let coordinator: NotificationCoordinator
        let ledger: UseItUpLedger
        let baseline: BankedResetNotificationBaseline
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.notification-coordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeHarness(
        providers: [any UsageProvider],
        accounts: [ProviderAccount]? = nil,
        withRegistry: Bool = false,
        providerFactory: (@MainActor (ProviderAccount) -> any UsageProvider)? = nil,
        continuityCache: (any UsageContinuityCaching)? = nil,
        accepts: Bool = true,
        useItUp: Bool = true,
        banked: Bool = false
    ) -> Harness {
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.useItUpRemindersEnabled = useItUp
        preferences.bankedResetNotificationsEnabled = banked
        let poster = RecordingNotificationPoster(accepts: accepts)
        let ledger = UseItUpLedger(defaults: defaults)
        let baseline = BankedResetNotificationBaseline(defaults: defaults)
        let coordinator = NotificationCoordinator(poster: poster, useItUpLedger: ledger, bankedResetBaseline: baseline)
        let clock = MutableDateSource(now)
        let store = UsageStore(
            providers: providers,
            preferences: preferences,
            accounts: accounts,
            accountRegistry: withRegistry ? AccountRegistry(defaults: defaults) : nil,
            accountStorage: NotificationTestStorage(),
            providerFactory: providerFactory,
            continuityCache: continuityCache,
            notificationCoordinator: coordinator,
            now: { clock.now() }
        )
        return Harness(store: store, poster: poster, coordinator: coordinator, ledger: ledger, baseline: baseline)
    }

    /// Weekly at 27% left, 5 hours to reset: only the default 6 hour / 25% rule is due.
    private func dueWeekly(_ providerID: ProviderID, bankedResets: Int? = nil) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [UsageWindow(kind: .weekly, utilization: 73, resetsAt: now.addingTimeInterval(5 * 3_600))],
            planLabel: "plus",
            bankedResets: bankedResets,
            capturedAt: now,
            freshness: .live
        )
    }

    private func settle(_ harness: Harness) async {
        await harness.coordinator.waitForPendingPosts()
    }

    @Test func freshCodexMergePostsOneUseItUpNotification() async throws {
        let harness = makeHarness(providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex))])
        await harness.store.refreshAll()
        await settle(harness)

        let posted = try #require(harness.poster.posted.first)
        #expect(harness.poster.posted.count == 1)
        let epochMinutes = Int(now.addingTimeInterval(5 * 3_600).timeIntervalSince1970 / 60)
        #expect(posted.identifier == "use-it-up.codex.primary.weekly.\(epochMinutes)")
        #expect(posted.threadIdentifier == "codex.primary")
        #expect(posted.title.hasPrefix("27% of Codex"))
        #expect(!posted.title.contains("("))
        #expect(harness.ledger.entry(for: codexBuiltIn, windowID: "weekly") != nil)

        // AE1: the same cycle does not fire again.
        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.count == 1)
    }

    @Test func failedPollWithRetainedWindowsPostsNothing() async {
        let provider = MutableStubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex))
        let harness = makeHarness(providers: [provider], useItUp: false)
        await harness.store.refreshAll()
        harness.store.setUseItUpRemindersEnabled(true)

        provider.set(.stale(for: .codex, reason: .transient("blip")))
        await harness.store.refreshAll()
        await settle(harness)

        #expect(!harness.store.snapshot(for: codexBuiltIn).windows.isEmpty)
        #expect(harness.store.snapshot(for: codexBuiltIn).freshness != .live)
        #expect(harness.poster.posted.isEmpty)
    }

    @Test func launchRestoredSnapshotPostsNothing() async {
        let cache = UsageContinuityCache(defaults: freshDefaults())
        cache.save(dueWeekly(.codex), for: codexBuiltIn)
        let harness = makeHarness(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: .stale(for: .codex, reason: .transient("offline")))],
            continuityCache: cache
        )
        #expect(!harness.store.snapshot(for: codexBuiltIn).windows.isEmpty)
        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.isEmpty)
    }

    @Test func rejectedPostRecordsNothingSoALaterFreshMergeRetries() async {
        let harness = makeHarness(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex, bankedResets: 2))],
            accepts: false,
            banked: true
        )
        harness.baseline.record(count: 1, for: codexBuiltIn)

        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.count == 2)
        #expect(harness.ledger.entries().isEmpty)
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 1)

        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.count == 4)

        harness.poster.setAccepts(true)
        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.count == 6)
        #expect(harness.ledger.entry(for: codexBuiltIn, windowID: "weekly") != nil)
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 2)

        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.count == 6)
    }

    @Test func bankedRiseThroughTheStoreSeedsThenNotifies() async throws {
        let provider = MutableStubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex, bankedResets: 1))
        let harness = makeHarness(providers: [provider], useItUp: false, banked: true)

        // AE5: the first count seeds silently.
        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.isEmpty)
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 1)

        provider.set(dueWeekly(.codex, bankedResets: 2))
        await harness.store.refreshAll()
        await settle(harness)
        let posted = try #require(harness.poster.posted.first)
        #expect(harness.poster.posted.count == 1)
        #expect(posted.identifier == "codex-banked.primary.2")
        #expect(posted.threadIdentifier == "codex.primary")
        #expect(posted.title == "Codex banked a reset")
        #expect(posted.body == "You now have 2 banked resets.")
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 2)
    }

    @Test func removingACodexAccountPurgesBothLedgers() async throws {
        let harness = makeHarness(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex, bankedResets: 1))],
            withRegistry: true,
            providerFactory: { account in
                NotificationAccountStub(id: account.providerID, accountID: account.id, snapshot: self.dueWeekly(.codex, bankedResets: 3))
            },
            banked: true
        )
        let added = try #require(harness.store.addAccount(for: .codex))
        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.ledger.entry(for: added.key, windowID: "weekly") != nil)
        #expect(harness.baseline.baselineCount(for: added.key) == 3)

        #expect(await harness.store.removeAccount(added.key) == .removed)
        #expect(harness.ledger.entry(for: added.key, windowID: "weekly") == nil)
        #expect(harness.baseline.baselineCount(for: added.key) == nil)
        #expect(harness.ledger.entry(for: codexBuiltIn, windowID: "weekly") != nil)
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 1)
    }

    @Test func signOutAndSetUpAgainPurgesBothLedgers() async {
        let harness = makeHarness(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex, bankedResets: 1))],
            banked: true
        )
        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.ledger.entry(for: codexBuiltIn, windowID: "weekly") != nil)
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 1)

        harness.store.invalidateUsageForAccountReset(codexBuiltIn)
        #expect(harness.ledger.entries().isEmpty)
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == nil)
    }

    @Test func twoClaudeAccountsEachGetALabelledNotification() async {
        let work = AccountID("work")
        let harness = makeHarness(
            providers: [
                NotificationAccountStub(id: .claude, accountID: .primary, snapshot: dueWeekly(.claude)),
                NotificationAccountStub(id: .claude, accountID: work, snapshot: dueWeekly(.claude)),
            ],
            accounts: [
                ProviderAccount(id: .primary, providerID: .claude, label: "Personal", isBuiltIn: true),
                ProviderAccount(id: work, providerID: .claude, label: "Work"),
            ]
        )
        await harness.store.refreshAll()
        await settle(harness)

        let posted = harness.poster.posted
        #expect(posted.count == 2)
        #expect(Set(posted.map(\.threadIdentifier)) == ["claude.primary", "claude.work"])
        #expect(posted.contains { $0.threadIdentifier == "claude.primary" && $0.title.contains("Personal") })
        #expect(posted.contains { $0.threadIdentifier == "claude.work" && $0.title.contains("Work") })
    }

    @Test func capabilityFailureNeverReachesTheCoordinator() async {
        let harness = makeHarness(providers: [
            CapabilityStubProvider(
                id: .claude,
                accountID: .primary,
                displayName: "Claude",
                result: UsageProviderFetchResult(snapshot: dueWeekly(.claude), capability: .inconclusive(.shellTimeout))
            ),
        ])
        await harness.store.refreshAll()
        await settle(harness)
        #expect(harness.poster.posted.isEmpty)
        #expect(harness.ledger.entries().isEmpty)
    }

    @Test func secondMergeWhilePostIsInFlightPostsOnce() async {
        let harness = makeHarness(providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex))])
        let generation = harness.store.schedulerAttachmentGeneration(for: codexBuiltIn)
        let result = UsageProviderFetchResult(snapshot: dueWeekly(.codex))
        harness.poster.gate.suspendNextFetch()

        #expect(harness.store.schedulerMerge(key: codexBuiltIn, result: result, attachmentGeneration: generation))
        #expect(harness.store.schedulerMerge(key: codexBuiltIn, result: result, attachmentGeneration: generation))
        await harness.poster.gate.waitUntilStarted()
        #expect(harness.poster.posted.count == 1)

        harness.poster.gate.release()
        await settle(harness)
        #expect(harness.poster.posted.count == 1)
        #expect(harness.ledger.entry(for: codexBuiltIn, windowID: "weekly") != nil)
    }

    @Test func secondBankedMergeWhilePostIsInFlightPostsOnce() async {
        let harness = makeHarness(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: dueWeekly(.codex, bankedResets: 2))],
            useItUp: false,
            banked: true
        )
        harness.baseline.record(count: 1, for: codexBuiltIn)
        let generation = harness.store.schedulerAttachmentGeneration(for: codexBuiltIn)
        let result = UsageProviderFetchResult(snapshot: dueWeekly(.codex, bankedResets: 2))
        harness.poster.gate.suspendNextFetch()

        harness.store.schedulerMerge(key: codexBuiltIn, result: result, attachmentGeneration: generation)
        harness.store.schedulerMerge(key: codexBuiltIn, result: result, attachmentGeneration: generation)
        await harness.poster.gate.waitUntilStarted()
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 1)

        harness.poster.gate.release()
        await settle(harness)
        #expect(harness.poster.posted.count == 1)
        #expect(harness.baseline.baselineCount(for: codexBuiltIn) == 2)
    }

    @Test func accountRemovedWhileItsPostIsPendingLeavesNoLedgerEntry() async throws {
        let harness = makeHarness(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: .stale(for: .codex, reason: .transient("idle")))],
            withRegistry: true,
            providerFactory: { account in
                NotificationAccountStub(id: account.providerID, accountID: account.id, snapshot: self.dueWeekly(.codex))
            }
        )
        let added = try #require(harness.store.addAccount(for: .codex))
        let generation = harness.store.schedulerAttachmentGeneration(for: added.key)
        harness.poster.gate.suspendNextFetch()

        #expect(harness.store.schedulerMerge(
            key: added.key,
            result: UsageProviderFetchResult(snapshot: dueWeekly(.codex)),
            attachmentGeneration: generation
        ))
        await harness.poster.gate.waitUntilStarted()
        #expect(await harness.store.removeAccount(added.key) == .removed)

        harness.poster.gate.release()
        await settle(harness)
        #expect(harness.poster.posted.count == 1)
        #expect(harness.ledger.entry(for: added.key, windowID: "weekly") == nil)
    }
}

/// Account-scoped provider double for the multi-account and lifecycle scenarios.
private final class NotificationAccountStub: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName = "P"
    private let lock = NSLock()
    private var snapshot: UsageSnapshot

    init(id: ProviderID, accountID: AccountID, snapshot: UsageSnapshot) {
        self.id = id
        self.accountID = accountID
        self.snapshot = snapshot
    }

    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { snapshot } }
}

/// No-op storage so these tests never touch the real Application Support tree.
private struct NotificationTestStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .success(()) }
}
