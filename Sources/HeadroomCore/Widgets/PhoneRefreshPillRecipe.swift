import Foundation

/// The phone has one decorative pill, not the Mac's per-provider meters. A successful
/// assembled snapshot earns the same fresh print; a failed/partial check stays ghosted.
public struct PhoneRefreshPillRecipe: Sendable, Equatable {
    public let pill: LoadingPillState?
    public let visibleUntil: Date?

    public init(isChecking: Bool, requestedAt: Date?, endedAt: Date?, didUpdate: Bool,
                now: Date, reduceMotion: Bool) {
        let finish = isChecking ? nil : endedAt
        visibleUntil = finish.map {
            max($0.addingTimeInterval(max(LoadingMotionConstants.printDuration, LoadingMotionConstants.endHoldDuration)),
                Date(timeIntervalSince1970: floor($0.timeIntervalSince1970) + LoadingMotionConstants.sloshCycle))
        }
        guard isChecking || visibleUntil.map({ now < $0 }) == true else {
            pill = nil
            return
        }
        let ink: LoadingInk
        if isChecking, let requestedAt,
           now.timeIntervalSince(requestedAt) < LoadingMotionConstants.ghostWipeDuration {
            let progress = max(0, now.timeIntervalSince(requestedAt) / LoadingMotionConstants.ghostWipeDuration)
            ink = reduceMotion ? .crossfade(progress: 1 - progress) : .ghostWipe(progress: progress)
        } else if let finish, didUpdate {
            let progress = max(0, now.timeIntervalSince(finish) / LoadingMotionConstants.printDuration)
            ink = progress < 1 ? (reduceMotion ? .crossfade(progress: progress) : .printing(progress: progress)) : .full
        } else {
            ink = .ghost
        }
        pill = LoadingPillState(id: "phone-refresh", level: LoadingMotionConstants.decorativeLevel,
                               ink: ink, isSloshing: LoadingMotionClock.isSloshing(
                                active: isChecking, endedAt: finish, now: now, reduceMotion: reduceMotion))
    }
}
