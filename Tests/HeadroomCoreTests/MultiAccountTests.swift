import Foundation
import Testing
@testable import HeadroomCore

/// Provider double bound to one (provider, account) pair.
private struct AccountStubProvider: UsageProvider {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    let snapshot: UsageSnapshot
    let accountCapacity: Int
    let reportsProviderCapability: Bool
    let capability: ProviderCapabilityState

    init(
        id: ProviderID,
        accountID: AccountID,
        displayName: String,
        snapshot: UsageSnapshot,
        accountCapacity: Int = AccountRegistry.testedEnvelope,
        reportsProviderCapability: Bool = false,
        capability: ProviderCapabilityState = .available
    ) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.snapshot = snapshot
        self.accountCapacity = accountCapacity
        self.reportsProviderCapability = reportsProviderCapability
        self.capability = capability
    }

    func fetchSnapshot() async -> UsageSnapshot { snapshot }

    func fetchResult() async -> UsageProviderFetchResult {
        UsageProviderFetchResult(
            snapshot: snapshot,
            capability: reportsProviderCapability ? capability : nil
        )
    }
}

private func freshDefaults() -> UserDefaults {
    let suite = "headroom.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func window(_ kind: WindowKind, used: Double) -> UsageWindow {
    UsageWindow(kind: kind, utilization: used, resetsAt: Date(timeIntervalSince1970: 3_000_000))
}

/// No-op storage so account-lifecycle tests never touch the real Application
/// Support tree (AGENTS.md: suite is all mocked).
private struct NoopAccountStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .success(()) }
}

private final class FailingRemovalStorage: AccountStorageManaging, @unchecked Sendable {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .failure(.removeFailed) }
}

private struct ActiveSetupRemovalStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .failure(.setupActive) }
}

/// Records every on-disk removal so stop-tracking tests can prove the CLI's own
/// config home is never touched.
private final class RecordingRemovalStorage: AccountStorageManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var removed: [AccountKey] = []
    var removedKeys: [AccountKey] { lock.withLock { removed } }

    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> {
        lock.withLock { removed.append(account.key) }
        return .success(())
    }
}

private struct ActiveHandoffStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func setupHandoffIsActive(for account: ProviderAccount) async -> Bool { true }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .success(()) }
}

private actor FetchConcurrencyProbe {
    private var active = 0
    private(set) var maximum = 0

    func begin() {
        active += 1
        maximum = max(maximum, active)
    }

    func end() { active -= 1 }
}

private struct ProbedAccountProvider: UsageProvider {
    let id: ProviderID
    let accountID: AccountID
    let displayName = "P"
    let pollingLane: ProviderPollingLane = .serial("claude-cli")
    let probe: FetchConcurrencyProbe

    func fetchSnapshot() async -> UsageSnapshot {
        await probe.begin()
        try? await Task.sleep(for: .milliseconds(40))
        await probe.end()
        return .live(id, windows: [window(.weekly, used: 20)])
    }
}

private final class SuspendedAccountProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName = "P"
    let pollingLane: ProviderPollingLane
    let reportsProviderCapability: Bool
    let capability: ProviderCapabilityState
    private let lock = NSLock()
    private var count = 0
    private var started: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var shouldRelease = false

    init(
        id: ProviderID,
        accountID: AccountID,
        pollingLane: ProviderPollingLane = .concurrent,
        reportsProviderCapability: Bool = false,
        capability: ProviderCapabilityState = .available
    ) {
        self.id = id
        self.accountID = accountID
        self.pollingLane = pollingLane
        self.reportsProviderCapability = reportsProviderCapability
        self.capability = capability
    }

    var fetchCount: Int { lock.withLock { count } }

    func waitUntilStarted() async {
        if lock.withLock({ didStart }) { return }
        await withCheckedContinuation { continuation in
            var immediate = false
            lock.withLock {
                if didStart { immediate = true } else { started = continuation }
            }
            if immediate { continuation.resume() }
        }
    }

    func releaseFetches() {
        let continuation = lock.withLock {
            shouldRelease = true
            let pending = release
            release = nil
            return pending
        }
        continuation?.resume()
    }

    func suspendNextFetch() {
        lock.withLock {
            shouldRelease = false
            didStart = false
        }
    }

    func fetchSnapshot() async -> UsageSnapshot {
        let start = lock.withLock {
            count += 1
            didStart = true
            let pending = started
            started = nil
            return pending
        }
        start?.resume()
        if !lock.withLock({ shouldRelease }) {
            await withCheckedContinuation { continuation in
                var immediate = false
                lock.withLock {
                    if shouldRelease { immediate = true } else { release = continuation }
                }
                if immediate { continuation.resume() }
            }
        }
        return .live(id, windows: [window(.weekly, used: 20)])
    }

    func fetchResult() async -> UsageProviderFetchResult {
        UsageProviderFetchResult(
            snapshot: await fetchSnapshot(),
            capability: reportsProviderCapability ? capability : nil
        )
    }
}

@MainActor
private final class IgnoringSetupScheduler: SetupRetryScheduling {
    private final class Cancellation: SetupRetryCancellation {
        func cancel() {}
    }

    func schedule(
        after _: Duration,
        operation _: @escaping @MainActor @Sendable () -> Void
    ) -> any SetupRetryCancellation {
        Cancellation()
    }
}

// MARK: - Registry

@Suite struct AccountRegistryTests {
    @Test func seedsBuiltInAccountFirst() {
        let registry = AccountRegistry(defaults: freshDefaults())
        let accounts = registry.accounts(for: .claude)
        #expect(accounts.count == 1)
        #expect(accounts[0].isBuiltIn)
        #expect(accounts[0].id == .primary)
    }

    @Test func addAssignsSequentialDefaultLabels() {
        let registry = AccountRegistry(defaults: freshDefaults())
        let second = registry.addAccount(for: .claude)
        let third = registry.addAccount(for: .claude)
        #expect(second?.label == "Account 2")
        #expect(third?.label == "Account 3")
        #expect(registry.accounts(for: .claude).map(\.label) == ["Main", "Account 2", "Account 3"])
    }

    @Test func capsAtTheProviderCapacityIndependently() {
        // KTD10: the registry enforces whatever capacity the provider passes.
        let registry = AccountRegistry(defaults: freshDefaults())
        for _ in 0..<4 { #expect(registry.addAccount(for: .claude, capacity: 5) != nil) }
        #expect(!registry.canAddAccount(for: .claude, capacity: 5))
        #expect(registry.addAccount(for: .claude, capacity: 5) == nil)
        // The Codex cap is its own budget.
        #expect(registry.canAddAccount(for: .codex, capacity: 5))
        #expect(registry.addAccount(for: .codex, capacity: 5) != nil)
    }

    @Test func renamePersistsAndTrims() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let account = registry.addAccount(for: .codex)!
        registry.renameAccount(account.key, to: "  Work \n")
        #expect(AccountRegistry(defaults: defaults).accounts(for: .codex).last?.label == "Work")
        // Blank rename is a no-op, not an empty label.
        registry.renameAccount(account.key, to: "   ")
        #expect(AccountRegistry(defaults: defaults).accounts(for: .codex).last?.label == "Work")
    }

    @Test func removeDeletesExtraButNeverBuiltIn() {
        let registry = AccountRegistry(defaults: freshDefaults())
        let extra = registry.addAccount(for: .claude)!
        registry.removeAccount(extra.key)
        #expect(registry.accounts(for: .claude).count == 1)
        registry.removeAccount(AccountKey(providerID: .claude, accountID: .primary))
        #expect(registry.accounts(for: .claude).count == 1) // built-in survives
    }

    @Test func builtInCanBeRenamed() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        registry.renameAccount(AccountKey(providerID: .claude, accountID: .primary), to: "Personal")
        let accounts = AccountRegistry(defaults: defaults).accounts(for: .claude)
        #expect(accounts[0].isBuiltIn)
        #expect(accounts[0].label == "Personal")
    }

    @Test func malformedPersistedCatalogIsCanonicalized() {
        let registry = AccountRegistry(defaults: freshDefaults())
        let duplicate = AccountID("work")
        registry.seed([
            ProviderAccount(id: duplicate, providerID: .claude, label: "Work"),
            ProviderAccount(id: duplicate, providerID: .claude, label: "Duplicate"),
            ProviderAccount(id: .primary, providerID: .claude, label: "Personal"),
            ProviderAccount(id: AccountID("other-built-in"), providerID: .claude,
                            label: "Wrong built-in", isBuiltIn: true),
        ])

        let accounts = registry.accounts(for: .claude)
        #expect(accounts.map(\.id) == [.primary, duplicate])
        #expect(accounts[0].isBuiltIn)
        #expect(accounts[0].label == "Personal")
        #expect(accounts[1].label == "Work")
    }

    @Test func stopTrackingHidesBuiltInAcrossReload() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        #expect(registry.canStopTrackingBuiltIn(for: .claude))
        #expect(registry.stopTrackingBuiltIn(for: .claude))
        #expect(registry.accounts(for: .claude).map(\.id) == [extra.id])
        // The tombstone is persisted state, not an in-memory flag — a fresh registry
        // (relaunch / registry reconstruction) must not resurrect the built-in row.
        #expect(AccountRegistry(defaults: defaults).accounts(for: .claude).map(\.id) == [extra.id])
    }

    @Test func stopTrackingRefusedWhenBuiltInIsOnlyAccount() {
        let registry = AccountRegistry(defaults: freshDefaults())
        #expect(!registry.canStopTrackingBuiltIn(for: .claude))
        #expect(!registry.stopTrackingBuiltIn(for: .claude))
        #expect(registry.accounts(for: .claude).map(\.id) == [.primary])
    }

    @Test func resumeTrackingRestoresBuiltInFirstWithItsLabel() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        registry.renameAccount(AccountKey(providerID: .claude, accountID: .primary), to: "Personal")
        let extra = registry.addAccount(for: .claude)!
        #expect(registry.stopTrackingBuiltIn(for: .claude))
        #expect(registry.resumeTrackingBuiltIn(for: .claude))
        let accounts = AccountRegistry(defaults: defaults).accounts(for: .claude)
        #expect(accounts.map(\.id) == [.primary, extra.id])
        #expect(accounts.first?.label == "Personal")
    }

    @Test func removingLastExtraClearsTombstone() {
        let registry = AccountRegistry(defaults: freshDefaults())
        let extra = registry.addAccount(for: .claude)!
        #expect(registry.stopTrackingBuiltIn(for: .claude))
        registry.removeAccount(extra.key)
        // The built-in is the only possible row again, and the cleared tombstone means
        // a future extra must not silently re-hide it.
        #expect(registry.accounts(for: .claude).map(\.id) == [.primary])
        #expect(!registry.isBuiltInHidden(for: .claude))
        let second = registry.addAccount(for: .claude)!
        #expect(registry.accounts(for: .claude).map(\.id) == [.primary, second.id])
    }

    @Test func orphanedTombstoneSelfHealsAndDoesNotHideBuiltInOnNextAdd() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        #expect(registry.stopTrackingBuiltIn(for: .claude))
        // Simulate a crash between removeAccount's two writes: the catalog loses the
        // extra but the tombstone-clearing write never lands. seed() writes only the
        // catalog key, leaving the now-orphaned tombstone in defaults.
        registry.seed([.builtIn(for: .claude)])
        #expect(!registry.accounts(for: .claude).contains { $0.id == extra.id })

        // Relaunch: the built-in is visible, and reading self-heals the tombstone.
        let relaunched = AccountRegistry(defaults: defaults)
        #expect(relaunched.accounts(for: .claude).map(\.id) == [.primary])
        #expect(!relaunched.isBuiltInHidden(for: .claude))
        // The stale tombstone must not ambush the next add by re-hiding the built-in.
        let second = relaunched.addAccount(for: .claude)!
        #expect(relaunched.accounts(for: .claude).map(\.id) == [.primary, second.id])
    }

    @Test func hiddenBuiltInStillCountsTowardCap() {
        let registry = AccountRegistry(defaults: freshDefaults())
        for _ in 0..<4 { #expect(registry.addAccount(for: .claude, capacity: 5) != nil) }
        #expect(registry.stopTrackingBuiltIn(for: .claude))
        // The hidden built-in keeps its slot so resuming can never overflow the cap.
        #expect(!registry.canAddAccount(for: .claude, capacity: 5))
        #expect(registry.addAccount(for: .claude, capacity: 5) == nil)
        #expect(registry.resumeTrackingBuiltIn(for: .claude))
        #expect(registry.accounts(for: .claude, capacity: 5).count == 5)
    }

    @Test func tombstoneIsPerProvider() {
        let registry = AccountRegistry(defaults: freshDefaults())
        _ = registry.addAccount(for: .claude)
        _ = registry.addAccount(for: .codex)
        #expect(registry.stopTrackingBuiltIn(for: .claude))
        #expect(registry.isBuiltInHidden(for: .claude))
        #expect(!registry.isBuiltInHidden(for: .codex))
        #expect(registry.accounts(for: .codex).first?.id == .primary)
    }

    @Test func promotedPrimaryIsFirstAndPersistsAcrossRegistryRecreation() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!

        #expect(registry.promote(extra.key))
        #expect(registry.accounts(for: .claude).map(\.id) == [extra.id, .primary])
        #expect(AccountRegistry(defaults: defaults).accounts(for: .claude).map(\.id) == [extra.id, .primary])
    }

    @Test func danglingPrimaryPointerFallsBackWithoutWritingDefaults() throws {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        let survivor = registry.addAccount(for: .claude)!
        #expect(registry.promote(extra.key))
        registry.removeAccount(extra.key)
        let before = try #require(defaults.data(forKey: "primaryAccounts.v1"))

        #expect(registry.accounts(for: .claude).map(\.id) == [.primary, survivor.id])
        #expect(defaults.data(forKey: "primaryAccounts.v1") == before)
    }

    @Test func promotedExtraStaysPrimaryAcrossBuiltInStopAndResume() {
        let registry = AccountRegistry(defaults: freshDefaults())
        let extra = registry.addAccount(for: .claude)!
        #expect(registry.promote(extra.key))

        #expect(registry.stopTrackingBuiltIn(for: .claude))
        #expect(registry.accounts(for: .claude).map(\.id) == [extra.id])
        #expect(registry.resumeTrackingBuiltIn(for: .claude))
        #expect(registry.accounts(for: .claude).map(\.id) == [extra.id, .primary])
    }

    @Test func primaryPointerDoesNotChangeCapacityAndCannotPromoteUnknownAccount() throws {
        let registry = AccountRegistry(defaults: freshDefaults())
        var last: ProviderAccount?
        for _ in 0..<4 { last = registry.addAccount(for: .claude, capacity: 5) }
        let promoted = try #require(last)

        #expect(registry.promote(promoted.key))
        #expect(!registry.canAddAccount(for: .claude, capacity: 5))
        #expect(!registry.promote(AccountKey(providerID: .claude, accountID: AccountID("missing"))))
    }

    @Test func storageComponentsCannotTraverseOutOfAccountRoot() {
        #expect(AccountStorage.safePathComponent("../victim") == "%2E%2E%2Fvictim")
        #expect(AccountStorage.safePathComponent("normal-id_1") == "normal-id_1")
        let account = ProviderAccount(
            id: AccountID("../victim"), providerID: ProviderID("../../provider"), label: "Bad"
        )
        let base = AccountStorage.baseDirectoryURL.standardizedFileURL.path + "/"
        let resolved = AccountStorage.accountDirectoryURL(for: account).standardizedFileURL.path
        #expect(resolved.hasPrefix(base))
    }
}

// MARK: - Store

@MainActor
@Suite struct MultiAccountStoreTests {
    @MainActor
    @Test func storeForwardsConfirmedCapabilityFailureToVerifyingCoordinator() async {
        let account = ProviderAccount.builtIn(for: .claude)
        let store = UsageStore(
            providers: [
                AccountStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    snapshot: .stale(for: .claude, reason: .transient("capability unavailable")),
                    reportsProviderCapability: true,
                    capability: .confirmedAbsent
                ),
            ],
            preferences: Preferences(defaults: freshDefaults())
        )
        let coordinator = SetupSessionCoordinator(
            scheduler: IgnoringSetupScheduler(),
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
        store.attachSetupCoordinator(coordinator)
        coordinator.handoffDidEnd(account.key)

        await store.refreshAll()

        #expect(coordinator.state(for: account.key) == .failed(.providerCapability(.confirmedAbsent)))
        #expect(store.snapshot(for: account.key).freshness == .pending)
    }

    @Test func accountRefreshForwardsInconclusiveCapabilityWithoutSettlingEarly() async {
        let account = ProviderAccount.builtIn(for: .claude)
        let store = UsageStore(
            providers: [
                AccountStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    snapshot: .stale(for: .claude, reason: .transient("capability unavailable")),
                    reportsProviderCapability: true,
                    capability: .inconclusive(.shellTimeout)
                ),
            ],
            preferences: Preferences(defaults: freshDefaults())
        )
        let coordinator = SetupSessionCoordinator(
            scheduler: IgnoringSetupScheduler(),
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
        store.attachSetupCoordinator(coordinator)
        coordinator.handoffDidEnd(account.key)

        await store.refreshAccount(account.key)

        #expect(coordinator.state(for: account.key) == .verifying)
        #expect(store.providerCapabilities[.claude]?.state == .inconclusive(.shellTimeout))
    }
    @Test func sharedClaudeCapabilityKeepsAccountRecoveryIndependent() async {
        let work = AccountID("work")
        let store = UsageStore(
            providers: [
                CapabilityStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    result: UsageProviderFetchResult(
                        snapshot: .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)),
                        capability: .available
                    )
                ),
                CapabilityStubProvider(
                    id: .claude,
                    accountID: work,
                    displayName: "Claude",
                    result: UsageProviderFetchResult(
                        snapshot: .stale(for: .claude, reason: .providerSetup(.claudeTrustRequired)),
                        capability: .available
                    )
                ),
            ],
            preferences: Preferences(defaults: freshDefaults())
        )

        await store.refreshAll()

        #expect(store.providerCapabilities.count == 1)
        #expect(store.providerCapabilities[.claude]?.state == .available)
        #expect(
            store.snapshot(for: AccountKey(providerID: .claude, accountID: .primary))
                .freshness == .stale(.providerSetup(.claudeLoginRequired))
        )
        #expect(
            store.snapshot(for: AccountKey(providerID: .claude, accountID: work))
                .freshness == .stale(.providerSetup(.claudeTrustRequired))
        )
    }

    @Test func sharedClaudeCapabilityUsesLatestSerialObservation() async {
        let work = AccountID("work")
        let store = UsageStore(
            providers: [
                CapabilityStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    result: UsageProviderFetchResult(
                        snapshot: .stale(for: .claude, reason: .transient("capability unavailable")),
                        capability: .confirmedAbsent
                    )
                ),
                CapabilityStubProvider(
                    id: .claude,
                    accountID: work,
                    displayName: "Claude",
                    result: UsageProviderFetchResult(
                        snapshot: .live(.claude, windows: [window(.weekly, used: 20)]),
                        capability: .available
                    )
                ),
            ],
            preferences: Preferences(defaults: freshDefaults())
        )

        await store.refreshAll()

        #expect(store.providerCapabilities[.claude]?.state == .available)
    }

    private let work = AccountID("work")

    private func twoAccountStore(
        workSnapshot: UsageSnapshot,
        primarySnapshot: UsageSnapshot? = nil
    ) -> UsageStore {
        let accounts = [
            ProviderAccount.builtIn(for: .claude),
            ProviderAccount(id: work, providerID: .claude, label: "Work"),
        ]
        return UsageStore(
            providers: [
                AccountStubProvider(
                    id: .claude, accountID: .primary, displayName: "Claude",
                    snapshot: primarySnapshot ?? .live(.claude, windows: [window(.weekly, used: 30)])
                ),
                AccountStubProvider(id: .claude, accountID: work, displayName: "Claude", snapshot: workSnapshot),
            ],
            preferences: Preferences(defaults: freshDefaults()),
            accounts: accounts
        )
    }

    @Test func snapshotsAreKeyedPerAccount() async {
        let store = twoAccountStore(
            workSnapshot: .live(.claude, windows: [window(.weekly, used: 80)])
        )
        await store.refreshAll()
        let primary = store.snapshot(for: AccountKey(providerID: .claude, accountID: .primary))
        let secondary = store.snapshot(for: AccountKey(providerID: .claude, accountID: work))
        #expect(primary.windows.first?.utilization == 30)
        #expect(secondary.windows.first?.utilization == 80)
        // providerOrder still lists Claude once.
        #expect(store.providerOrder == [.claude])
    }

    @Test func oneAccountFailureNeverTouchesItsSibling() async {
        let store = twoAccountStore(
            workSnapshot: .stale(for: .claude, reason: .needsReauth("sign in"))
        )
        await store.refreshAll()
        let primary = store.snapshot(for: AccountKey(providerID: .claude, accountID: .primary))
        #expect(primary.freshness == .live)
        if case .stale = store.snapshot(for: AccountKey(providerID: .claude, accountID: work)).freshness {
        } else {
            Issue.record("work account should be stale")
        }
    }

    @Test func menuBarFollowsPrimaryAccountOnly() async {
        let preferences = Preferences(defaults: freshDefaults())
        preferences.menuBarFillSource = .claude
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
                AccountStubProvider(id: .claude, accountID: work, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 95)])),
            ],
            preferences: preferences,
            accounts: [
                .builtIn(for: .claude),
                ProviderAccount(id: work, providerID: .claude, label: "Work"),
            ]
        )
        await store.refreshAll()
        // 30% used → 70% remaining, from the built-in account — not the 95%-used extra.
        #expect(store.menuBarSummary.text == "70%")
    }

    @Test func promotionReordersPrimaryConsumersAndExportsImmediately() async {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        let widgetExporter = SpyWidgetExporter()
        let phoneExporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
                AccountStubProvider(id: .claude, accountID: extra.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 95)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .pending(for: account.providerID))
            },
            widgetExporter: widgetExporter,
            phoneSyncExporter: phoneExporter
        )
        await store.refreshAll()
        let widgetBaseline = widgetExporter.exports.count
        let phoneBaseline = phoneExporter.exports.count

        #expect(store.promoteAccount(extra.key))
        #expect(store.primaryAccount(for: .claude)?.key == extra.key)
        #expect(store.snapshot(for: .claude).windows.first?.utilization == 95)
        #expect(store.menuBarSummary.text == "5%")
        #expect(widgetExporter.exports.count == widgetBaseline + 1)
        #expect(phoneExporter.exports.count == phoneBaseline + 1)
    }

    @Test func storeRestoresPersistedPrimaryOrderRegardlessOfProviderConstructionOrder() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        #expect(registry.promote(extra.key))

        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .pending(for: .claude)),
                AccountStubProvider(id: .claude, accountID: extra.id, displayName: "Claude",
                                    snapshot: .pending(for: .claude)),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .pending(for: account.providerID))
            }
        )

        #expect(store.accounts(for: .claude).map(\.id) == [extra.id, .primary])
        #expect(store.primaryAccount(for: .claude)?.key == extra.key)
    }

    @Test func promotionRefreshesOnlyThePromotedAccount() async {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extraAccount = registry.addAccount(for: .claude)!
        let builtIn = SuspendedAccountProvider(id: .claude, accountID: .primary)
        let extra = SuspendedAccountProvider(id: .claude, accountID: extraAccount.id)
        let store = UsageStore(
            providers: [builtIn, extra],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .pending(for: account.providerID))
            }
        )

        #expect(store.promoteAccount(extraAccount.key))
        await extra.waitUntilStarted()
        #expect(builtIn.fetchCount == 0)
        #expect(extra.fetchCount == 1)
        extra.releaseFetches()
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func neverSignedInExemptionFollowsPrimaryPositionInsteadOfBuiltInIdentity() {
        // KTD5 (2026-09-19 polling plan): the four-interval wait keys off whichever row is
        // the selected primary, not the built-in identity, so a promoted extra stays on
        // cadence while the demoted built-in waits.
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let chosen: TimeInterval = 5 * 60
        let builtIn = LaneSchedule.AccountRecord(
            key: AccountKey(providerID: .claude, accountID: .primary),
            isPrimary: false, lastAttempt: now, isNeverSignedIn: true, forcedDue: false
        )
        let promoted = LaneSchedule.AccountRecord(
            key: AccountKey(providerID: .claude, accountID: AccountID("work")),
            isPrimary: true, lastAttempt: now, isNeverSignedIn: true, forcedDue: false
        )
        #expect(LaneSchedule.nextDue(for: promoted, chosen: chosen, effective: chosen) == now.addingTimeInterval(chosen))
        #expect(LaneSchedule.nextDue(for: builtIn, chosen: chosen, effective: chosen) == now.addingTimeInterval(4 * chosen))
    }

    @Test func anyAccountNeedingReauthFlagsMenuBarAttention() async {
        let store = twoAccountStore(
            workSnapshot: .stale(for: .claude, reason: .needsReauth("sign in"))
        )
        await store.refreshAll()
        #expect(store.menuBarSummary.needsAttention)
    }

    @Test func transientFailureOnExtraAccountDoesNotFlagAttention() async {
        let store = twoAccountStore(
            workSnapshot: .stale(for: .claude, reason: .transient("blip"))
        )
        await store.refreshAll()
        #expect(!store.menuBarSummary.needsAttention)
    }

    @Test func addAccountCreatesProviderAndPresetSnapshot() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            }
        )
        #expect(store.canAddAccount(for: .claude))
        let added = store.addAccount(for: .claude)
        #expect(added != nil)
        #expect(store.accounts(for: .claude).count == 2)
        // Instant "finish sign-in" placeholder, not a 20–30s pending probe.
        if case .stale(let reason) = store.snapshot(for: added!.key).freshness {
            #expect(reason.isPermanent)
        } else {
            Issue.record("expected preset stale snapshot")
        }
    }

    @Test func addedAccountFetchesOnNextRefresh() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            }
        )
        let added = store.addAccount(for: .claude)!
        await store.refreshAll()
        #expect(store.snapshot(for: added.key).freshness == .live)
        #expect(store.snapshot(for: added.key).windows.first?.utilization == 50)
    }

    @Test func removeAccountDropsProviderSnapshotAndRegistryEntry() async {
        let defaults = freshDefaults()
        let continuityCache = UsageContinuityCache(defaults: defaults)
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            },
            continuityCache: continuityCache
        )
        let added = store.addAccount(for: .claude)!
        await store.refreshAll()
        #expect(continuityCache.load()[added.key] != nil)
        #expect(await store.removeAccount(added.key) == .removed)
        #expect(continuityCache.load()[added.key] == nil)
        #expect(store.accounts(for: .claude).count == 1)
        // Snapshot access for the removed key degrades to pending, and a refresh
        // doesn't resurrect it.
        await store.refreshAll()
        #expect(store.snapshot(for: added.key).freshness == .pending)
    }

    @Test func builtInAccountCannotBeRemovedFromStore() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .pending(for: .claude))
            }
        )
        #expect(await store.removeAccount(AccountKey(providerID: .claude, accountID: .primary)) == .notAllowed)
        #expect(store.accounts(for: .claude).count == 1)
    }

    @Test func stopTrackingBuiltInDetachesWithoutDeletingCLIState() async {
        let defaults = freshDefaults()
        let continuityCache = UsageContinuityCache(defaults: defaults)
        let storage = RecordingRemovalStorage()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: storage,
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            },
            continuityCache: continuityCache
        )
        let primaryKey = AccountKey(providerID: .claude, accountID: .primary)
        let extra = store.addAccount(for: .claude)!
        await store.refreshAll()
        #expect(continuityCache.load()[primaryKey] != nil)

        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(store.accounts(for: .claude).map(\.key) == [extra.key])
        // Compact surfaces (menu bar, widgets) follow the surviving account.
        #expect(store.primaryAccount(for: .claude)?.key == extra.key)
        // The whole point: nothing on disk was deleted — not the extra's home, and
        // certainly not the CLI's own config.
        #expect(storage.removedKeys.isEmpty)
        #expect(continuityCache.load()[primaryKey] == nil)
        // A later refresh doesn't resurrect the detached row.
        await store.refreshAll()
        #expect(store.snapshot(for: primaryKey).freshness == .pending)
    }

    @Test func stopTrackingBuiltInRefusedAsOnlyAccount() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .pending(for: .claude))
            }
        )
        #expect(!store.canStopTrackingBuiltInAccount(for: .claude))
        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .notAllowed)
        #expect(store.accounts(for: .claude).count == 1)
    }

    /// Demo and preview compositions build the store with no `providerFactory`. Every
    /// account-lifecycle mutation has to be inert there — refused outright, never half
    /// applied to the persisted registry with no provider instance to match it.
    @Test func factorylessStoreRefusesStopTrackingWithoutTouchingTheRegistry() async {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
                AccountStubProvider(id: .claude, accountID: extra.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage()
        )
        // The registry itself would allow it (a second account exists), so the refusal
        // below can only come from the missing factory.
        #expect(registry.canStopTrackingBuiltIn(for: .claude))

        #expect(!store.canStopTrackingBuiltInAccount(for: .claude))
        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .notAllowed)
        #expect(!registry.isBuiltInHidden(for: .claude))
        #expect(store.accounts(for: .claude).map(\.id) == [.primary, extra.id])
        #expect(store.providers.count == 2)
    }

    @Test func factorylessStoreRefusesResumeTrackingAndLeavesTheTombstoneInPlace() {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        #expect(registry.stopTrackingBuiltIn(for: .claude))
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: extra.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage()
        )

        #expect(store.resumeTrackingBuiltInAccount(for: .claude) == nil)
        // The factory guard runs before the registry mutation, so the tombstone that
        // hides the CLI's own row survives a refused resume.
        #expect(registry.isBuiltInHidden(for: .claude))
        #expect(store.accounts(for: .claude).map(\.id) == [extra.id])
        #expect(store.providers.count == 1)
    }

    /// `attachBuiltInProvider` is the last hop of both resume and the reinstate that
    /// follows removing the final extra. Without a factory it must attach nothing —
    /// not a pending snapshot for a row that could never poll.
    @Test func factorylessStoreAttachesNoBuiltInProviderWhenTheLastExtraIsRemoved() async {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .claude)!
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: extra.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage()
        )
        let builtInKey = AccountKey(providerID: .claude, accountID: .primary)

        #expect(await store.removeAccount(extra.key) == .removed)
        #expect(store.providers.isEmpty)
        #expect(store.snapshots[builtInKey] == nil)
    }

    @Test func stopTrackingBuiltInBlockedByActiveSetupHandoff() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: ActiveHandoffStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .pending(for: .claude))
            }
        )
        _ = store.addAccount(for: .claude)
        let primaryKey = AccountKey(providerID: .claude, accountID: .primary)
        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .setupActive)
        #expect(store.accounts(for: .claude).map(\.id).contains(.primary))
        #expect(store.accountRemovalStates[primaryKey] == .setupActive)
        store.cancelAccountRemoval(primaryKey)
        #expect(store.accountRemovalStates[primaryKey] == nil)
    }

    @Test func resumeTrackingRestoresBuiltInProviderAndFetches() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            }
        )
        _ = store.addAccount(for: .claude)
        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)

        let resumed = store.resumeTrackingBuiltInAccount(for: .claude)
        #expect(resumed?.id == .primary)
        #expect(store.accounts(for: .claude).first?.id == .primary)
        let primaryKey = AccountKey(providerID: .claude, accountID: .primary)
        #expect(store.snapshot(for: primaryKey).freshness == .pending)
        await store.refreshAll()
        #expect(store.snapshot(for: primaryKey).freshness == .live)
    }

    @Test func removingLastExtraReinstatesTombstonedBuiltIn() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            }
        )
        let extra = store.addAccount(for: .claude)!
        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(await store.removeAccount(extra.key) == .removed)
        // The registry cleared the tombstone; the store must also recreate the
        // built-in's provider instance so the resurfaced row actually polls.
        #expect(store.accounts(for: .claude).map(\.id) == [.primary])
        let primaryKey = AccountKey(providerID: .claude, accountID: .primary)
        await store.refreshAll()
        #expect(store.snapshot(for: primaryKey).freshness == .live)
    }

    @Test func resumedBuiltInSetupSessionIsUsableAgain() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            }
        )
        let coordinator = SetupSessionCoordinator(
            scheduler: IgnoringSetupScheduler(),
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
        store.attachSetupCoordinator(coordinator)
        _ = store.addAccount(for: .claude)
        let primaryKey = AccountKey(providerID: .claude, accountID: .primary)

        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(coordinator.state(for: primaryKey) == .removed)

        let resumed = store.resumeTrackingBuiltInAccount(for: .claude)
        #expect(resumed != nil)
        // The reused `.primary` key must leave the coordinator's `.removed` sentinel,
        // or the resumed row's Sign In silently no-ops until relaunch.
        #expect(coordinator.state(for: primaryKey) == .idle)

        if let resumed { coordinator.begin(for: resumed) }
        for _ in 0..<20 { await Task.yield() }
        #expect(coordinator.state(for: primaryKey) == .waiting(attempt: 0))
    }

    @Test func lastExtraRemovalReinstateClearsCoordinatorRemovedSentinel() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            }
        )
        let coordinator = SetupSessionCoordinator(
            scheduler: IgnoringSetupScheduler(),
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
        store.attachSetupCoordinator(coordinator)
        let extra = store.addAccount(for: .claude)!
        let primaryKey = AccountKey(providerID: .claude, accountID: .primary)

        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(coordinator.state(for: primaryKey) == .removed)

        #expect(await store.removeAccount(extra.key) == .removed)
        // Removing the last extra reinstates the tombstoned built-in; its setup
        // session must be usable again through this path too.
        #expect(coordinator.state(for: primaryKey) == .idle)
        #expect(coordinator.state(for: extra.key) == .removed)
    }

    @Test func lateResultFromPreStopProviderCannotOverwriteResumedRow() async {
        let defaults = freshDefaults()
        let continuityCache = UsageContinuityCache(defaults: defaults)
        let primary = SuspendedAccountProvider(id: .claude, accountID: .primary)
        let store = UsageStore(
            providers: [primary],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            },
            continuityCache: continuityCache
        )
        _ = store.addAccount(for: .claude)
        let primaryKey = AccountKey(providerID: .claude, accountID: .primary)

        let refresh = Task { await store.refreshAll() }
        await primary.waitUntilStarted()

        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(store.resumeTrackingBuiltInAccount(for: .claude) != nil)
        #expect(store.snapshot(for: primaryKey).freshness == .pending)

        primary.releaseFetches()
        await refresh.value

        // The pre-stop instance's late result must not overwrite the resumed row's
        // deliberately fresh pending state or repopulate the continuity record the
        // stop-track cleared.
        #expect(store.snapshot(for: primaryKey).freshness == .pending)
        #expect(store.snapshot(for: primaryKey).windows.isEmpty)
        #expect(continuityCache.load()[primaryKey] == nil)
    }

    @Test func resetBoundariesRejectOldAndMidHandoffResultsBeforeFreshCapture() async {
        let defaults = freshDefaults()
        let continuityCache = UsageContinuityCache(defaults: defaults)
        let key = AccountKey(providerID: .claude, accountID: .primary)
        continuityCache.save(
            .live(.claude, windows: [window(.weekly, used: 91)]),
            for: key
        )
        let provider = SuspendedAccountProvider(id: .claude, accountID: .primary)
        let store = UsageStore(
            providers: [provider],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(
                    id: account.providerID,
                    accountID: account.id,
                    displayName: "Claude",
                    snapshot: .live(.claude, windows: [window(.weekly, used: 20)])
                )
            },
            continuityCache: continuityCache
        )
        let coordinator = SetupSessionCoordinator(
            scheduler: IgnoringSetupScheduler(),
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in },
            resetBoundary: { store.invalidateUsageForAccountReset($0) }
        )
        store.attachSetupCoordinator(coordinator)
        let oldRefresh = Task { await store.refreshAll() }
        await provider.waitUntilStarted()

        coordinator.beginReset(for: .builtIn(for: .claude))
        provider.releaseFetches()
        await oldRefresh.value
        #expect(continuityCache.load()[key] == nil)

        provider.suspendNextFetch()
        let midHandoffRefresh = Task { await store.refreshAll() }
        await provider.waitUntilStarted()
        coordinator.handoffDidEnd(key)
        provider.releaseFetches()
        await midHandoffRefresh.value
        #expect(continuityCache.load()[key] == nil)

        await store.refreshAll()
        #expect(coordinator.state(for: key) == .connected)
        #expect(store.snapshot(for: key).windows.first?.utilization == 20)
        #expect(continuityCache.load()[key]?.windows.first?.utilization == 20)
    }

    @Test func resetBoundaryDoesNotRetainOldLoginWindowInPartialLiveCapture() async {
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.widgetsEnabled = true
        preferences.syncToIPhoneEnabled = true
        let continuityCache = UsageContinuityCache(defaults: defaults)
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let now = Date(timeIntervalSince1970: 2_000_000)
        continuityCache.save(
            UsageSnapshot(
                providerID: .claude,
                windows: [
                    window(.weekly, used: 41),
                    window(.other("Weekly (Fable)"), used: 73),
                ],
                planLabel: "Old Max",
                accountEmail: "old@example.com",
                capturedAt: Date(timeIntervalSince1970: 1_000_000),
                freshness: .live
            ),
            for: key
        )
        let newSnapshot = UsageSnapshot(
            providerID: .claude,
            windows: [window(.weekly, used: 12)],
            planLabel: "New Pro",
            accountEmail: "new@example.com",
            capturedAt: now,
            freshness: .live
        )
        let widgetExporter = SpyWidgetExporter()
        let phoneExporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                AccountStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    snapshot: newSnapshot
                ),
            ],
            preferences: preferences,
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(
                    id: account.providerID,
                    accountID: account.id,
                    displayName: "Claude",
                    snapshot: .pending(for: account.providerID)
                )
            },
            continuityCache: continuityCache,
            now: { now },
            widgetExporter: widgetExporter,
            phoneSyncExporter: phoneExporter
        )

        #expect(store.snapshot(for: key).windows.count == 2)
        store.invalidateUsageForAccountReset(key)

        let resetSnapshot = store.snapshot(for: key)
        #expect(resetSnapshot.freshness == .pending)
        #expect(resetSnapshot.windows.isEmpty)
        #expect(resetSnapshot.planLabel == nil)
        #expect(resetSnapshot.accountEmail == nil)
        #expect(store.accounts(for: .claude).map(\.key) == [key])
        #expect(widgetExporter.exports.last?.providers.first?.windows.isEmpty == true)
        #expect(widgetExporter.exports.last?.providers.first?.planLabel == nil)
        #expect(phoneExporter.exports.last?.providers.first?.windows.isEmpty == true)
        #expect(phoneExporter.exports.last?.providers.first?.planLabel == nil)

        await store.refreshAll()

        let refreshed = store.snapshot(for: key)
        #expect(refreshed.windows.map(\.kind) == [.weekly])
        #expect(refreshed.planLabel == "New Pro")
        #expect(refreshed.accountEmail == "new@example.com")
        #expect(continuityCache.load()[key]?.windows.map(\.kind) == [.weekly])
    }

    @Test func resetBoundaryDoesNotRetainOldLoginDataInTransientFirstCapture() async {
        let defaults = freshDefaults()
        let continuityCache = UsageContinuityCache(defaults: defaults)
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let now = Date(timeIntervalSince1970: 2_000_000)
        continuityCache.save(
            UsageSnapshot(
                providerID: .claude,
                windows: [
                    window(.weekly, used: 41),
                    window(.other("Weekly (Fable)"), used: 73),
                ],
                planLabel: "Old Max",
                accountEmail: "old@example.com",
                capturedAt: Date(timeIntervalSince1970: 1_000_000),
                freshness: .live
            ),
            for: key
        )
        let store = UsageStore(
            providers: [
                AccountStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    snapshot: .stale(for: .claude, reason: .transient("Try again"))
                ),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(
                    id: account.providerID,
                    accountID: account.id,
                    displayName: "Claude",
                    snapshot: .pending(for: account.providerID)
                )
            },
            continuityCache: continuityCache,
            now: { now }
        )

        store.invalidateUsageForAccountReset(key)
        await store.refreshAll()

        let refreshed = store.snapshot(for: key)
        #expect(refreshed.windows.isEmpty)
        #expect(refreshed.planLabel == nil)
        #expect(refreshed.accountEmail == nil)
        #expect(store.accounts(for: .claude).map(\.key) == [key])
        #expect(continuityCache.load()[key] == nil)
    }

    @Test func forceCancelledResetKeepsAccountVisibleAndPollable() async {
        let defaults = freshDefaults()
        let account = ProviderAccount.builtIn(for: .claude)
        let store = UsageStore(
            providers: [
                AccountStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    snapshot: .live(.claude, windows: [window(.weekly, used: 37)])
                ),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { _ in
                AccountStubProvider(
                    id: .claude,
                    accountID: .primary,
                    displayName: "Claude",
                    snapshot: .pending(for: .claude)
                )
            }
        )
        let coordinator = SetupSessionCoordinator(
            scheduler: IgnoringSetupScheduler(),
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in },
            resetBoundary: { store.invalidateUsageForAccountReset($0) }
        )
        store.attachSetupCoordinator(coordinator)

        coordinator.beginReset(for: account)
        coordinator.forceCancel(account.key)
        await store.refreshAll()

        #expect(store.accounts(for: .claude).map(\.key) == [account.key])
        #expect(store.snapshot(for: account.key).freshness == .live)
        #expect(coordinator.state(for: account.key) == .cancelled)
    }

    @Test func stopTrackingBuiltInKeepsProviderGroupOrder() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
                AccountStubProvider(id: .codex, accountID: .primary, displayName: "Codex",
                                    snapshot: .pending(for: .codex)),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 50)]))
            }
        )
        _ = store.addAccount(for: .claude)
        #expect(store.registeredProviderOrder == [.claude, .codex])

        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        // The claude group keeps its composed position even though its only remaining
        // instance sits at the end of the provider array.
        #expect(store.registeredProviderOrder == [.claude, .codex])

        #expect(store.resumeTrackingBuiltInAccount(for: .claude) != nil)
        #expect(store.registeredProviderOrder == [.claude, .codex])
    }

    @Test func deletionFailureKeepsRecoverableRegisteredAccount() async {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .codex, accountID: .primary, displayName: "Codex", snapshot: .pending(for: .codex)),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: FailingRemovalStorage(),
            providerFactory: { account in
                AccountStubProvider(id: .codex, accountID: account.id, displayName: "Codex", snapshot: .pending(for: .codex))
            }
        )
        let added = store.addAccount(for: .codex)!

        #expect(await store.removeAccount(added.key) == .failed)
        #expect(store.accounts(for: .codex).contains(where: { $0.key == added.key }))
        #expect(store.accountRemovalStates[added.key] == .failed)

        store.cancelAccountRemoval(added.key)
        #expect(store.accountRemovalStates[added.key] == nil)
        #expect(store.accounts(for: .codex).contains(where: { $0.key == added.key }))
    }

    @Test func activeExternalSetupKeepsAccountRegisteredAndRemovalRetryable() async {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .codex, accountID: .primary, displayName: "Codex", snapshot: .pending(for: .codex)),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: ActiveSetupRemovalStorage(),
            providerFactory: { account in
                AccountStubProvider(id: .codex, accountID: account.id, displayName: "Codex", snapshot: .pending(for: .codex))
            }
        )
        let added = store.addAccount(for: .codex)!

        #expect(await store.removeAccount(added.key) == .setupActive)
        #expect(store.accounts(for: .codex).contains(where: { $0.key == added.key }))
        #expect(store.accountRemovalStates[added.key] == .setupActive)
        store.cancelAccountRemoval(added.key)
        #expect(store.accountRemovalStates[added.key] == nil)
    }

    @Test func renameUpdatesAccountLabel() {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .pending(for: .claude)),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(id: account.providerID, accountID: account.id, displayName: "Claude",
                                    snapshot: .pending(for: .claude))
            }
        )
        store.renameAccount(AccountKey(providerID: .claude, accountID: .primary), to: "Personal")
        #expect(store.accounts(for: .claude).first?.label == "Personal")
    }

    @Test func accountManagementDisabledWithoutRegistryAndFactory() {
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .pending(for: .claude)),
            ],
            preferences: Preferences(defaults: freshDefaults())
        )
        #expect(!store.canAddAccount(for: .claude))
        #expect(store.addAccount(for: .claude) == nil)
    }

    @Test func singleAccountProviderRejectsAdditionalAccounts() {
        let defaults = freshDefaults()
        let store = UsageStore(
            providers: [
                AccountStubProvider(
                    id: .cursor,
                    accountID: .primary,
                    displayName: "Cursor",
                    snapshot: .pending(for: .cursor),
                    accountCapacity: 1
                ),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(
                    id: account.providerID,
                    accountID: account.id,
                    displayName: "Cursor",
                    snapshot: .pending(for: .cursor),
                    accountCapacity: 1
                )
            }
        )

        #expect(store.accountCapacity(for: .cursor) == 1)
        #expect(!store.canAddAccount(for: .cursor))
        #expect(store.addAccount(for: .cursor) == nil)
    }

    @Test func refreshAccountFetchesOnlyThatAccount() async {
        let store = twoAccountStore(
            workSnapshot: .live(.claude, windows: [window(.weekly, used: 80)])
        )
        let workKey = AccountKey(providerID: .claude, accountID: work)
        await store.refreshAccount(workKey)
        // The targeted account is live; its sibling was never fetched and stays pending.
        #expect(store.snapshot(for: workKey).freshness == .live)
        #expect(store.snapshot(for: AccountKey(providerID: .claude, accountID: .primary)).freshness == .pending)
    }

    @Test func claudeAccountProbesAreSequenced() async {
        let probe = FetchConcurrencyProbe()
        let accountIDs: [AccountID] = [.primary, AccountID("work"), AccountID("client")]
        let accounts = accountIDs.enumerated().map { index, id in
            ProviderAccount(
                id: id, providerID: .claude, label: index == 0 ? "Main" : "Account \(index + 1)",
                isBuiltIn: index == 0
            )
        }
        let store = UsageStore(
            providers: accountIDs.map {
                ProbedAccountProvider(id: .claude, accountID: $0, probe: probe)
            },
            preferences: Preferences(defaults: freshDefaults()),
            accounts: accounts
        )

        await store.refreshAll()

        #expect(await probe.maximum == 1)
        #expect(accountIDs.allSatisfy {
            store.snapshot(for: AccountKey(providerID: .claude, accountID: $0)).freshness == .live
        })
    }

    @Test func setupRefreshDuringFleetProbeCoalescesWithTheInFlightAccount() async {
        let primary = SuspendedAccountProvider(id: .claude, accountID: .primary)
        let extraID = AccountID("work")
        let extra = SuspendedAccountProvider(id: .claude, accountID: extraID)
        let accounts: [ProviderAccount] = [
            .builtIn(for: .claude),
            ProviderAccount(id: extraID, providerID: .claude, label: "Work"),
        ]
        let store = UsageStore(
            providers: [primary, extra],
            preferences: Preferences(defaults: freshDefaults()),
            accounts: accounts
        )
        let fleet = Task { await store.refreshAll() }
        await primary.waitUntilStarted()
        await extra.waitUntilStarted()

        let key = AccountKey(providerID: .claude, accountID: extraID)
        store.refreshAccountNow(key)
        store.refreshAccountNow(key)
        extra.releaseFetches()
        primary.releaseFetches()
        await fleet.value

        // KTD7: the in-flight probe answers both setup checks as well as the fleet refresh.
        #expect(extra.fetchCount == 1)
    }

    @Test func removingAccountDuringFleetRefreshDoesNotStrandCapabilityDiscovery() async {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extraAccount = registry.addAccount(for: .claude)!
        let lane = ProviderPollingLane.serial("claude-cli")
        let primary = SuspendedAccountProvider(
            id: .claude,
            accountID: .primary,
            pollingLane: lane,
            reportsProviderCapability: true
        )
        primary.releaseFetches()
        let extra = SuspendedAccountProvider(
            id: .claude,
            accountID: extraAccount.id,
            pollingLane: lane,
            reportsProviderCapability: true
        )
        let store = UsageStore(
            providers: [primary, extra],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                AccountStubProvider(
                    id: account.providerID,
                    accountID: account.id,
                    displayName: "Claude",
                    snapshot: .pending(for: account.providerID)
                )
            }
        )
        let fleet = Task { await store.refreshAll() }
        await extra.waitUntilStarted()

        #expect(await store.removeAccount(extraAccount.key) == .removed)
        extra.releaseFetches()
        await fleet.value

        #expect(store.providerCapabilities[.claude]?.state == .available)
    }

    @Test func capabilityVerdictRemainsVisibleDuringLaterRefresh() async {
        let provider = SuspendedAccountProvider(
            id: .claude,
            accountID: .primary,
            pollingLane: .serial("claude-cli"),
            reportsProviderCapability: true,
            capability: .confirmedAbsent
        )
        provider.releaseFetches()
        let store = UsageStore(
            providers: [provider],
            preferences: Preferences(defaults: freshDefaults())
        )
        await store.refreshAll()
        #expect(store.providerCapabilities[.claude]?.state == .confirmedAbsent)

        provider.suspendNextFetch()
        let refresh = Task { await store.refreshAll() }
        await provider.waitUntilStarted()

        #expect(store.providerCapabilities[.claude]?.state == .confirmedAbsent)

        provider.releaseFetches()
        await refresh.value
    }

    @Test func widgetExportUsesPrimaryAccountOnly() async {
        let exporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 30)])),
                AccountStubProvider(id: .claude, accountID: work, displayName: "Claude",
                                    snapshot: .live(.claude, windows: [window(.weekly, used: 95)])),
            ],
            preferences: Preferences(defaults: freshDefaults()),
            accounts: [
                .builtIn(for: .claude),
                ProviderAccount(id: work, providerID: .claude, label: "Work"),
            ],
            widgetExporter: exporter
        )
        await store.refreshAll()
        let claude = exporter.exports.last?.providers.first { $0.id == ProviderID.claude.raw }
        let weekly = claude?.windows.first { $0.kind == .weekly }
        #expect(weekly?.percentRemaining == 70) // built-in account (30% used), not the 95%-used extra
    }

    @Test func fallbackAccountIndexSynthesizesBuiltIn() {
        let store = UsageStore(
            providers: [
                AccountStubProvider(id: .claude, accountID: .primary, displayName: "Claude",
                                    snapshot: .pending(for: .claude)),
            ],
            preferences: Preferences(defaults: freshDefaults())
        )
        let accounts = store.accounts(for: .claude)
        #expect(accounts.count == 1)
        #expect(accounts[0].isBuiltIn)
    }
}

// MARK: - OpenCode accounts (U4 of the OpenCode plan: R9, R10, KTD8, KTD10, KTD12)

/// A source whose captures for a home can be held open, counting starts per home.
private actor HoldingOpenCodeSource: OpenCodeUsageSource {
    private var holds: Set<OpenCodeAccountHome> = []
    private var waiters: [OpenCodeAccountHome: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var starts: [OpenCodeAccountHome: Int] = [:]

    func hold(_ home: OpenCodeAccountHome) { holds.insert(home) }
    func startCount(_ home: OpenCodeAccountHome) -> Int { starts[home, default: 0] }
    func waiting(_ home: OpenCodeAccountHome) -> Int { waiters[home]?.count ?? 0 }
    func releaseAll() {
        holds.removeAll()
        waiters.values.flatMap { $0 }.forEach { $0.resume() }
        waiters.removeAll()
    }

    func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        starts[home, default: 0] += 1
        if holds.contains(home) {
            await withCheckedContinuation { waiters[home, default: []].append($0) }
        }
        return .noGoPlan
    }
}

/// A clock only ever moved forward, so a probe and the test loop can both advance it.
private final class ForwardClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    @discardableResult
    func advance(by seconds: TimeInterval) -> (start: Date, end: Date) {
        lock.withLock {
            let start = value
            value = value.addingTimeInterval(seconds)
            return (start, value)
        }
    }
}

/// KTD12's slow Console: every capture takes `duration` seconds of the test's clock.
private final class SlowOpenCodeSource: OpenCodeUsageSource, @unchecked Sendable {
    struct Run: Equatable {
        let home: OpenCodeAccountHome
        let span: LaneSchedule.ProbeSpan
        let userRequested: Bool
    }

    private let lock = NSLock()
    private var recorded: [Run] = []
    private let clock: ForwardClock
    private let duration: TimeInterval
    private let resetsAt: Date

    init(clock: ForwardClock, duration: TimeInterval, resetsAt: Date) {
        self.clock = clock
        self.duration = duration
        self.resetsAt = resetsAt
    }

    var runs: [Run] { lock.withLock { recorded } }

    func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        let userRequested = UserRequestedProbeContext.isUserRequested
        let (start, end) = clock.advance(by: duration)
        lock.withLock {
            recorded.append(Run(home: home, span: .init(start: start, end: end), userRequested: userRequested))
        }
        let window = OpenCodeGoWindow(percentUsed: 10, isLimited: false, resetsAt: resetsAt)
        return .goUsage(OpenCodeGoUsage(rolling: window, weekly: window, monthly: window))
    }
}

/// AE4's fake `opencode`: written once for the suite and run as `/bin/sh <script>` (KTD17).
/// Like the real client it reads `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`, and it is
/// signed in only when that folder holds a `seeded` file.
private enum SeededHomeOpenCodeScript {
    static let body = #"""
    data="${XDG_DATA_HOME:-$HOME/.local/share}"
    case "$*" in
      "--version") echo "opencode v2.2.5"; exit 0 ;;
      "api --standalone experimental.usage.limits")
        if [ -f "$data/opencode/seeded" ]; then
          r=$(( ($(date +%s) + 3600) * 1000 ))
          printf '{"location":{"directory":"/x"},"data":{"go":{"rolling":{"percent":29,"limited":false,"resetsAt":%s},"weekly":{"percent":47,"limited":false,"resetsAt":%s},"monthly":{"percent":63,"limited":false,"resetsAt":%s}}}}\n' "$r" "$r" "$r"
        else
          echo '{"location":{"directory":"/x"},"data":null}'
        fi
        exit 0 ;;
      "auth list --standalone --format json") echo '[]'; exit 0 ;;
      *) exit 2 ;;
    esac
    """#

    static let path: String = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-opencode-seeded-fake-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("opencode")
        try? Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        // The source checks the path is executable before it spawns `/bin/sh <script>`.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }()
}

@MainActor
@Suite struct OpenCodeMultiAccountTests {
    private func openCodeDefaults() -> UserDefaults { freshDefaults() }

    @Test func registrationCapacityAndProviderCapacityAgree() {
        let provider = OpenCodeProvider(source: HoldingOpenCodeSource(), home: .builtIn)
        #expect(provider.accountCapacity == AccountRegistry.testedEnvelope)
        #expect(provider.pollingLane == .serial("opencode-cli"))
        let defaults = openCodeDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let store = UsageStore(
            providers: [provider],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                OpenCodeProvider(source: HoldingOpenCodeSource(), accountID: account.id, home: .isolated(root: "/tmp/\(account.id.raw)"))
            }
        )
        #expect(store.accountCapacity(for: .opencode) == AccountRegistry.testedEnvelope)
        for _ in 1..<AccountRegistry.testedEnvelope { #expect(store.addAccount(for: .opencode) != nil) }
        #expect(store.accounts(for: .opencode).count == AccountRegistry.testedEnvelope)
        #expect(!store.canAddAccount(for: .opencode))
    }

    /// AE4 / R10: a new extra account whose home is empty reads as signed out while the
    /// built-in account, on the default home, is live. Then seeding the extra's own data
    /// folder signs only it in.
    @Test func emptyExtraHomeIsSignedOutWhileTheBuiltInIsLive() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-opencode-ae4-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let userHome = scratch.appendingPathComponent("home", isDirectory: true)
        let defaultData = userHome.appendingPathComponent(".local/share/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultData, withIntermediateDirectories: true)
        try Data().write(to: defaultData.appendingPathComponent("seeded"))
        let accountsBase = scratch.appendingPathComponent("Accounts", isDirectory: true)

        let script = SeededHomeOpenCodeScript.path
        let cli = OpenCodeCLIUsageSource(
            resolveExecutable: { script },
            resolveLoginPath: { "/usr/bin:/bin" },
            inheritedEnvironment: { ["HOME": userHome.path, "XDG_DATA_HOME": "/nonexistent-shell-profile"] },
            workingDirectory: scratch.appendingPathComponent("OpenCodeProbe").path,
            deadline: 10,
            versionDeadline: 5,
            interpreter: "/bin/sh"
        )
        let cache = OpenCodeUsageCaptureCache(source: cli)
        let extra = ProviderAccount(id: AccountID("work"), providerID: .opencode, label: "Work")
        try AccountStorage.ensureDirectories(for: extra, baseDirectoryURL: accountsBase)
        let extraHome = try #require(ProviderAccountConfiguration.make(for: extra, accountsBase: accountsBase).opencodeHome)
        let builtInHome = try #require(ProviderAccountConfiguration.make(for: .builtIn(for: .opencode), accountsBase: accountsBase).opencodeHome)
        #expect(builtInHome == .builtIn)

        let defaults = openCodeDefaults()
        let store = UsageStore(
            providers: [
                OpenCodeProvider(source: cache, home: builtInHome),
                OpenCodeProvider(source: cache, accountID: extra.id, home: extraHome),
            ],
            preferences: Preferences(defaults: defaults),
            accounts: [.builtIn(for: .opencode), extra]
        )
        store.setSurfaceEnabled(true, for: .opencodeSubscription)
        await store.refreshAll()

        let builtInKey = AccountKey(providerID: .opencode, accountID: .primary)
        #expect(store.snapshot(for: builtInKey).freshness == .live)
        #expect(store.snapshot(for: builtInKey).windows.map(\.percentUsed) == [29, 47, 63])
        #expect(store.snapshot(for: extra.key).freshness == .stale(.providerSetup(.opencodeSignedOut)))

        guard case .isolated(let root) = extraHome else { Issue.record("extra must be isolated"); return }
        let extraData = URL(fileURLWithPath: root).appendingPathComponent("data/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: extraData, withIntermediateDirectories: true)
        try Data().write(to: extraData.appendingPathComponent("seeded"))
        await store.refreshAll()
        #expect(store.snapshot(for: extra.key).freshness == .live)
    }

    private func makeHeldStore(source: HoldingOpenCodeSource, cache: OpenCodeUsageCaptureCache)
        -> (UsageStore, ProviderAccount, OpenCodeAccountHome) {
        let defaults = openCodeDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .opencode)!
        let extraHome = OpenCodeAccountHome.isolated(root: "/tmp/headroom-opencode-\(extra.id.raw)")
        let store = UsageStore(
            providers: [
                OpenCodeProvider(source: cache, home: .builtIn),
                OpenCodeProvider(source: cache, accountID: extra.id, home: extraHome),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopAccountStorage(),
            providerFactory: { account in
                OpenCodeProvider(source: cache, accountID: account.id, home: .isolated(root: "/tmp/\(account.id.raw)"))
            }
        )
        store.setSurfaceEnabled(true, for: .opencodeSubscription)
        return (store, extra, extraHome)
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// KTD8: removal drops the in-flight entry, so a later read for the home never joins
    /// the capture that began before the removal.
    @Test func removingAnAccountMidCaptureInvalidatesItsInFlightRead() async {
        let source = HoldingOpenCodeSource()
        let cache = OpenCodeUsageCaptureCache(source: source)
        let (store, extra, extraHome) = makeHeldStore(source: source, cache: cache)
        await source.hold(extraHome)
        let refresh = Task { await store.refreshAccount(extra.key) }
        await waitUntil { await source.waiting(extraHome) == 1 }

        #expect(await store.removeAccount(extra.key) == .removed)
        let next = Task { await cache.capture(home: extraHome) }
        await waitUntil { await source.startCount(extraHome) == 2 }
        #expect(await source.startCount(extraHome) == 2)

        await source.releaseAll()
        _ = await next.value
        await refresh.value
    }

    /// KTD8: the reset boundary drops the in-flight entry too, so the first reading after a
    /// sign-out and sign-in is a fresh read of the new login.
    @Test func accountResetInvalidatesTheInFlightRead() async {
        let source = HoldingOpenCodeSource()
        let cache = OpenCodeUsageCaptureCache(source: source)
        let (store, _, _) = makeHeldStore(source: source, cache: cache)
        let builtInKey = AccountKey(providerID: .opencode, accountID: .primary)
        await source.hold(.builtIn)
        let refresh = Task { await store.refreshAccount(builtInKey) }
        await waitUntil { await source.waiting(.builtIn) == 1 }

        store.invalidateUsageForAccountReset(builtInKey)
        let next = Task { await cache.capture(home: .builtIn) }
        await waitUntil { await source.startCount(.builtIn) == 2 }
        #expect(await source.startCount(.builtIn) == 2)

        await source.releaseAll()
        _ = await next.value
        await refresh.value
    }

    /// KTD9 of the sign-in plan and KTD8: a Terminal exit's handoff boundary drops the
    /// in-flight entry too, so the follow-up check after sign-in never joins a read that began
    /// before it and would be rejected anyway.
    @Test func handoffBoundaryInvalidatesTheInFlightRead() async {
        let source = HoldingOpenCodeSource()
        let cache = OpenCodeUsageCaptureCache(source: source)
        let (store, _, _) = makeHeldStore(source: source, cache: cache)
        let builtInKey = AccountKey(providerID: .opencode, accountID: .primary)
        await source.hold(.builtIn)
        let refresh = Task { await store.refreshAccount(builtInKey) }
        await waitUntil { await source.waiting(.builtIn) == 1 }

        store.invalidateUsageForHandoffBoundary(builtInKey)
        let next = Task { await cache.capture(home: .builtIn) }
        await waitUntil { await source.startCount(.builtIn) == 2 }
        #expect(await source.startCount(.builtIn) == 2)

        await source.releaseAll()
        _ = await next.value
        await refresh.value
    }

    /// KTD12: twenty accounts behind 16-second captures. The launch's user pass reaches every
    /// account (user work bypasses the gate); after it, no timer probe starts while the lane
    /// has been busy for more than half of the trailing window, the lane never runs two reads
    /// at once, and every account keeps being reached in turn.
    @Test func twentySlowAccountsStayWithinTheDutyCycleGate() async {
        let t0 = Date(timeIntervalSince1970: 2_000_000_000)
        let clock = ForwardClock(t0)
        let source = SlowOpenCodeSource(clock: clock, duration: 16, resetsAt: t0.addingTimeInterval(60 * 24 * 3_600))
        let cache = OpenCodeUsageCaptureCache(source: source)
        let accounts = [ProviderAccount.builtIn(for: .opencode)]
            + (1..<AccountRegistry.testedEnvelope).map {
                ProviderAccount(id: AccountID("extra-\($0)"), providerID: .opencode, label: "Extra \($0)")
            }
        let homes = Dictionary(uniqueKeysWithValues: accounts.map { account in
            (account.key, account.isBuiltIn ? OpenCodeAccountHome.builtIn : .isolated(root: "/tmp/\(account.id.raw)"))
        })
        let prefs = Preferences(defaults: openCodeDefaults())
        prefs.pollIntervalMinutes = 5
        let store = UsageStore(
            providers: accounts.map { OpenCodeProvider(source: cache, accountID: $0.id, home: homes[$0.key]!, now: clock.now) },
            preferences: prefs,
            accounts: accounts,
            now: clock.now
        )
        store.setSurfaceEnabled(true, for: .opencodeSubscription)

        await store.refreshAll()
        #expect(Set(source.runs.map(\.home)) == Set(homes.values))
        #expect(source.runs.count == accounts.count)

        // Ninety simulated minutes of five-second timer wakes.
        for _ in 0..<(90 * 12) {
            clock.advance(by: 5)
            store.dispatchDueNow()
            for _ in 0..<3 { await Task.yield() }
            await store.waitForAccountProbesToFinish()
        }

        let runs = source.runs
        let chosen: TimeInterval = 5 * 60
        let window = LaneSchedule.window(chosen: chosen)
        for (index, run) in runs.enumerated() where !run.userRequested {
            let earlier = runs[..<index].map(\.span)
            let busy = LaneSchedule.busyTime(log: earlier, now: run.span.start, window: window)
            #expect(busy <= window * LaneSchedule.dutyCycleCeiling, "timer probe \(index) started with \(busy) s busy")
        }
        for (previous, next) in zip(runs, runs.dropFirst()) {
            #expect(next.span.start >= previous.span.end, "the serial lane ran two reads at once")
        }
        let timerRuns = runs.filter { !$0.userRequested }
        let perHome = Dictionary(grouping: timerRuns, by: \.home).mapValues(\.count)
        #expect(perHome.count == accounts.count, "an account was never reached by the timer")
        let counts = perHome.values
        #expect((counts.max() ?? 0) - (counts.min() ?? 0) <= 1, "accounts were not reached in turn: \(perHome.values.sorted())")
        // KTD12 measures it: 20 × 16 s exceeds half of a 10-minute window, so the lane runs
        // slower than the chosen 5 minutes and Settings says so. Measured on 2026-11-12: the
        // longest on-cadence gap is 16 minutes (960 s); one minute of slack for wake order.
        let cadence = store.pollCadence(for: .opencode)
        #expect(cadence.isStretched)
        #expect(cadence.effectiveInterval <= 17 * 60, "effective interval \(cadence.effectiveInterval)")
    }
}
