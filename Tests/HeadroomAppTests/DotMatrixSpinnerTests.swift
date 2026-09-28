import Testing
@testable import Headroom

/// The vendored Flicker pattern is hand-transcribed art, so a dropped character would
/// silently shift every later dot. These pin its shape and the frame clock.
@Suite
struct DotMatrixSpinnerTests {
    @Test func everyFrameIsAFullFiveByFiveGrid() {
        let pattern = DotMatrixPattern.arc
        #expect(pattern.columns == 5)
        #expect(pattern.frames.count == 6)
        #expect(pattern.frames.allSatisfy { $0.count == 25 })
    }

    /// Reduce Motion holds this frame, so it must show the mark, not a blank grid.
    @Test func theReduceMotionFrameIsLit() {
        let pattern = DotMatrixPattern.arc
        #expect(pattern.frames[pattern.stillFrame].contains(true))
    }

    @Test func framesAdvanceEveryHundredFiftyMillisecondsAndWrap() {
        #expect(DotMatrixPattern.frameIndex(elapsed: 0, frameCount: 6) == 0)
        #expect(DotMatrixPattern.frameIndex(elapsed: 0.149, frameCount: 6) == 0)
        // Timeline dates land a hair before the boundary; that still counts as the next frame.
        #expect(DotMatrixPattern.frameIndex(elapsed: 0.1499999, frameCount: 6) == 1)
        #expect(DotMatrixPattern.frameIndex(elapsed: 6 * 0.150, frameCount: 6) == 0)
        #expect(DotMatrixPattern.frameIndex(elapsed: -1, frameCount: 6) == 0)
    }
}
