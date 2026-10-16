import Testing
@testable import HeadroomCore

/// U3 / KTD1–KTD2. The Mac popover shows one column of provider cards until the single-column
/// stack would pass the cards-height cap, then two columns read down then across (R4, R5). The
/// count and split are decided on open and on an account-set change, never on a height change
/// (R6); two columns that still pass the cap scroll (R8).
@Suite struct AccountColumnsPlanTests {
    private let metrics = AccountColumnsMetrics.popover
    private let cap = 640.0
    /// A Standard-format account section inside a multi-account card.
    private let row = 74.0

    private func accounts(_ provider: String, _ heights: [Double]) -> [AccountColumnsItem] {
        heights.enumerated().map {
            AccountColumnsItem(id: "\(provider).\($0.offset)", groupID: provider, height: $0.element)
        }
    }

    private func spend(_ height: Double = 60) -> AccountColumnsItem {
        AccountColumnsItem(id: "spend", groupID: "spend", height: height, isSpend: true)
    }

    private func plan(
        _ items: [AccountColumnsItem], cap: Double? = nil, generation: Int = 0,
        previous: AccountColumnsPlan? = nil
    ) -> AccountColumnsPlan {
        AccountColumnsPlanner.plan(items: items, cap: cap ?? self.cap, generation: generation, previous: previous)
    }

    private func columnIDs(_ plan: AccountColumnsPlan) -> [[String]] {
        [Array(plan.itemIDs[..<plan.splitIndex]), Array(plan.itemIDs[plan.splitIndex...])]
    }

    @Test func disablingHorizontalExpansionKeepsATallListInReadingOrder() {
        let items = accounts("claude", Array(repeating: row, count: 20))
            + accounts("codex", [row]) + [spend()]
        let result = AccountColumnsPlanner.plan(
            items: items, cap: cap, generation: 0, previous: nil,
            allowsHorizontalExpansion: false
        )
        #expect(result.columnCount == 1)
        #expect(result.splitIndex == items.count)
        #expect(result.itemIDs == items.map(\.id))
        let placed = AccountColumnsPlanner.placement(of: result, items: items)
        #expect(placed.contentHeight > cap)
        #expect(placed.columnHeights.count == 1)
        #expect(placed.fragments.map(\.groupID) == ["claude", "codex", "spend"])
    }

    @Test func disablingHorizontalExpansionOverridesAKeptTwoColumnPlan() {
        let items = accounts("claude", Array(repeating: row, count: 20))
        let two = plan(items)
        #expect(two.columnCount == 2)
        let single = AccountColumnsPlanner.plan(
            items: items, cap: cap, generation: two.generation, previous: two,
            allowsHorizontalExpansion: false
        )
        #expect(single.columnCount == 1)
        #expect(plan(items, generation: 1, previous: single).columnCount == 2)
    }

    /// Single-account cards of `heights`, one provider each.
    private func singles(_ heights: [Double]) -> [AccountColumnsItem] {
        heights.enumerated().flatMap { accounts("p\($0.offset)", [$0.element]) }
    }

    // MARK: Metrics

    @Test func popoverMetricsMatchProviderCardView() {
        #expect(metrics.cardPadding == 13)
        #expect(metrics.cardGap == 20)
        #expect(metrics.accountGap == 26)
        #expect(metrics.columnWidth == 346)
        #expect(metrics.gridWidth(columns: 1) == 346)
        #expect(metrics.gridWidth(columns: 2) == 712)
        #expect(metrics.columnX(0) == 0)
        #expect(metrics.columnX(1) == 366)
    }

    // MARK: Single-column height

    /// Characterizes today's measured `cardsHeight`: a VStack(spacing: 20) of cards, each padded
    /// 13pt top and bottom, accounts in one card 26pt apart.
    @Test func singleColumnHeightMatchesTheTodayStackForMulti5() {
        let claude = [70.0, 74, 78, 74, 74]
        let codex = [80.0, 76, 72]
        let items = accounts("claude", claude) + accounts("codex", codex) + [spend(58)]
        let claudeCard = 26 + claude.reduce(0, +) + 4 * 26
        let codexCard = 26 + codex.reduce(0, +) + 2 * 26
        let spendCard = 26 + 58.0
        let expected = claudeCard + 20 + codexCard + 20 + spendCard
        #expect(AccountColumnsPlanner.singleColumnHeight(items: items) == expected)

        let placement = AccountColumnsPlanner.placement(of: plan(items, cap: 10_000), items: items)
        #expect(placement.columnHeights == [expected])
        #expect(placement.contentHeight == expected)
    }

    // MARK: Column count

    @Test func underTheCapIsOneColumnWithNoSplit() {
        let items = accounts("claude", [row, row]) + accounts("codex", [row]) + [spend()]
        let result = plan(items)
        #expect(AccountColumnsPlanner.singleColumnHeight(items: items) < cap)
        #expect(result.columnCount == 1)
        #expect(result.splitIndex == items.count)
        #expect(result.itemIDs == items.map(\.id))
    }

    @Test func exactlyAtTheCapIsOneColumn() {
        let items = singles([100, 100, 100])  // 3·126 + 2·20 = 418
        #expect(AccountColumnsPlanner.singleColumnHeight(items: items) == 418)
        #expect(plan(items, cap: 418).columnCount == 1)
        #expect(plan(items, cap: 417.9).columnCount == 2)
    }

    /// The options doc's case: seven Claude accounts and one Codex account at Standard heights.
    @Test func sevenClaudeAndOneCodexSplitInsideClaudeWithMainTopLeft() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        // Claude card 26 + 7·74 + 6·26 = 700, Codex card 100, gap 20.
        #expect(AccountColumnsPlanner.singleColumnHeight(items: items) == 820)
        let result = plan(items)
        #expect(result.columnCount == 2)
        #expect(result.itemIDs.first == "claude.0")
        #expect(result.splitIndex == 4)

        let placement = AccountColumnsPlanner.placement(of: result, items: items)
        #expect(placement.fragments.map(\.groupID) == ["claude", "claude", "codex"])
        #expect(placement.fragments[0] == AccountColumnsFragment(
            groupID: "claude", itemRange: 0..<4, isFirstFragmentOfGroup: true, column: 0, y: 0, height: 400
        ))
        #expect(placement.fragments[1] == AccountColumnsFragment(
            groupID: "claude", itemRange: 4..<7, isFirstFragmentOfGroup: false, column: 1, y: 0, height: 300
        ))
        #expect(placement.fragments[2] == AccountColumnsFragment(
            groupID: "codex", itemRange: 7..<8, isFirstFragmentOfGroup: true, column: 1, y: 320, height: 100
        ))
        #expect(placement.columnHeights == [400, 420])
        #expect(placement.contentHeight == 420)
    }

    /// A split inside a provider gives both halves their own 13pt top and bottom padding and
    /// drops the 26pt account gap where the card was cut.
    @Test func aSplitInsideAProviderAddsFragmentChromeAndDropsTheAccountGap() {
        let items = accounts("claude", [100, 100, 100, 100])
        let single = AccountColumnsPlanner.singleColumnHeight(items: items)
        #expect(single == 26 + 400 + 78)
        let result = plan(items, cap: 300)
        #expect(result.columnCount == 2)
        #expect(result.splitIndex == 2)
        let placement = AccountColumnsPlanner.placement(of: result, items: items)
        let fragment: Double = 26 + 200 + 26
        #expect(placement.columnHeights == [fragment, fragment])
        #expect(placement.columnHeights.reduce(0, +) == single + 2 * 13 - 26)
        #expect(placement.fragments.map(\.isFirstFragmentOfGroup) == [true, false])
    }

    /// A split between providers adds no chrome: each card keeps its own padding.
    @Test func aSplitBetweenProvidersAddsNoChrome() {
        let items = singles([200, 200])
        let result = plan(items, cap: 400)
        #expect(result.columnCount == 2)
        #expect(result.splitIndex == 1)
        let placement = AccountColumnsPlanner.placement(of: result, items: items)
        #expect(placement.columnHeights == [226, 226])
        #expect(placement.fragments.map(\.isFirstFragmentOfGroup) == [true, true])
    }

    /// The caller folds a recovering provider's header and notice (plus the 26pt gap below them)
    /// into its first item, since that header is only drawn in the first fragment. The heavier
    /// first item moves the split earlier than the same provider without the notice.
    @Test func aCapabilityRecoveryHeaderCountsOnTheFirstItem() {
        let plain = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        var recovering = plain
        recovering[0] = AccountColumnsItem(id: "claude.0", groupID: "claude", height: row + 200 + 26)
        let plainPlan = plan(plain)
        let recoveringPlan = plan(recovering)
        #expect(recoveringPlan.splitIndex < plainPlan.splitIndex)
        let placement = AccountColumnsPlanner.placement(of: recoveringPlan, items: recovering)
        #expect(placement.fragments[0].itemRange.lowerBound == 0)
        #expect(placement.fragments[0].isFirstFragmentOfGroup)
        #expect(AccountColumnsPlanner.singleColumnHeight(items: recovering)
            == AccountColumnsPlanner.singleColumnHeight(items: plain) + 226)
    }

    // MARK: Spend

    @Test func theSpendItemLandsLastInTheSecondColumn() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row]) + [spend()]
        let result = plan(items)
        #expect(result.columnCount == 2)
        #expect(columnIDs(result)[1].last == "spend")
        let placement = AccountColumnsPlanner.placement(of: result, items: items)
        let last = placement.fragments.last
        #expect(last?.groupID == "spend")
        #expect(last?.column == 1)
        #expect(last?.isFirstFragmentOfGroup == true)
    }

    /// Spend is its own card even if a caller gave it a provider's group ID.
    @Test func theSpendItemIsAlwaysItsOwnCard() {
        let items = accounts("claude", [100]) + [
            AccountColumnsItem(id: "spend", groupID: "claude", height: 60, isSpend: true),
        ]
        #expect(AccountColumnsPlanner.singleColumnHeight(items: items) == 126 + 20 + 86)
        let placement = AccountColumnsPlanner.placement(of: plan(items), items: items)
        #expect(placement.fragments.count == 2)
    }

    /// A big spend card never pulls accounts into column 1 after it, nor sits in column 0 alone.
    @Test func theSpendItemNeverLeavesTheLastColumn() {
        let items = singles([100, 100]) + [spend(500)]
        let result = plan(items, cap: 300)
        #expect(result.columnCount == 2)
        #expect(result.splitIndex == 2)
        #expect(columnIDs(result)[1] == ["spend"])
    }

    @Test func noSpendChangesNothingElse() {
        let base = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let withSpend = base + [spend(0.0001)]
        #expect(plan(base).columnCount == plan(withSpend).columnCount)
        #expect(plan(base).itemIDs == Array(plan(withSpend).itemIDs.dropLast()))
    }

    // MARK: Scroll and bounds

    @Test func twentyAccountsPerProviderScrollInTwoColumns() {
        let items = accounts("claude", Array(repeating: row, count: 20))
            + accounts("codex", Array(repeating: row, count: 20)) + [spend()]
        let result = plan(items)
        #expect(result.columnCount == 2)
        let placement = AccountColumnsPlanner.placement(of: result, items: items)
        #expect(placement.columnHeights.count == 2)
        #expect(placement.contentHeight > cap)
        // Balanced to within one account row.
        #expect(abs(placement.columnHeights[0] - placement.columnHeights[1]) <= row + 26 + 26)
    }

    @Test func neverMoreThanTwoColumns() {
        for count in 0...60 {
            let items = accounts("claude", Array(repeating: row, count: count)) + [spend()]
            let result = plan(items, cap: 100)
            #expect(result.columnCount <= 2)
            #expect(AccountColumnsPlanner.placement(of: result, items: items).columnHeights.count <= 2)
        }
    }

    @Test func aSingleItemTallerThanTheCapIsOneColumn() {
        let items = accounts("claude", [900])
        let result = plan(items)
        #expect(result.columnCount == 1)
        #expect(AccountColumnsPlanner.placement(of: result, items: items).contentHeight == 926)
    }

    @Test func anEmptyListIsOneColumnOfZeroHeight() {
        let result = plan([])
        #expect(result.columnCount == 1)
        #expect(result.splitIndex == 0)
        let placement = AccountColumnsPlanner.placement(of: result, items: [])
        #expect(placement.fragments.isEmpty)
        #expect(placement.contentHeight == 0)
        #expect(AccountColumnsPlanner.singleColumnHeight(items: []) == 0)
    }

    @Test func onlySpendIsOneColumn() {
        let result = plan([spend(900)])
        #expect(result.columnCount == 1)
        #expect(result.splitIndex == 1)
    }

    @Test func oneProviderWithOneAccountIsOneCard() {
        let items = accounts("claude", [row])
        let placement = AccountColumnsPlanner.placement(of: plan(items), items: items)
        #expect(placement.fragments == [AccountColumnsFragment(
            groupID: "claude", itemRange: 0..<1, isFirstFragmentOfGroup: true, column: 0, y: 0, height: 100
        )])
    }

    /// Equal taller-column candidates resolve to more content in column 0 (down then across).
    @Test func tiesPreferMoreContentInTheFirstColumn() {
        let items = singles([100, 100, 100])  // splits 1 and 2 both give a 272pt taller column
        let result = plan(items, cap: 300)
        #expect(result.splitIndex == 2)
    }

    // MARK: Stability (R6)

    /// Data loading or a card growing while open keeps the split, even where a fresh plan from
    /// the new heights would have moved it.
    @Test func aHeightChangeKeepsTheSplit() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let first = plan(items, generation: 1)
        var grown = items
        grown[0] = AccountColumnsItem(id: "claude.0", groupID: "claude", height: 300)
        let kept = plan(grown, generation: 1, previous: first)
        #expect(kept == first)

        // Proves the test can fail: from scratch, the taller first account moves the split.
        let fresh = plan(grown, generation: 1)
        #expect(fresh.splitIndex != first.splitIndex)

        // Placement follows the new heights under the kept split.
        let placement = AccountColumnsPlanner.placement(of: kept, items: grown)
        #expect(placement.columnHeights[0] == 400 - row + 300)
    }

    @Test func aShrinkBelowTheCapKeepsTwoColumnsWhileOpen() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let first = plan(items, generation: 3)
        let shrunk = accounts("claude", Array(repeating: 20, count: 7)) + accounts("codex", [20])
        #expect(plan(shrunk, generation: 3, previous: first) == first)
    }

    @Test func floatingPointNoiseDoesNotReplanOrFlipTheCount() {
        let items = singles([100, 100, 100])
        let first = plan(items, cap: 418, generation: 1)
        #expect(first.columnCount == 1)
        let noisy = singles([100.0001, 100, 100.0002])
        #expect(plan(noisy, cap: 418, generation: 1, previous: first) == first)
        // Even on a fresh open, sub-pixel noise at the cap stays one column.
        #expect(plan(noisy, cap: 418, generation: 2).columnCount == 1)
        #expect(AccountColumnsPlanner.needsReplan(previous: first, itemIDs: first.itemIDs, generation: 1) == false)
    }

    /// Noise must not flip a tie between two splits either.
    @Test func floatingPointNoiseDoesNotFlipATie() {
        let tie = plan(singles([100, 100, 100]), cap: 300)
        let noisy = plan(singles([100, 100, 100.0002]), cap: 300)
        let noisyOther = plan(singles([100.0002, 100, 100]), cap: 300)
        #expect(tie.splitIndex == 2)
        #expect(noisy.splitIndex == 2)
        #expect(noisyOther.splitIndex == 2)
    }

    @Test func addingOrRemovingAnItemReplansOnce() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let first = plan(items, generation: 1)

        let added = items + accounts("grok", [row])
        #expect(AccountColumnsPlanner.needsReplan(previous: first, itemIDs: added.map(\.id), generation: 1))
        let replanned = plan(added, generation: 1, previous: first)
        #expect(replanned.itemIDs == added.map(\.id))
        #expect(replanned != first)

        var tweaked = added
        tweaked[8] = AccountColumnsItem(id: "grok.0", groupID: "grok", height: 120)
        #expect(plan(tweaked, generation: 1, previous: replanned) == replanned)

        let removed = Array(items.dropLast())
        let afterRemoval = plan(removed, generation: 1, previous: replanned)
        #expect(afterRemoval.itemIDs == removed.map(\.id))
        #expect(plan(removed, generation: 1, previous: afterRemoval) == afterRemoval)
    }

    /// Make Main reorders the account list; the new main sits top-left.
    @Test func reorderingReplansWithTheNewMainTopLeft() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let first = plan(items, generation: 1)
        var reordered = items
        reordered.swapAt(0, 5)
        #expect(AccountColumnsPlanner.needsReplan(previous: first, itemIDs: reordered.map(\.id), generation: 1))
        let result = plan(reordered, generation: 1, previous: first)
        #expect(result.itemIDs.first == "claude.5")
        let placement = AccountColumnsPlanner.placement(of: result, items: reordered)
        #expect(placement.fragments[0].column == 0)
        #expect(placement.fragments[0].y == 0)
        #expect(placement.fragments[0].itemRange.lowerBound == 0)
    }

    @Test func aNewOpenGenerationReplansWithCurrentHeights() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let first = plan(items, generation: 1)
        var grown = items
        grown[0] = AccountColumnsItem(id: "claude.0", groupID: "claude", height: 300)
        #expect(AccountColumnsPlanner.needsReplan(previous: first, itemIDs: grown.map(\.id), generation: 2))
        let reopened = plan(grown, generation: 2, previous: first)
        #expect(reopened.generation == 2)
        #expect(reopened.splitIndex == plan(grown, generation: 2).splitIndex)
        #expect(reopened.splitIndex != first.splitIndex)
    }

    // MARK: Hysteresis (KTD2)

    @Test func hysteresisHoldsTwoColumnsUntilARowAllowanceBelowTheCap() {
        let items = singles([100, 100, 100])  // single column 418, allowance 100
        let two = plan(items, cap: 400, generation: 1)
        #expect(two.columnCount == 2)
        // Without history, 418 under a 420 cap is one column…
        #expect(plan(items, cap: 420, generation: 2).columnCount == 1)
        // …but a previous two-column plan holds until 418 ≤ cap − 100.
        #expect(plan(items, cap: 420, generation: 2, previous: two).columnCount == 2)
        #expect(plan(items, cap: 517.9, generation: 2, previous: two).columnCount == 2)
        #expect(plan(items, cap: 518, generation: 2, previous: two).columnCount == 1)
    }

    /// The allowance is the tallest non-spend item; a tall spend card does not widen it.
    @Test func theAllowanceIgnoresTheSpendItem() {
        let items = singles([100, 100]) + [spend(150)]  // 126 + 20 + 126 + 20 + 176 = 468
        let two = plan(items, cap: 400, generation: 1)
        #expect(two.columnCount == 2)
        #expect(plan(items, cap: 568, generation: 2, previous: two).columnCount == 1)
        #expect(plan(items, cap: 567, generation: 2, previous: two).columnCount == 2)
    }

    @Test func heightsHoveringAroundTheCapDoNotAlternate() {
        func items(_ total: Double) -> [AccountColumnsItem] {
            // Two single-account cards: total = 2·(h + 26) + 20.
            let h = (total - 20) / 2 - 26
            return singles([h, h])
        }
        var previous: AccountColumnsPlan?
        var counts: [Int] = []
        for (generation, total) in [641.0, 639, 641, 639, 640, 638].enumerated() {
            let next = plan(items(total), generation: generation, previous: previous)
            counts.append(next.columnCount)
            previous = next
        }
        #expect(counts == [2, 2, 2, 2, 2, 2])

        // Starting under the cap stays one column until it truly passes it.
        previous = nil
        counts = []
        for (generation, total) in [639.0, 640, 639.5].enumerated() {
            let next = plan(items(total), generation: generation, previous: previous)
            counts.append(next.columnCount)
            previous = next
        }
        #expect(counts == [1, 1, 1])
    }

    // MARK: Mismatch safety

    /// A plan placed against a different item list (the caller hasn't replanned yet) lays the
    /// items out as one column instead of splitting at an index that means something else.
    @Test func aStalePlanPlacesAsOneColumn() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let stale = plan(items)
        let other = accounts("codex", [row, row])
        let placement = AccountColumnsPlanner.placement(of: stale, items: other)
        #expect(placement.columnHeights.count == 1)
        #expect(placement.columnHeights == [AccountColumnsPlanner.singleColumnHeight(items: other)])
    }

    // MARK: Carrying a plan to a new item list

    /// R6: between an account-set change and the replan that waits on the new items' heights,
    /// the popover keeps drawing two columns rather than collapsing to one for a pass.
    @Test func aCarriedPlanKeepsColumnOneFromItsFirstSurvivingItem() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row]) + [spend()]
        let kept = plan(items)
        #expect(kept.columnCount == 2)
        let secondColumnHead = kept.itemIDs[kept.splitIndex]
        let added = AccountColumnsItem(id: "claude.new", groupID: "claude", height: 0)
        let next = Array(items[..<2]) + [added] + Array(items[2...])
        let carried = AccountColumnsPlanner.carried(kept, to: next)
        #expect(carried.columnCount == 2)
        #expect(carried.itemIDs == next.map(\.id))
        #expect(carried.itemIDs[carried.splitIndex] == secondColumnHead)
    }

    @Test func aCarriedPlanIsUnchangedForTheSameItems() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let kept = plan(items)
        #expect(AccountColumnsPlanner.carried(kept, to: items) == kept)
    }

    @Test func aMissingOrSingleColumnPlanCarriesAsOneColumn() {
        let items = accounts("claude", [row, row])
        #expect(AccountColumnsPlanner.carried(nil, to: items).columnCount == 1)
        #expect(AccountColumnsPlanner.carried(nil, to: items).splitIndex == 2)
        let single = plan(items)
        let more = items + accounts("codex", [row])
        let carried = AccountColumnsPlanner.carried(single, to: more)
        #expect(carried.columnCount == 1)
        #expect(carried.splitIndex == more.count)
    }

    @Test func aCarriedPlanNeverPutsSpendInColumnZeroAndFallsBackWhenColumnOneEmptied() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row]) + [spend()]
        let kept = plan(items)
        // Every account that sat in column 1 is gone; spend alone still reads in column 1.
        let survivors = Array(items[..<kept.splitIndex]) + [spend()]
        let carried = AccountColumnsPlanner.carried(kept, to: survivors)
        #expect(carried.columnCount == 2)
        #expect(carried.itemIDs[carried.splitIndex] == "spend")
        // Without spend, nothing survives in column 1: one column.
        let noSpend = Array(items[..<kept.splitIndex])
        #expect(AccountColumnsPlanner.carried(kept, to: noSpend).columnCount == 1)
    }

    /// A carried plan is for drawing only: it keeps the old generation but its IDs differ from
    /// the stored plan's, so handing the stored plan to `plan` still replans once.
    @Test func carryingDoesNotStandInForTheReplan() {
        let items = accounts("claude", Array(repeating: row, count: 7)) + accounts("codex", [row])
        let kept = plan(items)
        let fewer = Array(items.dropLast(3))
        #expect(AccountColumnsPlanner.needsReplan(previous: kept, itemIDs: fewer.map(\.id), generation: kept.generation))
    }

    // MARK: Fragment headers

    /// The Compact layout's column header repeats in each piece of a split card, so splitting
    /// pays it twice; a whole card pays it once.
    @Test func aFragmentHeaderIsCountedOncePerPiece() {
        let header = 26.0
        let items = (0..<4).map {
            AccountColumnsItem(id: "c.\($0)", groupID: "claude", height: 26, fragmentHeader: header)
        }
        let whole = AccountColumnsPlan(columnCount: 1, splitIndex: 4, itemIDs: items.map(\.id), generation: 0)
        #expect(AccountColumnsPlanner.placement(of: whole, items: items).contentHeight
            == 2 * metrics.cardPadding + header + 4 * 26 + 3 * metrics.accountGap)
        let split = AccountColumnsPlan(columnCount: 2, splitIndex: 2, itemIDs: items.map(\.id), generation: 0)
        let placed = AccountColumnsPlanner.placement(of: split, items: items)
        #expect(placed.columnHeights == [2 * metrics.cardPadding + header + 2 * 26 + metrics.accountGap,
                                         2 * metrics.cardPadding + header + 2 * 26 + metrics.accountGap])
    }
}
