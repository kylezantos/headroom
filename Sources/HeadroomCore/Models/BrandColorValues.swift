import Foundation

/// SwiftUI-free RGB color values shared by the app and widget targets.
public struct HeadroomRGBColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = HeadroomRGBColor(red: 1, green: 1, blue: 1)
    public static let black = HeadroomRGBColor(red: 0, green: 0, blue: 0)
}

/// A base color plus an opacity, kept SwiftUI-free so both widget style layers can build
/// the same translucent tint (`Color(tint.color).opacity(tint.opacity)`) without the raw
/// numbers living in two places.
public struct HeadroomTint: Sendable, Equatable {
    public let color: HeadroomRGBColor
    public let opacity: Double

    public init(color: HeadroomRGBColor, opacity: Double) {
        self.color = color
        self.opacity = opacity
    }
}

/// R2C18 / R2C12 / R2C16: perceptual (OKLCH) coordinates for an sRGB color.
///
/// Three round-2 decisions all need the *same* operation — move a color's lightness or
/// chroma while its hue stays put — and sRGB arithmetic cannot do it: mixing a fill toward
/// white in sRGB swings the amber ramp ~8.5° warmer at its start, and hand-authored "same
/// family" literals had drifted the Claude token 9° off its own artwork. Keeping one
/// conversion here means the brand ramps (R2C18), the meter ramp (R2C12), and the stale
/// desaturation (R2C16) all traverse the same space rather than three approximations of it.
///
/// Out-of-gamut results are clamped per channel at the `rgb` boundary; every shipped token
/// is asserted to survive that clamp with < 2° of hue error.
public struct HeadroomOKLCH: Sendable, Equatable {
    public let lightness: Double
    public let chroma: Double
    /// Degrees, 0..<360.
    public let hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = max(0, chroma)
        self.hue = hue
    }

    public init(_ rgb: HeadroomRGBColor) {
        let (l, a, b) = Self.oklab(from: rgb)
        self.lightness = l
        self.chroma = (a * a + b * b).squareRoot()
        let degrees = atan2(b, a) * 180 / .pi
        self.hue = degrees < 0 ? degrees + 360 : degrees
    }

    /// The color with a new lightness, keeping hue and chroma.
    public func withLightness(_ lightness: Double) -> HeadroomOKLCH {
        HeadroomOKLCH(lightness: lightness, chroma: chroma, hue: hue)
    }

    /// The color with its chroma scaled, keeping lightness and hue (R2C16's stale hedge).
    public func scalingChroma(by factor: Double) -> HeadroomOKLCH {
        HeadroomOKLCH(lightness: lightness, chroma: chroma * factor, hue: hue)
    }

    /// Interpolates lightness and chroma toward `other` while holding *this* color's hue.
    /// Both call sites (the meter ramp, the brand ramps) are constant-hue by construction, so
    /// carrying `self.hue` through is what keeps a mix toward white or black from bending the
    /// family sideways — and it is why the ramp's hue-drift assertion can hold at 0°.
    public func interpolated(to other: HeadroomOKLCH, progress: Double) -> HeadroomOKLCH {
        let t = min(1, max(0, progress))
        return HeadroomOKLCH(
            lightness: lightness + (other.lightness - lightness) * t,
            chroma: chroma + (other.chroma - chroma) * t,
            hue: hue
        )
    }

    public var rgb: HeadroomRGBColor {
        let a = chroma * cos(hue * .pi / 180)
        let b = chroma * sin(hue * .pi / 180)
        return Self.srgb(fromOklabL: lightness, a: a, b: b)
    }

    // MARK: - Conversion (Björn Ottosson's Oklab, sRGB transfer function)

    private static func oklab(from rgb: HeadroomRGBColor) -> (Double, Double, Double) {
        let r = linearized(rgb.red), g = linearized(rgb.green), b = linearized(rgb.blue)
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return (
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    private static func srgb(fromOklabL lightness: Double, a: Double, b: Double) -> HeadroomRGBColor {
        let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return HeadroomRGBColor(
            red: encoded(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: encoded(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: encoded(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ component: Double) -> Double {
        let value = component <= 0.0031308
            ? component * 12.92
            : 1.055 * pow(max(component, 0), 1 / 2.4) - 0.055
        return min(1, max(0, value))
    }
}

public enum HeadroomBrandColorValues {
    /// R2C18: the artwork's own hues. `claude-color.svg` fills `#D97757` = `oklch(0.672
    /// 0.131 38.8)`; the token used to be a hand-authored `#D97842` at H 47.8°, so the mark
    /// and its accent were 9° apart in the same card. Every Claude/Codex brand value below
    /// and in `HeadroomBrandRamp` is now one constant-hue ramp off these two numbers.
    public static let claudeHue: Double = 38.8
    public static let codexHue: Double = 271.5

    public static let claude = HeadroomOKLCH(lightness: 0.672, chroma: 0.131, hue: claudeHue).rgb
    public static let codex = HeadroomOKLCH(lightness: 0.555, chroma: 0.246, hue: codexHue).rgb
    // Grok and Cursor are monochrome brands (their marks ship as light/dark pairs); these
    // mid-tone accents exist for the SF Symbol fallback + single-color tints and read on
    // both schemes. First-pass identity values — Phase 2 owns visual density.
    public static let grok = HeadroomRGBColor(red: 0.36, green: 0.40, blue: 0.46)
    public static let cursor = HeadroomRGBColor(red: 0.33, green: 0.34, blue: 0.38)

    /// R2C13: the value ceiling for the two monochrome marks. Their artwork shipped at the
    /// numeral's own value (`#F5F5F7` dark / `#0D0D0F` light), which put Cursor's solid cube
    /// and Grok's slash *above* the account title they sit beside and level with the primary
    /// figure — the card's hierarchy inverted on four rows at once. ~86% ink lands each mark
    /// between its title and its numeral in both schemes. This is a *value* fix;
    /// `HeadroomBrandMark.massCorrection` (geometry) is deliberately untouched.
    ///
    /// The SVGs carry these as literal fills (both the app bundle copy and the
    /// `BrandIcons.xcassets` copy the iOS app and widgets read); `BrandColorValuesTests`
    /// re-reads the artwork so the token and the shipped files cannot drift.
    public static func monochromeMarkInk(dark: Bool) -> HeadroomRGBColor {
        dark
            ? HeadroomRGBColor(red: 0xC9 / 255, green: 0xCD / 255, blue: 0xD4 / 255)
            : HeadroomRGBColor(red: 0x3A / 255, green: 0x3D / 255, blue: 0x42 / 255)
    }

    public static func monochromeMarkInkHex(dark: Bool) -> String {
        dark ? "#C9CDD4" : "#3A3D42"
    }
}

/// R2C18: the two brand families as constant-hue OKLCH ramps.
///
/// Before this, `textAccent` lived here while both CTA gradients, the "Connected" ink and a
/// byte-copy of the shared light neutral lived as raw `Color(red:green:blue:)` literals
/// inside the two setup views — eight Claude oranges and four Codex blues, no two of which
/// agreed on a hue. Each stop below is `(lightness, chroma)` at its family's hue, so a tweak
/// moves along the ramp instead of off it. The setup views keep their own `…SetupStyle`
/// enums as the *call* surface (the two provider flows stay decoupled); only the numbers
/// moved here.
///
/// White-on-CTA-top clears WCAG AA (≥4.5:1) in both schemes — the dark tops dropped
/// (Claude L 0.605 → 0.560, Codex 0.611 → 0.565) because they measured 4.05 / 3.97:1 while
/// the old comment claimed the ramp "averages ≈4.5:1". `BrandColorValuesTests` asserts it.
public enum HeadroomBrandRamp {
    private static func claude(_ lightness: Double, _ chroma: Double) -> HeadroomRGBColor {
        HeadroomOKLCH(lightness: lightness, chroma: chroma, hue: HeadroomBrandColorValues.claudeHue).rgb
    }

    private static func codex(_ lightness: Double, _ chroma: Double) -> HeadroomRGBColor {
        HeadroomOKLCH(lightness: lightness, chroma: chroma, hue: HeadroomBrandColorValues.codexHue).rgb
    }

    /// Provider display-name accent. Light Claude sits at 4.17:1 on the widget's light
    /// container top at its smallest usage (12pt semibold), so it takes a darker step to
    /// clear WCAG AA small-text on every light surface it appears on.
    public static func claudeTextAccent(dark: Bool) -> HeadroomRGBColor {
        dark ? claude(0.734, 0.121) : claude(0.556, 0.139)
    }

    public static func codexTextAccent(dark: Bool) -> HeadroomRGBColor {
        dark ? codex(0.739, 0.136) : codex(0.471, 0.225)
    }

    public static func claudeCTATop(dark: Bool) -> HeadroomRGBColor {
        dark ? claude(0.560, 0.129) : claude(0.575, 0.143)
    }

    public static func claudeCTABottom(dark: Bool) -> HeadroomRGBColor {
        dark ? claude(0.515, 0.130) : claude(0.530, 0.135)
    }

    public static func codexCTATop(dark: Bool) -> HeadroomRGBColor {
        dark ? codex(0.565, 0.189) : codex(0.540, 0.210)
    }

    public static func codexCTABottom(dark: Bool) -> HeadroomRGBColor {
        dark ? codex(0.472, 0.187) : codex(0.447, 0.203)
    }

    /// R2C18: the "Connected" chip's ink, now a documented lightness offset from the healthy
    /// severity token rather than a hand-written green beside a chip fill *derived* from that
    /// token — one chip, two greens. The offset is what the hand-written pair already
    /// measured (dark +0.058 Lc, light −0.054), i.e. "step away from the surface so the label
    /// passes AA on its own tint"; hue and chroma come from `healthy` so the family cannot
    /// drift again.
    public static func connectedInkLightnessOffset(dark: Bool) -> Double {
        dark ? 0.058 : -0.054
    }

    public static func connectedInk(dark: Bool) -> HeadroomRGBColor {
        let green = HeadroomOKLCH(HeadroomSeverityColorValues.healthy(dark: dark))
        return green.withLightness(green.lightness + connectedInkLightnessOffset(dark: dark)).rgb
    }
}

/// R2: one source of truth for the widget "usage" look — provider text accents and the
/// muted text / bar-track / hairline tints. Both the macOS (`WidgetProviderStyle`) and iOS
/// (`IOSWidgetStyle`) style layers wrap these values so the two widget families cannot
/// visually drift. The SwiftUI `Color` construction stays at each platform's style edge;
/// only the raw numbers live here (already compiled into both widget targets).
public enum HeadroomWidgetColorValues {
    /// Provider display-name accent, tuned warmer/cooler than the raw brand fill per scheme.
    /// Returns `nil` for unknown providers so the caller can fall back to `.secondary`.
    public static func textAccent(for providerID: String, dark: Bool) -> HeadroomRGBColor? {
        switch (providerID, dark) {
        // R2C18: Claude's and Codex's steps are now stops on their family's constant-hue
        // OKLCH ramp (`HeadroomBrandRamp`) rather than free literals — same lightnesses the
        // WCAG tuning landed on, re-authored at the artwork's real hue.
        case (ProviderID.claude.raw, _): HeadroomBrandRamp.claudeTextAccent(dark: dark)
        case (ProviderID.codex.raw, _): HeadroomBrandRamp.codexTextAccent(dark: dark)
        // Grok/Cursor are monochrome brands: their title accent is a legible near-primary
        // neutral (grok cooler, cursor pure) that clears WCAG AA small-text on the light
        // container (dark step) and the dark tile (light step).
        case (ProviderID.grok.raw, false): HeadroomRGBColor(red: 0.20, green: 0.22, blue: 0.25)
        case (ProviderID.grok.raw, true): HeadroomRGBColor(red: 0.78, green: 0.80, blue: 0.84)
        case (ProviderID.cursor.raw, false): HeadroomRGBColor(red: 0.17, green: 0.17, blue: 0.18)
        case (ProviderID.cursor.raw, true): HeadroomRGBColor(red: 0.81, green: 0.81, blue: 0.83)
        default: nil
        }
    }

    private static let darkNeutral = HeadroomRGBColor(red: 0.92, green: 0.92, blue: 0.96)
    private static let lightNeutral = HeadroomRGBColor(red: 0.24, green: 0.24, blue: 0.26)

    // Light opacities are set by WCAG AA small-text (≥4.5:1) on the lightest surfaces each
    // role sits on: tertiary needs 0.74 to clear the white tile fill (4.96) and the light
    // container bottom where the widget footer lives (4.56); secondary steps to 0.84 so the
    // two-level gray hierarchy survives the tertiary bump (6.63 on white, 5.44 on the plan
    // capsule's bar-track).
    //
    // PA13 (Sep 2026): the dark steps were originally matched to light on WCAG *ratio*, which
    // is polarity-blind — the same ratio buys far less separation on a dark surface. Re-derived
    // on APCA |Lc| against the RaisedTile card fills, tertiary moves 0.56 → 0.68 (|Lc| 41.8 →
    // 54.3 vs light's 74.4) and secondary follows it to 0.76 (|Lc| 52.2 → 63.4 vs light's 82.8)
    // for exactly the reason the light branch already documents: the two-level grey hierarchy
    // has to survive the tertiary bump, and at the old 0.66 secondary would have landed *below*
    // the new tertiary.
    public static func secondaryText(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.76) : HeadroomTint(color: lightNeutral, opacity: 0.84)
    }

    public static func tertiaryText(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.68) : HeadroomTint(color: lightNeutral, opacity: 0.74)
    }

    /// R2C18: the setup flow's quiet-chip label ink. Its light step was a byte-for-byte copy
    /// of `lightNeutral` written out again in `ClaudeSetupViews`, and its dark step was a
    /// bare `Color(white: 0.85)` with no relationship to anything. Both now read the shared
    /// neutral bases; dark's slightly recessed step survives as an opacity on `darkNeutral`
    /// (which composites to ≈0.86 white on the setup card) rather than as a second grey.
    public static func setupChipInk(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.92) : HeadroomTint(color: lightNeutral, opacity: 1)
    }

    /// PA13: the plan pill's own ink. It used to take the system `.tertiary`, which measured
    /// |Lc| ≈ 20 on the dark card — below APCA's placeholder floor — against ≈ 40 in light, and
    /// the plan name is the only thing that says which subscription a meter is measuring. This
    /// token lands both schemes at |Lc| ≈ 46–50 *on the identity capsule* (which is itself only
    /// white @ 0.06 / black @ 0.045 over the card), so the pill reads the same in either
    /// appearance instead of dissolving in one of them.
    public static func planLabel(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: darkNeutral, opacity: 0.60) : HeadroomTint(color: lightNeutral, opacity: 0.52)
    }

    // G1A (Sep 2026): the account title's ink — a cool grey that sits *below* the countdown
    // in the hierarchy on purpose (the numeral carries the value, the title only names the
    // account). Light #5F6771 measures |Lc| ≈ 78 on the card.
    //
    // PA13: the dark step was #7B838D, derived by mirroring the light step across the card on
    // WCAG ratio. Ratio is polarity-blind, and that mirror actually measured |Lc| ≈ 33 — less
    // than half of light's separation, on the one label that names the account a meter belongs
    // to. Re-derived on APCA against the same card fills, #9AA2AC measures |Lc| ≈ 48–50: still
    // deliberately under the 15pt title's full-primary ink, but no longer recessive in dark
    // only.
    public static func accountTitle(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: HeadroomRGBColor(red: 154 / 255, green: 162 / 255, blue: 172 / 255), opacity: 1)
            : HeadroomTint(color: HeadroomRGBColor(red: 95 / 255, green: 103 / 255, blue: 113 / 255), opacity: 1)
    }

    public static func barTrack(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.14) : HeadroomTint(color: .black, opacity: 0.12)
    }

    public static func hairline(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.10) : HeadroomTint(color: .black, opacity: 0.07)
    }

    /// R2C18: the recessed well every "content sits in here" surface uses — the setup flow's
    /// command wells and the Settings preview wells. Both already drew the same two numbers;
    /// the Settings panes just reached them through `ClaudeSetupStyle.wellBackground`, which
    /// made a Claude-branded token the source of truth for a pane with no Claude in it. The
    /// value is unchanged, so nothing moves visually — only where it is read from.
    public static func recessedWell(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0.32 : 0.05)
    }

    public static func containerBackgroundTop(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.082, green: 0.090, blue: 0.114) : HeadroomRGBColor(red: 0.965, green: 0.969, blue: 0.976)
    }

    public static func containerBackgroundMiddle(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.061, green: 0.070, blue: 0.091) : HeadroomRGBColor(red: 0.945, green: 0.951, blue: 0.963)
    }

    public static func containerBackgroundBottom(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.043, green: 0.051, blue: 0.067) : HeadroomRGBColor(red: 0.925, green: 0.933, blue: 0.949)
    }

    public static func containerBackgroundGlow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: HeadroomRGBColor(red: 0.431, green: 0.475, blue: 1.0), opacity: dark ? 0.10 : 0.08)
    }

    public static func tileFillTop(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.145, green: 0.152, blue: 0.176) : .white
    }

    public static func tileFillBottom(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.098, green: 0.106, blue: 0.129) : HeadroomRGBColor(red: 0.984, green: 0.984, blue: 0.988)
    }

    public static func tileRing(dark: Bool) -> HeadroomTint {
        dark ? HeadroomTint(color: .white, opacity: 0.065) : HeadroomTint(color: .black, opacity: 0.05)
    }

    public static func tileTopRim(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .white, opacity: dark ? 0.07 : 0)
    }

    public static func tileCloseShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0.28 : 0.06)
    }

    public static func tileAmbientShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0.40 : 0.05)
    }

    public static func tileLongShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0 : 0.05)
    }
}

/// The ramp's dark-scheme start is mixed against different meter surfaces. Light mode
/// uses the same white mix on both because both reference surfaces are light neutrals.
public enum MeterRampSurface: Sendable {
    case flat
    case well
}

/// App-local color tokens for the macOS popover meter. These stay separate from
/// `HeadroomWidgetColorValues` so meter experiments cannot change the widgets by accident.
public enum HeadroomMeterColorValues {
    private static let darkText = HeadroomRGBColor(red: 0.92, green: 0.92, blue: 0.96)
    private static let lightLabel = HeadroomRGBColor(
        red: 29.0 / 255.0,
        green: 31.0 / 255.0,
        blue: 36.0 / 255.0
    )
    private static let lightMetadata = HeadroomRGBColor(red: 0.24, green: 0.24, blue: 0.26)

    public static func labelInk(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: dark ? darkText : lightLabel, opacity: 0.90)
    }

    public static func countdownInk(dark: Bool) -> HeadroomTint {
        // The round-4 D2 values clear 4.5:1 against both RaisedTile fill endpoints.
        //
        // PA13: dark stepped 0.53 → 0.66. The pair was matched on WCAG ratio, which is
        // polarity-blind — at 0.53 the dark countdown measured |Lc| ≈ 39 against light's ≈ 71,
        // so the reset time was noticeably fainter in one appearance than the other. 0.66
        // lands at |Lc| ≈ 52 and still clears 4.5:1 (6.33–6.95) on both card fills.
        HeadroomTint(color: dark ? darkText : lightMetadata, opacity: dark ? 0.66 : 0.72)
    }

    // PA1: the neutral (no-event) meter greys.
    //
    // Light used to be *opaque* mid-greys (#757C86 / #666C75, #6B727B / #474E57) while dark was
    // white-alpha over the card. Alpha over an opaque literal is not a cosmetic difference: on
    // the shipping default (micro · chip · color-as-event) the light neutral body measured APCA
    // |Lc| ≈ 72 on the card while the amber "running low" fill measured ≈ 52, so a healthy 72%
    // bar visibly outweighed the low 38% bar above it and "color as event" inverted its own
    // meaning. Light now mirrors dark's construction — black-alpha over the card — which puts
    // the neutral body below every severity fill in both schemes.
    //
    // Body ≈ black @ 0.24, end stop ≈ black @ 0.36; the amber is untouched. These are the
    // starting values from the decision, tuned from live `--demo multi-4` captures.
    // `BrandColorValuesTests` pins the ordering, not the literals.
    public static func glassA(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: dark ? .white : .black, opacity: dark ? 0.22 : 0.24)
    }

    public static func glassB(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: dark ? .white : .black, opacity: dark ? 0.11 : 0.36)
    }

    public static func glassRim(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .white, opacity: dark ? 0.25 : 0.30)
    }

    public static func wellBackground(dark: Bool) -> HeadroomRGBColor {
        dark
            ? HeadroomRGBColor(
                red: 15.0 / 255.0,
                green: 17.0 / 255.0,
                blue: 20.0 / 255.0
            )
            : HeadroomRGBColor(
                red: 223.0 / 255.0,
                green: 226.0 / 255.0,
                blue: 231.0 / 255.0
            )
    }

    public static func wellShadow(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: .black, opacity: dark ? 0.65 : 0.20)
    }

    public static func tickOff(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.09)
            : HeadroomTint(color: .black, opacity: 0.08)
    }

    /// PA1: the segmented neutral body — same mirror as `glassA`.
    public static func tickGlass(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: dark ? .white : .black, opacity: dark ? 0.26 : 0.24)
    }

    /// PA1: the segmented neutral *tip*. Deliberately heavier than the body in both schemes —
    /// it is a one-cell end marker, not the fill's weight.
    ///
    /// R2C4b: dark stepped 0.52 → 0.42. PA1's exemption said the cap "is exempt and stays
    /// exempt"; measured, dark's 0.52 cap read |Lc| ≈ 50 against a 41–43 critical fill, so a
    /// fully healthy grey meter's tip out-shouted a critical red meter's. The exemption was
    /// the ordering bug, not a licence for it. At 0.42 the cap still clears its own body
    /// (|Lc| ≈ 40 vs 25–27) and now sits under critical, and the whole dark ramp is monotonic:
    /// body < cap < critical < healthy < low. Light's 0.36 already ordered correctly.
    public static func tickGlassCap(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: dark ? .white : .black, opacity: dark ? 0.42 : 0.36)
    }

    /// R2C15: the bar track at `.critical` only.
    ///
    /// Severity's ink area shrinks exactly as severity rises — at 9% left the alarm colour
    /// owns ~5pt of a bar while a comfortable 74% paints a wide neutral one. The track is the
    /// surface that does not shrink, so at critical it carries the hue the fill no longer can,
    /// at constant OKLCH lightness (`oklch(0.905 0.045 28.1)` light / `oklch(0.391 0.055
    /// 28.1)` dark, the critical hue) so it reads as a tint rather than a second value step.
    /// The pinned fill-vs-track separation barely moves (light 3.22 → 3.14:1, dark 3.58 →
    /// 3.67:1) and `BrandColorValuesTests` asserts both. Fires at critical only; the machined
    /// well keeps its own recessed background.
    public static func criticalBarTrack(dark: Bool) -> HeadroomRGBColor {
        HeadroomOKLCH(
            lightness: dark ? 0.391 : 0.905,
            chroma: dark ? 0.055 : 0.045,
            hue: criticalHue
        ).rgb
    }

    /// The critical family's OKLCH hue, measured from `HeadroomSeverityColorValues.critical`.
    private static let criticalHue: Double = 28.1

    /// How much of the severity *fill* survives in the Hue ramp's start stop (the rest is
    /// mixed toward white in light, black in dark).
    ///
    /// Light retuned 0.55 → 0.75 alongside the vivid fill tier: the default light fills are
    /// lighter than the text-tier values the 0.55 mix was set against, so a 45% white mix
    /// washed the start into the track (amber 1.27:1, was 1.55:1). At 0.75 every light start
    /// matches or beats its previous separation (1.59 / 1.69 / 2.27:1). Under Increase
    /// Contrast the fills revert to the text tier, so the mix reverts with them and the ramp
    /// renders exactly as it does today.
    public static func rampStartSeverityMix(
        dark: Bool,
        surface: MeterRampSurface,
        increasedContrast: Bool = false
    ) -> Double {
        guard dark else { return increasedContrast ? 0.55 : 0.75 }
        return surface == .flat ? 0.58 : 0.42
    }

    /// R2C16: how much chroma a `.stale` fill keeps.
    ///
    /// Stale used to replace the whole fill with the system secondary label at 0.55, so a
    /// stale **21%** row rendered flat grey directly beneath a live **38%** amber bar and the
    /// eye ranked the healthier number as the more urgent one. A stale critical is still a
    /// critical: desaturate to de-emphasise, don't neutralise to erase. The fill keeps its
    /// severity lightness and hue and drops to 35% of its chroma — the dim the numeral takes
    /// is unchanged, and `.unavailable` (which paints no fill at all) is untouched.
    public static let staleFillChromaScale: Double = 0.35

    /// The fill a `.stale` meter paints for `severity`. See `staleFillChromaScale`.
    public static func staleFill(
        for severity: UsageSeverity,
        dark: Bool,
        increasedContrast: Bool
    ) -> HeadroomRGBColor {
        let live = HeadroomSeverityColorValues.fill(
            for: severity,
            dark: dark,
            increasedContrast: increasedContrast
        )
        return HeadroomOKLCH(live).scalingChroma(by: staleFillChromaScale).rgb
    }

    /// FS1 (Kyle, Sep 2026): how strongly a segmented *body* cell paints its fill colour.
    /// Every lit cell used to sit at full strength, so the tip — the cell that carries the
    /// reading — had nothing to stand out against. Body cells drop to this fraction of their
    /// own colour so the tip reads as the value and the trail reads as context. `.staleGrey`
    /// is exempt (it is already a dim), and `.off` cells never see it.
    ///
    /// FS2 (Kyle, Sep 2026): retuned 0.72 → 0.70 alongside the larger Full cell. Deliberately
    /// one number shared by both formats — Full is the Micro cell scaled up, so the trail
    /// should sit the same distance behind its tip at either size rather than reading as two
    /// different meters.
    public static let segmentBodyAttenuation: Double = 0.70

    /// R2C18: the dim a *flat* (non-tip) severity fill takes in dark — the continuous Solid
    /// bar and the segmented body's severity cell. These two numbers were untokenised inline
    /// literals in `MeterGauge.flatSeverityColor`; they belong beside
    /// `segmentBodyAttenuation`, which is the same idea one layer up. Critical keeps more of
    /// itself (0.95) than the other bands (0.85) because it is the one fill the card is
    /// trying to draw attention to. Light takes no dim.
    public static func flatFillAttenuation(for severity: UsageSeverity, dark: Bool) -> Double {
        guard dark else { return 1 }
        return severity == .critical ? 0.95 : 0.85
    }

    /// PB13: the quarter-mark hairline. The base is the system primary label at the SwiftUI
    /// edge, the per-scheme number lives here.
    public static func quarterMarkOpacity(dark: Bool) -> Double {
        dark ? 0.11 : 0.14
    }

    /// Opacity applied to the severity *fill* token for the Ghost body. Left at the round-6
    /// values through the fill split: the vivid light fills lower the recorded body-vs-track
    /// separation slightly (1.38–1.63 → 1.26–1.55), and Ghost is deliberately subtle, so this
    /// stays a characterized measurement rather than a chased number. `BrandColorValuesTests`
    /// records both branches.
    public static func ghostBodyOpacity(for severity: UsageSeverity, dark: Bool) -> Double {
        switch (dark, severity) {
        case (true, .critical): 0.22
        case (true, _): 0.18
        case (false, .critical): 0.34
        case (false, _): 0.30
        }
    }
}

/// The rendered size of one brand mark's *ink*, in points.
public struct HeadroomBrandMarkSize: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Layout metrics for the bare (no-container) brand marks, shared by every surface — the
/// iOS app + widget, and the Mac popover + widget — so they stay visually identical.
///
/// OA2 (Sep 2026) replaced a by-eye per-provider `opticalScale` with a measured rule. The
/// brand SVGs are now trimmed so the path's tight bounding box *is* the viewBox, which
/// makes "how big is this mark" a property of the artwork rather than of each surface's
/// guess about it. Every surface then applies the same rule below and leading-aligns the
/// result inside its slot, so all four marks hang on one mark axis. PA9 then layered a
/// per-provider ink-mass correction on top of that shared box, because equal boxes of very
/// unequal coverage do not read as one size.
public enum HeadroomBrandMark {
    /// The ink's larger dimension as a fraction of the slot *before* mass correction: 13pt of
    /// ink in the card's 15pt mark slot. That is what the accepted Claude/Codex rendering
    /// already measured at, so it is the rule the other two marks are brought onto rather
    /// than a new look.
    public static let inkFraction: Double = 13.0 / 15.0

    /// Per-provider shape-mass tuning, applied on top of `inkFraction`.
    ///
    /// This is the dial the rule's own comment predicted: equal ink *boxes* are not equal ink
    /// *mass*. Measured coverage inside the same 13pt box — Codex 0.71, Cursor 0.56, Claude
    /// 0.42, Grok 0.25 — put Grok's hairline slash directly under Cursor's solid cube in the
    /// four-provider card list, so equal geometry read as four different sizes.
    ///
    /// PA9 (Sep 2026): first correction pass, weighting each mark against its coverage —
    /// the sparse marks grow, the dense ones shrink. These are starting values; live
    /// `--demo multi-4` captures in both appearances are what settles them.
    public static func massCorrection(for providerID: String) -> Double {
        switch providerID {
        case ProviderID.claude.raw: 1.05
        case ProviderID.codex.raw: 0.92
        case ProviderID.grok.raw: 1.10
        case ProviderID.cursor.raw: 0.94
        default: 1.0
        }
    }

    /// The fraction of the slot the mark's ink should occupy along its larger dimension.
    public static func inkScale(for providerID: String) -> Double {
        inkFraction * massCorrection(for: providerID)
    }

    /// The trimmed ink box's aspect (width ÷ height), measured from the brand SVG viewBoxes
    /// after OA2 trimmed them to their ink. Kept here rather than read from the artwork so
    /// the asset-catalog surfaces (iOS, both widget families), which only ever see an
    /// `Image(name)`, size their marks by exactly the same numbers the Mac popover does.
    /// `BrandMarkInkTests` re-measures the SVGs and fails if a mark is re-cut without this
    /// table following it.
    public static func inkAspect(for providerID: String) -> Double {
        switch providerID {
        case ProviderID.claude.raw: 1.0
        case ProviderID.codex.raw: 1.0
        // Grok's slash is wider than it is tall; Cursor's cube is taller than it is wide.
        // Neither is padded back to square — the slot's leftover goes on the trailing side.
        case ProviderID.grok.raw: 24.0 / 23.0332
        case ProviderID.cursor.raw: 21.0586 / 24.0
        default: 1.0
        }
    }

    /// The mark's rendered ink size inside a square `slot`: the larger dimension is
    /// `inkScale × slot`, the other follows from `inkAspect`, and the aspect is preserved.
    public static func markSize(for providerID: String, slot: Double) -> HeadroomBrandMarkSize {
        let ink = slot * inkScale(for: providerID)
        let aspect = inkAspect(for: providerID)
        guard aspect.isFinite, aspect > 0 else {
            return HeadroomBrandMarkSize(width: ink, height: ink)
        }
        return aspect >= 1
            ? HeadroomBrandMarkSize(width: ink, height: ink / aspect)
            : HeadroomBrandMarkSize(width: ink * aspect, height: ink)
    }
}

/// Two tiers of severity color (Sep 2026 policy change — see `…Fill` below).
///
/// **Text tier** — `healthy/low/critical(dark:)` and `criticalText(dark:)`. The dark values
/// are the vivid originals (tuned for dark cards); the light values are darkened along the
/// same hues so severity *ink* reads ≥4:1 on white. Dark critical is nudged (0.27 → 0.34
/// green) for the 3:1 bar-vs-track floor; dark healthy/low already passed and are untouched.
/// Every text, icon, and pill use stays on this tier. Values are unchanged by the fill split.
///
/// **Fill tier** — `healthyFill/lowFill/criticalFill(dark:increasedContrast:)`, what a meter
/// bar paints. See that tier's own note below.
public enum HeadroomSeverityColorValues {
    public static func healthy(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 0.20, green: 0.78, blue: 0.35) : HeadroomRGBColor(red: 0.09, green: 0.52, blue: 0.22)
    }

    public static func low(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 1.00, green: 0.62, blue: 0.04) : HeadroomRGBColor(red: 0.70, green: 0.41, blue: 0.00)
    }

    public static func critical(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 1.00, green: 0.34, blue: 0.29) : HeadroomRGBColor(red: 0.85, green: 0.16, blue: 0.13)
    }

    /// Critical severity rendered as *text*, decoupled from the bar fill (H3a, Jul 2026
    /// multi-account design review). The chipless multi-account meter paints the percentage
    /// numeral critical instead of showing the "Low" chip, so the numeral becomes AA-legible
    /// body text rather than a bar fill — a separate token because the fill red fails at text
    /// size. WCAG contrast for 18pt-semibold numerals (relative luminance L, ratio
    /// (L_light+0.05)/(L_dark+0.05)):
    /// - Dark = (1.00,0.40,0.35), L≈0.315, on the composite dark card #2C2C2E (L≈0.025)
    ///   → 4.85:1. The raw fill red (1.00,0.34,0.29) lands at only ~4.45:1 there, so it is
    ///   brightened (green 0.34→0.40, blue 0.29→0.35) until it clears ≥4.5:1.
    /// - Light = (0.82,0.14,0.11), L≈0.149, on white → 5.28:1 and across the light card fill
    ///   (L≈0.87 bottom … 0.97 top) ≥4.6:1. The raw fill red (0.85,0.16,0.13) passes on pure
    ///   white (4.9:1) but dips to ~4.3:1 on the card's darker lower fill, so it is darkened
    ///   (0.85→0.82 R, 0.16→0.14 G, 0.13→0.11 B) to hold ≥4.5:1 over the whole surface.
    public static func criticalText(dark: Bool) -> HeadroomRGBColor {
        dark ? HeadroomRGBColor(red: 1.00, green: 0.40, blue: 0.35) : HeadroomRGBColor(red: 0.82, green: 0.14, blue: 0.11)
    }

    public static func color(for severity: WidgetUsageSeverity, dark: Bool) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthy(dark: dark)
        case .low: low(dark: dark)
        case .critical: critical(dark: dark)
        }
    }

    // MARK: - Fill tier
    //
    // What a meter bar paints, split from the text tier in Sep 2026 by product decision.
    //
    // In the *default* light appearance these are vivid — close to the dark tokens in feel —
    // and they deliberately sit below WCAG 1.4.11's 3:1 non-text floor against the light bar
    // track (measured 2.06–3.22:1, worst case low/amber over the darker card fill). That is a
    // considered choice, not an oversight: the percent numeral beside every bar already states
    // the value at full text contrast, so the bar is a redundant visualization rather than the
    // sole carrier of the information the guideline protects.
    //
    // Two things keep it accessible:
    //   1. every *text*, icon, and pill use stays on the text tier above (unchanged), and
    //   2. when the user turns on Increase Contrast, the light fills fall back to the text
    //      tier's darkened values, which clear 3:1 on the track (3.15–3.61:1). The dark fills
    //      are the dark text-tier values in both branches — they already pass (3.06–4.63:1) —
    //      except critical, which R2C4b lifted off the text token to make the dark severity
    //      ramp monotonic; it passes by more (3.58–4.19:1), not less.
    //
    // Why a split instead of a retune: no vivid light fill can clear 3:1 on the light track on
    // its own. The track is black @ 0.12 over a near-white card (L≈0.745), so a 3:1 fill has to
    // sit at L ≤ 0.215 — darker than any saturated sRGB orange (rgb(0.96,0.58,0.05) is L≈0.41).
    // Deepening the track makes it *worse*, not better: these mid-luminance fills are darker
    // than the track, so a darker track converges on them (at 0.18 alpha the amber falls to
    // 1.46:1). The light track therefore stays at 0.12.
    //
    // Light default values were tuned down from the brief's starting points only where the
    // ≥2.0:1-vs-track / ≥2.5:1-vs-card policy floor required it: amber
    // (0.96,0.58,0.05) → (0.91,0.50,0.02) (1.70 → 2.06 vs track); green and red pass as given.
    // `BrandColorValuesTests` pins every ratio.

    public static func healthyFill(dark: Bool, increasedContrast: Bool) -> HeadroomRGBColor {
        guard !dark else { return healthy(dark: true) }
        return increasedContrast
            ? healthy(dark: false)
            : HeadroomRGBColor(red: 0.16, green: 0.66, blue: 0.30)
    }

    /// R2C4a: the light default darkened `oklch(0.700 0.166 58.3)` → `oklch(0.660 0.166
    /// 58.3)`, hue and chroma untouched. A severity ramp that is not monotonic does not
    /// encode severity, and this one ran backwards: light `lowFill` measured |Lc| 53.4/51.0
    /// against the card while `healthyFill` measured 57.2/54.8, so "running low" was quieter
    /// than "you're fine" on the same row. It now reads 59.4/57.0 — above healthy, below
    /// critical — and both pinned floors improve with it (vs track 2.06 → 2.48:1, vs card
    /// 2.71 → 3.27:1).
    public static func lowFill(dark: Bool, increasedContrast: Bool) -> HeadroomRGBColor {
        guard !dark else { return low(dark: true) }
        return increasedContrast
            ? low(dark: false)
            : HeadroomRGBColor(red: 0.856, green: 0.450, blue: 0.000)
    }

    /// R2C4b: the dark fill is the one severity fill that is *not* its text token. The dark
    /// text critical (`oklch(0.683 0.206 28.1)`) measured |Lc| 41–43 against the card, below
    /// the neutral `tickGlassCap`, so a healthy grey meter's tip out-shouted a critical red
    /// meter's. `oklch(0.740 0.190 28.1)` lifts it to 47–49, above the retuned cap and below
    /// healthy. The honest limit: |Lc| cannot put red above amber in dark without
    /// desaturating it, which is fine — AP1 already gives critical a second channel (the red
    /// numeral). Separation vs the track improves too (3.06 → 3.58:1), so the 3:1 floor the
    /// dark fills claim still holds in both the default and Increase Contrast branches.
    public static func criticalFill(dark: Bool, increasedContrast: Bool) -> HeadroomRGBColor {
        guard !dark else { return HeadroomRGBColor(red: 1.00, green: 0.448, blue: 0.389) }
        return increasedContrast
            ? critical(dark: false)
            : HeadroomRGBColor(red: 0.90, green: 0.22, blue: 0.20)
    }

    public static func fill(
        for severity: WidgetUsageSeverity,
        dark: Bool,
        increasedContrast: Bool
    ) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthyFill(dark: dark, increasedContrast: increasedContrast)
        case .low: lowFill(dark: dark, increasedContrast: increasedContrast)
        case .critical: criticalFill(dark: dark, increasedContrast: increasedContrast)
        }
    }
}
