import SwiftUI

/// A raised content tile that reads as elevated on the Liquid Glass popover in **both**
/// appearances (R-depth). The trick is that "elevation" is drawn differently per scheme:
///
/// - **Dark**: a faint top-lit rim (bright at the top edge, fading down the perimeter) over a
///   subtle vertical fill, plus a deep shadow — the glassy raised-tile look.
/// - **Light**: a brighter near-opaque fill with a soft shadow and a fine bottom-weighted
///   hairline. A white top-rim would vanish on a light surface, so light mode leans on the
///   shadow + fill contrast instead.
///
/// Content stays a plain tile (never a second `.glassEffect`), so glass-on-glass never muddies
/// the popover (UI-07); glass is reserved for the shell + controls.
struct RaisedTile: ViewModifier {
    var cornerRadius: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        content
            .background(
                shape
                    .fill(LinearGradient(
                        colors: dark
                            ? [Color.white.opacity(0.075), Color.white.opacity(0.045)]
                            : [Color.white.opacity(0.92), Color.white.opacity(0.80)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(dark ? 0.42 : 0.12),
                            radius: dark ? 7 : 5, y: 1)
            )
            .overlay(
                // One gradient stroke does both jobs: a lit top edge fading to a faint
                // side/bottom rim (dark), or a bright top highlight fading to a hairline
                // bottom shadow line (light).
                shape.strokeBorder(
                    LinearGradient(
                        colors: dark
                            ? [Color.white.opacity(0.20), Color.white.opacity(0.06)]
                            : [Color.white.opacity(0.90), Color.black.opacity(0.07)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
    }
}

extension View {
    /// Elevate a content tile on the popover glass, adapting to light/dark. See `RaisedTile`.
    func raisedTile(cornerRadius: CGFloat = 12) -> some View {
        modifier(RaisedTile(cornerRadius: cornerRadius))
    }
}
