import Foundation
import Testing
@testable import HeadroomCore

/// R2M5 / U3: the freshness stamp, lifted from the Mac footer so the phone dates its numbers
/// the same way. Wording first (migrated from the Mac's resolver tests), then aggregation.
@Suite
struct FreshnessStampTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    // MARK: - Wording

    /// Beside Refresh the stamp needs no "Updated" verb.
    @Test func aLiveCaptureReadsAsABareAge() {
        let stamp = FreshnessStamp.resolve(.init(oldestLive: minutesAgo(8)), now: now)
        #expect(stamp.kind == .updated)
        #expect(stamp.text == "8 min ago")
        #expect(stamp.rollValue == 8)
    }

    @Test func aFreshCaptureReadsAsSentenceCase() {
        #expect(FreshnessStamp.resolve(.init(oldestLive: now), now: now).text == "Just now")
    }

    /// Retained numbers on screen still carry a date, and say they are not live.
    @Test func nothingLiveFallsBackToTheNewestObservation() {
        let stamp = FreshnessStamp.resolve(.init(newestCheck: minutesAgo(12)), now: now)
        #expect(stamp.kind == .lastChecked)
        #expect(stamp.text == "Checked 12 min ago")
        #expect(stamp.rollValue == 12)
    }

    @Test func firstRunSaysSoRatherThanGoingSilent() {
        let stamp = FreshnessStamp.resolve(.init(), now: now)
        #expect(stamp.kind == .never)
        #expect(stamp.text == "Not checked yet")
        #expect(stamp.rollValue == nil)
    }

    /// The roll follows whole elapsed minutes, never negative under a backwards clock.
    @Test func theRollValueIsFlooredAndNonnegative() {
        #expect(FreshnessStamp.resolve(.init(oldestLive: now.addingTimeInterval(-179)), now: now).rollValue == 2)
        #expect(FreshnessStamp.resolve(.init(oldestLive: now.addingTimeInterval(90)), now: now).rollValue == 0)
    }

    // MARK: - Aggregation

    private func window(_ freshness: UsageWindowFreshness = .live, observedAt: Date? = nil) -> UsageWindow {
        UsageWindow(kind: .fiveHour, utilization: 40, resetsAt: now.addingTimeInterval(3600),
                    freshness: freshness, observedAt: observedAt)
    }

    private func snapshot(_ freshness: Freshness, capturedAt: Date?, windows: [UsageWindow]) -> UsageSnapshot {
        UsageSnapshot(providerID: .claude, windows: windows, planLabel: nil, capturedAt: capturedAt, freshness: freshness)
    }

    /// Plan U3: the oldest live observation wins, so the stamp never claims data is fresher
    /// than the least-fresh account on screen.
    @Test func theOldestLiveObservationWins() {
        let stamp = FreshnessStamp.resolve(snapshots: [
            snapshot(.live, capturedAt: minutesAgo(2), windows: [window()]),
            snapshot(.live, capturedAt: minutesAgo(9), windows: [window()]),
            snapshot(.live, capturedAt: minutesAgo(5), windows: [window()]),
        ], now: now)
        #expect(stamp.text == "9 min ago")
    }

    /// A synced live row carries its own source time; that, not the snapshot's later
    /// publication, is what the stamp dates.
    @Test func aLiveWindowsOwnAnchorOutranksTheCaptureTime() {
        let anchors = FreshnessStamp.Anchors(snapshots: [
            snapshot(.live, capturedAt: minutesAgo(1), windows: [
                window(observedAt: minutesAgo(6)),
                window(observedAt: minutesAgo(4)),
            ]),
        ])
        #expect(anchors.oldestLive == minutesAgo(6))
        #expect(anchors.newestCheck == minutesAgo(4))
    }

    /// The Mac's provider rows carry no per-window anchor, so the capture time stands in —
    /// the stamp the footer has always shown.
    @Test func liveWindowsWithoutAnAnchorUseTheCaptureTime() {
        let anchors = FreshnessStamp.Anchors(snapshots: [
            snapshot(.live, capturedAt: minutesAgo(3), windows: [window(), window()]),
            snapshot(.live, capturedAt: minutesAgo(7), windows: []),
        ])
        #expect(anchors.oldestLive == minutesAgo(7))
        #expect(anchors.newestCheck == minutesAgo(3))
    }

    /// A retained model row inside a live capture is not a live reading: it must not drag
    /// the age back to its own older observation.
    @Test func aRetainedRowInsideALiveCaptureDoesNotAgeTheStamp() {
        let anchors = FreshnessStamp.Anchors(snapshots: [
            snapshot(.live, capturedAt: minutesAgo(2), windows: [
                window(),
                window(.stale(observedAt: minutesAgo(40))),
                window(.unavailable(since: minutesAgo(90)), observedAt: minutesAgo(120)),
            ]),
        ])
        #expect(anchors.oldestLive == minutesAgo(2))
        #expect(FreshnessStamp.resolve(anchors, now: now).text == "2 min ago")
    }

    /// Plan U3: a stale-only set reads "Checked N ago", from the newest retained anchor.
    @Test func aStaleOnlySetReadsChecked() {
        let stamp = FreshnessStamp.resolve(snapshots: [
            snapshot(.stale(.transient("offline")), capturedAt: minutesAgo(30), windows: [
                window(.stale(observedAt: minutesAgo(30))),
            ]),
            snapshot(.stale(.transient("offline")), capturedAt: minutesAgo(50), windows: [
                window(.stale(observedAt: minutesAgo(14))),
                window(.unavailable(since: minutesAgo(3)), observedAt: minutesAgo(45)),
            ]),
        ], now: now)
        #expect(stamp.kind == .lastChecked)
        #expect(stamp.text == "Checked 14 min ago")
    }

    /// Each retained row keeps its own original anchor: the snapshot's later capture time
    /// does not restamp a row that carries one.
    @Test func retainedRowsKeepTheirOwnAnchors() {
        let anchors = FreshnessStamp.Anchors(snapshots: [
            snapshot(.stale(.transient("offline")), capturedAt: minutesAgo(1), windows: [
                window(.stale(observedAt: minutesAgo(25))),
            ]),
        ])
        #expect(anchors.oldestLive == nil)
        #expect(anchors.newestCheck == minutesAgo(25))
    }

    /// With no window anchor at all, a retained snapshot falls back to its capture time.
    @Test func aRetainedSnapshotWithoutWindowAnchorsUsesItsCaptureTime() {
        let anchors = FreshnessStamp.Anchors(snapshots: [
            snapshot(.stale(.transient("offline")), capturedAt: minutesAgo(18), windows: [window()]),
        ])
        #expect(anchors.newestCheck == minutesAgo(18))
    }

    /// Live outranks retained even when a retained row is newer.
    @Test func liveAndRetainedTogetherReadAsTheLiveAge() {
        let stamp = FreshnessStamp.resolve(snapshots: [
            snapshot(.live, capturedAt: minutesAgo(10), windows: [window()]),
            snapshot(.stale(.transient("offline")), capturedAt: minutesAgo(1), windows: [
                window(.stale(observedAt: minutesAgo(1))),
            ]),
        ], now: now)
        #expect(stamp.kind == .updated)
        #expect(stamp.text == "10 min ago")
    }

    /// Plan U3: no live data reads "Not checked yet".
    @Test func pendingSnapshotsReadNotCheckedYet() {
        let stamp = FreshnessStamp.resolve(snapshots: [
            snapshot(.pending, capturedAt: nil, windows: []),
            snapshot(.pending, capturedAt: nil, windows: []),
        ], now: now)
        #expect(stamp == FreshnessStamp(kind: .never, text: "Not checked yet", rollValue: nil))
        #expect(FreshnessStamp.resolve(snapshots: [UsageSnapshot](), now: now).kind == .never)
    }
}
