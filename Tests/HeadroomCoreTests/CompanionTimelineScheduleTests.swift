import Foundation
import Testing
@testable import HeadroomCore

/// U13 (iOS parity plan): widget timelines cross into the dimmed and past-reset states on
/// their own, and a healthy Mac never produces a dimmed entry (KTD15, AE5, AE6).
struct CompanionTimelineScheduleTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let minute: TimeInterval = 60

    static func window(
        _ kind: WidgetWindowKind, deadline: Date, observedAt: Date? = nil,
        freshness: WidgetWindowFreshness = .live
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind, label: kind == .fiveHour ? "5h" : "Weekly", percentRemaining: 40,
            resetSchedule: .scheduled(deadline), resetLabel: nil, observedAt: observedAt,
            severity: .healthy, freshness: freshness)
    }

    static func envelope(_ windows: [WidgetWindowSummary], generatedAt: Date = now) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: generatedAt, status: .enabled,
            providers: [WidgetProviderSummary(id: "claude", displayName: "Claude", planLabel: nil,
                                              freshness: .live, windows: windows, renewalDate: nil)],
            apiSpendProviders: [], widgetProviderSelection: ["claude"])
    }

    static func inputs(generatedAt: Date, firstSeen: Date, interval: Double? = 300, v3Only: Bool = false)
        -> CompanionFreshnessInputs
    {
        CompanionFreshnessInputs(generatedAt: generatedAt, firstSeen: firstSeen,
                                 largestEffectiveIntervalSeconds: interval, isV3Only: v3Only)
    }

    // MARK: Dim moment (KTD15)

    @Test func aWidgetTimelineHasAnEntryAtTheWidgetDimMoment() {
        let inputs = Self.inputs(generatedAt: Self.now, firstSeen: Self.now)
        let timeline = CompanionTimelineSchedule.timeline(for: Self.envelope([]), freshness: inputs, now: Self.now)
        // A 5-minute Mac's rule threshold is 15 minutes; widgets floor it at 60.
        let dimsAt = Self.now.addingTimeInterval(60 * Self.minute)
        #expect(timeline.entryDates.contains(dimsAt))
        #expect(timeline.dimsAt == dimsAt)
        #expect(!CompanionFreshnessRule.isDimmed(inputs, surface: .widget, at: dimsAt.addingTimeInterval(-1)))
        #expect(CompanionFreshnessRule.isDimmed(inputs, surface: .widget, at: dimsAt))
    }

    @Test func aStretchedCadenceMovesTheDimMomentPastTheFloor() {
        // 2 × a 45-minute effective interval beats the 60-minute widget floor.
        let inputs = Self.inputs(generatedAt: Self.now, firstSeen: Self.now, interval: 45 * 60)
        let timeline = CompanionTimelineSchedule.timeline(for: Self.envelope([]), freshness: inputs, now: Self.now)
        #expect(timeline.dimsAt == Self.now.addingTimeInterval(90 * Self.minute))
    }

    @Test func aV3OnlySnapshotDimsAtTheHundredTwentyMinuteThreshold() {
        // The Mac widget's case: its local file has no cadence, so it uses the v3-only rule
        // against the Mac's own export time (generatedAt and first-seen are one clock).
        let exported = Self.now.addingTimeInterval(-30 * Self.minute)
        let inputs = Self.inputs(generatedAt: exported, firstSeen: exported, interval: nil, v3Only: true)
        let timeline = CompanionTimelineSchedule.timeline(for: Self.envelope([]), freshness: inputs, now: Self.now)
        #expect(timeline.dimsAt == exported.addingTimeInterval(120 * Self.minute))
        #expect(timeline.entryDates.contains(exported.addingTimeInterval(120 * Self.minute)))
    }

    @Test func theReloadIsRequestedNoLaterThanTheDimMoment() {
        // Data first seen 50 minutes ago dims in 10 minutes: the reload comes then, before the
        // usual 15-minute refresh, so a healthy Mac's newer data lands before anything dims.
        let seen = Self.now.addingTimeInterval(-50 * Self.minute)
        let inputs = Self.inputs(generatedAt: seen, firstSeen: seen)
        let timeline = CompanionTimelineSchedule.timeline(for: Self.envelope([]), freshness: inputs, now: Self.now)
        #expect(timeline.reloadDate == Self.now.addingTimeInterval(10 * Self.minute))
        #expect(timeline.entryDates.contains(timeline.reloadDate))
    }

    @Test func aDistantDimMomentKeepsTheRegularRefresh() {
        let inputs = Self.inputs(generatedAt: Self.now, firstSeen: Self.now)
        let timeline = CompanionTimelineSchedule.timeline(for: Self.envelope([]), freshness: inputs, now: Self.now)
        #expect(timeline.reloadDate == WidgetTimelineSchedule.refreshDate(after: Self.now))
    }

    @Test func anAlreadyDimmedSnapshotHasNoFutureDimEntryAndTheRegularRefresh() {
        let old = Self.now.addingTimeInterval(-3 * 3_600)
        let inputs = Self.inputs(generatedAt: old, firstSeen: old)
        let timeline = CompanionTimelineSchedule.timeline(for: Self.envelope([]), freshness: inputs, now: Self.now)
        #expect(timeline.dimsAt == nil)
        #expect(timeline.reloadDate == WidgetTimelineSchedule.refreshDate(after: Self.now))
        #expect(timeline.entryDates.allSatisfy { CompanionFreshnessRule.isDimmed(inputs, surface: .widget, at: $0) })
    }

    @Test func noFreshnessInputsKeepsTheBaseSchedule() {
        // Demo and status states carry no Mac clock: nothing dims.
        let envelope = Self.envelope([Self.window(.fiveHour, deadline: Self.now.addingTimeInterval(3_600))])
        let timeline = CompanionTimelineSchedule.timeline(for: envelope, freshness: nil, now: Self.now)
        #expect(timeline.dimsAt == nil)
        #expect(timeline.reloadDate == WidgetTimelineSchedule.refreshDate(after: Self.now))
        #expect(Set(WidgetTimelineSchedule.entryDates(for: envelope, now: Self.now)).isSubset(of: Set(timeline.entryDates)))
    }

    // MARK: Past reset (R11, AE6)

    @Test func everyShownWindowGetsAnEntryTenMinutesAfterItsReset() {
        let fiveHour = Self.now.addingTimeInterval(40 * Self.minute)
        let weekly = Self.now.addingTimeInterval(50 * Self.minute)
        let envelope = Self.envelope([Self.window(.fiveHour, deadline: fiveHour), Self.window(.weekly, deadline: weekly)])
        let inputs = Self.inputs(generatedAt: Self.now, firstSeen: Self.now)
        let timeline = CompanionTimelineSchedule.timeline(for: envelope, freshness: inputs, now: Self.now)
        #expect(timeline.entryDates.contains(fiveHour.addingTimeInterval(10 * Self.minute)))
        #expect(timeline.entryDates.contains(weekly.addingTimeInterval(10 * Self.minute)))
        // At that entry the rule hides the number.
        let crossing = fiveHour.addingTimeInterval(10 * Self.minute)
        #expect(CompanionFreshnessRule.pastResetTime(envelope.providers[0].windows[0], at: crossing) == fiveHour)
    }

    @Test func aReadingTakenAfterTheResetSchedulesNoCrossing() {
        let deadline = Self.now.addingTimeInterval(-5 * Self.minute)
        let window = Self.window(.fiveHour, deadline: deadline, observedAt: Self.now.addingTimeInterval(-1 * Self.minute))
        #expect(CompanionTimelineSchedule.pastResetCrossings(Self.envelope([window])).isEmpty)
    }

    @Test func anUnavailableWindowSchedulesNoCrossing() {
        let deadline = Self.now.addingTimeInterval(20 * Self.minute)
        let window = Self.window(.fiveHour, deadline: deadline, freshness: .unavailable(since: Self.now))
        #expect(CompanionTimelineSchedule.pastResetCrossings(Self.envelope([window])).isEmpty)
    }

    @Test func aCrossingAlreadyPassedIsNotScheduled() {
        let deadline = Self.now.addingTimeInterval(-30 * Self.minute)
        let timeline = CompanionTimelineSchedule.timeline(
            for: Self.envelope([Self.window(.fiveHour, deadline: deadline)]), freshness: nil, now: Self.now)
        #expect(timeline.entryDates.allSatisfy { $0 >= Self.now })
        #expect(timeline.entryDates.first == Self.now)
    }

    @Test func entriesAreSortedAndUnique() {
        let deadline = Self.now.addingTimeInterval(5 * Self.minute)
        let envelope = Self.envelope([Self.window(.fiveHour, deadline: deadline), Self.window(.weekly, deadline: deadline)])
        let inputs = Self.inputs(generatedAt: Self.now, firstSeen: Self.now)
        let dates = CompanionTimelineSchedule.timeline(for: envelope, freshness: inputs, now: Self.now).entryDates
        #expect(dates == Array(Set(dates)).sorted())
    }

    // MARK: AE5 end to end

    /// A healthy 5-minute Mac publishes every five minutes; WidgetKit only reloads the widget
    /// every 60 minutes. Each reload reads the latest generation and is the first process to
    /// see it. No entry shown before the next reload is dimmed.
    @Test func aHealthyFiveMinuteMacWithASixtyMinuteReloadGapNeverDims() {
        let start = Self.now
        let publish: TimeInterval = 5 * Self.minute
        let gap: TimeInterval = 60 * Self.minute
        for offset in stride(from: 0, to: publish, by: Self.minute) {
            for reload in 0..<12 {
                let reloadAt = start.addingTimeInterval(offset + Double(reload) * gap)
                let elapsed = reloadAt.timeIntervalSince(start)
                let generatedAt = start.addingTimeInterval((elapsed / publish).rounded(.down) * publish)
                let inputs = Self.inputs(generatedAt: generatedAt, firstSeen: reloadAt)
                let envelope = Self.envelope([Self.window(.fiveHour, deadline: reloadAt.addingTimeInterval(2 * 3_600))],
                                             generatedAt: generatedAt)
                let timeline = CompanionTimelineSchedule.timeline(for: envelope, freshness: inputs, now: reloadAt)
                let shown = timeline.entryDates.filter { $0 < reloadAt.addingTimeInterval(gap) }
                #expect(!shown.isEmpty)
                for entry in shown {
                    #expect(!CompanionFreshnessRule.isDimmed(inputs, surface: .widget, at: entry),
                            "offset \(offset) reload \(reload) entry \(entry.timeIntervalSince(reloadAt))")
                }
            }
        }
    }

    /// AE5: the same 5-minute Mac asleep for 30 minutes does not dim a widget (the app does),
    /// and the widget dims once its 60-minute floor passes, without a reload.
    @Test func aSleepingMacDimsTheWidgetOnlyPastItsFloor() {
        let lastPublish = Self.now
        let inputs = Self.inputs(generatedAt: lastPublish, firstSeen: lastPublish.addingTimeInterval(Self.minute))
        let thirtyMinutesLater = lastPublish.addingTimeInterval(30 * Self.minute)
        #expect(CompanionFreshnessRule.isDimmed(inputs, surface: .app, at: thirtyMinutesLater))
        let timeline = CompanionTimelineSchedule.timeline(for: Self.envelope([], generatedAt: lastPublish),
                                                          freshness: inputs, now: thirtyMinutesLater)
        #expect(!CompanionFreshnessRule.isDimmed(inputs, surface: .widget, at: thirtyMinutesLater))
        let dimmed = timeline.entryDates.filter { CompanionFreshnessRule.isDimmed(inputs, surface: .widget, at: $0) }
        #expect(dimmed == [lastPublish.addingTimeInterval(61 * Self.minute)])
    }
}
