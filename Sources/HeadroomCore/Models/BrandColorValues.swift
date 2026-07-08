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
        case (ProviderID.claude.raw, false): HeadroomRGBColor(red: 0.74, green: 0.36, blue: 0.13)
        case (ProviderID.claude.raw, true): HeadroomRGBColor(red: 0.91, green: 0.56, blue: 0.41)
        case (ProviderID.codex.raw, false): HeadroomRGBColor(red: 0.20, green: 0.25, blue: 0.84)
        case (ProviderID.codex.raw, true): HeadroomRGBColor(red: 0.59, green: 0.63, blue: 1.00)
        default: nil
        }
    }

    private static let darkNeutral = HeadroomRGBColor(red: 0.92, green: 0.92, blue: 0.96)
    private static let lightNeutral = HeadroomRGBColor(red: 0.24, green: 0.24, blue: 0.26)

    public static func secondaryText(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.66) : HeadroomTint(color: lightNeutral, opacity: 0.74)
    }

    public static func tertiaryText(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.56) : HeadroomTint(color: lightNeutral, opacity: 0.54)
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
    /// its viewBox, so at an equal frame it reads ~13% larger than Codex's inset blob;
    /// scaling it down inside a fixed slot makes the two read as equal weight.
    public static func opticalScale(for providerID: String) -> Double {
        switch providerID {
        case ProviderID.claude.raw: 0.87
        default: 1.0
        }
    }
}

public enum HeadroomSeverityColorValues {
    public static let healthy = HeadroomRGBColor(red: 0.20, green: 0.78, blue: 0.35)
    public static let low = HeadroomRGBColor(red: 1.00, green: 0.62, blue: 0.04)
    public static let critical = HeadroomRGBColor(red: 1.00, green: 0.27, blue: 0.23)

    public static func color(for severity: WidgetUsageSeverity) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthy
        case .low: low
        case .critical: critical
        }
    }
}
