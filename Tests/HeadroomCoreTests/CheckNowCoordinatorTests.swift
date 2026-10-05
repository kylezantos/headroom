import Foundation
import Testing

@testable import HeadroomCore

/// U6 (KTD14.2–14.8, R19): the Mac's check-now intake, launch scan, dedupe, cooldown and
/// receipts, against a controllable host and an in-memory KVS double. The store-level guard
/// and the real publisher are covered end to end in `FullRefreshGuardTests`.
@MainActor
@Suite
struct CheckNowCoordinatorTests {
    private typealias F = CompanionFixtures
    private let iPhone = "a1a1a1a1-0000-4000-8000-000000000001"
    private let iPad = "b2b2b2b2-0000-4000-8000-000000000002"
    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    private struct Rig {
        let coordinator: CheckNowCoordinator
        let host: FakeCheckNowHost
        let store: CheckNowKeyValueStore
        let clock: ManualClock
        let ledger: CheckNowLedger
        let defaults: UserDefaults
    }

    private func rig(
        store: CheckNowKeyValueStore = CheckNowKeyValueStore(), defaults: UserDefaults? = nil,
        clock: ManualClock? = nil
    ) -> Rig {
        let clock = clock ?? ManualClock(t0)
        let defaults = defaults ?? freshDefaults()
        let host = FakeCheckNowHost(store: store, clock: clock)
        let ledger = CheckNowLedger(defaults: defaults)
        let coordinator = CheckNowCoordinator(
            store: store, host: host, ledger: ledger,
            configuration: .init(sourceID: F.macA, now: { clock.now }, sleep: { clock.advance($0) }))
        return Rig(coordinator: coordinator, host: host, store: store, clock: clock, ledger: ledger, defaults: defaults)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.checknow.mac.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func requestID(_ n: Int) -> String { String(format: "c0c0c0c0-0000-4000-8000-%012d", n) }

    /// A phone writes its install's request key (overwriting its previous request).
    @discardableResult
    private func phoneWrites(
        _ device: String, id: String, at date: Date? = nil, source: String = CompanionFixtures.macA,
        into store: CheckNowKeyValueStore
    ) -> String {
        let key = CompanionSyncKeys.request(deviceUUID: device)!
        let request = try! CompanionRequest(
            requestID: id, requestedAt: CompanionWireDate(date: date ?? t0)!, sourceID: source)
        store.seed(key, F.bytes(request))
        return key
    }

    private func change(_ keys: [String], _ reason: iCloudKeyValueChangeReason = .serverChange) -> iCloudKeyValueChange {
        iCloudKeyValueChange(reason: reason, changedKeys: keys)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            await Task.yield()
        }
    }

    /// Bounded: a regression that leaves a run open fails the expectations after it instead
    /// of hanging the suite.
    private func drain(_ r: Rig) async {
        await settle { !r.coordinator.hasPendingWork }
    }

    private func receipt(_ store: CheckNowKeyValueStore) -> CompanionReceipt? {
        if case .value(let receipt) = CompanionSyncCodec.decodeReceipt(store.data(forKey: CompanionSyncKeys.receipt)) {
            return receipt
        }
        return nil
    }

    private func receiptWrites(_ store: CheckNowKeyValueStore) -> Int {
        store.setKeys.filter { $0 == CompanionSyncKeys.receipt }.count
    }

    /// Starts a run from one request and waits until the refresh is held open.
    private func startRun(_ r: Rig, device: String? = nil, id: String) async {
        let key = phoneWrites(device ?? iPhone, id: id, into: r.store)
        r.coordinator.receive(change([key]))
        await settle { r.host.waitingCount > 0 }
    }

    // MARK: One refresh (V18/AE3, V19, V20)

    /// AE3: five requests in ten seconds — even five distinct IDs from one phone — run one
    /// refresh, and every one of them is answered by it.
    @Test func fiveRequestsInTenSecondsRunExactlyOneRefresh() async {
        let r = rig()
        r.coordinator.start()
        for n in 1...5 {
            let key = phoneWrites(iPhone, id: requestID(n), into: r.store)
            r.coordinator.receive(change([key]))
            r.clock.advance(2)
            await settle { r.host.waitingCount > 0 }
        }
        #expect(r.host.refreshes == 1)
        r.host.completeRefresh()
        await drain(r)
        let finished = receipt(r.store)
        #expect(finished?.state == .finished)
        #expect(Set(finished?.requestIDs ?? []) == Set((1...5).map(requestID)))
        #expect(Set(r.host.history.map(\.requestID)) == Set((1...5).map(requestID)))
        #expect(r.host.publishes.count == 1)
    }

    /// V19: an iPhone and an iPad 2 s apart share one refresh and both finish.
    @Test func iPhoneAndIPadTwoSecondsApartShareOneRefresh() async {
        let r = rig()
        r.coordinator.start()
        await startRun(r, device: iPhone, id: requestID(1))
        r.clock.advance(2)
        let key = phoneWrites(iPad, id: requestID(2), into: r.store)
        r.coordinator.receive(change([key]))
        r.clock.advance(20)
        r.host.report(total: 2, completed: 1, landed: try? CompanionLastLanded(providerID: "claude", accountID: "primary", live: true))
        await settle { receipt(r.store)?.requestIDs.count == 2 }
        #expect(receipt(r.store)?.requestIDs.sorted() == [requestID(1), requestID(2)])
        r.host.completeRefresh()
        await drain(r)
        #expect(r.host.refreshes == 1)
        let finished = receipt(r.store)
        #expect(finished?.state == .finished && finished?.finishedGeneration == 10)
        #expect(finished?.answeredRequests.map(\.requestID).sorted() == [requestID(1), requestID(2)])
        #expect(r.ledger.lastHandled(device: iPhone) == requestID(1) && r.ledger.lastHandled(device: iPad) == requestID(2))
    }

    /// V20: a request during a Mac-started refresh joins it: no second refresh, and the run
    /// keeps the Mac refresh's start time.
    @Test func aRequestDuringAMacStartedRefreshJoinsIt() async {
        let r = rig()
        r.coordinator.start()
        let started = r.clock.now
        let mac = r.host.beginMacRefresh()
        r.clock.advance(5)
        await startRun(r, id: requestID(1))
        #expect(r.host.refreshes == 1)
        #expect(receipt(r.store)?.state == .accepted && receipt(r.store)?.startedAt == CompanionWireDate(date: started))
        r.host.completeRefresh()
        await mac.value
        await drain(r)
        #expect(r.host.refreshes == 1 && receipt(r.store)?.state == .finished)
    }

    // MARK: Ignored requests (V21, KTD14.2)

    @Test func requestsWhileSyncIsOffAreIgnoredAndWriteNothing() async {
        let r = rig()
        r.host.syncEnabled = false
        let key = phoneWrites(iPhone, id: requestID(1), into: r.store)
        r.coordinator.receive(change([key]))
        r.coordinator.start()
        r.coordinator.receive(change([key]))
        await drain(r)
        #expect(r.host.refreshes == 0 && r.store.setKeys.isEmpty && r.store.removedKeys.isEmpty)
    }

    @Test func aRequestAddressedToAnotherMacIsIgnored() async {
        let r = rig()
        r.coordinator.start()
        let key = phoneWrites(iPhone, id: requestID(1), source: F.macB, into: r.store)
        r.coordinator.receive(change([key]))
        await drain(r)
        #expect(r.host.refreshes == 0 && r.store.setKeys.isEmpty)
    }

    @Test func nonRequestKeysAndMalformedSuffixesAreIgnored() async {
        let r = rig()
        r.coordinator.start()
        r.store.seed(CompanionSyncKeys.requestPrefix + "My-iPhone", Data("{}".utf8))
        r.coordinator.receive(change([CompanionSyncKeys.manifest, CompanionSyncKeys.requestPrefix + "My-iPhone"]))
        await drain(r)
        #expect(r.host.refreshes == 0)
    }

    // MARK: Launch (AE2, KTD14.2, KTD14.3)

    /// A request written while Headroom was quit is found by the launch scan and run once.
    @Test func aQuitTimeRequestIsFoundByTheLaunchScanAndRunOnce() async {
        let r = rig()
        phoneWrites(iPhone, id: requestID(1), at: t0.addingTimeInterval(-90), into: r.store)
        r.coordinator.start()
        await settle { r.host.waitingCount > 0 }
        #expect(r.host.refreshes == 1)
        r.host.completeRefresh()
        await drain(r)
        #expect(receipt(r.store)?.state == .finished)
    }

    /// AE2: older than 10 minutes plus 2 minutes of skew, found at launch (or delivered by the
    /// first sync after launch), it is ignored. A live notification has no age check.
    @Test func aLaunchRequestOlderThanTheAgeLimitIsIgnored() async {
        let r = rig()
        phoneWrites(iPhone, id: requestID(1), at: t0.addingTimeInterval(-(12 * 60 + 1)), into: r.store)
        r.coordinator.start()
        let late = phoneWrites(iPad, id: requestID(2), at: t0.addingTimeInterval(-(13 * 60)), into: r.store)
        r.coordinator.receive(change([late], .initialSyncChange))
        await drain(r)
        #expect(r.host.refreshes == 0)

        // Inside the backstop (11 minutes, a phone clock running behind): accepted.
        let skewed = rig()
        phoneWrites(iPhone, id: requestID(3), at: t0.addingTimeInterval(-11 * 60), into: skewed.store)
        skewed.coordinator.start()
        await settle { skewed.host.waitingCount > 0 }
        #expect(skewed.host.refreshes == 1)
        skewed.host.completeRefresh()
        await drain(skewed)

        // A running Mac compares no clocks: a live request with an old phone clock runs.
        let live = rig()
        live.coordinator.start()
        await startRun(live, id: requestID(4))
        #expect(live.host.refreshes == 1)
        live.host.completeRefresh()
        await drain(live)
    }

    /// KTD14.2: requests seen before `start()` queue, then join the launch refresh.
    @Test func requestsSeenBeforeStartJoinTheLaunchRefresh() async {
        let r = rig()
        let key = phoneWrites(iPhone, id: requestID(1), into: r.store)
        r.coordinator.receive(change([key]))
        #expect(r.store.setKeys.isEmpty)
        let launch = r.host.beginMacRefresh()
        r.coordinator.start()
        await settle { r.host.waitingCount > 1 }
        #expect(r.host.refreshes == 1)
        r.host.completeRefresh()
        await launch.value
        await drain(r)
        #expect(receipt(r.store)?.state == .finished && receipt(r.store)?.requestIDs == [requestID(1)])
    }

    /// KTD14.3: a handled request replayed by the initial sync after a relaunch is ignored.
    @Test func aHandledRequestReplayedAfterARelaunchIsIgnored() async {
        let store = CheckNowKeyValueStore()
        let defaults = freshDefaults()
        let first = rig(store: store, defaults: defaults)
        first.coordinator.start()
        await startRun(first, id: requestID(1))
        first.host.completeRefresh()
        await drain(first)

        let clock = ManualClock(t0.addingTimeInterval(5 * 60))
        let relaunched = rig(store: store, defaults: defaults, clock: clock)
        // The first manifest after relaunch still echoes the answer (Decision 2).
        #expect(relaunched.host.history.map(\.requestID) == [requestID(1)])
        relaunched.coordinator.start()
        relaunched.coordinator.receive(change([CompanionSyncKeys.request(deviceUUID: iPhone)!], .initialSyncChange))
        await drain(relaunched)
        #expect(relaunched.host.refreshes == 0)
    }

    // MARK: Cooldown (KTD14.4)

    @Test func aRequestInsideSixtySecondsOfAnyFullRefreshGetsACooldownAnswer() async {
        let r = rig()
        r.coordinator.start()
        let mac = r.host.beginMacRefresh()
        await settle { r.host.waitingCount > 0 }
        r.host.completeRefresh()
        await mac.value
        r.clock.advance(40)
        let key = phoneWrites(iPhone, id: requestID(1), into: r.store)
        r.coordinator.receive(change([key]))
        await drain(r)
        #expect(r.host.refreshes == 1)
        // It republished (flushing anything dirty) before answering, and names that flush.
        #expect(r.host.publishes.map { $0.map(\.outcome) } == [[.cooldown]])
        let answer = receipt(r.store)
        #expect(answer?.state == .cooldown && answer?.finishedGeneration == 10)
        #expect(answer?.checkedAt == CompanionWireDate(date: t0))
        #expect(answer?.answeredRequests.first?.finishedGeneration == 10)
        let manifestIndex = r.store.setKeys.firstIndex(of: CompanionSyncKeys.manifest)
        let receiptIndex = r.store.setKeys.lastIndex(of: CompanionSyncKeys.receipt)
        #expect(manifestIndex != nil && receiptIndex != nil && manifestIndex! < receiptIndex!)

        // Past the cooldown, a new request refreshes again.
        r.clock.advance(61)
        await startRun(r, id: requestID(2))
        #expect(r.host.refreshes == 2)
        r.host.completeRefresh()
        await drain(r)
    }

    // MARK: Finish and receipts (KTD14.5, KTD14.6, KTD8)

    @Test func theFinishedReceiptIsWrittenOnlyAfterTheForcedFlush() async {
        let r = rig()
        r.coordinator.start()
        await startRun(r, id: requestID(1))
        #expect(r.host.publishes.isEmpty)
        r.host.completeRefresh()
        await drain(r)
        let keys = r.store.setKeys
        let manifest = keys.lastIndex(of: CompanionSyncKeys.manifest)!
        #expect(keys.last == CompanionSyncKeys.receipt && manifest < keys.count - 1)
        let finished = receipt(r.store)
        #expect(finished?.finishedGeneration == 10)
        #expect(r.host.publishes.first?.first?.finishedGeneration == 10)
    }

    /// Progress reaches the receipt from the user-progress callback, never more often than
    /// every 15 s while the check runs; the finished receipt keeps the final counts.
    @Test func progressReceiptsAreSpacedAtLeastFifteenSecondsApart() async {
        let r = rig()
        r.coordinator.start()
        await startRun(r, id: requestID(1))
        #expect(receiptWrites(r.store) == 1)
        let landed = try? CompanionLastLanded(providerID: "claude", accountID: "work", live: false)
        r.host.report(total: 3, completed: 1, landed: landed)
        r.host.report(total: 3, completed: 2, landed: landed)
        await settle { receiptWrites(r.store) == 2 }
        #expect(receiptWrites(r.store) == 2)
        #expect(r.clock.now == t0.addingTimeInterval(15))
        let running = receipt(r.store)
        #expect(running?.state == .running && running?.completed == 2 && running?.total == 3)
        #expect(running?.lastLanded == landed)
        r.host.report(total: 3, completed: 3, landed: landed)
        r.host.completeRefresh()
        await drain(r)
        let finished = receipt(r.store)
        #expect(finished?.state == .finished && finished?.completed == 3 && finished?.total == 3)
    }

    @Test func aFailedFlushAnswersFailedWithoutClaimingAFinish() async {
        let r = rig()
        r.coordinator.start()
        await startRun(r, id: requestID(1))
        r.host.publishFails = true
        r.host.completeRefresh()
        await drain(r)
        let last = receipt(r.store)
        #expect(last?.state == .accepted && last?.finishedGeneration == nil)
        #expect(last?.answeredRequests.first(where: { $0.requestID == requestID(1) })?.outcome == .failed)
    }

    /// Sync turned off mid-run: the publisher's sweep owns cleanup; nothing more is written.
    @Test func syncTurnedOffMidRunWritesNoFinish() async {
        let r = rig()
        r.coordinator.start()
        await startRun(r, id: requestID(1))
        r.host.syncEnabled = false
        let writes = receiptWrites(r.store)
        r.host.completeRefresh()
        await drain(r)
        #expect(receiptWrites(r.store) == writes && r.host.publishes.isEmpty)
    }

    // MARK: Cleanup (KTD14.8)

    @Test func requestKeysOlderThanThirtyDaysArePrunedAndNothingElseIsDeleted() async {
        let r = rig()
        let old = phoneWrites(iPhone, id: requestID(1), at: t0.addingTimeInterval(-31 * 24 * 3600), into: r.store)
        let recent = phoneWrites(iPad, id: requestID(2), at: t0.addingTimeInterval(-29 * 24 * 3600), into: r.store)
        let unreadable = CompanionSyncKeys.request(deviceUUID: "e5e5e5e5-0000-4000-8000-000000000005")!
        r.store.seed(unreadable, Data("not a request".utf8))
        r.store.seed(CompanionSyncKeys.receipt, Data("x".utf8))
        r.coordinator.start()
        await drain(r)
        #expect(r.store.removedKeys == [old])
        #expect(r.store.data(forKey: recent) != nil && r.store.data(forKey: unreadable) != nil)
        #expect(r.host.refreshes == 0)
    }

    // MARK: Publisher (KTD14.5)

    /// The forced publish skips the spacing, writes the manifest with the stamped answers and
    /// returns its generation; a newer capture already pending supersedes it.
    @Test func forcedPublishSkipsSpacingAndReturnsTheGenerationToAssemble() async throws {
        let store = RecordingKeyValueStore()
        let clock = ManualClock(t0)
        let publisher = CompanionPublisher(
            store: store,
            configuration: .init(sourceID: F.macA, flushSpacing: 60, now: { clock.now }, autoSchedule: false))
        func capture(_ generation: Int64) -> CompanionPublishCapture {
            var capture = CompanionPublisherTests.capture()
            capture.generation = generation
            return capture
        }
        await publisher.receive(capture(1))
        clock.advance(5)
        var forced = capture(2)
        forced.answeredRequests = [try CompanionAnsweredRequest(requestID: requestID(1), outcome: .finished, finishedGeneration: 2)]
        #expect(await publisher.publishForced(forced) == 2)
        guard case .value(.active(let manifest)) = CompanionSyncCodec.decodeManifest(store.data(forKey: CompanionSyncKeys.manifest)) else {
            Issue.record("no manifest"); return
        }
        #expect(manifest.generation == 2 && manifest.answeredRequests.map(\.requestID) == [requestID(1)])
        // Already superseded by a later publish: that generation carries the answers.
        await publisher.receive(capture(4), forced: true)
        #expect(await publisher.publishForced(capture(3)) == 4)
    }
}
