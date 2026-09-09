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

public enum HeadroomBrandColorValues {
    public static let claude = HeadroomRGBColor(red: 0.85, green: 0.47, blue: 0.26)
    public static let codex = HeadroomRGBColor(red: 0.28, green: 0.34, blue: 1.00)
    // Grok and Cursor are monochrome brands (their marks ship as light/dark pairs); these
    // mid-tone accents exist for the SF Symbol fallback + single-color tints and read on
    // both schemes. First-pass identity values — Phase 2 owns visual density.
    public static let grok = HeadroomRGBColor(red: 0.36, green: 0.40, blue: 0.46)
    public static let cursor = HeadroomRGBColor(red: 0.33, green: 0.34, blue: 0.38)
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
        // Light Claude sits at 4.17:1 on the widget's light container top at its smallest
        // usage (12pt semibold, small-widget provider rows); this darker step clears
        // WCAG AA small-text (≥4.5:1) on every light surface it appears on.
        case (ProviderID.claude.raw, false): HeadroomRGBColor(red: 0.70, green: 0.33, blue: 0.11)
        case (ProviderID.claude.raw, true): HeadroomRGBColor(red: 0.91, green: 0.56, blue: 0.41)
        case (ProviderID.codex.raw, false): HeadroomRGBColor(red: 0.20, green: 0.25, blue: 0.84)
        case (ProviderID.codex.raw, true): HeadroomRGBColor(red: 0.59, green: 0.63, blue: 1.00)
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
    /// it is a one-cell end marker, not the fill's weight — so it is the one neutral token
    /// exempt from the body-below-severity ordering (dark's 0.52 cap already measures above
    /// the dark critical fill and always has).
    public static func tickGlassCap(dark: Bool) -> HeadroomTint {
        HeadroomTint(color: dark ? .white : .black, opacity: dark ? 0.52 : 0.36)
    }

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

    /// PB13: the dim a `.staleGrey` fill paints at. The *base* stays the system secondary
    /// label at the SwiftUI edge (this is the one meter fill that follows the system label
    /// colour rather than a fixed grey); only the number lives here, with the rest of the
    /// meter chrome, instead of inline in `MeterGauge`.
    public static let staleFillOpacity: Double = 0.55

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

    /// PB13: the quarter-mark hairline. Same split as `staleFillOpacity` — the base is the
    /// system primary label at the SwiftUI edge, the per-scheme number lives here.
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
    //      are the dark text-tier values in both branches — they already pass (3.06–4.63:1).
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

    public static func lowFill(dark: Bool, increasedContrast: Bool) -> HeadroomRGBColor {
        guard !dark else { return low(dark: true) }
        return increasedContrast
            ? low(dark: false)
            : HeadroomRGBColor(red: 0.91, green: 0.50, blue: 0.02)
    }

    public static func criticalFill(dark: Bool, increasedContrast: Bool) -> HeadroomRGBColor {
        guard !dark else { return critical(dark: true) }
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
