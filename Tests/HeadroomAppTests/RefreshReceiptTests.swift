import Foundation
import HeadroomCore
import Testing
@testable import Headroom

@Suite(.sharedAppState) struct RefreshReceiptTests {
    private let claude = AccountKey(providerID: .claude, accountID: .primary)
    private let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
    private let now = Date(timeIntervalSince1970: 100)

    /// The footer passes the recipe's rest phase; the presentation lives in Core (U6).
    private func line(_ run: UserRefreshRun?, phase: ReprintRecipe.Phase = .spinner, date: Date? = nil) -> RefreshReceiptPresentation.Line? {
        RefreshReceiptPresentation.line(run: run, isResting: phase == .rest, now: date ?? now,
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
        let expected = RefreshReceiptPresentation.Line(checked: true, text: "Claude Work", count: "2 of 2")
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

    /// CA-M1: "2 of 3 → 3 of 3" on one account rolls only the count; the name slot keeps
    /// its identity, so the name does not slide away and back.
    @Test func aCountChangeLeavesTheNameSlotInPlace() {
        let twoOfThree = RefreshReceiptPresentation.landed(title: "Claude Work", live: true, completed: 2, total: 3)
        let threeOfThree = RefreshReceiptPresentation.landed(title: "Claude Work", live: true, completed: 3, total: 3)
        #expect(ReceiptRoll.nameSlotID(twoOfThree) == ReceiptRoll.nameSlotID(threeOfThree))
        #expect(ReceiptRoll.countValue(twoOfThree.count ?? "") == 2)
        #expect(ReceiptRoll.countValue(threeOfThree.count ?? "") == 3)
    }

    /// CA-M1: three receipts landing 60ms apart are three name slots, each removed on the
    /// 80ms part exit (KTD8) rather than stacked, so only the last one is left. The roll
    /// travels the approved 7pt, not a full line.
    @Test func aBurstOfReceiptsLeavesOnlyTheLastOne() {
        let lines = ["Claude", "Claude Work", "Codex"].enumerated().map { index, title in
            RefreshReceiptPresentation.landed(title: title, live: true, completed: index + 1, total: 3)
        }
        #expect(Set(lines.map(ReceiptRoll.nameSlotID)).count == 3)
        #expect(ReceiptRoll.exitAnimation == HeadroomMotion.partOut)
        #expect(ReceiptRoll.distance == 7)
    }

    /// U6: the phone's check-now line reuses these strings, so pin them here as the Mac
    /// footer shows them.
    @Test func sharedReceiptStringsAreTheFooterStrings() {
        #expect(RefreshReceiptPresentation.checking(1).text == "Checking 1 account…")
        #expect(RefreshReceiptPresentation.checking(3).text == "Checking 3 accounts…")
        #expect(RefreshReceiptPresentation.landed(title: "Claude Work", live: true, completed: 2, total: 3)
            == .init(checked: true, text: "Claude Work", count: "2 of 3"))
        #expect(RefreshReceiptPresentation.title(providerName: "Claude", accountTitle: "Work", providerAccountCount: 1) == "Claude")
        #expect(RefreshReceiptPresentation.title(providerName: "Claude", accountTitle: "Work", providerAccountCount: 2) == "Claude Work")
    }
}
