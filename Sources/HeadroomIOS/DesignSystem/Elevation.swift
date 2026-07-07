import SwiftUI

/// Card elevation via the ring-glow technique (Jakub Krehel, "Details that make
/// interfaces feel better") — elevation is *drawn*, never bordered. A faint uniform ring
/// replaces the border, a top-rim highlight catches the light in dark mode, and soft
/// ambient shadows ground the tile. Ports the approved `design/ios-companion.html`
/// `--tile-shadow` recipe faithfully:
///   dark:  0 0 0 1px rgba(255,255,255,.065), inset 0 1px 0 rgba(255,255,255,.07),
///          0 1px 2px rgba(0,0,0,.28), 0 10px 26px -14px rgba(0,0,0,.45)
///   light: 0 0 0 1px rgba(0,0,0,.05), 0 1px 2px -1px rgba(0,0,0,.06),
///          0 4px 8px -2px rgba(0,0,0,.05), 0 12px 22px -8px rgba(0,0,0,.05)
struct HeadroomTileModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        content
            // Opaque fill carries its own ambient shadows so they survive on the near-black
            // screen; a black drop shadow barely reads there (the memory's point), so the
            // ring + top-rim do the real edge-definition work in dark.
            .background {
                shape
                    .fill(HeadroomTheme.tileFill(scheme))
                    .shadow(color: .black.opacity(dark ? 0.28 : 0.06), radius: 1.5, y: 1)
                    .shadow(color: .black.opacity(dark ? 0.40 : 0.05), radius: dark ? 11 : 6, y: dark ? 9 : 3)
                    .shadow(color: .black.opacity(dark ? 0 : 0.05), radius: 13, y: 9)
            }
            // The ring — a faint hairline that replaces the border (not a hard outline).
            .overlay {
                shape.strokeBorder(
                    dark ? Color.white.opacity(0.065) : Color.black.opacity(0.05),
                    lineWidth: 1
                )
            }
            // Top-rim highlight — the restrained glow catching the top edge. A white rim
            // would vanish on the light card, so it's dark-only.
            .overlay(alignment: .top) {
                shape
                    .fill(Color.white.opacity(dark ? 0.07 : 0))
                    .frame(height: 1)
                    .padding(.horizontal, 9)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func headroomTile(cornerRadius: CGFloat = HeadroomTheme.tileRadius) -> some View {
        modifier(HeadroomTileModifier(cornerRadius: cornerRadius))
    }
}
