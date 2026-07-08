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
