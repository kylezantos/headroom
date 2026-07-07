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
}

public enum HeadroomBrandColorValues {
    public static let claude = HeadroomRGBColor(red: 0.85, green: 0.47, blue: 0.26)
    public static let codex = HeadroomRGBColor(red: 0.28, green: 0.34, blue: 1.00)
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
