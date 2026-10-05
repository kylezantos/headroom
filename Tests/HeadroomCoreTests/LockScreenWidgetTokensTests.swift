import Testing
@testable import HeadroomCore

struct LockScreenWidgetTokensTests {
    @Test func approvedDesignSizesStayPinned() {
        #expect(LockScreenWidgetTokens.tightestNumeral == 17)
        #expect(LockScreenWidgetTokens.tightestMark == 15)
        #expect(LockScreenWidgetTokens.liquidNumeral == 18)
        #expect(LockScreenWidgetTokens.liquidMark == 15)
        #expect(LockScreenWidgetTokens.vesselNumeral == 19)
        #expect(LockScreenWidgetTokens.nestedNumeral == 18)
        #expect(LockScreenWidgetTokens.nestedBarWidth == 34)
        #expect(LockScreenWidgetTokens.nestedParentHeight == 4)
        #expect(LockScreenWidgetTokens.nestedRailHeight == 2)
    }

    @Test func opaqueInkLevelsHaveTheRequiredOrdering() {
        #expect(LockScreenWidgetTokens.fullInk > LockScreenWidgetTokens.secondaryInk)
        #expect(LockScreenWidgetTokens.secondaryInk > LockScreenWidgetTokens.halfInk)
        #expect(LockScreenWidgetTokens.halfInk > LockScreenWidgetTokens.trackInk)
        #expect(LockScreenWidgetTokens.alwaysOnWash < LockScreenWidgetTokens.washBottom)
        #expect(LockScreenWidgetTokens.labelDynamicTypeCap == .xLarge)
    }

    @Test func vesselKeepsItsStrokeFloorAtTheSmallestCircle() {
        let geometry = WidgetVesselGeometry(height: LockScreenWidgetTokens.vesselNumeral)
        #expect(geometry.stroke >= 1.5)
        #expect(geometry.height < 68)
        #expect(geometry.innerHeight > 0)
    }
}
