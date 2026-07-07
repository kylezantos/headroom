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
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.44) : HeadroomTint(color: lightNeutral, opacity: 0.55)
    }

    public static func barTrack(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.16) : HeadroomTint(color: .black, opacity: 0.14)
    }

    public static func hairline(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.10) : HeadroomTint(color: .black, opacity: 0.09)
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
