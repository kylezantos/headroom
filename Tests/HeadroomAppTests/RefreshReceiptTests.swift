import Foundation
import HeadroomCore
import Testing
@testable import Headroom

/// W4 (Oct 2026, design/refresh-stamp-merge-round4.html): the footer receipt's copy for a
/// refresh the user started, and the hand-back to the stamp once the work drains.
@Suite
struct RefreshReceiptTests {
    private let claude = AccountKey(providerID: .claude, accountID: .primary)
    private let work = AccountKey(providerID: .claude, accountID: AccountID("work"))

    private func line(_ progress: RefreshProgress?, live: Set<AccountKey> = []) -> RefreshReceipt.Line? {
        RefreshReceipt.line(
            progress: progress,
            title: { $0 == self.work ? "Claude Work" : "Claude" },
            isLive: { live.contains($0) }
        )
    }

    @Test func noUserWorkLeavesTheSlotToTheStamp() {
        #expect(line(nil) == nil)
        #expect(line(RefreshProgress(total: 0, completed: 0, lastLanded: nil)) == nil)
    }

    @Test func beforeAnythingLandsItCountsWhatWasAskedFor() {
        #expect(line(RefreshProgress(total: 5, completed: 0, lastLanded: nil))
            == .init(checked: false, text: "Checking 5 accounts…", count: nil))
        #expect(line(RefreshProgress(total: 1, completed: 0, lastLanded: nil))?.text == "Checking 1 account…")
    }

    @Test func eachLandingNamesTheAccountAndTheCount() {
        #expect(line(RefreshProgress(total: 5, completed: 2, lastLanded: work), live: [work])
            == .init(checked: true, text: "Claude Work", count: "2 of 5"))
    }

    /// A probe that came back stale is named without a check; its card says what went wrong.
    @Test func aStaleLandingIsNamedWithoutACheck() {
        #expect(line(RefreshProgress(total: 2, completed: 1, lastLanded: claude))?.checked == false)
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
