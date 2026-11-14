#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI

/// R2M9: the three copy-to-clipboard glyph buttons wrote the pasteboard and changed nothing
/// on screen — once the 100ms press scale returned there was no evidence the click had done
/// anything. This is the one click in the app with zero feedback, and copy→check is the
/// answer every comparable tool already ships.
///
/// Three rules the sites had been getting wrong individually:
/// - the check only appears on a **successful** pasteboard write; `NSPasteboard.setString`
///   returns `Bool` and every call site was discarding it, so a failed copy would have
///   confirmed itself;
/// - the hold is a sleeping `Task`, not `DispatchQueue.asyncAfter` (M8A's pattern) — it is
///   cancellable, so a second copy inside the hold restarts the window instead of letting
///   the first timer clear the check out from under it;
/// - the accessibility label carries the state, because the glyph is the only thing that
///   changes and VoiceOver never sees it.
///
/// Deliberately not `.symbolEffect`: the house motion vocabulary contains crossfades,
/// movement and two springs, and a symbol-replace effect is none of them. CA-M7 builds the
/// swap from those instead.
struct CopyFeedbackButton: View {
    /// Performs the pasteboard write and reports whether it landed.
    let copy: () -> Bool
    /// Resting label, used for both the tooltip and the idle accessibility label.
    let label: String
    var confirmationLabel: String = "Copied"
    var horizontalPadding: CGFloat = 2
    var verticalPadding: CGFloat = 2

    @State private var copied = false
    @State private var hold: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Long enough to read without becoming a state the user has to wait out.
    private static let holdDuration = Duration.milliseconds(1200)

    var body: some View {
        Button(action: perform) {
            // Both glyphs are always laid out inside the fixed 22×22 slot, so the row beside
            // it never reflows.
            // CA-M7 (MOT-07): two glyphs of different shape crossfading at one scale read as a
            // double-exposed smudge. Now the outgoing glyph shrinks into the reveal blur as it
            // fades and the incoming one resolves out of it: a swap, on house tokens.
            ZStack {
                swapGlyph("doc.on.doc", shown: !copied)
                swapGlyph("checkmark", shown: copied)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(HoverButtonStyle(horizontalPadding: horizontalPadding,
                                      verticalPadding: verticalPadding))
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(copied ? confirmationLabel : label)
    }

    /// CA-M7 (MOT-07): an icon swap recedes deep, to half size behind a 2pt blur, not the
    /// 0.97 / 1.5pt reveal used for settling rows. One call site, so these stay local
    /// (DESIGN.md rule 2).
    private static let swapScale: CGFloat = 0.5
    private static let swapBlur: CGFloat = 2

    /// CA-M7: scale and blur are movement on `valueSpring`, so Reduce Motion drops them and
    /// keeps today's 200ms crossfade (S2A).
    private func swapGlyph(_ systemName: String, shown: Bool) -> some View {
        let receded = !shown && !reduceMotion
        return Image(systemName: systemName)
            .scaleEffect(receded ? Self.swapScale : 1)
            .blur(radius: receded ? Self.swapBlur : 0)
            .animation(HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                       value: copied)
            .opacity(shown ? 1 : 0)
            .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                       value: copied)
    }

    private func perform() {
        guard copy() else { return }
        hold?.cancel()
        copied = true
        hold = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDuration)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
