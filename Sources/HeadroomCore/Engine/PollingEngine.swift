import Foundation

/// R2M3: pure cadence arithmetic for the polling loop. Kept out of `PollingEngine` so the
/// wake-time decision is testable without a clock.
public enum PollPhasing {
    /// How long after a window's reset deadline the phased poll wakes. Enough slack for the
    /// provider's own bookkeeping to roll over before we ask, short enough that the user sees
    /// the refill rather than a wrong number.
    public static let postResetGrace: TimeInterval = 30

    /// Seconds to sleep before the next poll. Normally one full interval; when a tracked
    /// window's reset deadline lands *inside* that interval the same poll is moved to just
    /// after the deadline. This never adds a poll and never raises the cadence beyond the
    /// enforced interval floor (AGENTS.md's cost warning) — it only changes when the one
    /// scheduled poll happens.
    public static func secondsUntilNextPoll(
        intervalMinutes: Int,
        nextDeadline: Date?,
        now: Date
    ) -> TimeInterval {
        let interval = Double(PollingEngine.clampedIntervalMinutes(intervalMinutes)) * 60
        let floor = Double(Preferences.minimumIntervalMinutes) * 60
        guard let nextDeadline else { return interval }
        let untilDeadline = nextDeadline.timeIntervalSince(now)
        // A deadline further out than this interval is answered by a later cycle's own
        // phasing; one already behind us is answered by the poll we're waiting on.
        guard untilDeadline > 0, untilDeadline <= interval else { return interval }
        return max(floor, untilDeadline + postResetGrace)
    }
}

/// Interval loop that drives periodic refreshes (U6). Kept separate from the store
/// so the cadence mechanics are isolated. `reschedule()` restarts the loop so a
/// changed poll interval takes effect immediately (R14).
@MainActor
public final class PollingEngine {
    private var task: Task<Void, Never>?
    private let intervalMinutes: @MainActor () -> Int
    private let nextResetDeadline: @MainActor () -> Date?
    private let now: @Sendable () -> Date
    private let tick: @MainActor () async -> Void
    /// How many times the sleep loop has been (re)started. Test seam for the R2M2
    /// re-phase: a two-minute floor makes the loop's own timing unobservable inside a
    /// fast unit test, but the restart itself is exactly what re-phasing means.
    private(set) var startCount = 0

    public init(
        intervalMinutes: @escaping @MainActor () -> Int,
        nextResetDeadline: @escaping @MainActor () -> Date? = { nil },
        now: @escaping @Sendable () -> Date = { Date() },
        tick: @escaping @MainActor () async -> Void
    ) {
        self.intervalMinutes = intervalMinutes
        self.nextResetDeadline = nextResetDeadline
        self.now = now
        self.tick = tick
    }

    nonisolated public static func clampedIntervalMinutes(_ minutes: Int) -> Int {
        max(Preferences.minimumIntervalMinutes, minutes)
    }

    /// Seconds this loop would sleep for right now. Exposed so the phasing decision can be
    /// asserted without waiting on a real timer.
    public var secondsUntilNextPoll: TimeInterval {
        PollPhasing.secondsUntilNextPoll(
            intervalMinutes: intervalMinutes(),
            nextDeadline: nextResetDeadline(),
            now: now()
        )
    }

    /// Start (or restart) the loop. Reads the interval and the next reset deadline each
    /// cycle, so a preference change or a newly captured deadline is picked up on the next
    /// wake without an explicit reschedule.
    public func start() {
        startCount += 1
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = self.secondsUntilNextPoll
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                await self.tick()
            }
        }
    }

    public func reschedule() { start() }

    /// R2M2: restart the sleep after an off-cadence refresh already answered this interval,
    /// so the next tick is a full interval later instead of firing on top of fresh data.
    /// Identical mechanics to `reschedule()`; separate name because the reason differs.
    public func rephase() { start() }

    public func stop() { task?.cancel(); task = nil }

    deinit { task?.cancel() }
}
