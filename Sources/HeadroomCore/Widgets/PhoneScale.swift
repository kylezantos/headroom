import Foundation

/// KTD3 (iOS parity plan): the phone sets the popover's own rows one Dynamic Type unit up.
/// One multiplier, applied to the popover ramp's type, spacing and measured reservations
/// alike, so the shared rows keep their proportions; it is never `minimumScaleFactor`.
///
/// Core holds only the numbers. The SwiftUI host owns its single
/// `@ScaledMetric(relativeTo: .body)` factor seeded with `defaultFactor`, and passes the
/// result to the shared rows' `scale` parameter; the Mac passes `popover`.
public enum PhoneScale {
    /// The Mac popover's own proportions. Every shared row's measurements at this scale are
    /// the ones the popover has always rendered.
    public static let popover: Double = 1.0
    /// The phone's factor at the default text size ("Popover proportions, one step up").
    public static let defaultFactor: Double = 1.15

    /// U8: where the phone stops growing — the factor at xxxLarge (body 23pt over the default
    /// 17pt). The popover's Micro row reserves a gauge, a "100%" column and two insets on one
    /// line, so past this the shared rows need more than a 390pt phone has and the whole
    /// screen widens off the glass. Accessibility sizes keep the xxxLarge layout; Reduce
    /// Motion and accessibility stay best-effort (AGENTS.md).
    public static let maximumFactor: Double = defaultFactor * 23 / 17

    /// The host's `@ScaledMetric` value, held to the range the shared rows fit in.
    public static func clamped(_ factor: Double) -> Double {
        guard factor.isFinite else { return defaultFactor }
        return min(max(factor, popover), maximumFactor)
    }
}
