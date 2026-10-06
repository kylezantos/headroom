import Foundation
import Testing
@testable import HeadroomCore

struct PhoneRefreshPillRecipeTests {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)

    private func recipe(_ elapsed: Double, checking: Bool = true, updated: Bool = true,
                        reduceMotion: Bool = false) -> PhoneRefreshPillRecipe {
        PhoneRefreshPillRecipe(isChecking: checking, requestedAt: start,
                              endedAt: checking ? nil : start.addingTimeInterval(2),
                              didUpdate: updated, now: start.addingTimeInterval(elapsed), reduceMotion: reduceMotion)
    }

    @Test func wipesSloshesPrintsAndStops() {
        #expect(recipe(0).pill?.ink == .ghostWipe(progress: 0))
        #expect(recipe(1).pill?.ink == .ghost)
        #expect(recipe(1).pill?.isSloshing == true)
        #expect(recipe(2, checking: false).pill?.ink == .printing(progress: 0))
        #expect(recipe(2.5, checking: false).pill?.ink == .full)
        #expect(recipe(3, checking: false).pill == nil)
    }

    @Test func failedOrPartialChecksNeverPrintFreshInk() {
        #expect(recipe(2.2, checking: false, updated: false).pill?.ink == .ghost)
        #expect(recipe(3, checking: false, updated: false).pill == nil)
    }

    @Test func reduceMotionUsesUniformInkAndNoWave() {
        #expect(recipe(0, reduceMotion: true).pill?.ink == .crossfade(progress: 1))
        #expect(recipe(1, reduceMotion: true).pill?.isSloshing == false)
        #expect(recipe(2, checking: false, reduceMotion: true).pill?.ink == .crossfade(progress: 0))
    }

    @Test func newRequestIgnoresPreviousFinish() {
        let result = PhoneRefreshPillRecipe(isChecking: true, requestedAt: start,
                                           endedAt: start.addingTimeInterval(-10), didUpdate: false,
                                           now: start.addingTimeInterval(1), reduceMotion: false)
        #expect(result.visibleUntil == nil)
        #expect(result.pill?.isSloshing == true)
    }
}
