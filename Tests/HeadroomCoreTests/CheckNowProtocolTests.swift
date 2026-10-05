import Foundation
import Testing

@testable import HeadroomCore

/// U6 (KTD14, R18, R19, contract Decision 2): the phone's check-now state machine and
/// client. Pure inputs — resolved snapshots from the real resolver, receipts through the real
/// codec, an injected phone clock — and an in-memory KVS double.
@Suite
struct CheckNowProtocolTests {
    private typealias F = CompanionFixtures
    private let device = "d0d0d0d0-0000-4000-8000-000000000001"
    private let otherPhone = "99999999-0000-4000-8000-000000000099"
    /// Phone clock origin: deliberately unrelated to the Mac's fixture clock.
    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    // MARK: Fixtures

    private func accounts(stale: Bool = false) -> (CompanionAccountSummary, [CompanionAccountSummary]) {
        let work = stale
            ? try! CompanionAccountSummary(
                id: "work", title: "Work", freshness: .stale, capturedAt: F.date(), attention: .signInAgain,
                needsAttention: true, windows: [F.window()])
            : F.account("work", title: "Work")
        return (F.account(), [work])
    }

    /// A resolved v4 snapshot of Mac A at `generation`. `lagging` publishes the Claude key one
    /// generation behind its manifest entry; `staleWork` makes the Work account stale.
    private func v4(
        generation: Int64, answered: [CompanionAnsweredRequest] = [], lagging: Bool = false,
        staleWork: Bool = false, source: String = CompanionFixtures.macA, now: Date? = nil
    ) -> CompanionResolvedSnapshot {
        let (main, extras) = accounts(stale: staleWork)
        let payload = F.payload(source: source, generation: lagging ? generation - 1 : generation, main: main, extras: extras)
        let bytes = F.bytes(payload)
        let manifest = F.manifest(
            source: source, generation: generation, generatedAt: generation,
            entries: ["claude": lagging ? F.entry(F.bytes(F.payload(source: source, generation: generation)), generation: generation) : F.entry(bytes, generation: generation)],
            answered: answered)
        return CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: F.bytes(manifest), providerKeys: ["claude": bytes], v3: nil, now: now ?? t0)
        ).snapshot
    }

    private func v3Only(lineage: (String, Int64)? = nil, manifestGeneration: Int64? = nil) -> CompanionResolvedSnapshot {
        let manifest = manifestGeneration.map { generation -> Data in
            let bytes = F.bytes(F.payload(generation: generation))
            return F.bytes(F.manifest(generation: generation, generatedAt: 0, entries: ["claude": F.entry(bytes, generation: generation)]))
        }
        return CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: manifest, providerKeys: [:],
                v3: F.v3Bytes(F.v3(generatedAt: 600, lineage: lineage)), now: t0)
        ).snapshot
    }

    private func receipt(
        _ state: CompanionReceiptState, ids: [String], answered: [CompanionAnsweredRequest] = [],
        total: Int? = nil, completed: Int? = nil, landed: CompanionLastLanded? = nil,
        finishedGeneration: Int64? = nil, source: String = CompanionFixtures.macA
    ) -> CompanionReceipt {
        let built = try! CompanionReceipt(
            sourceID: source, state: state, requestIDs: ids, answeredRequests: answered,
            startedAt: F.date(), finishedAt: state == .finished ? F.date(60) : nil,
            checkedAt: state == .cooldown ? F.date(30) : nil, total: total, completed: completed,
            lastLanded: landed, finishedGeneration: finishedGeneration)
        // Every receipt the phone sees has crossed the real codec.
        guard case .value(let decoded) = CompanionSyncCodec.decodeReceipt(try! CompanionSyncCodec.encode(built)) else {
            fatalError("receipt fixture failed the codec")
        }
        return decoded
    }

    private func answered(_ id: String, _ outcome: CompanionAnsweredOutcome = .finished, generation: Int64? = 8) -> CompanionAnsweredRequest {
        try! CompanionAnsweredRequest(requestID: id, outcome: outcome, finishedGeneration: generation)
    }

    private func landed(_ account: String = "work", live: Bool = true) -> CompanionLastLanded {
        try! CompanionLastLanded(providerID: "claude", accountID: account, live: live)
    }

    private func started(_ snapshot: CompanionResolvedSnapshot? = nil, id: String = "11111111-0000-4000-8000-000000000001") throws -> (CheckNowRequestState, CompanionRequest) {
        guard case .requested(let state, let request) = CheckNowMachine.begin(
            snapshot: snapshot ?? v4(generation: 7), current: nil, requestID: id, now: t0)
        else { throw CheckNowTestError.notRequested }
        return (state, request)
    }

    private enum CheckNowTestError: Error { case notRequested }

    private func client(_ store: CheckNowKeyValueStore, state: MemoryCheckNowStateStore = MemoryCheckNowStateStore(),
                        clock: ManualClock, ids: RequestIDSequence = RequestIDSequence()) -> CheckNowClient {
        CheckNowClient(store: store, stateStore: state, deviceUUID: device, now: { clock.now }, makeRequestID: ids.make)
    }

    // MARK: Requests (KTD14.1)

    @Test func aV4WinnerWritesOneRequestUnderThisInstallsKeyThenSynchronizes() throws {
        let store = CheckNowKeyValueStore()
        let clock = ManualClock(t0)
        let result = client(store, clock: clock).pull(snapshot: v4(generation: 7))
        guard case .requested(let status) = result else { Issue.record("expected a request"); return }
        #expect(status.phase == .asking && status.line == .message(CheckNowCopy.asking) && status.isInFlight)
        let key = try #require(CompanionSyncKeys.request(deviceUUID: device))
        #expect(key.utf8.count <= CompanionSyncKeys.maximumKeyBytes)
        #expect(store.setKeys == [key] && store.synchronizeCount == 1)
        guard case .value(let request) = CompanionSyncCodec.decodeRequest(store.data(forKey: key)) else {
            Issue.record("request did not decode"); return
        }
        #expect(request.sourceID == F.macA && request.requestID == status.requestID)
        #expect(request.requestedAt == CompanionWireDate(date: t0))
    }

    /// AE1 / V-old-Mac: no manifest, a lineage-less v3 that beats a stale manifest
    /// (downgraded Mac), a paused Mac and nothing readable all re-read only.
    @Test func anOldDowngradedPausedOrMissingMacNeverReceivesARequest() throws {
        let paused = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: F.bytes(try CompanionManifest.disabledTombstone(sourceID: F.macA)), v3: nil, now: t0)
        ).snapshot
        let downgraded = v3Only(manifestGeneration: 3)
        #expect(downgraded.content?.origin == .v3 && downgraded.content?.notice == .updateMac)
        for snapshot in [v3Only(), downgraded, paused, CompanionResolvedSnapshot(state: .waiting(nil))] {
            let store = CheckNowKeyValueStore()
            #expect(client(store, clock: ManualClock(t0)).pull(snapshot: snapshot) == .rereadOnly)
            #expect(store.setKeys.isEmpty && store.synchronizeCount == 0)
        }
    }

    /// AE3, phone half: five pulls in ten seconds coalesce onto one request ID and one write.
    @Test func fivePullsInTenSecondsWriteOneRequest() {
        let store = CheckNowKeyValueStore()
        let clock = ManualClock(t0)
        let phone = client(store, clock: clock)
        var ids: Set<String> = []
        for _ in 0..<5 {
            switch phone.pull(snapshot: v4(generation: 7)) {
            case .requested(let status), .pending(let status): ids.insert(status.requestID)
            case .rereadOnly: Issue.record("unexpected re-read")
            }
            clock.advance(2)
        }
        #expect(ids.count == 1 && store.setKeys.count == 1)
    }

    @Test func deviceUUIDIsCreatedOnceAndIsNeverADeviceName() throws {
        let suite = "headroom.checknow.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CheckNowDeviceIdentity.deviceUUID(in: defaults)
        #expect(UUID(uuidString: first) != nil && first == first.lowercased())
        #expect(CheckNowDeviceIdentity.deviceUUID(in: defaults) == first)
        #expect(CompanionSyncKeys.request(deviceUUID: first)?.utf8.count == 61)
    }

    // MARK: Acknowledgement (KTD14.7, AE2, V22)

    @Test func noAcknowledgementInSixtySecondsReadsHasNotAnswered() throws {
        let (state, _) = try started()
        #expect(CheckNowMachine.phase(of: state, now: t0.addingTimeInterval(59)) == .asking)
        #expect(CheckNowMachine.nextDeadline(of: state, now: t0) == t0.addingTimeInterval(60))
        let status = CheckNowStatus.make(state: state, snapshot: nil, now: t0.addingTimeInterval(60))
        #expect(status.phase == .noAnswer && !status.isInFlight)
        #expect(status.line == .message("Your Mac hasn’t answered. It may be asleep, or Headroom isn’t open."))
    }

    /// AE2: the Mac wakes inside 10 minutes; its acknowledgement resumes the request and the
    /// check finishes. After the age limit an acknowledgement no longer revives it.
    @Test func aLaterAcknowledgementInsideTheAgeLimitResumesAndAfterItDoesNot() throws {
        let (state, request) = try started()
        let late = t0.addingTimeInterval(9 * 60)
        let resumed = CheckNowMachine.receive(receipt(.accepted, ids: [request.requestID]), into: state, now: late)
        #expect(CheckNowMachine.phase(of: resumed, now: late) == .checking(total: nil, completed: 0, lastLanded: nil))

        let tooLate = t0.addingTimeInterval(10 * 60)
        let expired = CheckNowMachine.receive(receipt(.accepted, ids: [request.requestID]), into: state, now: tooLate)
        #expect(CheckNowMachine.phase(of: expired, now: tooLate) == .noAnswer)
        #expect(CheckNowMachine.isSettled(expired, now: tooLate))
        #expect(!CheckNowMachine.isSettled(state, now: late))
    }

    /// KTD14.7: finish deadline = ack + max(3 minutes, largest lane × per-probe estimate).
    @Test func finishTimeoutFollowsTheFormula() throws {
        let (state, request) = try started()
        #expect(state.largestLaneAccountCount == 2)
        let acked = CheckNowMachine.receive(receipt(.running, ids: [request.requestID], total: 2, completed: 0), into: state, now: t0.addingTimeInterval(5))
        let deadline = t0.addingTimeInterval(5 + 180)
        #expect(CheckNowMachine.nextDeadline(of: acked, now: t0.addingTimeInterval(6)) == deadline)
        #expect(CheckNowMachine.phase(of: acked, now: deadline.addingTimeInterval(-1)) == .checking(total: 2, completed: 0, lastLanded: nil))
        let status = CheckNowStatus.make(state: acked, snapshot: nil, now: deadline)
        #expect(status.phase == .notFinished)
        #expect(status.line == .message("Your Mac started checking but hasn’t finished. Pull again later."))

        let big = CheckNowRequestState(requestID: request.requestID, sourceID: F.macA, askedAt: t0, largestLaneAccountCount: 20)
        let bigAcked = CheckNowMachine.receive(receipt(.accepted, ids: [request.requestID]), into: big, now: t0)
        #expect(CheckNowTiming.finishWindow(largestLaneAccountCount: 20) == 20 * CheckNowTiming.provisionalPerProbeSeconds)
        #expect(CheckNowMachine.nextDeadline(of: bigAcked, now: t0) == t0.addingTimeInterval(600))
    }

    @Test func progressOnlyMovesForwardAndALowerCompletedCountIsIgnored() throws {
        let (state, request) = try started()
        let id = request.requestID
        var next = CheckNowMachine.receive(receipt(.running, ids: [id], total: 3, completed: 2, landed: landed("work")), into: state, now: t0)
        next = CheckNowMachine.receive(receipt(.running, ids: [id], total: 3, completed: 1, landed: landed("primary")), into: next, now: t0)
        #expect(CheckNowMachine.phase(of: next, now: t0) == .checking(total: 3, completed: 2, lastLanded: landed("work")))
    }

    // MARK: Completion (KTD14.5–7)

    @Test func finishedReceiptShowsJustNowOnlyAfterAssemblingItsGeneration() throws {
        let (state, request) = try started()
        let id = request.requestID
        let finished = CheckNowMachine.receive(
            receipt(.finished, ids: [id], answered: [answered(id)], total: 2, completed: 2, landed: landed(), finishedGeneration: 8),
            into: state, now: t0.addingTimeInterval(30))
        // Generation 7 assembled; 8 not yet: still the receipt line, never "Just now".
        #expect(CheckNowMachine.phase(of: finished, now: t0.addingTimeInterval(31)) == .checking(total: 2, completed: 2, lastLanded: landed()))
        // A lagging provider key at 8 is not assembly.
        let lagging = CheckNowMachine.receive(v4(generation: 8, lagging: true), into: finished, now: t0.addingTimeInterval(32))
        #expect(lagging.assembledGeneration == 7)
        let done = CheckNowMachine.receive(v4(generation: 8), into: lagging, now: t0.addingTimeInterval(33))
        let status = CheckNowStatus.make(state: done, snapshot: v4(generation: 8), now: t0.addingTimeInterval(33))
        #expect(status.phase == .finished(notUpdated: 0) && status.line == .message("Just now") && !status.isInFlight)
    }

    /// V22: the manifest at `finishedGeneration` naming this request arrives before the
    /// receipt, and completes it on its own.
    @Test func theFinishedSnapshotArrivingFirstSkipsToJustNow() throws {
        let (state, request) = try started()
        let first = CheckNowMachine.receive(v4(generation: 8, answered: [answered(request.requestID)]), into: state, now: t0.addingTimeInterval(20))
        #expect(CheckNowMachine.phase(of: first, now: t0.addingTimeInterval(20)) == .finished(notUpdated: 0))
    }

    /// Decision 2: a newer heartbeat without this request's answer completes nothing.
    @Test func anUnrelatedLaterHeartbeatDoesNotComplete() throws {
        let (state, request) = try started()
        let acked = CheckNowMachine.receive(receipt(.accepted, ids: [request.requestID]), into: state, now: t0)
        let heartbeat = CheckNowMachine.receive(v4(generation: 12, answered: [answered(otherPhone, generation: 11)]), into: acked, now: t0.addingTimeInterval(5))
        #expect(CheckNowMachine.phase(of: heartbeat, now: t0.addingTimeInterval(5)) == .checking(total: nil, completed: 0, lastLanded: nil))
    }

    @Test func aFinishedCheckWithNonLiveAccountsSaysHowManyDidNotUpdate() throws {
        let (state, request) = try started()
        let done = CheckNowMachine.receive(
            v4(generation: 8, answered: [answered(request.requestID)], staleWork: true), into: state, now: t0)
        #expect(CheckNowStatus.make(state: done, snapshot: nil, now: t0).line == .message("Checked · 1 account didn’t update"))
        #expect(CheckNowCopy.notUpdated(2) == "Checked · 2 accounts didn’t update")
    }

    /// Cooldown answers complete the same way, on the generation the Mac flushed.
    @Test func aCooldownAnswerReadsCheckedAMomentAgoOnceItsGenerationIsAssembled() throws {
        let (state, request) = try started()
        let id = request.requestID
        let answer = answered(id, .cooldown, generation: 9)
        let cooling = CheckNowMachine.receive(
            receipt(.cooldown, ids: [id], answered: [answer], finishedGeneration: 9), into: state, now: t0)
        #expect(CheckNowMachine.phase(of: cooling, now: t0) != .cooldown)
        let done = CheckNowMachine.receive(v4(generation: 9, answered: [answer]), into: cooling, now: t0)
        #expect(CheckNowStatus.make(state: done, snapshot: nil, now: t0).line == .message("Checked a moment ago"))
    }

    @Test func aFailedAnswerEndsTheRequestWithTheNotFinishedLine() throws {
        let (state, request) = try started()
        let failed = CheckNowMachine.receive(
            receipt(.running, ids: [request.requestID], answered: [answered(request.requestID, .failed, generation: nil)], total: 2, completed: 2),
            into: state, now: t0)
        #expect(CheckNowMachine.phase(of: failed, now: t0) == .notFinished)
    }

    // MARK: Matching by ID (Decision 2, V19)

    @Test func anotherPhonesRunAndAForeignMacChangeNothing() throws {
        let (state, request) = try started()
        let other = CheckNowMachine.receive(receipt(.running, ids: [otherPhone], total: 2, completed: 1), into: state, now: t0)
        #expect(other == state)
        let foreign = CheckNowMachine.receive(
            receipt(.finished, ids: [request.requestID], answered: [answered(request.requestID)], total: 2, completed: 2,
                    finishedGeneration: 8, source: F.macB),
            into: state, now: t0)
        #expect(foreign == state)
        let foreignSnapshot = CheckNowMachine.receive(v4(generation: 8, answered: [answered(request.requestID)], source: F.macB), into: state, now: t0)
        #expect(foreignSnapshot == state)
    }

    /// V19: an iPad run that starts after the iPhone's finish replaces the receipt's active
    /// list; the iPhone still finds its own answer in the recent-answers list.
    @Test func theIPhoneFindsItsAnswerAfterAnIPadRunStarts() throws {
        let (state, request) = try started()
        let iPadRun = receipt(.running, ids: [otherPhone], answered: [answered(request.requestID)], total: 2, completed: 0)
        let found = CheckNowMachine.receive(iPadRun, into: state, now: t0.addingTimeInterval(40))
        let done = CheckNowMachine.receive(v4(generation: 8), into: found, now: t0.addingTimeInterval(41))
        #expect(CheckNowMachine.phase(of: done, now: t0.addingTimeInterval(41)) == .finished(notUpdated: 0))
    }

    /// The phone matches IDs, never clocks: the same receipts complete the same way whether
    /// the phone's clock runs five minutes ahead of or behind the Mac's.
    @Test func phoneClockFiveMinutesAheadOrBehindChangesNothing() throws {
        for skew in [-300.0, 0, 300] {
            let start = t0.addingTimeInterval(skew)
            guard case .requested(let state, let request) = CheckNowMachine.begin(
                snapshot: v4(generation: 7, now: start), current: nil, requestID: "11111111-0000-4000-8000-000000000002", now: start)
            else { Issue.record("expected a request"); return }
            var next = CheckNowMachine.receive(receipt(.running, ids: [request.requestID], total: 2, completed: 1, landed: landed()), into: state, now: start.addingTimeInterval(3))
            #expect(CheckNowMachine.phase(of: next, now: start.addingTimeInterval(3)) == .checking(total: 2, completed: 1, lastLanded: landed()))
            next = CheckNowMachine.receive(receipt(.finished, ids: [request.requestID], answered: [answered(request.requestID)], total: 2, completed: 2, finishedGeneration: 8), into: next, now: start.addingTimeInterval(9))
            next = CheckNowMachine.receive(v4(generation: 8, now: start), into: next, now: start.addingTimeInterval(10))
            #expect(CheckNowMachine.phase(of: next, now: start.addingTimeInterval(10)) == .finished(notUpdated: 0))
        }
    }

    // MARK: Client (App Group state, KVS reads)

    @Test func clientFoldsTheReceiptKeyAndSnapshotIntoTheSharedState() throws {
        let store = CheckNowKeyValueStore()
        let state = MemoryCheckNowStateStore()
        let clock = ManualClock(t0)
        let phone = client(store, state: state, clock: clock)
        guard case .requested(let asked) = phone.pull(snapshot: v4(generation: 7)) else { Issue.record("no request"); return }
        let id = asked.requestID

        store.seed(CompanionSyncKeys.receipt, F.bytes(receipt(.running, ids: [id], total: 2, completed: 1, landed: landed())))
        clock.advance(4)
        let running = try #require(phone.update(snapshot: v4(generation: 7)))
        #expect(running.line == .receipt(.init(checked: true, text: "Claude Work", count: "1 of 2")))

        // A second process (the widget's control) sees the same outstanding request.
        let widget = CheckNowClient(store: store, stateStore: state, deviceUUID: device, now: { clock.now }, makeRequestID: { "22222222-0000-4000-8000-000000000002" })
        guard case .pending(let shared) = widget.pull(snapshot: v4(generation: 7)) else { Issue.record("expected coalescing"); return }
        #expect(shared.requestID == id)

        store.seed(CompanionSyncKeys.receipt, F.bytes(receipt(.finished, ids: [id], answered: [answered(id)], total: 2, completed: 2, finishedGeneration: 8)))
        clock.advance(4)
        #expect(phone.update(snapshot: v4(generation: 8))?.line == .message("Just now"))

        // Settled: the next pull is a new request.
        guard case .requested(let again) = phone.pull(snapshot: v4(generation: 8)) else { Issue.record("expected a new request"); return }
        #expect(again.requestID != id)
    }

    @Test func checkingLineCountsAccountsAndOmitsAnUnknownLandedAccount() throws {
        let (state, request) = try started()
        let accepted = CheckNowMachine.receive(receipt(.accepted, ids: [request.requestID]), into: state, now: t0)
        #expect(CheckNowStatus.make(state: accepted, snapshot: v4(generation: 7), now: t0).line == .receipt(.init(checked: false, text: "Checking 2 accounts…", count: nil)))
        let unknown = CheckNowMachine.receive(receipt(.running, ids: [request.requestID], total: 2, completed: 1, landed: landed("gone")), into: state, now: t0)
        #expect(CheckNowStatus.make(state: unknown, snapshot: v4(generation: 7), now: t0).line == .receipt(.init(checked: false, text: "Checking 2 accounts…", count: nil)))
    }

    /// AE8: Explore Demo drives the same machine from the bundled replay and writes nothing.
    @Test func theDemoReplayReachesJustNowThroughTheMachineWithoutWriting() async throws {
        let clock = DemoReplayClock(t0)
        let demo = CompanionDemoModeStore(defaults: nil, now: { clock.now }, sleep: { clock.sleep($0) })
        guard case .requested(var state, _) = CheckNowMachine.begin(
            snapshot: demo.snapshot(.multiAccount), current: nil, requestID: CompanionDemoData.requestID, now: clock.now)
        else { Issue.record("demo variant should support check now"); return }
        let recorder = DemoStepRecorder()
        #expect(await demo.replayCheckNow(.multiAccount) { await recorder.record($0) })
        for step in await recorder.steps {
            state = CheckNowMachine.receive(step.receipt, into: state, now: clock.now)
            if let snapshot = step.snapshot { state = CheckNowMachine.receive(snapshot, into: state, now: clock.now) }
        }
        #expect(CheckNowMachine.phase(of: state, now: clock.now) == .finished(notUpdated: 0))
    }

    // MARK: Copy (R2C6)

    @Test func everyLinePassesTheR2C6CopyRules() {
        let lines = [CheckNowCopy.asking, CheckNowCopy.noAnswer, CheckNowCopy.notFinished, CheckNowCopy.justNow,
                     CheckNowCopy.checkedMomentAgo, CheckNowCopy.notUpdated(1), CheckNowCopy.notUpdated(3),
                     RefreshReceiptPresentation.checking(3).text]
        for line in lines {
            #expect(!line.localizedCaseInsensitiveContains("connect"))
            #expect(!line.contains("'"))
            if line.contains("—") { #expect(line.contains("\u{00A0}—\u{00A0}")) }
        }
        #expect(CheckNowCopy.noAnswer == "Your Mac hasn’t answered. It may be asleep, or Headroom isn’t open.")
        #expect(CheckNowCopy.notFinished == "Your Mac started checking but hasn’t finished. Pull again later.")
        #expect(CheckNowCopy.notUpdated(1) == "Checked · 1 account didn’t update")
    }
}
