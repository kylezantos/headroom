import Foundation

/// What a widget window is, for ordering and shedding (2026-10-02 widget-styles plan, KTD10).
public enum WidgetWindowRole: Sendable, Equatable {
    case fiveHour
    case weekly
    /// A billing-period pool (Grok's weekly pool, Cursor's two monthly pools).
    case pool
    /// A model-specific sub-limit such as Claude's "Weekly (Fable)".
    case model
    /// Codex's optional Spark counter.
    case spark
}

public extension WidgetWindowSummary {
    var widgetRole: WidgetWindowRole {
        if isBillingPeriod { return .pool }
        switch kind {
        case .fiveHour: return .fiveHour
        case .weekly: return .weekly
        case .other:
            return label.localizedCaseInsensitiveContains("spark") ? .spark : .model
        }
    }

    /// R11: an unavailable window has no number to show, and must never look like 0%.
    var hasDisplayValue: Bool { displayPercentRemaining != nil }
}

/// KTD4: the one window ranking every widget style uses.
///
/// Lowest displayed value first. Stale windows rank by their value alongside live ones —
/// Claude's model rows are the ones most often retained as stale, and ranking live-first would
/// hide a tighter limit behind a looser live one (Key Decisions, 2026-10-02). Unavailable
/// windows have no displayed value, so they rank last and never headline while another window
/// has a number. Ties keep source order.
public enum WidgetWindowRanking {
    public static func ranked(_ windows: [WidgetWindowSummary]) -> [WidgetWindowSummary] {
        windows.enumerated().sorted { lhs, rhs in
            switch (lhs.element.displayPercentRemaining, rhs.element.displayPercentRemaining) {
            case let (l?, r?):
                return l == r ? lhs.offset < rhs.offset : l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    public static func tightest(_ windows: [WidgetWindowSummary]) -> WidgetWindowSummary? {
        ranked(windows).first
    }

    /// The popover's row order since #141: the 5-hour window, then the period window(s) —
    /// weekly or billing pools — then model rows, then Spark. Stable within a rank.
    public static func displayOrder(_ windows: [WidgetWindowSummary]) -> [WidgetWindowSummary] {
        func rank(_ window: WidgetWindowSummary) -> Int {
            switch window.widgetRole {
            case .fiveHour: 0
            case .weekly, .pool: 1
            case .model: 2
            case .spark: 3
            }
        }
        return windows.enumerated().sorted { lhs, rhs in
            (rank(lhs.element), lhs.offset) < (rank(rhs.element), rhs.offset)
        }.map(\.element)
    }
}
