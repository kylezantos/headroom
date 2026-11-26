import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif

/// 2A (Kyle, 2026-11-24): the Settings rename field's recipe.
enum RenameFieldStyle {
    static let cornerRadius: CGFloat = 6
    /// The resting name's approach fill (the value the field used before 2A).
    static let hoverFill: Double = 0.06
    /// The editing field's 1pt ink ring.
    static let ringOpacity: Double = 0.28
    /// The field never shrinks below a short name, so an emptied field stays a target.
    static let minWidth: CGFloat = 64
    /// Where the pencil sits in the row's 16pt leading gutter (`AccountRowMetrics.leadingInset`).
    static let pencilGutterOffset: CGFloat = 14
    /// How long "Saved" holds before it fades out.
    static let savedHold: Duration = .milliseconds(1400)
}

/// "✓ Saved": a small check and the word, 3pt apart.
struct RenameSavedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 9, weight: .semibold))
            configuration.title
        }
    }
}

/// 2A: ends text editing on any click outside the field being edited. AppKit only moves
/// focus to views that accept first responder, so a click on blank window space or on a
/// plain button leaves a text field focused and the focus-loss commit never runs. While
/// active, a local monitor sees every mouse-down first and calls `onOutsideClick`; the
/// event still goes on to whatever was clicked.
struct OutsideClickEndsEditing: ViewModifier {
    let isActive: Bool
    let onOutsideClick: @MainActor () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                if active { install() } else { remove() }
            }
            .onDisappear { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        let action = onOutsideClick
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            MainActor.assumeIsolated {
                if !Self.isInsideEditingField(event) { action() }
            }
            return event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Inside means on the focused field or the few points of padding drawn around it.
    @MainActor private static func isInsideEditingField(_ event: NSEvent) -> Bool {
        guard let window = event.window,
              let editor = window.firstResponder as? NSTextView,
              editor.isFieldEditor,
              let field = editor.delegate as? NSView
        else { return false }
        let frame = field.convert(field.bounds, to: nil).insetBy(dx: -8, dy: -5)
        return frame.contains(event.locationInWindow)
    }
}
