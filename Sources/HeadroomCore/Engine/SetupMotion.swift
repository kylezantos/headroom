import Foundation

/// KTD5/KTD10/KTD20: meaning follows phase; small drip awaits its looping-preview gate.
public struct SetupMotion: Sendable, Equatable {
    public enum Surface: Sendable, Equatable {
        case card
        case row
        case settings
    }

    public let motion: LoadingMotion
    public let level: Double

    public static func resolve(
        phase: SetupWaitingPhase?,
        surface: Surface,
        level: Double = LoadingMotionConstants.decorativeLevel,
        reduceMotion: Bool = false,
        rowDripApproved: Bool = false
    ) -> Self {
        let level = min(1, max(0, level))
        switch phase {
        case .openingTerminal, .confirming:
            return Self(motion: reduceMotion ? .still : .slosh, level: level)
        case .waitingForUser:
            // Empty waiting pose remains distinct even when the animated row fallback
            // would slosh: Reduce Motion expresses the semantic phase, not the fallback.
            if reduceMotion { return Self(motion: .still, level: 0) }
            let usesDrip = surface == .card || rowDripApproved
            return Self(motion: usesDrip ? .drip : .slosh, level: usesDrip ? 0 : level)
        case nil:
            return Self(motion: .still, level: level)
        }
    }
}
