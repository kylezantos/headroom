import Foundation
import Testing
@testable import HeadroomCore

/// WCF3 / WCF4 / WCL2 / WCL4 / WCL5: the layout constants, pinned. These numbers are what
/// makes a Mac tile and an iPhone tile the same design rather than two similar ones.
struct WidgetMetricsTests {
    // MARK: - WCF4 margins

    @Test func marginTokensMatchThePlan() {
        #expect(WidgetMetrics.residualMargin == 2)
        #expect(WidgetMetrics.iOSMarginReclaim == 4)
        #expect(WidgetMetrics.iOSMediumMargin == 16)
    }

    @Test func iOSTakesTheReclaimOnSmallAndLargeOnly() {
        #expect(WidgetMetrics.iOSMargin(for: .small) == 14)
        #expect(WidgetMetrics.iOSMargin(for: .large) == 14)
        #expect(WidgetMetrics.iOSMargin(for: .medium) == 16)
    }

    // MARK: - WCF3 the content axis

    @Test func markSlotsMatchTheCapHeightDerivation() {
        #expect(WidgetMetrics.markSlot(for: .small) == 15)
        #expect(WidgetMetrics.markSlot(for: .medium) == 16)
        #expect(WidgetMetrics.markSlot(for: .large, step: .standard) == 20)
        #expect(WidgetMetrics.markSlot(for: .large, step: .dense) == 18)
    }

    @Test func theContentAxisIsTheMarkSlotPlusTheGap() {
        #expect(WidgetMetrics.markGap == 6)
        #expect(WidgetMetrics.contentAxis(for: .small) == 21)
        #expect(WidgetMetrics.contentAxis(for: .medium) == 22)
        #expect(WidgetMetrics.contentAxis(for: .large, step: .standard) == 26)
        #expect(WidgetMetrics.contentAxis(for: .large, step: .dense) == 24)

        for family in WidgetFamily.allCases {
            for step in WidgetTypeStep.allCases {
                #expect(
                    WidgetMetrics.contentAxis(for: family, step: step)
                        == WidgetMetrics.markSlot(for: family, step: step) + WidgetMetrics.markGap,
                    "\(family)/\(step)"
                )
            }
        }
    }

    /// WCL3 sizes the mark from the name's cap height, so a bigger name must never get a
    /// smaller mark.
    @Test func theMarkSlotTracksTheNameSize() {
        let pairs: [(WidgetFamily, WidgetTypeStep)] = [
            (.small, .standard), (.medium, .standard), (.large, .standard), (.large, .dense),
        ]
        for (family, step) in pairs {
            let name = WidgetTypeScale.scale(for: family, step: step).name
            let slot = WidgetMetrics.markSlot(for: family, step: step)
            #expect(slot > name * 0.9 && slot < name * 1.6, "\(family)/\(step): \(slot) for a \(name)pt name")
        }
        #expect(
            WidgetMetrics.markSlot(for: .large, step: .standard)
                > WidgetMetrics.markSlot(for: .large, step: .dense)
        )
    }

    // MARK: - WCL2 grouping

    @Test func labelToBarIsOneNumberEverywhere() {
        #expect(WidgetMetrics.labelToBar == 7)
    }

    @Test func smallRhythmMatchesThePlan() {
        #expect(WidgetMetrics.smallHeaderToRows == 22)
        #expect(WidgetMetrics.smallRowToRow == 12)
        #expect(WidgetMetrics.smallBarHeight == 8)
    }

    @Test func mediumRhythmMatchesThePlan() {
        #expect(WidgetMetrics.mediumHeaderToMeter == 6)
        #expect(WidgetMetrics.mediumMeterToMeter == 10)
        #expect(WidgetMetrics.mediumBarHeight == 6)
        #expect(WidgetMetrics.mediumGutter == 28)
        #expect(WidgetMetrics.mediumSpendAirFloor == 14)
    }

    /// The grouping ratio WCL2 protects: a meter's label belongs to its bar more tightly than
    /// one meter belongs to the next, which in turn is tighter than a header's own group.
    @Test func mediumKeepsItsGroupingRatio() {
        #expect(WidgetMetrics.mediumHeaderToMeter < WidgetMetrics.mediumMeterToMeter)
        #expect(WidgetMetrics.labelToBar < WidgetMetrics.mediumMeterToMeter)
        #expect(WidgetMetrics.labelToBar < WidgetMetrics.smallRowToRow)
    }

    /// WCL4: each column's bar ends half the gutter clear of the centre rule, which is the
    /// number that makes the rule read as a divider instead of a border on one column.
    @Test func theMediumGutterLeavesTheSpendFloorOfAirOnEachSideOfTheRule() {
        #expect(WidgetMetrics.mediumGutter / 2 == WidgetMetrics.mediumSpendAirFloor)
    }

    // MARK: - WCW6 spend strip and WCL4 rules

    @Test func spendAndRuleTokensMatchThePlan() {
        #expect(WidgetMetrics.spendItemGap == 10)
        #expect(WidgetMetrics.spendRuleToRow == 9)
        #expect(WidgetMetrics.suffixGap == 5)
        #expect(WidgetMetrics.hairline == 1)
    }
}
