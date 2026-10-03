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
    }

    @Test func mediumLadderMatchesThePlan() {
        let scale = WidgetTypeScale.scale(for: .medium)
        #expect(scale.header == 11)
        #expect(scale.name == 14)
        #expect(scale.label == 12)
        #expect(scale.countdown == 11)
    }

    @Test func largeLadderMatchesThePlan() {
        let scale = WidgetTypeScale.scale(for: .large)
        #expect(scale.name == 15)
        #expect(scale.label == 13)
        #expect(scale.countdown == 11)
    }

    /// The sizes that do not vary by family — the spend strip, the footer, the status card and
    /// the plan pill are the same object wherever they appear.
    @Test func familyInvariantSizesAreTheSameOnEveryLadder() {
        for family in WidgetFamily.allCases {
            let scale = WidgetTypeScale.scale(for: family)
            let label = "\(family)"
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

    /// WCF1's hierarchy, on every ladder: the name outranks the label, and the countdown is
    /// the quietest thing in the row.
    @Test func everyLadderKeepsItsHierarchy() {
        for family in WidgetFamily.allCases {
            let scale = WidgetTypeScale.scale(for: family)
            #expect(scale.name >= scale.label, "\(family)")
            #expect(scale.label >= scale.countdown, "\(family)")
        }
    }
}
