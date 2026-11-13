import Foundation
import Testing
@testable import HeadroomCore

// U3 of the OpenCode plan: OpenCode accounts in the store — surface eligibility, per-account
// plan status through continuity, the KTD7 re-check after See Go Plans, and removal while a
// capture is in flight. All doubles; no CLI (AGENTS.md).

private func freshDefaults() -> UserDefaults {
    let suite = "headroom.opencode-store.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private struct NoopStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .success(()) }
}

/// A source scripted per home, with one optional gate that holds the next capture open.
private actor ScriptedOpenCodeSource: OpenCodeUsageSource {
    private var scripts: [OpenCodeAccountHome: [OpenCodeCapture]]
    private var gate: CheckedContinuation<Void, Never>?
    private var holdsNext = false
    private var heldWaiter: CheckedContinuation<Void, Never>?
    private(set) var counts: [OpenCodeAccountHome: Int] = [:]

    init(_ scripts: [OpenCodeAccountHome: [OpenCodeCapture]]) { self.scripts = scripts }

    func count(_ home: OpenCodeAccountHome) -> Int { counts[home, default: 0] }
    func holdNextCapture() { holdsNext = true }
    func release() { gate?.resume(); gate = nil }
    func waitUntilHeld() async {
        if gate != nil { return }
        await withCheckedContinuation { heldWaiter = $0 }
    }

    func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        counts[home, default: 0] += 1
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { continuation in
                gate = continuation
                heldWaiter?.resume()
                heldWaiter = nil
            }
        }
        var list = scripts[home] ?? [.failed(.signedOut)]
        let next = list.count > 1 ? list.removeFirst() : list[0]
        scripts[home] = list
        return next
    }
}

@MainActor
@Suite struct OpenCodeStoreTests {
    private let go = OpenCodeCapture.goUsage(OpenCodeGoUsage(
        rolling: .init(percentUsed: 10, isLimited: false, resetsAt: Date(timeIntervalSince1970: 3_000_000)),
        weekly: .init(percentUsed: 20, isLimited: false, resetsAt: Date(timeIntervalSince1970: 3_000_000)),
        monthly: .init(percentUsed: 30, isLimited: false, resetsAt: Date(timeIntervalSince1970: 3_000_000))
    ))
    private let work = OpenCodeAccountHome.isolated(root: "/tmp/opencode-work")
    private let builtInKey = AccountKey(providerID: .opencode, accountID: .primary)

    private func makeStore(
        source: ScriptedOpenCodeSource,
        clock: MutableDateSource? = nil,
        otherProviders: [any UsageProvider] = []
    ) -> (UsageStore, ProviderAccount) {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let extra = registry.addAccount(for: .opencode)!
        let work = work
        let now: @Sendable () -> Date = { clock?.now() ?? Date() }
        let store = UsageStore(
            providers: [
                OpenCodeProvider(source: source, accountID: .primary, home: .builtIn, now: now),
                OpenCodeProvider(source: source, accountID: extra.id, home: work, now: now),
            ] + otherProviders,
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: NoopStorage(),
            providerFactory: { account in
                OpenCodeProvider(source: source, accountID: account.id, home: work, now: now)
            },
            now: now
        )
        return (store, extra)
    }

    private func yieldALot() async {
        for _ in 0..<100 { await Task.yield() }
    }

    @Test func theSurfaceIsOffByDefaultAndPollsOnceTurnedOn() async {
        let source = ScriptedOpenCodeSource([.builtIn: [go], work: [go]])
        let (store, _) = makeStore(source: source)
        #expect(!store.isSurfaceEnabled(.opencodeSubscription))
        #expect(store.providerOrder.isEmpty)
        #expect(store.registeredProviderOrder == [.opencode])
        await store.refreshAll()
        #expect(await source.count(.builtIn) == 0)

        store.setSurfaceEnabled(true, for: .opencodeSubscription)
        #expect(store.providerOrder == [.opencode])
        await store.refreshAll()
        #expect(await source.count(.builtIn) == 1)
        #expect(await source.count(work) == 1)

        store.setSurfaceEnabled(false, for: .opencodeSubscription)
        await store.refreshAll()
        #expect(await source.count(.builtIn) == 1)
    }

    @Test func eachAccountReadsItsOwnHomeAndKeepsItsOwnPlanStatus() async {
        let source = ScriptedOpenCodeSource([
            .builtIn: [go],
            work: [.noGoPlan, .failed(.transient(.consoleUnavailable)), go],
        ])
        let (store, extra) = makeStore(source: source)
        store.setSurfaceEnabled(true, for: .opencodeSubscription)

        await store.refreshAll()
        #expect(store.snapshot(for: builtInKey).planStatus == nil)
        #expect(store.snapshot(for: builtInKey).windows.count == 3)
        #expect(store.snapshot(for: extra.key).planStatus == .noActivePlan)
        #expect(store.snapshot(for: extra.key).freshness == .live)

        // A failed poll keeps the no-plan row (KTD7) on that account only.
        await store.refreshAccount(extra.key)
        #expect(store.snapshot(for: extra.key).planStatus == .noActivePlan)
        #expect(store.snapshot(for: extra.key).freshness == .stale(.providerSetup(.opencodeTransientCapture)))
        #expect(store.snapshot(for: builtInKey).planStatus == nil)

        // Buying Go clears it.
        await store.refreshAccount(extra.key)
        #expect(store.snapshot(for: extra.key).planStatus == nil)
        #expect(store.snapshot(for: extra.key).windows.count == 3)
    }

    /// KTD7: See Go Plans arms one re-check, which the next popover open spends.
    @Test func seeGoPlansArmsOneRecheckForTheNextPopoverOpen() async {
        let source = ScriptedOpenCodeSource([.builtIn: [.noGoPlan, go], work: [go]])
        let (store, extra) = makeStore(source: source)
        store.setSurfaceEnabled(true, for: .opencodeSubscription)
        await store.refreshAccount(builtInKey)
        await store.refreshAccount(extra.key)
        #expect(store.snapshot(for: builtInKey).planStatus == .noActivePlan)
        #expect(await source.count(.builtIn) == 1)

        // An unarmed open with fresh captures probes nothing.
        store.refreshOnPopoverOpen()
        await yieldALot()
        #expect(await source.count(.builtIn) == 1)

        store.armRecheckOnNextPopoverOpen(builtInKey)
        store.armRecheckOnNextPopoverOpen(builtInKey)
        // An armed account that is not in the no-plan state is skipped.
        store.armRecheckOnNextPopoverOpen(extra.key)
        store.refreshOnPopoverOpen()
        #expect(store.popoverOpenRechecks.isEmpty)
        for _ in 0..<500 where store.snapshot(for: builtInKey).planStatus != nil { await Task.yield() }
        #expect(store.snapshot(for: builtInKey).planStatus == nil)
        #expect(await source.count(.builtIn) == 2)
        #expect(await source.count(work) == 1)

        // Spent: the next open probes nothing more.
        store.refreshOnPopoverOpen()
        await yieldALot()
        #expect(await source.count(.builtIn) == 2)
    }

    /// The armed re-check is a user-origin request, so it raises `isRefreshing`; it must not
    /// make the open skip the ordinary wake for another provider's due account. (Accounts in
    /// OpenCode's own lane wait for the lane's next pass either way: a draining lane is left
    /// alone by `dispatchDue`.)
    @Test func anArmedRecheckNeverSuppressesThePopoverOpenWakeForOtherProviders() async {
        let clock = MutableDateSource(Date(timeIntervalSince1970: 2_000_000_000))
        let claude = ClockedClaudeProvider(clock: clock)
        let source = ScriptedOpenCodeSource([.builtIn: [.noGoPlan, go], work: [go]])
        let (store, extra) = makeStore(source: source, clock: clock, otherProviders: [claude])
        let claudeKey = AccountKey(providerID: .claude, accountID: .primary)
        store.setSurfaceEnabled(true, for: .opencodeSubscription)
        await store.refreshAccount(builtInKey)
        await store.refreshAccount(extra.key)
        await store.refreshAccount(claudeKey)
        #expect(claude.fetchCount == 1)

        // Every capture has aged a full interval, so this open wakes the queue.
        clock.set(clock.now().addingTimeInterval(Double(Preferences.defaultIntervalMinutes) * 60 + 1))
        store.armRecheckOnNextPopoverOpen(builtInKey)
        store.refreshOnPopoverOpen()
        for _ in 0..<2_000 {
            if claude.fetchCount >= 2, store.snapshot(for: builtInKey).planStatus == nil { break }
            await Task.yield()
        }
        #expect(store.snapshot(for: builtInKey).planStatus == nil, "the armed re-check ran")
        #expect(claude.fetchCount == 2, "the other provider's due account was woken too")
    }

    @Test func aCaptureThatLandsAfterRemovalNeverResurrectsTheRow() async {
        let source = ScriptedOpenCodeSource([.builtIn: [go], work: [.noGoPlan]])
        let (store, extra) = makeStore(source: source)
        store.setSurfaceEnabled(true, for: .opencodeSubscription)
        await source.holdNextCapture()
        store.refreshAccountNow(extra.key)
        await source.waitUntilHeld()

        #expect(await store.removeAccount(extra.key) == .removed)
        await source.release()
        await yieldALot()
        #expect(!store.accounts(for: .opencode).contains { $0.key == extra.key })
        #expect(store.snapshots[extra.key] == nil)
    }
}

/// A Claude account on its own lane whose capture time is the test's clock, so capture age,
/// which the popover-open gate reads, is deterministic.
private final class ClockedClaudeProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .claude
    let accountID: AccountID = .primary
    let displayName = "Claude"
    let pollingLane: ProviderPollingLane = .serial("claude-cli")
    private let clock: MutableDateSource
    private let lock = NSLock()
    private var count = 0

    init(clock: MutableDateSource) { self.clock = clock }

    var fetchCount: Int { lock.withLock { count } }

    func fetchSnapshot() async -> UsageSnapshot {
        lock.withLock { count += 1 }
        return UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: clock.now().addingTimeInterval(3_600))],
            planLabel: nil,
            capturedAt: clock.now(),
            freshness: .live
        )
    }
}
