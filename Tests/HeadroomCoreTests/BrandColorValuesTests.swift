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

    @Test func usageSeverityLookupReturnsCanonicalValues() {
        #expect(HeadroomSeverityColorValues.color(for: UsageSeverity.healthy) == HeadroomSeverityColorValues.healthy)
        #expect(HeadroomSeverityColorValues.color(for: UsageSeverity.low) == HeadroomSeverityColorValues.low)
        #expect(HeadroomSeverityColorValues.color(for: UsageSeverity.critical) == HeadroomSeverityColorValues.critical)
    }

    @Test func widgetContainerBackgroundMatchesCanonicalSpec() {
        #expect(HeadroomWidgetColorValues.containerBackgroundTop(dark: true) == HeadroomRGBColor(red: 0.082, green: 0.090, blue: 0.114))
        #expect(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: true) == HeadroomRGBColor(red: 0.061, green: 0.070, blue: 0.091))
        #expect(HeadroomWidgetColorValues.containerBackgroundBottom(dark: true) == HeadroomRGBColor(red: 0.043, green: 0.051, blue: 0.067))
        #expect(HeadroomWidgetColorValues.containerBackgroundTop(dark: false) == HeadroomRGBColor(red: 0.965, green: 0.969, blue: 0.976))
        #expect(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: false) == HeadroomRGBColor(red: 0.945, green: 0.951, blue: 0.963))
        #expect(HeadroomWidgetColorValues.containerBackgroundBottom(dark: false) == HeadroomRGBColor(red: 0.925, green: 0.933, blue: 0.949))
        #expect(HeadroomWidgetColorValues.containerBackgroundGlow(dark: true) == HeadroomTint(color: HeadroomRGBColor(red: 0.431, green: 0.475, blue: 1.0), opacity: 0.10))
        #expect(HeadroomWidgetColorValues.containerBackgroundGlow(dark: false) == HeadroomTint(color: HeadroomRGBColor(red: 0.431, green: 0.475, blue: 1.0), opacity: 0.08))
    }

    @Test func widgetTileMaterialsMatchCanonicalSpec() {
        #expect(HeadroomWidgetColorValues.tileFillTop(dark: true) == HeadroomRGBColor(red: 0.145, green: 0.152, blue: 0.176))
        #expect(HeadroomWidgetColorValues.tileFillBottom(dark: true) == HeadroomRGBColor(red: 0.098, green: 0.106, blue: 0.129))
        #expect(HeadroomWidgetColorValues.tileFillTop(dark: false) == .white)
        #expect(HeadroomWidgetColorValues.tileFillBottom(dark: false) == HeadroomRGBColor(red: 0.984, green: 0.984, blue: 0.988))
        #expect(HeadroomWidgetColorValues.tileRing(dark: true) == HeadroomTint(color: .white, opacity: 0.065))
        #expect(HeadroomWidgetColorValues.tileRing(dark: false) == HeadroomTint(color: .black, opacity: 0.05))
        #expect(HeadroomWidgetColorValues.tileTopRim(dark: true) == HeadroomTint(color: .white, opacity: 0.07))
        #expect(HeadroomWidgetColorValues.tileTopRim(dark: false) == HeadroomTint(color: .white, opacity: 0))
        #expect(HeadroomWidgetColorValues.tileCloseShadow(dark: true) == HeadroomTint(color: .black, opacity: 0.28))
        #expect(HeadroomWidgetColorValues.tileAmbientShadow(dark: true) == HeadroomTint(color: .black, opacity: 0.40))
        #expect(HeadroomWidgetColorValues.tileLongShadow(dark: false) == HeadroomTint(color: .black, opacity: 0.05))
    }
}
