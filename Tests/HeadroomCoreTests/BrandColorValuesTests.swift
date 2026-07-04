import Testing
@testable import HeadroomCore

struct BrandColorValuesTests {
    @Test func providerAccentsMatchCanonicalSpec() {
        #expect(HeadroomBrandColorValues.claude == HeadroomRGBColor(red: 0.85, green: 0.47, blue: 0.26))
        #expect(HeadroomBrandColorValues.codex == HeadroomRGBColor(red: 0.28, green: 0.34, blue: 1.00))
    }

    @Test func usageSeverityColorsMatchCanonicalSpec() {
        #expect(HeadroomSeverityColorValues.healthy == HeadroomRGBColor(red: 0.20, green: 0.78, blue: 0.35))
        #expect(HeadroomSeverityColorValues.low == HeadroomRGBColor(red: 1.00, green: 0.62, blue: 0.04))
        #expect(HeadroomSeverityColorValues.critical == HeadroomRGBColor(red: 1.00, green: 0.27, blue: 0.23))
    }
}
