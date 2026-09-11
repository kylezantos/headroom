import Foundation
import Testing
@testable import HeadroomCore

/// WCF1 / WCF2: the ladder is the contract. These pin every size in the plan's table, so a
/// "small tidy-up" in a view body cannot quietly reintroduce per-platform semantic fonts.
struct WidgetTypeScaleTests {
    @Test func smallLadderMatchesThePlan() {
        let scale = WidgetTypeScale.scale(for: .small)
        #expect(scale.header == 11)
        #expect(scale.name == 14)
        #expect(scale.nameKerning == -0.15)
        #expect(scale.label == 12)
        #expect(scale.countdown == 11)
        #expect(scale.numeral == 18)
        #expect(scale.suffix == 11)
    }

    @Test func mediumLadderMatchesThePlan() {
        let scale = WidgetTypeScale.scale(for: .medium)
        #expect(scale.header == 11)
        #expect(scale.name == 14)
        #expect(scale.label == 12)
        #expect(scale.countdown == 11)
        #expect(scale.numeral == 16)
        #expect(scale.suffix == 11)
    }

    @Test func largeStandardLadderMatchesThePlan() {
        let scale = WidgetTypeScale.scale(for: .large, step: .standard)
        #expect(scale.name == 15)
        #expect(scale.label == 13)
        #expect(scale.countdown == 11)
        #expect(scale.numeral == 18)
        #expect(scale.suffix == 11)
    }

    @Test func largeDenseLadderMatchesThePlan() {
        let scale = WidgetTypeScale.scale(for: .large, step: .dense)
        #expect(scale.name == 14)
        #expect(scale.label == 12)
        #expect(scale.countdown == 10.5)
        #expect(scale.numeral == 16)
        #expect(scale.suffix == 10.5)
    }

    /// The sizes that do not vary by family — the spend strip, the footer, the status card and
    /// the plan pill are the same object wherever they appear.
    @Test func familyInvariantSizesAreTheSameOnEveryLadder() {
        for family in WidgetFamily.allCases {
            for step in WidgetTypeStep.allCases {
                let scale = WidgetTypeScale.scale(for: family, step: step)
                let label = "\(family)/\(step)"
                #expect(scale.spendAmount == 13, "\(label)")
                #expect(scale.spendSuffix == 11, "\(label)")
                #expect(scale.footer == 11, "\(label)")
                #expect(scale.statusTitle == 14, "\(label)")
                #expect(scale.statusMessage == 11.5, "\(label)")
                #expect(scale.pillLabel == 9.5, "\(label)")
                #expect(scale.pillHeight == 15, "\(label)")
                #expect(scale.header == 11, "\(label)")
                #expect(scale.nameKerning == -0.15, "\(label)")
            }
        }
    }

    /// The dense step belongs to the large family's compact tier; small and medium have one
    /// content mix each and ignore it.
    @Test func onlyTheLargeFamilyHonoursTheDenseStep() {
        #expect(WidgetTypeScale.scale(for: .small, step: .dense) == WidgetTypeScale.scale(for: .small))
        #expect(WidgetTypeScale.scale(for: .medium, step: .dense) == WidgetTypeScale.scale(for: .medium))
        #expect(WidgetTypeScale.scale(for: .large, step: .dense) != WidgetTypeScale.scale(for: .large))
    }

    /// WCF1's hierarchy, on every ladder: the numeral is the glance value, the name outranks
    /// the label, and the countdown is the quietest thing in the row.
    @Test func everyLadderKeepsItsHierarchy() {
        for family in WidgetFamily.allCases {
            for step in WidgetTypeStep.allCases {
                let scale = WidgetTypeScale.scale(for: family, step: step)
                let label = "\(family)/\(step)"
                #expect(scale.numeral > scale.name, "\(label)")
                #expect(scale.name >= scale.label, "\(label)")
                #expect(scale.label >= scale.countdown, "\(label)")
                #expect(scale.suffix <= scale.numeral, "\(label)")
            }
        }
    }

    // MARK: - WCF2 numeral column

    @Test func numeralColumnWidthsMatchTheMeasuredTable() {
        #expect(WidgetTypeScale.numeralColumnWidth(forNumeralSize: 18) == 52)
        #expect(WidgetTypeScale.numeralColumnWidth(forNumeralSize: 16) == 47.5)
        #expect(WidgetTypeScale.numeralColumnWidth(forNumeralSize: 14) == 42)
    }

    @Test func eachLadderReadsItsOwnColumnWidth() {
        #expect(WidgetTypeScale.scale(for: .small).numeralColumnWidth == 52)
        #expect(WidgetTypeScale.scale(for: .medium).numeralColumnWidth == 47.5)
        #expect(WidgetTypeScale.scale(for: .large, step: .standard).numeralColumnWidth == 52)
        #expect(WidgetTypeScale.scale(for: .large, step: .dense).numeralColumnWidth == 47.5)
    }

    @Test func sizesBetweenTheStopsInterpolateLinearly() {
        #expect(abs(WidgetTypeScale.numeralColumnWidth(forNumeralSize: 15) - 44.75) < 0.0001)
        #expect(abs(WidgetTypeScale.numeralColumnWidth(forNumeralSize: 17) - 49.75) < 0.0001)
    }

    /// A future ladder size gets a sane column instead of a clamp — the column keeps growing
    /// with the glyphs it has to hold.
    @Test func sizesOutsideTheTableExtrapolateAlongTheNearestSegment() {
        let small = WidgetTypeScale.numeralColumnWidth(forNumeralSize: 12)
        let large = WidgetTypeScale.numeralColumnWidth(forNumeralSize: 20)
        #expect(abs(small - 36.5) < 0.0001)
        #expect(abs(large - 56.5) < 0.0001)
        #expect(small > 0)
    }

    @Test func theColumnIsMonotonicInTheNumeralSize() {
        var previous = 0.0
        for size in stride(from: 10.0, through: 24.0, by: 0.5) {
            let width = WidgetTypeScale.numeralColumnWidth(forNumeralSize: size)
            #expect(width > previous, "\(size)pt")
            previous = width
        }
    }
}
