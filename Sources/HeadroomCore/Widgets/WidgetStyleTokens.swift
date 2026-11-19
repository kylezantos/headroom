import Foundation

/// KTD8 (2026-10-02 widget-styles plan): the numeral sizes the four widget styles add to the
/// `WidgetTypeScale` ladder. Hero numerals are fixed size — scaling a 42pt hero at xxLarge
/// overflows "100%" and drags Vessel Hero's vessel with it — while labels, captions and
/// countdowns keep the ladder's Dynamic Type scaling. Values are the approved mocks.
public enum WidgetStyleType {
    public static func heroNumeral(style: WidgetLayoutStyle, family: WidgetFamily, providerCount: Int) -> Double {
        switch (style, family) {
        case (.nestedMeter, .small): 20
        case (.nestedMeter, .medium): 30
        case (.nestedMeter, .large): 42
        case (.vesselHero, .small): 36
        case (.vesselHero, .medium): providerCount > 1 ? 30 : 34
        case (.vesselHero, .large): 42
        case (.tightestFirst, .small): 22
        case (.tightestFirst, .medium): 34
        case (.tightestFirst, .large): 34
        case (.liquidLevel, .small): 44
        case (.liquidLevel, .medium): 38
        case (.liquidLevel, .large): 50
        }
    }

    /// Numerals on secondary rows: Vessel Hero's and Liquid Level's large lists, Tightest
    /// First's ranked list, Nested Meter's rail values.
    public static func rowNumeral(style: WidgetLayoutStyle, family: WidgetFamily) -> Double {
        switch (style, family) {
        case (.nestedMeter, .large): 13
        case (.nestedMeter, _): 11.5
        case (.vesselHero, .large), (.liquidLevel, .large): 18
        case (.tightestFirst, .large): 16
        case (_, _): 12
        }
    }

    /// Vessel Hero medium with one provider: the numerals on the secondary column, a step up
    /// from the shared medium `rowNumeral` as the approved mock draws them (`num(x, 16)`).
    public static let vesselHeroMediumRowNumeral = 16.0

    /// The mocks' 10.5pt caption (`.cd` at 10.5px): Nested Meter's small detail line, medium
    /// countdowns and large rail countdowns, Tightest First's small window label and large row
    /// countdowns, and the small waiting line. Half a point under `WidgetTypeScale.countdown`;
    /// like every caption it keeps Dynamic Type scaling through the caption view.
    public static let compactCaption = 10.5
}

/// Layout tokens the four widget styles add (KTD6, KTD9, KTD10). Values are the approved
/// mocks; each is a token because more than one family or style uses it (DESIGN.md rule 2).
public enum WidgetStyleMetrics {
    /// Nested Meter: the primary window's bar, and the rails hung beneath it.
    public static func nestedParentBar(_ family: WidgetFamily) -> Double {
        family == .large ? 10 : 7
    }

    public static func nestedRail(_ family: WidgetFamily) -> Double {
        family == .large ? 4 : 3
    }

    public static func nestedRailGap(_ family: WidgetFamily) -> Double {
        family == .small ? 3 : 4
    }

    /// Tightest First's bars: the headline bar on large, every other bar.
    public static let tightestHeadlineBar = 8.0
    public static let tightestRowBar = 5.0

    /// Vessel Hero: the gap between vessel and numeral, as a fraction of the numeral size.
    public static let heroVesselGapRatio = 0.2
    /// The small vessel beside a list row's numeral, and its stroke.
    public static let rowVesselWidth = 9.0
    public static let rowVesselHeight = 16.0
    public static let rowVesselStroke = 1.3
    /// Vessel Hero medium with one provider: the secondary column's vessels, a size up from the
    /// large list's 9 × 16 as the approved mock draws them (`vessel(x, 10, 18)`). Same stroke.
    public static let mediumRowVesselWidth = 10.0
    public static let mediumRowVesselHeight = 18.0
    /// The brand-mark slot on a list row (Vessel Hero's and Tightest First's large lists),
    /// smaller than the family's identity-row `WidgetMetrics.markSlot` (mock: `mk(x.p.id, 15)`).
    public static let rowMark = 15.0

    /// KTD9: Liquid Level's wash in full color — fill alpha at the top and bottom of the
    /// liquid, and the bright top edge.
    public static let washTopOpacity = 0.30
    public static let washBottomOpacity = 0.12
    public static let washEdgeOpacity = 0.70
    public static let washEdgeWidth = 1.5
    /// KTD9: the wash outside full color (accented, vibrant, StandBy) is `.primary` at this
    /// opacity, never an opaque fill.
    public static let washMonochromeOpacity = 0.12

    /// CA-W1: the clear space the surface edge keeps from a text band, above and below.
    public static let washEdgeTextClearance = 3.0
    /// CA-W1: the content inset the wash cannot read from where it is drawn (system margin
    /// plus the 2pt residual): 14 on iPhone small and large, 16 on iPhone medium, 18 on the
    /// Mac. A text band is taken across the whole range, so one rule holds on every host.
    public static let washContentInset: ClosedRange<Double> = 14...18

    /// CA-W1: Liquid Level's vertical rhythm, shared by the view that lays it out and the
    /// recipe that keeps the surface edge off its text. Large's hero sits this far under the
    /// identity row; the numeral and its caption block are `heroCaptionGap` apart, the caption
    /// lines `captionLineGap`; each large secondary row is `largeRowHeight` tall; the tail
    /// (footer or spend strip) sits `tailGap` under the rows.
    public static let liquidLargeHeroTop = 10.0
    public static let liquidHeroCaptionGap = 5.0
    public static let liquidCaptionLineGap = 2.0
    public static let liquidLargeRowHeight = 26.0
    public static let liquidTailGap = 8.0

    /// CA-W1: spacing the shared frame and tail draw around every style, which the surface
    /// rule has to know too. Each mirrors a literal at its drawing site and must move with it:
    /// the gap above the dimmed sentence and the small/medium reset notes
    /// (`HeadroomWidgetFreshnessFrame.lineGap`), the gap under large's reset notes
    /// (`HeadroomWidgetStyleTail`), and the waiting caption's ghost mark (`HeadroomWidgetWaitingLine`).
    public static let freshnessLineGap = 6.0
    public static let pastResetNoteGap = 6.0
    public static let waitingMarkHeight = 13.0
    /// The spend strip's rule and the gap under it, above its row.
    public static var spendStripRule: Double { WidgetMetrics.hairline + WidgetMetrics.spendRuleToRow }
}

/// CA-W1: the line metrics of the system face the widgets set every string in, as fractions
/// of the point size (SF Pro, measured with `NSFont`: line 1.178 em, ascender 0.967 em, cap
/// height 0.705 em). Core cannot measure a font, so the recipe's text bands use these.
public enum WidgetTextMetrics {
    /// One line's height: ascender plus descender (the system face has no leading).
    public static let lineHeightRatio = 1.178
    /// From the top of a line to the top of its capitals and figures.
    public static let capTopRatio = 0.247

    public static func lineHeight(_ size: Double) -> Double { size * lineHeightRatio }
    public static func capTop(_ size: Double) -> Double { size * capTopRatio }
}

/// KTD5: the one fill every widget style paints with — bars, rails, vessel liquid and the
/// liquid wash. Severity comes from the data (`window.severity`), never recomputed here.
public enum WidgetStyleColors {
    public static func fill(
        for window: WidgetWindowSummary,
        colorMode: WidgetColorMode,
        dark: Bool,
        increasedContrast: Bool
    ) -> HeadroomTint? {
        switch window.freshness {
        case .unavailable:
            return nil
        case .stale:
            switch window.severity {
            case .healthy:
                // The `WidgetUsageSeverity` overload maps healthy to the neutral stale grey,
                // which is the event mode; Always colored takes the popover's tinted green.
                return colorMode == .solid
                    ? opaque(HeadroomMeterColorValues.staleFill(for: UsageSeverity.healthy, dark: dark, increasedContrast: increasedContrast))
                    : opaque(HeadroomWidgetColorValues.staleNeutralFill(dark: dark))
            case .low, .critical:
                return opaque(HeadroomMeterColorValues.staleFill(for: window.severity, dark: dark, increasedContrast: increasedContrast))
            }
        case .live:
            switch window.severity {
            case .healthy:
                return colorMode == .solid
                    ? opaque(HeadroomSeverityColorValues.healthyFill(dark: dark, increasedContrast: increasedContrast))
                    : HeadroomWidgetColorValues.neutralFill(dark: dark)
            case .low:
                return opaque(HeadroomSeverityColorValues.lowFill(dark: dark, increasedContrast: increasedContrast))
            case .critical:
                return opaque(HeadroomSeverityColorValues.criticalFill(dark: dark, increasedContrast: increasedContrast))
            }
        }
    }

    private static func opaque(_ color: HeadroomRGBColor) -> HeadroomTint {
        HeadroomTint(color: color, opacity: 1)
    }
}
