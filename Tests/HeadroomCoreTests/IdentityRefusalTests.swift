import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U2 (KTD2): a reading taken while the login was changing is refused,
/// read again soon, and never counts as a failure. The refusals are bounded.
@MainActor
struct IdentityRefusalTests {
    private let reset = Date(timeIntervalSince1970: 3_000_000_000)
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    private func defaults() -> UserDefaults {
        let suite = "headroom.identity-refusal.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    nonisolated private func live(_ id: ProviderID, used: Double = 10, at capturedAt: Date) -> UsageProviderFetchResult {
        .init(snapshot: UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .fiveHour, utilization: used, resetsAt: reset)],
            planLabel: nil,
            capturedAt: capturedAt,
            freshness: .live
        ))
    }

    /// Returns its results in order, repeating the last one.
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [UsageProviderFetchResult]
        init(_ results: [UsageProviderFetchResult]) { self.results = results }
        func next() -> UsageProviderFetchResult {
            lock.withLock { results.count > 1 ? results.removeFirst() : results[0] }
        }
    }

    private func store(
        _ probe: LaneProbe,
        clock: MutableDateSource,
        reliability: SessionReliabilityRecord? = nil
    ) -> UsageStore {
        UsageStore(
            providers: [probe],
            preferences: Preferences(defaults: defaults()),
            accounts: [.builtIn(for: probe.id)],
            sessionReliabilityRecord: reliability,
            now: clock.now
        )
    }

    /// Covers AE6.
    @Test func refusedReadingIsReadAgainAtOnceAndNeverShowsAsAFailure() async {
        let clock = MutableDateSource(t0)
        let script = Script([live(.claude, used: 10, at: t0), .identityUnreadable(for: .claude), live(.claude, used: 40, at: t0)])
        let probe = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: ProbeOrder(),
                              result: { script.next() })
        let reliability = SessionReliabilityRecord(defaults: defaults(), now: clock.now)
        let store = store(probe, clock: clock, reliability: reliability)

        await store.refreshAll()
        #expect(store.snapshot(for: .claude).windows.first?.utilization == 10)
        let observations = reliability.days.map(\.observations).reduce(0, +)

        // One interval on, the timer probe meets a login change, then reads again.
        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await store.waitForAccountProbesToFinish()

        #expect(probe.fetchCount == 3)
        #expect(store.snapshot(for: .claude).freshness == .live)
        #expect(store.snapshot(for: .claude).windows.first?.utilization == 40)
        // The refused reading was never noted: one more observation, not two.
        #expect(reliability.days.map(\.observations).reduce(0, +) == observations + 1)
        #expect(store.scheduler.identityRefusalTotals[probe.accountKey] == 1)
    }

    @Test func refusedReadingLeavesTheRowUntouchedWhileItWaits() async {
        let clock = MutableDateSource(t0)
        let script = Script([live(.codex, used: 10, at: t0), .identityUnreadable(for: .codex)])
        let probe = LaneProbe(id: .codex, accountID: .primary, lane: .concurrent, order: ProbeOrder(),
                              result: { script.next() })
        let store = store(probe, clock: clock)
        await store.refreshAll()
        let before = store.snapshot(for: .codex)

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await store.waitForAccountProbesToFinish()

        // The concurrent lane has no loop: one refused probe, the row neither dimmed nor
        // changed, and the account due again at the next wake rather than backed off.
        #expect(probe.fetchCount == 2)
        #expect(store.snapshot(for: .codex) == before)
        #expect(store.snapshot(for: .codex).freshness == .live)
        #expect(store.scheduler.wakeDelay() <= 1)
    }

    @Test func aPermanentlyUnreadableIdentityEndsInAStaleRowWithBackoff() async {
        let clock = MutableDateSource(t0)
        let script = Script([live(.claude, at: t0), .identityUnreadable(for: .claude)])
        let probe = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: ProbeOrder(),
                              result: { script.next() })
        let store = store(probe, clock: clock)
        await store.refreshAll()

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await store.waitForAccountProbesToFinish()

        // Two refusals, then the third is merged as an ordinary transient failure: the
        // last-known windows stay, dimmed, and the account backs off instead of looping.
        #expect(probe.fetchCount == 1 + AccountProbeScheduler.identityRefusalBound + 1)
        #expect(store.snapshot(for: .claude).freshness == .stale(UsageProviderFetchResult.identityUnconfirmedReason))
        #expect(store.snapshot(for: .claude).windows.count == 1)
        #expect(store.scheduler.wakeDelay() > 60)
    }

    @Test func aRefusalInsideAUserRefreshIsReQueuedOnceAndTheRefreshCompletes() async {
        let clock = MutableDateSource(t0)
        let script = Script([.identityUnreadable(for: .codex), live(.codex, used: 25, at: t0)])
        let probe = LaneProbe(id: .codex, accountID: .primary, lane: .concurrent, order: ProbeOrder(),
                              result: { script.next() })
        let store = store(probe, clock: clock)

        await store.refreshAll()

        #expect(probe.fetchCount == 2)
        #expect(store.snapshot(for: .codex).windows.first?.utilization == 25)
        #expect(store.isRefreshing == false)
        #expect(store.refreshProgress == nil)
        #expect(store.userRefreshRun?.entries[probe.accountKey]?.outcome == .live)
    }

    @Test func aSecondRefusalInsideOneUserRefreshIsNotQueuedAgain() async {
        let clock = MutableDateSource(t0)
        let probe = LaneProbe(id: .codex, accountID: .primary, lane: .concurrent, order: ProbeOrder(),
                              result: { .identityUnreadable(for: .codex) })
        let store = store(probe, clock: clock)

        await store.refreshAll()

        #expect(probe.fetchCount == 2)
        #expect(store.isRefreshing == false)
        #expect(store.snapshot(for: .codex).freshness == .pending)
    }
}
