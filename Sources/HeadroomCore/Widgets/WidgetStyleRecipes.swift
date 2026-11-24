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
    /// The window a style shows beside the primary one: the 5-hour window when there is one,
    /// else the next window in popover order (Vessel Hero's second line, Liquid Level's detail).
    public var companion: WidgetWindowSummary? {
        secondary.first { $0.widgetRole == .fiveHour } ?? secondary.first
    }
    /// A provider Headroom has not read yet (R11): no meter values, a waiting caption.
    public var isWaiting: Bool { summary.freshness == .pending && windows.isEmpty }
    /// KTD15: a placeholder carries neutral decorative ink, never a usage value.
    public var waitingPill: LoadingPillState? {
        guard isWaiting else { return nil }
        return LoadingPillState(id: "waiting-\(id)", level: LoadingMotionConstants.decorativeLevel, ink: .ghost)
    }
    /// R6: whether this provider has any number to show.
    public var hasDisplayValue: Bool { windows.contains(where: \.hasDisplayValue) }
    /// WCM5-v: the provider's on-wire stale reason, trimmed — the line large prints beside the
    /// name. Nil when live, pending, or the reason is blank.
    public var staleMessage: String? {
        guard case .stale(let message, _) = summary.freshness else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// KTD10: the secondary rows at one rung of `secondaryLadder`. A provider whose ladder is
    /// shorter than the widget's rung count stays on its last rung.
    public func secondary(atRung rung: Int) -> [WidgetWindowSummary] {
        guard !secondaryLadder.isEmpty else { return [] }
        return secondaryLadder[min(max(rung, 0), secondaryLadder.count - 1)]
    }

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

/// KTD3 (2026-10-04 Lock Screen plan): home and Lock Screen use the same value-aware
/// single-provider pick and stable cross-provider ranking, with each caller owning its scope.
public enum WidgetProviderSelection {
    public static func singleProvider(from providers: [WidgetStyleProviderRecipe]) -> WidgetStyleProviderRecipe? {
        guard let first = providers.first else { return nil }
        return first.hasDisplayValue ? first : providers.first(where: \.hasDisplayValue) ?? first
    }

    public static func rankedRows(from providers: [WidgetStyleProviderRecipe]) -> [WidgetRankedRow] {
        let all = providers.flatMap { provider in
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
        return rows
    }
}

/// CA-W1: what a Liquid Level column lays out over its wash, as the recipe already knows it.
/// The wash is drawn in a layer of its own (KTD9), so it cannot measure the type above it;
/// it resolves these into text bands with the tile height and Dynamic Type factor it has.
public struct WidgetWashColumnLayout: Sendable, Equatable {
    public let family: WidgetFamily
    /// The hero numeral's point size (`WidgetStyleType.heroNumeral`).
    public let heroNumeral: Double
    /// A provider not read yet draws the one-line waiting caption instead of a hero.
    public let isWaiting: Bool
    /// Caption lines under the hero: one, or two when large adds the countdown.
    public let heroCaptionLines: Int
    /// Large's secondary rows at the fullest rung, bottom-aligned above the tail.
    public let secondaryRows: Int
    /// Large's tail: the footer stamp, or the spend strip in its place.
    public let showsFooter: Bool
    public let showsSpend: Bool
    /// "Reset at <time>" lines: in large's tail, under the column elsewhere.
    public let pastResetNoteLines: Int
    /// The dimmed sentence at the foot of every family.
    public let isDimmed: Bool

    public init(
        family: WidgetFamily, heroNumeral: Double, isWaiting: Bool = false, heroCaptionLines: Int = 1,
        secondaryRows: Int = 0, showsFooter: Bool = false, showsSpend: Bool = false,
        pastResetNoteLines: Int = 0, isDimmed: Bool = false
    ) {
        self.family = family
        self.heroNumeral = heroNumeral
        self.isWaiting = isWaiting
        self.heroCaptionLines = heroCaptionLines
        self.secondaryRows = secondaryRows
        self.showsFooter = showsFooter
        self.showsSpend = showsSpend
        self.pastResetNoteLines = pastResetNoteLines
        self.isDimmed = isDimmed
    }

    /// Every block of type in the column, as offsets from the content edge it hangs from.
    /// Captions grow with `typeUnit`; numerals, marks and spacing stay in points (KTD8). The
    /// numeral's band starts at its cap top: the empty line space above it is not ink.
    public func textBands(typeUnit: Double) -> [WidgetWashTextBand] {
        let scale = WidgetTypeScale.scale(for: family)
        func line(_ size: Double) -> Double { WidgetTextMetrics.lineHeight(size) * typeUnit }
        func lines(_ count: Int, _ size: Double, gap: Double) -> Double {
            count > 0 ? Double(count) * line(size) + Double(count - 1) * gap : 0
        }
        let identity = max(WidgetMetrics.markSlot(for: family), line(scale.name))
        let numeralLine = WidgetTextMetrics.lineHeight(heroNumeral)
        let numeralCapTop = WidgetTextMetrics.capTop(heroNumeral)
        let waitingLine = max(WidgetStyleMetrics.waitingMarkHeight, line(scale.countdown))
        let heroCaptions = lines(heroCaptionLines, scale.countdown, gap: WidgetStyleMetrics.liquidCaptionLineGap)
        let freshnessGap = WidgetStyleMetrics.freshnessLineGap

        var bands = [WidgetWashTextBand(edge: .top, near: 0, far: identity)]
        // The foot of the content box, upward: the dimmed sentence, then (outside large) the
        // reset notes, each a freshness gap above the last.
        var foot = 0.0
        if isDimmed { foot += line(scale.footer) + freshnessGap }

        if family == .large {
            let heroTop = identity + WidgetStyleMetrics.liquidLargeHeroTop
            bands.append(isWaiting
                ? WidgetWashTextBand(edge: .top, near: heroTop, far: heroTop + waitingLine)
                : WidgetWashTextBand(edge: .top, near: heroTop + numeralCapTop,
                                     far: heroTop + numeralLine + WidgetStyleMetrics.liquidHeroCaptionGap + heroCaptions))
            var tail = 0.0
            if showsSpend {
                tail += WidgetStyleMetrics.spendStripRule + line(scale.spendAmount)
            } else if showsFooter {
                tail += line(scale.footer)
            }
            if pastResetNoteLines > 0 {
                tail += lines(pastResetNoteLines, scale.countdown, gap: WidgetStyleMetrics.liquidCaptionLineGap)
                    + WidgetStyleMetrics.pastResetNoteGap
            }
            let rows = Double(secondaryRows) * WidgetStyleMetrics.liquidLargeRowHeight
            let top = foot + tail + (rows > 0 ? WidgetStyleMetrics.liquidTailGap + rows : 0)
            if top > 0 { bands.append(WidgetWashTextBand(edge: .bottom, near: 0, far: top)) }
        } else {
            if pastResetNoteLines > 0 {
                foot += lines(pastResetNoteLines, scale.countdown, gap: WidgetStyleMetrics.liquidCaptionLineGap) + freshnessGap
            }
            let hero = isWaiting
                ? waitingLine
                : heroCaptions + WidgetStyleMetrics.liquidHeroCaptionGap + numeralLine - numeralCapTop
            bands.append(WidgetWashTextBand(edge: .bottom, near: 0, far: foot + hero))
        }
        return bands
    }
}

/// CA-W1: one block of type in a Liquid Level column, as offsets in points from the content
/// edge it hangs from: `near` is the block's edge closest to that content edge, `far` the
/// other, so a top band reads downward and a bottom band upward.
public struct WidgetWashTextBand: Sendable, Equatable {
    public enum Edge: Sendable, Equatable { case top, bottom }

    public let edge: Edge
    public let near: Double
    public let far: Double

    public init(edge: Edge, near: Double, far: Double) {
        self.edge = edge
        self.near = near
        self.far = far
    }

    /// The band in tile points from the tile's top, widened by the clearance and taken across
    /// every content inset a host may use (`WidgetStyleMetrics.washContentInset`).
    public func span(tileHeight: Double) -> ClosedRange<Double> {
        let inset = WidgetStyleMetrics.washContentInset
        let clearance = WidgetStyleMetrics.washEdgeTextClearance
        switch edge {
        case .top:
            return (inset.lowerBound + near - clearance)...(inset.upperBound + far + clearance)
        case .bottom:
            return (tileHeight - inset.upperBound - far - clearance)...(tileHeight - inset.lowerBound - near + clearance)
        }
    }
}

/// KTD9: one column of Liquid Level's full-bleed wash.
public struct WidgetWashSegment: Sendable, Equatable, Identifiable {
    public let providerID: String
    public let window: WidgetWindowSummary?
    /// The level, 0…1. Nil when the provider's primary window has no displayed value — no
    /// wash is drawn, so unavailable never looks like empty (R11).
    public let fraction: Double?
    /// CA-W1: the type the column lays out over this wash. Nil draws the edge everywhere.
    public let layout: WidgetWashColumnLayout?
    public var id: String { providerID }

    public init(providerID: String, window: WidgetWindowSummary?, fraction: Double?, layout: WidgetWashColumnLayout? = nil) {
        self.providerID = providerID
        self.window = window
        self.fraction = fraction
        self.layout = layout
    }

    /// CA-W1 (option A): the bright surface edge is drawn only where it crosses no text band.
    /// A 1.5pt rule through "38%" reads as a strike-through, so across a band the gradient
    /// body alone shows the level, and the wash itself is unchanged. `tileHeight` is the
    /// full-bleed column's height; `typeUnit` the Dynamic Type factor the captions are set at.
    public func showsEdge(tileHeight: Double, typeUnit: Double) -> Bool {
        guard let fraction, fraction > 0 else { return false }
        guard let layout else { return true }
        let edge = WidgetStyleMetrics.washEdgeWidth
        // The same arithmetic as the wash: the liquid is never thinner than its edge.
        let top = tileHeight - max(edge, tileHeight * fraction)
        let bottom = top + edge
        return !layout.textBands(typeUnit: typeUnit).contains { band in
            let span = band.span(tileHeight: tileHeight)
            return top < span.upperBound && bottom > span.lowerBound
        }
    }
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
    /// R11 for Tightest First large: the shown providers with no window to rank (pending, or
    /// stale with nothing retained), in provider order, so the list never drops them. Empty for
    /// the other styles and families.
    public let providersWithoutRows: [WidgetStyleProviderRecipe]
    /// KTD9: Liquid Level's wash, one segment per shown provider. Empty for other styles.
    public let washSegments: [WidgetWashSegment]
    /// R14: the API spend strip and the "Updated N ago" footer are large-only.
    public let showsSpend: Bool
    public let showsFooter: Bool
    /// U13 (KTD15): the freshness rules applied to every window above. While dimmed, the
    /// dimmed sentence takes the place of the footer and the spend strip.
    public let freshness: WidgetFreshnessTreatment
    /// R11: one "Reset at <time>" note per shown provider with a window past its reset.
    public let pastResetNotes: [WidgetPastResetNote]

    public var showsWashDivider: Bool { washSegments.count > 1 }
    /// KTD10: how many shedding rungs the widget tries — the longest provider ladder, at least
    /// one. Pair with `WidgetStyleProviderRecipe.secondary(atRung:)`.
    public var ladderRungCount: Int { max(1, providers.map(\.secondaryLadder.count).max() ?? 1) }

    public init(
        style: WidgetLayoutStyle, family: WidgetFamily, envelope source: WidgetSnapshotEnvelope,
        freshness: WidgetFreshnessTreatment = .none
    ) {
        // U13: every decision below reads the windows after the KTD15 rules, so past-reset
        // and dimmed windows rank, fill and wash through the existing unavailable and stale paths.
        let envelope = freshness.applied(to: source)
        self.style = style
        self.family = family
        var shown = envelope.widgetProviders.map(WidgetStyleProviderRecipe.init(summary:))
        // R6: small Vessel Hero and small Liquid Level have room for one provider. Take the
        // first, unless it has nothing to show yet and the second does.
        if family == .small, style == .vesselHero || style == .liquidLevel,
           let pick = WidgetProviderSelection.singleProvider(from: shown) {
            shown = [pick]
        }
        providers = shown

        if style == .tightestFirst, family == .large {
            let rows = WidgetProviderSelection.rankedRows(from: shown)
            rankedRows = rows
            rankedRowsLadder = rows.isEmpty ? [] : (1...rows.count).reversed().map { Array(rows.prefix($0)) }
            providersWithoutRows = shown.filter(\.windows.isEmpty)
        } else {
            rankedRows = []
            rankedRowsLadder = []
            providersWithoutRows = []
        }

        // U13: while dimmed, the dimmed sentence takes the footer's place and the spend strip
        // yields to it — its amounts are as old as the meters, and KTD10 sheds spend first.
        let showsSpend = family == .large && !envelope.apiSpendProviders.isEmpty && !freshness.isDimmed
        let showsFooter = family == .large && !freshness.isDimmed
        self.showsSpend = showsSpend
        self.showsFooter = showsFooter
        self.freshness = freshness
        let pastResetNotes = shown.compactMap { recipe in
            source.providers.first { $0.id == recipe.id }
                .flatMap { freshness.pastResetNote(for: $0, namesProvider: shown.count > 1) }
        }
        self.pastResetNotes = pastResetNotes

        washSegments = style == .liquidLevel
            ? shown.map { provider in
                // WCM5: a stale provider's wash takes the stale fill, as its rows do.
                WidgetWashSegment(
                    providerID: provider.id,
                    window: provider.summary.freshness == .live ? provider.primary : provider.primary?.demotedToStale(),
                    fraction: provider.primary?.displayPercentRemaining.map { min(1, max(0, $0 / 100)) },
                    // CA-W1: the column's type, at its fullest rung (a shed row only frees room),
                    // so the edge is dropped wherever any rung could put text.
                    layout: WidgetWashColumnLayout(
                        family: family,
                        heroNumeral: WidgetStyleType.heroNumeral(style: style, family: family, providerCount: family == .small ? 1 : shown.count),
                        isWaiting: provider.isWaiting,
                        heroCaptionLines: family == .large && provider.primary.map(Self.printsCountdown) == true ? 2 : 1,
                        secondaryRows: family == .large ? provider.secondary(atRung: 0).count : 0,
                        showsFooter: showsFooter,
                        showsSpend: showsSpend,
                        pastResetNoteLines: pastResetNotes.count,
                        isDimmed: freshness.isDimmed
                    )
                )
            }
            : []
    }

    /// Whether a window prints a countdown under the hero (`WidgetWindowText.countdown`).
    private static func printsCountdown(_ window: WidgetWindowSummary) -> Bool {
        !window.freshness.isUnavailable && window.resetSchedule.deadline != nil
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

    /// "Resets in 3h 15m" — or "Resets now" at the reset itself, as the popover's tooltip says.
    public static func resetsIn(_ countdown: String) -> String {
        countdown == "now" ? "Resets now" : "Resets in \(countdown)"
    }

    /// R11: a provider Headroom has not read yet.
    public static let waiting = "Waiting for first reading"
    /// Tightest First's small caption and large heading.
    public static let tightestSmallHeading = "Tightest limit"
    public static let tightestLargeHeading = "Tightest first"
}
