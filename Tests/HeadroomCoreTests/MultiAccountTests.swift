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
        accountCapacity: Int = AccountRegistry.maxPerProvider,
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

    @Test func capsAtFivePerProviderIndependently() {
        let registry = AccountRegistry(defaults: freshDefaults())
        for _ in 0..<4 { #expect(registry.addAccount(for: .claude) != nil) }
        #expect(!registry.canAddAccount(for: .claude))
        #expect(registry.addAccount(for: .claude) == nil)
        // The Codex cap is its own budget.
        #expect(registry.canAddAccount(for: .codex))
        #expect(registry.addAccount(for: .codex) != nil)
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

    @Test func setupRefreshQueuedDuringFleetRefreshIsDeduplicatedAndDrained() async {
        let primary = SuspendedAccountProvider(id: .claude, accountID: .primary)
        let extraID = AccountID("work")
        let extra = SuspendedAccountProvider(id: .claude, accountID: extraID)
        extra.releaseFetches()
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

        async let first: Void = store.refreshAccount(AccountKey(providerID: .claude, accountID: extraID))
        async let second: Void = store.refreshAccount(AccountKey(providerID: .claude, accountID: extraID))
        _ = await (first, second)
        primary.releaseFetches()
        await fleet.value

        // One fleet fetch plus one deduplicated queued setup check.
        #expect(extra.fetchCount == 2)
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
