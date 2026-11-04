import Foundation

/// Pure scheduling decisions for per-account polling (2026-09-19 polling plan, KTD1).
/// Every function takes an explicit `now` and the records it decides over, so the
/// choices are unit-testable without a store, a clock, or a CLI.
///
/// The scheduler owns its own attempt clock (KTD3): a failed probe deliberately keeps
/// the prior `UsageSnapshot.capturedAt`, so capture time can never stand in for "when
/// did we last try this account".
public enum LaneSchedule {
    /// KTD5: growing spacing stops here, or at the effective interval when that is longer,
    /// so a failing account is never due sooner than a healthy one.
    public static let backoffCap: TimeInterval = 30 * 60
    /// KTD5 / R13: an abandoned Add Account waits four intervals, replacing the old
    /// every-fourth-timer-cycle rule with a due-time statement of the same cost bound.
    public static let neverSignedInMultiplier: Double = 4
    /// KTD4 / R8: a CLI lane may be busy for at most this fraction of the trailing window.
    public static let dutyCycleCeiling: Double = 0.5
    /// KTD6: the shortest sleep the wake timer takes when something is already overdue.
    public static let minimumWake: TimeInterval = 1
    /// R10 / R12: a gap this far past the chosen interval is wake jitter plus at most one
    /// probe's wait, which the promise allows, so it never reads as a stretched lane.
    public static let cadenceTolerance: TimeInterval = 90

    /// Scheduler-owned per-account state (KTD3).
    public struct AccountRecord: Sendable, Equatable {
        public let key: AccountKey
        public var isPrimary: Bool
        public var lastAttempt: Date?
        public var previousAttempt: Date?
        public var consecutiveFailures: Int
        public var isNeverSignedIn: Bool
        /// A user action, an attach, or a surface re-enable made this account due now
        /// regardless of its attempt clock (KTD2, KTD11). Cleared when an attempt starts.
        public var forcedDue: Bool
        /// The account's own next tracked reset deadline, for per-account phasing (KTD6).
        public var resetDeadline: Date?
        /// Whether the gap ending at `lastAttempt` was scheduled at the chosen interval.
        /// Decided when the attempt starts (KTD4): a first success after backoff, or the
        /// first capture after a sign-in, must not report its stretched gap as the lane's.
        public var lastGapOnCadence: Bool

        public init(
            key: AccountKey,
            isPrimary: Bool = false,
            lastAttempt: Date? = nil,
            previousAttempt: Date? = nil,
            consecutiveFailures: Int = 0,
            isNeverSignedIn: Bool = false,
            forcedDue: Bool = true,
            resetDeadline: Date? = nil,
            lastGapOnCadence: Bool = true
        ) {
            self.key = key
            self.isPrimary = isPrimary
            self.lastAttempt = lastAttempt
            self.previousAttempt = previousAttempt
            self.consecutiveFailures = consecutiveFailures
            self.isNeverSignedIn = isNeverSignedIn
            self.forcedDue = forcedDue
            self.resetDeadline = resetDeadline
            self.lastGapOnCadence = lastGapOnCadence
        }

        /// Gap between the last two attempts — the measured cadence the account actually
        /// experienced (KTD4). Nil until two attempts exist.
        public var attemptGap: TimeInterval? {
            guard let lastAttempt, let previousAttempt else { return nil }
            return lastAttempt.timeIntervalSince(previousAttempt)
        }

        /// Accounts in backoff or on the never-signed-in rule are stretched on purpose;
        /// their gaps say nothing about the lane's cadence (KTD4).
        public var isOnCadence: Bool {
            lastGapOnCadence && scheduledOnCadence
        }

        /// Whether the *next* gap will be scheduled at the chosen interval.
        public var scheduledOnCadence: Bool {
            consecutiveFailures == 0 && !(isNeverSignedIn && !isPrimary)
        }
    }

    /// One probe's wall-clock footprint in a lane's log (KTD4).
    public struct ProbeSpan: Sendable, Equatable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// How an attempt's result moves the failure count (KTD3).
    public enum AttemptOutcome: Sendable, Equatable {
        case success
        case transientFailure
        /// Login, trust, or another permanent setup state: not a failure to back off
        /// from, so the account stays on cadence and recovers within one interval.
        case permanentState
    }

    // MARK: Intervals

    public static func chosenInterval(minutes: Int) -> TimeInterval {
        Double(PollingEngine.clampedIntervalMinutes(minutes)) * 60
    }

    /// The smallest spacing two attempts of one account may ever have (R20).
    static var intervalFloor: TimeInterval {
        Double(Preferences.minimumIntervalMinutes) * 60
    }

    /// KTD4: what Settings shows. The chosen interval, or the longest gap an on-cadence
    /// account actually saw between attempts, rounded up to whole minutes. Measured
    /// rather than computed from probe durations, so an outage clears within one normal
    /// pass instead of being averaged for hours.
    public static func effectiveInterval(chosen: TimeInterval, attemptGaps: [TimeInterval]) -> TimeInterval {
        let longest = attemptGaps.max() ?? 0
        guard longest > chosen + cadenceTolerance else { return chosen }
        return (longest / 60).rounded(.up) * 60
    }

    // MARK: Due times

    /// KTD5 and KTD6: when this account should next be probed. `.distantPast` means now.
    public static func nextDue(
        for record: AccountRecord,
        chosen: TimeInterval,
        effective: TimeInterval
    ) -> Date {
        guard !record.forcedDue, let last = record.lastAttempt else { return .distantPast }
        if record.consecutiveFailures > 0 {
            // KTD5: doubling from the chosen interval, never sooner than a healthy account in
            // a stretched lane (the effective interval), never later than the cap.
            let doubled = chosen * pow(2, Double(record.consecutiveFailures))
            let spaced = min(max(doubled, effective), max(backoffCap, effective))
            return last.addingTimeInterval(max(intervalFloor, spaced))
        }
        if record.isNeverSignedIn && !record.isPrimary {
            return last.addingTimeInterval(chosen * neverSignedInMultiplier)
        }
        let due = last.addingTimeInterval(chosen)
        // R2M3 carried per account: a reset that lands inside this account's interval pulls
        // its next probe to just after the refill, never closer than the floor.
        if let deadline = record.resetDeadline, deadline > last, deadline < due {
            return max(
                last.addingTimeInterval(intervalFloor),
                deadline.addingTimeInterval(PollPhasing.postResetGrace)
            )
        }
        return due
    }

    public static func isDue(
        _ record: AccountRecord,
        now: Date,
        chosen: TimeInterval,
        effective: TimeInterval
    ) -> Bool {
        !(nextDue(for: record, chosen: chosen, effective: effective) > now)
    }

    /// KTD6 / KTD7 ordering for a lane that serves one account at a time: a priority
    /// request first, then an overdue primary, then the most overdue account. Nil when
    /// nothing is due.
    public static func nextAccount(
        records: [AccountRecord],
        priority: [AccountKey],
        now: Date,
        chosen: TimeInterval,
        effective: TimeInterval
    ) -> AccountKey? {
        let keys = Set(records.map(\.key))
        if let requested = priority.first(where: keys.contains) { return requested }
        let due = records.filter { isDue($0, now: now, chosen: chosen, effective: effective) }
        let dueDate = { (record: AccountRecord) in nextDue(for: record, chosen: chosen, effective: effective) }
        if let primary = due.filter(\.isPrimary).min(by: { dueDate($0) < dueDate($1) }) {
            return primary.key
        }
        return due.min(by: { dueDate($0) < dueDate($1) })?.key
    }

    /// Every account a concurrent (HTTP) lane should fetch now, priority requests first.
    public static func dueAccounts(
        records: [AccountRecord],
        priority: [AccountKey],
        now: Date,
        chosen: TimeInterval,
        effective: TimeInterval
    ) -> [AccountKey] {
        let keys = Set(records.map(\.key))
        let requested = priority.filter(keys.contains)
        let requestedSet = Set(requested)
        let due = records
            .filter { !requestedSet.contains($0.key) && isDue($0, now: now, chosen: chosen, effective: effective) }
            .map(\.key)
        return requested + due
    }

    // MARK: Duty cycle (KTD4)

    public static func window(chosen: TimeInterval) -> TimeInterval { 2 * chosen }

    /// Seconds of probe time inside the trailing window ending at `now`.
    public static func busyTime(log: [ProbeSpan], now: Date, window: TimeInterval) -> TimeInterval {
        let left = now.addingTimeInterval(-window)
        return log.reduce(0) { total, span in
            let start = max(span.start, left)
            let end = min(span.end, now)
            return total + max(0, end.timeIntervalSince(start))
        }
    }

    /// R8: a timer-driven probe may start only while the lane has been busy for at most
    /// half of the trailing window. Priority requests bypass this; their time still counts.
    public static func mayStartTimerProbe(log: [ProbeSpan], now: Date, chosen: TimeInterval) -> Bool {
        let window = window(chosen: chosen)
        return busyTime(log: log, now: now, window: window) <= window * dutyCycleCeiling
    }

    /// The earliest moment the budget reopens, or nil when it is open now. Slides the
    /// window's left edge forward through the logged spans in start order until enough
    /// busy time has fallen out.
    public static func budgetReopens(log: [ProbeSpan], now: Date, chosen: TimeInterval) -> Date? {
        let window = window(chosen: chosen)
        let budget = window * dutyCycleCeiling
        var busy = busyTime(log: log, now: now, window: window)
        guard busy > budget else { return nil }
        let left = now.addingTimeInterval(-window)
        let clipped = log
            .compactMap { span -> (start: Date, end: Date)? in
                let start = max(span.start, left)
                let end = min(span.end, now)
                return end > start ? (start, end) : nil
            }
            .sorted { $0.start < $1.start }
        for span in clipped {
            let length = span.end.timeIntervalSince(span.start)
            let excess = busy - budget
            if length >= excess {
                return span.start.addingTimeInterval(excess + window)
            }
            busy -= length
        }
        return now.addingTimeInterval(window)
    }

    // MARK: Wake timer (KTD6)

    /// Seconds the engine sleeps: until the earliest candidate, never under one second,
    /// never over the chosen interval. Callers pass only accounts in idle lanes (a draining
    /// lane serves its own) plus each closed lane's budget-reopen time.
    public static func wakeDelay(candidates: [Date], now: Date, chosen: TimeInterval) -> TimeInterval {
        guard let earliest = candidates.min() else { return chosen }
        return min(chosen, max(minimumWake, earliest.timeIntervalSince(now)))
    }

    // MARK: Attempt outcomes (KTD3)

    public static func outcome(of result: UsageProviderFetchResult) -> AttemptOutcome {
        if let capability = result.capability, capability != .available { return .transientFailure }
        switch result.snapshot.freshness {
        case .live:
            return .success
        case .stale(let reason):
            return reason.isPermanent ? .permanentState : .transientFailure
        case .pending:
            return .transientFailure
        }
    }

    public static func consecutiveFailures(after outcome: AttemptOutcome, previous: Int) -> Int {
        switch outcome {
        case .success, .permanentState: return 0
        case .transientFailure: return previous + 1
        }
    }

    /// R13: the never-signed-in states the four-interval rule applies to.
    public static func isNeverSignedIn(_ freshness: Freshness?) -> Bool {
        guard case .stale(let reason) = freshness else { return false }
        if case .notLoggedIn = reason { return true }
        guard case .providerSetup(let outcome) = reason else { return false }
        return outcome.isNeverSignedIn
    }
}

/// KTD12: what Settings reads for one provider. `effectiveInterval` is measured (KTD4),
/// so it can only exceed `chosenInterval`, and only for a CLI lane.
public struct PollCadence: Sendable, Equatable {
    public let chosenInterval: TimeInterval
    public let effectiveInterval: TimeInterval
    public let accountCount: Int

    public init(chosenInterval: TimeInterval, effectiveInterval: TimeInterval, accountCount: Int) {
        self.chosenInterval = chosenInterval
        self.effectiveInterval = effectiveInterval
        self.accountCount = accountCount
    }

    public var isStretched: Bool { effectiveInterval > chosenInterval }
}

/// KTD12 / R9, R10: the read-only Settings sentence for providers whose accounts run slower
/// than the chosen interval. The stepper above shows the chosen interval, so the sentence
/// names each stretched provider's effective interval and its account count (the reason).
/// Nil when every promise is kept, so nothing extra shows. One sentence, not a line per
/// provider: stacked 11pt paragraphs under one control broke R2B2's one-help-block rule.
public enum PollCadencePresentation {
    /// R9 (2026-09-26 notifications plan): the "can land up to N min late" figure under the
    /// reminder list. The slowest effective interval across the providers' lanes, rounded up
    /// the same way as the sentence below, so the two panes never quote different numbers.
    /// The chosen interval when nothing has been measured yet.
    public static func slowestEffectiveMinutes(_ cadences: [PollCadence], chosenInterval: TimeInterval) -> Int {
        let slowest = cadences.map(\.effectiveInterval).max() ?? chosenInterval
        return Int((max(slowest, chosenInterval) / 60).rounded(.up))
    }

    public static func sentence(for cadences: [(providerName: String, cadence: PollCadence)]) -> String? {
        let clauses = cadences.filter { $0.cadence.isStretched }.map { entry in
            let effective = Int((entry.cadence.effectiveInterval / 60).rounded(.up))
            let count = entry.cadence.accountCount
            let accounts = count == 1 ? "1\u{00A0}account" : "\(count)\u{00A0}accounts"
            return (name: entry.providerName, rest: "about every \(effective)\u{00A0}min across \(accounts)")
        }
        guard let first = clauses.first else { return nil }
        let lead = "Right now \(first.name) refreshes \(first.rest)"
        let others = clauses.dropFirst().map { "\($0.name) \($0.rest)" }
        switch others.count {
        case 0: return lead + "."
        case 1: return "\(lead), and \(others[0])."
        default: return "\(lead), " + others.dropLast().joined(separator: ", ") + ", and \(others.last!)."
        }
    }
}
