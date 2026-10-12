import AppKit
import SwiftUI

/// A raised content tile that reads as elevated on the Liquid Glass popover in **both**
/// appearances (R-depth). The trick is that "elevation" is drawn differently per scheme:
///
/// - **Dark**: a lit top rim fading to a *dark* bottom rim over a subtle vertical fill, plus a
///   shadow deep enough to read on the popover shell — the glassy raised-tile look.
///   (R2C1: this used to say "fading down the perimeter", and the code faded to
///   `white 0.06`, which measured ~50 against a 37 card on a 27 shell — the brightest
///   boundary on the card was its *bottom* edge, so the tile read as an inlay, lit from
///   below. The shadow made it worse by rendering nothing at all: `black 0.42` over a
///   `#1B1B1B` shell sampled 27 on every side, identical to bare shell.)
/// - **Light**: a brighter near-opaque fill with a soft shadow and a fine bottom-weighted
///   hairline. A white top-rim would vanish on a light surface, so light mode leans on the
///   shadow + fill contrast instead.
///
/// Content stays a plain tile (never a second `.glassEffect`), so glass-on-glass never muddies
/// the popover (UI-07); glass is reserved for the shell + controls.
enum RaisedTileSurface {
    case glass
    case opaque
}

struct RaisedTile: ViewModifier {
    var cornerRadius: CGFloat = 12
    var surface: RaisedTileSurface = .glass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.headroomTuning) private var t

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        let highLegibility = reduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let fillColors = highLegibility ? solidFillColors : fillColors(dark: dark)
        content
            .background(
                shape
                    .fill(LinearGradient(
                        colors: fillColors,
                        startPoint: .top, endPoint: .bottom))
                    // R2C1: dark's shadow is 0.6 @ r10 y3, not 0.42 @ r7 y1 — the old one
                    // measured identical to bare shell at every sample, so the card had no
                    // shadow at all. Light is unchanged (211 shadow vs 225 shell, correct).
                    .shadow(
                        color: .black.opacity(dark ? t.darkShadowOpacity : (surface == .opaque ? 0.09 : t.lightShadowOpacity)),
                        radius: dark ? t.darkShadowRadius : t.lightShadowRadius,
                        y: dark ? t.darkShadowY : t.lightShadowY
                    )
            )
            .overlay(
                // One gradient stroke does both jobs, and after R2C1 both schemes do it the
                // same way: a lit top edge fading to a dark bottom rim. Apple's dark grouped
                // tables and Raycast's dark rows are built this way for the same reason —
                // Apple §12, a bigger surface reads as thicker, lit from above.
                shape.strokeBorder(
                    highLegibility
                        ? LinearGradient(colors: [Color(nsColor: .separatorColor), Color(nsColor: .separatorColor)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(
                            colors: dark
                                ? [Color.white.opacity(t.darkRimTop), Color.black.opacity(t.darkRimBottom)]
                                : [Color.white.opacity(t.lightRimTop), Color.black.opacity(t.lightRimBottom)],
                            startPoint: .top, endPoint: .bottom),
                    lineWidth: highLegibility ? 1.2 : 1)
            )
    }

    private var solidFillColors: [Color] {
        [Color(nsColor: .controlBackgroundColor), Color(nsColor: .controlBackgroundColor)]
    }

    private func fillColors(dark: Bool) -> [Color] {
        switch (surface, dark) {
        case (.glass, true):
            [Color.white.opacity(t.darkFillTop), Color.white.opacity(t.darkFillBottom)]
        case (.glass, false):
            // Near-opaque white (0.92/0.80 → 0.98/0.94, Jul 2026): with the light shell
            // tinted, the translucent fill let the gray bleed through and the card-vs-shell
            // step collapsed to ~6% luminance (dark mode's is ~36%). Full-white cards on
            // the gray shell is the System Settings idiom; shadows + hairline stay as-is.
            [Color.white.opacity(t.lightFillTop), Color.white.opacity(t.lightFillBottom)]
        case (.opaque, true):
            [Color.white.opacity(0.08), Color.white.opacity(0.05)]
        case (.opaque, false):
            [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor).opacity(0.96)]
        }
    }
}

extension View {
    /// Elevate a content tile on the popover glass, adapting to light/dark. See `RaisedTile`.
    func raisedTile(cornerRadius: CGFloat = 12, surface: RaisedTileSurface = .glass) -> some View {
        modifier(RaisedTile(cornerRadius: cornerRadius, surface: surface))
    }
}
