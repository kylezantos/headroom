import Foundation

/// KTD15: preserve the existing mark gutter; three ghosts require the full Mini Pill slot.
public struct WidgetLoadingPlaceholderRecipe: Sendable, Equatable {
    public static let rowWidth: Double = 44
    public let usesRow: Bool
    public var pills: [LoadingPillState] { LoadingPillState.ghostRow(count: usesRow ? 3 : 1) }
    public var width: Double { usesRow ? Self.rowWidth : 12 }
    public var height: Double { usesRow ? 16 : 20 }

    public init(availableWidth: Double) {
        usesRow = availableWidth >= Self.rowWidth
    }
}

public extension WidgetStatusState {
    func loadingPlaceholder(availableWidth: Double) -> WidgetLoadingPlaceholderRecipe? {
        switch self {
        case .macPending, .iosWaitingForMac:
            WidgetLoadingPlaceholderRecipe(availableWidth: availableWidth)
        default:
            nil
        }
    }
}

/// KTD14: a local cache check finishes its current wave before the button becomes available.
public struct LoadingCheckRecipe: Sendable, Equatable {
    public let isWorking: Bool
    public let waveEnd: Date?
    public let pills: [LoadingPillState]

    public init(isChecking: Bool, endedAt: Date?, now: Date, reduceMotion: Bool) {
        isWorking = isChecking || LoadingMotionClock.isSloshing(
            active: false, endedAt: endedAt, now: now, reduceMotion: reduceMotion
        )
        waveEnd = reduceMotion ? nil : endedAt.map {
            let cycle = LoadingMotionConstants.sloshCycle
            return Date(timeIntervalSince1970: (floor($0.timeIntervalSince1970 / cycle) + 1) * cycle)
        }
        pills = LoadingPillState.ghostRow(isSloshing: isChecking && !reduceMotion)
    }
}
