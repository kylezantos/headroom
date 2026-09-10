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
/// movement and two springs, and a symbol-replace effect is none of them.
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
            // Both glyphs are always laid out inside the fixed 22×22 slot, so the swap is a
            // pure opacity crossfade and the row beside it never reflows.
            ZStack {
                Image(systemName: "doc.on.doc").opacity(copied ? 0 : 1)
                Image(systemName: "checkmark").opacity(copied ? 1 : 0)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(HoverButtonStyle(horizontalPadding: horizontalPadding,
                                      verticalPadding: verticalPadding))
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(copied ? confirmationLabel : label)
    }

    private func perform() {
        guard copy() else { return }
        hold?.cancel()
        // S2A: opacity only, so the confirmation keeps its 200ms under Reduce Motion.
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
            copied = true
        }
        hold = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDuration)
            guard !Task.isCancelled else { return }
            withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
                copied = false
            }
        }
    }
}
