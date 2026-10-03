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

    // MARK: - WCF3 the content axis

    @Test func markSlotsMatchTheCapHeightDerivation() {
        #expect(WidgetMetrics.markSlot(for: .small) == 15)
        #expect(WidgetMetrics.markSlot(for: .medium) == 16)
        #expect(WidgetMetrics.markSlot(for: .large) == 20)
    }

    /// WCL3 sizes the mark from the name's cap height, so a bigger name must never get a
    /// smaller mark.
    @Test func theMarkSlotTracksTheNameSize() {
        for family in WidgetFamily.allCases {
            let name = WidgetTypeScale.scale(for: family).name
            let slot = WidgetMetrics.markSlot(for: family)
            #expect(slot > name * 0.9 && slot < name * 1.6, "\(family): \(slot) for a \(name)pt name")
        }
    }

    // MARK: - WCW6 spend strip and WCL4 rules

    @Test func spendAndRuleTokensMatchThePlan() {
        #expect(WidgetMetrics.spendItemGap == 10)
        #expect(WidgetMetrics.spendRuleToRow == 9)
        #expect(WidgetMetrics.hairline == 1)
    }
}
