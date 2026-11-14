import AppKit
import Foundation
import HeadroomCore
import SwiftUI
import Testing
@testable import Headroom

/// S2A: Reduce Motion is a gentler equivalent, not silence. These pin the resolver's
/// contract so a future call site can't quietly gate a cross-fade into nothing, and S1A's
/// single curve family so the retired `easeOut` can't drift back in.
@MainActor
@Suite(.sharedAppState)
struct HeadroomMotionTests {
    @Test func crossfadeKeepsItsAnimationWhateverReduceMotionSays() {
        #expect(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: true)
            == HeadroomMotion.settle)
        #expect(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: false)
            == HeadroomMotion.settle)
        #expect(HeadroomMotion.resolved(HeadroomMotion.hoverOut, .crossfade, reduceMotion: true)
            == HeadroomMotion.hoverOut)
    }

    @Test func movementIsTheOnlyKindReduceMotionSilences() {
        #expect(HeadroomMotion.resolved(HeadroomMotion.pressDown, .movement, reduceMotion: true) == nil)
        #expect(HeadroomMotion.resolved(HeadroomMotion.pressDown, .movement, reduceMotion: false)
            == HeadroomMotion.pressDown)
        #expect(HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: true) == nil)
    }

    /// S1A/S3A: one curve family, and a press pair that lands inside 100ms then returns on
    /// `settle`. Asserted against literals so a change to the vocabulary is a deliberate edit.
    @Test func thePressAndHoverPairsUseTheHouseCurve() {
        #expect(HeadroomMotion.pressDown == Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.10))
        #expect(HeadroomMotion.settle == Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20))
        #expect(HeadroomMotion.quickSettle == Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.12))
        #expect(HeadroomMotion.hoverIn == HeadroomMotion.quickSettle)
        #expect(HeadroomMotion.hoverOut == Animation.smooth(duration: 0.18, extraBounce: 0))
        #expect(HeadroomMotion.pressDown != Animation.easeOut(duration: 0.12))
    }

    /// PB12: one press scale for every button style. It was 0.96 in `HoverButtonStyle` and
    /// 0.98 in the three chip/CTA styles, so two neighbouring controls gave different amounts
    /// of give. Pinned to the literal, and to the 0.95 floor below which a press reads as
    /// exaggerated rather than tactile.
    @Test func everyButtonStyleSharesOnePressScale() {
        #expect(HeadroomMotion.pressScale == 0.96)
        #expect(HeadroomMotion.pressScale > 0.95)
        #expect(HeadroomMotion.pressScale < 1)
    }

    /// M2A/S2A: the digit roll is movement, so Reduce Motion swaps the text outright.
    @Test func numericTextCollapsesToAPlainSwapUnderReduceMotion() {
        #expect(HeadroomMotion.numericText(value: 12, reduceMotion: true) == .identity)
        #expect(HeadroomMotion.numericText(value: 12, reduceMotion: false) != .identity)
        #expect(HeadroomMotion.numericText(reduceMotion: true) == .identity)
        #expect(HeadroomMotion.numericText(reduceMotion: false) != .identity)
    }
    // MARK: Token hygiene (CA-F1, MOT-09)

    /// CA-F1: one source for the house curve. `settle`, AppKit's window curve and the DialKit
    /// defaults are all built from the same exposed constants, so retuning a token moves the
    /// meters too.
    @Test func settleTheWindowCurveAndTheTuningDefaultsShareOneSource() {
        let curve = HeadroomMotion.houseCurve
        #expect(curve == HeadroomMotion.BezierControlPoints(x1: 0.22, y1: 1, x2: 0.36, y2: 1))
        #expect(HeadroomMotion.settleDuration == 0.20)
        #expect(HeadroomMotion.valueSpringResponse == 0.3)
        #expect(HeadroomMotion.settle == HeadroomMotion.houseCurve(duration: HeadroomMotion.settleDuration))
        #expect(HeadroomMotion.valueSpring
            == Animation.spring(response: HeadroomMotion.valueSpringResponse, dampingFraction: 1.0))

        var p1 = [Float](repeating: 0, count: 2)
        var p2 = [Float](repeating: 0, count: 2)
        HeadroomMotion.windowCurve.getControlPoint(at: 1, values: &p1)
        HeadroomMotion.windowCurve.getControlPoint(at: 2, values: &p2)
        #expect(p1 == [Float(curve.x1), Float(curve.y1)])
        #expect(p2 == [Float(curve.x2), Float(curve.y2)])

        let tuning = HeadroomTuning()
        #expect(tuning.settleDuration == HeadroomMotion.settleDuration)
        #expect(tuning.valueSpringResponse == HeadroomMotion.valueSpringResponse)
        #expect(tuning.valueSpringDamping == HeadroomMotion.valueSpringDampingFraction)
        #expect(tuning.settle == HeadroomMotion.settle)
        #expect(tuning.valueSpring == HeadroomMotion.valueSpring)
    }

    /// CA-F1/CA-M3/CA-M6: the promoted values, pinned to the literals their call sites carry.
    @Test func theRevealDrainAndArrivalTokensHoldTheirApprovedValues() {
        #expect(HeadroomMotion.revealBlur == 1.5)
        #expect(HeadroomMotion.revealScale == 0.97)
        #expect(HeadroomMotion.arrivalAccountCap == 8)
        #expect(HeadroomMotion.drain == Animation.linear(duration: LoadingMotionConstants.drainDuration))
    }

    /// CA-F1 (MOT-09): `hover` and `press` were compatibility aliases with no callers. The
    /// motion file no longer declares them and no source file reaches for them.
    @Test func theRetiredAliasesAreGoneEverywhere() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let motion = try String(
            contentsOf: root.appendingPathComponent("Sources/HeadroomSharedUI/HeadroomMotion.swift"), encoding: .utf8)
        #expect(!motion.contains("static let hover ="))
        #expect(!motion.contains("static let press ="))

        let sources = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        let alias = try NSRegularExpression(pattern: #"HeadroomMotion\.(hover|press)\b(?![A-Za-z])"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            #expect(alias.firstMatch(in: text, range: range) == nil, "\(file.lastPathComponent) uses a retired alias")
        }
    }
}
