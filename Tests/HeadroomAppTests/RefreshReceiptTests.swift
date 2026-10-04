import Foundation
import HeadroomCore
import Testing
@testable import Headroom

@Suite struct RefreshReceiptTests {
    private let claude = AccountKey(providerID: .claude, accountID: .primary)
    private let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
    private let now = Date(timeIntervalSince1970: 100)

    private func line(_ run: UserRefreshRun?, phase: ReprintRecipe.Phase = .spinner, date: Date? = nil) -> RefreshReceipt.Line? {
        RefreshReceipt.line(run: run, phase: phase, now: date ?? now,
                            title: { $0 == self.work ? "Claude Work" : "Claude" })
    }
    @Test func setupOnlyAndRestLeaveTheSlotToTheStamp() {
        #expect(line(nil) == nil)
        let run = UserRefreshRun(startedAt: now, entries: [claude: .init(origin: .setupCheck, requestedAt: now)])
        #expect(line(run) == nil)
        #expect(line(run, phase: .rest) == nil)
    }
    @Test func beforeAnythingLandsItCountsOnlyUserRequests() {
        let run = UserRefreshRun(startedAt: now, entries: [claude: .init(origin: .accountAction, requestedAt: now),
            work: .init(origin: .setupCheck, requestedAt: now)])
        #expect(line(run) == .init(checked: false, text: "Checking 1 account…", count: nil))
    }
    @Test func retainedLandingSurvivesSpendAndHoldUntilTheButtonReturns() {
        let run = UserRefreshRun(startedAt: now, entries: [claude: .init(origin: .fullRefresh, requestedAt: now,
            outcome: .stale, landedAt: now), work: .init(origin: .fullRefresh, requestedAt: now,
            outcome: .live, landedAt: now.addingTimeInterval(1))])
        let expected = RefreshReceipt.Line(checked: true, text: "Claude Work", count: "2 of 2")
        #expect(line(run, phase: .spendTail, date: now.addingTimeInterval(4)) == expected)
        #expect(line(run, phase: .hold, date: now.addingTimeInterval(4.4)) == expected)
        #expect(line(run, phase: .rest, date: now.addingTimeInterval(4.5)) == nil)
    }
    @Test func outcomeIsHistoricalAndTiesAreDeterministic() {
        let run = UserRefreshRun(startedAt: now, entries: [claude: .init(origin: .accountAction, requestedAt: now,
            outcome: .live, landedAt: now), work: .init(origin: .accountAction, requestedAt: now,
            outcome: .stale, landedAt: now)])
        #expect(line(run) == .init(checked: false, text: "Claude Work", count: "2 of 2"))
    }
    @Test func newRunDuringHoldKeepsReceiptVisible() {
        let run = UserRefreshRun(startedAt: now, entries: [claude: .init(origin: .fullRefresh, requestedAt: now)])
        #expect(line(run, phase: .spinner) != nil)
    }
}

/// Round-3 S2 (Oct 2026): the menu-bar slosh frame clock. Stepped by hand (`autoTick: false`).
@MainActor
@Suite
struct MenuBarSloshTests {
    @Test func aPillSloshesWhileItsAccountIsCheckedAndFinishesItsWaveBeforeGoingFlat() {
        let slosh = MenuBarSlosh(autoTick: false)
        slosh.update([.claude], reduceMotion: false)
        #expect(slosh.phases == [.claude: 0])

        for _ in 0..<3 { slosh.advance() }
        slosh.update([], reduceMotion: false)
        // The check ended mid-wave: the surface keeps travelling to the end of the cycle.
        #expect(slosh.sloshing == [.claude])
        for _ in 0..<(MenuBarSlosh.frameCount - 4) { slosh.advance() }
        #expect(slosh.sloshing == [.claude])
        slosh.advance()
        #expect(slosh.sloshing.isEmpty)
        #expect(slosh.phase == 0)
    }

    @Test func onlyThePillsBeingCheckedMove() {
        let slosh = MenuBarSlosh(autoTick: false)
        slosh.update([.codex], reduceMotion: false)
        #expect(slosh.phases[.claude] == nil)
        #expect(slosh.phases[.codex] == 0)
    }

    @Test func reduceMotionKeepsEveryPillFlat() {
        let slosh = MenuBarSlosh(autoTick: false)
        slosh.update([.claude], reduceMotion: false)
        slosh.update([.claude], reduceMotion: true)
        #expect(slosh.phases.isEmpty)
    }
}
