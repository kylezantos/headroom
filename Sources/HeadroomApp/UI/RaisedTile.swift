import AppKit
import HeadroomCore
import SwiftUI
#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif

/// A raised content tile. Two surfaces, each with its own recipe (CA-S1, KTD4):
///
/// - **`.glass`**, the popover's cards on the Liquid Glass shell.
///   - **Dark** (CA-P2): one layer per job, the setup chip's CMM3 recipe at card scale. An
///     even ring holds all four edges, a 1pt inset lip catches the light along the top and
///     fades out down the sides, and two tight shadows seat the card on the shell. This
///     overturns R2C1's single white 0.20 → black 0.22 gradient stroke: its top was the
///     brightest line in the popover (rule 8 caps a dark rim at 0.15) while the sides and the
///     bottom dissolved, a bright lid on a box with no floor.
///   - **Light**: a near-opaque white fill with a soft shadow and a fine bottom-weighted
///     hairline. A white top rim would vanish on a light surface, so light leans on the
///     shadow and the fill step instead. Unchanged by CA-P2.
/// - **`.opaque`**, Settings' tiles (CA-S1). Flat: no gradient, a translucent 1pt ring, two
///   tight shadows in light and none in dark, where a shadow on a dark canvas renders as
///   nothing. Settings used to inherit the glass card's R2C1 rim and gradient, which faded
///   the light tile's foot into the pane and gave the dark tile the 0.20 lid.
///
/// Increase Contrast and Reduce Transparency keep their solid fill and separator stroke.
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
        content
            .background {
                if highLegibility {
                    highLegibilityTile(shape: shape, dark: dark)
                } else {
                    switch (surface, dark) {
                    case (.glass, true): darkGlassTile(shape: shape)
                    case (.glass, false): lightGlassTile(shape: shape)
                    case (.opaque, true): darkOpaqueTile(shape: shape)
                    case (.opaque, false): lightOpaqueTile(shape: shape)
                    }
                }
            }
    }

    /// CA-P2: ring, masked lip, contact shadow, ambient shadow. The lip mask is the setup
    /// chip's (`SetupChipButtonStyle`), so it fades rather than leaving a ledge.
    private func darkGlassTile(shape: RoundedRectangle) -> some View {
        shape
            .fill(LinearGradient(
                colors: [Color.white.opacity(t.darkFillTop), Color.white.opacity(t.darkFillBottom)],
                startPoint: .top, endPoint: .bottom))
            .overlay {
                shape
                    .inset(by: 1)
                    .strokeBorder(Color.white.opacity(t.darkRimTop), lineWidth: 1)
                    .mask {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.55)
                        )
                    }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(t.darkRing), lineWidth: 1))
            .shadow(color: .black.opacity(t.darkShadowOpacity), radius: t.darkShadowRadius, y: t.darkShadowY)
            .shadow(color: .black.opacity(t.darkAmbientShadowOpacity), radius: t.darkAmbientShadowRadius, y: t.darkAmbientShadowY)
    }

    private func lightGlassTile(shape: RoundedRectangle) -> some View {
        // Near-opaque white (0.92/0.80 → 0.98/0.94, Jul 2026): with the light shell tinted,
        // the translucent fill let the gray bleed through and the card-vs-shell step collapsed
        // to ~6% luminance. Full-white cards on the gray shell is the System Settings idiom.
        shape
            .fill(LinearGradient(
                colors: [Color.white.opacity(t.lightFillTop), Color.white.opacity(t.lightFillBottom)],
                startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(t.lightShadowOpacity), radius: t.lightShadowRadius, y: t.lightShadowY)
            .overlay(shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(t.lightRimTop), Color.black.opacity(t.lightRimBottom)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 1))
    }

    /// CA-S1: a white 0.06 panel with a 0.09 ring and nothing else. Settings' window canvas
    /// is dark enough that any shadow under it samples as bare canvas.
    private func darkOpaqueTile(shape: RoundedRectangle) -> some View {
        shape
            .fill(Color.white.opacity(HeadroomTileEdgeValues.darkOpaqueFillOpacity))
            .overlay(shape.strokeBorder(
                Color.white.opacity(HeadroomTileEdgeValues.darkOpaqueRingOpacity), lineWidth: 1))
    }

    /// CA-S1: a flat white panel on the grey pane, a black 0.07 ring and two tight shadows
    /// (the audit's `0 1px 1px` at 0.05 and `0 2px 4px` at 0.04; SwiftUI's radius is half a
    /// CSS blur).
    private func lightOpaqueTile(shape: RoundedRectangle) -> some View {
        shape
            .fill(Color(nsColor: .controlBackgroundColor))
            .shadow(color: .black.opacity(0.05), radius: 0.5, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 2)
            .overlay(shape.strokeBorder(
                Color.black.opacity(HeadroomTileEdgeValues.lightOpaqueRingOpacity), lineWidth: 1))
    }

    /// Increase Contrast / Reduce Transparency: unchanged by the craft audit, so it keeps the
    /// literals it drew before CA-P2 retuned the dark glass shadow.
    private func highLegibilityTile(shape: RoundedRectangle, dark: Bool) -> some View {
        shape
            .fill(Color(nsColor: .controlBackgroundColor))
            .shadow(
                color: .black.opacity(dark ? 0.6 : (surface == .opaque ? 0.09 : t.lightShadowOpacity)),
                radius: dark ? 10 : t.lightShadowRadius,
                y: dark ? 3 : t.lightShadowY
            )
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1.2))
    }
}

extension View {
    /// Elevate a content tile on the popover glass, adapting to light/dark. See `RaisedTile`.
    func raisedTile(cornerRadius: CGFloat = 12, surface: RaisedTileSurface = .glass) -> some View {
        modifier(RaisedTile(cornerRadius: cornerRadius, surface: surface))
    }
}
