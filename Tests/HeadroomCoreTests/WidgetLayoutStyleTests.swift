import Testing
@testable import HeadroomCore

struct WidgetLayoutStyleTests {
    @Test func defaultsAreNestedMeterAndAlwaysColored() {
        #expect(WidgetLayoutStyle.default == .nestedMeter)
        #expect(WidgetColorMode.default == .solid)
    }

    @Test func unknownStoredStyleFallsBackToNestedMeter() {
        #expect(WidgetLayoutStyle(storedValue: "classic") == .nestedMeter)
        #expect(WidgetLayoutStyle(storedValue: "") == .nestedMeter)
        #expect(WidgetLayoutStyle(storedValue: nil) == .nestedMeter)
    }

    @Test func unknownStoredColorFallsBackToAlwaysColored() {
        #expect(WidgetColorMode(storedValue: "rainbow") == .solid)
        #expect(WidgetColorMode(storedValue: nil) == .solid)
    }

    @Test func stylesRoundTripThroughTheirStoredValues() {
        for style in WidgetLayoutStyle.allCases {
            #expect(WidgetLayoutStyle(storedValue: style.rawValue) == style)
        }
        for mode in WidgetColorMode.allCases {
            #expect(WidgetColorMode(storedValue: mode.rawValue) == mode)
        }
    }

    /// The raw values are persisted inside every placed widget's configuration; renaming one
    /// would silently reset that widget to the default.
    @Test func storedValuesAreStable() {
        #expect(WidgetLayoutStyle.allCases.map(\.rawValue) == ["nestedMeter", "vesselHero", "tightestFirst", "liquidLevel"])
        #expect(WidgetColorMode.allCases.map(\.rawValue) == ["solid", "event"])
    }

    @Test func displayNamesMatchTheEditWidgetCopy() {
        #expect(WidgetLayoutStyle.allCases.map(\.displayName) == ["Nested Meter", "Vessel Hero", "Tightest First", "Liquid Level"])
        #expect(WidgetColorMode.solid.displayName == "Always colored")
        #expect(WidgetColorMode.event.displayName == "Only when low")
    }
}
