import Foundation

// KTD1 / R4–R8 (popover account layout plan): the Mac popover shows one column of provider
// cards until the single-column stack would pass the cards-height cap, then two columns that
// read down the first and then down the second. This file is the pure decision: the column
// count and the one contiguous split point, plus where each card fragment sits. The popover
// only lays views out from it.
//
// `FlowingColumnsPlanner.assign` is shortest-column masonry, which fills across before down,
// so it can't give R5's down-then-across order and isn't reused here.
//
// Kept to Foundation and plain `Double`s because both iOS targets compile `Models/` whole (KTD4).

/// The popover card stack's fixed measurements, matching `ProviderCardView` and `PopoverView`.
public struct AccountColumnsMetrics: Sendable, Equatable {
    /// Applied to the top and the bottom of every card, and of every fragment of a split card.
    public var cardPadding: Double
    /// Between cards (or fragments) in a column, and between the two columns.
    public var cardGap: Double
    /// Between accounts inside one card; dropped where a card is split across columns.
    public var accountGap: Double
    /// One card's width.
    public var columnWidth: Double

    public static let popover = AccountColumnsMetrics(
        cardPadding: 13, cardGap: 20, accountGap: 26, columnWidth: 346
    )

    public init(cardPadding: Double, cardGap: Double, accountGap: Double, columnWidth: Double) {
        self.cardPadding = cardPadding
        self.cardGap = cardGap
        self.accountGap = accountGap
        self.columnWidth = columnWidth
    }

    /// n·card width + (n−1)·gap; the popover shell adds its own insets.
    public func gridWidth(columns: Int) -> Double {
        let count = max(columns, 1)
        return Double(count) * columnWidth + Double(count - 1) * cardGap
    }

    /// Leading edge of a column within the grid.
    public func columnX(_ column: Int) -> Double {
        Double(column) * (columnWidth + cardGap)
    }
}

/// One entry in the popover's reading order: an account section, or the API spend card.
///
/// Consecutive items with the same `groupID` share one card. `height` is the measured content
/// height without the card's padding. A provider's card header (the capability-recovery
/// identity row and notice, and the 26pt gap below them) is drawn only in the provider's first
/// fragment, so the caller folds that height into the provider's first item; the planner then
/// counts it wherever that item lands.
public struct AccountColumnsItem: Sendable, Equatable {
    /// Stable view identity: the account key string, or a spend ID.
    public let id: String
    /// The provider ID.
    public let groupID: String
    public let height: Double
    /// The spend card is always its own card, last in the flow, and in the last column when
    /// there are two (R5).
    public let isSpend: Bool

    public init(id: String, groupID: String, height: Double, isSpend: Bool = false) {
        self.id = id
        self.groupID = groupID
        self.height = height
        self.isSpend = isSpend
    }
}

/// The column count and split for one item order, kept until a replan trigger (KTD2). Heights
/// are not part of its identity: a kept plan places items at their current heights under the
/// original split, so nothing jumps between columns while the popover is open (R6).
public struct AccountColumnsPlan: Sendable, Equatable {
    /// 1 or 2.
    public let columnCount: Int
    /// `itemIDs[..<splitIndex]` read down column 0, the rest down column 1. Equals
    /// `itemIDs.count` for one column.
    public let splitIndex: Int
    public let itemIDs: [String]
    /// The popover-open (or layout preference) generation this plan was made for.
    public let generation: Int

    public init(columnCount: Int, splitIndex: Int, itemIDs: [String], generation: Int) {
        self.columnCount = columnCount
        self.splitIndex = splitIndex
        self.itemIDs = itemIDs
        self.generation = generation
    }
}

/// One card, or one piece of a card split across columns.
public struct AccountColumnsFragment: Sendable, Equatable {
    public let groupID: String
    /// Indices into the item list.
    public let itemRange: Range<Int>
    /// Only the first fragment draws the provider's card header.
    public let isFirstFragmentOfGroup: Bool
    public let column: Int
    /// Top of the fragment's card within its column.
    public let y: Double
    /// Including the card padding.
    public let height: Double

    public init(groupID: String, itemRange: Range<Int>, isFirstFragmentOfGroup: Bool,
                column: Int, y: Double, height: Double) {
        self.groupID = groupID
        self.itemRange = itemRange
        self.isFirstFragmentOfGroup = isFirstFragmentOfGroup
        self.column = column
        self.y = y
        self.height = height
    }
}

public struct AccountColumnsPlacement: Sendable, Equatable {
    /// Column 0's fragments top to bottom, then column 1's.
    public let fragments: [AccountColumnsFragment]
    public let columnHeights: [Double]
    /// The tallest column; past the cap the popover scrolls (R8).
    public var contentHeight: Double { columnHeights.max() ?? 0 }

    public init(fragments: [AccountColumnsFragment], columnHeights: [Double]) {
        self.fragments = fragments
        self.columnHeights = columnHeights
    }
}

public enum AccountColumnsPlanner {
    /// Absorbs floating-point noise in measured heights, far below a pixel: a stack measured a
    /// hair over the cap stays one column, and a near-tie between splits doesn't flip.
    public static let heightTolerance: Double = 0.001

    /// KTD2 / R6: only a new open (or layout preference) generation or a changed item order
    /// replans. Heights never do, matching `FlowingColumnsPlanner.replanReason`.
    public static func needsReplan(previous: AccountColumnsPlan?, itemIDs: [String], generation: Int) -> Bool {
        guard let previous else { return true }
        return previous.generation != generation || previous.itemIDs != itemIDs
    }

    public static func plan(
        items: [AccountColumnsItem],
        cap: Double,
        generation: Int,
        previous: AccountColumnsPlan?,
        metrics: AccountColumnsMetrics = .popover
    ) -> AccountColumnsPlan {
        let ids = items.map(\.id)
        if let previous, !needsReplan(previous: previous, itemIDs: ids, generation: generation) {
            return previous
        }
        let single = singleColumnHeight(items: items, metrics: metrics)
        // KTD2 hysteresis: once two columns, stay two until the single stack clears the cap by
        // one account row, so heights hovering at the cap don't alternate across opens.
        let allowance = previous?.columnCount == 2
            ? items.lazy.filter { !$0.isSpend }.map { max($0.height, 0) }.max() ?? 0
            : 0
        let lastSplit = splitCeiling(items)
        guard lastSplit >= 1, single > cap - allowance + heightTolerance else {
            return AccountColumnsPlan(columnCount: 1, splitIndex: items.count, itemIDs: ids, generation: generation)
        }
        return AccountColumnsPlan(
            columnCount: 2,
            splitIndex: bestSplit(items: items, through: lastSplit, metrics: metrics),
            itemIDs: ids,
            generation: generation
        )
    }

    /// Lays out the current heights under the kept split. If the item IDs no longer match the
    /// plan (the caller placed before replanning), everything goes in one column rather than
    /// splitting at an index that now means a different item.
    public static func placement(
        of plan: AccountColumnsPlan,
        items: [AccountColumnsItem],
        metrics: AccountColumnsMetrics = .popover
    ) -> AccountColumnsPlacement {
        let matches = plan.itemIDs == items.map(\.id) && plan.columnCount == 2
            && (1..<items.count).contains(plan.splitIndex)
        let ranges = matches ? [0..<plan.splitIndex, plan.splitIndex..<items.count] : [0..<items.count]
        var fragments: [AccountColumnsFragment] = []
        var heights: [Double] = []
        for (column, range) in ranges.enumerated() {
            var bottom = 0.0
            for run in runs(items, in: range) {
                let y = run.lowerBound == range.lowerBound ? 0 : bottom + metrics.cardGap
                let height = fragmentHeight(items, run, metrics)
                fragments.append(AccountColumnsFragment(
                    groupID: items[run.lowerBound].groupID,
                    itemRange: run,
                    isFirstFragmentOfGroup: startsCard(items, at: run.lowerBound),
                    column: column,
                    y: y,
                    height: height
                ))
                bottom = y + height
            }
            heights.append(bottom)
        }
        return AccountColumnsPlacement(fragments: fragments, columnHeights: heights)
    }

    /// R6: what to draw for `items` while the replan waits on heights the popover hasn't
    /// measured yet (a new account has no height until it is drawn). Two columns stay two, with
    /// column 1 starting at the first item that was already there; one column, no plan, or a
    /// column 1 that lost every item draws as one column. Draw from it, never store it: it
    /// carries the old generation under new IDs, so it would pass for an already-made plan.
    public static func carried(_ plan: AccountColumnsPlan?, to items: [AccountColumnsItem]) -> AccountColumnsPlan {
        let ids = items.map(\.id)
        let single = AccountColumnsPlan(
            columnCount: 1, splitIndex: ids.count, itemIDs: ids, generation: plan?.generation ?? 0
        )
        guard let plan, plan.columnCount == 2 else { return single }
        if plan.itemIDs == ids { return plan }
        let secondColumn = Set(plan.itemIDs[min(plan.splitIndex, plan.itemIDs.count)...])
        guard let head = ids.firstIndex(where: secondColumn.contains) else { return single }
        let split = min(head, splitCeiling(items))
        guard split >= 1 else { return single }
        return AccountColumnsPlan(columnCount: 2, splitIndex: split, itemIDs: ids, generation: plan.generation)
    }

    /// The height today's one-column `VStack(spacing: 20)` of cards would measure.
    public static func singleColumnHeight(
        items: [AccountColumnsItem],
        metrics: AccountColumnsMetrics = .popover
    ) -> Double {
        columnHeight(items, 0..<items.count, metrics)
    }

    // MARK: - Partition

    /// The largest split that keeps every spend item in column 1 (R5). Spend is expected last,
    /// so this is normally `items.count - 1`.
    private static func splitCeiling(_ items: [AccountColumnsItem]) -> Int {
        min(items.count - 1, items.firstIndex(where: \.isSpend) ?? items.count)
    }

    /// The split that minimises the taller column. Ties (within `heightTolerance`) go to the
    /// larger split, putting more content in column 0 so the flow reads down then across.
    /// Scanning from the largest split and replacing only on a clear improvement gives that.
    private static func bestSplit(items: [AccountColumnsItem], through last: Int,
                                  metrics: AccountColumnsMetrics) -> Int {
        var best = last
        var bestHeight = Double.infinity
        for split in stride(from: last, through: 1, by: -1) {
            let taller = max(
                columnHeight(items, 0..<split, metrics),
                columnHeight(items, split..<items.count, metrics)
            )
            if taller < bestHeight - heightTolerance {
                best = split
                bestHeight = taller
            }
        }
        return best
    }

    // MARK: - Height model (KTD1)

    private static func columnHeight(_ items: [AccountColumnsItem], _ range: Range<Int>,
                                     _ metrics: AccountColumnsMetrics) -> Double {
        let cards = runs(items, in: range)
        guard !cards.isEmpty else { return 0 }
        return cards.reduce(0) { $0 + fragmentHeight(items, $1, metrics) }
            + Double(cards.count - 1) * metrics.cardGap
    }

    private static func fragmentHeight(_ items: [AccountColumnsItem], _ run: Range<Int>,
                                       _ metrics: AccountColumnsMetrics) -> Double {
        2 * metrics.cardPadding
            + items[run].reduce(0) { $0 + max($1.height, 0) }
            + Double(run.count - 1) * metrics.accountGap
    }

    /// Contiguous same-card runs inside `range`. A column edge always ends a run, which is how
    /// a split card gets its own padding and loses the account gap at the cut.
    private static func runs(_ items: [AccountColumnsItem], in range: Range<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        for index in range where index > range.lowerBound && startsCard(items, at: index) {
            result.append(start..<index)
            start = index
        }
        if !range.isEmpty { result.append(start..<range.upperBound) }
        return result
    }

    /// True where a new card begins in the full flow: a provider change, or either side of the
    /// spend card, which is always its own card.
    private static func startsCard(_ items: [AccountColumnsItem], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let item = items[index], prior = items[index - 1]
        return item.groupID != prior.groupID || item.isSpend || prior.isSpend
    }
}
