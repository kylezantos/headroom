import SwiftUI

/// A quiet button style that finally makes the popover's controls *feel* clickable
/// (UI-06). The stock `.plain` text buttons had no hover, no pressed state, and no
/// pointer cursor, so gear/Refresh/Quit/Copy read as static labels. This adds a subtle
/// rounded highlight on hover and a deeper one while pressed. Purely input-driven
/// (no idle motion), so it stays inside the no-pulsing rule.
struct HoverButtonStyle: ButtonStyle {
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
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            // S3A: hover in fast, out slow — the pill is there when the pointer arrives and
            // lingers a beat when it leaves. Press lands inside 100ms, release returns on settle.
            let hoverAnimation = hovering ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut
            let pressAnimation = configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle
            styledLabel
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    ZStack {
                        shape.fill(Color.primary.opacity(0.09))
                            .opacity(hovering && !configuration.isPressed ? 1 : 0)
                        shape.fill(Color.primary.opacity(0.16))
                            .opacity(configuration.isPressed ? 1 : 0)
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
                // Tactile press: a subtle 0.96 scale (never below 0.95, which reads as
                // exaggerated). S2A: scaling is movement, so Reduce Motion drops it outright
                // while the pill above still cross-fades — still input-driven, no idle
                // motion, so it stays inside the no-pulsing rule.
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
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

extension View {
    /// A deliberately delayed help label for small pointer-only affordances. SwiftUI's
    /// native `help` modifier does not expose its delay, so the API-spend action uses this
    /// local presentation to guarantee a full second before appearing.
    func delayedHelp(_ text: String, delay: Duration = .seconds(1)) -> some View {
        modifier(DelayedHelpModifier(text: text, delay: delay))
    }
}

private struct DelayedHelpModifier: ViewModifier {
    let text: String
    let delay: Duration

    @State private var hovering = false
    @State private var showingHelp = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                hovering = isHovering
                if !isHovering {
                    showingHelp = false
                }
            }
            .task(id: hovering) {
                guard hovering else { return }

                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                guard hovering else { return }
                showingHelp = true
            }
            .overlay(alignment: .topTrailing) {
                if showingHelp {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                        .offset(y: -29)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .zIndex(showingHelp ? 1 : 0)
    }
}
