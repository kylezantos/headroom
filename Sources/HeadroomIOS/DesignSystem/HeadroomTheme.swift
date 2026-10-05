import SwiftUI

/// KTD1 (iOS parity): the phone keeps only its own layout here — the screen background and the
/// opaque tile. Colour comes from `ProviderStyle` and the Core values, motion from the shared
/// `HeadroomMotion` (plus the phone's entrance in `HeadroomMotion+Phone.swift`).
enum HeadroomTheme {
    static let tileRadius: CGFloat = 17

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
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    init(_ tint: HeadroomTint) {
        self = Color(tint.color).opacity(tint.opacity)
    }
}
