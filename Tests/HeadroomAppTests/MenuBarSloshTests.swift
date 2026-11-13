import Foundation
import AppKit
import Testing
import HeadroomCore
@testable import Headroom

@MainActor
@Suite(.sharedAppState, .serialized) struct MenuBarSloshTests {
    private let key = AccountKey(providerID: .claude, accountID: .primary)
    private let start = Date(timeIntervalSince1970: 100.25)

    private func meter(pending: Bool = false, live: Bool = false,
                       source: AccountKey? = nil, provider: ProviderID? = .claude) -> MenuBarMeter {
        MenuBarMeter(summary: .init(text: "73%", providerID: provider, detail: "Claude",
            isNeutral: pending), fill: pending ? nil : 0.73, awaitingFirstReading: pending,
            isLiveReading: live, sourceAccountKey: source ?? key)
    }

    @Test func sloshUsesTheSharedWallClockAndStopsAtTheNextWrap() {
        let motion = MenuBarSlosh(autoTick: false)
        let meters = [meter(pending: true)]
        motion.update(meters: meters, automatic: false, updating: [.claude], reduceMotion: false, at: start)
        #expect(motion.presentation(for: meters[0], automatic: false, at: start).wavePhase
            == LoadingMotionClock.sloshPhase(at: start))
        motion.update(meters: meters, automatic: false, updating: [], reduceMotion: false,
                      at: start.addingTimeInterval(0.2))
        #expect(motion.presentation(for: meters[0], automatic: false,
                                   at: Date(timeIntervalSince1970: 100.99)).wavePhase != nil)
        #expect(motion.presentation(for: meters[0], automatic: false,
                                   at: Date(timeIntervalSince1970: 101)).wavePhase == nil)
        #expect(motion.deadline == Date(timeIntervalSince1970: 101))
    }

    @Test func firstLiveReadingPlaysFourFramesThenStops() {
        let motion = MenuBarSlosh(autoTick: false)
        motion.update(meters: [meter(pending: true)], automatic: false, updating: [], reduceMotion: false, at: start)
        let live = meter(live: true)
        motion.update(meters: [live], automatic: false, updating: [], reduceMotion: false, at: start)
        for frame in 0..<LoadingMotionConstants.menuBarPrintFrameCount {
            let date = start.addingTimeInterval(Double(frame) * 0.1 + 0.001)
            #expect(motion.presentation(for: live, automatic: false, at: date).ink == .printing(frame: frame))
        }
        #expect(motion.presentation(for: live, automatic: false, at: start.addingTimeInterval(0.401)).ink == .solid)
        #expect(!motion.isActive)
    }

    @Test func automaticIdentitySurvivesNeutralBecomingAProviderSummary() {
        let motion = MenuBarSlosh(autoTick: false)
        motion.update(meters: [meter(pending: true, provider: nil)], automatic: true,
                      updating: [.claude], reduceMotion: false, at: start)
        let live = meter(live: true)
        motion.update(meters: [live], automatic: true, updating: [], reduceMotion: false, at: start)
        #expect(motion.presentation(for: live, automatic: true, at: start).ink == .printing(frame: 0))
    }

    @Test func automaticPendingPillFinishesItsFinalActiveProbeWave() {
        let motion = MenuBarSlosh(autoTick: false)
        let pending = meter(pending: true, provider: nil)
        motion.update(meters: [pending], automatic: true, updating: [.claude],
                      reduceMotion: false, at: start)
        motion.update(meters: [pending], automatic: true, updating: [], reduceMotion: false,
                      probeEndTimes: [.claude: start.addingTimeInterval(0.2)],
                      at: start.addingTimeInterval(0.2))
        #expect(motion.presentation(for: pending, automatic: true,
                                   at: Date(timeIntervalSince1970: 100.99)).wavePhase != nil)
        #expect(motion.presentation(for: pending, automatic: true,
                                   at: Date(timeIntervalSince1970: 101)).wavePhase == nil)
        #expect(motion.deadline == Date(timeIntervalSince1970: 101))
    }

    @Test func staleLandingAndSourceSwitchNeverPretendAFreshReadingArrived() {
        let motion = MenuBarSlosh(autoTick: false)
        motion.update(meters: [meter(pending: true)], automatic: false, updating: [], reduceMotion: false, at: start)
        let stale = meter()
        motion.update(meters: [stale], automatic: false, updating: [], reduceMotion: false, at: start)
        #expect(motion.presentation(for: stale, automatic: false, at: start).ink == .solid)
        motion.update(meters: [meter(pending: true)], automatic: false, updating: [], reduceMotion: false, at: start)
        let other = meter(live: true, source: AccountKey(providerID: .claude, accountID: AccountID("work")))
        motion.update(meters: [other], automatic: false, updating: [], reduceMotion: false, at: start)
        #expect(motion.presentation(for: other, automatic: false, at: start).ink == .solid)
    }

    @Test func reduceMotionUsesUniformBlendFramesAndNoWave() {
        let motion = MenuBarSlosh(autoTick: false)
        motion.update(meters: [meter(pending: true)], automatic: false, updating: [.claude], reduceMotion: true, at: start)
        let live = meter(live: true)
        motion.update(meters: [live], automatic: false, updating: [.claude], reduceMotion: true, at: start)
        #expect(motion.presentation(for: live, automatic: false, at: start).ink == .crossfade(frame: 0))
        #expect(motion.presentation(for: live, automatic: false, at: start).wavePhase == nil)
        #expect(motion.presentation(for: live, automatic: false, at: start.addingTimeInterval(0.401)).ink == .solid)
    }

    @Test func settingsPreviewIsStaticEvenWhenMetersLandLive() {
        let pending = meter(pending: true)
        #expect(MenuBarSlosh.staticPresentation(for: pending).ink == .ghost)
        #expect(MenuBarSlosh.staticPresentation(for: pending).wavePhase == nil)
        #expect(MenuBarSlosh.staticPresentation(for: meter(live: true)).ink == .solid)
    }

    @Test func pendingPreviewUsesTheNativeGhostPathAndLivePreviewKeepsItsValue() {
        let palette = MenuBarPalette(isDarkMenuBar: true)
        let pending = meter(pending: true)
        let defaultImage = MenuBarLabelRenderer.render(meters: [pending], showsPercentage: false, palette: palette).image
        let ghost = MenuBarLabelRenderer.render(meters: [pending], showsPercentage: false, palette: palette,
            presentations: [.provider(.claude): .init(ink: .ghost)]).image
        let solid = MenuBarLabelRenderer.render(meters: [pending], showsPercentage: false, palette: palette,
            presentations: [.provider(.claude): .init(ink: .solid)]).image
        #expect(defaultImage.tiffRepresentation == ghost.tiffRepresentation)
        #expect(defaultImage.tiffRepresentation != solid.tiffRepresentation)
        let live = meter(live: true)
        let liveDefault = MenuBarLabelRenderer.render(meters: [live], showsPercentage: false, palette: palette).image
        let liveSolid = MenuBarLabelRenderer.render(meters: [live], showsPercentage: false, palette: palette,
            presentations: [.provider(.claude): .init(ink: .solid)]).image
        #expect(liveDefault.tiffRepresentation == liveSolid.tiffRepresentation)
    }

    @Test func finishWaveUsesTheActualProbeEndAndHiddenProvidersDoNotTick() {
        let motion = MenuBarSlosh(autoTick: false)
        let pending = meter(pending: true)
        motion.update(meters: [pending], automatic: false, updating: [.codex], reduceMotion: false, at: start)
        #expect(!motion.isActive)
        motion.update(meters: [pending], automatic: false, updating: [.claude], reduceMotion: false, at: start)
        motion.update(meters: [pending], automatic: false, updating: [], reduceMotion: false,
            probeEndTimes: [.claude: Date(timeIntervalSince1970: 100.9)], at: Date(timeIntervalSince1970: 101.05))
        #expect(motion.presentation(for: pending, automatic: false, at: Date(timeIntervalSince1970: 101.05)).wavePhase == nil)
        #expect(motion.deadline == Date(timeIntervalSince1970: 101))
    }

    @Test func automaticMainSwitchDoesNotPrintAnExistingLiveReading() {
        let motion = MenuBarSlosh(autoTick: false)
        motion.update(meters: [meter(pending: true, provider: nil)], automatic: true, updating: [],
            reduceMotion: false, sourceAccounts: [.claude: key], at: start)
        let other = AccountKey(providerID: .claude, accountID: AccountID("work"))
        let live = meter(live: true, source: other)
        motion.update(meters: [live], automatic: true, updating: [], reduceMotion: false,
                      sourceAccounts: [.claude: other], at: start)
        #expect(motion.presentation(for: live, automatic: true, at: start).ink == .solid)
    }

    @Test func printAndBlendFinishAtTheSameNativeSolidImage() {
        let palette = MenuBarPalette(isDarkMenuBar: true)
        let solid = VesselGlyph.menuBarImage(fill: 0.73, severity: .healthy, isNeutral: false, palette: palette)
        let printed = VesselGlyph.menuBarImage(fill: 0.73, severity: .healthy, isNeutral: false,
                                               palette: palette, ink: .printing(frame: 3))
        let blended = VesselGlyph.menuBarImage(fill: 0.73, severity: .healthy, isNeutral: false,
                                               palette: palette, ink: .crossfade(frame: 3))
        #expect(printed.tiffRepresentation == solid.tiffRepresentation)
        #expect(blended.tiffRepresentation == solid.tiffRepresentation)
        let ghost = VesselGlyph.menuBarImage(fill: 0.73, severity: .healthy, isNeutral: false, palette: palette, ink: .ghost)
        #expect(ghost.tiffRepresentation != solid.tiffRepresentation)
    }

    @Test func probingAnEmptyLivePillCannotDrawLiquidAboveZero() {
        for dark in [false, true] {
            let palette = MenuBarPalette(isDarkMenuBar: dark)
            let empty = VesselGlyph.menuBarImage(fill: 0, severity: .critical,
                                                 isNeutral: false, palette: palette)
            for phase in 0..<LoadingMotionConstants.sloshFrameCount {
                let wave = VesselGlyph.menuBarImage(fill: 0, severity: .critical,
                    isNeutral: false, palette: palette, wavePhase: phase)
                #expect(wave.tiffRepresentation == empty.tiffRepresentation)
            }
        }
    }

    @Test func nativeClockStopsWhenInkSettlesAndWhenTheLabelLeaves() async throws {
        let motion = MenuBarSlosh()
        let now = Date()
        motion.update(meters: [meter(pending: true)], automatic: false, updating: [], reduceMotion: false, at: now)
        #expect(!motion.isClockRunning)
        let live = meter(live: true)
        motion.update(meters: [live], automatic: false, updating: [], reduceMotion: false, at: now)
        #expect(motion.isClockRunning)
        try await Task.sleep(for: .milliseconds(550))
        #expect(!motion.isClockRunning)
        #expect(motion.presentation(for: live, automatic: false, at: motion.frameDate).ink == .solid)
        motion.update(meters: [live], automatic: false, updating: [.claude], reduceMotion: false, at: Date())
        #expect(motion.isClockRunning)
        motion.suspend()
        #expect(!motion.isClockRunning)
    }

    @Test func pinnedRenderingDerivesThePoseWithoutStartingAClock() {
        let motion = MenuBarSlosh()
        let pending = meter(pending: true)
        motion.update(meters: [pending], automatic: false, updating: [.claude], reduceMotion: false,
                      clockEnabled: false, at: start)
        #expect(!motion.isClockRunning)
        #expect(motion.presentation(for: pending, automatic: false, at: start).wavePhase
            == LoadingMotionClock.sloshPhase(at: start))
        let live = meter(live: true)
        motion.update(meters: [live], automatic: false, updating: [], reduceMotion: false,
                      clockEnabled: false, at: start)
        #expect(!motion.isClockRunning)
        #expect(motion.presentation(for: live, automatic: false, at: start).ink == .printing(frame: 0))
        motion.update(meters: [live], automatic: false, updating: [.claude], reduceMotion: false, at: Date())
        #expect(motion.isClockRunning)
        motion.update(meters: [live], automatic: false, updating: [.claude], reduceMotion: false,
                      clockEnabled: false, at: Date())
        #expect(!motion.isClockRunning)
    }

    @Test func ghostUsesOneLevelBucketAndPrintCacheStaysBounded() {
        VesselGlyph.resetCacheForTesting()
        let palette = MenuBarPalette(isDarkMenuBar: true)
        let ghost = VesselGlyph.menuBarImage(fill: 0.1, severity: .healthy, isNeutral: true,
                                             palette: palette, ink: .ghost)
        let same = VesselGlyph.menuBarImage(fill: 0.9, severity: .healthy, isNeutral: true,
                                            palette: palette, ink: .ghost)
        #expect(ghost === same)
        for dark in [false, true] {
            for fill in [0.15, 0.73, 0.99] {
                for frame in 0..<4 {
                    _ = VesselGlyph.menuBarImage(fill: fill, severity: .healthy, isNeutral: false,
                        palette: MenuBarPalette(isDarkMenuBar: dark), ink: .printing(frame: frame))
                }
                #expect(VesselGlyph.transitionCacheEntryCount <= 8)
            }
        }
        let first = VesselGlyph.menuBarImage(fill: 0.15, severity: .healthy, isNeutral: false,
            palette: palette, ink: .printing(frame: 0))
        _ = VesselGlyph.menuBarImage(fill: 0.99, severity: .healthy, isNeutral: false,
            palette: palette, ink: .printing(frame: 0))
        let restored = VesselGlyph.menuBarImage(fill: 0.15, severity: .healthy, isNeutral: false,
            palette: palette, ink: .printing(frame: 0))
        #expect(first.tiffRepresentation == restored.tiffRepresentation)
        #expect(VesselGlyph.transitionCacheEntryCount <= 8)
    }
}
