import SwiftUI

/// The house motion vocabulary. Every animation in the app target reaches for one of these;
/// no view declares its own curve, duration, or spring. Decision anchors (`S1A`, `S2A`,
/// `S3A`, `M1A`, `M7A`, `SM1`–`SM3`) live in `docs/plans/2026-09-04-002-feat-subtle-motion-system-plan.md`.
enum HeadroomMotion {
    // MARK: Curves — one family (S1A). The stock `easeOut` press curve was retired because
    // built-in curves are too weak to read at 100–200ms.

    static let settle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
    static let quickSettle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.12)

    /// S3A: feedback belongs on pointer-down, so the pressed state lands inside 100ms.
    /// Release returns on `settle`, so the pair is `isPressed ? pressDown : settle`.
    static let pressDown = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.10)

    // MARK: Press geometry (PB12)

    /// PB12: how far a pressed control shrinks. It was 0.96 in `HoverButtonStyle` and 0.98 in
    /// the three chip/CTA styles, so pressing two neighbouring buttons gave two different
    /// amounts of give. One number, and 0.96 is the one that reads — 0.98 is close enough to
    /// nothing that a small chip barely registers the press. Never below 0.95, which reads as
    /// exaggerated.
    static let pressScale: CGFloat = 0.96

    /// S3A: hover in fast, out slow — the pill should be there when the pointer arrives and
    /// linger a beat when it leaves. `hoverOut` is a zero-bounce spring, not a bezier.
    static let hoverIn = quickSettle
    static let hoverOut = Animation.smooth(duration: 0.18, extraBounce: 0)

    // MARK: Springs — critically damped. Apple reserves bounce for motion that inherits a
    // gesture's momentum, and since PS5 nothing here carries any.

    /// M1A: a bar that represents a value must never overshoot it, even by a hair, so the
    /// old `dampingFraction: 0.9` became `1.0`. Drives fill length, numeral roll, and
    /// severity colour together — one cause, one motion.
    static let valueSpring = Animation.spring(response: 0.3, dampingFraction: 1.0)

    /// M7A: account-list reorders. Slower than `valueSpring` because a row travels ~30pt, and
    /// a spring so a second click mid-flight retargets instead of restarting.
    static let reorder = Animation.spring(response: 0.35, dampingFraction: 1.0)

    // MARK: Settings pass (2026-09-22)

    /// SM1: the selection plate travelling between swatches in one picker row. Critically
    /// damped for the same reason as `valueSpring` — the plate names a value, so it lands on
    /// it without overshoot. A spring, so a second click mid-flight retargets.
    static let selectionTravel = Animation.spring(response: 0.3, dampingFraction: 1.0)

    /// SM2: M6B's pane dissolve, split so the two rooms never read as a double exposure. The
    /// outgoing pane leaves in 80ms; the incoming one resolves out of a slight blur on the
    /// house curve. Still nothing travels.
    static let paneIn = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
    static let paneOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.08)

    /// SM3: neighbours making room while a pill card is dragged. Quicker than `reorder`:
    /// the gap has to open while the pointer is still crossing, or it reads as lag.
    static let dragNudge = Animation.spring(response: 0.26, dampingFraction: 1.0)

    /// SM3: the dropped card settling into its gap. PS5 (Kyle, 2026-09-24): critically
    /// damped now. The card lands on an exact slot and the store commits the moment it
    /// arrives, so any overshoot was cut off at the commit and read as a jolt.
    static let dragSettle = Animation.spring(response: 0.32, dampingFraction: 1.0)

    /// PS6: a pill card changing form between the shelf and the menu bar once it has landed —
    /// the card's height, the rows' heights, and its parts arriving. A spring so a second
    /// drop mid-morph retargets; critically damped because it is a layout change, not a
    /// gesture's momentum.
    static let cardMorph = Animation.spring(response: 0.3, dampingFraction: 1.0)

    // MARK: Arrival timing (M9A)

    /// M9A (Kyle, 2026-09-11): the once-per-launch count-up fires from the row's `onAppear`,
    /// which is the same instant `MenuBarExtra(.window)` is still animating its window in — so
    /// on a first open the front half of the sweep played behind an un-settled popover and the
    /// user never saw it. One short beat lets the window arrive first; the count-up then plays
    /// fully in view. Deliberately brief — just long enough to clear the open, never long
    /// enough to hold the real number back. Applies only to the staged arrival; reopens, live
    /// updates, and Reduce Motion still land immediately.
    static let arrivalDelay: Duration = .milliseconds(250)

    // MARK: Compatibility names — retire as call sites migrate to the S3A pairs above.

    static let hover = hoverOut
    static let press = pressDown

    // MARK: Reduce Motion (S2A)

    /// What an animation does to the eye. `crossfade` is opacity or colour only; `movement`
    /// is anything that travels, scales, blurs, resizes, or rolls digits.
    enum Kind {
        case crossfade
        case movement
    }

    /// S2A: Reduce Motion is a gentler equivalent, not silence. Crossfades keep their timing;
    /// movement becomes instant. A modifier that drives both kinds must be split so each
    /// property resolves on its own.
    static func resolved(_ animation: Animation, _ kind: Kind, reduceMotion: Bool) -> Animation? {
        reduceMotion && kind == .movement ? nil : animation
    }

    /// S2A companion for `contentTransition`: the digit roll is movement, so Reduce Motion
    /// swaps the text outright. `value` gives the roll its direction (M2A: countdowns roll
    /// down, "ago" labels roll up).
    static func numericText(value: Double, reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .identity : .numericText(value: value)
    }

    static func numericText(reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .identity : .numericText()
    }
}
