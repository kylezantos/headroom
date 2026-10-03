import Foundation

/// KTD6 (2026-10-02 widget-styles plan): the Headroom vessel at widget scale.
///
/// The proportion is the menu-bar glyph's (`VesselGlyph.menuBarSize`, 11 × 18), promoted here
/// because the widget is its second call site (DESIGN.md rule 2) and the widget extensions
/// cannot import AppKit. Liquid is clipped to an inset capsule and fills the *inner* height,
/// as `VesselGlyph.render` does.
public struct WidgetVesselGeometry: Sendable, Equatable {
    public static let aspect = 11.0 / 18.0
    /// Hero stroke is ~11% of the width, clamped so it neither hairlines nor thickens.
    public static let heroStrokeRange: ClosedRange<Double> = 1.5...2.1

    public let width: Double
    public let height: Double
    public let stroke: Double
    public let inset: Double

    /// A hero vessel sized from its height (Vessel Hero sizes it to the numeral's digit ink).
    public init(height: Double) {
        self.init(width: (height * Self.aspect * 2).rounded() / 2, height: height)
    }

    public init(width: Double, height: Double, stroke: Double? = nil) {
        self.width = width
        self.height = height
        let resolved = stroke ?? min(Self.heroStrokeRange.upperBound, max(Self.heroStrokeRange.lowerBound, width * 0.11))
        self.stroke = resolved
        inset = resolved + max(0.6, width * 0.055)
    }

    public var innerWidth: Double { max(0, width - 2 * inset) }
    public var innerHeight: Double { max(0, height - 2 * inset) }

    /// Nil or zero → no liquid (R11: an unavailable window draws an empty outline). Any other
    /// value is floored at half the inner width so a nonzero level always reads as liquid.
    public func liquidHeight(fraction: Double?) -> Double {
        guard let fraction, fraction > 0 else { return 0 }
        return min(innerHeight, max(innerWidth * 0.5, innerHeight * min(1, fraction)))
    }

    /// The menu-bar rule: only a live critical window inks the wall.
    public static func wallIsCritical(_ window: WidgetWindowSummary?) -> Bool {
        guard let window, window.freshness.isLive else { return false }
        return window.severity == .critical
    }
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
