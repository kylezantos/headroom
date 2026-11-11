import Foundation

/// Which phone surface asks. Widgets, Lock Screen and Control only see new data when
/// WidgetKit reloads them, so they share a higher dim floor (KTD15).
public enum CompanionFreshnessSurface: Sendable, Equatable, CaseIterable {
    case app, siri, widget, lockScreen, control

    var usesWidgetFloor: Bool {
        switch self {
        case .app, .siri: false
        case .widget, .lockScreen, .control: true
        }
    }

    /// Home Screen, Lock Screen and Control follow the main account only (KTD13, KTD20).
    public var showsMainAccountsOnly: Bool { usesWidgetFloor }
}

/// The resolver's freshness inputs (KTD15). Every surface derives dimming from these
/// with `CompanionFreshnessRule`, so they all dim at the same moment: first-seen comes
/// from the shared cache transaction, never from a per-process clock.
public struct CompanionFreshnessInputs: Equatable, Sendable {
    /// The Mac's publish time for the shown generation (manifest or v3), Mac clock.
    public let generatedAt: Date
    /// When this phone first saw that generation, phone clock, created once per scope.
    public let firstSeen: Date
    /// The largest effective interval the manifest reports; nil when only v3 is shown.
    public let largestEffectiveIntervalSeconds: Double?
    public let isV3Only: Bool

    public init(
        generatedAt: Date, firstSeen: Date, largestEffectiveIntervalSeconds: Double?,
        isV3Only: Bool
    ) {
        self.generatedAt = generatedAt
        self.firstSeen = firstSeen
        self.largestEffectiveIntervalSeconds = largestEffectiveIntervalSeconds
        self.isV3Only = isV3Only
    }
}

/// One pure Core freshness recipe for the app, both widget hosts, Siri, Lock Screen and
/// Control (KTD15, R9–R11). It never reads the clock itself.
public enum CompanionFreshnessRule {
    /// Either clock may be off by this much without a false dim.
    public static let clockAllowance: TimeInterval = 10 * 60
    public static let minimumThreshold: TimeInterval = 15 * 60
    /// Twice the longest interval the Mac allows: an old Mac's cadence is unknown.
    public static let v3OnlyThreshold: TimeInterval = 120 * 60
    public static let widgetFloor: TimeInterval = 60 * 60
    public static let pastResetGrace: TimeInterval = 10 * 60
    /// KTD6.3: a lagging provider key turns "Last known" after max(2 minutes, a heartbeat).
    public static let lagGraceMinimum: TimeInterval = 2 * 60

    /// min(first-seen, generatedAt + 10 min): a skewed Mac clock cannot stick or flicker,
    /// and a phone arriving at an hours-old generation dims at once.
    public static func dimBase(_ inputs: CompanionFreshnessInputs) -> Date {
        min(inputs.firstSeen, inputs.generatedAt.addingTimeInterval(clockAllowance))
    }

    /// max(15 min, 2 × the largest effective interval); 120 min when only v3 is known.
    /// The effective interval comes from LaneSchedule on the Mac, so a stretched
    /// 20-account lane never dims healthy data.
    public static func threshold(largestEffectiveIntervalSeconds: Double?, isV3Only: Bool)
        -> TimeInterval
    {
        guard !isV3Only else { return v3OnlyThreshold }
        guard let interval = largestEffectiveIntervalSeconds, interval.isFinite, interval > 0 else {
            // An invalid cadence never invents a healthy one; dim on the conservative floor.
            return minimumThreshold
        }
        return max(minimumThreshold, 2 * interval)
    }

    public static func threshold(_ inputs: CompanionFreshnessInputs, surface: CompanionFreshnessSurface)
        -> TimeInterval
    {
        let rule = threshold(
            largestEffectiveIntervalSeconds: inputs.largestEffectiveIntervalSeconds,
            isV3Only: inputs.isV3Only)
        return surface.usesWidgetFloor ? max(rule, widgetFloor) : rule
    }

    /// The moment a surface dims. Widget timelines end with a reload request here.
    public static func dimsAt(_ inputs: CompanionFreshnessInputs, surface: CompanionFreshnessSurface)
        -> Date
    {
        dimBase(inputs).addingTimeInterval(threshold(inputs, surface: surface))
    }

    public static func isDimmed(
        _ inputs: CompanionFreshnessInputs, surface: CompanionFreshnessSurface, at now: Date
    ) -> Bool {
        !(now < dimsAt(inputs, surface: surface))
    }

    /// The time in "No update from your Mac since <time>": the Mac's publish time, never
    /// later than when this phone first saw it, so a fast Mac clock cannot name the future.
    public static func lastHeardFromMac(_ inputs: CompanionFreshnessInputs) -> Date {
        min(inputs.generatedAt, inputs.firstSeen)
    }

    /// R9: "Updated" names the oldest live reading on screen, not the publish time.
    public static func updatedAt(_ windows: [WidgetWindowSummary]) -> Date? {
        windows.filter(\.freshness.isLive).compactMap(\.observedAt).min()
    }

    /// R11/AE6: ten minutes after a scheduled reset with no newer reading, the number hides
    /// and the row says when it reset. Returns that reset time while hidden.
    public static func pastResetTime(_ window: WidgetWindowSummary, at now: Date) -> Date? {
        pastResetTime(window, at: now, isRemembered: false)
    }

    /// Default-login plan R8: a remembered row's window hides at its reset, with no grace.
    /// The grace covers a Mac that is about to read a live account again; nothing reads a
    /// remembered account, so its number is never current after the reset. Depends only on
    /// the row, never on how fresh the manifest is.
    public static func pastResetTime(_ window: WidgetWindowSummary, at now: Date, isRemembered: Bool) -> Date? {
        guard case .scheduled(let deadline) = window.resetSchedule else { return nil }
        let observed = window.observedAt ?? window.freshness.observedAt
        if let observed, !(observed < deadline) { return nil }
        let grace = isRemembered ? 0 : pastResetGrace
        return !(now < deadline.addingTimeInterval(grace)) ? deadline : nil
    }

    /// The number a surface may show: hidden while unavailable or past reset (R11).
    public static func visiblePercentRemaining(_ window: WidgetWindowSummary, at now: Date) -> Double? {
        pastResetTime(window, at: now) == nil ? window.displayPercentRemaining : nil
    }

    /// Whole-surface dimming and per-row stale never stack opacity (KTD15).
    public static func showsRowStaleTreatment(_ window: WidgetWindowSummary, surfaceDimmed: Bool) -> Bool {
        !surfaceDimmed && window.freshness.isStale
    }

    /// The per-provider "Last known" grace for a key below the manifest's generation.
    public static func lagGrace(chosenIntervalSeconds: Int) -> TimeInterval {
        max(lagGraceMinimum, TimeInterval(chosenIntervalSeconds))
    }
}

/// KTD15 copy. Never "Your Mac is asleep". Times arrive already formatted by the
/// surface's shared reset/clock formatter.
public enum CompanionFreshnessCopy {
    public static let waitingForMac = "Waiting for your Mac"

    public static func noUpdate(since time: String) -> String {
        "No update from your Mac since \(time)"
    }

    public static func pastReset(at time: String) -> String {
        "Reset at \(time) · waiting for your Mac"
    }
}
