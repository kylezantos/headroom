import Foundation
import Testing

@testable import HeadroomCore

/// U6 (KTD14.4, KTD14.5): the one in-flight full refresh inside `refreshAll()`, and the
/// whole Mac check-now path end to end — the real store, scheduler, coordinator and
/// coalesced publisher over an in-memory KVS — down to the phone completing on the bytes
/// the Mac left in iCloud.
@MainActor
@Suite
struct FullRefreshGuardTests {
    private let reset = Date(timeIntervalSince1970: 3_000_000)
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private let phone = "a1a1a1a1-0000-4000-8000-000000000001"
    private let workID = AccountID("work")

    private struct Rig {
        let store: UsageStore
        let coordinator: CheckNowCoordinator
        let kvs: RecordingKeyValueStore
        let primary: LaneProbe
        let work: LaneProbe
        let spend: GatedSpendProvider
        let clock: ManualClock
        let sourceID: String
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.fullrefresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func rig(sync: Bool = true) -> Rig {
        let clock = ManualClock(t0)
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.syncToIPhoneEnabled = sync
        preferences.setSurfaceEnabled(true, for: UsageSurface.api(for: .claude)!)
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let reset = self.reset
        let live: @Sendable () -> UsageProviderFetchResult = {
            .init(snapshot: UsageSnapshot(
                providerID: .claude, windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset)],
                planLabel: "Max", capturedAt: clock.now, freshness: .live))
        }
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order, result: live)
        let work = LaneProbe(id: .claude, accountID: workID, lane: lane, order: order, result: live)
        let spend = GatedSpendProvider(id: .claude)
        let kvs = RecordingKeyValueStore()
        let lineage = CompanionLineage(defaults: defaults)
        let sync = CompanionPhoneSync(
            store: kvs, lineage: lineage, diagnosticsStore: nil, macAppVersion: "1.5"
        ) { configuration in
            configuration.now = { clock.now }
            configuration.autoSchedule = false
        }
        let store = UsageStore(
            providers: [primary, work], apiSpendProviders: [spend], preferences: preferences,
            accounts: [.builtIn(for: .claude), ProviderAccount(id: workID, providerID: .claude, label: "Work")],
            now: { clock.now }, phoneSyncExporter: sync)
        let coordinator = CheckNowCoordinator(
            store: kvs, host: store, ledger: CheckNowLedger(defaults: defaults),
            configuration: .init(sourceID: lineage.sourceID, now: { clock.now }, sleep: { clock.advance($0) }))
        return Rig(store: store, coordinator: coordinator, kvs: kvs, primary: primary, work: work, spend: spend,
                   clock: clock, sourceID: lineage.sourceID)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func request(_ r: Rig, id: String) -> CompanionRequest {
        let request = try! CompanionRequest(requestID: id, requestedAt: CompanionWireDate(date: r.clock.now)!, sourceID: r.sourceID)
        let key = CompanionSyncKeys.request(deviceUUID: phone)!
        r.kvs.seed(key, try! CompanionSyncCodec.encode(request))
        r.coordinator.receive(iCloudKeyValueChange(reason: .serverChange, changedKeys: [key]))
        return request
    }

    private func receipt(_ r: Rig) -> CompanionReceipt? {
        if case .value(let receipt) = CompanionSyncCodec.decodeReceipt(r.kvs.data(forKey: CompanionSyncKeys.receipt)) {
            return receipt
        }
        return nil
    }

    private func requestID(_ n: Int) -> String { String(format: "c0c0c0c0-0000-4000-8000-%012d", n) }

    // MARK: The guard (KTD14.4)

    /// Popover and launch triggers while one full refresh runs await it: one probe round,
    /// one start time, one completion time.
    @Test func aSecondFullRefreshAwaitsTheOneInFlight() async {
        let r = rig()
        r.primary.suspendNextFetch()
        let launch = Task { await r.store.refreshAll() }
        await r.primary.waitUntilStarted()
        #expect(r.store.fullRefreshStartedAt == t0)
        r.clock.advance(3)
        let popover = Task { await r.store.refreshAll() }
        let again = Task { await r.store.refreshAll() }
        await Task.yield()
        #expect(r.store.fullRefreshStartedAt == t0)
        r.primary.release()
        await launch.value
        await popover.value
        await again.value
        #expect(r.primary.fetchCount == 1 && r.work.fetchCount == 1)
        #expect(r.store.fullRefreshStartedAt == nil && r.store.lastFullRefreshCompletedAt == r.clock.now)
        #expect(!r.store.isRefreshing)
    }

    /// Timer passes stay out of `isRefreshing` and are not full refreshes.
    @Test func aTimerPassIsNeitherRefreshingNorAFullRefresh() async {
        let r = rig()
        r.primary.suspendNextFetch()
        r.store.dispatchDueNow()
        await r.primary.waitUntilStarted()
        #expect(!r.store.isRefreshing && r.store.fullRefreshStartedAt == nil)
        r.primary.release()
        await settle { r.store.probingAccounts.isEmpty && r.work.fetchCount == 1 }
        #expect(r.store.lastFullRefreshCompletedAt == nil)
    }

    // MARK: End to end (KTD14.5–7)

    /// The finished receipt follows the forced flush whose manifest echoes the answer, and the
    /// phone, resolving exactly the bytes in iCloud, reaches "Just now".
    @Test func aPhoneRequestRefreshesOnceAndThePhoneCompletesOnTheFlushedGeneration() async throws {
        let r = rig()
        r.coordinator.start()
        let asked = request(r, id: requestID(1))
        await settle { receipt(r)?.state == .finished }
        #expect(r.primary.fetchCount == 1 && r.work.fetchCount == 1)

        let finished = try #require(receipt(r))
        let generation = try #require(finished.finishedGeneration)
        #expect(finished.requestIDs == [asked.requestID] && finished.total == 2 && finished.completed == 2)

        // Order: the manifest carrying the answer lands before the finished receipt.
        let ops = r.kvs.operations
        let receiptIndex = try #require(ops.lastIndex(of: .set(CompanionSyncKeys.receipt)))
        let manifestIndex = try #require(ops.lastIndex(of: .set(CompanionSyncKeys.manifest)))
        #expect(manifestIndex < receiptIndex)
        guard case .value(.active(let manifest)) = CompanionSyncCodec.decodeManifest(r.kvs.data(forKey: CompanionSyncKeys.manifest)) else {
            Issue.record("no manifest"); return
        }
        #expect(manifest.generation == generation)
        #expect(manifest.answeredRequests.map(\.requestID) == [asked.requestID])
        #expect(manifest.answeredRequests.first?.finishedGeneration == generation)

        // The phone side, from the KVS bytes alone.
        var providerKeys: [String: Data] = [:]
        for key in r.kvs.keys(withPrefix: CompanionSyncKeys.providerPrefix) {
            providerKeys[CompanionSyncKeys.providerID(fromKey: key)!] = r.kvs.data(forKey: key)
        }
        let resolved = CompanionSnapshotResolver.resolve(
            .init(manifest: r.kvs.data(forKey: CompanionSyncKeys.manifest), providerKeys: providerKeys,
                  v3: r.kvs.data(forKey: iCloudSnapshotSync.snapshotKey), now: r.clock.now)).snapshot
        #expect(resolved.content?.assembledGeneration == generation)
        var state = CheckNowRequestState(
            requestID: asked.requestID, sourceID: r.sourceID, askedAt: t0, largestLaneAccountCount: 2)
        state = CheckNowMachine.receive(finished, into: state, now: t0)
        state = CheckNowMachine.receive(resolved, into: state, now: t0)
        #expect(CheckNowStatus.make(state: state, snapshot: resolved, now: t0).line == .message("Just now"))
    }

    /// A request during the launch refresh joins it: one probe round.
    @Test func aRequestDuringTheLaunchRefreshProducesOnePass() async {
        let r = rig()
        r.primary.suspendNextFetch()
        let launch = Task { await r.store.refreshAll() }
        await r.primary.waitUntilStarted()
        r.coordinator.start()
        _ = request(r, id: requestID(1))
        await settle { receipt(r) != nil }
        #expect(receipt(r)?.state == .accepted || receipt(r)?.state == .running)
        r.primary.release()
        await launch.value
        await settle { receipt(r)?.state == .finished }
        #expect(r.primary.fetchCount == 1 && r.work.fetchCount == 1)
        #expect(receipt(r)?.state == .finished)
    }

    /// A request during a single-account Check Now starts a full pass whose receipt counts
    /// every account.
    @Test func aRequestDuringASingleAccountCheckStartsAFullPassCountingEveryAccount() async {
        let r = rig()
        r.coordinator.start()
        r.primary.suspendNextFetch()
        r.store.refreshAccountNow(r.primary.accountKey)
        await r.primary.waitUntilStarted()
        #expect(r.store.fullRefreshStartedAt == nil)
        _ = request(r, id: requestID(1))
        await settle { r.store.fullRefreshStartedAt != nil }
        r.primary.release()
        await settle { receipt(r)?.state == .finished }
        let finished = receipt(r)
        #expect(finished?.total == 2 && finished?.completed == 2)
        #expect(r.primary.fetchCount == 1 && r.work.fetchCount == 1)
    }

    /// A spend-only refresh is not a full refresh: it never answers a request, sets no
    /// cooldown, and a request during it starts the subscription pass.
    @Test func aSpendOnlyRefreshNeverAnswersARequest() async {
        let r = rig()
        r.coordinator.start()
        r.spend.gate.suspendNextFetch()
        let spendOnly = Task { await r.store.refreshAPISpendOnly() }
        await r.spend.gate.waitUntilStarted()
        #expect(r.store.fullRefreshStartedAt == nil && r.store.lastFullRefreshCompletedAt == nil)
        r.primary.suspendNextFetch()
        _ = request(r, id: requestID(1))
        await r.primary.waitUntilStarted()
        #expect(receipt(r)?.state != .finished)
        r.primary.release()
        await settle { receipt(r)?.state == .finished }
        #expect(receipt(r)?.state == .finished && r.work.fetchCount == 1)
        r.spend.gate.release()
        await spendOnly.value
    }

    /// Cooldown on the real store: inside 60 s of a popover refresh, no probes, one forced
    /// flush, and the answer names its generation.
    @Test func aRequestInsideTheCooldownForcesAFlushAndProbesNothing() async throws {
        let r = rig()
        r.coordinator.start()
        await r.store.refreshAll()
        await settle { r.kvs.data(forKey: CompanionSyncKeys.manifest) != nil }
        r.clock.advance(30)
        _ = request(r, id: requestID(1))
        await settle { receipt(r)?.state == .cooldown }
        let answer = try #require(receipt(r))
        #expect(r.primary.fetchCount == 1 && r.work.fetchCount == 1)
        guard case .value(.active(let manifest)) = CompanionSyncCodec.decodeManifest(r.kvs.data(forKey: CompanionSyncKeys.manifest)) else {
            Issue.record("no manifest"); return
        }
        #expect(answer.finishedGeneration == manifest.generation)
        #expect(manifest.answeredRequests.first?.outcome == .cooldown)
        #expect(answer.checkedAt == CompanionWireDate(date: t0))
    }

    /// V21: with sync off the real store ignores requests and writes nothing.
    @Test func withSyncOffTheStoreIgnoresRequests() async {
        let r = rig(sync: false)
        r.coordinator.start()
        _ = request(r, id: requestID(1))
        for _ in 0..<50 { await Task.yield() }
        #expect(r.primary.fetchCount == 0 && receipt(r) == nil)
    }
}
