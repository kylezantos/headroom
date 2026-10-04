import Foundation
import Testing
@testable import HeadroomCore

struct LoadingMotionTests {
    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test func clockWrapsInStepWithTheMenuBarAndFinishesTheWave() {
        #expect(LoadingMotionClock.sloshPhase(at: date(0.95)) == 9)
        #expect(LoadingMotionClock.sloshPhase(at: date(1)) == 0)
        // Foundation stores Date relative to 2001; use an exactly representable fraction
        // to test negative modulo without placing a rounded timestamp on a frame boundary.
        #expect(LoadingMotionClock.sloshPhase(at: date(-0.125)) == 8)
        #expect(LoadingMotionClock.isSloshing(active: false, endedAt: date(4.3), now: date(4.99)))
        #expect(!LoadingMotionClock.isSloshing(active: false, endedAt: date(4.3), now: date(5)))
        #expect(!LoadingMotionClock.isSloshing(active: false, endedAt: nil, now: date(4.3)))
        #expect(!LoadingMotionClock.isSloshing(active: false, endedAt: date(5), now: date(4.3)))
        #expect(!LoadingMotionClock.isSloshing(active: true, endedAt: nil, now: date(4.3), reduceMotion: true))
    }

    @Test func ghostPlaceholdersHaveNoDistinctValuesOrMotion() {
        let row = LoadingPillState.ghostRow()
        #expect(row.count == 3)
        #expect(Set(row.map(\.level)).count == 1)
        #expect(Set(row.map(\.id)).count == 3)
        #expect(row.allSatisfy { $0.ink == .ghost && !$0.isSloshing })
    }

    @Test func setupMeaningIsIndependentOfProviderAndPrompt() {
        for prompt in [SetupWaitingPrompt.signIn, .deviceCode, .workspaceApproval, .signInNeedsLoginCommand] {
            for surface in [SetupMotion.Surface.card, .row, .settings] {
                #expect(SetupMotion.resolve(phase: .openingTerminal, surface: surface).motion == .slosh)
                #expect(SetupMotion.resolve(phase: .confirming(prompt, reportedFinished: true), surface: surface).motion == .slosh)
                #expect(SetupMotion.resolve(phase: .confirming(prompt, reportedFinished: false), surface: surface).motion == .slosh)
                #expect(SetupMotion.resolve(phase: .waitingForUser(prompt), surface: surface, rowDripApproved: true).motion == .drip)
            }
        }
    }

    @Test func smallDripIsGatedButCardsAlwaysDrip() {
        #expect(SetupMotion.resolve(phase: .waitingForUser(.signIn), surface: .card).motion == .drip)
        for surface in [SetupMotion.Surface.row, .settings] {
            #expect(SetupMotion.resolve(phase: .waitingForUser(.signIn), surface: surface).motion == .slosh)
        }
        #expect(SetupMotion.resolve(phase: nil, surface: .row).motion == .still)
    }

    @Test func reduceMotionHasAnEmptyWaitAndFilledWorkEvenBeforeDripApproval() {
        for surface in [SetupMotion.Surface.card, .row, .settings] {
            let waiting = SetupMotion.resolve(phase: .waitingForUser(.signIn), surface: surface, level: 0.7, reduceMotion: true)
            let working = SetupMotion.resolve(phase: .openingTerminal, surface: surface, level: 0.7, reduceMotion: true)
            #expect(waiting.motion == .still && waiting.level == 0)
            #expect(working.motion == .still && working.level == 0.7)
        }
    }
}
