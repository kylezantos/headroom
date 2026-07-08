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

    // R2: wraps the shared HeadroomWidgetColorValues so macOS and iOS cannot drift.
    static func textAccent(for id: String, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id, dark: scheme == .dark) else { return .secondary }
        return Color(rgb)
    }

    static func symbol(for id: String) -> String {
        switch id {
        case ProviderID.claude.raw: "sparkle"
        case ProviderID.codex.raw: "chevron.left.forwardslash.chevron.right"
        default: "circle.dashed"
        }
    }

    static func severityColor(for severity: WidgetUsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    static func secondaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark))
    }

    static func tertiaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark))
    }

    static func barTrack(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.barTrack(dark: scheme == .dark))
    }

    static func hairline(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.hairline(dark: scheme == .dark))
    }

    static func cardFill(scheme: ColorScheme) -> LinearGradient {
        let dark = scheme == .dark
        return LinearGradient(
            colors: [
                Color(HeadroomWidgetColorValues.tileFillTop(dark: dark)),
                Color(HeadroomWidgetColorValues.tileFillBottom(dark: dark))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func cardRing(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileRing(dark: scheme == .dark))
    }

    static func cardTopRim(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileTopRim(dark: scheme == .dark))
    }

    static func cardEdgeShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileCloseShadow(dark: scheme == .dark))
    }

    static func cardCloseShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileAmbientShadow(dark: scheme == .dark))
    }

    static func cardAmbientShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileLongShadow(dark: scheme == .dark))
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    init(_ tint: HeadroomTint) {
        self = Color(tint.color).opacity(tint.opacity)
    }
}
