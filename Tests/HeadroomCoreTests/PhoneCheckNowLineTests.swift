import Foundation
import Testing

@testable import HeadroomCore

/// U9 and review #10: what the slot under the phone's title shows while a check-now request
/// runs and when it hands back to the stamp, driven by the bundled demo replay through the
/// real machine; and the rule that only the latest-started snapshot load may publish.
@Suite
struct PhoneCheckNowLineTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    // MARK: CA-I2: the dimmed header stamp

    @Test func theDimmedHeaderStampUsesTheWidgetsWords() {
        #expect(CheckNowLinePolicy.dimmedStamp(since: "1:25 AM") == "Last update 1:25 AM")
        // The widgets' small rung says the same thing (CA-W4).
        let treatment = WidgetFreshnessTreatment(
            now: now, dimmedSince: now.addingTimeInterval(-7_200), host: .phone,
            timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US_POSIX"))
        let time = WidgetClockText.text(
            for: now.addingTimeInterval(-7_200), now: now,
            timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US_POSIX"))
        #expect(treatment.dimmedCaptions.contains(CheckNowLinePolicy.dimmedStamp(since: time)))
    }

    // MARK: CA-M5: one launch entrance

    /// 20 accounts across six cards (five providers and spend): the last card starts within
    /// 0.22 s whatever the account split, and settles within half a second.
    @Test func theWorstCaseEntranceDelayIsCappedAtTheFourthCard() {
        let delays = PhoneCardEntranceSchedule.delays(accountCounts: [8, 5, 4, 2, 1], hasSpendCard: true)
        #expect(delays.count == 6)
        let last = try? #require(delays.last)
        #expect((last ?? 1) <= 0.22 + 1e-9)
        #expect(delays == PhoneCardEntranceSchedule.delays(accountCounts: [1, 1, 1, 1, 16], hasSpendCard: true),
                "account counts never add delay")
        #expect(delays.max()! + PhoneCardEntranceSchedule.duration <= 0.5 + 1e-9)
        #expect(delays == delays.sorted(), "cards enter top to bottom")
        #expect(delays.first == 0)
    }

    @Test func reduceMotionFadesWithNoRiseAndMetersNeverDrawIn() {
        #expect(PhoneCardEntranceSchedule.rise(reduceMotion: true) == 0)
        #expect(PhoneCardEntranceSchedule.rise(reduceMotion: false) == 10)
        #expect(!PhoneCardEntranceSchedule.metersDrawIn)
    }

    // MARK: U9: the check-now slot

    private func demoStatus(steps: Int?, at clock: Date) async throws -> CheckNowStatus {
        let (state, latest) = try await demoState(steps: steps, at: clock)
        return CheckNowStatus.make(state: state, snapshot: latest, now: clock)
    }

    /// The demo's request state after `steps` replay steps, and the snapshot it last adopted.
    private func demoState(steps: Int?, at clock: Date) async throws -> (CheckNowRequestState, CompanionResolvedSnapshot) {
        let demo = CompanionDemoModeStore(defaults: nil, now: { clock }, sleep: { _ in })
        let snapshot = demo.snapshot(.multiAccount)
        guard case .requested(var state, _) = CheckNowMachine.begin(
            snapshot: snapshot, current: nil, requestID: CompanionDemoData.requestID, now: clock)
        else { throw CheckNowTestError.notRequested }
        let recorder = DemoStepRecorder()
        _ = await demo.replayCheckNow(.multiAccount) { await recorder.record($0) }
        var latest = snapshot
        for step in await recorder.steps.prefix(steps ?? .max) {
            state = CheckNowMachine.receive(step.receipt, into: state, now: clock)
            if let adopted = step.snapshot {
                latest = adopted
                state = CheckNowMachine.receive(adopted, into: state, now: clock)
            }
        }
        return (state, latest)
    }

    private enum CheckNowTestError: Error { case notRequested }

    @Test func theSlotShowsTheReceiptWhileInFlightThenJustNowThenTheStamp() async throws {
        let asking = try await demoStatus(steps: 0, at: now)
        #expect(CheckNowLinePolicy.slot(status: asking, completedAt: nil, now: now)
            == .checkNow(.message("Asking your Mac…"), isInFlight: true))

        let landed = try await demoStatus(steps: 3, at: now)
        guard case .checkNow(.receipt(let line), true) = CheckNowLinePolicy.slot(status: landed, completedAt: nil, now: now)
        else { Issue.record("a running receipt shows its landed account"); return }
        #expect(line.count == "2 of 5")
        #expect(line.checked)

        let finished = try await demoStatus(steps: nil, at: now)
        #expect(finished.phase == .finished(notUpdated: 0))
        #expect(CheckNowLinePolicy.slot(status: finished, completedAt: now, now: now.addingTimeInterval(2.9))
            == .checkNow(.message("Just now"), isInFlight: false))
        #expect(CheckNowLinePolicy.revertsAt(status: finished, completedAt: now) == now.addingTimeInterval(3))
        #expect(CheckNowLinePolicy.slot(status: finished, completedAt: now, now: now.addingTimeInterval(3)) == .freshness)
        #expect(!CheckNowLinePolicy.resumesAtLaunch(finished), "yesterday's Just now never greets a launch")
        #expect(CheckNowLinePolicy.resumesAtLaunch(asking))
        #expect(finished.askedAt == now)
    }

    @Test func timeoutLinesStayUntilSomethingChangesThem() async throws {
        let asked = try await demoStatus(steps: 0, at: now)
        // The machine re-evaluated past its acknowledgement timeout.
        let demo = CompanionDemoModeStore(defaults: nil, now: { self.now }, sleep: { _ in })
        guard case .requested(let state, _) = CheckNowMachine.begin(
            snapshot: demo.snapshot(.multiAccount), current: nil, requestID: asked.requestID, now: now)
        else { Issue.record("demo supports check now"); return }
        let late = now.addingTimeInterval(CheckNowTiming.acknowledgementTimeout)
        let noAnswer = CheckNowStatus.make(state: state, snapshot: nil, now: late)
        #expect(noAnswer.phase == .noAnswer)
        #expect(CheckNowLinePolicy.slot(status: noAnswer, completedAt: nil, now: late.addingTimeInterval(300))
            == .checkNow(.message(CheckNowCopy.noAnswer), isInFlight: false))
        #expect(CheckNowLinePolicy.revertsAt(status: noAnswer, completedAt: nil) == nil)
        #expect(CheckNowLinePolicy.resumesAtLaunch(noAnswer), "still answerable inside the age limit")
        let expired = CheckNowStatus.make(
            state: state, snapshot: nil, now: now.addingTimeInterval(CheckNowTiming.requestAgeLimit))
        #expect(!CheckNowLinePolicy.resumesAtLaunch(expired))
        #expect(CheckNowLinePolicy.slot(status: nil, completedAt: nil, now: now) == .freshness)
    }

    // MARK: Review 2 #1: the wake never re-arms at a past date

    /// Explore Demo re-makes its status from the replay's state at every wake
    /// (`PhoneCheckNow.deadlinePassed`'s demo branch). A finished check wakes once, at the end
    /// of the three-second hold, and then nothing future remains.
    @Test func aFinishedDemoCheckWakesOnceAtTheHoldsEndThenStops() async throws {
        let (state, latest) = try await demoState(steps: nil, at: now)
        var host = CheckNowWakeHost()
        host.apply(CheckNowStatus.make(state: state, snapshot: latest, now: now), at: now)
        let wakes = host.run(from: now) { CheckNowStatus.make(state: state, snapshot: latest, now: $0) }
        #expect(wakes == [now.addingTimeInterval(CheckNowLinePolicy.completionHold)])
        #expect(CheckNowLinePolicy.slot(status: host.status, completedAt: host.completedAt, now: wakes[0]) == .freshness)
        #expect(CheckNowLinePolicy.nextWake(status: host.status, completedAt: host.completedAt, now: wakes[0]) == nil)
    }

    /// A demo request that is never answered wakes at the acknowledgement timeout ("Your Mac
    /// hasn’t answered"), again at the age limit, and then stops.
    @Test func anUnansweredDemoRequestWakesAtEachTimeoutThenStops() async throws {
        let (state, latest) = try await demoState(steps: 0, at: now)
        var host = CheckNowWakeHost()
        host.apply(CheckNowStatus.make(state: state, snapshot: latest, now: now), at: now)
        let wakes = host.run(from: now) { CheckNowStatus.make(state: state, snapshot: latest, now: $0) }
        #expect(wakes == [
            now.addingTimeInterval(CheckNowTiming.acknowledgementTimeout),
            now.addingTimeInterval(CheckNowTiming.requestAgeLimit),
        ])
    }

    /// The decision itself: only dates after `now` are wakes, so a hold that has already
    /// ended (or a deadline the status was made before) schedules nothing.
    @Test func nextWakeOnlyReturnsFutureDates() async throws {
        let finished = try await demoStatus(steps: nil, at: now)
        let hold = now.addingTimeInterval(CheckNowLinePolicy.completionHold)
        #expect(CheckNowLinePolicy.nextWake(status: finished, completedAt: now, now: now) == hold)
        #expect(CheckNowLinePolicy.nextWake(status: finished, completedAt: now, now: hold) == nil)
        #expect(CheckNowLinePolicy.nextWake(status: finished, completedAt: now, now: hold.addingTimeInterval(60)) == nil)
        let asking = try await demoStatus(steps: 0, at: now)
        let timeout = now.addingTimeInterval(CheckNowTiming.acknowledgementTimeout)
        #expect(CheckNowLinePolicy.nextWake(status: asking, completedAt: nil, now: now) == timeout)
        #expect(CheckNowLinePolicy.nextWake(status: asking, completedAt: nil, now: timeout) == nil,
                "a status made before its deadline never asks for a wake at or after it")
        #expect(CheckNowLinePolicy.nextWake(status: nil, completedAt: nil, now: now) == nil)
    }

    /// AE1 / KTD14.1: an older Mac's content never starts a request, so the phone re-reads
    /// with no "Asking your Mac" state.
    @Test func anOlderMacsPullIsReReadOnly() {
        let demo = CompanionDemoModeStore(defaults: nil, now: { self.now }, sleep: { _ in })
        #expect(CheckNowMachine.begin(
            snapshot: demo.snapshot(.oldMac), current: nil, requestID: CompanionDemoData.requestID, now: now)
            == .rereadOnly)
    }

    // MARK: Review #10: the latest-started load wins

    @MainActor
    @Test func anOlderLoadThatFinishesLastNeverPublishes() async {
        let loads = CompanionLatestLoad<String>()
        let gate = LoadGate()
        let older = Task { @MainActor in await loads.run { await gate.wait("older") } }
        await gate.waitUntilWaiting("older")
        let newer = Task { @MainActor in await loads.run { await gate.wait("newer") } }
        await gate.waitUntilWaiting("newer")
        await gate.release("newer")
        #expect(await newer.value == "newer")
        await gate.release("older")
        #expect(await older.value == nil, "the stale read is dropped")
    }

    @MainActor
    @Test func anAdoptionSupersedesLoadsInFlight() async {
        let loads = CompanionLatestLoad<String>()
        let gate = LoadGate()
        let inFlight = Task { @MainActor in await loads.run { await gate.wait("load") } }
        await gate.waitUntilWaiting("load")
        loads.supersede()
        await gate.release("load")
        #expect(await inFlight.value == nil)
        #expect(await loads.run { "next" } == "next")
    }
}

/// Holds named loads open until the test releases them, so completion order is the test's.
private actor LoadGate {
    private var waiting: [String: CheckedContinuation<String, Never>] = [:]
    private var watchers: [String: [CheckedContinuation<Void, Never>]] = [:]

    func wait(_ name: String) async -> String {
        await withCheckedContinuation { continuation in
            waiting[name] = continuation
            watchers.removeValue(forKey: name)?.forEach { $0.resume() }
        }
    }

    func waitUntilWaiting(_ name: String) async {
        guard waiting[name] == nil else { return }
        await withCheckedContinuation { watchers[name, default: []].append($0) }
    }

    func release(_ name: String) {
        waiting.removeValue(forKey: name)?.resume(returning: name)
    }
}
