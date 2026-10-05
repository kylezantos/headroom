import Foundation

// KTD17 / R24: the iPad (and iPhone landscape) usage screen flows provider cards into columns.
// This file is the pure decision — how many columns, how wide, where the grid sits, and which
// column each card lives in. `FlowingColumnsLayout` in HeadroomSharedUI only places subviews
// from it, so the rules are testable without SwiftUI.
//
// Kept to Foundation and plain `Double`s because both iOS targets compile `Models/` whole (KTD4).

/// The grid's fixed measurements. Card widths take the Dynamic Type scale; margins and gaps don't.
public struct FlowingColumnsMetrics: Sendable, Equatable {
    /// Screen edge to the first and last column; the approved mock's 28pt (U8-A).
    public static let defaultMargin: Double = 28
    public static let defaultGap: Double = 20
    /// About 400pt at the default text size (KTD17): two columns at 1032pt, three at 1376pt, one
    /// at 834pt and 744pt.
    public static let defaultMinimumCardWidth: Double = 400
    /// Cards keep the phone's proportions rather than stretching (U8-A); past this the grid
    /// centers. 600 keeps the 11-inch landscape pair (559pt) uncapped and matches the width the
    /// options doc used for a single centered column.
    public static let defaultMaximumCardWidth: Double = 600

    public static let standard = FlowingColumnsMetrics(
        margin: defaultMargin,
        gap: defaultGap,
        minimumCardWidth: defaultMinimumCardWidth,
        maximumCardWidth: defaultMaximumCardWidth
    )

    public var margin: Double
    public var gap: Double
    public var minimumCardWidth: Double
    public var maximumCardWidth: Double

    public init(margin: Double, gap: Double, minimumCardWidth: Double, maximumCardWidth: Double) {
        self.margin = margin
        self.gap = gap
        self.minimumCardWidth = minimumCardWidth
        self.maximumCardWidth = maximumCardWidth
    }

    /// The same grid at a Dynamic Type scale factor. Only the card widths grow, because a card's
    /// text grows with the setting while the screen's margins don't.
    public func scaled(by factor: Double) -> FlowingColumnsMetrics {
        FlowingColumnsMetrics(
            margin: margin,
            gap: gap,
            minimumCardWidth: minimumCardWidth * factor,
            maximumCardWidth: maximumCardWidth * factor
        )
    }
}

/// How many columns fit and where they sit, from width alone. Cards are measured at
/// `columnWidth` before they are assigned, so this has to come first.
public struct FlowingColumnsGeometry: Sendable, Equatable {
    public let columnCount: Int
    public let columnWidth: Double
    /// Leading edge of the first column: the margin, or more once cards reach their maximum
    /// width and the grid centers.
    public let leadingInset: Double
    public let gap: Double

    public init(columnCount: Int, columnWidth: Double, leadingInset: Double, gap: Double) {
        self.columnCount = columnCount
        self.columnWidth = columnWidth
        self.leadingInset = leadingInset
        self.gap = gap
    }

    public var gridWidth: Double {
        Double(columnCount) * columnWidth + Double(max(columnCount - 1, 0)) * gap
    }

    public func columnX(_ column: Int) -> Double {
        leadingInset + Double(column) * (columnWidth + gap)
    }

    /// n columns fit when n·minimum + (n−1)·gap ≤ width − 2·margin; at least one always does,
    /// narrower than the minimum if it must, so nothing overflows the window. A grid never has
    /// more columns than cards: two providers in landscape center as a pair instead of leaving a
    /// third column empty.
    public static func resolve(
        availableWidth: Double,
        metrics: FlowingColumnsMetrics,
        cardCount: Int
    ) -> FlowingColumnsGeometry {
        // A non-finite width would trap converting the fit to `Int`; the layout resolves
        // unbounded proposals before calling this.
        let finiteWidth = availableWidth.isFinite ? availableWidth : 0
        let content = max(finiteWidth - 2 * metrics.margin, 0)
        let minimum = max(metrics.minimumCardWidth, 1)
        let maximum = max(metrics.maximumCardWidth, minimum)
        // The epsilon keeps an exact fit (876pt for two columns) from losing a column to
        // floating-point error.
        let fitting = Int(((content + metrics.gap) / (minimum + metrics.gap) + 1e-9).rounded(.down))
        let count = max(min(fitting, cardCount), 1)

        let natural = (content - Double(count - 1) * metrics.gap) / Double(count)
        let width = max(min(natural, maximum), 0)
        let grid = Double(count) * width + Double(count - 1) * metrics.gap
        return FlowingColumnsGeometry(
            columnCount: count,
            columnWidth: width,
            leadingInset: metrics.margin + max(content - grid, 0) / 2,
            gap: metrics.gap
        )
    }
}

/// One card as the planner sees it. The ID should change whenever the card's account set does
/// (for example provider plus account keys), so an added account re-plans (KTD17).
public struct FlowingColumnsCard<ID: Hashable & Sendable>: Sendable, Equatable {
    public let id: ID
    public let height: Double

    public init(id: ID, height: Double) {
        self.id = id
        self.height = height
    }
}

/// Why the planner threw away the previous assignment. `nil` from
/// `FlowingColumnsPlanner.replanReason` means the assignment is kept.
public enum FlowingColumnsReplanReason: Sendable, Equatable {
    case initial
    case width
    /// The Dynamic Type-scaled card widths (or the margin or gap) changed.
    case metrics
    /// A card was added, removed or reordered.
    case cards
}

/// Which column every card is in, plus the inputs that produced it. Heights are not part of its
/// identity: a kept plan places cards at their current heights in their original columns.
public struct FlowingColumnsPlan<ID: Hashable & Sendable>: Sendable, Equatable {
    public let availableWidth: Double
    public let metrics: FlowingColumnsMetrics
    /// Card order; also VoiceOver order.
    public let cardIDs: [ID]
    public let geometry: FlowingColumnsGeometry
    /// The column of each card, aligned with `cardIDs`.
    public let columnOfCard: [Int]
    /// Counts re-plans, so a caller (and the tests) can tell a kept plan from a new one.
    public let revision: Int

    public init(
        availableWidth: Double,
        metrics: FlowingColumnsMetrics,
        cardIDs: [ID],
        geometry: FlowingColumnsGeometry,
        columnOfCard: [Int],
        revision: Int
    ) {
        self.availableWidth = availableWidth
        self.metrics = metrics
        self.cardIDs = cardIDs
        self.geometry = geometry
        self.columnOfCard = columnOfCard
        self.revision = revision
    }

    /// Card IDs per column, top to bottom.
    public var columns: [[ID]] {
        var columns = Array(repeating: [ID](), count: geometry.columnCount)
        for (index, column) in columnOfCard.enumerated() {
            columns[column].append(cardIDs[index])
        }
        return columns
    }

    /// Frames for the cards at their current heights (aligned with `cardIDs`; a missing height
    /// counts as zero). Each column stacks its cards in card order, separated by the gap; the
    /// content is as tall as the tallest column.
    public func placement(heights: [Double]) -> FlowingColumnsPlacement {
        var bottoms = Array(repeating: 0.0, count: geometry.columnCount)
        var occupied = Array(repeating: false, count: geometry.columnCount)
        var frames: [FlowingColumnsPlacement.Frame] = []
        frames.reserveCapacity(columnOfCard.count)
        for (index, column) in columnOfCard.enumerated() {
            let height = heights.indices.contains(index) ? max(heights[index], 0) : 0
            let y = occupied[column] ? bottoms[column] + geometry.gap : 0
            frames.append(.init(x: geometry.columnX(column), y: y, width: geometry.columnWidth, height: height))
            bottoms[column] = y + height
            occupied[column] = true
        }
        return FlowingColumnsPlacement(frames: frames, contentHeight: bottoms.max() ?? 0)
    }
}

/// Card frames in the grid's coordinate space: x from the window's leading edge, y from the
/// grid's top.
public struct FlowingColumnsPlacement: Sendable, Equatable {
    public struct Frame: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Aligned with the plan's `cardIDs`.
    public let frames: [Frame]
    public let contentHeight: Double

    public init(frames: [Frame], contentHeight: Double) {
        self.frames = frames
        self.contentHeight = contentHeight
    }
}

/// Decides whether to keep the previous assignment or re-plan (KTD17). It re-plans only when
/// the width, the Dynamic Type-scaled metrics, or the ordered card IDs change. A capsule
/// opening or a receipt line appearing changes a height and keeps every card in its column, so
/// nothing jumps sideways while you read it. A text-size change arrives as new metrics plus
/// re-measured heights, so it re-plans and may change the column count at a fixed width.
public enum FlowingColumnsPlanner {
    /// Absorbs floating-point noise only. Any real resize re-plans (KTD17), and a kept plan's
    /// geometry must match the width it is placed in, so this stays far below a pixel.
    public static let widthTolerance: Double = 0.001

    public static func replanReason<ID>(
        previous: FlowingColumnsPlan<ID>?,
        availableWidth: Double,
        metrics: FlowingColumnsMetrics,
        cardIDs: [ID]
    ) -> FlowingColumnsReplanReason? {
        guard let previous else { return .initial }
        if previous.cardIDs != cardIDs { return .cards }
        if previous.metrics != metrics { return .metrics }
        if abs(previous.availableWidth - availableWidth) > widthTolerance { return .width }
        return nil
    }

    public static func plan<ID>(
        cards: [FlowingColumnsCard<ID>],
        availableWidth: Double,
        metrics: FlowingColumnsMetrics,
        previous: FlowingColumnsPlan<ID>?
    ) -> FlowingColumnsPlan<ID> {
        let ids = cards.map(\.id)
        if let previous,
           replanReason(previous: previous, availableWidth: availableWidth, metrics: metrics, cardIDs: ids) == nil {
            return previous
        }
        let geometry = FlowingColumnsGeometry.resolve(
            availableWidth: availableWidth, metrics: metrics, cardCount: cards.count
        )
        return FlowingColumnsPlan(
            availableWidth: availableWidth,
            metrics: metrics,
            cardIDs: ids,
            geometry: geometry,
            columnOfCard: assign(heights: cards.map(\.height), columnCount: geometry.columnCount, gap: geometry.gap),
            revision: (previous?.revision ?? -1) + 1
        )
    }

    /// Each card in order joins the column whose bottom is highest (leftmost on a tie). The
    /// first row fills left to right in card order, every column reads in card order, and the
    /// columns end as close to level as greedy allows.
    static func assign(heights: [Double], columnCount: Int, gap: Double) -> [Int] {
        var bottoms = Array(repeating: 0.0, count: max(columnCount, 1))
        var occupied = Array(repeating: false, count: bottoms.count)
        return heights.map { height in
            var shortest = 0
            for column in bottoms.indices where bottoms[column] < bottoms[shortest] {
                shortest = column
            }
            bottoms[shortest] += (occupied[shortest] ? gap : 0) + max(height, 0)
            occupied[shortest] = true
            return shortest
        }
    }
}
