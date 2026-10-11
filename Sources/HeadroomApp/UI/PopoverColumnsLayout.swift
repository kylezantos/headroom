import SwiftUI
import HeadroomCore

/// KTD3: places the popover's card fragments into the columns `PopoverPlanModel` resolved.
/// Which column a fragment reads in is the plan's decision, carried on each subview as
/// `PopoverColumn`; this layout only stacks each column at the card width. One column is
/// exactly today's `VStack(spacing: 20)`, so the container is never swapped (KTD3).
struct PopoverColumnsLayout: Layout {
    var columnCount: Int
    var metrics: AccountColumnsMetrics = .popover

    /// Every card is measured at the one card width whatever the proposal, so one stacking
    /// serves the whole pass; SwiftUI rebuilds the cache when the subviews change.
    struct Cache {
        var columns: [Column]?
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let columns = stacked(subviews, cache: &cache)
        return CGSize(
            width: metrics.gridWidth(columns: columnCount),
            height: columns.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let card = ProposedViewSize(width: metrics.columnWidth, height: nil)
        for column in stacked(subviews, cache: &cache) {
            for (index, y) in column.tops {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + metrics.columnX(column.index), y: bounds.minY + y),
                    anchor: .topLeading,
                    proposal: card
                )
            }
        }
    }

    private func stacked(_ subviews: Subviews, cache: inout Cache) -> [Column] {
        if let columns = cache.columns { return columns }
        let columns = stack(subviews)
        cache.columns = columns
        return columns
    }

    struct Column {
        let index: Int
        var tops: [(Int, CGFloat)] = []
        var height: CGFloat = 0
    }

    /// Each column top to bottom, 20pt between cards. A subview with no height (the spend card
    /// when no API surface is on) takes no gap.
    private func stack(_ subviews: Subviews) -> [Column] {
        let count = max(columnCount, 1)
        var columns = (0..<count).map { Column(index: $0) }
        let card = ProposedViewSize(width: metrics.columnWidth, height: nil)
        for (index, subview) in subviews.enumerated() {
            let height = subview.sizeThatFits(card).height
            guard height > 0 else { continue }
            let column = min(max(subview[PopoverColumn.self], 0), count - 1)
            let y = columns[column].tops.isEmpty ? 0 : columns[column].height + metrics.cardGap
            columns[column].tops.append((index, y))
            columns[column].height = y + height
        }
        return columns
    }
}

struct PopoverColumn: LayoutValueKey {
    static let defaultValue = 0
}

/// KTD3 / KTD10: a provider card's account stack — a leading-aligned `VStack` — that reports
/// each account's height to the popover's plan as it places it. The sizes are ones layout
/// already computed, so measuring costs nothing extra; a geometry reader on every account cost
/// about 90ms per open at the 20-account envelope.
struct ColumnItemsStack: Layout {
    var spacing: CGFloat
    var report: ((String, CGFloat) -> Void)?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        guard !sizes.isEmpty else { return .zero }
        return CGSize(
            width: proposal.width ?? sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).reduce(0, +) + spacing * CGFloat(sizes.count - 1)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(width).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: width)
            if let report, let id = subview[ColumnItemID.self] { report(id, height) }
            y += height + spacing
        }
    }
}

struct ColumnItemID: LayoutValueKey {
    static let defaultValue: String? = nil
}
