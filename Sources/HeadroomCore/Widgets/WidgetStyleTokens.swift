import Foundation

/// KTD8 (2026-10-02 widget-styles plan): the numeral sizes the four widget styles add to the
/// `WidgetTypeScale` ladder. Hero numerals are fixed size — scaling a 42pt hero at xxLarge
/// overflows "100%" and drags Vessel Hero's vessel with it — while labels, captions and
/// countdowns keep the ladder's Dynamic Type scaling. Values are the approved mocks
/// (`design/widget-styles-round2.html`).
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

    /// The bar height the shared usage meter uses on large (was `LargeWidgetDensity.regular`).
    public static let largeMeterBar = 7.0

    /// Vessel Hero: the gap between vessel and numeral, as a fraction of the numeral size.
    public static let heroVesselGapRatio = 0.2
    /// The small vessel beside a list row's numeral, and its stroke.
    public static let rowVesselWidth = 9.0
    public static let rowVesselHeight = 16.0
    public static let rowVesselStroke = 1.3

    /// KTD9: Liquid Level's wash in full color — fill alpha at the top and bottom of the
    /// liquid, and the bright top edge.
    public static let washTopOpacity = 0.30
    public static let washBottomOpacity = 0.12
    public static let washEdgeOpacity = 0.70
    public static let washEdgeWidth = 1.5
    /// KTD9: the wash outside full color (accented, vibrant, StandBy) is `.primary` at this
    /// opacity, never an opaque fill.
    public static let washMonochromeOpacity = 0.12
}
