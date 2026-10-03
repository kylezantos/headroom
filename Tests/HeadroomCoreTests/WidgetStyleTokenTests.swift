import Testing
@testable import HeadroomCore

/// Pins the widget-style tokens to the approved mocks (2026-10-02 widget-styles plan, KTD8).
struct WidgetStyleTokenTests {
    @Test func heroNumeralsMatchTheMocks() {
        let table: [(WidgetLayoutStyle, [Double])] = [
            (.nestedMeter, [20, 30, 42]),
            (.vesselHero, [36, 30, 42]),
            (.tightestFirst, [22, 34, 34]),
            (.liquidLevel, [44, 38, 50]),
        ]
        for (style, sizes) in table {
            let actual = [WidgetFamily.small, .medium, .large].map {
                WidgetStyleType.heroNumeral(style: style, family: $0, providerCount: 2)
            }
            #expect(actual == sizes, "\(style)")
        }
    }

    @Test func singleProviderVesselHeroMediumGetsTheLargerHero() {
        #expect(WidgetStyleType.heroNumeral(style: .vesselHero, family: .medium, providerCount: 1) == 34)
    }

    @Test func heroNumeralsStayAboveTheLadder() {
        for style in WidgetLayoutStyle.allCases where style != .nestedMeter {
            for family in WidgetFamily.allCases {
                #expect(WidgetStyleType.heroNumeral(style: style, family: family, providerCount: 2) > 18)
            }
        }
    }

    @Test func nestedMeterRailsAreThinnerThanTheirParent() {
        for family in WidgetFamily.allCases {
            #expect(WidgetStyleMetrics.nestedRail(family) < WidgetStyleMetrics.nestedParentBar(family))
        }
    }

    @Test func washIsTranslucentInEveryMode() {
        #expect(WidgetStyleMetrics.washTopOpacity < 1)
        #expect(WidgetStyleMetrics.washBottomOpacity < WidgetStyleMetrics.washTopOpacity)
        #expect(WidgetStyleMetrics.washMonochromeOpacity < 0.2)
    }
}
