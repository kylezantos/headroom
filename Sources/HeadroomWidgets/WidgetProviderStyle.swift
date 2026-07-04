import HeadroomCore
import SwiftUI

enum WidgetProviderStyle {
    static func assetName(for id: String) -> String? {
        switch id {
        case ProviderID.claude.raw: "ClaudeBrandIcon"
        case ProviderID.codex.raw: "CodexBrandIcon"
        default: nil
        }
    }

    static func accent(for id: String) -> Color {
        switch id {
        case ProviderID.claude.raw: return Color(HeadroomBrandColorValues.claude)
        case ProviderID.codex.raw: return Color(HeadroomBrandColorValues.codex)
        default: return .secondary
        }
    }

    static func textAccent(for id: String, scheme: ColorScheme) -> Color {
        switch (id, scheme) {
        case (ProviderID.claude.raw, .light): Color(red: 0.74, green: 0.36, blue: 0.13)
        case (ProviderID.claude.raw, .dark): Color(red: 0.91, green: 0.56, blue: 0.41)
        case (ProviderID.codex.raw, .light): Color(red: 0.20, green: 0.25, blue: 0.84)
        case (ProviderID.codex.raw, .dark): Color(red: 0.59, green: 0.63, blue: 1.00)
        default: .secondary
        }
    }

    static func symbol(for id: String) -> String {
        switch id {
        case ProviderID.claude.raw: "sparkle"
        case ProviderID.codex.raw: "chevron.left.forwardslash.chevron.right"
        default: "circle.dashed"
        }
    }

    static func severityColor(for severity: WidgetUsageSeverity) -> Color {
        switch severity {
        case .healthy: return Color(HeadroomSeverityColorValues.healthy)
        case .low: return Color(HeadroomSeverityColorValues.low)
        case .critical: return Color(HeadroomSeverityColorValues.critical)
        }
    }

    static func secondaryText(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.66) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.74)
    }

    static func tertiaryText(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.44) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.55)
    }

    static func barTrack(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)
    }

    static func hairline(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.09)
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
