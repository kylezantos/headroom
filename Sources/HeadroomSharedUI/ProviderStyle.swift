import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif

/// Static per-provider visual identity (design review): a brand-ish accent color and
/// SF Symbol so Claude and Codex cards are distinguishable at a glance. Static only —
/// no pulsing/animated indicators (user's standing rule).
public enum ProviderStyle {
    /// Claude and Codex ship a single color mark that reads on both schemes; Grok and
    /// Cursor are monochrome brands, so they carry a light/dark SVG pair selected here.
    public static func svgResourceName(for id: ProviderID, scheme: ColorScheme) -> String? {
        switch id {
        case .claude: return "claude-color"
        case .codex: return "codex-color"
        case .grok: return scheme == .dark ? "grok-dark" : "grok-light"
        case .cursor: return scheme == .dark ? "cursor-dark" : "cursor-light"
        default: return nil
        }
    }

    public static func accent(for id: ProviderID) -> Color {
        switch id {
        case .claude: return Color(HeadroomBrandColorValues.claude)
        case .codex: return Color(HeadroomBrandColorValues.codex)
        case .grok: return Color(HeadroomBrandColorValues.grok)
        case .cursor: return Color(HeadroomBrandColorValues.cursor)
        default: return .secondary
        }
    }

    /// Brand-tinted provider *title* color, shared with the widgets
    /// (`HeadroomWidgetColorValues.textAccent` — WCAG-tuned per scheme) so the popover
    /// and widget headers read as one system (Jul 2026 widget-alignment pass).
    public static func textAccent(for id: ProviderID, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id.raw, dark: scheme == .dark) else {
            return .primary
        }
        return Color(rgb)
    }

    /// Widget-tuned label grays (WCAG-checked in `HeadroomWidgetColorValues`), adopted
    /// over the system `.secondary`/`.tertiary` — system tertiary sat at ~2.3:1 on the
    /// dark tile; the shared token reaches ~4.2:1 and keeps all surfaces in step.
    public static func secondaryText(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    public static func tertiaryText(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// G1A: account-title ink (identity rows and the API spend row names) in the user's
    /// chosen mode — `.neutral` is the recessive grey token, `.brand` is the per-provider
    /// tint the widget headers use, for people who want the popover colored the way they
    /// are used to.
    public static func accountTitleInk(for id: ProviderID, ink: AccountTitleInk, scheme: ColorScheme) -> Color {
        switch ink {
        case .neutral: return accountTitleInk(scheme: scheme)
        case .brand: return textAccent(for: id, scheme: scheme)
        }
    }

    /// T1A: the neutral grey on its own. Kept for surfaces that are not account titles and
    /// for the `.neutral` branch above.
    public static func accountTitleInk(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.accountTitle(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// PA13: the plan pill's ink. It used to be the system `.tertiary`, which measured
    /// |Lc| ≈ 20 on the dark card against ≈ 40 in light — the plan name is the only thing
    /// saying which subscription a meter measures, so it now has a token that reads the same
    /// in both appearances. See `HeadroomWidgetColorValues.planLabel`.
    public static func planLabelInk(scheme: ColorScheme) -> Color {
        color(HeadroomWidgetColorValues.planLabel(dark: scheme == .dark))
    }

    public static func barTrack(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.barTrack(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// R2C15: the track carries the critical hue the shrinking fill no longer can. Every
    /// other severity keeps the neutral track. See `HeadroomMeterColorValues.criticalBarTrack`.
    public static func barTrack(for severity: UsageSeverity, scheme: ColorScheme) -> Color {
        guard severity == .critical else { return barTrack(scheme: scheme) }
        return Color(HeadroomMeterColorValues.criticalBarTrack(dark: scheme == .dark))
    }

    public static func meterLabelInk(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.labelInk(dark: scheme == .dark))
    }

    public static func meterCountdownInk(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.countdownInk(dark: scheme == .dark))
    }

    public static func meterGlassA(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.glassA(dark: scheme == .dark))
    }

    public static func meterGlassB(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.glassB(dark: scheme == .dark))
    }

    public static func meterGlassRim(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.glassRim(dark: scheme == .dark))
    }

    public static func meterWellBackground(scheme: ColorScheme) -> Color {
        Color(HeadroomMeterColorValues.wellBackground(dark: scheme == .dark))
    }

    public static func meterWellShadow(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.wellShadow(dark: scheme == .dark))
    }

    public static func meterWellTopShade(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.wellTopShade(dark: scheme == .dark))
    }

    public static func meterWellBottomLip(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.wellBottomLip(dark: scheme == .dark))
    }

    public static func meterWellHairline(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.wellHairline(dark: scheme == .dark))
    }

    public static func meterTickOff(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.tickOff(dark: scheme == .dark))
    }

    public static func meterTickGlass(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.tickGlass(dark: scheme == .dark))
    }

    public static func meterTickGlassCap(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.tickGlassCap(dark: scheme == .dark))
    }

    /// R2C16: the `.stale` fill keeps its severity's lightness and hue at reduced chroma
    /// instead of collapsing to the system secondary grey — a stale critical is still a
    /// critical. See `HeadroomMeterColorValues.staleFill`.
    public static func meterStaleFill(
        for severity: UsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(HeadroomMeterColorValues.staleFill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }

    /// R2C18: the recessed well shared by the setup flow's command wells and the Settings
    /// preview wells. The Settings panes reached this through `ClaudeSetupStyle.wellBackground`
    /// — a Claude-branded token owning a pane with no Claude in it. Same value, one home.
    public static func recessedWell(dark: Bool) -> Color {
        color(HeadroomWidgetColorValues.recessedWell(dark: dark))
    }

    /// R2C18: the setup flow's quiet-chip label ink, shared with the neutral text bases.
    public static func setupChipInk(dark: Bool) -> Color {
        color(HeadroomWidgetColorValues.setupChipInk(dark: dark))
    }

    // MARK: - R2C18: brand-ramp bridges for the two setup flows
    //
    // `ClaudeSetupStyle` / `CodexSetupStyle` stay the setup views' call surface (the two
    // provider flows are deliberately decoupled), but every number they draw now comes from
    // the one constant-hue ramp in `HeadroomBrandRamp`. These take `dark:` rather than a
    // `ColorScheme` because that is what the setup styles already resolve.

    public static func claudeCTATop(dark: Bool) -> Color {
        Color(HeadroomBrandRamp.claudeCTATop(dark: dark))
    }

    public static func claudeCTABottom(dark: Bool) -> Color {
        Color(HeadroomBrandRamp.claudeCTABottom(dark: dark))
    }

    public static func codexCTATop(dark: Bool) -> Color {
        Color(HeadroomBrandRamp.codexCTATop(dark: dark))
    }

    public static func codexCTABottom(dark: Bool) -> Color {
        Color(HeadroomBrandRamp.codexCTABottom(dark: dark))
    }

    public static func connectedInk(dark: Bool) -> Color {
        Color(HeadroomBrandRamp.connectedInk(dark: dark))
    }

    /// PB13: the quarter-mark hairline, same split as `meterStaleFill`.
    public static func meterQuarterMark(scheme: ColorScheme) -> Color {
        Color.primary.opacity(HeadroomMeterColorValues.quarterMarkOpacity(dark: scheme == .dark))
    }

    /// R2C12: the ramp's gradient stops. Three, not two — SwiftUI interpolates a two-colour
    /// gradient in its own space, so the explicit middle stop is what holds the drawn bar on
    /// the OKLCH path the recipe computed. See `MeterRampStops.color(at:)`.
    ///
    /// MX2: Full draws its softer, eased ramp, which needs more than one middle stop to hold
    /// its curve — `gradientSamples` supplies them. Micro's linear ramp is unchanged.
    public static func meterRampColors(
        for severity: UsageSeverity,
        format: GaugeFormat,
        surface: MeterRampSurface,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> [Color] {
        MeterRecipe.rampStops(
            format: format,
            severity: severity,
            scheme: scheme == .dark ? .dark : .light,
            surface: surface,
            increasedContrast: increasedContrast
        ).gradientSamples.map { Color($0) }
    }

    public static func meterGhostBody(
        for severity: UsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        severityFill(for: severity, scheme: scheme, increasedContrast: increasedContrast)
            .opacity(
                HeadroomMeterColorValues.ghostBodyOpacity(
                    for: severity,
                    dark: scheme == .dark
                )
            )
    }

    /// Semantic fill for a usage bar by health band (UI-01). A static three-stop ramp —
    /// green → amber → red — chosen over the brand accent because Claude's warm clay is
    /// too close to amber to read as "warning". Brand identity stays in the logo + plan
    /// pill; the bar's job is to signal how much is left. No animation: a threshold, not
    /// a pulse, so it honors the standing no-pulsing rule.
    public static func severityColor(for severity: UsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    /// Meter-bar fill tier: vivid in the default light appearance, falling back to the
    /// text-tier (3:1-passing) values under Increase Contrast. Callers read
    /// `\.colorSchemeContrast` at the SwiftUI boundary — the Core token stays a pure Bool
    /// so both branches are testable. Only bars, caps, segments, and ramps use this;
    /// numerals, icons, and the "Low" pill stay on `severityColor(for:scheme:)`.
    public static func severityFill(
        for severity: UsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(HeadroomSeverityColorValues.fill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }

    /// Critical-as-text ink (H3a), decoupled from the bar fill so the chipless multi-account
    /// numeral clears WCAG AA at 18pt semibold. See `HeadroomSeverityColorValues.criticalText`.
    public static func criticalText(scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.criticalText(dark: scheme == .dark))
    }

    public static func symbol(for id: ProviderID) -> String {
        switch id {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .grok: return "atom"
        case .cursor: return "cursorarrow"
        default: return "circle.dashed"
        }
    }

    private static func color(_ tint: HeadroomTint) -> Color {
        Color(tint.color).opacity(tint.opacity)
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Account-title ink propagation (G1A)

/// The popover's account-title ink travels through the environment rather than through
/// every card/section initializer: `IdentityRow` is reached at three nesting depths (single
/// account, account section, spend row) and none of them already carry a display
/// preference, so threading one would add a parameter to four types to deliver a value that
/// only ever changes in Settings. The popover root and the Settings specimen are the only
/// two places that set it; everything below just reads it.
private struct AccountTitleInkKey: EnvironmentKey {
    static let defaultValue: AccountTitleInk = .neutral
}

public extension EnvironmentValues {
    var accountTitleInk: AccountTitleInk {
        get { self[AccountTitleInkKey.self] }
        set { self[AccountTitleInkKey.self] = newValue }
    }
}

/// Applies the resolved title ink for `providerID`, reading both the scheme and the user's
/// choice itself so a call site is a single modifier.
private struct AccountTitleInkStyle: ViewModifier {
    let providerID: ProviderID

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accountTitleInk) private var ink

    func body(content: Content) -> some View {
        content.foregroundStyle(ProviderStyle.accountTitleInk(for: providerID, ink: ink, scheme: scheme))
    }
}

public extension View {
    func accountTitleInk(for providerID: ProviderID) -> some View {
        modifier(AccountTitleInkStyle(providerID: providerID))
    }
}
