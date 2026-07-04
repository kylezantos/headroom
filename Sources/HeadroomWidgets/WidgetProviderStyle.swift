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
        case ProviderID.claude.raw: Color(red: 0.85, green: 0.47, blue: 0.26)
        case ProviderID.codex.raw: Color(red: 0.28, green: 0.34, blue: 1.00)
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
        case .healthy: Color(red: 0.20, green: 0.78, blue: 0.35)
        case .low: Color(red: 1.00, green: 0.62, blue: 0.04)
        case .critical: Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }
}
