import AppKit
import SwiftUI
import Testing
@testable import Headroom

/// OA1: the optical-margin corrections that pull the card's text column onto one perceived
/// edge. These read real CoreText metrics for the system font — deterministic on macOS — so
/// a font-metric or table change surfaces here rather than as a column that quietly re-jitters.
@Suite
struct OpticalLeadingTests {
    private static func semibold15(_ text: String) -> CGFloat {
        OpticalLeading.correction(for: text, size: 15, weight: .semibold)
    }

    private static func semibold13(_ text: String) -> CGFloat {
        OpticalLeading.correction(for: text, size: 13, weight: .semibold)
    }

    @Test func emptyTextNeedsNoCorrection() {
        #expect(OpticalLeading.correction(for: "", size: 15, weight: .semibold) == 0)
        #expect(OpticalLeading.correction(for: "", font: .systemFont(ofSize: 15, weight: .semibold)) == 0)
        #expect(OpticalLeading.unroundedCorrection(for: "", font: .systemFont(ofSize: 15)) == 0)
    }

    /// A stem meets the axis along its whole height, so "P" corrects by its bearing alone.
    @Test func stemsCorrectByBearingOnly() {
        let raw = OpticalLeading.unroundedCorrection(
            for: "Personal",
            font: .systemFont(ofSize: 15, weight: .semibold)
        )
        #expect(abs(raw - 1.30) < 0.05)
        // The applied value lands on the 0.25pt raster grid.
        #expect(Self.semibold15("Personal") == 1.25)
    }

    /// A diagonal adds the 6%-of-size overhang on top of its (much smaller) bearing.
    @Test func diagonalsAddTheirOverhang() {
        let raw = OpticalLeading.unroundedCorrection(
            for: "Work",
            font: .systemFont(ofSize: 15, weight: .semibold)
        )
        #expect(abs(raw - (0.64 + 0.9)) < 0.1)
        #expect(Self.semibold15("Work") == 1.5)
    }

    /// The stagger this whole mechanism exists to remove: a diagonal-led label reads further
    /// right than a stem-led one, so it must be pulled back further.
    @Test func aDiagonalLabelIsPulledBackFurtherThanAStemLabel() {
        #expect(Self.semibold13("Weekly") > Self.semibold13("5-hour"))
    }

    /// Rounds hang less far than diagonals: a curve's tangent point overshoots the axis less
    /// than an apex does. SF's own bearings put "O" slightly outside "P" to begin with, so
    /// the ordering that matters is round-under-diagonal.
    @Test func roundsHangLessThanDiagonals() {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let round = OpticalLeading.unroundedCorrection(for: "OpenAI", font: font)
        let diagonal = OpticalLeading.unroundedCorrection(for: "Work", font: font)
        #expect(round < diagonal)
        #expect(abs(round - (0.857 + 0.525)) < 0.05)
    }

    /// Only the first character matters, and the cached second read agrees with the first.
    @Test func repeatedLookupsAreStableThroughTheCache() {
        let first = Self.semibold15("Personal")
        let second = Self.semibold15("Personal")
        #expect(first == second)
        #expect(Self.semibold15("Priority") == first)
    }

    /// Anything CoreText can't reduce to a single glyph from a single UTF-16 unit corrects
    /// by 0 rather than guessing.
    @Test func multiUnitCharactersFallBackToZero() {
        #expect(OpticalLeading.correction(for: "🙂 hello", size: 15, weight: .semibold) == 0)
    }

    @Test func swiftUIWeightsMapOntoTheirAppKitCounterparts() {
        #expect(NSFont.Weight.from(.semibold) == .semibold)
        #expect(NSFont.Weight.from(.medium) == .medium)
        #expect(NSFont.Weight.from(.regular) == .regular)
    }
}
