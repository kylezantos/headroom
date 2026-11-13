import Foundation
import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

@MainActor
@Suite
struct MiniPillTests {
    @Test func fallingDropStaysInsideTheVesselAtTheReadableFloor() throws {
        for frame in 0..<14 {
            let pose = MiniPillPose(mode: .drip, level: 0.7,
                                    date: Date(timeIntervalSince1970: Double(frame) / 30), reduceMotion: false)
            let drop = try #require(pose.drop)
            #expect(drop.width >= 1.2)
            #expect(MiniPillPose.inner.contains(drop))
        }
    }

    @Test func reduceMotionHasDateIndependentDistinctWorkingAndWaitingStills() {
        let dates = [Date(timeIntervalSince1970: 0.1), Date(timeIntervalSince1970: 0.8)]
        let waits = dates.map { MiniPillPose(mode: .drip, level: 0.46, date: $0, reduceMotion: true) }
        let work = dates.map { MiniPillPose(mode: .slosh, level: 0.46, date: $0, reduceMotion: true) }
        #expect(waits.allSatisfy { $0.level == 0 && $0.drop == nil && $0.ripple == nil && $0.wavePhase == nil })
        #expect(work.allSatisfy { $0.level == 0.46 && $0.drop == nil && $0.wavePhase == nil })
        #expect(waits[0].liquidPath == waits[1].liquidPath)
        #expect(work[0].liquidPath == work[1].liquidPath)
        #expect(waits[0].liquidPath != work[0].liquidPath)
    }

    @Test func drainUsesTheStartingLevelAndFinishesEmpty() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(MiniPillPose(mode: .drain(progress: 0), level: 0.73, date: date, reduceMotion: false).level == 0.73)
        #expect(MiniPillPose(mode: .drain(progress: 1), level: 0.73, date: date, reduceMotion: false).level == 0)
    }

    @Test func allRowCountsFitAndKeepTheirInputOrder() {
        for count in 1...6 {
            let layout = HalftonePillRow.Layout(count: count)
            #expect(layout.origins.count == count)
            #expect(layout.origins == layout.origins.sorted())
            #expect(layout.origins.first! >= 0)
            #expect(layout.origins.last! + layout.pillWidth <= layout.width)
            #expect(abs(layout.origins.first! - (layout.width - layout.origins.last! - layout.pillWidth)) < 0.001)
            #expect(layout.columns == (count >= 4 ? 3 : 4))
            if count >= 4 { #expect(layout.gap > 0) }
        }
    }

    /// U6 (Copilot plan): five pills draw five, and none is dropped.
    @Test func fivePillsDrawFiveAndDropNone() {
        #expect(HalftonePillRow.Layout(count: 5).origins.count == 5)
    }

    /// U7 (OpenCode plan): the one-to-five rows are pinned to the geometry they had before a
    /// sixth provider, so adding six moves none of them.
    @Test func oneToFivePillRowsKeepTheirGeometry() {
        let expected: [Int: (width: Double, gap: Double, columns: Int, origins: [Double])] = [
            1: (10, 7, 4, [17]),
            2: (10, 7, 4, [8.5, 25.5]),
            3: (10, 7, 4, [0, 17, 34]),
            4: (8.6, 3.2, 3, [0, 11.8, 23.6, 35.4]),
            5: (7.2, 2, 3, [0, 9.2, 18.4, 27.6, 36.8]),
        ]
        for (count, pinned) in expected {
            let layout = HalftonePillRow.Layout(count: count)
            #expect(layout.width == 44)
            #expect(layout.pillWidth == pinned.width)
            #expect(abs(layout.gap - pinned.gap) < 0.0001)
            #expect(layout.columns == pinned.columns)
            #expect(layout.origins.count == pinned.origins.count)
            for (origin, want) in zip(layout.origins, pinned.origins) { #expect(abs(origin - want) < 0.0001) }
        }
    }

    /// U7 (OpenCode plan, KTD14): six 6pt pills with 1.6pt gaps fill the same 44pt slot, so
    /// the Refresh button keeps its size; a seventh is never drawn.
    @Test func sixPillsAreSixPointsWideInsideTheSameSlot() {
        let layout = HalftonePillRow.Layout(count: 6)
        #expect(HalftonePillRow.Layout.maximumCount == 6)
        #expect(layout.width == 44)
        #expect(layout.pillWidth == 6)
        #expect(abs(layout.gap - 1.6) < 0.0001)
        #expect(layout.columns == 3)
        #expect(layout.origins.count == 6)
        for (index, origin) in layout.origins.enumerated() {
            #expect(abs(origin - Double(index) * 7.6) < 0.0001)
        }
        #expect(abs(layout.origins.last! + layout.pillWidth - 44) < 0.0001)
        #expect(HalftonePillRow.Layout(count: 7).origins.count == 6)
    }

    @Test nonisolated func timelinePausesWhenStillPinnedOrAfterItsTail() {
        let now = Date(timeIntervalSince1970: 10)
        #expect(LoadingTimeline<EmptyView>.isPaused(active: false, until: nil, now: now, pinned: false))
        #expect(LoadingTimeline<EmptyView>.isPaused(active: true, until: nil, now: now, pinned: true))
        #expect(!LoadingTimeline<EmptyView>.isPaused(active: false, until: now.addingTimeInterval(0.2), now: now, pinned: false))
        #expect(LoadingTimeline<EmptyView>.isPaused(active: false, until: now, now: now, pinned: false))
    }

    @Test nonisolated func timelineExpirySettlesTheWaveAndHoldWhilePinnedRendersStayFixed() {
        let lastTick = Date(timeIntervalSince1970: 10.9)
        let now = Date(timeIntervalSince1970: 11.01)
        let end = Date(timeIntervalSince1970: 10.55)
        let paused = LoadingTimeline<EmptyView>.isPaused(active: false, until: Date(timeIntervalSince1970: 11), now: now, pinned: false)
        let settled = LoadingTimeline<EmptyView>.frameDate(pinned: nil, paused: paused, now: now, scheduled: lastTick)
        #expect(settled == now)
        #expect(!LoadingCheckRecipe(isChecking: false, endedAt: end, now: settled, reduceMotion: false).isWorking)
        #expect(!LoadingMotionClock.isSloshing(active: false, endedAt: end, now: settled))
        let footerRecipe: (Date) -> ReprintRecipe = { date in
            ReprintRecipe(meters: [], automatic: true, currentMains: [:], run: nil,
                          probingAccounts: [], probeEndTimes: [:], spendInFlightProviders: [],
                          visibleWork: VisibleRefreshWork(clearedAt: Date(timeIntervalSince1970: 10.5)), now: date)
        }
        #expect(footerRecipe(settled).isEnabled)

        let running = LoadingTimeline<EmptyView>.frameDate(pinned: nil, paused: false, now: now, scheduled: lastTick)
        #expect(running == lastTick)
        #expect(LoadingCheckRecipe(isChecking: false, endedAt: end, now: running, reduceMotion: false).isWorking)
        #expect(footerRecipe(running).phase == .hold)
        let pinned = LoadingTimeline<EmptyView>.frameDate(pinned: lastTick, paused: true, now: now, scheduled: now)
        #expect(pinned == lastTick)
        #expect(LoadingMotionClock.isSloshing(active: false, endedAt: end, now: pinned))
    }
}
