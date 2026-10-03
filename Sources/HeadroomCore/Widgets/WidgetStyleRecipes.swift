import Foundation

/// KTD3 (2026-10-02 widget-styles plan): one provider as a widget style draws it. Pure data —
/// the shared SwiftUI style bodies only lay this out.
public struct WidgetStyleProviderRecipe: Sendable, Equatable, Identifiable {
    public let summary: WidgetProviderSummary
    /// R2/KTD4: weekly, else the tightest billing pool (unavailable pools rank last).
    public let primary: WidgetWindowSummary?
    /// R3: this provider's lowest displayed window, whatever its kind.
    public let tightest: WidgetWindowSummary?
    /// Every window, in the popover's order (#141).
    public let windows: [WidgetWindowSummary]
    /// Every window except `primary`, in the popover's order.
    public let secondary: [WidgetWindowSummary]
    /// Cursor-style: two or more billing pools and no weekly window. The pools are siblings,
    /// not nested, so Nested Meter draws them as equal bars.
    public let hasSiblingPools: Bool
    /// KTD10 for Nested Meter, Vessel Hero and Liquid Level: `secondary` from fullest to most
    /// shed. Spark rows go first, then model rows; subscription windows never drop.
    public let secondaryLadder: [[WidgetWindowSummary]]

    public var id: String { summary.id }
    /// A provider Headroom has not read yet (R11): no meter values, a waiting caption.
    public var isWaiting: Bool { summary.freshness == .pending && windows.isEmpty }
    /// R6: whether this provider has any number to show.
    public var hasDisplayValue: Bool { windows.contains(where: \.hasDisplayValue) }

    public init(summary: WidgetProviderSummary) {
        self.summary = summary
        let ordered = WidgetWindowRanking.displayOrder(summary.windows)
        let primary = summary.primarySubscriptionWindow ?? WidgetWindowRanking.tightest(ordered)
        self.primary = primary
        self.tightest = WidgetWindowRanking.tightest(ordered)
        self.windows = ordered
        let secondary = ordered.filter { $0 != primary }
        self.secondary = secondary
        self.hasSiblingPools = summary.weeklyWindow == nil
            && summary.windows.filter(\.isBillingPeriod).count > 1
        self.secondaryLadder = Self.ladder(secondary)
    }

    private static func ladder(_ rows: [WidgetWindowSummary]) -> [[WidgetWindowSummary]] {
        var rungs = [rows]
        let withoutSpark = rows.filter { $0.widgetRole != .spark }
        if withoutSpark != rungs.last { rungs.append(withoutSpark) }
        let withoutModels = withoutSpark.filter { $0.widgetRole != .model }
        if withoutModels != rungs.last { rungs.append(withoutModels) }
        return rungs
    }
}

/// One row of Tightest First's large list.
public struct WidgetRankedRow: Sendable, Equatable, Identifiable {
    public let providerID: String
    public let providerName: String
    public let window: WidgetWindowSummary
    public var id: String { "\(providerID)|\(window.id)" }
}

/// KTD9: one column of Liquid Level's full-bleed wash.
public struct WidgetWashSegment: Sendable, Equatable, Identifiable {
    public let providerID: String
    public let window: WidgetWindowSummary?
    /// The level, 0…1. Nil when the provider's primary window has no displayed value — no
    /// wash is drawn, so unavailable never looks like empty (R11).
    public let fraction: Double?
    public var id: String { providerID }
}

/// KTD3: everything a widget style decides for one family, from the envelope alone.
public struct WidgetStyleRecipe: Sendable, Equatable {
    public let style: WidgetLayoutStyle
    public let family: WidgetFamily
    public let providers: [WidgetStyleProviderRecipe]
    /// R3: Tightest First large — every shown window across providers, ranked (KTD4). The
    /// first row is the headline. Empty for the other styles and families.
    public let rankedRows: [WidgetRankedRow]
    /// KTD10 for Tightest First large: `rankedRows` shed from the loosest end, down to the
    /// headline alone, so the tightest limits always survive.
    public let rankedRowsLadder: [[WidgetRankedRow]]
    /// KTD9: Liquid Level's wash, one segment per shown provider. Empty for other styles.
    public let washSegments: [WidgetWashSegment]
    /// R14: the API spend strip and the "Updated N ago" footer are large-only.
    public let showsSpend: Bool
    public let showsFooter: Bool

    public var showsWashDivider: Bool { washSegments.count > 1 }

    public init(style: WidgetLayoutStyle, family: WidgetFamily, envelope: WidgetSnapshotEnvelope) {
        self.style = style
        self.family = family
        var shown = envelope.widgetProviders.map(WidgetStyleProviderRecipe.init(summary:))
        // R6: small Vessel Hero and small Liquid Level have room for one provider. Take the
        // first, unless it has nothing to show yet and the second does.
        if family == .small, style == .vesselHero || style == .liquidLevel, let first = shown.first {
            let pick = first.hasDisplayValue ? first : shown.first(where: \.hasDisplayValue) ?? first
            shown = [pick]
        }
        providers = shown

        if style == .tightestFirst, family == .large {
            let all = shown.flatMap { provider in
                provider.windows.map {
                    (row: WidgetRankedRow(providerID: provider.id, providerName: provider.summary.displayName, window: $0), window: $0)
                }
            }
            let rankedWindows = WidgetWindowRanking.ranked(all.map(\.window))
            var remaining = all
            var rows: [WidgetRankedRow] = []
            for window in rankedWindows {
                guard let index = remaining.firstIndex(where: { $0.window == window }) else { continue }
                rows.append(remaining.remove(at: index).row)
            }
            rankedRows = rows
            rankedRowsLadder = rows.isEmpty ? [] : (1...rows.count).reversed().map { Array(rows.prefix($0)) }
        } else {
            rankedRows = []
            rankedRowsLadder = []
        }

        washSegments = style == .liquidLevel
            ? shown.map { provider in
                WidgetWashSegment(
                    providerID: provider.id,
                    window: provider.primary,
                    fraction: provider.primary?.displayPercentRemaining.map { min(1, max(0, $0 / 100)) }
                )
            }
            : []

        showsSpend = family == .large && !envelope.apiSpendProviders.isEmpty
        showsFooter = family == .large
    }
}

/// Strings the widget styles share. Display only; nothing here touches the wire format.
public enum WidgetStyleCopy {
    /// The caption under a hero numeral: "weekly left", "monthly left", or — when a provider
    /// bills several sibling pools, or the hero is a 5-hour or model window — the window's own
    /// name ("Other Models left", "5-hour left"), so the number is never captioned with a
    /// period it does not belong to.
    public static func leftCaption(for window: WidgetWindowSummary, in provider: WidgetStyleProviderRecipe) -> String {
        switch window.widgetRole {
        case .weekly:
            return "weekly left"
        case .pool:
            if provider.hasSiblingPools { return "\(window.widgetDisplayLabel) left" }
            let duration = window.billingPeriodDuration ?? 0
            return duration >= 28 * 86_400 ? "monthly left" : "weekly left"
        case .fiveHour, .model, .spark:
            return "\(window.widgetDisplayLabel) left"
        }
    }

    /// R11: a provider Headroom has not read yet.
    public static let waiting = "Waiting for first reading"
    /// Tightest First's small caption and large heading.
    public static let tightestSmallHeading = "Tightest limit"
    public static let tightestLargeHeading = "Tightest first"
}
