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
    @Test func everyRegisteredProviderHasABrandTextAccent() {
        for id in [ProviderID.claude, .codex, .grok, .cursor] {
            #expect(HeadroomWidgetColorValues.textAccent(for: id.raw, dark: false) != nil, "\(id.raw) light")
            #expect(HeadroomWidgetColorValues.textAccent(for: id.raw, dark: true) != nil, "\(id.raw) dark")
        }
    }

    // MARK: - OA2 brand-mark sizing rule

    /// The shared rule is still one number for everyone — the ink's larger dimension is 13/15
    /// of the slot — and `massCorrection` is the only per-provider dial on top of it, so any
    /// provider drifting off `13/15 × its correction` is a deliberate edit that has to land
    /// here first.
    ///
    /// PA9 set the first non-1.0 corrections. Equal ink *boxes* turned out not to be equal ink
    /// *mass*: measured coverage inside the same 13pt box ran Codex 0.71, Cursor 0.56, Claude
    /// 0.42, Grok 0.25, which put Grok's hairline slash directly under Cursor's solid cube in
    /// the four-provider card list. The corrections therefore have to run *opposite* to
    /// coverage — sparse marks grow, dense marks shrink — and that direction is asserted here
    /// so a later re-tune from live captures can move the magnitudes without silently
    /// inverting the intent.
    @Test func everyProviderRendersItsInkAtThirteenFifteenthsOfTheSlotTimesItsMassCorrection() {
        #expect(HeadroomBrandMark.inkFraction == 13.0 / 15.0)
        let corrections: [(ProviderID, Double)] = [
            (.claude, 1.05), (.codex, 0.92), (.grok, 1.10), (.cursor, 0.94),
        ]
        for (id, correction) in corrections {
            #expect(HeadroomBrandMark.massCorrection(for: id.raw) == correction, "\(id.raw) mass")
            #expect(
                abs(HeadroomBrandMark.inkScale(for: id.raw) - 13.0 / 15.0 * correction) < 1e-12,
                "\(id.raw) scale"
            )
        }
        // Sparse ink grows, dense ink shrinks.
        #expect(HeadroomBrandMark.massCorrection(for: ProviderID.grok.raw) > 1)
        #expect(HeadroomBrandMark.massCorrection(for: ProviderID.claude.raw) > 1)
        #expect(HeadroomBrandMark.massCorrection(for: ProviderID.codex.raw) < 1)
        #expect(HeadroomBrandMark.massCorrection(for: ProviderID.cursor.raw) < 1)
        // Grok is the sparsest mark, Codex the densest, so they bound the table.
        for id in [ProviderID.claude, .codex, .cursor] {
            #expect(HeadroomBrandMark.massCorrection(for: ProviderID.grok.raw)
                >= HeadroomBrandMark.massCorrection(for: id.raw))
            #expect(HeadroomBrandMark.massCorrection(for: ProviderID.codex.raw)
                <= HeadroomBrandMark.massCorrection(for: id.raw))
        }
        // An unregistered provider gets the uncorrected shared rule.
        #expect(HeadroomBrandMark.massCorrection(for: "unknown-provider") == 1.0)
        #expect(HeadroomBrandMark.inkScale(for: "unknown-provider") == 13.0 / 15.0)
    }

    /// The larger dimension lands on the provider's mass-corrected share of 13pt in the card's
    /// 15pt slot, the aspect is preserved rather than padded back to square, and the shorter
    /// dimension is what shrinks (Grok's slash vertically, Cursor's cube horizontally).
    @Test func markSizeFitsTheLargerInkDimensionAndKeepsAspect() {
        for id in [ProviderID.claude, .codex, .grok, .cursor] {
            let mark = HeadroomBrandMark.markSize(for: id.raw, slot: 15)
            let box = 13 * HeadroomBrandMark.massCorrection(for: id.raw)
            #expect(abs(max(mark.width, mark.height) - box) < 0.0001, "\(id.raw) larger dimension")
            #expect(min(mark.width, mark.height) <= box + 0.0001, "\(id.raw) shorter dimension")
            let aspect = HeadroomBrandMark.inkAspect(for: id.raw)
            #expect(abs(mark.width / mark.height - aspect) < 0.0001, "\(id.raw) aspect")
        }
        // Square marks fill their corrected box in both axes; the two non-square marks do not.
        for id in [ProviderID.claude, .codex] {
            let mark = HeadroomBrandMark.markSize(for: id.raw, slot: 15)
            #expect(abs(mark.height - 13 * HeadroomBrandMark.massCorrection(for: id.raw)) < 0.0001)
            #expect(abs(mark.width - mark.height) < 0.0001)
        }
        #expect(HeadroomBrandMark.markSize(for: ProviderID.grok.raw, slot: 15).height
            < 13 * HeadroomBrandMark.massCorrection(for: ProviderID.grok.raw))
        #expect(HeadroomBrandMark.markSize(for: ProviderID.cursor.raw, slot: 15).width
            < 13 * HeadroomBrandMark.massCorrection(for: ProviderID.cursor.raw))
    }

    @Test func markSizeScalesLinearlyWithTheSlot() {
        let small = HeadroomBrandMark.markSize(for: ProviderID.cursor.raw, slot: 15)
        let large = HeadroomBrandMark.markSize(for: ProviderID.cursor.raw, slot: 30)
        #expect(abs(large.width - small.width * 2) < 0.0001)
        #expect(abs(large.height - small.height * 2) < 0.0001)
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
        // PA13: dark stepped 0.53 → 0.66; ratio-matched pairs left it ~half of light's |Lc|.
        #expect(HeadroomMeterColorValues.countdownInk(dark: true).opacity == 0.66)
        #expect(HeadroomMeterColorValues.countdownInk(dark: false).opacity == 0.72)

        // PA1: light is black-alpha over the card, mirroring dark's white-alpha (it used to be
        // opaque mid-greys, which is what let the neutral fill outshout the amber one).
        #expect(HeadroomMeterColorValues.glassA(dark: true) == HeadroomTint(color: .white, opacity: 0.22))
        #expect(HeadroomMeterColorValues.glassB(dark: true) == HeadroomTint(color: .white, opacity: 0.11))
        #expect(HeadroomMeterColorValues.glassA(dark: false) == HeadroomTint(color: .black, opacity: 0.24))
        #expect(HeadroomMeterColorValues.glassB(dark: false) == HeadroomTint(color: .black, opacity: 0.36))
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
        #expect(HeadroomMeterColorValues.tickGlass(dark: false) == HeadroomTint(color: .black, opacity: 0.24))
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: true) == HeadroomTint(color: .white, opacity: 0.52))
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: false) == HeadroomTint(color: .black, opacity: 0.36))

        // PB13: the stale dim and the quarter-mark hairline moved out of `MeterGauge` and in
        // here with the rest of the meter chrome; only the numbers travel, the bases stay the
        // system label colours at the SwiftUI edge.
        #expect(HeadroomMeterColorValues.staleFillOpacity == 0.55)
        #expect(HeadroomMeterColorValues.quarterMarkOpacity(dark: true) == 0.11)
        #expect(HeadroomMeterColorValues.quarterMarkOpacity(dark: false) == 0.14)

        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: true, surface: .well) == 0.42)
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: true, surface: .flat) == 0.58)
        // Light retuned 0.55 → 0.75 with the vivid fill tier (the lighter fills washed the
        // ramp start into the track at 0.55). Increase Contrast reverts fills *and* mix.
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: false, surface: .well) == 0.75)
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: false, surface: .flat) == 0.75)
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: false, surface: .well, increasedContrast: true) == 0.55)
        #expect(HeadroomMeterColorValues.rampStartSeverityMix(dark: true, surface: .flat, increasedContrast: true) == 0.58)
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

    @Test func severityFillTokensMatchCanonicalSpec() {
        // Fill tier (Sep 2026): vivid light defaults, text-tier fallbacks under Increase
        // Contrast, dark unchanged in both branches. Amber was tuned down from the design
        // brief's (0.96, 0.58, 0.05) to clear the ≥2.0:1-vs-track floor (1.70 → 2.06).
        #expect(HeadroomSeverityColorValues.healthyFill(dark: false, increasedContrast: false) == HeadroomRGBColor(red: 0.16, green: 0.66, blue: 0.30))
        #expect(HeadroomSeverityColorValues.lowFill(dark: false, increasedContrast: false) == HeadroomRGBColor(red: 0.91, green: 0.50, blue: 0.02))
        #expect(HeadroomSeverityColorValues.criticalFill(dark: false, increasedContrast: false) == HeadroomRGBColor(red: 0.90, green: 0.22, blue: 0.20))

        for severity in [UsageSeverity.healthy, .low, .critical] {
            #expect(
                HeadroomSeverityColorValues.fill(for: severity, dark: false, increasedContrast: true)
                    == HeadroomSeverityColorValues.color(for: severity, dark: false),
                "light increased contrast falls back to the text tier: \(severity)"
            )
            for increasedContrast in [true, false] {
                #expect(
                    HeadroomSeverityColorValues.fill(for: severity, dark: true, increasedContrast: increasedContrast)
                        == HeadroomSeverityColorValues.color(for: severity, dark: true),
                    "dark fills are the dark text tier: \(severity)"
                )
            }
        }

        // The two `fill(for:)` overloads (UsageSeverity / WidgetUsageSeverity) cannot drift.
        #expect(HeadroomSeverityColorValues.fill(for: WidgetUsageSeverity.low, dark: false, increasedContrast: false)
            == HeadroomSeverityColorValues.fill(for: UsageSeverity.low, dark: false, increasedContrast: false))
    }

    /// The 3:1 (WCAG 1.4.11) floor still holds everywhere it is claimed: every dark fill, and
    /// every light fill once the user turns on Increase Contrast. The *default* light
    /// appearance is deliberately exempt — see the redundant-visualization test below.
    @Test func everySeverityFillClearsNonTextContrastWhereItIsClaimed() {
        for dark in [true, false] {
            for background in raisedTileFillColors(dark: dark) {
                let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: background)
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let fill = HeadroomSeverityColorValues.fill(
                        for: severity,
                        dark: dark,
                        increasedContrast: true
                    )
                    #expect(contrastRatio(fill, track) >= 3, "\(severity), dark=\(dark)")
                }
            }
        }
    }

    /// Characterizes the deliberate policy change. In the default light appearance the bar is a
    /// *redundant* visualization — the percent numeral beside it states the value at full text
    /// contrast — so the fills trade 1.4.11's 3:1 for vividness and are held instead to a
    /// legibility floor of ≥2.0:1 against the track and ≥2.5:1 against the card behind it.
    /// Increase Contrast restores the 3:1 fills (asserted above).
    @Test func defaultLightSeverityFillsClearTheRedundantVisualizationFloor() {
        for background in raisedTileFillColors(dark: false) {
            let track = composite(HeadroomWidgetColorValues.barTrack(dark: false), over: background)
            for severity in [UsageSeverity.healthy, .low, .critical] {
                let fill = HeadroomSeverityColorValues.fill(
                    for: severity,
                    dark: false,
                    increasedContrast: false
                )
                #expect(contrastRatio(fill, track) >= 2.0, "\(severity) vs track")
                #expect(contrastRatio(fill, background) >= 2.5, "\(severity) vs card")
            }
        }
    }

    /// Why the policy is a two-tier split rather than a palette retune, and why the light track
    /// stays at black @ 0.12 (renamed from `vividDarkSeverityColorsCannotBeReusedOnTheLightTrack`
    /// now that the default light fills sit below 3:1 on purpose). On the light track no
    /// saturated fill can reach 3:1: the track sits at L≈0.745, so a 3:1 fill needs L ≤ 0.215 —
    /// darker than any vivid sRGB amber (the dark token is L≈0.41). And *deepening* the track
    /// lowers the ratio instead of raising it, because these mid-luminance fills are darker than
    /// the track and converge on it as it darkens (amber: 2.06 → 1.46 at 0.18 alpha). Both facts
    /// are asserted so a future "just darken the track" fix fails here first.
    @Test func noVividLightFillCanClearThreeToOneOnTheLightTrack() {
        let card = raisedTileFillColors(dark: false)[1]
        let track = composite(HeadroomWidgetColorValues.barTrack(dark: false), over: card)

        for severity in [UsageSeverity.healthy, .low, .critical] {
            let darkToken = HeadroomSeverityColorValues.color(for: severity, dark: true)
            let lightFill = HeadroomSeverityColorValues.fill(
                for: severity,
                dark: false,
                increasedContrast: false
            )
            #expect(contrastRatio(darkToken, track) < 3, "dark \(severity) reused on the light track")
            // Critical's light fill happens to clear 3:1 on its own; healthy and low do not,
            // and the policy does not require them to.
            if severity != .critical {
                #expect(contrastRatio(lightFill, track) < 3, "default light \(severity) is intentionally below 3:1")
            }

            let deeperTrack = composite(HeadroomTint(color: .black, opacity: 0.18), over: card)
            #expect(
                contrastRatio(lightFill, deeperTrack) < contrastRatio(lightFill, track),
                "deepening the light track reduces fill separation: \(severity)"
            )
        }
    }

    @Test func rampStartsRemainChromaBearingInBothSchemes() {
        for scheme in MeterColorScheme.allCases {
            for surface in [MeterRampSurface.flat, .well] {
                for increasedContrast in [false, true] {
                    for severity in [UsageSeverity.healthy, .low, .critical] {
                        let start = MeterRecipe.rampStops(
                            severity: severity,
                            scheme: scheme,
                            surface: surface,
                            increasedContrast: increasedContrast
                        ).start
                        #expect(rgbChroma(start) >= 0.04, "\(severity), \(scheme), \(surface), ic=\(increasedContrast)")
                    }
                }
            }
        }
    }

    /// The light ramp-start retune (0.55 → 0.75) exists to hold the start's separation from the
    /// track once the fills went vivid; at 0.55 the amber start fell to 1.27:1 (was 1.55:1).
    /// Each default light start now matches or beats what the old text-tier ramp measured.
    @Test func lightRampStartsKeepTheirSeparationFromTheTrack() {
        let previousLightStartRatios: [UsageSeverity: Double] = [
            .healthy: 1.628,
            .low: 1.545,
            .critical: 1.833,
        ]
        for background in raisedTileFillColors(dark: false) {
            let track = composite(HeadroomWidgetColorValues.barTrack(dark: false), over: background)
            for (severity, previous) in previousLightStartRatios {
                let start = MeterRecipe.rampStops(
                    severity: severity,
                    scheme: .light,
                    surface: .flat,
                    increasedContrast: false
                ).start
                #expect(contrastRatio(start, track) >= previous, "\(severity) ramp start")
            }
        }
    }

    /// These are characterization measurements, not 3:1 pass assertions. Ghost is
    /// deliberately subtle, and U8 owns the live decision if that subtlety reads as lost.
    /// The light *default* band moved (1.3815–1.6345 → 1.2584–1.5465) because Ghost tints the
    /// severity fill and the vivid light fills sit closer in luminance to the track. The
    /// increased-contrast branch keeps the old band exactly, because it keeps the old colors.
    @Test func ghostBodyContrastOnTrackIsRecorded() {
        #expect(measuredGhostRatios(dark: true, increasedContrast: false).min().map { abs($0 - 1.2295) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: true, increasedContrast: false).max().map { abs($0 - 1.3733) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: false).min().map { abs($0 - 1.2584) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: false).max().map { abs($0 - 1.5465) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: true).min().map { abs($0 - 1.3815) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: true).max().map { abs($0 - 1.6345) < 0.0001 } == true)
    }

    /// Glass is recorded rather than promoted to a blanket pass. Dark is unchanged. The light
    /// band moved 3.0986–4.0254 → 1.7514–2.4396 under PA1: the old light glass was an opaque
    /// mid-grey that measured *higher* against its own track than any severity fill did, which
    /// is precisely the inversion PA1 removes. Glass is decorative chrome — the percent numeral
    /// beside it carries the value at full text contrast — so the drop is the fix, not a
    /// regression.
    @Test func healthyGlassContrastOnTrackIsRecorded() {
        #expect(measuredGlassRatios(dark: true).min().map { abs($0 - 1.3782) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: true).max().map { abs($0 - 1.9544) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).min().map { abs($0 - 1.7514) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).max().map { abs($0 - 2.4396) < 0.0001 } == true)
    }

    // MARK: - PA1: neutral never outshouts an event

    /// "Colour as event" means a neutral meter says *nothing is happening* and a coloured one
    /// says something is. That only reads if the neutral fill is the quietest thing in the
    /// list. In light it was not: the neutral greys were opaque mid-greys measuring APCA
    /// |Lc| ≈ 72 against the card while the amber "running low" fill measured ≈ 52, so on the
    /// shipping default a healthy 72% bar visibly outweighed a low 38% bar above it and the
    /// mode inverted its own meaning.
    ///
    /// Measured the way it renders: the neutral fill is an alpha over the bar track, which is
    /// itself an alpha over the card; the severity fills paint opaque over that same track.
    /// The ordering is what is pinned here — the literals stay tunable from live captures.
    ///
    /// The two *end* tokens are exempt and stay exempt. `tickGlassCap` is a one-cell tip
    /// marker, not the fill's weight, and dark's 0.52 cap has always measured above the dark
    /// critical fill; `glassB` is the glass gradient's shaded foot for the same reason.
    @Test func theNeutralMeterBodyNeverOutweighsASeverityFillInEitherScheme() {
        for dark in [true, false] {
            for card in raisedTileFillColors(dark: dark) {
                let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: card)
                let quietestEvent = [UsageSeverity.healthy, .low, .critical]
                    .map { severity in
                        abs(apcaLc(
                            text: HeadroomSeverityColorValues.fill(
                                for: severity,
                                dark: dark,
                                increasedContrast: false
                            ),
                            background: card
                        ))
                    }
                    .min() ?? 0
                let bodies = [
                    ("glassA", HeadroomMeterColorValues.glassA(dark: dark)),
                    ("tickGlass", HeadroomMeterColorValues.tickGlass(dark: dark)),
                ]
                for (name, tint) in bodies {
                    let neutral = abs(apcaLc(text: composite(tint, over: track), background: card))
                    #expect(
                        neutral < quietestEvent,
                        "\(name) |Lc| \(neutral) vs quietest severity \(quietestEvent), dark=\(dark)"
                    )
                }
            }
        }
    }

    /// The structural half of PA1: light is *authored* the way dark is, an alpha over the card,
    /// so the two branches cannot drift back apart into "opaque grey here, translucent white
    /// there". A future opaque literal fails here even if it happens to measure quietly on the
    /// two card fills this suite samples.
    @Test func lightNeutralMeterTokensMirrorDarksAlphaConstruction() {
        let tokens: [(String, (Bool) -> HeadroomTint)] = [
            ("glassA", HeadroomMeterColorValues.glassA),
            ("glassB", HeadroomMeterColorValues.glassB),
            ("tickGlass", HeadroomMeterColorValues.tickGlass),
            ("tickGlassCap", HeadroomMeterColorValues.tickGlassCap),
        ]
        for (name, token) in tokens {
            #expect(token(true).color == .white, "\(name) dark base")
            #expect(token(false).color == .black, "\(name) light base")
            #expect(token(true).opacity < 1, "\(name) dark is an alpha")
            #expect(token(false).opacity < 1, "\(name) light is an alpha")
        }
        // Each scheme's end stop is heavier than its body, in both branches.
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: true).opacity
            > HeadroomMeterColorValues.tickGlass(dark: true).opacity)
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: false).opacity
            > HeadroomMeterColorValues.tickGlass(dark: false).opacity)
    }

    // MARK: - PA13: dark muted text re-derived by |Lc|

    /// The dark muted-text steps were matched to their light partners on WCAG *ratio*, which is
    /// polarity-blind — the same ratio buys much less separation on a dark surface. Measured on
    /// APCA against the same card fills, the dark account title came out at |Lc| 33 against
    /// light's 79 (41%), and the plan pill, on the system `.tertiary`, at ≈ 20.
    ///
    /// Two relationships are pinned rather than the literals: every muted role clears APCA's
    /// Lc 45 tier in *both* schemes, and no dark role keeps less than 55% of its light partner's
    /// separation. Re-tuning the numbers is fine; letting one scheme recede again is not.
    @Test func everyMutedTextRoleHoldsItsSeparationInBothSchemes() {
        for (name, measured) in mutedTextSeparations() {
            for (dark, values) in measured {
                for value in values {
                    #expect(value >= 45, "\(name) |Lc| \(value), dark=\(dark)")
                }
            }
            for (darkValue, lightValue) in zip(measured[true] ?? [], measured[false] ?? []) {
                #expect(
                    darkValue / lightValue >= 0.55,
                    "\(name) keeps \(darkValue / lightValue) of its light separation"
                )
            }
        }
    }

    /// The two-level grey hierarchy the light branch documents has to hold in dark too — the
    /// tertiary bump would otherwise have pushed tertiary *past* secondary, which is why
    /// secondary moved with it.
    @Test func secondaryTextStaysAboveTertiaryTextInBothSchemes() {
        for dark in [true, false] {
            for card in raisedTileFillColors(dark: dark) {
                let secondary = abs(apcaLc(
                    text: composite(HeadroomWidgetColorValues.secondaryText(dark: dark), over: card),
                    background: card
                ))
                let tertiary = abs(apcaLc(
                    text: composite(HeadroomWidgetColorValues.tertiaryText(dark: dark), over: card),
                    background: card
                ))
                #expect(secondary > tertiary, "dark=\(dark): secondary \(secondary), tertiary \(tertiary)")
            }
        }
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

private func measuredGhostRatios(dark: Bool, increasedContrast: Bool) -> [Double] {
    raisedTileFillColors(dark: dark).flatMap { background in
        let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: background)
        return [UsageSeverity.healthy, .low, .critical].map { severity in
            let body = HeadroomTint(
                color: HeadroomSeverityColorValues.fill(
                    for: severity,
                    dark: dark,
                    increasedContrast: increasedContrast
                ),
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

/// APCA-W3 (0.0.98 G-4g) lightness contrast, signed: positive for dark-on-light, negative for
/// light-on-dark. WCAG's ratio is polarity-blind, which is exactly what let the dark muted text
/// and the light neutral meter greys drift (PA1, PA13), so those two decisions are measured
/// here instead. Inputs are already-composited opaque sRGB.
private func apcaLc(text: HeadroomRGBColor, background: HeadroomRGBColor) -> Double {
    let textY = apcaScreenLuminance(text)
    let backgroundY = apcaScreenLuminance(background)
    guard abs(backgroundY - textY) >= 0.0005 else { return 0 }
    if backgroundY > textY {
        let sapc = (pow(backgroundY, 0.56) - pow(textY, 0.57)) * 1.14
        return sapc < 0.1 ? 0 : (sapc - 0.027) * 100
    }
    let sapc = (pow(backgroundY, 0.65) - pow(textY, 0.62)) * 1.14
    return sapc > -0.1 ? 0 : (sapc + 0.027) * 100
}

private func apcaScreenLuminance(_ color: HeadroomRGBColor) -> Double {
    let y = 0.2126729 * pow(color.red, 2.4)
        + 0.7151522 * pow(color.green, 2.4)
        + 0.0721750 * pow(color.blue, 2.4)
    // APCA's soft black clamp.
    return y < 0.022 ? y + pow(0.022 - y, 1.414) : y
}

/// Every muted text role's |Lc| on both card fills, per scheme. The plan pill is measured on
/// the identity capsule it actually sits in (white @ 0.06 dark / black @ 0.045 light over the
/// card) rather than on the bare card, because that is the surface it has to read against.
private func mutedTextSeparations() -> [(String, [Bool: [Double]])] {
    func onCard(_ tint: @escaping (Bool) -> HeadroomTint) -> [Bool: [Double]] {
        var result: [Bool: [Double]] = [:]
        for dark in [true, false] {
            result[dark] = raisedTileFillColors(dark: dark).map { card in
                abs(apcaLc(text: composite(tint(dark), over: card), background: card))
            }
        }
        return result
    }

    var planPill: [Bool: [Double]] = [:]
    for dark in [true, false] {
        let capsule = HeadroomTint(color: dark ? .white : .black, opacity: dark ? 0.06 : 0.045)
        planPill[dark] = raisedTileFillColors(dark: dark).map { card in
            let surface = composite(capsule, over: card)
            return abs(apcaLc(
                text: composite(HeadroomWidgetColorValues.planLabel(dark: dark), over: surface),
                background: surface
            ))
        }
    }

    return [
        ("accountTitle", onCard(HeadroomWidgetColorValues.accountTitle)),
        ("secondaryText", onCard(HeadroomWidgetColorValues.secondaryText)),
        ("tertiaryText", onCard(HeadroomWidgetColorValues.tertiaryText)),
        ("countdownInk", onCard(HeadroomMeterColorValues.countdownInk)),
        ("planLabel", planPill),
    ]
}
