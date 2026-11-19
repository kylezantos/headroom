import SwiftUI

/// CA-M5 (MOT-05; overturns the iOS parity plan's KTD16, "the phone's only motion of its
/// own", with its per-account stagger capped at the eighth account): the card entrance is the
/// launch's one motion, and the meters no longer draw in on top of it. Timing is Core's
/// `PhoneCardEntranceSchedule`, so the worst case is tested without a SwiftUI host.
extension HeadroomMotion {
    /// The card entrance: the house curve (S1A) at 0.28 s.
    static let phoneCardEntrance = houseCurve(duration: PhoneCardEntranceSchedule.duration)

    static func phoneCardEntranceDelay(cardIndex: Int) -> Double {
        PhoneCardEntranceSchedule.delay(cardIndex: cardIndex)
    }
}

/// KTD16 (kept): the entrance plays once per app launch — never on a data refresh, rotation,
/// resize or a demo switch that rebuilds the screen. Launch-scoped and in memory, like the
/// Mac's arrival registry.
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
/// Reduce Motion keeps the fade and drops the rise.
struct PhoneCardEntranceModifier: ViewModifier {
    let isShown: Bool
    let cardIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let animation = HeadroomMotion.phoneCardEntrance.delay(HeadroomMotion.phoneCardEntranceDelay(cardIndex: cardIndex))
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : PhoneCardEntranceSchedule.rise(reduceMotion: reduceMotion))
            .animation(animation, value: isShown)
    }
}

extension View {
    func phoneCardEntrance(isShown: Bool, cardIndex: Int) -> some View {
        modifier(PhoneCardEntranceModifier(isShown: isShown, cardIndex: cardIndex))
    }
}
