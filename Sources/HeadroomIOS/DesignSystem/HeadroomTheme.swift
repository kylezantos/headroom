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
        switch (id, scheme) {
        case (ProviderID.claude.raw, .light): Color(red: 0.74, green: 0.36, blue: 0.13)
        case (ProviderID.claude.raw, .dark): Color(red: 0.91, green: 0.56, blue: 0.41)
        case (ProviderID.codex.raw, .light): Color(red: 0.20, green: 0.25, blue: 0.84)
        case (ProviderID.codex.raw, .dark): Color(red: 0.59, green: 0.63, blue: 1.00)
        default: .secondary
        }
    }

    static func severityColor(for severity: WidgetUsageSeverity) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity))
    }

    /// The screen background — a lifted vertical gradient (gray at top → near-black at
    /// bottom) with a faint cool glow bleeding from the top, ported from the approved
    /// `design/ios-companion.html` mock. This is what gives the phone its Mac-like
    /// elevated feel without literally copying the Mac's translucent glass (a flat
    /// full-screen gray would read muddier, not more premium).
    static func backgroundView(_ scheme: ColorScheme) -> some View {
        let dark = scheme == .dark
        let stops: [Color] = dark
            ? [Color(red: 0.082, green: 0.090, blue: 0.114), Color(red: 0.043, green: 0.051, blue: 0.067)]
            : [Color(red: 0.965, green: 0.969, blue: 0.976), Color(red: 0.925, green: 0.933, blue: 0.949)]
        let glow = Color(red: 0.431, green: 0.475, blue: 1.0).opacity(dark ? 0.10 : 0.08)
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
        let stops: [Color] = scheme == .dark
            ? [Color(red: 0.145, green: 0.152, blue: 0.176), Color(red: 0.098, green: 0.106, blue: 0.129)]
            : [Color(red: 1.0, green: 1.0, blue: 1.0), Color(red: 0.984, green: 0.984, blue: 0.988)]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.66)
            : Color(red: 0.22, green: 0.22, blue: 0.24).opacity(0.74)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        // Dark bumped 0.46 → 0.56 so the small caption text (reset labels, "left") clears
        // WCAG AA on the card fill; light already passes.
        scheme == .dark
            ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.56)
            : Color(red: 0.22, green: 0.22, blue: 0.24).opacity(0.54)
    }

    static func barTrack(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }
}

extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
