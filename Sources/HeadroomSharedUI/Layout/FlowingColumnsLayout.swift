#if SWIFT_PACKAGE
import HeadroomCore
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

// KTD17 / R24: provider cards flow into columns that fill the width. Every decision — column
// count, width, centering, which column a card lives in and when that may change — is
// `FlowingColumnsPlanner` in Core; this file measures cards and places them from the plan.
// Placement is the layout's alone (no `.offset` handovers), so a re-plan is one change of
// placement that animates in whatever transaction caused it
// (docs/solutions/ui/swiftui-layout-owned-drag-position.md).

/// The flowing-columns container. Mark each card with `.flowingColumnsCard(id:)`:
///
/// ```swift
/// FlowingColumns {
///     ForEach(providers) { provider in
///         ProviderCard(provider).flowingColumnsCard(id: provider.columnsKey)
///     }
///     SpendCard().flowingColumnsCard(id: "spend")
/// }
/// ```
///
/// Card widths scale with Dynamic Type, so a larger text size can drop a column at a fixed
/// window width. VoiceOver reads cards in declaration (provider) order, not column by column.
public struct FlowingColumns<Content: View>: View {
    @ScaledMetric(relativeTo: .body) private var minimumCardWidth: CGFloat =
        FlowingColumnsMetrics.defaultMinimumCardWidth
    @ScaledMetric(relativeTo: .body) private var maximumCardWidth: CGFloat =
        FlowingColumnsMetrics.defaultMaximumCardWidth

    private let margin: CGFloat
    private let gap: CGFloat
    private let content: Content

    public init(
        margin: CGFloat = FlowingColumnsMetrics.defaultMargin,
        gap: CGFloat = FlowingColumnsMetrics.defaultGap,
        @ViewBuilder content: () -> Content
    ) {
        self.margin = margin
        self.gap = gap
        self.content = content()
    }

    private var metrics: FlowingColumnsMetrics {
        FlowingColumnsMetrics(
            margin: margin,
            gap: gap,
            minimumCardWidth: minimumCardWidth,
            maximumCardWidth: maximumCardWidth
        )
    }

    public var body: some View {
        Group(subviews: content) { cards in
            FlowingColumnsLayout(metrics: metrics) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    card
                        // Columns read top to bottom, so without this VoiceOver could follow
                        // the geometry and skip between providers (KTD17).
                        .accessibilitySortPriority(Double(cards.count - index))
                        .layoutValue(key: FlowingColumnsCardID.self, value: card.containerValues.flowingColumnsCardID)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// Names a card inside `FlowingColumns`. Make the ID change whenever the card's account set
    /// does (provider plus account keys, say): a new ID set re-plans the columns, while a height
    /// change alone keeps every card where it is (KTD17).
    public func flowingColumnsCard(id: String) -> some View {
        containerValue(\.flowingColumnsCardID, id)
    }
}

private struct FlowingColumnsCardIDContainerKey: ContainerValueKey {
    static let defaultValue: String? = nil
}

extension ContainerValues {
    fileprivate var flowingColumnsCardID: String? {
        get { self[FlowingColumnsCardIDContainerKey.self] }
        set { self[FlowingColumnsCardIDContainerKey.self] = newValue }
    }
}

/// A card's identity for `FlowingColumnsLayout` when the layout is used directly. Cards without
/// one are identified by position.
public struct FlowingColumnsCardID: LayoutValueKey {
    public static let defaultValue: String? = nil
}

/// Places cards from a `FlowingColumnsPlan`. The plan survives in the cache, so an ordinary
/// height change re-stacks each column without moving any card to another one.
public struct FlowingColumnsLayout: Layout {
    public var metrics: FlowingColumnsMetrics

    public init(metrics: FlowingColumnsMetrics = .standard) {
        self.metrics = metrics
    }

    public struct Cache {
        /// Only `placeSubviews` writes this: sizing probes at other widths (a parent asking for
        /// an ideal or maximum size) must not cost the real width its assignment.
        fileprivate var plan: FlowingColumnsPlan<String>?
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    /// The default rebuilds the cache, which would throw the plan away on every content
    /// change. The planner decides when the subviews' IDs warrant a new one.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = resolvedWidth(proposal.width, cardCount: subviews.count)
        let (plan, heights) = resolve(width: width, subviews: subviews, previous: cache.plan)
        return CGSize(width: width, height: plan.placement(heights: heights).contentHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let (plan, heights) = resolve(width: bounds.width, subviews: subviews, previous: cache.plan)
        cache.plan = plan
        let frames = plan.placement(heights: heights).frames
        for (index, subview) in subviews.enumerated() {
            let frame = frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.x, y: bounds.minY + frame.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// An unspecified width asks for the ideal size: one card at its minimum width. An infinite
    /// one asks for the most the grid can use: every card side by side at its maximum width.
    private func resolvedWidth(_ proposed: CGFloat?, cardCount: Int) -> CGFloat {
        guard let proposed else {
            return metrics.minimumCardWidth + 2 * metrics.margin
        }
        guard proposed.isFinite else {
            let count = Double(max(cardCount, 1))
            let card = max(metrics.maximumCardWidth, metrics.minimumCardWidth)
            return count * card + (count - 1) * metrics.gap + 2 * metrics.margin
        }
        return proposed
    }

    /// Cards are measured at the width they will be placed at, then planned. A text-size change
    /// arrives as new metrics with these fresh heights, so its re-plan uses the new sizes.
    private func resolve(
        width: CGFloat,
        subviews: Subviews,
        previous: FlowingColumnsPlan<String>?
    ) -> (FlowingColumnsPlan<String>, [Double]) {
        let geometry = FlowingColumnsGeometry.resolve(
            availableWidth: width, metrics: metrics, cardCount: subviews.count
        )
        let measure = ProposedViewSize(width: geometry.columnWidth, height: nil)
        let heights = subviews.map { Double($0.sizeThatFits(measure).height) }
        let cards = subviews.enumerated().map { index, subview in
            FlowingColumnsCard(id: subview[FlowingColumnsCardID.self] ?? "#\(index)", height: heights[index])
        }
        let plan = FlowingColumnsPlanner.plan(
            cards: cards, availableWidth: width, metrics: metrics, previous: previous
        )
        return (plan, heights)
    }
}

#if DEBUG && os(iOS)
#Preview("Flowing columns") {
    ScrollView {
        FlowingColumns {
            ForEach(Array([180.0, 260, 140, 220, 120].enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                    .frame(height: height)
                    .overlay(Text("Card \(index + 1)"))
                    .flowingColumnsCard(id: "card\(index)")
            }
        }
    }
}
#endif
