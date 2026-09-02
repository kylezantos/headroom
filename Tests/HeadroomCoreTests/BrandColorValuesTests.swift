import Foundation
import Testing
@testable import HeadroomCore

struct BrandColorValuesTests {
    @Test func providerAccentsMatchCanonicalSpec() {
        #expect(HeadroomBrandColorValues.claude == HeadroomRGBColor(red: 0.85, green: 0.47, blue: 0.26))
        #expect(HeadroomBrandColorValues.codex == HeadroomRGBColor(red: 0.28, green: 0.34, blue: 1.00))
        #expect(HeadroomBrandColorValues.grok == HeadroomRGBColor(red: 0.36, green: 0.40, blue: 0.46))
        #expect(HeadroomBrandColorValues.cursor == HeadroomRGBColor(red: 0.33, green: 0.34, blue: 0.38))
    }

    @Test func newProviderTextAccentsMatchCanonicalSpec() {
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.grok.raw, dark: false) == HeadroomRGBColor(red: 0.20, green: 0.22, blue: 0.25))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.grok.raw, dark: true) == HeadroomRGBColor(red: 0.78, green: 0.80, blue: 0.84))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.cursor.raw, dark: false) == HeadroomRGBColor(red: 0.17, green: 0.17, blue: 0.18))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.cursor.raw, dark: true) == HeadroomRGBColor(red: 0.81, green: 0.81, blue: 0.83))
    }

    /// Guards the P1 "grey-identity default arm" class of bug: every registered provider
    /// must resolve a real title accent (both schemes), not fall through to `.secondary`.
    /// Cursor's mark is inset like Claude's, so its optical scale must be corrected too.
    @Test func everyRegisteredProviderHasABrandTextAccent() {
        for id in [ProviderID.claude, .codex, .grok, .cursor] {
            #expect(HeadroomWidgetColorValues.textAccent(for: id.raw, dark: false) != nil, "\(id.raw) light")
            #expect(HeadroomWidgetColorValues.textAccent(for: id.raw, dark: true) != nil, "\(id.raw) dark")
        }
        #expect(HeadroomBrandMark.opticalScale(for: ProviderID.cursor.raw) == 0.9)
    }

    @Test func usageSeverityColorsMatchCanonicalSpec() {
        // Dark: vivid originals (critical nudged 0.27 → 0.34 green for the 3:1 bar-vs-track
        // floor). Light: darkened along the same hues so bars clear WCAG 1.4.11 on the
        // light track and read ≥4:1 as chip text on white.
        #expect(HeadroomSeverityColorValues.healthy(dark: true) == HeadroomRGBColor(red: 0.20, green: 0.78, blue: 0.35))
        #expect(HeadroomSeverityColorValues.low(dark: true) == HeadroomRGBColor(red: 1.00, green: 0.62, blue: 0.04))
        #expect(HeadroomSeverityColorValues.critical(dark: true) == HeadroomRGBColor(red: 1.00, green: 0.34, blue: 0.29))
        #expect(HeadroomSeverityColorValues.healthy(dark: false) == HeadroomRGBColor(red: 0.09, green: 0.52, blue: 0.22))
        #expect(HeadroomSeverityColorValues.low(dark: false) == HeadroomRGBColor(red: 0.70, green: 0.41, blue: 0.00))
        #expect(HeadroomSeverityColorValues.critical(dark: false) == HeadroomRGBColor(red: 0.85, green: 0.16, blue: 0.13))
    }

    @Test func usageSeverityLookupReturnsCanonicalValues() {
        for dark in [true, false] {
            #expect(HeadroomSeverityColorValues.color(for: UsageSeverity.healthy, dark: dark) == HeadroomSeverityColorValues.healthy(dark: dark))
            #expect(HeadroomSeverityColorValues.color(for: UsageSeverity.low, dark: dark) == HeadroomSeverityColorValues.low(dark: dark))
            #expect(HeadroomSeverityColorValues.color(for: UsageSeverity.critical, dark: dark) == HeadroomSeverityColorValues.critical(dark: dark))
            #expect(HeadroomSeverityColorValues.color(for: WidgetUsageSeverity.healthy, dark: dark) == HeadroomSeverityColorValues.healthy(dark: dark))
        }
    }

    @Test func meterTokensMatchTheApprovedSchemeSpecificValues() {
        #expect(HeadroomMeterColorValues.labelInk(dark: true) == HeadroomTint(
            color: HeadroomRGBColor(red: 0.92, green: 0.92, blue: 0.96),
            opacity: 0.90
        ))
        #expect(HeadroomMeterColorValues.labelInk(dark: false) == HeadroomTint(
            color: HeadroomRGBColor(red: 29.0 / 255.0, green: 31.0 / 255.0, blue: 36.0 / 255.0),
            opacity: 0.90
        ))
        #expect(HeadroomMeterColorValues.countdownInk(dark: true).opacity == 0.53)
        #expect(HeadroomMeterColorValues.countdownInk(dark: false).opacity == 0.72)

        #expect(HeadroomMeterColorValues.glassA(dark: true) == HeadroomTint(color: .white, opacity: 0.22))
        #expect(HeadroomMeterColorValues.glassB(dark: true) == HeadroomTint(color: .white, opacity: 0.11))
        #expect(HeadroomMeterColorValues.glassA(dark: false) == HeadroomTint(
            color: HeadroomRGBColor(red: 117.0 / 255.0, green: 124.0 / 255.0, blue: 134.0 / 255.0),
            opacity: 1
        ))
        #expect(HeadroomMeterColorValues.glassB(dark: false) == HeadroomTint(
            color: HeadroomRGBColor(red: 102.0 / 255.0, green: 108.0 / 255.0, blue: 117.0 / 255.0),
            opacity: 1
        ))
        #expect(HeadroomMeterColorValues.glassRim(dark: true) == HeadroomTint(color: .white, opacity: 0.25))
        #expect(HeadroomMeterColorValues.glassRim(dark: false) == HeadroomTint(color: .white, opacity: 0.30))

        #expect(HeadroomMeterColorValues.wellBackground(dark: true) == HeadroomRGBColor(
            red: 15.0 / 255.0, green: 17.0 / 255.0, blue: 20.0 / 255.0
        ))
        #expect(HeadroomMeterColorValues.wellBackground(dark: false) == HeadroomRGBColor(
            red: 223.0 / 255.0, green: 226.0 / 255.0, blue: 231.0 / 255.0
        ))
        #expect(HeadroomMeterColorValues.wellShadow(dark: true) == HeadroomTint(color: .black, opacity: 0.65))
        #expect(HeadroomMeterColorValues.wellShadow(dark: false) == HeadroomTint(color: .black, opacity: 0.20))

        #expect(HeadroomMeterColorValues.tickOff(dark: true) == HeadroomTint(color: .white, opacity: 0.09))
        #expect(HeadroomMeterColorValues.tickOff(dark: false) == HeadroomTint(color: .black, opacity: 0.08))
        #expect(HeadroomMeterColorValues.tickGlass(dark: true) == HeadroomTint(color: .white, opacity: 0.26))
        #expect(HeadroomMeterColorValues.tickGlass(dark: false) == HeadroomTint(
            color: HeadroomRGBColor(red: 107.0 / 255.0, green: 114.0 / 255.0, blue: 123.0 / 255.0),
            opacity: 1
        ))
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: true) == HeadroomTint(color: .white, opacity: 0.52))
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: false) == HeadroomTint(
            color: HeadroomRGBColor(red: 71.0 / 255.0, green: 78.0 / 255.0, blue: 87.0 / 255.0),
            opacity: 1
        ))

        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: true, surface: .well) == 0.42)
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: true, surface: .flat) == 0.58)
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: false, surface: .well) == 0.55)
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: false, surface: .flat) == 0.55)
        #expect(HeadroomMeterColorValues.ghostBodyOpacity(for: .healthy, dark: true) == 0.18)
        #expect(HeadroomMeterColorValues.ghostBodyOpacity(for: .critical, dark: true) == 0.22)
        #expect(HeadroomMeterColorValues.ghostBodyOpacity(for: .healthy, dark: false) == 0.30)
        #expect(HeadroomMeterColorValues.ghostBodyOpacity(for: .critical, dark: false) == 0.34)
    }

    @Test func meterTextClearsSmallTextContrastOnRaisedTileFills() {
        for dark in [true, false] {
            for background in raisedTileFillColors(dark: dark) {
                let label = composite(HeadroomMeterColorValues.labelInk(dark: dark), over: background)
                let countdown = composite(HeadroomMeterColorValues.countdownInk(dark: dark), over: background)
                #expect(contrastRatio(label, background) >= 4.5, "label, dark=\(dark)")
                #expect(contrastRatio(countdown, background) >= 4.5, "countdown, dark=\(dark)")
            }
        }
    }

    @Test func everySeverityClearsNonTextContrastAgainstTheTrack() {
        for dark in [true, false] {
            for background in raisedTileFillColors(dark: dark) {
                let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: background)
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let color = HeadroomSeverityColorValues.color(for: severity, dark: dark)
                    #expect(contrastRatio(color, track) >= 3, "\(severity), dark=\(dark)")
                }
            }
        }
    }

    @Test func rampStartsRemainChromaBearingInBothSchemes() {
        for scheme in MeterColorScheme.allCases {
            for surface in [MeterRampSurface.flat, .well] {
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let start = MeterRecipe.rampStops(
                        severity: severity,
                        scheme: scheme,
                        surface: surface
                    ).start
                    #expect(rgbChroma(start) >= 0.04, "\(severity), \(scheme), \(surface)")
                }
            }
        }
    }

    /// These are characterization measurements, not 3:1 pass assertions. Ghost is
    /// deliberately subtle, and U8 owns the live decision if that subtlety reads as lost.
    @Test func ghostBodyContrastOnTrackIsRecorded() {
        #expect(measuredGhostRatios(dark: true).min().map { abs($0 - 1.2295) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: true).max().map { abs($0 - 1.3733) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false).min().map { abs($0 - 1.3815) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false).max().map { abs($0 - 1.6345) < 0.0001 } == true)
    }

    /// Glass is also recorded rather than promoted to a blanket pass: its dark-scheme
    /// gradient measures below 3:1, while both light-scheme endpoints clear it.
    @Test func healthyGlassContrastOnTrackIsRecorded() {
        #expect(measuredGlassRatios(dark: true).min().map { abs($0 - 1.3782) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: true).max().map { abs($0 - 1.9544) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).min().map { abs($0 - 3.0986) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).max().map { abs($0 - 4.0254) < 0.0001 } == true)
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

private func raisedTileFillColors(dark: Bool) -> [HeadroomRGBColor] {
    // Flattened endpoints of RaisedTile's current glass fill in the design reference.
    [
        HeadroomWidgetColorValues.tileFillTop(dark: dark),
        HeadroomWidgetColorValues.tileFillBottom(dark: dark),
    ]
}

private func composite(_ tint: HeadroomTint, over background: HeadroomRGBColor) -> HeadroomRGBColor {
    mix(tint.color, weight: tint.opacity, with: background)
}

private func mix(
    _ foreground: HeadroomRGBColor,
    weight: Double,
    with background: HeadroomRGBColor
) -> HeadroomRGBColor {
    HeadroomRGBColor(
        red: foreground.red * weight + background.red * (1 - weight),
        green: foreground.green * weight + background.green * (1 - weight),
        blue: foreground.blue * weight + background.blue * (1 - weight)
    )
}

private func contrastRatio(_ lhs: HeadroomRGBColor, _ rhs: HeadroomRGBColor) -> Double {
    let lighter = max(relativeLuminance(lhs), relativeLuminance(rhs))
    let darker = min(relativeLuminance(lhs), relativeLuminance(rhs))
    return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ color: HeadroomRGBColor) -> Double {
    0.2126 * linearized(color.red)
        + 0.7152 * linearized(color.green)
        + 0.0722 * linearized(color.blue)
}

private func linearized(_ component: Double) -> Double {
    component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
}

private func rgbChroma(_ color: HeadroomRGBColor) -> Double {
    max(color.red, color.green, color.blue) - min(color.red, color.green, color.blue)
}

private func measuredGhostRatios(dark: Bool) -> [Double] {
    raisedTileFillColors(dark: dark).flatMap { background in
        let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: background)
        return [UsageSeverity.healthy, .low, .critical].map { severity in
            let body = HeadroomTint(
                color: HeadroomSeverityColorValues.color(for: severity, dark: dark),
                opacity: HeadroomMeterColorValues.ghostBodyOpacity(for: severity, dark: dark)
            )
            return contrastRatio(composite(body, over: track), track)
        }
    }
}

private func measuredGlassRatios(dark: Bool) -> [Double] {
    let glass = [
        HeadroomMeterColorValues.glassA(dark: dark),
        HeadroomMeterColorValues.glassB(dark: dark),
    ]
    return raisedTileFillColors(dark: dark).flatMap { background in
        let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: background)
        return glass.map { contrastRatio(composite($0, over: track), track) }
    }
}
