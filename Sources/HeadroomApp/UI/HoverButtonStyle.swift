import SwiftUI

/// A quiet button style that finally makes the popover's controls *feel* clickable
/// (UI-06). The stock `.plain` text buttons had no hover, no pressed state, and no
/// pointer cursor, so gear/Refresh/Quit/Copy read as static labels. This adds a subtle
/// rounded highlight on hover and a deeper one while pressed. Purely input-driven
/// (no idle motion), so it stays inside the no-pulsing rule.
struct HoverButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding)
    }

    private struct HoverButtonBody: View {
        let configuration: Configuration
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            configuration.label
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(shape.fill(Color.primary.opacity(
                    configuration.isPressed ? 0.16 : (hovering ? 0.09 : 0))))
                // Extend the tap target 8pt past the visible pill to clear the 40pt floor
                // (7pt left the default chip at ≈38pt), then pull that padding back out of
                // layout so neighbouring controls don't shift — SwiftUI's equivalent of a
                // hit-area pseudo-element. The visible chip is unchanged; only the
                // invisible interaction region grows.
                .padding(8)
                .contentShape(Rectangle())
                .padding(-8)
                // Tactile press: a subtle 0.96 scale (never below 0.95, which reads as
                // exaggerated). An interruptible value animation, so releasing mid-press
                // springs back smoothly rather than snapping — still input-driven, no idle
                // motion, so it stays inside the no-pulsing rule.
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .onHover { hovering = $0 }
                .animation(HeadroomMotion.press, value: hovering)
                .animation(HeadroomMotion.press, value: configuration.isPressed)
        }
    }
}
