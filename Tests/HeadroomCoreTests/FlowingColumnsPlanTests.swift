import Testing
@testable import HeadroomCore

/// U11 / KTD17. The iPad usage screen flows provider cards into columns. The column count comes
/// from the measured width and a Dynamic Type-scaled minimum card width; the assignment of cards
/// to columns is stable across ordinary height changes and re-plans only when the width, the
/// scaled card widths, or the card set changes.
@Suite struct FlowingColumnsPlanTests {
    private let metrics = FlowingColumnsMetrics.standard

    private func cards(_ heights: [Double]) -> [FlowingColumnsCard<String>] {
        heights.enumerated().map { FlowingColumnsCard(id: "card\($0.offset)", height: $0.element) }
    }

    private func geometry(_ width: Double, cards count: Int = 5,
                          metrics: FlowingColumnsMetrics = .standard) -> FlowingColumnsGeometry {
        FlowingColumnsGeometry.resolve(availableWidth: width, metrics: metrics, cardCount: count)
    }

    // MARK: Column count

    @Test func standardMetricsMatchTheApprovedMock() {
        #expect(metrics.margin == 28)
        #expect(metrics.gap == 20)
        #expect(metrics.minimumCardWidth == 400)
        #expect(metrics.maximumCardWidth >= metrics.minimumCardWidth)
    }

    /// iPad Pro 13″ portrait: two columns that span the width between 28pt margins.
    @Test func thirteenInchPortraitHasTwoColumns() {
        let g = geometry(1032)
        #expect(g.columnCount == 2)
        #expect(g.columnWidth == (1032 - 56 - 20) / 2)
        #expect(g.leadingInset == 28)
        #expect(g.columnX(1) == 28 + g.columnWidth + 20)
    }

    @Test func thirteenInchLandscapeHasThreeColumns() {
        let g = geometry(1376)
        #expect(g.columnCount == 3)
        #expect(abs(g.columnWidth - (1376 - 56 - 40) / 3) < 1e-9)
        #expect(g.leadingInset == 28)
    }

    /// 11-inch (834pt) and mini (744pt) portrait can't fit two 400pt cards.
    @Test(arguments: [834.0, 744.0])
    func smallerIPadPortraitHasOneColumn(width: Double) {
        #expect(geometry(width).columnCount == 1)
    }

    /// Stage Manager's narrowest windows are compact width; anything there is one column, and a
    /// card narrower than the minimum still fits between the margins rather than overflowing.
    @Test(arguments: [320.0, 375.0, 507.0])
    func stageManagerMinimumWindowsHaveOneColumnWithoutOverflow(width: Double) {
        let g = geometry(width)
        #expect(g.columnCount == 1)
        #expect(g.leadingInset >= 28)
        #expect(g.leadingInset + g.gridWidth <= width - 28 + 1e-9)
    }

    /// iPhone landscape follows the same formula: n columns fit when
    /// n·min + (n−1)·gap ≤ width − 2·margin.
    @Test(arguments: [
        (667.0, 1),  // iPhone SE
        (750.0, 1),  // iPhone 17 Pro inside its landscape safe area
        (832.0, 1),  // iPhone 17 Pro Max inside its landscape safe area
        (874.0, 1),  // iPhone 17 Pro full width: 818 < 820
        (956.0, 2),  // iPhone 17 Pro Max full width: 900 ≥ 820
    ])
    func iPhoneLandscapeFollowsTheFormula(width: Double, expected: Int) {
        #expect(geometry(width).columnCount == expected)
    }

    @Test func theCountChangesExactlyAtTheFormulaBoundary() {
        // Two columns need 2·400 + 20 = 820 between the margins: 876pt overall.
        #expect(geometry(876).columnCount == 2)
        #expect(geometry(875.5).columnCount == 1)
    }

    /// With fewer cards than would fit, the grid uses one column per card instead of leaving
    /// empty columns, and the cards center at their maximum width.
    @Test func fewerCardsThanColumnsUseOneColumnPerCard() {
        let g = geometry(1376, cards: 2)
        #expect(g.columnCount == 2)
        #expect(g.columnWidth == metrics.maximumCardWidth)
        #expect(abs(g.leadingInset - (1376 - g.gridWidth) / 2) < 1e-9)
        #expect(geometry(1376, cards: 0).columnCount == 1)
    }

    // MARK: Maximum width and centering

    @Test func cardsStopGrowingAtTheMaximumWidthAndTheGridCenters() {
        let g = geometry(834)
        #expect(g.columnCount == 1)
        #expect(g.columnWidth == metrics.maximumCardWidth)
        #expect(g.leadingInset == (834 - metrics.maximumCardWidth) / 2)

        let wide = geometry(2000, cards: 3)
        #expect(wide.columnCount == 3)
        #expect(wide.columnWidth == metrics.maximumCardWidth)
        #expect(wide.gridWidth == 3 * metrics.maximumCardWidth + 40)
        #expect(wide.leadingInset == (2000 - wide.gridWidth) / 2)
    }

    @Test func columnsNeverExceedTheMaximumOrOverflowTheWidth() {
        for width in stride(from: 300.0, through: 2600, by: 7) {
            let g = geometry(width)
            #expect(g.columnWidth <= metrics.maximumCardWidth)
            #expect(g.leadingInset >= metrics.margin - 1e-9)
            #expect(g.leadingInset + g.gridWidth <= width - metrics.margin + 1e-6)
        }
    }

    // MARK: Assignment

    /// Each card goes to the shortest column so far (leftmost on ties), so the first row fills
    /// left to right in card order and columns stay balanced.
    @Test func cardsGoToTheShortestColumnInOrder() {
        let plan = FlowingColumnsPlanner.plan(
            cards: cards([300, 100, 100, 100]), availableWidth: 1032, metrics: metrics, previous: nil
        )
        #expect(plan.columns == [["card0"], ["card1", "card2", "card3"]])
    }

    @Test func orderIsPreservedWithinAndAcrossColumns() {
        let plan = FlowingColumnsPlanner.plan(
            cards: cards([220, 340, 180, 260, 120, 300]), availableWidth: 1376, metrics: metrics,
            previous: nil
        )
        #expect(plan.columns.map(\.first) == ["card0", "card1", "card2"])
        for column in plan.columns {
            let positions = column.compactMap { id in plan.cardIDs.firstIndex(of: id) }
            #expect(positions == positions.sorted())
        }
        #expect(plan.columns.flatMap { $0 }.sorted() == plan.cardIDs.sorted())
    }

    @Test func placementsStackEachColumnWithTheGap() {
        let plan = FlowingColumnsPlanner.plan(
            cards: cards([300, 100, 100]), availableWidth: 1032, metrics: metrics, previous: nil
        )
        let placement = plan.placement(heights: [300, 100, 100])
        let g = plan.geometry
        #expect(placement.frames[0] == .init(x: 28, y: 0, width: g.columnWidth, height: 300))
        #expect(placement.frames[1] == .init(x: g.columnX(1), y: 0, width: g.columnWidth, height: 100))
        #expect(placement.frames[2] == .init(x: g.columnX(1), y: 120, width: g.columnWidth, height: 100))
        #expect(placement.contentHeight == 300)
    }

    // MARK: Stability

    /// A capsule opening or a receipt line appearing changes a card's height. The cards stay in
    /// their columns, even where a fresh plan from the new heights would have moved them.
    @Test func aHeightChangeKeepsTheAssignment() {
        let first = FlowingColumnsPlanner.plan(
            cards: cards([200, 200, 200, 200]), availableWidth: 1032, metrics: metrics, previous: nil
        )
        #expect(first.columns == [["card0", "card2"], ["card1", "card3"]])

        let grown = cards([200, 200, 200, 600])
        let kept = FlowingColumnsPlanner.plan(
            cards: grown, availableWidth: 1032, metrics: metrics, previous: first
        )
        #expect(kept.columns == first.columns)
        #expect(kept.revision == first.revision)

        // Proves the test can fail: from scratch, a taller card0 would shift the layout.
        let tall = cards([600, 200, 200, 200])
        let fresh = FlowingColumnsPlanner.plan(cards: tall, availableWidth: 1032, metrics: metrics, previous: nil)
        let keptTall = FlowingColumnsPlanner.plan(cards: tall, availableWidth: 1032, metrics: metrics, previous: first)
        #expect(fresh.columns != first.columns)
        #expect(keptTall.columns == first.columns)

        // Frames follow the new heights inside the kept columns.
        let placement = kept.placement(heights: grown.map(\.height))
        #expect(placement.frames[3].height == 600)
        #expect(placement.contentHeight == 820)
    }

    @Test func floatingPointNoiseDoesNotReplanButARealResizeDoes() {
        let first = FlowingColumnsPlanner.plan(
            cards: cards([200, 200, 200]), availableWidth: 1032, metrics: metrics, previous: nil
        )
        #expect(FlowingColumnsPlanner.replanReason(
            previous: first, availableWidth: 1032.0004, metrics: metrics, cardIDs: first.cardIDs
        ) == nil)
        #expect(FlowingColumnsPlanner.replanReason(
            previous: first, availableWidth: 1031.5, metrics: metrics, cardIDs: first.cardIDs
        ) == .width)
        #expect(FlowingColumnsPlanner.replanReason(
            previous: first, availableWidth: 1376, metrics: metrics, cardIDs: first.cardIDs
        ) == .width)
    }

    @Test func addingACardReplansOnce() {
        let first = FlowingColumnsPlanner.plan(
            cards: cards([200, 200, 200]), availableWidth: 1032, metrics: metrics, previous: nil
        )
        #expect(FlowingColumnsPlanner.replanReason(
            previous: nil, availableWidth: 1032, metrics: metrics, cardIDs: first.cardIDs
        ) == .initial)

        let four = cards([200, 200, 200, 120])
        #expect(FlowingColumnsPlanner.replanReason(
            previous: first, availableWidth: 1032, metrics: metrics, cardIDs: four.map(\.id)
        ) == .cards)
        let added = FlowingColumnsPlanner.plan(cards: four, availableWidth: 1032, metrics: metrics, previous: first)
        #expect(added.revision == first.revision + 1)
        #expect(added.cardIDs == four.map(\.id))

        let again = FlowingColumnsPlanner.plan(
            cards: cards([200, 260, 200, 120]), availableWidth: 1032, metrics: metrics, previous: added
        )
        #expect(again.revision == added.revision)
        #expect(again.columns == added.columns)
    }

    /// Make Main and Settings reorder cards; the order is part of the plan's identity.
    @Test func reorderingCardsReplans() {
        let first = FlowingColumnsPlanner.plan(
            cards: cards([200, 200, 200]), availableWidth: 1032, metrics: metrics, previous: nil
        )
        #expect(FlowingColumnsPlanner.replanReason(
            previous: first, availableWidth: 1032, metrics: metrics, cardIDs: first.cardIDs.reversed()
        ) == .cards)
    }

    // MARK: Dynamic Type

    /// A larger text size scales the minimum card width; at a fixed 1376pt window three cards
    /// no longer fit, so the grid re-plans to two from re-measured heights. Returning to the
    /// default size restores three.
    @Test func aTextSizeChangeAtAFixedWidthChangesTheCountAndReturningRestoresIt() {
        let base = FlowingColumnsPlanner.plan(
            cards: cards([200, 200, 200, 200]), availableWidth: 1376, metrics: metrics, previous: nil
        )
        #expect(base.geometry.columnCount == 3)

        let larger = metrics.scaled(by: 1.1)
        #expect(abs(larger.minimumCardWidth - 440) < 1e-9)
        #expect(larger.margin == metrics.margin)
        #expect(larger.gap == metrics.gap)
        #expect(FlowingColumnsPlanner.replanReason(
            previous: base, availableWidth: 1376, metrics: larger, cardIDs: base.cardIDs
        ) == .metrics)

        let remeasured = cards([240, 260, 240, 250])
        let scaled = FlowingColumnsPlanner.plan(
            cards: remeasured, availableWidth: 1376, metrics: larger, previous: base
        )
        #expect(scaled.geometry.columnCount == 2)
        #expect(scaled.revision == base.revision + 1)
        #expect(scaled.geometry.leadingInset + scaled.geometry.gridWidth <= 1376 - 28 + 1e-9)
        #expect(scaled.geometry.columnWidth >= larger.minimumCardWidth)

        let restored = FlowingColumnsPlanner.plan(
            cards: cards([200, 200, 200, 200]), availableWidth: 1376, metrics: metrics, previous: scaled
        )
        #expect(restored.geometry.columnCount == 3)
        #expect(restored.columns == base.columns)
    }

    @Test func accessibilityTextSizesFallBackToOneColumnWithoutOverflow() {
        let huge = metrics.scaled(by: 2.4)
        let g = FlowingColumnsGeometry.resolve(availableWidth: 1032, metrics: huge, cardCount: 5)
        #expect(g.columnCount == 1)
        #expect(g.leadingInset + g.gridWidth <= 1032 - 28 + 1e-9)
    }

    @Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
    func aNonFiniteWidthResolvesToOneColumnInsteadOfTrapping(width: Double) {
        let g = FlowingColumnsGeometry.resolve(availableWidth: width, metrics: metrics, cardCount: 4)
        #expect(g.columnCount == 1)
        #expect(g.columnWidth == 0)
    }

    @Test func aMaximumBelowTheMinimumIsRaisedToIt() {
        let odd = FlowingColumnsMetrics(margin: 28, gap: 20, minimumCardWidth: 500, maximumCardWidth: 300)
        let g = FlowingColumnsGeometry.resolve(availableWidth: 1200, metrics: odd, cardCount: 4)
        #expect(g.columnCount == 2)
        #expect(g.columnWidth == 500)
    }
}
