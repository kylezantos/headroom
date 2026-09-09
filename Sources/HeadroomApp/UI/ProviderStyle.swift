import SwiftUI
import HeadroomCore

/// Static per-provider visual identity (design review): a brand-ish accent color and
/// SF Symbol so Claude and Codex cards are distinguishable at a glance. Static only —
/// no pulsing/animated indicators (user's standing rule).
enum ProviderStyle {
    /// Claude and Codex ship a single color mark that reads on both schemes; Grok and
    /// Cursor are monochrome brands, so they carry a light/dark SVG pair selected here.
    static func svgResourceName(for id: ProviderID, scheme: ColorScheme) -> String? {
        switch id {
        case .claude: return "claude-color"
        case .codex: return "codex-color"
        case .grok: return scheme == .dark ? "grok-dark" : "grok-light"
        case .cursor: return scheme == .dark ? "cursor-dark" : "cursor-light"
        default: return nil
        }
    }

    static func accent(for id: ProviderID) -> Color {
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
    static func textAccent(for id: ProviderID, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id.raw, dark: scheme == .dark) else {
            return .primary
        }
        return Color(rgb)
    }

    /// Widget-tuned label grays (WCAG-checked in `HeadroomWidgetColorValues`), adopted
    /// over the system `.secondary`/`.tertiary` — system tertiary sat at ~2.3:1 on the
    /// dark tile; the shared token reaches ~4.2:1 and keeps all surfaces in step.
    static func secondaryText(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    static func tertiaryText(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// G1A: account-title ink (identity rows and the API spend row names) in the user's
    /// chosen mode — `.neutral` is the recessive grey token, `.brand` is the per-provider
    /// tint the widget headers use, for people who want the popover colored the way they
    /// are used to.
    static func accountTitleInk(for id: ProviderID, ink: AccountTitleInk, scheme: ColorScheme) -> Color {
        switch ink {
        case .neutral: return accountTitleInk(scheme: scheme)
        case .brand: return textAccent(for: id, scheme: scheme)
        }
    }

    /// T1A: the neutral grey on its own. Kept for surfaces that are not account titles and
    /// for the `.neutral` branch above.
    static func accountTitleInk(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.accountTitle(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// PA13: the plan pill's ink. It used to be the system `.tertiary`, which measured
    /// |Lc| ≈ 20 on the dark card against ≈ 40 in light — the plan name is the only thing
    /// saying which subscription a meter measures, so it now has a token that reads the same
    /// in both appearances. See `HeadroomWidgetColorValues.planLabel`.
    static func planLabelInk(scheme: ColorScheme) -> Color {
        color(HeadroomWidgetColorValues.planLabel(dark: scheme == .dark))
    }

    static func barTrack(scheme: ColorScheme) -> Color {
        let tint = HeadroomWidgetColorValues.barTrack(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    static func meterLabelInk(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.labelInk(dark: scheme == .dark))
    }

    static func meterCountdownInk(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.countdownInk(dark: scheme == .dark))
    }

    static func meterGlassA(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.glassA(dark: scheme == .dark))
    }

    static func meterGlassB(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.glassB(dark: scheme == .dark))
    }

    static func meterGlassRim(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.glassRim(dark: scheme == .dark))
    }

    static func meterWellBackground(scheme: ColorScheme) -> Color {
        Color(HeadroomMeterColorValues.wellBackground(dark: scheme == .dark))
    }

    static func meterWellShadow(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.wellShadow(dark: scheme == .dark))
    }

    static func meterTickOff(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.tickOff(dark: scheme == .dark))
    }

    static func meterTickGlass(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.tickGlass(dark: scheme == .dark))
    }

    static func meterTickGlassCap(scheme: ColorScheme) -> Color {
        color(HeadroomMeterColorValues.tickGlassCap(dark: scheme == .dark))
    }

    /// PB13: the `.staleGrey` fill. The base follows the system secondary label — a stale
    /// meter should recede exactly as far as stale text does — and the dim it takes lives in
    /// `HeadroomMeterColorValues` with the rest of the meter chrome.
    static var meterStaleFill: Color {
        Color.secondary.opacity(HeadroomMeterColorValues.staleFillOpacity)
    }

    /// PB13: the quarter-mark hairline, same split as `meterStaleFill`.
    static func meterQuarterMark(scheme: ColorScheme) -> Color {
        Color.primary.opacity(HeadroomMeterColorValues.quarterMarkOpacity(dark: scheme == .dark))
    }

    static func meterRampStart(
        for severity: UsageSeverity,
        surface: MeterRampSurface,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        let stops = MeterRecipe.rampStops(
            severity: severity,
            scheme: scheme == .dark ? .dark : .light,
            surface: surface,
            increasedContrast: increasedContrast
        )
        return Color(stops.start)
    }

    static func meterGhostBody(
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
    static func severityColor(for severity: UsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    /// Meter-bar fill tier: vivid in the default light appearance, falling back to the
    /// text-tier (3:1-passing) values under Increase Contrast. Callers read
    /// `\.colorSchemeContrast` at the SwiftUI boundary — the Core token stays a pure Bool
    /// so both branches are testable. Only bars, caps, segments, and ramps use this;
    /// numerals, icons, and the "Low" pill stay on `severityColor(for:scheme:)`.
    static func severityFill(
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
    static func criticalText(scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.criticalText(dark: scheme == .dark))
    }

    static func symbol(for id: ProviderID) -> String {
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

extension EnvironmentValues {
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

extension View {
    func accountTitleInk(for providerID: ProviderID) -> some View {
        modifier(AccountTitleInkStyle(providerID: providerID))
    }
}
