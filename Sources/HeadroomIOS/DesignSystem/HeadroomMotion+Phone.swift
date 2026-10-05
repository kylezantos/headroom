import SwiftUI

/// KTD16 (R7, "Short entrance on app open"): the phone's only motion of its own. Everything
/// else — the meters' landing, digit rolls, capsule and fades — rides the shared
/// `HeadroomMotion` tokens, exactly as on the Mac.
extension HeadroomMotion {
    /// The card entrance: the house curve (S1A) at 0.34 s, carried over from the July phone.
    static let phoneCardEntrance = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.34)
    /// Each card waits this long per account above it…
    static let phoneCardEntranceStagger: Double = 0.055
    /// …up to the eighth account (spec-flow M6: 60 meters must not trickle in for seconds);
    /// every later card enters with the eighth.
    static let phoneCardEntranceStaggerCap = 8
    /// How far a card rises as it enters. Movement, so Reduce Motion drops it (S2A).
    static let phoneCardEntranceRise: CGFloat = 10

    static func phoneCardEntranceDelay(accountsBefore: Int) -> Double {
        Double(min(max(0, accountsBefore), phoneCardEntranceStaggerCap)) * phoneCardEntranceStagger
    }
}

/// KTD16: the entrance plays once per app launch — never on a data refresh, rotation, resize
/// or a demo switch that rebuilds the screen. Launch-scoped and in memory, like the Mac's
/// arrival registry.
@MainActor
@Observable
final class PhoneLaunchEntrance {
    static let shared = PhoneLaunchEntrance()

    /// How many times an entrance has started this launch. Read by the DEBUG marker the UI
    /// test checks; it can only ever reach 1.
    private(set) var playCount = 0

    var hasPlayed: Bool { playCount > 0 }

    /// Claims the launch's one entrance. False once it has played.
    func claim() -> Bool {
        guard playCount == 0 else { return false }
        playCount += 1
        return true
    }
}

/// One card's part in the entrance: fades and rises in with its staggered delay once
/// `isShown` flips. A card that appears after the entrance has played is shown at once.
struct PhoneCardEntranceModifier: ViewModifier {
    let isShown: Bool
    let accountsBefore: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let delay = HeadroomMotion.phoneCardEntranceDelay(accountsBefore: accountsBefore)
        content
            .opacity(isShown ? 1 : 0)
            .animation(HeadroomMotion.phoneCardEntrance.delay(delay), value: isShown)
            .offset(y: isShown || reduceMotion ? 0 : HeadroomMotion.phoneCardEntranceRise)
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.phoneCardEntrance.delay(delay), .movement, reduceMotion: reduceMotion),
                value: isShown
            )
    }
}

extension View {
    func phoneCardEntrance(isShown: Bool, accountsBefore: Int) -> some View {
        modifier(PhoneCardEntranceModifier(isShown: isShown, accountsBefore: accountsBefore))
    }
}
