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
    // Grok and Cursor are monochrome brands (their marks ship as light/dark pairs); these
    // mid-tone accents exist for the SF Symbol fallback + single-color tints and read on
    // both schemes. First-pass identity values — Phase 2 owns visual density.
    public static let grok = HeadroomRGBColor(red: 0.36, green: 0.40, blue: 0.46)
    public static let cursor = HeadroomRGBColor(red: 0.33, green: 0.34, blue: 0.38)
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
        // Grok/Cursor are monochrome brands: their title accent is a legible near-primary
        // neutral (grok cooler, cursor pure) that clears WCAG AA small-text on the light
        // container (dark step) and the dark tile (light step).
        case (ProviderID.grok.raw, false): HeadroomRGBColor(red: 0.20, green: 0.22, blue: 0.25)
        case (ProviderID.grok.raw, true): HeadroomRGBColor(red: 0.78, green: 0.80, blue: 0.84)
        case (ProviderID.cursor.raw, false): HeadroomRGBColor(red: 0.17, green: 0.17, blue: 0.18)
        case (ProviderID.cursor.raw, true): HeadroomRGBColor(red: 0.81, green: 0.81, blue: 0.83)
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

/// The ramp's dark-scheme start is mixed against different meter surfaces. Light mode
/// uses the same white mix on both because both reference surfaces are light neutrals.
public enum MeterRampSurface: Sendable {
    case flat
    case well
}

/// App-local color tokens for the macOS popover meter. These stay separate from
/// `HeadroomWidgetColorValues` so meter experiments cannot change the widgets by accident.
public enum HeadroomMeterColorValues {
    private static let darkText = HeadroomRGBColor(red: 0.92, green: 0.92, blue: 0.96)
    private static let lightLabel = HeadroomRGBColor(
        red: 29.0 / 255.0,
        green: 31.0 / 255.0,
        blue: 36.0 / 255.0
    )
    private static let lightMetadata = HeadroomRGBColor(red: 0.24, green: 0.24, blue: 0.26)

    public static func labelInk(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: dark ? darkText : lightLabel, opacity: 0.90)
    }

    public static func countdownInk(dark: Bool) -> HeadroomTint {
        // The round-4 D2 values clear 4.5:1 against both RaisedTile fill endpoints.
        HeadroomTint(color: dark ? darkText : lightMetadata, opacity: dark ? 0.53 : 0.72)
    }

    public static func glassA(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.22)
            : HeadroomTint(
                color: HeadroomRGBColor(
                    red: 117.0 / 255.0,
                    green: 124.0 / 255.0,
                    blue: 134.0 / 255.0
                ),
                opacity: 1
            )
    }

    public static func glassB(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.11)
            : HeadroomTint(
                color: HeadroomRGBColor(
                    red: 102.0 / 255.0,
                    green: 108.0 / 255.0,
                    blue: 117.0 / 255.0
                ),
                opacity: 1
            )
    }

    public static func glassRim(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .white, opacity: dark ? 0.25 : 0.30)
    }

    public static func wellBackground(dark: Bool) -> HeadroomRGBColor {
        dark
            ? HeadroomRGBColor(
                red: 15.0 / 255.0,
                green: 17.0 / 255.0,
                blue: 20.0 / 255.0
            )
            : HeadroomRGBColor(
                red: 223.0 / 255.0,
                green: 226.0 / 255.0,
                blue: 231.0 / 255.0
            )
    }

    public static func wellShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0.65 : 0.20)
    }

    public static func tickOff(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.09)
            : HeadroomTint(color: .black, opacity: 0.08)
    }

    public static func tickGlass(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.26)
            : HeadroomTint(
                color: HeadroomRGBColor(
                    red: 107.0 / 255.0,
                    green: 114.0 / 255.0,
                    blue: 123.0 / 255.0
                ),
                opacity: 1
            )
    }

    public static func tickGlassCap(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.52)
            : HeadroomTint(
                color: HeadroomRGBColor(
                    red: 71.0 / 255.0,
                    green: 78.0 / 255.0,
                    blue: 87.0 / 255.0
                ),
                opacity: 1
            )
    }

    public static func rampStartSeverityMix(
        dark: Bool,
        surface: MeterRampSurface
    ) -> Double {
        guard dark else { return 0.55 }
        return surface == .flat ? 0.58 : 0.42
    }

    public static func ghostBodyOpacity(for severity: UsageSeverity, dark: Bool) -> Double {
        switch (dark, severity) {
        case (true, .critical): 0.22
        case (true, _): 0.18
        case (false, .critical): 0.34
        case (false, _): 0.30
        }
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
        // Cursor's cube fills its 24pt viewBox edge-to-edge like Claude's starburst; inset
        // it so it reads at the same weight as the other marks in the fixed icon slot.
        case ProviderID.cursor.raw: 0.9
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

    /// Critical severity rendered as *text*, decoupled from the bar fill (H3a, Jul 2026
    /// multi-account design review). The chipless multi-account meter paints the percentage
    /// numeral critical instead of showing the "Low" chip, so the numeral becomes AA-legible
    /// body text rather than a bar fill — a separate token because the fill red fails at text
    /// size. WCAG contrast for 18pt-semibold numerals (relative luminance L, ratio
    /// (L_light+0.05)/(L_dark+0.05)):
    /// - Dark = (1.00,0.40,0.35), L≈0.315, on the composite dark card #2C2C2E (L≈0.025)
    ///   → 4.85:1. The raw fill red (1.00,0.34,0.29) lands at only ~4.45:1 there, so it is
    ///   brightened (green 0.34→0.40, blue 0.29→0.35) until it clears ≥4.5:1.
    /// - Light = (0.82,0.14,0.11), L≈0.149, on white → 5.28:1 and across the light card fill
    ///   (L≈0.87 bottom … 0.97 top) ≥4.6:1. The raw fill red (0.85,0.16,0.13) passes on pure
    ///   white (4.9:1) but dips to ~4.3:1 on the card's darker lower fill, so it is darkened
    ///   (0.85→0.82 R, 0.16→0.14 G, 0.13→0.11 B) to hold ≥4.5:1 over the whole surface.
    public static func criticalText(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 1.00, green: 0.40, blue: 0.35) : HeadroomRGBColor(red: 0.82, green: 0.14, blue: 0.11)
    }

    public static func color(for severity: WidgetUsageSeverity, dark: Bool) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthy(dark: dark)
        case .low: low(dark: dark)
        case .critical: critical(dark: dark)
        }
    }
}
