import SwiftUI

enum HeadroomTheme {
    static let tileRadius: CGFloat = 17
    static let entranceAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.34)
    static let valueSpring = Animation.spring(response: 0.3, dampingFraction: 0.9)

    static func providerAccent(for id: String) -> Color {
        switch id {
        case ProviderID.claude.raw: Color(HeadroomBrandColorValues.claude)
        case ProviderID.codex.raw: Color(HeadroomBrandColorValues.codex)
        default: .secondary
        }
    }

    static func providerTextAccent(for id: String, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id, dark: scheme == .dark) else { return .secondary }
        return Color(rgb)
    }

    static func severityColor(for severity: WidgetUsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    /// The screen background — a lifted vertical gradient (gray at top → near-black at
    /// bottom) with a faint cool glow bleeding from the top, ported from the approved
    /// `design/ios-companion.html` mock. This is what gives the phone its Mac-like
    /// elevated feel without literally copying the Mac's translucent glass (a flat
    /// full-screen gray would read muddier, not more premium).
    static func backgroundView(_ scheme: ColorScheme) -> some View {
        let dark = scheme == .dark
        let stops = [
            Color(HeadroomWidgetColorValues.containerBackgroundTop(dark: dark)),
            Color(HeadroomWidgetColorValues.containerBackgroundBottom(dark: dark))
        ]
        let glow = Color(HeadroomWidgetColorValues.containerBackgroundGlow(dark: dark))
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
            .overlay {
                RadialGradient(
                    gradient: Gradient(colors: [glow, .clear]),
                    center: UnitPoint(x: 0.5, y: -0.05),
                    startRadius: 0,
                    endRadius: 460
                )
            }
    }

    /// Opaque tile fill — a subtle top-lit vertical gradient. Colours are the mock's
    /// translucent white-on-gradient card pre-composited over the background so the tile
    /// stays fully opaque and can cast a real ambient shadow (a translucent fill would
    /// swallow the shadow it needs to ground on the lighter top of the screen).
    static func tileFill(_ scheme: ColorScheme) -> LinearGradient {
        let dark = scheme == .dark
        let stops = [
            Color(HeadroomWidgetColorValues.tileFillTop(dark: dark)),
            Color(HeadroomWidgetColorValues.tileFillBottom(dark: dark))
        ]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark))
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        // Both schemes tuned so the small caption text (reset labels, "left") clears
        // WCAG AA (≥4.5:1) on the tile fill — dark at 0.56, light at 0.74 opacity; the
        // rationale lives with the values in HeadroomWidgetColorValues.
        Color(HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark))
    }

    static func barTrack(_ scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.barTrack(dark: scheme == .dark))
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.hairline(dark: scheme == .dark))
    }
}

extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    init(_ tint: HeadroomTint) {
        self = Color(tint.color).opacity(tint.opacity)
    }
}
