import Foundation
import Testing

@testable import HeadroomCore

/// KTD15 / R9–R11 and scenarios V32–V35, AE5, AE6.
@Suite
struct CompanionFreshnessRuleTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func inputs(
        generatedAt: Double = 0, firstSeen: Double = 0, interval: Double? = 300, v3Only: Bool = false
    ) -> CompanionFreshnessInputs {
        CompanionFreshnessInputs(
            generatedAt: at(generatedAt), firstSeen: at(firstSeen),
            largestEffectiveIntervalSeconds: interval, isV3Only: v3Only)
    }

    /// AE5: a 5-minute Mac asleep for 30 minutes dims the app and Siri; widgets, Lock
    /// Screen and Control wait for their own 60-minute floor.
    @Test func fiveMinuteIntervalQuietForThirtyMinutesDimsAppButNotWidgetsUntilTheirFloor() {
        let quiet = inputs()
        #expect(CompanionFreshnessRule.threshold(quiet, surface: .app) == 15 * 60)
        #expect(!CompanionFreshnessRule.isDimmed(quiet, surface: .app, at: at(14.9)))
        for surface in [CompanionFreshnessSurface.app, .siri] {
            #expect(CompanionFreshnessRule.isDimmed(quiet, surface: surface, at: at(30)))
        }
        for surface in [CompanionFreshnessSurface.widget, .lockScreen, .control] {
            #expect(!CompanionFreshnessRule.isDimmed(quiet, surface: surface, at: at(30)))
            #expect(CompanionFreshnessRule.dimsAt(quiet, surface: surface) == at(60))
            #expect(CompanionFreshnessRule.isDimmed(quiet, surface: surface, at: at(60)))
        }
    }

    /// AE5: a 60-minute interval and a stretched Claude lane never dim healthy data.
    @Test func sixtyMinuteIntervalWithAStretchedLaneDoesNotDim() {
        let stretched = inputs(interval: 95 * 60)
        #expect(CompanionFreshnessRule.threshold(stretched, surface: .app) == 190 * 60)
        #expect(!CompanionFreshnessRule.isDimmed(stretched, surface: .app, at: at(150)))
        #expect(!CompanionFreshnessRule.isDimmed(stretched, surface: .widget, at: at(150)))
    }

    /// AE5: a healthy 5-minute Mac and a 60-minute WidgetKit reload gap: no entry dims.
    @Test func healthyMacWithAnHourBetweenWidgetReloadsNeverDimsAnEntry() {
        for reload in stride(from: 0.0, through: 240, by: 60) {
            // Each reload sees the heartbeat published just before it.
            let loaded = inputs(generatedAt: reload - 4, firstSeen: reload)
            for entry in stride(from: reload, to: reload + 60, by: 15) {
                #expect(!CompanionFreshnessRule.isDimmed(loaded, surface: .widget, at: at(entry)))
            }
        }
    }

    /// V33: a Mac clock 10 minutes ahead or behind neither sticks nor flickers.
    @Test func macClockSkewOfTenMinutesEitherWayNeitherSticksNorFlickers() {
        for skew in [-10.0, 10.0] {
            var dims: [Bool] = []
            var firstSeen = 0.0
            // A heartbeat every 5 minutes for an hour, sampled every minute; then silence.
            for minute in stride(from: 0.0, through: 120, by: 1) {
                if minute <= 60, minute.truncatingRemainder(dividingBy: 5) == 0 { firstSeen = minute }
                let current = inputs(generatedAt: firstSeen + skew, firstSeen: firstSeen)
                dims.append(CompanionFreshnessRule.isDimmed(current, surface: .app, at: at(minute)))
            }
            #expect(dims.prefix(75).allSatisfy { !$0 }, "skew \(skew)")
            #expect(dims.suffix(from: 75).allSatisfy { $0 }, "skew \(skew)")
        }
    }

    /// V35: a v3-only Mac on a 60-minute cadence never dims between publishes.
    @Test func v3OnlyMacOnAnHourlyCadenceNeverDims() {
        #expect(CompanionFreshnessRule.threshold(largestEffectiveIntervalSeconds: 300, isV3Only: true) == 7_200)
        for publish in stride(from: 0.0, through: 300, by: 60) {
            let current = inputs(generatedAt: publish, firstSeen: publish + 1, interval: nil, v3Only: true)
            #expect(!CompanionFreshnessRule.isDimmed(current, surface: .app, at: at(publish + 59)))
            #expect(!CompanionFreshnessRule.isDimmed(current, surface: .widget, at: at(publish + 59)))
        }
        let silent = inputs(interval: nil, v3Only: true)
        #expect(CompanionFreshnessRule.isDimmed(silent, surface: .app, at: at(120)))
    }

    /// V32: a phone offline for 3 hours dims as soon as it sees the old generation.
    @Test func phoneOfflineForThreeHoursDimsOnArrival() {
        let arrival = inputs(generatedAt: 0, firstSeen: 180)
        #expect(CompanionFreshnessRule.dimBase(arrival) == at(10))
        #expect(CompanionFreshnessRule.isDimmed(arrival, surface: .app, at: at(180)))
        #expect(CompanionFreshnessRule.isDimmed(arrival, surface: .widget, at: at(180)))
        #expect(CompanionFreshnessRule.lastHeardFromMac(arrival) == at(0))
    }

    @Test func invalidCadenceUsesTheConservativeFloorAndFastClockNeverNamesTheFuture() {
        #expect(CompanionFreshnessRule.threshold(largestEffectiveIntervalSeconds: .nan, isV3Only: false) == 900)
        #expect(CompanionFreshnessRule.threshold(largestEffectiveIntervalSeconds: 0, isV3Only: false) == 900)
        #expect(CompanionFreshnessRule.threshold(largestEffectiveIntervalSeconds: nil, isV3Only: false) == 900)
        let ahead = inputs(generatedAt: 600, firstSeen: 0)
        #expect(CompanionFreshnessRule.lastHeardFromMac(ahead) == at(0))
    }

    // MARK: Updated, past reset and opacity (R9, R11)

    private func window(
        observed: Double?, reset: Double?, freshness: WidgetWindowFreshness = .live, remaining: Double = 40
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .weekly, label: "Weekly", percentRemaining: remaining,
            resetSchedule: reset.map { .scheduled(at($0)) } ?? .unresolved(.absent),
            resetLabel: nil, observedAt: observed.map(at), severity: .low, freshness: freshness)
    }

    @Test func updatedNamesTheOldestLiveReadingNotThePublishTime() {
        let rows = [
            window(observed: 30, reset: nil), window(observed: 12, reset: nil),
            window(observed: 2, reset: nil, freshness: .stale(observedAt: at(2))),
            window(observed: nil, reset: nil, freshness: .unavailable(since: at(1))),
        ]
        #expect(CompanionFreshnessRule.updatedAt(rows) == at(12))
        #expect(CompanionFreshnessRule.updatedAt([]) == nil)
    }

    /// AE6: a weekly limit that reset at 2:00 pm while the Mac slept hides its number at 2:10.
    @Test func pastResetHidesTheNumberTenMinutesAfterTheDeadline() {
        let row = window(observed: -60, reset: 0)
        #expect(CompanionFreshnessRule.pastResetTime(row, at: at(9.9)) == nil)
        #expect(CompanionFreshnessRule.visiblePercentRemaining(row, at: at(9.9)) == 40)
        #expect(CompanionFreshnessRule.pastResetTime(row, at: at(10)) == at(0))
        #expect(CompanionFreshnessRule.pastResetTime(row, at: at(11)) == at(0))
        #expect(CompanionFreshnessRule.visiblePercentRemaining(row, at: at(11)) == nil)
        // A reading taken after the deadline is newer evidence and stays visible.
        #expect(CompanionFreshnessRule.pastResetTime(window(observed: 1, reset: 0), at: at(30)) == nil)
        #expect(CompanionFreshnessRule.pastResetTime(window(observed: 0, reset: nil), at: at(999)) == nil)
        let unavailable = window(observed: nil, reset: 0, freshness: .unavailable(since: at(-5)))
        #expect(CompanionFreshnessRule.visiblePercentRemaining(unavailable, at: at(1)) == nil)
        #expect(
            CompanionFreshnessCopy.pastReset(at: "2:00 pm") == "Reset at 2:00 pm · waiting for your Mac")
    }

    @Test func surfaceDimmingAndRowStaleNeverStack() {
        let stale = window(observed: 0, reset: nil, freshness: .stale(observedAt: at(0)))
        #expect(CompanionFreshnessRule.showsRowStaleTreatment(stale, surfaceDimmed: false))
        #expect(!CompanionFreshnessRule.showsRowStaleTreatment(stale, surfaceDimmed: true))
        #expect(!CompanionFreshnessRule.showsRowStaleTreatment(window(observed: 0, reset: nil), surfaceDimmed: false))
    }

    @Test func copyNeverBlamesSleep() {
        let line = CompanionFreshnessCopy.noUpdate(since: "9:41 am")
        #expect(line == "No update from your Mac since 9:41 am")
        #expect(!line.localizedCaseInsensitiveContains("asleep"))
        #expect(CompanionFreshnessCopy.waitingForMac == "Waiting for your Mac")
        #expect(CompanionFreshnessRule.lagGrace(chosenIntervalSeconds: 60) == 120)
        #expect(CompanionFreshnessRule.lagGrace(chosenIntervalSeconds: 600) == 600)
    }
}
