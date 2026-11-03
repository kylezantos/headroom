import Foundation
import Testing
@testable import HeadroomCore

/// U2 of the 2026-09-19 polling plan: the per-lane due-queue through the store's public
/// surface — ordering, priority requests, backoff, the user-only refreshing flag, and
/// provider-scoped dispatch. All providers are doubles; nothing waits on a real clock.
@MainActor
struct AccountProbeSchedulerTests {
    private let reset = Date(timeIntervalSince1970: 3_000_000)
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    private func preferences() -> Preferences {
        let suite = "headroom.scheduler.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Preferences(defaults: defaults)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            await Task.yield()
        }
    }

    /// Called from the doubles' `@Sendable` result closures off the main actor.
    nonisolated private func liveSnapshot(_ id: ProviderID, at capturedAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset)],
            planLabel: nil,
            capturedAt: capturedAt ?? Date(),
            freshness: .live
        )
    }

    // MARK: Ordering (AE1, AE4)

    @Test func primaryIsProbedBeforeAnOverdueExtraInASerialLane() async {
        let order = ProbeOrder()
        let extraID = AccountID("work")
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: .serial("claude-cli"), order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        // Providers listed extra-first so registry order, not array order, must decide.
        let store = UsageStore(
            providers: [extra, primary],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )

        await store.refreshAll()

        #expect(order.keys.first == primary.accountKey)
        #expect(order.keys.count == 2)
    }

    // MARK: User-requested probe flag

    @Test func setupCheckProbeCarriesTheUserRequestedFlag() async {
        let recorder = UserRequestFlagRecorder()
        let probe = flagRecordingProbe(recorder)
        let store = UsageStore(providers: [probe], preferences: preferences(), accounts: [.builtIn(for: .claude)])

        await store.refreshAccount(probe.accountKey, origin: .setupCheck)

        #expect(recorder.values == [true])
    }

    @Test func fullRefreshProbeCarriesTheUserRequestedFlag() async {
        let recorder = UserRequestFlagRecorder()
        let probe = flagRecordingProbe(recorder)
        let store = UsageStore(providers: [probe], preferences: preferences(), accounts: [.builtIn(for: .claude)])

        await store.refreshAll()

        #expect(recorder.values == [true])
    }

    @Test func timerProbeDoesNotCarryTheUserRequestedFlag() async {
        let recorder = UserRequestFlagRecorder()
        let probe = flagRecordingProbe(recorder)
        let store = UsageStore(providers: [probe], preferences: preferences(), accounts: [.builtIn(for: .claude)])

        store.dispatchDueNow()
        await settle { probe.fetchCount == 1 }

        #expect(recorder.values == [false])
    }

    @Test func popoverOpenProbeDoesNotCarryTheUserRequestedFlag() async {
        let clock = MutableDateSource(t0)
        let recorder = UserRequestFlagRecorder()
        let probe = flagRecordingProbe(recorder, clock: clock)
        let store = UsageStore(
            providers: [probe], preferences: preferences(), accounts: [.builtIn(for: .claude)], now: clock.now
        )
        await store.refreshAll()

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.refreshOnPopoverOpen()
        await settle { probe.fetchCount == 2 }

        #expect(recorder.values == [true, false])
    }

    @Test func userRequestForOneAccountLeavesItsTimerSiblingUnflagged() async {
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primaryFlags = UserRequestFlagRecorder()
        let extraFlags = UserRequestFlagRecorder()
        let primary = LaneProbe(
            id: .claude, accountID: .primary, lane: lane, order: order,
            onFetch: { primaryFlags.record(UserRequestedProbeContext.isUserRequested) },
            result: { .init(snapshot: self.liveSnapshot(.claude)) }
        )
        let extra = LaneProbe(
            id: .claude, accountID: extraID, lane: lane, order: order,
            onFetch: { extraFlags.record(UserRequestedProbeContext.isUserRequested) },
            result: { .init(snapshot: self.liveSnapshot(.claude)) }
        )
        primary.suspendNextFetch()
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )

        store.dispatchDueNow()
        await primary.waitUntilStarted()
        store.refreshAccountNow(extra.accountKey, origin: .setupCheck)
        primary.release()
        await settle { extra.fetchCount == 1 }

        #expect(primaryFlags.values == [false])
        #expect(extraFlags.values == [true])
    }

    nonisolated private func flagRecordingProbe(
        _ recorder: UserRequestFlagRecorder,
        clock: MutableDateSource? = nil
    ) -> LaneProbe {
        LaneProbe(
            id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: ProbeOrder(),
            onFetch: { recorder.record(UserRequestedProbeContext.isUserRequested) },
            result: { .init(snapshot: self.liveSnapshot(.claude, at: clock?.now())) }
        )
    }

    @Test func priorityRequestIsServedRightAfterTheInFlightProbe() async {
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let ids = ["a", "b", "c"].map(AccountID.init)
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        primary.suspendNextFetch()
        let extras = ids.map { id in
            LaneProbe(id: .claude, accountID: id, lane: lane, order: order,
                      result: { .init(snapshot: self.liveSnapshot(.claude)) })
        }
        let accounts: [ProviderAccount] = [.builtIn(for: .claude)]
            + ids.map { ProviderAccount(id: $0, providerID: .claude, label: $0.raw) }
        let store = UsageStore(providers: [primary] + extras, preferences: preferences(), accounts: accounts)

        let refresh = Task { await store.refreshAll() }
        await primary.waitUntilStarted()
        let requested = AccountKey(providerID: .claude, accountID: ids[2])
        store.refreshAccountNow(requested)
        primary.release()
        await refresh.value

        #expect(order.keys.first == primary.accountKey)
        #expect(order.keys.dropFirst().first == requested)
        #expect(order.keys.count == 4)
    }

    @Test func latestPriorityLocatorGenerationCrossesTheSchedulerTaskHop() async {
        let order = ProbeOrder()
        let generations = LocatorGenerationRecorder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(
            id: .claude,
            accountID: .primary,
            lane: lane,
            order: order,
            result: { .init(snapshot: self.liveSnapshot(.claude)) }
        )
        primary.suspendNextFetch()
        let extra = LaneProbe(
            id: .claude,
            accountID: extraID,
            lane: lane,
            order: order,
            onFetch: { generations.record(CLIExecutableRefreshContext.generation) },
            result: { .init(snapshot: self.liveSnapshot(.claude)) }
        )
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [
                .builtIn(for: .claude),
                ProviderAccount(id: extraID, providerID: .claude, label: "Work"),
            ]
        )

        let fleet = Task { await store.refreshAll() }
        await primary.waitUntilStarted()
        let first = UUID()
        let latest = UUID()
        CLIExecutableRefreshContext.$generation.withValue(first) {
            store.refreshAccountNow(extra.accountKey)
        }
        CLIExecutableRefreshContext.$generation.withValue(latest) {
            store.refreshAccountNow(extra.accountKey)
        }
        primary.release()
        await fleet.value

        #expect(extra.fetchCount == 1)
        #expect(generations.values == [latest])
    }

    // MARK: Concurrent lane and backoff (AE8)

    @Test func codexAccountsFetchConcurrentlyAndOnlyTheFailingOneBacksOff() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let healthyID = AccountID("healthy")
        let failingID = AccountID("failing")
        let primary = LaneProbe(id: .codex, accountID: .primary, lane: .concurrent, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.codex, at: clock.now())) })
        let healthy = LaneProbe(id: .codex, accountID: healthyID, lane: .concurrent, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.codex, at: clock.now())) })
        let failing = LaneProbe(id: .codex, accountID: failingID, lane: .concurrent, order: order,
                                result: { .init(snapshot: .stale(for: .codex, reason: .transient("retry"))) })
        primary.suspendNextFetch()
        healthy.suspendNextFetch()
        let store = UsageStore(
            providers: [primary, healthy, failing],
            preferences: preferences(),
            accounts: [
                .builtIn(for: .codex),
                ProviderAccount(id: healthyID, providerID: .codex, label: "Healthy"),
                ProviderAccount(id: failingID, providerID: .codex, label: "Failing"),
            ],
            now: clock.now
        )

        let refresh = Task { await store.refreshAll() }
        // Both suspended fetches are in flight at once: the HTTP lane does not serialize.
        await primary.waitUntilStarted()
        await healthy.waitUntilStarted()
        #expect(primary.fetchCount == 1 && healthy.fetchCount == 1)
        primary.release()
        healthy.release()
        await refresh.value
        #expect(failing.fetchCount == 1)

        // One interval on: the healthy accounts are due, the failing one is backing off.
        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await settle { healthy.fetchCount == 2 && primary.fetchCount == 2 }
        #expect(healthy.fetchCount == 2)
        #expect(failing.fetchCount == 1)

        // Two intervals on (5 × 2¹ = 10 min): the failing account is due again.
        clock.set(t0.addingTimeInterval(10 * 60 + 1))
        store.dispatchDueNow()
        await settle { failing.fetchCount == 2 }
        #expect(failing.fetchCount == 2)
    }

    @Test func priorityAtConcurrentDispatchBoundaryCoalescesWithTheDispatchedProbe() async {
        let order = ProbeOrder()
        let provider = LaneProbe(
            id: .codex,
            accountID: .primary,
            lane: .concurrent,
            order: order,
            result: { .init(snapshot: self.liveSnapshot(.codex)) }
        )
        provider.suspendNextFetch()
        let store = UsageStore(providers: [provider], preferences: preferences())

        // Keep this sequence synchronous: dispatch has reserved the account, but its task
        // has not started. A user request in this boundary must share that dispatched probe.
        store.scheduler.markAllDue()
        store.scheduler.dispatchDue()
        store.scheduler.requestPriority(provider.accountKey)

        await provider.waitUntilStarted()
        provider.release()
        await store.scheduler.waitUntilUserWorkDrains()
        await store.scheduler.waitUntilLanesIdle()

        #expect(provider.fetchCount == 1)
    }

    @Test func concurrentReservationClearsWhenTheAccountBecomesIneligibleBeforeTaskStart() async {
        let order = ProbeOrder()
        let provider = LaneProbe(
            id: .codex,
            accountID: .primary,
            lane: .concurrent,
            order: order,
            result: { .init(snapshot: self.liveSnapshot(.codex)) }
        )
        let store = UsageStore(providers: [provider], preferences: preferences())

        // Both calls stay on the main actor without suspension, so the surface turns off
        // after dispatch reserves the key and before the scheduler task can start it.
        store.scheduler.markAllDue()
        store.scheduler.dispatchDue()
        store.setSurfaceEnabled(false, for: .codexSubscription)
        await store.scheduler.waitUntilLanesIdle()

        #expect(provider.fetchCount == 0)
        #expect(store.scheduler.allLanesIdle)
    }

    @Test func neverSignedInExtraWaitsFourIntervalsWhileThePrimaryStaysOnCadence() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: .stale(for: .claude, reason: .notLoggedIn("sign in"))) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")],
            now: clock.now
        )
        await store.refreshAll()
        #expect(primary.fetchCount == 1 && extra.fetchCount == 1)

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await settle { primary.fetchCount == 2 }
        await store.scheduler.waitUntilLanesIdle()
        #expect(primary.fetchCount == 2)
        #expect(extra.fetchCount == 1)

        // Fifteen minutes: past two doublings of backoff, still short of four intervals.
        clock.set(t0.addingTimeInterval(15 * 60 + 1))
        store.dispatchDueNow()
        await settle { primary.fetchCount == 3 }
        await store.scheduler.waitUntilLanesIdle()
        #expect(primary.fetchCount == 3)
        #expect(extra.fetchCount == 1)

        clock.set(t0.addingTimeInterval(20 * 60 + 1))
        store.dispatchDueNow()
        await settle { extra.fetchCount == 2 }
        await store.scheduler.waitUntilLanesIdle()
        #expect(extra.fetchCount == 2)
    }

    // MARK: Refreshing flag and spend refreshes (KTD2)

    @Test func timerPassLeavesIsRefreshingFalseButAUserRefreshSetsIt() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let provider = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                 result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let store = UsageStore(providers: [provider], preferences: preferences(), now: clock.now)
        await store.refreshAll()

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        provider.suspendNextFetch()
        store.dispatchDueNow()
        await provider.waitUntilStarted()
        #expect(!store.isRefreshing)

        let refresh = Task { await store.refreshAll() }
        await settle { store.isRefreshing }
        #expect(store.isRefreshing)
        provider.release()
        await refresh.value
        #expect(!store.isRefreshing)
        // KTD7: the in-flight probe answered the refresh; it was not probed a second time.
        #expect(provider.fetchCount == 2)
    }

    @Test func spendOnlyRefreshRunsWhileAClaudeLaneIsDraining() async {
        let order = ProbeOrder()
        let provider = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                 result: { .init(snapshot: self.liveSnapshot(.claude)) })
        provider.suspendNextFetch()
        let spend = StubSpendProvider(id: .claude)
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)
        let store = UsageStore(providers: [provider], apiSpendProviders: [spend], preferences: prefs)

        let refresh = Task { await store.refreshAll() }
        await provider.waitUntilStarted()
        await store.refreshAPISpendOnly()
        #expect(spend.fetchCount == 1)

        provider.release()
        await refresh.value
    }

    // MARK: Provider-scoped dispatch (KTD11)

    @Test func enablingASurfaceDispatchesOnlyThatProvider() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let claude = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                               result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let grok = LaneProbe(id: .grok, accountID: .primary, lane: .serial("grok-cli"), order: order,
                             result: { .init(snapshot: self.liveSnapshot(.grok, at: clock.now())) })
        let store = UsageStore(providers: [claude, grok], preferences: preferences(), now: clock.now)
        await store.refreshAll()
        #expect(claude.fetchCount == 1)
        #expect(grok.fetchCount == 0)

        // Claude is overdue by now, so only the provider scoping keeps it out of this dispatch.
        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.setSurfaceEnabled(true, for: .grokSubscription)
        store.dispatchDueNow(for: .grok)
        await settle { grok.fetchCount == 1 }
        #expect(grok.fetchCount == 1)
        #expect(claude.fetchCount == 1)

        store.dispatchDueNow()
        await settle { claude.fetchCount == 2 }
        #expect(claude.fetchCount == 2)
    }

    @Test func disablingASurfaceMidRefreshReleasesTheRefreshInsteadOfStrandingIt() async {
        // KTD11: a queued user request for an account that can no longer be scheduled must
        // not pin `isRefreshing` and a full refresh open until the surface comes back.
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        primary.suspendNextFetch()
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )

        let refresh = Task { await store.refreshAll() }
        await primary.waitUntilStarted()
        store.setSurfaceEnabled(false, for: .claudeSubscription)
        primary.release()
        await refresh.value

        #expect(!store.isRefreshing)
        #expect(extra.fetchCount == 0)
    }

    @Test func aSingleAccountRequestDoesNotWakeTimerDueSiblings() async {
        // KTD7 / AGENTS.md: Check Now, Make Main and a setup check refresh only their account;
        // siblings that are merely due wait for the timer.
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )

        await store.refreshAccount(extra.accountKey)
        #expect(extra.fetchCount == 1)
        #expect(primary.fetchCount == 0)

        store.dispatchDueNow()
        await settle { primary.fetchCount == 1 }
        #expect(primary.fetchCount == 1)
        #expect(extra.fetchCount == 1)
    }

    @Test func aRequestAfterAHandoffBoundaryIsNotAnsweredByTheProbeThatPredatesIt() async {
        // KTD7: the running probe's result will be rejected at the boundary, so the request
        // queues a follow-up instead of coalescing onto it.
        let order = ProbeOrder()
        let provider = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                 result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let store = UsageStore(providers: [provider], preferences: preferences())
        provider.suspendNextFetch()
        store.dispatchDueNow()
        await provider.waitUntilStarted()

        store.invalidateUsageForHandoffBoundary(provider.accountKey)
        let check = Task { await store.refreshAccount(provider.accountKey) }
        provider.release()
        await check.value

        #expect(provider.fetchCount == 2)
        #expect(store.snapshot(for: provider.accountKey).freshness == .live)
    }

    @Test func theGateHoldsTimerWorkAfterALongProbeButNeverUserWork() async {
        // KTD4 / R8 through the store: a 200 s probe in a 240 s window closes the gate for
        // timer work until enough of it ages out; a user refresh runs regardless.
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let prefs = preferences()
        prefs.pollIntervalMinutes = 2
        let provider = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                 result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let store = UsageStore(providers: [provider], preferences: prefs, now: clock.now)

        provider.suspendNextFetch()
        let launch = Task { await store.refreshAll() }
        await provider.waitUntilStarted()
        clock.set(t0.addingTimeInterval(200))
        provider.release()
        await launch.value
        #expect(provider.fetchCount == 1)

        clock.set(t0.addingTimeInterval(201))
        store.dispatchDueNow()
        for _ in 0..<20 { await Task.yield() }
        #expect(provider.fetchCount == 1)

        await store.refreshAll()
        #expect(provider.fetchCount == 2)

        // The 200 s span's excess (80 s) plus the window: reopens at t0 + 320.
        clock.set(t0.addingTimeInterval(321))
        store.dispatchDueNow()
        await settle { provider.fetchCount == 3 }
        #expect(provider.fetchCount == 3)
        #expect(!store.pollCadence(for: .claude).isStretched)
    }

    @Test func aTimerPassAppliesTheNewestCapabilityVerdictAtItsEnd() async {
        // KTD8: an earlier path miss in the pass is cleared by a later account that found the
        // CLI, and nothing is applied before the pass ends.
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                reportsProviderCapability: true,
                                result: { .init(snapshot: .stale(for: .claude, reason: .transient("cli missing")),
                                                capability: .inconclusive(.shellTimeout)) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              reportsProviderCapability: true,
                              result: { .init(snapshot: self.liveSnapshot(.claude), capability: .available) })
        extra.suspendNextFetch()
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )

        store.dispatchDueNow()
        await extra.waitUntilStarted()
        #expect(store.providerCapabilities[.claude]?.state == .discovering)

        extra.release()
        await settle { store.providerCapabilities[.claude]?.state == .available }
        #expect(store.providerCapabilities[.claude]?.state == .available)
    }

    @Test func fullRefreshExportsOnceAndAPrimaryTimerMergeExportsAtOnce() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let exporter = SpyWidgetExporter()
        let extraID = AccountID("work")
        let lane = ProviderPollingLane.serial("claude-cli")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")],
            now: clock.now,
            widgetExporter: exporter
        )
        await store.refreshAll()
        #expect(exporter.exports.count == 1)

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        extra.suspendNextFetch()
        store.dispatchDueNow()
        await extra.waitUntilStarted()
        // The primary merged first and exported without waiting for the extra (R19).
        #expect(exporter.exports.count == 2)
        extra.release()
        await settle { store.scheduler.allLanesIdle }
        #expect(exporter.exports.count == 2)
    }

    @Test func pollCadenceReportsChosenIntervalAndAccountCount() async {
        let order = ProbeOrder()
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: .serial("claude-cli"), order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )
        await store.refreshAll()
        let cadence = store.pollCadence(for: .claude)
        #expect(cadence.chosenInterval == 5 * 60)
        #expect(cadence.effectiveInterval == 5 * 60)
        #expect(cadence.accountCount == 2)
        #expect(!cadence.isStretched)
    }

    // MARK: Menu-bar slosh and the refresh receipt (Oct 2026)

    /// Round-3 S2: a pill sloshes while its provider's main account is being probed, timer
    /// passes included, and only then; an extra account's probe moves nothing.
    @Test func probingAccountsTrackRunningProbesAndOnlyAMainAccountMovesItsPill() async {
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )
        #expect(store.probingAccounts.isEmpty)

        primary.suspendNextFetch()
        extra.suspendNextFetch()
        store.dispatchDueNow()
        await primary.waitUntilStarted()
        #expect(store.probingAccounts == [primary.accountKey])
        #expect(store.menuBarUpdatingProviders == [.claude])
        // A timer pass is not user work, so there is no receipt.
        #expect(store.refreshProgress == nil)

        primary.release()
        await extra.waitUntilStarted()
        #expect(store.probingAccounts == [extra.accountKey])
        #expect(store.menuBarUpdatingProviders.isEmpty)

        extra.release()
        await settle { store.probingAccounts.isEmpty }
        #expect(store.probingAccounts.isEmpty)
    }

    /// W4: a user refresh reports each account as it finishes, then clears once drained so
    /// the footer hands back to the stamp.
    @Test func refreshProgressCountsLandedAccountsAndClearsWhenDrained() async {
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )
        primary.suspendNextFetch()
        extra.suspendNextFetch()
        let refresh = Task { await store.refreshAll() }
        await primary.waitUntilStarted()
        #expect(store.refreshProgress == RefreshProgress(total: 2, completed: 0, lastLanded: nil))

        primary.release()
        await extra.waitUntilStarted()
        #expect(store.refreshProgress == RefreshProgress(total: 2, completed: 1, lastLanded: primary.accountKey))

        extra.release()
        await refresh.value
        #expect(store.refreshProgress == nil)
        #expect(store.probingAccounts.isEmpty)
    }

    @Test func receiptTitleNamesTheAccountOnlyOnceAProviderHasSeveral() async {
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let claude = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                               result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let work = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                             result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let codex = LaneProbe(id: .codex, accountID: .primary, lane: .concurrent, order: order,
                              result: { .init(snapshot: self.liveSnapshot(.codex)) })
        let store = UsageStore(
            providers: [claude, work, codex],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work"),
                       .builtIn(for: .codex)]
        )
        #expect(store.refreshReceiptTitle(for: work.accountKey) == "Claude Work")
        #expect(store.refreshReceiptTitle(for: codex.accountKey) == "Codex")
    }
}

// MARK: - Doubles

/// Records the order in which fetches started across every double in a test.
final class ProbeOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var _keys: [AccountKey] = []
    var keys: [AccountKey] { lock.withLock { _keys } }
    func record(_ key: AccountKey) { lock.withLock { _keys.append(key) } }
}

final class LocatorGenerationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [UUID?] = []
    var values: [UUID?] { lock.withLock { recorded } }
    func record(_ generation: UUID?) { lock.withLock { recorded.append(generation) } }
}

final class UserRequestFlagRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []
    var values: [Bool] { lock.withLock { recorded } }
    func record(_ flag: Bool) { lock.withLock { recorded.append(flag) } }
}

/// Provider double for scheduler tests: a fixed lane, a result closure, a shared start
/// order, and a one-shot suspend gate the test releases.
final class LaneProbe: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    let pollingLane: ProviderPollingLane
    let reportsProviderCapability: Bool
    private let result: @Sendable () -> UsageProviderFetchResult
    private let onFetch: @Sendable () -> Void
    private let order: ProbeOrder
    private let gate = FetchGate()
    private let lock = NSLock()
    private var count = 0

    init(
        id: ProviderID,
        accountID: AccountID,
        lane: ProviderPollingLane,
        order: ProbeOrder,
        reportsProviderCapability: Bool = false,
        onFetch: @escaping @Sendable () -> Void = {},
        result: @escaping @Sendable () -> UsageProviderFetchResult
    ) {
        self.id = id
        self.accountID = accountID
        self.displayName = id.displayName
        self.pollingLane = lane
        self.order = order
        self.reportsProviderCapability = reportsProviderCapability
        self.onFetch = onFetch
        self.result = result
    }

    var fetchCount: Int { lock.withLock { count } }

    /// The next fetch blocks until `release()`.
    func suspendNextFetch() { gate.suspendNextFetch() }
    func waitUntilStarted() async { await gate.waitUntilStarted() }
    func release() { gate.release() }

    func fetchSnapshot() async -> UsageSnapshot { await fetchResult().snapshot }

    func fetchResult() async -> UsageProviderFetchResult {
        lock.withLock { count += 1 }
        order.record(accountKey)
        onFetch()
        await gate.enter()
        return result()
    }
}

final class StubSpendProvider: APISpendProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Spend"
    private let lock = NSLock()
    private var count = 0
    var fetchCount: Int { lock.withLock { count } }

    init(id: ProviderID) { self.id = id }

    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        lock.withLock { count += 1 }
        return .stale(providerID: id, displayName: displayName, periodLabel: period.label, reason: .transient("offline"))
    }
}
