#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI

/// A quiet button style that finally makes the popover's controls *feel* clickable
/// (UI-06). The stock `.plain` buttons had no hover, no pressed state, and no pointer
/// cursor, so they read as static labels. This adds a subtle rounded highlight on hover and
/// a deeper one while pressed. Purely input-driven (no idle motion), so it stays inside the
/// no-pulsing rule.
///
/// PA11b narrowed its remit to **glyph-only** controls — gear, `+`, `…`, copy, trash, reset,
/// the disclosure chevrons. Every text-labelled button in a card moved to
/// `SetupChipButtonStyle`'s resting container. A borderless icon in a title or toolbar row is
/// the macOS HIG's own convention; a borderless *word* beside prose is not, which is the trade
/// B3H had made and PA11b reversed. The footer's Refresh and Quit are the exception: native
/// `.bordered` at the small size (CA-P6), because a custom `ButtonStyle` label there was
/// rehosted upside down after an appearance change.
struct HoverButtonStyle: ButtonStyle {
    /// R2B3: one radius *ratio*, not one radius. The five call sites pad the same style to
    /// pills between 18×18 and 32×32, so a fixed 7pt corner read as 0.39 of the small pill
    /// and 0.22 of the large one — the same object with two different roundnesses. Deriving
    /// the corner from the pill's own short side keeps every glyph pill the same shape, and
    /// keeps it that way when a call site changes its padding.
    static let pillRadiusRatio: CGFloat = 0.30

    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 3
    var hoverForegroundColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        hoverForegroundColor: hoverForegroundColor)
    }

    private struct HoverButtonBody: View {
        let configuration: Configuration
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let hoverForegroundColor: Color?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            // S3A: hover in fast, out slow — the pill is there when the pointer arrives and
            // lingers a beat when it leaves. Press lands inside 100ms, release returns on settle.
            let hoverAnimation = hovering ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut
            let pressAnimation = configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle
            styledLabel
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    // R2B3: the pill measures itself so its corner stays a constant fraction
                    // of its short side. A background never proposes a size of its own, so
                    // reading the geometry here costs no layout.
                    GeometryReader { proxy in
                        let shape = RoundedRectangle(
                            cornerRadius: min(proxy.size.width, proxy.size.height)
                                * HoverButtonStyle.pillRadiusRatio,
                            style: .continuous
                        )
                        ZStack {
                            shape.fill(Color.primary.opacity(0.09))
                                .opacity(hovering && !configuration.isPressed ? 1 : 0)
                            shape.fill(Color.primary.opacity(0.16))
                                .opacity(configuration.isPressed ? 1 : 0)
                        }
                    }
                }
                // S2A: the pill and the hover ink are opacity only, so they keep their timing
                // under Reduce Motion. They carry their own modifiers because the scale below
                // is movement and has to resolve independently of them.
                .animation(HeadroomMotion.resolved(hoverAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: hovering)
                .animation(HeadroomMotion.resolved(pressAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                // Extend the tap target 8pt past the visible pill to clear the 40pt floor
                // (7pt left the default chip at ≈38pt), then pull that padding back out of
                // layout so neighbouring controls don't shift — SwiftUI's equivalent of a
                // hit-area pseudo-element. The visible chip is unchanged; only the
                // invisible interaction region grows.
                .padding(8)
                .contentShape(Rectangle())
                .padding(-8)
                // Tactile press: PB12's one `pressScale` for every button style in the app.
                // S2A: scaling is movement, so Reduce Motion drops it outright while the
                // pill above still cross-fades — still input-driven, no idle motion, so it
                // stays inside the no-pulsing rule.
                .scaleEffect(configuration.isPressed ? HeadroomMotion.pressScale : 1)
                .animation(HeadroomMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        @ViewBuilder private var styledLabel: some View {
            if let hoverForegroundColor {
                configuration.label
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 0 : 1)
                    .overlay {
                        configuration.label
                            .foregroundStyle(hoverForegroundColor)
                            .opacity(hovering ? 1 : 0)
                            .accessibilityHidden(true)
                    }
            } else {
                configuration.label
            }
        }
    }
}
