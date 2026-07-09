import Foundation

/// SwiftUI-free RGB color values shared by the app and widget targets.
public struct HeadroomRGBColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = HeadroomRGBColor(red: 1, green: 1, blue: 1)
    public static let black = HeadroomRGBColor(red: 0, green: 0, blue: 0)
}

/// A base color plus an opacity, kept SwiftUI-free so both widget style layers can build
/// the same translucent tint (`Color(tint.color).opacity(tint.opacity)`) without the raw
/// numbers living in two places.
public struct HeadroomTint: Sendable, Equatable {
    public let color: HeadroomRGBColor
    public let opacity: Double

    public init(color: HeadroomRGBColor, opacity: Double) {
        self.color = color
        self.opacity = opacity
    }
}

public enum HeadroomBrandColorValues {
    public static let claude = HeadroomRGBColor(red: 0.85, green: 0.47, blue: 0.26)
    public static let codex = HeadroomRGBColor(red: 0.28, green: 0.34, blue: 1.00)
}

/// R2: one source of truth for the widget "usage" look — provider text accents and the
/// muted text / bar-track / hairline tints. Both the macOS (`WidgetProviderStyle`) and iOS
/// (`IOSWidgetStyle`) style layers wrap these values so the two widget families cannot
/// visually drift. The SwiftUI `Color` construction stays at each platform's style edge;
/// only the raw numbers live here (already compiled into both widget targets).
public enum HeadroomWidgetColorValues {
    /// Provider display-name accent, tuned warmer/cooler than the raw brand fill per scheme.
    /// Returns `nil` for unknown providers so the caller can fall back to `.secondary`.
    public static func textAccent(for providerID: String, dark: Bool) -> HeadroomRGBColor? {
        switch (providerID, dark) {
        // Light Claude sits at 4.17:1 on the widget's light container top at its smallest
        // usage (12pt semibold, small-widget provider rows); this darker step clears
        // WCAG AA small-text (≥4.5:1) on every light surface it appears on.
        case (ProviderID.claude.raw, false): HeadroomRGBColor(red: 0.70, green: 0.33, blue: 0.11)
        case (ProviderID.claude.raw, true): HeadroomRGBColor(red: 0.91, green: 0.56, blue: 0.41)
        case (ProviderID.codex.raw, false): HeadroomRGBColor(red: 0.20, green: 0.25, blue: 0.84)
        case (ProviderID.codex.raw, true): HeadroomRGBColor(red: 0.59, green: 0.63, blue: 1.00)
        default: nil
        }
    }

    private static let darkNeutral = HeadroomRGBColor(red: 0.92, green: 0.92, blue: 0.96)
    private static let lightNeutral = HeadroomRGBColor(red: 0.24, green: 0.24, blue: 0.26)

    // Light opacities are set by WCAG AA small-text (≥4.5:1) on the lightest surfaces each
    // role sits on: tertiary needs 0.74 to clear the white tile fill (4.96) and the light
    // container bottom where the widget footer lives (4.56); secondary steps to 0.84 so the
    // two-level gray hierarchy survives the tertiary bump (6.63 on white, 5.44 on the plan
    // capsule's bar-track). Dark passes at the existing values (worst case 4.99).
    public static func secondaryText(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.66) : HeadroomTint(color: lightNeutral, opacity: 0.84)
    }

    public static func tertiaryText(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.56) : HeadroomTint(color: lightNeutral, opacity: 0.74)
    }

    public static func barTrack(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.14) : HeadroomTint(color: .black, opacity: 0.12)
    }

    public static func hairline(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.10) : HeadroomTint(color: .black, opacity: 0.07)
    }

    public static func containerBackgroundTop(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.082, green: 0.090, blue: 0.114) : HeadroomRGBColor(red: 0.965, green: 0.969, blue: 0.976)
    }

    public static func containerBackgroundMiddle(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.061, green: 0.070, blue: 0.091) : HeadroomRGBColor(red: 0.945, green: 0.951, blue: 0.963)
    }

    public static func containerBackgroundBottom(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.043, green: 0.051, blue: 0.067) : HeadroomRGBColor(red: 0.925, green: 0.933, blue: 0.949)
    }

    public static func containerBackgroundGlow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: HeadroomRGBColor(red: 0.431, green: 0.475, blue: 1.0), opacity: dark ? 0.10 : 0.08)
    }

    public static func tileFillTop(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.145, green: 0.152, blue: 0.176) : .white
    }

    public static func tileFillBottom(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.098, green: 0.106, blue: 0.129) : HeadroomRGBColor(red: 0.984, green: 0.984, blue: 0.988)
    }

    public static func tileRing(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.065) : HeadroomTint(color: .black, opacity: 0.05)
    }

    public static func tileTopRim(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .white, opacity: dark ? 0.07 : 0)
    }

    public static func tileCloseShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0.28 : 0.06)
    }

    public static func tileAmbientShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0.40 : 0.05)
    }

    public static func tileLongShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0 : 0.05)
    }
}

/// Layout metrics for the bare (no-container) brand marks, shared by every surface — the
/// iOS app + widget, and the Mac popover + widget — so they stay visually identical.
public enum HeadroomBrandMark {
    /// Per-provider optical-size correction. Claude's starburst radiates to the edges of
    /// its viewBox, so at an equal frame it reads larger than Codex's inset blob;
    /// scaling it down inside a fixed slot makes the two read as equal weight.
    /// (0.87 → 0.84, Jul 2026: at the larger 19–20pt card-header size the starburst
    /// still read slightly bigger.)
    public static func opticalScale(for providerID: String) -> Double {
        switch providerID {
        case ProviderID.claude.raw: 0.84
        default: 1.0
        }
    }
}

/// Severity colors are scheme-aware: the dark values are the vivid originals (tuned for
/// dark cards), while the light values are darkened along the same hues so bar fills clear
/// WCAG 1.4.11 (≥3:1) against the light bar track (the originals sat at 1.6–2.6:1) and read
/// ≥4:1 as chip text on white. Dark critical is nudged (0.27 → 0.34 green) for the same
/// 3:1 bar-vs-track floor; dark healthy/low already passed and are untouched.
public enum HeadroomSeverityColorValues {
    public static func healthy(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.20, green: 0.78, blue: 0.35) : HeadroomRGBColor(red: 0.09, green: 0.52, blue: 0.22)
    }

    public static func low(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 1.00, green: 0.62, blue: 0.04) : HeadroomRGBColor(red: 0.70, green: 0.41, blue: 0.00)
    }

    public static func critical(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 1.00, green: 0.34, blue: 0.29) : HeadroomRGBColor(red: 0.85, green: 0.16, blue: 0.13)
    }

    public static func color(for severity: WidgetUsageSeverity, dark: Bool) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthy(dark: dark)
        case .low: low(dark: dark)
        case .critical: critical(dark: dark)
        }
    }
}
