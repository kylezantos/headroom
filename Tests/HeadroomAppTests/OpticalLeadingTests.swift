import AppKit
import CoreText
import SwiftUI
import Testing
@testable import Headroom

/// OA1: the optical-margin corrections that pull the card's text column onto one perceived
/// edge. These read real CoreText metrics for the system font — deterministic on macOS — so
/// a font-metric or table change surfaces here rather than as a column that quietly re-jitters.
@Suite(.sharedAppState)
struct OpticalLeadingTests {
    private static func semibold15(_ text: String) -> CGFloat {
        OpticalLeading.correction(for: text, size: 15, weight: .semibold)
    }

    private static func semibold13(_ text: String) -> CGFloat {
        OpticalLeading.correction(for: text, size: 13, weight: .semibold)
    }

    /// U2: extracting StatusSentence must retain its Mac content-axis alignment when
    /// the shared component adopts the existing cross-platform CoreText helper.
    @Test(arguments: ["Sign in", "Waiting", "Open setup", "Try again", "", "🙂 hello"])
    func sharedStatusSentenceKeepsItsOpticalAxis(_ text: String) {
        #expect(HeadroomWidgetFontMetrics.leadingCorrection(for: text, size: 11.5, weight: .medium)
            == OpticalLeading.correction(for: text, size: 11.5, weight: .medium))
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

    /// PB11: `a d g q` joined the rounds table. Each meets the axis on a bowl, so each has
    /// to hang past it — before this they were corrected by bearing alone, exactly as if
    /// they were flat-sided. Measured against CoreText independently, so the assertion is
    /// "bearing plus the round overhang", not "whatever the table says".
    @Test func lowercaseBowlsNowTakeTheRoundOverhang() {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        for round in ["a", "d", "g", "q"] {
            let correction = OpticalLeading.unroundedCorrection(for: round, font: font)
            let expected = Self.coreTextBearing(round, font: font)
                + OpticalLeading.Overhang.round * font.pointSize
            #expect(abs(correction - expected) < 0.001)
        }
    }

    /// A flat-sided lowercase is still corrected by its bearing alone — the table grew, it
    /// did not stop discriminating.
    @Test func flatSidedLowercaseStillGetsNoOverhang() {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        for flat in ["i", "l", "m", "n"] {
            let correction = OpticalLeading.unroundedCorrection(for: flat, font: font)
            #expect(abs(correction - Self.coreTextBearing(flat, font: font)) < 0.001)
        }
    }

    /// The glyph's left side bearing, read the same way `OpticalLeading` reads it — but
    /// spelled out here so the test is an independent measurement rather than an echo.
    private static func coreTextBearing(_ text: String, font: NSFont) -> CGFloat {
        var units = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        guard CTFontGetGlyphsForCharacters(font as CTFont, &units, &glyphs, 1) else { return 0 }
        var rects = [CGRect](repeating: .zero, count: 1)
        CTFontGetBoundingRectsForGlyphs(font as CTFont, .horizontal, &glyphs, &rects, 1)
        return rects[0].origin.x
    }

    @Test func swiftUIWeightsMapOntoTheirAppKitCounterparts() {
        #expect(NSFont.Weight.from(.semibold) == .semibold)
        #expect(NSFont.Weight.from(.medium) == .medium)
        #expect(NSFont.Weight.from(.regular) == .regular)
    }
}

/// PA6: the Micro meter row stays `.center` (Kyle: "center aligned with each other, not the
/// bottom baseline") and every text element on it now declares its cap-height centre from
/// real `NSFont` metrics. These pin that offset math — the part a render cannot prove and a
/// font-metric change would silently move.
@Suite(.sharedAppState)
struct OpticalCenteringTests {
    /// The Micro row's four roles, as `UsageBarView` renders them.
    private static let label = (size: CGFloat(13), weight: NSFont.Weight.medium)
    private static let countdown = (size: CGFloat(11), weight: NSFont.Weight.regular)
    private static let numeral = (size: CGFloat(18), weight: NSFont.Weight.semibold)
    private static let term = (size: CGFloat(11), weight: NSFont.Weight.regular)

    @Test func theCapCentreIsHalfTheRealCapHeight() {
        for role in [Self.label, Self.countdown, Self.numeral] {
            let font = NSFont.systemFont(ofSize: role.size, weight: role.weight)
            #expect(OpticalCentering.capHeightCenter(size: role.size, weight: role.weight)
                == font.capHeight / 2)
            #expect(OpticalCentering.capHeightCenter(of: font) == font.capHeight / 2)
        }
    }

    /// The guide subtracts the cap centre from the rendered baseline, so a text laid out
    /// with its baseline at `b` reports its ink middle. Nothing here assumes a line height.
    @Test func theGuideIsTheBaselineLessTheCapCentre() {
        let guide = OpticalCentering.centerGuide(
            firstTextBaseline: 17.5,
            size: Self.numeral.size,
            weight: Self.numeral.weight
        )
        let expected = 17.5 - NSFont.systemFont(ofSize: 18, weight: .semibold).capHeight / 2
        #expect(abs(guide - expected) < 0.0001)
    }

    /// Bigger type has a taller cap, so cap-centring drops its baseline relative to a
    /// smaller neighbour's — the ~1.5pt "sag" the audit measured on the numeral is the
    /// correct result of this alignment, not the defect it looked like.
    @Test func capCentringDropsTheNumeralsBaselineBelowTheLabels() {
        let drop = OpticalCentering.capHeightCenter(size: Self.numeral.size, weight: Self.numeral.weight)
            - OpticalCentering.capHeightCenter(size: Self.label.size, weight: Self.label.weight)
        #expect(drop > 0)
        #expect(abs(drop - 1.76) < 0.05)
    }

    /// And the 11pt countdown rises slightly against the 13pt label it follows.
    @Test func theCountdownRisesSlightlyAgainstItsLabel() {
        let shift = OpticalCentering.capHeightCenter(size: Self.countdown.size, weight: Self.countdown.weight)
            - OpticalCentering.capHeightCenter(size: Self.label.size, weight: Self.label.weight)
        #expect(shift < 0)
        #expect(abs(shift + 0.70) < 0.05)
    }

    /// PA6's reason for existing: SwiftUI's plain `.center` centres line boxes, and a line
    /// box is asymmetric about its ink by a *different* amount at each size — so box
    /// centring left the 13pt label sitting below the 18pt numeral it labels. A cap-centre
    /// guide removes exactly that difference.
    @Test func boxCentringIsNotInkCentringAcrossTheMicroRow() {
        let labelDrop = OpticalCentering.inkCenterDrop(size: Self.label.size, weight: Self.label.weight)
        let numeralDrop = OpticalCentering.inkCenterDrop(size: Self.numeral.size, weight: Self.numeral.weight)
        #expect(labelDrop > 0)
        #expect(numeralDrop > 0)
        // Both ride low in their own boxes, but not by the same amount — that residue is
        // what the guides remove, and it is above the 0.25pt Retina raster quantum.
        #expect(abs(labelDrop - numeralDrop) > 0.25)
    }

    /// The term "used"/"left" shares the numeral's row, so it gets its own guide rather than
    /// riding the figure's baseline.
    @Test func theTermCentresOnItsOwnCapHeight() {
        #expect(OpticalCentering.capHeightCenter(size: Self.term.size, weight: Self.term.weight)
            < OpticalCentering.capHeightCenter(size: Self.numeral.size, weight: Self.numeral.weight))
    }

    /// PB12: the spend `+` went 10pt → 13pt semibold and has to land on the amount's ink, not
    /// on its own 18pt slot's box centre. The nudge is measured, and it moves the smaller
    /// glyph *up*.
    @Test func theSpendPlusIsNudgedUpOntoTheAmountsInk() {
        let nudge = OpticalCentering.inkCenterAlignment(
            size: 13, weight: .semibold,
            matching: 18, referenceWeight: .semibold
        )
        #expect(nudge < 0)
        #expect(abs(nudge) > 0.25)
        #expect(abs(nudge) < 1)
    }

    /// Aligning a glyph to its own role is a no-op, which is the sanity check that the
    /// nudge is a difference of drops and not an absolute offset.
    @Test func aligningARoleWithItselfMovesNothing() {
        #expect(OpticalCentering.inkCenterAlignment(
            size: 13, weight: .semibold,
            matching: 13, referenceWeight: .semibold
        ) == 0)
    }

    @Test func repeatedLookupsAreStableThroughTheCaches() {
        #expect(OpticalCentering.capHeightCenter(size: 18, weight: .semibold)
            == OpticalCentering.capHeightCenter(size: 18, weight: .semibold))
        #expect(OpticalCentering.inkCenterDrop(size: 13, weight: .medium)
            == OpticalCentering.inkCenterDrop(size: 13, weight: .medium))
    }
}

/// U3/KTD2: the shared popover rows swapped `NSFont` measurement and `OpticalLeading` /
/// `OpticalCentering` for the CoreText helpers in `HeadroomWidgetTypography`. These pin the
/// swap against the Mac's own metrics at every role the rows render, so the Mac popover keeps
/// its measurements exactly at scale 1.0.
@Suite(.sharedAppState)
struct SharedRowMetricsParityTests {
    private static func appKitWidth(_ text: String, font: NSFont, kerning: CGFloat = 0) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if kerning != 0 { attributes[.kern] = kerning }
        return (text as NSString).size(withAttributes: attributes).width
    }

    /// PB11: the title's truncation test measures with the title's kerning. Dropping it would
    /// under-measure a long name by its glyph count × 0.15pt.
    @Test(arguments: ["Personal", "Work — long-lived research account", "Anthropic", "🙂 hello", ""])
    func theKernedTitleMeasuresAsTheMacDid(_ title: String) {
        let font = NSFont.systemFont(ofSize: IdentityRowMetrics.titleSize, weight: .semibold)
        let mac = Self.appKitWidth(title, font: font, kerning: IdentityRowMetrics.titleKerning)
        let shared = HeadroomWidgetFontMetrics.textWidth(
            title, size: IdentityRowMetrics.titleSize, weight: .semibold,
            kerning: IdentityRowMetrics.titleKerning
        )
        #expect(abs(shared - mac) < 0.001)
        if title.count > 1 {
            let unkerned = HeadroomWidgetFontMetrics.textWidth(title, size: IdentityRowMetrics.titleSize, weight: .semibold)
            #expect(unkerned > shared)
        }
    }

    /// The meter's numeral column reserves "100%" in the 18pt semibold monospaced face.
    @Test func theNumeralColumnReservesTheSameWidth() {
        let mac = ceil(Self.appKitWidth("100%", font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)))
        let shared = ceil(HeadroomWidgetFontMetrics.textWidth("100%", size: 18, weight: .semibold, mono: true))
        #expect(shared == mac)
    }

    /// R2C8: the spend column reserves the widest visible amount, floored at "$0.00".
    @Test(arguments: ["$0.00", "$58.90", "$1,234.56", "$12,345.67"])
    func theSpendColumnReservesTheSameWidth(_ amount: String) {
        let mac = ceil(Self.appKitWidth(amount, font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)))
        let shared = ceil(HeadroomWidgetFontMetrics.textWidth(amount, size: 18, weight: .semibold, mono: true))
        #expect(shared == mac)
    }

    /// The shared spend row's column helper reserves exactly what the Mac section did.
    @Test func theSpendRowsColumnHelperMatchesTheMacReservation() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        for amounts in [[], ["$58.90"], ["$142.67", "$58.90"], ["$12,345.67", "$0.00"]] {
            let mac = (amounts + ["$0.00"]).map { ceil(Self.appKitWidth($0, font: font)) }.max() ?? 0
            #expect(APISpendRowMetrics.amountColumnWidth(for: amounts) == mac)
        }
        #expect(APISpendRowMetrics.amountColumnWidth(for: ["$58.90"], scale: 1.15)
            > APISpendRowMetrics.amountColumnWidth(for: ["$58.90"]))
    }

    /// Every leading correction the shared rows apply equals the Mac's at the same role:
    /// meter label 13 medium, title 15 semibold.
    @Test(arguments: ["Weekly", "5-hour", "Fable", "Auto", "Personal", "Work", "OpenAI", "anthropic", "", "🙂 hello"])
    func leadingCorrectionsMatchAtEveryRowRole(_ text: String) {
        for (size, weight) in [(CGFloat(13), Font.Weight.medium), (15, .semibold), (11, .regular), (18, .semibold)] {
            #expect(HeadroomWidgetFontMetrics.leadingCorrection(for: text, size: size, weight: weight)
                == OpticalLeading.correction(for: text, size: size, weight: .from(weight)))
        }
    }

    /// PA6: the Micro row's cap-centre guides — label 13, countdown and term 11, numeral 18 —
    /// read the same cap height through CoreText as through `NSFont`.
    @Test func capCentresMatchAtEveryMicroRowRole() {
        for (size, weight) in [(CGFloat(13), Font.Weight.medium), (11, .regular), (18, .semibold), (11, .medium)] {
            #expect(HeadroomWidgetFontMetrics.capHeightCenter(size: size, weight: weight)
                == OpticalCentering.capHeightCenter(size: size, weight: .from(weight)))
        }
    }
}
