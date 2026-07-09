import SwiftUI
import HeadroomCore

/// Static per-provider visual identity (design review): a brand-ish accent color and
/// SF Symbol so Claude and Codex cards are distinguishable at a glance. Static only —
/// no pulsing/animated indicators (user's standing rule).
enum ProviderStyle {
    static func svgResourceName(for id: ProviderID) -> String? {
        switch id {
        case .claude: return "claude-color"
        case .codex: return "codex-color"
        default: return nil
        }
    }

    static func accent(for id: ProviderID) -> Color {
        switch id {
        case .claude: return Color(HeadroomBrandColorValues.claude)
        case .codex: return Color(HeadroomBrandColorValues.codex)
        default: return .secondary
        }
    }

    /// Brand-tinted provider *title* color, shared with the widgets
    /// (`HeadroomWidgetColorValues.textAccent` — WCAG-tuned per scheme) so the popover
    /// and widget headers read as one system (Jul 2026 widget-alignment pass).
    static func textAccent(for id: ProviderID, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id.raw, dark: scheme == .dark) else {
            return .primary
        }
        return Color(rgb)
    }

    /// Widget-tuned label grays (WCAG-checked in `HeadroomWidgetColorValues`), adopted
    /// over the system `.secondary`/`.tertiary` — system tertiary sat at ~2.3:1 on the
    /// dark tile; the shared token reaches ~4.2:1 and keeps all surfaces in step.
    static func secondaryText(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    static func tertiaryText(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// Semantic fill for a usage bar by health band (UI-01). A static three-stop ramp —
    /// green → amber → red — chosen over the brand accent because Claude's warm clay is
    /// too close to amber to read as "warning". Brand identity stays in the logo + plan
    /// pill; the bar's job is to signal how much is left. No animation: a threshold, not
    /// a pulse, so it honors the standing no-pulsing rule.
    static func severityColor(for severity: UsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    static func symbol(for id: ProviderID) -> String {
        switch id {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        default: return "circle.dashed"
        }
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
