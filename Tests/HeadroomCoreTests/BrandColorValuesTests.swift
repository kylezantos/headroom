import Foundation
import Testing
@testable import HeadroomCore

struct BrandColorValuesTests {
    /// R2C18: the Claude accent *is* the mark's own fill. It used to be a hand-authored
    /// `#D97842` at H 47.8° beside a `#D97757` SVG at H 38.8° — the same card carrying two
    /// oranges nine degrees apart. Codex is unchanged in appearance; it is simply re-authored
    /// on its own measured hue so the whole family has one construction.
    @Test func providerAccentsMatchCanonicalSpec() {
        let claude = HeadroomOKLCH(HeadroomBrandColorValues.claude)
        #expect(abs(claude.lightness - 0.672) < 0.002)
        #expect(abs(claude.chroma - 0.131) < 0.002)
        #expect(abs(claude.hue - HeadroomBrandColorValues.claudeHue) < 0.5)
        // The SVG's fill, to the byte.
        #expect(hex(HeadroomBrandColorValues.claude) == "#D97757")

        let codex = HeadroomOKLCH(HeadroomBrandColorValues.codex)
        #expect(abs(codex.lightness - 0.555) < 0.002)
        #expect(abs(codex.hue - HeadroomBrandColorValues.codexHue) < 0.5)
        #expect(distance(HeadroomBrandColorValues.codex, HeadroomRGBColor(red: 0.28, green: 0.34, blue: 1.00)) < 0.01)

        #expect(HeadroomBrandColorValues.grok == HeadroomRGBColor(red: 0.36, green: 0.40, blue: 0.46))
        #expect(HeadroomBrandColorValues.cursor == HeadroomRGBColor(red: 0.33, green: 0.34, blue: 0.38))
        #expect(HeadroomBrandColorValues.copilot == HeadroomRGBColor(red: 0.34, green: 0.37, blue: 0.43))
        #expect(HeadroomBrandColorValues.opencode == HeadroomRGBColor(red: 0.35, green: 0.34, blue: 0.34))
    }

    /// R2C18: every Claude/Codex brand value is a stop on one constant-hue ramp — accent,
    /// title accent, and both CTA gradient ends. A new literal at a different hue fails here.
    @Test func everyBrandRampStopHoldsItsFamilyHue() {
        var claudeStops: [(String, HeadroomRGBColor)] = [("accent", HeadroomBrandColorValues.claude)]
        var codexStops: [(String, HeadroomRGBColor)] = [("accent", HeadroomBrandColorValues.codex)]
        for dark in [true, false] {
            claudeStops += [
                ("textAccent dark=\(dark)", HeadroomBrandRamp.claudeTextAccent(dark: dark)),
                ("ctaTop dark=\(dark)", HeadroomBrandRamp.claudeCTATop(dark: dark)),
                ("ctaBottom dark=\(dark)", HeadroomBrandRamp.claudeCTABottom(dark: dark)),
            ]
            codexStops += [
                ("textAccent dark=\(dark)", HeadroomBrandRamp.codexTextAccent(dark: dark)),
                ("ctaTop dark=\(dark)", HeadroomBrandRamp.codexCTATop(dark: dark)),
                ("ctaBottom dark=\(dark)", HeadroomBrandRamp.codexCTABottom(dark: dark)),
            ]
        }
        for (name, stop) in claudeStops {
            let hue = HeadroomOKLCH(stop).hue
            #expect(abs(hue - HeadroomBrandColorValues.claudeHue) < 2, "claude \(name) at H \(hue)")
        }
        for (name, stop) in codexStops {
            let hue = HeadroomOKLCH(stop).hue
            #expect(abs(hue - HeadroomBrandColorValues.codexHue) < 2, "codex \(name) at H \(hue)")
        }
        // The widget/popover title accent reads the ramp, so the two cannot drift apart.
        for dark in [true, false] {
            #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.claude.raw, dark: dark)
                == HeadroomBrandRamp.claudeTextAccent(dark: dark))
            #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.codex.raw, dark: dark)
                == HeadroomBrandRamp.codexTextAccent(dark: dark))
        }
        // The CTA is a gradient, so its bottom stop is the darker one in both schemes.
        for dark in [true, false] {
            #expect(HeadroomOKLCH(HeadroomBrandRamp.claudeCTABottom(dark: dark)).lightness
                < HeadroomOKLCH(HeadroomBrandRamp.claudeCTATop(dark: dark)).lightness)
            #expect(HeadroomOKLCH(HeadroomBrandRamp.codexCTABottom(dark: dark)).lightness
                < HeadroomOKLCH(HeadroomBrandRamp.codexCTATop(dark: dark)).lightness)
        }
    }

    /// R2C18: the CTA carries a white 13pt label. The dark tops used to measure 4.05:1
    /// (Claude) and 3.97:1 (Codex) against it while the comment beside them claimed the ramp
    /// "averages ≈4.5:1" — so the *top* stop, the lightest thing under the label, is what has
    /// to clear AA, not an average of the button face.
    @Test func whiteOnEveryCTATopClearsSmallTextContrast() {
        for dark in [true, false] {
            for (name, top) in [
                ("claude", HeadroomBrandRamp.claudeCTATop(dark: dark)),
                ("codex", HeadroomBrandRamp.codexCTATop(dark: dark)),
            ] {
                let measured = contrastRatio(.white, top)
                #expect(measured >= 4.5, "\(name) CTA top, dark=\(dark): \(measured):1")
                // The bottom stop is darker, so the whole face clears it too.
                let bottom = name == "claude"
                    ? HeadroomBrandRamp.claudeCTABottom(dark: dark)
                    : HeadroomBrandRamp.codexCTABottom(dark: dark)
                #expect(contrastRatio(.white, bottom) >= 4.5, "\(name) CTA bottom, dark=\(dark)")
            }
        }
    }

    /// R2C18: "Connected" used to be a hand-written green sitting beside a chip fill derived
    /// from `healthy` — one chip, two greens. The ink is now the same token stepped in
    /// lightness only, and it still has to pass AA as text on that chip.
    @Test func connectedInkIsALightnessOffsetFromHealthyAndStillPassesOnItsChip() {
        for dark in [true, false] {
            let green = HeadroomOKLCH(HeadroomSeverityColorValues.healthy(dark: dark))
            let ink = HeadroomOKLCH(HeadroomBrandRamp.connectedInk(dark: dark))
            #expect(abs(ink.hue - green.hue) < 2, "dark=\(dark) hue")
            #expect(abs(ink.chroma - green.chroma) < 0.02, "dark=\(dark) chroma")
            #expect(
                abs(ink.lightness - green.lightness
                    - HeadroomBrandRamp.connectedInkLightnessOffset(dark: dark)) < 0.01,
                "dark=\(dark) lightness offset"
            )
            // Dark steps away from its dark surface by getting brighter, light by getting darker.
            #expect((ink.lightness > green.lightness) == dark, "dark=\(dark) offset direction")

            let chip = composite(
                HeadroomTint(color: HeadroomSeverityColorValues.healthy(dark: dark), opacity: 0.12),
                over: raisedTileFillColors(dark: dark)[0]
            )
            let measured = contrastRatio(HeadroomBrandRamp.connectedInk(dark: dark), chip)
            #expect(measured >= 4.5, "connected ink on its chip, dark=\(dark): \(measured):1")
        }
    }

    /// R2C13: the two monochrome marks are capped at ~86% ink so each lands between its own
    /// title and the numeral instead of level with the numeral. The artwork carries the value
    /// (the mark is drawn from an SVG fill, not tinted at the call site), so the token and
    /// the shipped files are checked against each other — in *both* copies, because the Mac
    /// popover reads `Sources/HeadroomApp/Resources` and iOS + the widgets read the asset
    /// catalog, and a fix applied to one of them would silently split the two platforms.
    @Test func monochromeBrandMarksShipAtTheCappedInkValue() throws {
        #expect(hex(HeadroomBrandColorValues.monochromeMarkInk(dark: true)) == "#C9CDD4")
        #expect(hex(HeadroomBrandColorValues.monochromeMarkInk(dark: false)) == "#3A3D42")
        #expect(HeadroomBrandColorValues.monochromeMarkInkHex(dark: true)
            == hex(HeadroomBrandColorValues.monochromeMarkInk(dark: true)))
        #expect(HeadroomBrandColorValues.monochromeMarkInkHex(dark: false)
            == hex(HeadroomBrandColorValues.monochromeMarkInk(dark: false)))

        // The dark mark is dimmer than the numeral it used to match; the light mark is
        // lighter than the near-black it used to be. Both move *toward* their surface.
        #expect(HeadroomOKLCH(HeadroomBrandColorValues.monochromeMarkInk(dark: true)).lightness
            < HeadroomOKLCH(HeadroomRGBColor(red: 0.92, green: 0.92, blue: 0.96)).lightness)
        #expect(HeadroomOKLCH(HeadroomBrandColorValues.monochromeMarkInk(dark: false)).lightness
            > HeadroomOKLCH(HeadroomRGBColor(red: 0x0D / 255, green: 0x0D / 255, blue: 0x0F / 255)).lightness)

        for (path, dark) in monochromeMarkFiles {
            let svg = try String(contentsOf: path, encoding: .utf8)
            let expected = "fill=\"\(HeadroomBrandColorValues.monochromeMarkInkHex(dark: dark))\""
            #expect(svg.contains(expected), "\(path.lastPathComponent) does not carry \(expected)")
        }
    }

    /// U6 (OpenCode plan): iOS and both widget families never call a light/dark lookup; they
    /// read one imageset name and rely on its `luminosity` dark appearance. Each monochrome
    /// imageset must therefore list the light file as its default and the dark file under the
    /// dark appearance, and carry the same bytes as the Mac bundle copy.
    @Test(arguments: [
        ("GrokBrandIcon", "grok"), ("CursorBrandIcon", "cursor"),
        ("CopilotBrandIcon", "copilot"), ("OpenCodeBrandIcon", "opencode"),
    ])
    func monochromeImagesetsPairTheirDarkFileUnderTheLuminosityAppearance(_ pair: (String, String)) throws {
        let imageset = brandCatalogDirectory.appendingPathComponent("\(pair.0).imageset")
        let contents = try Data(contentsOf: imageset.appendingPathComponent("Contents.json"))
        struct Catalog: Decodable {
            struct Appearance: Decodable { var appearance: String; var value: String }
            struct Entry: Decodable { var filename: String?; var appearances: [Appearance]? }
            struct Properties: Decodable { var preservesVector: Bool?
                enum CodingKeys: String, CodingKey { case preservesVector = "preserves-vector-representation" } }
            var images: [Entry]
            var properties: Properties?
        }
        let catalog = try JSONDecoder().decode(Catalog.self, from: contents)
        let plain = catalog.images.filter { ($0.appearances ?? []).isEmpty }
        let dark = catalog.images.filter {
            ($0.appearances ?? []).contains { $0.appearance == "luminosity" && $0.value == "dark" }
        }
        #expect(plain.map(\.filename) == ["\(pair.1)-light.svg"], "\(pair.0) default image")
        #expect(dark.map(\.filename) == ["\(pair.1)-dark.svg"], "\(pair.0) dark image")
        #expect(catalog.properties?.preservesVector == true, "\(pair.0) vector")

        for variant in ["light", "dark"] {
            let file = "\(pair.1)-\(variant).svg"
            let catalogCopy = try Data(contentsOf: imageset.appendingPathComponent(file))
            let bundleCopy = try Data(contentsOf: brandBundleDirectory.appendingPathComponent(file))
            #expect(catalogCopy == bundleCopy, "\(file) differs between the Mac bundle and the asset catalog")
        }
    }

    /// R2C15: at critical the *track* takes the critical hue at a fixed lightness, because
    /// the fill's ink area shrinks exactly as severity rises. It is a tint, not a second
    /// value step (it stays close to the neutral track's lightness against the card), and the
    /// pinned fill-vs-track separation must survive it.
    @Test func theCriticalTrackKeepsItsHueAndItsSeparationFromTheFill() {
        for dark in [true, false] {
            let track = HeadroomMeterColorValues.criticalBarTrack(dark: dark)
            let critical = HeadroomOKLCH(HeadroomSeverityColorValues.critical(dark: dark))
            #expect(abs(HeadroomOKLCH(track).hue - critical.hue) < 2, "dark=\(dark) hue")

            let fill = HeadroomSeverityColorValues.fill(
                for: UsageSeverity.critical,
                dark: dark,
                increasedContrast: false
            )
            let measured = contrastRatio(fill, track)
            // Same floors the neutral track is held to: ≥2.0:1 for the deliberately vivid
            // light default, ≥3.0:1 for dark.
            #expect(measured >= (dark ? 3.0 : 2.0), "critical fill vs tinted track, dark=\(dark): \(measured):1")

            for card in raisedTileFillColors(dark: dark) {
                let neutral = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: card)
                // Within a quarter of an APCA tier of the neutral track it replaces — the
                // change has to read as hue, not as a brighter or darker bar.
                let shift = abs(abs(apcaLc(text: track, background: card))
                    - abs(apcaLc(text: neutral, background: card)))
                #expect(shift < 12, "dark=\(dark) tinted track shifts |Lc| by \(shift)")
            }
        }
    }

    /// R2C16: a stale critical is still a critical. The fill keeps its severity's lightness
    /// and hue and drops to 35% chroma instead of collapsing to one flat grey, so a stale 21%
    /// row can no longer read as calmer than the live 38% row above it.
    @Test func staleFillsKeepTheirSeverityHueAtReducedChroma() {
        for dark in [true, false] {
            for increasedContrast in [true, false] {
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let live = HeadroomOKLCH(HeadroomSeverityColorValues.fill(
                        for: severity, dark: dark, increasedContrast: increasedContrast
                    ))
                    let stale = HeadroomOKLCH(HeadroomMeterColorValues.staleFill(
                        for: severity, dark: dark, increasedContrast: increasedContrast
                    ))
                    let label = "\(severity) dark=\(dark) ic=\(increasedContrast)"
                    #expect(abs(stale.hue - live.hue) < 2, "\(label) hue")
                    #expect(abs(stale.lightness - live.lightness) < 0.01, "\(label) lightness")
                    #expect(
                        abs(stale.chroma - live.chroma * HeadroomMeterColorValues.staleFillChromaScale) < 0.005,
                        "\(label) chroma"
                    )
                    // Hedged, not erased, and not still shouting.
                    #expect(stale.chroma > 0.02, "\(label) still carries hue")
                    #expect(stale.chroma < live.chroma, "\(label) is quieter than live")
                }
                // The severity order survives the hedge, which is the whole point.
                let chromas = [UsageSeverity.healthy, .low, .critical].map {
                    HeadroomOKLCH(HeadroomMeterColorValues.staleFill(
                        for: $0, dark: dark, increasedContrast: increasedContrast
                    )).chroma
                }
                #expect(chromas.allSatisfy { $0 > 0 })
            }
        }
    }

    @Test func newProviderTextAccentsMatchCanonicalSpec() {
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.grok.raw, dark: false) == HeadroomRGBColor(red: 0.20, green: 0.22, blue: 0.25))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.grok.raw, dark: true) == HeadroomRGBColor(red: 0.78, green: 0.80, blue: 0.84))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.cursor.raw, dark: false) == HeadroomRGBColor(red: 0.17, green: 0.17, blue: 0.18))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.cursor.raw, dark: true) == HeadroomRGBColor(red: 0.81, green: 0.81, blue: 0.83))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.copilot.raw, dark: false) == HeadroomRGBColor(red: 0.18, green: 0.20, blue: 0.24))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.copilot.raw, dark: true) == HeadroomRGBColor(red: 0.79, green: 0.81, blue: 0.86))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.opencode.raw, dark: false) == HeadroomRGBColor(red: 0.18, green: 0.17, blue: 0.17))
        #expect(HeadroomWidgetColorValues.textAccent(for: ProviderID.opencode.raw, dark: true) == HeadroomRGBColor(red: 0.82, green: 0.81, blue: 0.81))
    }

    /// U6 (OpenCode plan): the OpenCode title accent clears WCAG AA small text on both raised
    /// tile stops and every widget container stop, in each scheme.
    @Test func opencodeTextAccentClearsSmallTextContrastOnEverySurface() throws {
        for dark in [true, false] {
            let accent = try #require(HeadroomWidgetColorValues.textAccent(for: ProviderID.opencode.raw, dark: dark))
            for surface in raisedTileFillColors(dark: dark) + widgetContainerColors(dark: dark) {
                let measured = contrastRatio(accent, surface)
                #expect(measured >= 4.5, "opencode accent dark=\(dark): \(measured):1")
            }
        }
    }

    /// U6 (OpenCode plan): OpenCode's own palette is a warm neutral (its mark's inner block is
    /// `#5A5858`), so its accent stays warm of Cursor's cool neutral and the two read apart.
    @Test func opencodeAccentIsAWarmNeutralDistinctFromCursor() {
        let opencode = HeadroomBrandColorValues.opencode
        #expect(opencode.red >= opencode.blue)
        #expect(opencode != HeadroomBrandColorValues.cursor)
        #expect(HeadroomOKLCH(opencode).chroma < 0.02)
    }

    /// U6 (Copilot plan): the Copilot title accent clears WCAG AA small text on both raised
    /// tile stops and both widget container stops, in each scheme.
    @Test func copilotTextAccentClearsSmallTextContrastOnEverySurface() throws {
        for dark in [true, false] {
            let accent = try #require(HeadroomWidgetColorValues.textAccent(for: ProviderID.copilot.raw, dark: dark))
            for surface in raisedTileFillColors(dark: dark) + widgetContainerColors(dark: dark) {
                let measured = contrastRatio(accent, surface)
                #expect(measured >= 4.5, "copilot accent dark=\(dark): \(measured):1")
            }
        }
    }

    /// Guards the P1 "grey-identity default arm" class of bug: every registered provider
    /// must resolve a real title accent (both schemes), not fall through to `.secondary`.
    @Test func everyRegisteredProviderHasABrandTextAccent() {
        for id in [ProviderID.claude, .codex, .grok, .cursor, .copilot, .opencode] {
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
    /// the four-provider card list. The extremes therefore run *opposite* to coverage — the
    /// sparsest mark grows, the densest shrinks — and that direction is asserted here. The
    /// two in between were re-tuned (Sep 2026) by measured optical size, which also weighs
    /// the ink box: Cursor is dense but narrow, so it grows slightly.
    @Test func everyProviderRendersItsInkAtThirteenFifteenthsOfTheSlotTimesItsMassCorrection() {
        #expect(HeadroomBrandMark.inkFraction == 13.0 / 15.0)
        let corrections: [(ProviderID, Double)] = [
            (.claude, 1.00), (.codex, 0.92), (.grok, 1.20), (.cursor, 1.03), (.copilot, 1.00),
            (.opencode, 1.00),
        ]
        for (id, correction) in corrections {
            #expect(HeadroomBrandMark.massCorrection(for: id.raw) == correction, "\(id.raw) mass")
            #expect(
                abs(HeadroomBrandMark.inkScale(for: id.raw) - 13.0 / 15.0 * correction) < 1e-12,
                "\(id.raw) scale"
            )
        }
        // The sparsest mark grows and the densest shrinks; the two between were settled by
        // measured optical size, not coverage alone (Cursor's narrow box offsets its mass).
        #expect(HeadroomBrandMark.massCorrection(for: ProviderID.grok.raw) > 1)
        #expect(HeadroomBrandMark.massCorrection(for: ProviderID.codex.raw) < 1)
        // Grok is the sparsest mark, Codex the densest, so they bound the table.
        for id in [ProviderID.claude, .codex, .cursor, .copilot, .opencode] {
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
        for id in [ProviderID.claude, .codex, .grok, .cursor, .copilot, .opencode] {
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
        // OpenCode's block is a 4:5 portrait: full height, 0.8 of it wide.
        let opencode = HeadroomBrandMark.markSize(for: ProviderID.opencode.raw, slot: 15)
        #expect(abs(opencode.height - 13) < 0.0001)
        #expect(abs(opencode.width - 10.4) < 0.0001)
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
        // CA-P10: dark stepped 0.22/0.11 → 0.36/0.24 so the dark gauge reads like light's.
        #expect(HeadroomMeterColorValues.glassA(dark: true) == HeadroomTint(color: .white, opacity: 0.36))
        #expect(HeadroomMeterColorValues.glassB(dark: true) == HeadroomTint(color: .white, opacity: 0.24))
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
        // MX4: Full Machined's lit-from-above well.
        #expect(HeadroomMeterColorValues.wellTopShade(dark: true) == HeadroomTint(color: .black, opacity: 0.55))
        #expect(HeadroomMeterColorValues.wellTopShade(dark: false) == HeadroomTint(color: .black, opacity: 0.16))
        #expect(HeadroomMeterColorValues.wellBottomLip(dark: true) == HeadroomTint(color: .white, opacity: 0.06))
        #expect(HeadroomMeterColorValues.wellBottomLip(dark: false) == HeadroomTint(color: .white, opacity: 0.55))
        #expect(HeadroomMeterColorValues.wellHairline(dark: true) == HeadroomTint(color: .black, opacity: 0.35))
        #expect(HeadroomMeterColorValues.wellHairline(dark: false) == HeadroomTint(color: .black, opacity: 0.06))
        // MX3: Full's unlit cells step back from `tickOff`.
        #expect(HeadroomMeterColorValues.fullUnlitCellScale == 0.70)

        #expect(HeadroomMeterColorValues.tickOff(dark: true) == HeadroomTint(color: .white, opacity: 0.09))
        #expect(HeadroomMeterColorValues.tickOff(dark: false) == HeadroomTint(color: .black, opacity: 0.08))
        #expect(HeadroomMeterColorValues.tickGlass(dark: true) == HeadroomTint(color: .white, opacity: 0.26))
        #expect(HeadroomMeterColorValues.tickGlass(dark: false) == HeadroomTint(color: .black, opacity: 0.24))
        // R2C4b: dark's cap stepped 0.52 → 0.42 so the neutral tip stops out-shouting the
        // critical fill (ordering asserted in `theDarkSeverityRampIsMonotonicInLc`).
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: true) == HeadroomTint(color: .white, opacity: 0.42))
        #expect(HeadroomMeterColorValues.tickGlassCap(dark: false) == HeadroomTint(color: .black, opacity: 0.36))

        // R2C16: the stale fill is no longer a flat system grey — it keeps its severity's
        // lightness and hue at 35% chroma (see `staleFillsKeepTheirSeverityHue`).
        #expect(HeadroomMeterColorValues.staleFillChromaScale == 0.35)
        #expect(HeadroomMeterColorValues.quarterMarkOpacity(dark: true) == 0.11)
        #expect(HeadroomMeterColorValues.quarterMarkOpacity(dark: false) == 0.14)

        // FS1: the segmented body dim. It must be a genuine step back from the tip — never
        // 1 (no separation at all) and never 0 (the trail would vanish and the meter would
        // read as a single lit cell). FS2 retuned it 0.72 → 0.70 with the larger Full cell,
        // and kept it a single number shared by both formats on purpose.
        #expect(HeadroomMeterColorValues.segmentBodyAttenuation == 0.70)
        #expect(HeadroomMeterColorValues.segmentBodyAttenuation > 0)
        #expect(HeadroomMeterColorValues.segmentBodyAttenuation < 1)

        // R2C18: the flat-fill dims moved out of `MeterGauge` and in beside it. Same shape as
        // `segmentBodyAttenuation`: a genuine step back in dark, no dim in light, and
        // critical keeps more of itself than the quieter bands.
        #expect(HeadroomMeterColorValues.flatFillAttenuation(for: .critical, dark: true) == 0.95)
        #expect(HeadroomMeterColorValues.flatFillAttenuation(for: .low, dark: true) == 0.85)
        #expect(HeadroomMeterColorValues.flatFillAttenuation(for: .healthy, dark: true) == 0.85)
        for severity in [UsageSeverity.healthy, .low, .critical] {
            #expect(HeadroomMeterColorValues.flatFillAttenuation(for: severity, dark: false) == 1)
            #expect(HeadroomMeterColorValues.flatFillAttenuation(for: severity, dark: true) > 0)
            #expect(HeadroomMeterColorValues.flatFillAttenuation(for: severity, dark: true) < 1)
        }
        #expect(HeadroomMeterColorValues.flatFillAttenuation(for: .critical, dark: true)
            > HeadroomMeterColorValues.flatFillAttenuation(for: .healthy, dark: true))

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
        // Contrast. R2C4a darkened the light amber `oklch(0.700 …)` → `oklch(0.660 0.166
        // 58.3)` so the light ramp is monotonic; R2C4b lifted the *dark* critical fill off
        // its text token to `oklch(0.740 0.190 28.1)` for the same reason in dark.
        #expect(HeadroomSeverityColorValues.healthyFill(dark: false, increasedContrast: false) == HeadroomRGBColor(red: 0.16, green: 0.66, blue: 0.30))
        #expect(HeadroomSeverityColorValues.lowFill(dark: false, increasedContrast: false) == HeadroomRGBColor(red: 0.856, green: 0.450, blue: 0.000))
        #expect(HeadroomSeverityColorValues.criticalFill(dark: false, increasedContrast: false) == HeadroomRGBColor(red: 0.90, green: 0.22, blue: 0.20))
        #expect(HeadroomSeverityColorValues.criticalFill(dark: true, increasedContrast: false) == HeadroomRGBColor(red: 1.00, green: 0.448, blue: 0.389))

        // The light amber moved lightness only: same hue, same chroma, one step darker.
        let amber = HeadroomOKLCH(HeadroomSeverityColorValues.lowFill(dark: false, increasedContrast: false))
        #expect(abs(amber.lightness - 0.660) < 0.005)
        #expect(abs(amber.chroma - 0.166) < 0.006)
        #expect(abs(amber.hue - 58.3) < 2.5)

        for severity in [UsageSeverity.healthy, .low, .critical] {
            #expect(
                HeadroomSeverityColorValues.fill(for: severity, dark: false, increasedContrast: true)
                    == HeadroomSeverityColorValues.color(for: severity, dark: false),
                "light increased contrast falls back to the text tier: \(severity)"
            )
            for increasedContrast in [true, false] {
                // Critical is the one dark fill that is deliberately *not* its text token
                // (R2C4b); the other two still are, in both branches.
                let expected = severity == .critical
                    ? HeadroomRGBColor(red: 1.00, green: 0.448, blue: 0.389)
                    : HeadroomSeverityColorValues.color(for: severity, dark: true)
                #expect(
                    HeadroomSeverityColorValues.fill(for: severity, dark: true, increasedContrast: increasedContrast)
                        == expected,
                    "dark fill: \(severity)"
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

    /// MX2: the harshness Kyle saw was the dark Full Fade starting *below* the track it sits
    /// on — mixed toward black, the start was a hole in the bar. Full's start now stays at or
    /// above the dark track's lightness on both card fills, so the ramp only ever brightens.
    @Test func darkFullRampStartsNeverSinkBelowTheTrack() {
        for background in raisedTileFillColors(dark: true) {
            let track = HeadroomOKLCH(composite(HeadroomWidgetColorValues.barTrack(dark: true), over: background))
            for increasedContrast in [false, true] {
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let start = HeadroomOKLCH(MeterRecipe.fullRampStops(
                        severity: severity,
                        scheme: .dark,
                        increasedContrast: increasedContrast
                    ).start)
                    #expect(start.lightness > track.lightness, "\(severity) ic=\(increasedContrast)")
                    #expect(rgbChroma(start.rgb) >= 0.04, "\(severity) ic=\(increasedContrast) keeps its colour")
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
    ///
    /// R2C4 moved two of the four recorded numbers: the dark minimum 1.2295 → 1.3099 (the
    /// dark critical fill lifted) and the light minimum 1.2584 → 1.2846 (the light amber
    /// darkened). Both improve; the increased-contrast branch is untouched because it keeps
    /// the text-tier colours.
    @Test func ghostBodyContrastOnTrackIsRecorded() {
        #expect(measuredGhostRatios(dark: true, increasedContrast: false).min().map { abs($0 - 1.3099) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: true, increasedContrast: false).max().map { abs($0 - 1.3733) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: false).min().map { abs($0 - 1.2846) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: false).max().map { abs($0 - 1.5465) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: true).min().map { abs($0 - 1.3815) < 0.0001 } == true)
        #expect(measuredGhostRatios(dark: false, increasedContrast: true).max().map { abs($0 - 1.6345) < 0.0001 } == true)
    }

    /// Glass is recorded rather than promoted to a blanket pass. The light
    /// band moved 3.0986–4.0254 → 1.7514–2.4396 under PA1: the old light glass was an opaque
    /// mid-grey that measured *higher* against its own track than any severity fill did, which
    /// is precisely the inversion PA1 removes. Glass is decorative chrome — the percent numeral
    /// beside it carries the value at full text contrast — so the drop is the fix, not a
    /// regression.
    ///
    /// CA-P10 moved the dark band 1.3782–1.9544 → 1.9815–2.8978 with the raised dark stops.
    @Test func healthyGlassContrastOnTrackIsRecorded() {
        #expect(measuredGlassRatios(dark: true).min().map { abs($0 - 1.9815) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: true).max().map { abs($0 - 2.8978) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).min().map { abs($0 - 1.7514) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).max().map { abs($0 - 2.4396) < 0.0001 } == true)
    }

    // MARK: - CA-P1 / CA-P10: stale healthy recedes, the dark gauge reads

    /// CA-P1 (KTD5): under Only when low a live healthy meter is neutral, so a stale healthy
    /// one paints that neutral at half alpha. It has to sit between the track and the live
    /// fill in both schemes: dimmer than live, still a shape. Each stop is measured the way it
    /// renders, an alpha over the track over the card. The segmented live body is `tickGlass`
    /// at `segmentBodyAttenuation`; the stale cells are uniform.
    @Test func staleHealthyNeutralIsDimmerThanLiveAndStillVisibleOnTheTrack() {
        for dark in [true, false] {
            let body = HeadroomMeterColorValues.tickGlass(dark: dark)
            let liveSegmentBody = HeadroomTint(
                color: body.color,
                opacity: body.opacity * HeadroomMeterColorValues.segmentBodyAttenuation
            )
            let pairs: [(String, HeadroomTint, HeadroomTint)] = [
                ("glassA", HeadroomMeterColorValues.glassA(dark: dark), HeadroomMeterColorValues.staleGlassA(dark: dark)),
                ("glassB", HeadroomMeterColorValues.glassB(dark: dark), HeadroomMeterColorValues.staleGlassB(dark: dark)),
                ("tickGlass", liveSegmentBody, HeadroomMeterColorValues.staleTickGlass(dark: dark)),
            ]
            for card in raisedTileFillColors(dark: dark) {
                let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: card)
                for (name, live, stale) in pairs {
                    let liveRatio = contrastRatio(composite(live, over: track), track)
                    let staleRatio = contrastRatio(composite(stale, over: track), track)
                    #expect(staleRatio > 1.2, "\(name) stale \(staleRatio) vanishes into the track, dark=\(dark)")
                    #expect(staleRatio < liveRatio, "\(name) stale \(staleRatio) is not dimmer than live \(liveRatio), dark=\(dark)")
                    #expect(stale.color == live.color, "\(name) stale changed ink, dark=\(dark)")
                }
            }
        }
        #expect(HeadroomMeterColorValues.staleNeutralScale == 0.5)
    }

    /// CA-P10: at 32×5pt the gauge's job is a glance read of how full, and dark's neutral
    /// measured ≈1.5:1 against its track where light's measured ≈2.1:1. The gradient's middle
    /// is the bar's weight; dark has to clear 2:1 and read at least as clearly as light.
    @Test func darkNeutralGaugeReadsAsClearlyAsLight() {
        func midRatios(dark: Bool) -> [Double] {
            let a = HeadroomMeterColorValues.glassA(dark: dark)
            let b = HeadroomMeterColorValues.glassB(dark: dark)
            let middle = HeadroomTint(color: a.color, opacity: (a.opacity + b.opacity) / 2)
            return raisedTileFillColors(dark: dark).map { card in
                let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: card)
                return contrastRatio(composite(middle, over: track), track)
            }
        }
        let dark = midRatios(dark: true)
        let light = midRatios(dark: false)
        #expect(dark.allSatisfy { $0 >= 2.0 }, "dark neutral gauge \(dark)")
        #expect((dark.min() ?? 0) >= (light.min() ?? .infinity), "dark \(dark) reads weaker than light \(light)")
    }

    /// CA-P2 / CA-S1 (DESIGN rule 8): no dark tile edge brighter than white 0.15. The glass
    /// card's top rim was 0.20 (R2C1) and Settings inherited it; both are now their own values.
    @Test func noDarkTileEdgeExceedsTheRimCeiling() {
        let edges: [(String, Double)] = [
            ("glass ring", HeadroomTileEdgeValues.darkGlassRingOpacity),
            ("glass lip", HeadroomTileEdgeValues.darkGlassLipOpacity),
            ("opaque ring", HeadroomTileEdgeValues.darkOpaqueRingOpacity),
        ]
        for (name, opacity) in edges {
            #expect(opacity > 0, "\(name) is gone")
            #expect(!(opacity > HeadroomTileEdgeValues.darkRimCeiling), "\(name) \(opacity) is a bright rim")
        }
        #expect(HeadroomTileEdgeValues.darkRimCeiling == 0.15)
        // The lip only catches the top; the ring holds the edge all round, so it stays the quieter of the two.
        #expect(HeadroomTileEdgeValues.darkGlassRingOpacity < HeadroomTileEdgeValues.darkGlassLipOpacity)
        // CA-S1: Settings' flat recipe, exact values from the audit.
        #expect(HeadroomTileEdgeValues.darkOpaqueFillOpacity == 0.06)
        #expect(HeadroomTileEdgeValues.darkOpaqueRingOpacity == 0.09)
        #expect(HeadroomTileEdgeValues.lightOpaqueRingOpacity == 0.07)
        #expect(HeadroomTileEdgeValues.darkGlassRingOpacity == 0.07)
        #expect(HeadroomTileEdgeValues.darkGlassLipOpacity == 0.10)
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
    /// R2C4b retired half of the old exemption here. `glassB` stays exempt — it is the glass
    /// gradient's shaded foot, not the fill's weight. `tickGlassCap` no longer is: see
    /// `theDarkSeverityRampIsMonotonicInLc`.
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

    // MARK: - R2C4: the severity ramp is monotonic in |Lc|

    /// R2C4a. PA1 fixed the neutral-vs-severity ordering; the severity tokens were never
    /// measured against *each other*. In light they ran backwards — `lowFill` |Lc| 53.4/51.0
    /// sat below `healthyFill` 57.2/54.8, so "running low" was quieter than "you're fine" on
    /// the same row. A ramp that is not monotonic does not encode severity.
    @Test func theLightSeverityRampIsMonotonicInLc() {
        for card in raisedTileFillColors(dark: false) {
            let ordered = [UsageSeverity.healthy, .low, .critical].map { severity in
                abs(apcaLc(
                    text: HeadroomSeverityColorValues.fill(
                        for: severity,
                        dark: false,
                        increasedContrast: false
                    ),
                    background: card
                ))
            }
            #expect(ordered[1] > ordered[0], "low \(ordered[1]) must outweigh healthy \(ordered[0])")
            #expect(ordered[2] > ordered[1], "critical \(ordered[2]) must outweigh low \(ordered[1])")
        }
    }

    /// R2C4b, the assertion that replaces PA1's documented exemption ("the two end tokens are
    /// exempt and stay exempt … dark's 0.52 cap has always measured above the dark critical
    /// fill"). It always had — that *was* the bug: a fully healthy grey meter's tip
    /// out-shouted a critical red meter's. The whole dark ramp is pinned in order now.
    ///
    /// The honest limit, recorded rather than chased: |Lc| cannot put red above amber in dark
    /// without desaturating the red. That is fine — AP1 gives critical a second channel (the
    /// red numeral), which is why critical sits below healthy/low here by design.
    @Test func theDarkSeverityRampIsMonotonicInLc() {
        for card in raisedTileFillColors(dark: true) {
            let track = composite(HeadroomWidgetColorValues.barTrack(dark: true), over: card)
            func onCard(_ tint: HeadroomTint) -> Double {
                abs(apcaLc(text: composite(tint, over: track), background: card))
            }
            func fill(_ severity: UsageSeverity) -> Double {
                abs(apcaLc(
                    text: HeadroomSeverityColorValues.fill(
                        for: severity,
                        dark: true,
                        increasedContrast: false
                    ),
                    background: card
                ))
            }
            let ladder: [(String, Double)] = [
                ("body", onCard(HeadroomMeterColorValues.tickGlass(dark: true))),
                ("cap", onCard(HeadroomMeterColorValues.tickGlassCap(dark: true))),
                ("critical", fill(.critical)),
                ("healthy", fill(.healthy)),
                ("low", fill(.low)),
            ]
            for (lower, upper) in zip(ladder, ladder.dropFirst()) {
                #expect(
                    lower.1 < upper.1,
                    "\(lower.0) |Lc| \(lower.1) must sit below \(upper.0) |Lc| \(upper.1)"
                )
            }
            // The cap is still a genuine end marker against its own body.
            #expect(ladder[1].1 > ladder[0].1 + 8, "cap barely reads against its body")
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

    // MARK: - Widget craft (WCM1 / WCM3 / WCL4)

    @Test func theWidgetNeutralFillMatchesCanonicalSpec() {
        #expect(HeadroomWidgetColorValues.neutralFill(dark: true) == HeadroomTint(color: .white, opacity: 0.26))
        let light = HeadroomWidgetColorValues.neutralFill(dark: false)
        #expect(hex(light.color) == "#6B727B")
        #expect(light.opacity == 1)
    }

    /// WCM1: healthy paints neutral, so the neutral fill has to read as a *shape* on the track
    /// — a bar you can see the length of — while carrying none of the hue that makes a low or
    /// critical bar an event.
    @Test func theNeutralFillReadsAsAShapeWithoutReadingAsAnEvent() {
        for dark in [true, false] {
            for background in widgetContainerColors(dark: dark) {
                let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: background)
                let neutral = composite(HeadroomWidgetColorValues.neutralFill(dark: dark), over: track)

                let measured = contrastRatio(neutral, track)
                #expect(measured >= 1.5, "neutral fill vs track, dark=\(dark): \(measured):1")

                for severity in [UsageSeverity.low, .critical] {
                    let fill = HeadroomSeverityColorValues.fill(
                        for: severity,
                        dark: dark,
                        increasedContrast: false
                    )
                    #expect(
                        rgbChroma(neutral) < rgbChroma(fill),
                        "\(severity) dark=\(dark): neutral carries \(rgbChroma(neutral)) chroma"
                    )
                }
            }
        }
    }

    @Test func theStaleNeutralFillMatchesCanonicalSpec() {
        #expect(hex(HeadroomWidgetColorValues.staleNeutralFill(dark: true)) == "#55575C")
        #expect(hex(HeadroomWidgetColorValues.staleNeutralFill(dark: false)) == "#8D9299")
    }

    /// WCM3: the widget overload routes low and critical through the popover's chroma hedge
    /// and sends healthy — which has no chroma left to hedge under WCM1 — to the neutral
    /// stale tone instead.
    @Test func theWidgetStaleOverloadHedgesSeverityAndNeutralisesHealthy() {
        for dark in [true, false] {
            for increasedContrast in [true, false] {
                #expect(
                    HeadroomMeterColorValues.staleFill(
                        for: WidgetUsageSeverity.healthy,
                        dark: dark,
                        increasedContrast: increasedContrast
                    ) == HeadroomWidgetColorValues.staleNeutralFill(dark: dark),
                    "healthy dark=\(dark) ic=\(increasedContrast)"
                )
                for (widget, popover) in [
                    (WidgetUsageSeverity.low, UsageSeverity.low),
                    (WidgetUsageSeverity.critical, UsageSeverity.critical),
                ] {
                    #expect(
                        HeadroomMeterColorValues.staleFill(
                            for: widget, dark: dark, increasedContrast: increasedContrast
                        ) == HeadroomMeterColorValues.staleFill(
                            for: popover, dark: dark, increasedContrast: increasedContrast
                        ),
                        "\(widget) dark=\(dark) ic=\(increasedContrast)"
                    )
                }
            }
        }
    }

    /// The M3 bug this replaces: widgets painted a stale bar with `secondaryText`, a *text*
    /// token, which made the stale bar the loudest bar on the tile (measured 4.7:1 against the
    /// light track where a live healthy fill sits at 2.1:1). Every stale tone now sits below
    /// the token it replaced.
    @Test func everyStaleWidgetFillRecedesFromTheTextTokenItReplaced() {
        for dark in [true, false] {
            for background in widgetContainerColors(dark: dark) {
                let track = composite(HeadroomWidgetColorValues.barTrack(dark: dark), over: background)
                let retired = composite(HeadroomWidgetColorValues.secondaryText(dark: dark), over: track)
                let retiredSeparation = contrastRatio(retired, track)
                for severity in [WidgetUsageSeverity.healthy, .low, .critical] {
                    let stale = HeadroomMeterColorValues.staleFill(
                        for: severity,
                        dark: dark,
                        increasedContrast: false
                    )
                    let measured = contrastRatio(stale, track)
                    #expect(
                        measured < retiredSeparation,
                        "\(severity) dark=\(dark): stale \(measured):1 vs retired \(retiredSeparation):1"
                    )
                }
            }
        }
    }

    /// WCL4: the widget rule keeps the hairline *weight* (1 device pixel) and buys its
    /// visibility on a Home Screen tile in opacity instead, so it never reads as a border.
    @Test func theWidgetHairlineIsLiftedOffTheSharedHairline() {
        #expect(HeadroomWidgetColorValues.widgetHairline(dark: true) == HeadroomTint(color: .white, opacity: 0.14))
        #expect(HeadroomWidgetColorValues.widgetHairline(dark: false) == HeadroomTint(color: .black, opacity: 0.10))
        for dark in [true, false] {
            let lifted = HeadroomWidgetColorValues.widgetHairline(dark: dark)
            let shared = HeadroomWidgetColorValues.hairline(dark: dark)
            #expect(lifted.color == shared.color, "dark=\(dark)")
            #expect(lifted.opacity > shared.opacity, "dark=\(dark)")
            // Still a hairline, not a divider: never heavier than the bar track it sits beside.
            #expect(lifted.opacity <= HeadroomWidgetColorValues.barTrack(dark: dark).opacity, "dark=\(dark)")
        }
    }

    /// U8 (U9-A, G6): the phone's controls are neutral and still legible. The label on a
    /// filled button and the bare tint used by text buttons clear WCAG AA small text on every
    /// surface they sit on; a switch's on-state clears the 3:1 non-text floor against the
    /// list cell it is drawn in.
    @Test func phoneControlColoursAreNeutralAndClearTheirContrastFloors() {
        for dark in [true, false] {
            let fill = HeadroomControlColorValues.buttonFill(dark: dark)
            let label = HeadroomControlColorValues.buttonLabel(dark: dark)
            #expect(contrastRatio(label, fill) >= 4.5, "label on fill, dark=\(dark)")
            // Neutral: no hue to speak of, so nothing reads as system blue or a brand accent.
            #expect(rgbChroma(fill) < 0.05, "fill chroma, dark=\(dark)")
            #expect(rgbChroma(HeadroomControlColorValues.tint(dark: dark)) < 0.05, "tint chroma, dark=\(dark)")

            let tint = HeadroomControlColorValues.tint(dark: dark)
            let screens = widgetContainerColors(dark: dark) + raisedTileFillColors(dark: dark)
                + groupedListColors(dark: dark)
            for background in screens {
                #expect(contrastRatio(tint, background) >= 4.5, "tint on \(hex(background)), dark=\(dark)")
            }

            let switchOn = HeadroomControlColorValues.switchOn(dark: dark)
            for cell in groupedListColors(dark: dark) {
                let track = composite(switchOn, over: cell)
                #expect(contrastRatio(track, cell) >= 3, "switch on \(hex(cell)), dark=\(dark)")
            }
        }
    }
}

/// iOS grouped list surfaces the phone's Settings rows sit on: `systemGroupedBackground` and
/// `secondarySystemGroupedBackground` (#F2F2F7 / #FFFFFF light, #000000 / #1C1C1E dark).
private func groupedListColors(dark: Bool) -> [HeadroomRGBColor] {
    dark
        ? [.black, HeadroomRGBColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255)]
        : [HeadroomRGBColor(red: 242 / 255, green: 242 / 255, blue: 247 / 255), .white]
}

private func hex(_ color: HeadroomRGBColor) -> String {
    func channel(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", channel(color.red), channel(color.green), channel(color.blue))
}

private func distance(_ lhs: HeadroomRGBColor, _ rhs: HeadroomRGBColor) -> Double {
    max(abs(lhs.red - rhs.red), max(abs(lhs.green - rhs.green), abs(lhs.blue - rhs.blue)))
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // HeadroomCoreTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // repo root
private let brandBundleDirectory = repositoryRoot.appendingPathComponent("Sources/HeadroomApp/Resources/BrandIcons")
private let brandCatalogDirectory = repositoryRoot.appendingPathComponent("Sources/HeadroomSharedResources/BrandIcons.xcassets")

/// Both shipped copies of each monochrome mark:the SwiftPM resource bundle the Mac popover
/// reads, and the asset catalog iOS and the widget families read (whose `luminosity` dark
/// appearance pairing is what makes the light/dark pair adapt natively).
private let monochromeMarkFiles: [(URL, Bool)] = {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HeadroomCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
    let appIcons = root.appendingPathComponent("Sources/HeadroomApp/Resources/BrandIcons")
    let catalog = root.appendingPathComponent("Sources/HeadroomSharedResources/BrandIcons.xcassets")
    return [
        (appIcons.appendingPathComponent("grok-dark.svg"), true),
        (appIcons.appendingPathComponent("grok-light.svg"), false),
        (appIcons.appendingPathComponent("cursor-dark.svg"), true),
        (appIcons.appendingPathComponent("cursor-light.svg"), false),
        (catalog.appendingPathComponent("GrokBrandIcon.imageset/grok-dark.svg"), true),
        (catalog.appendingPathComponent("GrokBrandIcon.imageset/grok-light.svg"), false),
        (catalog.appendingPathComponent("CursorBrandIcon.imageset/cursor-dark.svg"), true),
        (catalog.appendingPathComponent("CursorBrandIcon.imageset/cursor-light.svg"), false),
        (appIcons.appendingPathComponent("copilot-dark.svg"), true),
        (appIcons.appendingPathComponent("copilot-light.svg"), false),
        (catalog.appendingPathComponent("CopilotBrandIcon.imageset/copilot-dark.svg"), true),
        (catalog.appendingPathComponent("CopilotBrandIcon.imageset/copilot-light.svg"), false),
        (appIcons.appendingPathComponent("opencode-dark.svg"), true),
        (appIcons.appendingPathComponent("opencode-light.svg"), false),
        (catalog.appendingPathComponent("OpenCodeBrandIcon.imageset/opencode-dark.svg"), true),
        (catalog.appendingPathComponent("OpenCodeBrandIcon.imageset/opencode-light.svg"), false),
    ]
}()

private func raisedTileFillColors(dark: Bool) -> [HeadroomRGBColor] {
    // Flattened endpoints of RaisedTile's current glass fill in the design reference.
    [
        HeadroomWidgetColorValues.tileFillTop(dark: dark),
        HeadroomWidgetColorValues.tileFillBottom(dark: dark),
    ]
}

/// The widget tile's own background stops. WCF6 keeps widget content flat — there is no inner
/// tile — so a widget bar and its track composite straight onto these.
private func widgetContainerColors(dark: Bool) -> [HeadroomRGBColor] {
    [
        HeadroomWidgetColorValues.containerBackgroundTop(dark: dark),
        HeadroomWidgetColorValues.containerBackgroundMiddle(dark: dark),
        HeadroomWidgetColorValues.containerBackgroundBottom(dark: dark),
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
