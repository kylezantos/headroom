import Foundation

/// Loading-language KTD21: shared by the Mac, phone and widget rendering paths.
public enum LoadingMotionConstants {
    public static let sloshFrameCount = 10
    public static let sloshFrameInterval: TimeInterval = 0.1
    public static let sloshCycle: TimeInterval = 1
    public static let dripCycle: TimeInterval = 1.8
    public static let dripFall: TimeInterval = 0.45
    public static let dripRipple: TimeInterval = 0.6
    public static let printDuration: TimeInterval = 0.35
    public static let printRowInterval: TimeInterval = 0.035
    public static let menuBarPrintFrameCount = 4
    public static let ghostWipeDuration: TimeInterval = 0.2
    public static let endHoldDuration: TimeInterval = 0.5
    public static let drainDuration: TimeInterval = 1.1
    /// Matches `VesselGlyph.staticFill`; automatic mode and placeholders carry no value.
    public static let decorativeLevel = 0.46
}

public enum LoadingMotionClock {
    /// KTD6: independent views share a stepped wall-clock phase, with no tick counter.
    public static func sloshPhase(at date: Date) -> Int {
        let tick = floor(date.timeIntervalSince1970 * Double(LoadingMotionConstants.sloshFrameCount))
        let count = Double(LoadingMotionConstants.sloshFrameCount)
        return Int((tick.truncatingRemainder(dividingBy: count) + count).truncatingRemainder(dividingBy: count))
    }

    public static func isSloshing(active: Bool, endedAt: Date?, now: Date, reduceMotion: Bool = false) -> Bool {
        guard !reduceMotion else { return false }
        if active { return true }
        guard let endedAt, endedAt <= now else { return false }
        let cycle = LoadingMotionConstants.sloshCycle
        let wrap = (floor(endedAt.timeIntervalSince1970 / cycle) + 1) * cycle
        return now.timeIntervalSince1970 < wrap
    }
}

public enum LoadingMotion: Sendable, Equatable {
    case still
    case slosh
    case drip
}

/// Coverage coordinates run top (0) to bottom (1), regardless of Canvas orientation.
public enum LoadingInk: Sendable, Equatable {
    case full
    case ghost
    case ghostWipe(progress: Double)
    case printing(progress: Double)
    /// Reduce Motion's uniform ghost-to-full ink blend; no travelling boundary.
    case crossfade(progress: Double)

    /// Options 12d: the filled level retains 45% ink. Empty-field specks are a separate
    /// geometry coverage, so a ghost cannot disappear into the vessel's empty dots.
    public static let ghostCoverage = 0.45

    public var progress: Double? {
        switch self {
        case .ghostWipe(let progress), .printing(let progress), .crossfade(let progress): progress
        case .full, .ghost: nil
        }
    }

    public var isTransitioning: Bool { progress != nil }
    public var isTravelling: Bool {
        switch self {
        case .ghostWipe, .printing: true
        case .full, .ghost, .crossfade: false
        }
    }

    public func coverage(at verticalFraction: Double) -> Double {
        let y = min(1, max(0, verticalFraction))
        switch self {
        case .full: return 1
        case .ghost: return Self.ghostCoverage
        case .ghostWipe(let progress): return y < min(1, max(0, progress)) ? Self.ghostCoverage : 1
        case .printing(let progress): return y >= 1 - min(1, max(0, progress)) ? 1 : Self.ghostCoverage
        case .crossfade(let progress): return Self.ghostCoverage + (1 - Self.ghostCoverage) * min(1, max(0, progress))
        }
    }
}

/// iOS-safe render contract. IDs are rendering identities, never account identities.
public struct LoadingPillState: Sendable, Equatable, Identifiable {
    public let id: String
    public let level: Double
    public let ink: LoadingInk
    public let isSloshing: Bool

    public init(id: String, level: Double, ink: LoadingInk = .full, isSloshing: Bool = false) {
        self.id = id
        self.level = min(1, max(0, level))
        self.ink = ink
        self.isSloshing = isSloshing
    }

    /// KTD15/WCW4: identical levels cannot imply different provider usage values.
    public static func ghostRow(count: Int = 3, isSloshing: Bool = false) -> [Self] {
        (0..<max(0, count)).map {
            Self(id: "ghost-\($0)", level: LoadingMotionConstants.decorativeLevel, ink: .ghost, isSloshing: isSloshing)
        }
    }
}
