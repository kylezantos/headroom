import AppKit
#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif

extension HeadroomMotion {
    /// The house curve (S1A) for AppKit's animator, built from `houseCurve` (CA-F1). Computed:
    /// `CAMediaTimingFunction` is not `Sendable`, so it can't be a stored static under strict
    /// concurrency.
    static var windowCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(
            controlPoints: Float(houseCurve.x1), Float(houseCurve.y1),
            Float(houseCurve.x2), Float(houseCurve.y2))
    }

    // MARK: Keyboard-initiated changes (KB1)

    /// KB1 (2026-09-25 motion audit): a change the keyboard asked for lands instantly —
    /// someone arrowing through the Settings sidebar or pressing ⌘, is moving faster than
    /// any animation, and each replay makes them wait on it (Emil's frequency rule). Read at
    /// the moment the change is made, from the event AppKit is dispatching.
    @MainActor static var isKeyboardInitiated: Bool {
        NSApp.currentEvent?.type == .keyDown
    }

}
