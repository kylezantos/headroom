import SwiftUI
import HeadroomCore

/// The always-visible menu bar content (R5, UI-03): the compact vessel glyph, with the
/// tightest live window's remaining percent optionally shown beside it. The glyph is
/// tinted by *severity* (healthy → amber → red), not by brand color, so the menu bar
/// means "how close am I to running out" at a glance; a small warning dot appears when a
/// provider needs re-auth, so a dead provider isn't silently invisible. Static only — no
/// pulsing (user's standing rule).
struct MenuBarLabel: View {
    let summary: MenuBarSummary
    let showsPercentage: Bool
    /// 0…1 fill for the vessel (the selected provider's weekly remaining), or nil for
    /// the static decorative level.
    var fill: Double? = nil

    var body: some View {
        HStack(spacing: 3) {
            // A template `NSImage` (not a SwiftUI shape) — menu-bar labels only rasterize
            // `Text`/`Image`, and the template tints with the severity `foregroundStyle`.
            Image(nsImage: VesselGlyph.menuBarImage(fill: fill))
                .overlay(alignment: .topTrailing) {
                    if summary.needsAttention {
                        Circle()
                            .fill(.red)
                            .frame(width: 5, height: 5)
                            .offset(x: 3, y: -1)
                    }
                }
            if showsPercentage, !summary.isNeutral {
                Text(summary.text).font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(tint)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Severity color when there's a live number; a warning tint when a provider needs
    /// attention but there's no number yet; otherwise the neutral primary color.
    private var tint: Color {
        if !summary.isNeutral {
            return ProviderStyle.severityColor(for: summary.severity)
        }
        return summary.needsAttention ? ProviderStyle.severityColor(for: .critical) : .primary
    }

    private var accessibilityLabel: String {
        if summary.needsAttention, summary.isNeutral {
            return "AI usage — a provider needs sign-in"
        }
        let base = summary.detail.map { "\($0), \(summary.text) remaining" } ?? "AI usage"
        return summary.needsAttention ? "\(base) — a provider needs sign-in" : base
    }
}
