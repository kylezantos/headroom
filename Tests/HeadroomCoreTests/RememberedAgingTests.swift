import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U4 and U6: continuity never retains a window across two accounts,
/// and a remembered account's last reading ages honestly with no reading to replace it.
struct RememberedAgingTests {
    private let capturedAt = Date(timeIntervalSince1970: 2_000_000_000)
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60

    private func identity(_ id: String) -> AccountIdentityOutcome {
        .known(AccountIdentity(providerID: .claude, strength: .strong, digest: id, digestVersion: 1))
    }

    private func claude(
        _ windows: [UsageWindow],
        identity: AccountIdentityOutcome?,
        at date: Date,
        freshness: Freshness = .live
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .claude, windows: windows, planLabel: "Max",
            capturedAt: date, freshness: freshness, identity: identity
        )
    }

    private func full(at date: Date) -> [UsageWindow] {
        [
            UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: date.addingTimeInterval(3 * hour)),
            UsageWindow(kind: .weekly, utilization: 40, resetsAt: date.addingTimeInterval(4 * day)),
            UsageWindow(kind: .other("Weekly (Fable)"), utilization: 39, resetsAt: date.addingTimeInterval(4 * day)),
        ]
    }

    private func partial(at date: Date) -> [UsageWindow] { Array(full(at: date).prefix(2)) }

    private func defaults() -> UserDefaults {
        let suite = "headroom.remembered-aging.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Identity-aware continuity (U4)

    @Test func sameAccountPartialCaptureRetainsTheModelRowAsStale() {
        let later = capturedAt.addingTimeInterval(300)
        let merged = UsageContinuityPolicy.mergedSnapshot(
            claude(partial(at: later), identity: identity("a"), at: later),
            with: claude(full(at: capturedAt), identity: identity("a"), at: capturedAt),
            at: later
        )
        #expect(merged.windows.map(\.kind) == [.fiveHour, .weekly, .other("Weekly (Fable)")])
        #expect(merged.windows.last?.freshness == .stale(observedAt: capturedAt))
        #expect(merged.identity == identity("a"))
    }

    /// The open `BUGS.md` entry: a login switch followed by a partial capture.
    @Test func partialCaptureAfterALoginSwitchRetainsNoModelRowFromThePreviousLogin() {
        let later = capturedAt.addingTimeInterval(300)
        let merged = UsageContinuityPolicy.mergedSnapshot(
            claude(partial(at: later), identity: identity("b"), at: later),
            with: claude(full(at: capturedAt), identity: identity("a"), at: capturedAt),
            at: later
        )
        #expect(merged.windows.map(\.kind) == [.fiveHour, .weekly])
    }

    @Test func aPriorWithNoIdentityRetainsNothingOnceTheFreshReadingNamesAnAccount() {
        let later = capturedAt.addingTimeInterval(300)
        let merged = UsageContinuityPolicy.mergedSnapshot(
            claude(partial(at: later), identity: identity("a"), at: later),
            with: claude(full(at: capturedAt), identity: nil, at: capturedAt),
            at: later
        )
        #expect(merged.windows.map(\.kind) == [.fiveHour, .weekly])
    }

    /// R4: a live reading with no readable identity takes no history from a known account.
    @Test func anAbsentIdentityRetainsNothing() {
        let later = capturedAt.addingTimeInterval(300)
        let merged = UsageContinuityPolicy.mergedSnapshot(
            claude(partial(at: later), identity: .absent, at: later),
            with: claude(full(at: capturedAt), identity: identity("a"), at: capturedAt),
            at: later
        )
        #expect(merged.windows.map(\.kind) == [.fiveHour, .weekly])
    }

    @Test func aProviderThatReportsNoIdentityKeepsTheEarlierBehavior() {
        let later = capturedAt.addingTimeInterval(300)
        let merged = UsageContinuityPolicy.mergedSnapshot(
            claude(partial(at: later), identity: nil, at: later),
            with: claude(full(at: capturedAt), identity: nil, at: capturedAt),
            at: later
        )
        #expect(merged.windows.map(\.kind) == [.fiveHour, .weekly, .other("Weekly (Fable)")])
    }

    @Test func theDigestRoundTripsThroughTheCacheAndTheEnvelopeStaysSchemaTwo() throws {
        let defaults = defaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        UsageContinuityCache(defaults: defaults).save(
            claude(full(at: capturedAt), identity: identity("digest-a"), at: capturedAt), for: key
        )

        let restored = try #require(UsageContinuityCache(defaults: defaults).load()[key])
        #expect(restored.identity == identity("digest-a"))

        let data = try #require(defaults.data(forKey: "usageContinuitySnapshots.v2"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 2)
    }

    /// The relaunch half of the `BUGS.md` case: the restored record names account A.
    @Test func aRestoredRecordFromAnotherAccountRetainsNothingAcrossARelaunch() throws {
        let defaults = defaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        UsageContinuityCache(defaults: defaults).save(
            claude(full(at: capturedAt), identity: identity("a"), at: capturedAt), for: key
        )
        let later = capturedAt.addingTimeInterval(600)
        let restored = UsageContinuityPolicy.restoredSnapshot(
            UsageContinuityCache(defaults: defaults).load()[key], for: .claude, at: later
        )

        let merged = UsageContinuityPolicy.mergedSnapshot(
            claude(partial(at: later), identity: identity("b"), at: later), with: restored, at: later
        )
        #expect(merged.windows.map(\.kind) == [.fiveHour, .weekly])
    }

    @Test func aRecordWithoutADigestStillDecodes() throws {
        let defaults = defaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        UsageContinuityCache(defaults: defaults).save(claude(full(at: capturedAt), identity: nil, at: capturedAt), for: key)
        let restored = try #require(UsageContinuityCache(defaults: defaults).load()[key])
        #expect(restored.identity == nil)
        #expect(restored.windows.count == 3)
    }

    // MARK: Remembered aging (U6)

    private func remembered(at date: Date) -> UsageSnapshot {
        UsageContinuityPolicy.rememberedSnapshot(claude(full(at: capturedAt), identity: identity("a"), at: capturedAt), at: date)
    }

    @Test func beforeResetAWindowIsStaleWithItsOriginalObservationTimeAndNumber() {
        let aged = remembered(at: capturedAt.addingTimeInterval(2 * hour))
        #expect(aged.windows.map(\.freshness) == Array(repeating: .stale(observedAt: capturedAt), count: 3))
        #expect(aged.windows.map(\.utilization) == [20, 40, 39])
        #expect(aged.capturedAt == capturedAt)
    }

    /// Covers AE2.
    @Test func oneSecondAfterResetTheWindowIsUnavailableSinceItsReset() {
        let fiveHourReset = capturedAt.addingTimeInterval(3 * hour)
        let aged = remembered(at: fiveHourReset.addingTimeInterval(1))
        #expect(aged.windows[0].freshness == .unavailable(since: fiveHourReset))
        // The weekly reset has not passed: one unavailable, the rest stale.
        #expect(aged.windows[1].freshness == .stale(observedAt: capturedAt))
        #expect(aged.windows[2].freshness == .stale(observedAt: capturedAt))
    }

    @Test func nineDaysLaterEveryWindowIsUnavailableAndNoneIsDropped() {
        let aged = remembered(at: capturedAt.addingTimeInterval(9 * day))
        #expect(aged.windows.count == 3)
        #expect(aged.windows.allSatisfy { $0.freshness.isUnavailable })
        #expect(aged.windows[1].freshness == .unavailable(since: capturedAt.addingTimeInterval(4 * day)))
        #expect(aged.freshness != .pending)
    }

    @Test func agingIsIdempotentAcrossRepeatedPasses() {
        let once = remembered(at: capturedAt.addingTimeInterval(9 * day))
        let twice = UsageContinuityPolicy.rememberedSnapshot(once, at: capturedAt.addingTimeInterval(30 * day))
        #expect(twice == once)
    }

    @Test func aWindowWithNoScheduledResetFailsClosedAfterTheFallbackLifetime() {
        let modelRow = UsageWindow(
            kind: .other("Weekly (Fable)"), utilization: 39,
            resetSchedule: .unresolved(.unparseable), resetLabel: nil
        )
        let stored = claude([modelRow], identity: identity("a"), at: capturedAt)
        let before = UsageContinuityPolicy.rememberedSnapshot(stored, at: capturedAt.addingTimeInterval(6 * day))
        let after = UsageContinuityPolicy.rememberedSnapshot(stored, at: capturedAt.addingTimeInterval(7 * day + 1))
        #expect(before.windows[0].freshness == .stale(observedAt: capturedAt))
        #expect(after.windows[0].freshness == .unavailable(since: capturedAt.addingTimeInterval(7 * day)))
    }

    @Test func theOrdinaryModeStillDropsAnExpiredFiveHourWindow() {
        let restored = UsageContinuityPolicy.restoredSnapshot(
            claude(full(at: capturedAt), identity: nil, at: capturedAt),
            for: .claude,
            at: capturedAt.addingTimeInterval(4 * hour)
        )
        #expect(restored.windows.map(\.kind) == [.weekly, .other("Weekly (Fable)")])
    }

    // MARK: Wording (U6)

    @Test func lastReadReadsMinutesThenHoursThenDays() {
        func label(_ seconds: TimeInterval) -> String? {
            Countdown.updatedLabel(capturedAt: capturedAt, now: capturedAt.addingTimeInterval(seconds))
        }
        #expect(label(2 * 60) == "2 min ago")
        #expect(label(3 * hour) == "3 hr ago")
        #expect(label(23 * hour + 59 * 60) == "23 hr ago")
        #expect(label(24 * hour) == "1 day ago")
        #expect(label(9 * day + 5 * hour) == "9 days ago")
    }

    @Test func theLastReadTagIsTheSameWordingOnEverySurface() {
        #expect(Countdown.lastReadLabel(capturedAt: nil, now: capturedAt) == nil)
        #expect(Countdown.lastReadLabel(capturedAt: capturedAt, now: capturedAt.addingTimeInterval(120)) == "Last read 2 min ago")
        #expect(Countdown.lastReadLabel(capturedAt: capturedAt, now: capturedAt.addingTimeInterval(2 * day)) == "Last read 2 days ago")
    }

    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private let locale = Locale(identifier: "en_US")
    /// Friday 25 Sep 2026, 10:00 AM in Los Angeles.
    private let now = Date(timeIntervalSince1970: 1_790_355_600)

    private func line(_ resetAt: Date) -> String {
        Countdown.resetNotReadLine(resetAt: resetAt, now: now, timeZone: zone, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func resetLineSaysWhenTheWindowResetAndAddsTheDateOnceAWeekdayIsAmbiguous() {
        #expect(line(now.addingTimeInterval(-2 * hour)) == "Reset today at 8:00 AM · not read since")
        #expect(line(now.addingTimeInterval(-20 * hour)) == "Reset yesterday at 2:00 PM · not read since")
        #expect(line(now.addingTimeInterval(-2 * day)) == "Reset Wednesday at 10:00 AM · not read since")
        #expect(line(now.addingTimeInterval(-6 * day)) == "Reset Saturday at 10:00 AM · not read since")
        #expect(line(now.addingTimeInterval(-7 * day)) == "Reset Sep 18 at 10:00 AM · not read since")
    }
}
