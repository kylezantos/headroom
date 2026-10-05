import Foundation

/// KTD19: automatic ink follows every current main, independently of the summary winner.
public struct ReprintSourceIdentity: Sendable, Hashable {
    public let keys: [AccountKey?]

    public init(meters: [MenuBarMeter], automatic: Bool, currentMains: [ProviderID: AccountKey]) {
        keys = automatic
            ? currentMains.values.sorted { $0.description < $1.description }.map(Optional.some)
            : meters.map(\.sourceAccountKey)
    }
}

/// Loading-language KTD5/KTD18: reopening a view cannot restart a wipe, print or hold.
public struct ReprintRecipe: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case rest
        case spinner
        case spendTail
        case hold
    }

    public let phase: Phase
    public let pills: [LoadingPillState]
    public var isEnabled: Bool { phase == .rest }
    public var usesSlimGeometry: Bool { pills.count == 4 }
    public var needsTimeline: Bool {
        phase == .hold || pills.contains { $0.isSloshing || $0.ink.isTransitioning }
    }

    public init(
        meters: [MenuBarMeter],
        automatic: Bool,
        currentMains: [ProviderID: AccountKey],
        run: UserRefreshRun?,
        probingAccounts: Set<AccountKey>,
        probeEndTimes: [AccountKey: Date],
        spendInFlightProviders: Set<ProviderID>,
        visibleWork: VisibleRefreshWork,
        now: Date,
        reduceMotion: Bool = false
    ) {
        let entries = run?.entries.filter { $0.value.origin != .setupCheck } ?? [:]
        let clearedAt = visibleWork.clearedAt
        let pending = entries.values.contains { Self.hasNotLanded($0, at: now) }
        if visibleWork.isInFlight {
            phase = pending ? .spinner : .spendTail
        } else if let clearedAt, clearedAt <= now,
                  now < clearedAt.addingTimeInterval(LoadingMotionConstants.endHoldDuration) {
            phase = .hold
        } else {
            phase = .rest
        }

        let inTail = phase == .spendTail
        let shownProviders = Set(meters.compactMap(\.summary.providerID))
        let sloshWholeTail = automatic || shownProviders.isDisjoint(with: spendInFlightProviders)
        let resolvedPhase = phase
        pills = meters.map { meter in
            let provider = meter.summary.providerID
            let relevantEntries: [UserRefreshEntry]
            let active: Bool
            let endedAt: Date?
            if automatic {
                relevantEntries = currentMains.values.compactMap { entries[$0] }
                active = !probingAccounts.isEmpty
                endedAt = probeEndTimes.values.max()
            } else if let provider {
                relevantEntries = currentMains[provider].flatMap { entries[$0] }.map { [$0] } ?? []
                active = probingAccounts.contains { $0.providerID == provider }
                endedAt = probeEndTimes.lazy.filter { $0.key.providerID == provider }.map(\.value).max()
            } else {
                relevantEntries = []
                active = false
                endedAt = nil
            }
            let ink = Self.ink(entries: relevantEntries, now: now, reduceMotion: reduceMotion)
            let slosh = resolvedPhase != .rest && (
                LoadingMotionClock.isSloshing(active: active, endedAt: endedAt, now: now, reduceMotion: reduceMotion)
                || (inTail && !reduceMotion && (sloshWholeTail || provider.map(spendInFlightProviders.contains) == true))
            )
            return LoadingPillState(
                id: automatic ? "automatic" : (provider?.raw ?? "neutral"),
                level: automatic ? LoadingMotionConstants.decorativeLevel : (meter.fill ?? LoadingMotionConstants.decorativeLevel),
                ink: ink,
                isSloshing: slosh
            )
        }
    }

    private static func hasNotLanded(_ entry: UserRefreshEntry, at now: Date) -> Bool {
        entry.outcome == nil || entry.landedAt.map { $0 > now } == true
    }

    private static func ink(entries: [UserRefreshEntry], now: Date, reduceMotion: Bool) -> LoadingInk {
        let entries = entries.filter { $0.requestedAt <= now && $0.outcome != .dropped }
        guard !entries.isEmpty else { return .full } // KTD19: a new, unrequested main never prints.
        let pending = entries.filter { hasNotLanded($0, at: now) }
        if !pending.isEmpty {
            let requestedAt = pending.map(\.requestedAt).min()!
            let elapsed = now.timeIntervalSince(requestedAt)
            if elapsed < LoadingMotionConstants.ghostWipeDuration {
                let progress = max(0, elapsed / LoadingMotionConstants.ghostWipeDuration)
                return reduceMotion ? .crossfade(progress: 1 - progress) : .ghostWipe(progress: progress)
            }
            return .ghost
        }
        guard entries.allSatisfy({ $0.outcome == .live }), let landedAt = entries.compactMap(\.landedAt).max() else {
            return .ghost // A stale landing never claims a fresh print.
        }
        let elapsed = now.timeIntervalSince(landedAt)
        if elapsed < LoadingMotionConstants.printDuration {
            let progress = max(0, elapsed / LoadingMotionConstants.printDuration)
            return reduceMotion ? .crossfade(progress: progress) : .printing(progress: progress)
        }
        return .full
    }
}
