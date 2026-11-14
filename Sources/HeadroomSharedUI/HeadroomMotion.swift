import SwiftUI

/// The house motion vocabulary. Every animation in the app target reaches for one of these;
/// no view declares its own curve, duration, or spring. Decision anchors (`S1A`, `S2A`,
/// `S3A`, `M1A`, `M7A`, `SM1`–`SM3`) come from the subtle motion system plan.
public enum HeadroomMotion {
    // MARK: Curves — one family (S1A). The stock `easeOut` press curve was retired because
    // built-in curves are too weak to read at 100–200ms.

    public static let settle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
    public static let quickSettle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.12)

    /// S3A: feedback belongs on pointer-down, so the pressed state lands inside 100ms.
    /// Release returns on `settle`, so the pair is `isPressed ? pressDown : settle`.
    public static let pressDown = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.10)

    // MARK: Press geometry (PB12)

    /// PB12: how far a pressed control shrinks. It was 0.96 in `HoverButtonStyle` and 0.98 in
    /// the three chip/CTA styles, so pressing two neighbouring buttons gave two different
    /// amounts of give. One number, and 0.96 is the one that reads — 0.98 is close enough to
    /// nothing that a small chip barely registers the press. Never below 0.95, which reads as
    /// exaggerated.
    public static let pressScale: CGFloat = 0.96

    /// S3A: hover in fast, out slow — the pill should be there when the pointer arrives and
    /// linger a beat when it leaves. `hoverOut` is a zero-bounce spring, not a bezier.
    public static let hoverIn = quickSettle
    public static let hoverOut = Animation.smooth(duration: 0.18, extraBounce: 0)

    /// Row hover (Kyle, 2026-10-03: the account row's hover "has a sudden flash"). `hoverIn`
    /// suits a glyph pill: its strong ease-out lands ~80% of the change in the first 30ms,
    /// which on a full-width row whose fill, edge, sentence and glyph all brighten together
    /// reads as a blink. A colour change wants a plain `ease` (Emil Kowalski's rule for hover
    /// and colour), still in quicker than out, per S3A.
    public static let rowHoverIn = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16)
    public static let rowHoverOut = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.24)

    // MARK: Springs — critically damped. Apple reserves bounce for motion that inherits a
    // gesture's momentum, and since PS5 nothing here carries any.

    /// M1A: a bar that represents a value must never overshoot it, even by a hair, so the
    /// old `dampingFraction: 0.9` became `1.0`. Drives fill length, numeral roll, and
    /// severity colour together — one cause, one motion.
    public static let valueSpring = Animation.spring(response: 0.3, dampingFraction: 1.0)

    /// M7A: account-list reorders. Slower than `valueSpring` because a row travels ~30pt, and
    /// a spring so a second click mid-flight retargets instead of restarting.
    public static let reorder = Animation.spring(response: 0.35, dampingFraction: 1.0)

    // MARK: Settings pass (2026-09-22)

    /// SM1: the selection plate travelling between swatches in one picker row. Critically
    /// damped for the same reason as `valueSpring` — the plate names a value, so it lands on
    /// it without overshoot. A spring, so a second click mid-flight retargets.
    public static let selectionTravel = Animation.spring(response: 0.3, dampingFraction: 1.0)

    /// SM2: M6B's pane dissolve, split so the two rooms never read as a double exposure. The
    /// outgoing pane leaves in 80ms; the incoming one resolves out of a slight blur on the
    /// house curve. Still nothing travels.
    public static let paneIn = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
    public static let paneOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.08)

    /// SM3: neighbours making room while a pill card is dragged. Quicker than `reorder`:
    /// the gap has to open while the pointer is still crossing, or it reads as lag.
    public static let dragNudge = Animation.spring(response: 0.26, dampingFraction: 1.0)

    /// SM3: the dropped card settling into its gap. PS5 (Kyle, 2026-09-24): critically
    /// damped now. The card lands on an exact slot and the store commits the moment it
    /// arrives, so any overshoot was cut off at the commit and read as a jolt.
    public static let dragSettle = Animation.spring(response: 0.32, dampingFraction: 1.0)

    /// PS6: a pill card changing form between the shelf and the menu bar once it has landed —
    /// the card's height, the rows' heights, and its parts arriving. A spring so a second
    /// drop mid-morph retargets; critically damped because it is a layout change, not a
    /// gesture's momentum.
    public static let cardMorph = Animation.spring(response: 0.3, dampingFraction: 1.0)

    /// PS6 → MB1 (Kyle, 2026-09-25: the menu-bar switch's blur and fade "too long"). A card
    /// part arriving used to ride `cardMorph` after a 50ms beat — a spring that reads as
    /// ~450ms before the part is sharp. Now it resolves in 160ms on the house curve after a
    /// 30ms beat, so it still lands just behind the card's growth but finishes inside it. The
    /// part leaving goes in `paneOut`'s 80ms: exits are the quieter half.
    public static let partIn = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16).delay(0.03)
    public static let partOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.08)

    // MARK: Arrival timing (M9A)

    /// M9A (Kyle, 2026-09-11): the once-per-launch count-up fires from the row's `onAppear`,
    /// which is the same instant `MenuBarExtra(.window)` is still animating its window in — so
    /// on a first open the front half of the sweep played behind an un-settled popover and the
    /// user never saw it. One short beat lets the window arrive first; the count-up then plays
    /// fully in view. Deliberately brief — just long enough to clear the open, never long
    /// enough to hold the real number back. Applies only to the staged arrival; reopens, live
    /// updates, and Reduce Motion still land immediately.
    ///
    /// AR1 (Kyle, 2026-09-25): 250 → 350ms, so the draw-in is felt "just a tad more" without
    /// getting in the way. A beat the eye can use to land on the popover, still short enough
    /// that an empty meter never reads as missing data.
    public static let arrivalDelay: Duration = .milliseconds(350)

    /// AR1: the staged arrival's own spring — `valueSpring` a third slower, so the first
    /// draw-in is felt. Arrival only: a live update lands on `valueSpring` so a changed number
    /// never lags the data. Critically damped for the same reason (M1A).
    public static let arrivalSpring = Animation.spring(response: 0.4, dampingFraction: 1.0)

    // MARK: Window handoff (SW1)

    /// SW1 (Kyle, 2026-09-25: opening and closing Settings "feels clunky"). AppKit shows a
    /// SwiftUI `Window` with no entrance at all, and Headroom then moved it onto the active
    /// screen a tick later, so the window popped in and could visibly jump. The window now
    /// arrives hidden, is placed, and resolves in on the house curve; the popover it came from
    /// fades out over `windowOutDuration` at the same time, so the handoff is one crossfade. Closing uses
    /// AppKit's utility-window fade (~160ms, measured), shorter than the entrance so the exit
    /// is the quieter half. Opacity only, so Reduce Motion keeps it (S2A).
    public static let windowInDuration: TimeInterval = 0.26
    public static let windowOutDuration: TimeInterval = 0.12

    // MARK: Compatibility names — retire as call sites migrate to the S3A pairs above.

    public static let hover = hoverOut
    public static let press = pressDown

    // MARK: Reduce Motion (S2A)

    /// What an animation does to the eye. `crossfade` is opacity or colour only; `movement`
    /// is anything that travels, scales, blurs, resizes, or rolls digits.
    public enum Kind {
        case crossfade
        case movement
    }

    /// S2A: Reduce Motion is a gentler equivalent, not silence. Crossfades keep their timing;
    /// movement becomes instant. A modifier that drives both kinds must be split so each
    /// property resolves on its own.
    public static func resolved(_ animation: Animation, _ kind: Kind, reduceMotion: Bool) -> Animation? {
        reduceMotion && kind == .movement ? nil : animation
    }

    /// RM1 (2026-09-25 motion audit): a fade that keeps its timing under Reduce Motion by
    /// carrying its own animation. An `.animation` scope animates everything in its
    /// transaction, so a scope resolved as `.crossfade` to save a fade under Reduce Motion
    /// also kept the height change beside it. Such scopes now resolve as `.movement` and the
    /// fade rides the transition. Outside Reduce Motion this is a plain `.opacity`, so the
    /// scope still drives it exactly as before.
    public static func fade(_ animation: Animation, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? AnyTransition.opacity.animation(animation) : .opacity
    }

    /// S2A companion for `contentTransition`: the digit roll is movement, so Reduce Motion
    /// swaps the text outright. `value` gives the roll its direction (M2A: countdowns roll
    /// down, "ago" labels roll up).
    public static func numericText(value: Double, reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .identity : .numericText(value: value)
    }

    public static func numericText(reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .identity : .numericText()
    }
}
