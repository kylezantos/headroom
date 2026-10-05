import Foundation
import Testing
@testable import HeadroomCore

@MainActor
struct UsageStoreRefreshRunTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    private func preferences() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: "headroom.refresh-run.\(UUID())")!)
    }

    private func probe(_ id: ProviderID, account: AccountID = .primary, clock: MutableDateSource,
                       stale: Bool = false, lane: ProviderPollingLane = .concurrent) -> LaneProbe {
        LaneProbe(id: id, accountID: account, lane: lane, order: ProbeOrder(), result: {
            .init(snapshot: stale ? .stale(for: id, reason: .transient("offline")) : UsageSnapshot(
                providerID: id, windows: [], planLabel: nil, capturedAt: clock.now(), freshness: .live
            ))
        })
    }

    private func reprint(_ store: UsageStore, at date: Date) -> ReprintRecipe {
        ReprintRecipe(meters: store.menuBarMeters, automatic: true, currentMains: [:],
            run: store.userRefreshRun, probingAccounts: store.probingAccounts, probeEndTimes: store.lastProbeEndTimes,
            spendInFlightProviders: store.apiSpendInFlightProviders, visibleWork: store.visibleRefreshWork, now: date)
    }

    @Test func landedAccountActionHoldsThenRestsWhileUnrelatedSetupContinues() async {
        let clock = MutableDateSource(t0)
        let setup = probe(.claude, clock: clock)
        let action = probe(.codex, clock: clock)
        setup.suspendNextFetch()
        action.suspendNextFetch()
        let store = UsageStore(providers: [setup, action], preferences: preferences(), now: clock.now)
        store.refreshAccountNow(setup.accountKey, origin: .setupCheck)
        await setup.waitUntilStarted()
        #expect(reprint(store, at: clock.now()).phase == .rest)
        #expect(store.visibleRefreshWork == VisibleRefreshWork())
        store.refreshAccountNow(action.accountKey, origin: .accountAction)
        await action.waitUntilStarted()
        #expect(reprint(store, at: clock.now()).phase == .spinner)
        #expect(store.visibleRefreshWork == VisibleRefreshWork(isInFlight: true))
        clock.set(t0.addingTimeInterval(1))
        action.release()
        await store.scheduler.waitForCompletion(of: action.accountKey)
        #expect(store.isRefreshing)
        #expect(store.probingAccounts == [setup.accountKey])
        #expect(store.visibleRefreshWork == VisibleRefreshWork(clearedAt: clock.now()))
        #expect(reprint(store, at: clock.now().addingTimeInterval(0.49)).phase == .hold)
        #expect(reprint(store, at: clock.now().addingTimeInterval(0.5)).phase == .rest)
        clock.set(t0.addingTimeInterval(3))
        setup.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(reprint(store, at: clock.now()).phase == .rest)
        #expect(store.visibleRefreshWork.clearedAt == t0.addingTimeInterval(1))
    }

    @Test(arguments: [false, true])
    func setupCheckDuringEndHoldPreservesUserLanding(sameAccount: Bool) async {
        let clock = MutableDateSource(t0)
        let action = probe(.codex, clock: clock, stale: true)
        let unrelated = probe(.claude, clock: clock)
        let store = UsageStore(providers: [action, unrelated], preferences: preferences(), now: clock.now)
        store.refreshAccountNow(action.accountKey, origin: .accountAction)
        await store.scheduler.waitUntilLanesIdle()
        let historicalRun = store.userRefreshRun
        let historicalWork = store.visibleRefreshWork
        #expect(historicalRun?.entries[action.accountKey]?.outcome == .stale)
        #expect(reprint(store, at: clock.now()).phase == .hold)

        clock.set(t0.addingTimeInterval(0.1))
        let setup = sameAccount ? action : unrelated
        setup.suspendNextFetch()
        store.refreshAccountNow(setup.accountKey, origin: .setupCheck)
        await setup.waitUntilStarted()
        #expect(store.userRefreshRun?.id == historicalRun?.id)
        #expect(store.userRefreshRun?.entries[action.accountKey] == historicalRun?.entries[action.accountKey])
        #expect(store.visibleRefreshWork == historicalWork)
        #expect(reprint(store, at: t0.addingTimeInterval(0.49)).phase == .hold)
        #expect(reprint(store, at: t0.addingTimeInterval(0.5)).phase == .rest)

        clock.set(t0.addingTimeInterval(0.6))
        setup.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.entries[action.accountKey] == historicalRun?.entries[action.accountKey])
        #expect(store.visibleRefreshWork == historicalWork)
        #expect(reprint(store, at: clock.now()).phase == .rest)
    }

    @Test func setupCheckAfterRetentionStartsSetupOnlyRun() async {
        let clock = MutableDateSource(t0)
        let provider = probe(.codex, clock: clock)
        let store = UsageStore(providers: [provider], preferences: preferences(), now: clock.now)
        store.refreshAccountNow(provider.accountKey)
        await store.scheduler.waitUntilLanesIdle()
        let historicalID = store.userRefreshRun?.id
        clock.set(t0.addingTimeInterval(0.71))
        provider.suspendNextFetch()
        store.refreshAccountNow(provider.accountKey, origin: .setupCheck)
        await provider.waitUntilStarted()
        #expect(store.userRefreshRun?.id != historicalID)
        #expect(store.userRefreshRun?.entries[provider.accountKey]?.origin == .setupCheck)
        #expect(store.accountActionCheckingKeys.isEmpty)
        #expect(reprint(store, at: clock.now()).phase == .rest)
        provider.release()
        await store.scheduler.waitUntilLanesIdle()
    }

    @Test func spendOnlyCompletionHoldsEvenWithRetainedSetupHistory() async {
        let clock = MutableDateSource(t0)
        let setup = probe(.claude, clock: clock)
        setup.suspendNextFetch()
        let spend = RefreshRunSpendProbe(id: .codex)
        spend.gate.suspendNextFetch()
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .openAIAPI)
        let store = UsageStore(providers: [setup], apiSpendProviders: [spend], preferences: prefs, now: clock.now)
        store.refreshAccountNow(setup.accountKey, origin: .setupCheck)
        await setup.waitUntilStarted()
        #expect(reprint(store, at: clock.now()).phase == .rest)
        setup.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.visibleRefreshWork == VisibleRefreshWork())
        let setupRunID = store.userRefreshRun?.id
        clock.set(t0.addingTimeInterval(0.1))
        let refresh = Task { await store.refreshAPISpendOnly() }
        await spend.gate.waitUntilStarted()
        #expect(reprint(store, at: clock.now()).phase == .spendTail)
        clock.set(t0.addingTimeInterval(0.2))
        spend.gate.release()
        await refresh.value
        #expect(store.userRefreshRun?.id == setupRunID)
        #expect(store.visibleRefreshWork == VisibleRefreshWork(clearedAt: clock.now()))
        #expect(reprint(store, at: clock.now().addingTimeInterval(0.49)).phase == .hold)
        #expect(reprint(store, at: clock.now().addingTimeInterval(0.5)).phase == .rest)
    }

    @Test func fullRunRetainsEveryLandingAndClearTimeThenANewRequestStartsFresh() async {
        let clock = MutableDateSource(t0)
        let providers = [ProviderID.claude, .codex, .grok].map { probe($0, clock: clock) }
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .grokSubscription)
        let store = UsageStore(providers: providers, preferences: prefs, now: clock.now)
        await store.refreshAll()
        let run = try! #require(store.userRefreshRun)
        #expect(run.entries.count == 3)
        #expect(run.entries.values.allSatisfy { $0.origin == .fullRefresh && $0.outcome == .live && $0.landedAt == t0 })
        #expect(run.refreshingClearedAt == t0)
        clock.set(t0.addingTimeInterval(0.6))
        store.clearExpiredUserRefreshRun(at: clock.now())
        #expect(store.userRefreshRun?.id == run.id)
        providers[0].suspendNextFetch()
        store.refreshAccountNow(providers[0].accountKey)
        await providers[0].waitUntilStarted()
        #expect(store.userRefreshRun?.id != run.id)
        #expect(store.userRefreshRun?.entries.count == 1)
        providers[0].release()
        await store.scheduler.waitUntilLanesIdle()
        clock.set(clock.now().addingTimeInterval(0.71))
        store.clearExpiredUserRefreshRun(at: clock.now())
        #expect(store.userRefreshRun == nil)
    }

    @Test func coalescedOriginsRespectSetupPrecedenceAndLatestUserAction() async {
        let clock = MutableDateSource(t0)
        let provider = probe(.claude, clock: clock)
        provider.suspendNextFetch()
        let store = UsageStore(providers: [provider], preferences: preferences(), now: clock.now)
        let key = provider.accountKey
        store.refreshAccountNow(key, origin: .setupCheck)
        await provider.waitUntilStarted()
        #expect(store.userRefreshRun?.entries[key]?.origin == .setupCheck)
        #expect(store.accountActionCheckingKeys.isEmpty)
        clock.set(t0.addingTimeInterval(2))
        store.refreshAccountNow(key, origin: .fullRefresh)
        store.refreshAccountNow(key, origin: .setupCheck)
        #expect(store.userRefreshRun?.entries[key]?.origin == .fullRefresh)
        #expect(store.userRefreshRun?.entries[key]?.requestedAt == clock.now())
        store.refreshAccountNow(key)
        #expect(store.userRefreshRun?.entries[key]?.origin == .accountAction)
        #expect(store.accountActionCheckingKeys == [key])
        #expect(store.userRefreshRun?.entries.count == 1)
        provider.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(provider.fetchCount == 1)
        #expect(store.userRefreshRun?.entries[key]?.outcome == .live)
        #expect(store.accountActionCheckingKeys.isEmpty)
    }

    @Test func timerProbeCanSatisfyUserRequestAndAlwaysPublishesEndTime() async {
        let clock = MutableDateSource(t0)
        let provider = probe(.codex, clock: clock)
        provider.suspendNextFetch()
        let store = UsageStore(providers: [provider], preferences: preferences(), now: clock.now)
        store.dispatchDueNow()
        await provider.waitUntilStarted()
        #expect(store.userRefreshRun == nil)
        #expect(!store.isRefreshing)
        store.refreshAccountNow(provider.accountKey)
        clock.set(t0.addingTimeInterval(1.4))
        provider.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(provider.fetchCount == 1)
        #expect(store.lastProbeEndTimes[provider.accountKey] == clock.now())
        #expect(store.userRefreshRun?.entries[provider.accountKey]?.landedAt == clock.now())
    }

    @Test func staleAndWithdrawnAndRejectedResultsHaveDistinctOutcomes() async {
        let clock = MutableDateSource(t0)
        let stale = probe(.codex, clock: clock, stale: true)
        let store = UsageStore(providers: [stale], preferences: preferences(), now: clock.now)
        await store.refreshAll()
        #expect(store.userRefreshRun?.entries[stale.accountKey]?.outcome == .stale)
        stale.suspendNextFetch()
        store.refreshAccountNow(stale.accountKey)
        await stale.waitUntilStarted()
        store.invalidateUsageForAccountReset(stale.accountKey)
        stale.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.entries[stale.accountKey]?.outcome == .dropped)

        let primary = probe(.claude, clock: clock, lane: .serial("claude-cli"))
        let extra = probe(.claude, account: AccountID("work"), clock: clock, lane: .serial("claude-cli"))
        primary.suspendNextFetch()
        let fleet = UsageStore(providers: [primary, extra], preferences: preferences(), accounts: [
            .builtIn(for: .claude), ProviderAccount(id: extra.accountID, providerID: .claude, label: "Work")
        ], now: clock.now)
        let refresh = Task { await fleet.refreshAll() }
        await primary.waitUntilStarted()
        fleet.setSurfaceEnabled(false, for: .claudeSubscription)
        #expect(fleet.userRefreshRun?.entries[extra.accountKey]?.outcome == .dropped)
        primary.release()
        await refresh.value
    }
    @Test func setupOnlyRunAndTimerOnlyProbeKeepTheirOwnMeaning() async {
        let clock = MutableDateSource(t0)
        let provider = probe(.claude, clock: clock)
        let store = UsageStore(providers: [provider], preferences: preferences(), now: clock.now)
        store.refreshAccountNow(provider.accountKey, origin: .setupCheck)
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.entries.values.allSatisfy { $0.origin == .setupCheck } == true)
        #expect(store.visibleRefreshWork == VisibleRefreshWork())
        clock.set(t0.addingTimeInterval(301))
        store.clearExpiredUserRefreshRun(at: clock.now())
        provider.suspendNextFetch()
        store.dispatchDueNow()
        await provider.waitUntilStarted()
        #expect(store.userRefreshRun == nil)
        #expect(!store.isRefreshing)
        provider.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.lastProbeEndTimes[provider.accountKey] == clock.now())
    }

    @Test func lateAccountRequestJoinsSameRunWithItsOwnRequestAndLandingTime() async {
        let clock = MutableDateSource(t0)
        let claude = probe(.claude, clock: clock)
        let codex = probe(.codex, clock: clock)
        let store = UsageStore(providers: [claude, codex], preferences: preferences(), now: clock.now)
        claude.suspendNextFetch()
        codex.suspendNextFetch()
        store.refreshAccountNow(claude.accountKey)
        await claude.waitUntilStarted()
        let id = store.userRefreshRun?.id
        clock.set(t0.addingTimeInterval(2))
        store.refreshAccountNow(codex.accountKey)
        await codex.waitUntilStarted()
        #expect(store.userRefreshRun?.id == id)
        #expect(store.userRefreshRun?.entries[codex.accountKey]?.requestedAt == clock.now())
        claude.release()
        await store.scheduler.waitForCompletion(of: claude.accountKey)
        #expect(store.userRefreshRun?.entries[claude.accountKey]?.landedAt == clock.now())
        clock.set(t0.addingTimeInterval(3))
        codex.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.entries[codex.accountKey]?.landedAt == clock.now())
        #expect(store.userRefreshRun?.entries.count == 2)
    }

    @Test func spendTailRetainsRunAndSuppressesAccountPillUntilFullRefreshEnds() async {
        let clock = MutableDateSource(t0)
        let provider = probe(.claude, clock: clock)
        let spend = RefreshRunSpendProbe(id: .claude)
        spend.gate.suspendNextFetch()
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)
        let store = UsageStore(providers: [provider], apiSpendProviders: [spend], preferences: prefs, now: clock.now)
        let refresh = Task { await store.refreshAll() }
        await spend.gate.waitUntilStarted()
        let id = store.userRefreshRun?.id
        #expect(store.userRefreshRun?.entries[provider.accountKey]?.outcome == .live)
        #expect(store.userRefreshRun?.refreshingClearedAt == nil)
        #expect(store.apiSpendInFlightProviders == [.claude])
        #expect(store.visibleRefreshWork.isInFlight)
        #expect(reprint(store, at: clock.now()).phase == .spendTail)
        clock.set(t0.addingTimeInterval(3))
        store.clearExpiredUserRefreshRun(at: clock.now())
        #expect(store.userRefreshRun?.id == id)
        #expect(store.isRefreshing)
        provider.suspendNextFetch()
        store.refreshAccountNow(provider.accountKey)
        await provider.waitUntilStarted()
        #expect(store.userRefreshRun?.id == id)
        #expect(store.userRefreshRun?.entries[provider.accountKey]?.origin == .accountAction)
        #expect(store.accountActionCheckingKeys.isEmpty)
        spend.gate.release()
        // refreshAll waits for subscription work only before spend; the new account
        // request remains independently in flight after the full-refresh operation ends.
        await refresh.value
        #expect(store.apiSpendInFlightProviders.isEmpty)
        #expect(store.accountActionCheckingKeys == [provider.accountKey])
        #expect(store.userRefreshRun?.refreshingClearedAt == nil)
        provider.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.refreshingClearedAt == clock.now())
        clock.set(clock.now().addingTimeInterval(0.6))
        store.clearExpiredUserRefreshRun(at: clock.now())
        #expect(store.userRefreshRun != nil)
        clock.set(clock.now().addingTimeInterval(0.11))
        store.clearExpiredUserRefreshRun(at: clock.now())
        #expect(store.userRefreshRun == nil)
    }

    @Test func setupCheckDuringSpendTailPreservesHistoricalUserLanding() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let provider = LaneProbe(id: .claude, accountID: .primary, lane: .concurrent, order: order, result: {
            .init(snapshot: order.keys.count == 1
                ? .stale(for: .claude, reason: .transient("offline"))
                : UsageSnapshot(providerID: .claude, windows: [], planLabel: nil,
                                capturedAt: clock.now(), freshness: .live))
        })
        let spend = RefreshRunSpendProbe(id: .claude)
        spend.gate.suspendNextFetch()
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)
        let store = UsageStore(providers: [provider], apiSpendProviders: [spend], preferences: prefs, now: clock.now)
        let refresh = Task { await store.refreshAll() }
        await spend.gate.waitUntilStarted()
        let key = provider.accountKey
        let historical = store.userRefreshRun?.entries[key]
        #expect(historical?.origin == .fullRefresh)
        #expect(historical?.outcome == .stale)
        clock.set(t0.addingTimeInterval(2))
        provider.suspendNextFetch()
        store.refreshAccountNow(key, origin: .setupCheck)
        await provider.waitUntilStarted()
        #expect(store.userRefreshRun?.entries[key] == historical)
        #expect(store.accountActionCheckingKeys.isEmpty)
        #expect(store.probingAccounts.contains(key))
        clock.set(t0.addingTimeInterval(3))
        provider.release()
        await store.scheduler.waitForCompletion(of: key)
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.entries[key] == historical)
        #expect(store.lastProbeEndTimes[key] == clock.now())
        #expect(store.isRefreshing)
        spend.gate.release()
        await refresh.value
        #expect(store.userRefreshRun?.entries[key] == historical)
        #expect(store.userRefreshRun?.refreshingClearedAt == clock.now())
    }

    @Test func userActionCanUpgradeSetupProbeAfterHistoricalLandingDuringSpendTail() async {
        let clock = MutableDateSource(t0)
        let provider = probe(.claude, clock: clock)
        let spend = RefreshRunSpendProbe(id: .claude)
        spend.gate.suspendNextFetch()
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)
        let store = UsageStore(providers: [provider], apiSpendProviders: [spend], preferences: prefs, now: clock.now)
        let refresh = Task { await store.refreshAll() }
        await spend.gate.waitUntilStarted()
        let key = provider.accountKey
        let historical = store.userRefreshRun?.entries[key]
        clock.set(t0.addingTimeInterval(2))
        provider.suspendNextFetch()
        store.refreshAccountNow(key, origin: .setupCheck)
        await provider.waitUntilStarted()
        #expect(store.userRefreshRun?.entries[key] == historical)
        clock.set(t0.addingTimeInterval(3))
        store.refreshAccountNow(key, origin: .accountAction)
        #expect(store.userRefreshRun?.entries[key]?.origin == .accountAction)
        #expect(store.userRefreshRun?.entries[key]?.requestedAt == clock.now())
        #expect(store.userRefreshRun?.entries[key]?.outcome == nil)
        #expect(store.userRefreshRun?.entries[key]?.landedAt == nil)
        store.refreshAccountNow(key, origin: .setupCheck)
        #expect(store.userRefreshRun?.entries[key]?.origin == .accountAction)
        clock.set(t0.addingTimeInterval(4))
        provider.release()
        await store.scheduler.waitForCompletion(of: key)
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.entries[key]?.outcome == .live)
        #expect(store.userRefreshRun?.entries[key]?.landedAt == clock.now())
        #expect(provider.fetchCount == 2)
        spend.gate.release()
        await refresh.value
    }

    @Test func spendOnlyRepeatGuardAndProviderSetRemainAccurate() async {
        let clock = MutableDateSource(t0)
        let spend = RefreshRunSpendProbe(id: .codex)
        spend.gate.suspendNextFetch()
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .openAIAPI)
        let store = UsageStore(providers: [], apiSpendProviders: [spend], preferences: prefs, now: clock.now)
        let refresh = Task { await store.refreshAPISpendOnly() }
        await spend.gate.waitUntilStarted()
        #expect(store.apiSpendInFlightProviders == [.codex])
        #expect(store.userRefreshRun == nil)
        #expect(store.refreshingClearedAt == nil)
        await store.refreshAPISpendOnly()
        #expect(spend.fetchCount == 1)
        clock.set(t0.addingTimeInterval(3))
        spend.gate.release()
        await refresh.value
        #expect(store.apiSpendInFlightProviders.isEmpty)
        #expect(!store.isRefreshing)
        #expect(store.refreshingClearedAt == clock.now())
        let held = ReprintRecipe(meters: store.menuBarMeters, automatic: true, currentMains: [:],
            run: store.userRefreshRun, probingAccounts: store.probingAccounts, probeEndTimes: store.lastProbeEndTimes,
            spendInFlightProviders: store.apiSpendInFlightProviders, visibleWork: store.visibleRefreshWork, now: clock.now().addingTimeInterval(0.49))
        #expect(held.phase == .hold)
        let rested = ReprintRecipe(meters: store.menuBarMeters, automatic: true, currentMains: [:],
            run: store.userRefreshRun, probingAccounts: store.probingAccounts, probeEndTimes: store.lastProbeEndTimes,
            spendInFlightProviders: store.apiSpendInFlightProviders, visibleWork: store.visibleRefreshWork, now: clock.now().addingTimeInterval(0.5))
        #expect(rested.phase == .rest)
    }

    @Test func accountAndProviderChecksStayScoped() async {
        let clock = MutableDateSource(t0)
        let claude = [.primary, AccountID("work"), AccountID("other")].map {
            probe(.claude, account: $0, clock: clock, lane: .serial("claude-cli"))
        }
        let codex = probe(.codex, clock: clock)
        let accounts = claude.map { ProviderAccount(id: $0.accountID, providerID: .claude, label: $0.accountID.raw) }
            + [.builtIn(for: .codex)]
        let store = UsageStore(providers: claude + [codex], preferences: preferences(), accounts: accounts, now: clock.now)
        store.refreshAccountNow(claude[0].accountKey)
        await store.scheduler.waitUntilLanesIdle()
        #expect(claude.map(\.fetchCount) == [1, 0, 0])
        #expect(codex.fetchCount == 0)
        store.refreshProviderNow(.claude)
        await store.scheduler.waitUntilLanesIdle()
        #expect(claude.map(\.fetchCount) == [2, 1, 1])
        #expect(codex.fetchCount == 0)
        #expect(store.userRefreshRun?.entries.count == 3)
        #expect(store.userRefreshRun?.entries.values.allSatisfy { $0.origin == .accountAction } == true)
    }

    @Test func reservedIneligibleAndUnregisteredKeysLandDropped() async {
        let clock = MutableDateSource(t0)
        let provider = probe(.codex, clock: clock)
        let store = UsageStore(providers: [provider], preferences: preferences(), now: clock.now)
        store.scheduler.markAllDue()
        store.scheduler.dispatchDue()
        store.setSurfaceEnabled(false, for: .codexSubscription)
        await store.scheduler.waitUntilLanesIdle()
        #expect(store.userRefreshRun?.entries[provider.accountKey]?.outcome == .dropped)
        #expect(provider.fetchCount == 0)

        let active = probe(.claude, clock: clock)
        active.suspendNextFetch()
        let otherStore = UsageStore(providers: [active], preferences: preferences(), now: clock.now)
        otherStore.refreshAccountNow(active.accountKey)
        await active.waitUntilStarted()
        otherStore.scheduler.unregister(active.accountKey)
        #expect(otherStore.userRefreshRun?.entries[active.accountKey]?.outcome == .dropped)
        active.release()
        await otherStore.scheduler.waitUntilLanesIdle()
        #expect(otherStore.userRefreshRun?.entries[active.accountKey]?.outcome == .dropped)
    }

}


private final class RefreshRunSpendProbe: APISpendProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Spend"
    let gate = FetchGate()
    private let lock = NSLock()
    private var count = 0
    var fetchCount: Int { lock.withLock { count } }

    init(id: ProviderID) { self.id = id }

    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        lock.withLock { count += 1 }
        await gate.enter()
        return .stale(providerID: id, displayName: displayName, periodLabel: period.label, reason: .transient("offline"))
    }
}
