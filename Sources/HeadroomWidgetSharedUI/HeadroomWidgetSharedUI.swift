#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI
import WidgetKit

public enum HeadroomWidgetStyle {
    public static func assetName(for id: String) -> String? {
        switch id {
        case ProviderID.claude.raw: "ClaudeBrandIcon"
        case ProviderID.codex.raw: "CodexBrandIcon"
        // Grok/Cursor imagesets carry a luminosity dark appearance, so `Image(assetName)`
        // adapts per scheme natively — no separate light/dark lookup needed here.
        case ProviderID.grok.raw: "GrokBrandIcon"
        case ProviderID.cursor.raw: "CursorBrandIcon"
        default: nil
        }
    }

    public static func accent(for id: String) -> Color {
        switch id {
        case ProviderID.claude.raw: return Color(HeadroomBrandColorValues.claude)
        case ProviderID.codex.raw: return Color(HeadroomBrandColorValues.codex)
        case ProviderID.grok.raw: return Color(HeadroomBrandColorValues.grok)
        case ProviderID.cursor.raw: return Color(HeadroomBrandColorValues.cursor)
        default: return .secondary
        }
    }

    // R2: wraps the shared HeadroomWidgetColorValues so macOS and iOS cannot drift.
    public static func textAccent(for id: String, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id, dark: scheme == .dark) else { return .secondary }
        return Color(rgb)
    }

    public static func symbol(for id: String) -> String {
        switch id {
        case ProviderID.claude.raw: "sparkle"
        case ProviderID.codex.raw: "chevron.left.forwardslash.chevron.right"
        case ProviderID.grok.raw: "atom"
        case ProviderID.cursor.raw: "cursorarrow"
        default: "circle.dashed"
        }
    }

    public static func severityColor(for severity: WidgetUsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    /// Bar-fill tier, mirroring the popover (`ProviderStyle.severityFill`): vivid in the
    /// default light appearance, reverting to the 3:1-passing text-tier values under
    /// Increase Contrast. Text and the attention glyphs keep `severityColor`. See
    /// `HeadroomSeverityColorValues` for why the tiers differ.
    public static func severityFill(
        for severity: WidgetUsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(HeadroomSeverityColorValues.fill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }

    /// WCM1: what a *healthy live* bar paints. Green as the resting state carries no
    /// information; the popover's shipped default (`MeterStyle.default.fill ==
    /// .colorAsEvent`) already paints healthy neutral, and it is the precondition for WCM2
    /// and WCD1 — a red bar is only an alarm on a tile where nothing else is coloured.
    public static func neutralFill(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.neutralFill(dark: scheme == .dark))
    }

    /// WCM3: what a bar paints when its window (or its provider) is no longer live. The
    /// row keeps its own severity hue at 0.35 chroma, so a stale critical is still faintly
    /// red and a stale healthy is the neutral stale tone — the old `secondaryText` fill made
    /// a retired bar the loudest bar on the tile.
    public static func staleFill(
        for severity: WidgetUsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(HeadroomMeterColorValues.staleFill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }


    public static func criticalText(scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.criticalText(dark: scheme == .dark))
    }

    /// WCM2: at critical the track takes the critical hue at constant lightness, so the
    /// alarm survives the few points of fill left at 3%.
    public static func criticalBarTrack(scheme: ColorScheme) -> Color {
        Color(HeadroomMeterColorValues.criticalBarTrack(dark: scheme == .dark))
    }

    public static func secondaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark))
    }

    public static func tertiaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark))
    }

    /// WCD1: provider and account names are neutral on widgets. Colour lives in the brand
    /// mark and in severity events; Claude's dark text accent and the low amber are
    /// near-neighbours in hue at glance distance, and the mark already separates providers.
    public static func accountTitle(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.accountTitle(dark: scheme == .dark))
    }

    /// WCW9: the large family's plan pill ink.
    public static func planLabel(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.planLabel(dark: scheme == .dark))
    }

    public static func barTrack(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.barTrack(dark: scheme == .dark))
    }

    /// WCL4: the lifted widget-only rule ink. The shared `hairline` token was tuned for the
    /// popover's card fills and measures 1.28:1 on the widget container; a rule that is a
    /// true device pixel has to be a little stronger to read at all.
    public static func widgetHairline(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.widgetHairline(dark: scheme == .dark))
    }

    /// WCL4: one device pixel, not one point. Every rule in the widgets is drawn at this
    /// width so a 2× and a 3× tile carry the same hairline rather than a 2pt slab.
    public static func hairlineWidth(displayScale: CGFloat) -> CGFloat {
        CGFloat(WidgetMetrics.hairline) / max(1, displayScale)
    }
}

public struct HeadroomWidgetProviderIcon: View {
    private let providerID: String
    private let size: CGFloat

    public init(providerID: String, size: CGFloat) {
        self.providerID = providerID
        self.size = size
    }

    // OA2: same measured rule and centring as the popover and the iOS app — the imageset
    // artwork is trimmed to its ink, the larger ink dimension is 13/15 of the slot with the
    // aspect preserved, and the mark is centred in the slot so every provider's mark shares
    // one centre line and an even gap to its name.
    //
    // WCM7: `.desaturated` in the accented/vibrant families. The brand mark is the one
    // channel that separates Claude from Codex, and a tinted mark loses it; desaturated
    // keeps the silhouette's own value structure under the user's tint.
    public var body: some View {
        let mark = HeadroomBrandMark.markSize(for: providerID, slot: Double(size))
        let markWidth = CGFloat(mark.width)
        let markHeight = CGFloat(mark.height)
        if let assetName = HeadroomWidgetStyle.assetName(for: providerID) {
            Image(assetName)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: HeadroomWidgetStyle.symbol(for: providerID))
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .frame(width: size, height: size)
                .foregroundStyle(HeadroomWidgetStyle.accent(for: providerID))
                .accessibilityHidden(true)
        }
    }
}

/// WCM5: the one attention glyph pair. Provider-level attention is an account-lifecycle
/// fact, not a usage severity, so per R2C5 it comes off the severity ramp entirely and
/// prints in neutral `secondaryText` — the old amber triangle was the *same* amber as a low
/// bar, three meanings on one glyph. The circle marks a provider, the triangle a spend row.
public struct HeadroomWidgetAttentionGlyph: View {
    public enum Kind: Sendable, Equatable {
        case provider
        case spend

        var symbol: String {
            switch self {
            case .provider: "exclamationmark.circle.fill"
            case .spend: "exclamationmark.triangle.fill"
            }
        }
    }

    private let kind: Kind
    private let size: Double

    @Environment(\.colorScheme) private var scheme
    // WCF1: callers hand over the *ladder* size and the glyph takes the Dynamic Type factor
    // itself, so a glyph beside a name never stays put while the name grows — and the spend
    // strip, whose own sizes are already `@ScaledMetric`, passes its raw token rather than
    // scaling twice.
    @HeadroomWidgetTypeUnit private var typeUnit

    public init(kind: Kind, size: Double) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        let scaled = size * typeUnit
        return Image(systemName: kind.symbol)
            .font(HeadroomWidgetType.font(size: scaled, weight: .semibold))
            .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
            // WCL6/WCM5-iv: the glyph sits beside a name of another size, so it lands on the
            // row's cap-height axis rather than on its own line box.
            .widgetCapHeightCentered(size: scaled, weight: .semibold)
            .accessibilityHidden(true)
    }
}

/// WCW6: the API-spend strip. No eyebrow — the craft floor bans them, and a 10pt tracked
/// "API" was the same size as the amounts it labelled. The rule stays on large (spend is a
/// different *tile* in the popover; here the rule does that separating job), while medium
/// separates with air instead (WCL4). Each item is mark · amount · direction term, because
/// "$58.90" alone means money gone on a period row and money left on a balance row, and the
/// two render identically.
public struct HeadroomWidgetAPISpendStrip: View {
    private let summaries: [WidgetAPISpendSummary]
    private let now: Date
    private let family: HeadroomWidgetFamily
    private let scale: WidgetTypeScale
    private let footerText: String?
    /// WCF7/WCW6: the stamp's middle rung — the bare age ("38 min ago") that prints when the
    /// amounts and the full "Updated 38 min ago" cannot share the run, before the stamp
    /// drops whole.
    private let footerShortText: String?
    private let showsRule: Bool
    /// The brand mark, injected by in-app renders (Settings, the harness) that have no brand
    /// asset catalog; widgets leave it nil and draw `HeadroomWidgetProviderIcon`.
    private let mark: ((String, CGFloat) -> AnyView)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    @ScaledMetric private var amountSize: Double
    @ScaledMetric private var termSize: Double
    @ScaledMetric private var footerSize: Double

    public init(
        summaries: [WidgetAPISpendSummary],
        now: Date,
        family: HeadroomWidgetFamily,
        scale: WidgetTypeScale,
        footerText: String?,
        footerShortText: String? = nil,
        showsRule: Bool,
        mark: ((String, CGFloat) -> AnyView)? = nil
    ) {
        self.mark = mark
        self.summaries = summaries
        self.now = now
        self.family = family
        self.scale = scale
        self.footerText = footerText
        self.footerShortText = footerShortText
        self.showsRule = showsRule
        _amountSize = ScaledMetric(wrappedValue: scale.spendAmount, relativeTo: .body)
        _termSize = ScaledMetric(wrappedValue: scale.spendSuffix, relativeTo: .body)
        _footerSize = ScaledMetric(wrappedValue: scale.footer, relativeTo: .body)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsRule {
                Rectangle()
                    .fill(HeadroomWidgetStyle.widgetHairline(scheme: scheme))
                    .frame(height: HeadroomWidgetStyle.hairlineWidth(displayScale: displayScale))
                    .padding(.bottom, CGFloat(WidgetMetrics.spendRuleToRow))
                    .accessibilityHidden(true)
            }
            // WCF7: the stamp is the element that gives — dropped whole when the amounts
            // and it cannot share the run. The amounts never truncate; they are the payload.
            ViewThatFits(in: .horizontal) {
                row(footer: footerText)
                if let footerShortText, footerShortText != footerText {
                    row(footer: footerShortText)
                }
                row(footer: nil)
            }
        }
    }

    private func row(footer: String?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: CGFloat(WidgetMetrics.spendItemGap)) {
                ForEach(summaries) { summary in
                    item(summary)
                }
            }
            .fixedSize()
            Spacer(minLength: 8)
            if let footerText = footer {
                Text(footerText)
                    .font(HeadroomWidgetType.font(size: footerSize, weight: .medium, mono: true))
                    .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .widgetCapHeightCentered(size: footerSize, weight: .medium, mono: true)
            }
        }
    }

    private func item(_ summary: WidgetAPISpendSummary) -> some View {
        let status = rowStatus(summary)
        return HStack(alignment: .center, spacing: 5) {
            if let mark {
                mark(summary.id, 13)
            } else {
                HeadroomWidgetProviderIcon(providerID: summary.id, size: 13)
            }
            Text(amountText(summary))
                .font(HeadroomWidgetType.font(size: amountSize, weight: .semibold, mono: true))
                .foregroundStyle(amountColor(summary))
                .privacySensitive()
                .lineLimit(1)
                .widgetCapHeightCentered(size: amountSize, weight: .semibold, mono: true)
                .widgetAccentable()
            Text(APISpendPresentation.directionTerm(kind: summary.semanticKind))
                .font(HeadroomWidgetType.font(size: termSize))
                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .widgetCapHeightCentered(size: termSize, weight: .regular)
            attention(status)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(summary, status: status))
    }

    /// WCW6: large has the width to name the state — "Setup", "Rejected", "Denied",
    /// "Stale" — and those strings were written for this surface and never printed. Medium
    /// keeps the glyph and moves the word into the accessibility label; the glyph is
    /// neutral per R2C5, since a spend key problem is not a usage severity.
    @ViewBuilder
    private func attention(_ status: APISpendRowStatus) -> some View {
        if let badge = status.shortBadge {
            if family == .large {
                Text(badge)
                    .font(HeadroomWidgetType.font(size: termSize, weight: .medium))
                    .foregroundStyle(badgeInk(status.tone))
                    .lineLimit(1)
                    .widgetCapHeightCentered(size: termSize, weight: .medium)
            } else {
                // WCF1: the glyph scales the ladder token itself, so it gets the raw
                // `spendSuffix` rather than this view's already-scaled `termSize`.
                HeadroomWidgetAttentionGlyph(kind: .spend, size: scale.spendSuffix)
            }
        }
    }

    private func badgeInk(_ tone: APISpendRowStatus.Tone) -> Color {
        switch tone {
        case .critical: HeadroomWidgetStyle.criticalText(scheme: scheme)
        case .warning: HeadroomWidgetStyle.secondaryText(scheme: scheme)
        case .neutral, .quiet: HeadroomWidgetStyle.tertiaryText(scheme: scheme)
        }
    }

    private func rowStatus(_ summary: WidgetAPISpendSummary) -> APISpendRowStatus {
        APISpendPresentation.rowStatus(
            freshness: summary.freshness,
            attention: summary.attention,
            providerID: ProviderID(summary.id),
            displayName: summary.displayName,
            kind: summary.semanticKind
        )
    }

    /// The bare figure: the direction term is printed as its own element here, so the
    /// widget/phone form of `amountText` (which bakes "left" into balance rows) would
    /// double it.
    private func amountText(_ summary: WidgetAPISpendSummary) -> String {
        APISpendPresentation.amountText(amount: summary.amount, currency: summary.currency) ?? "—"
    }

    private func amountColor(_ summary: WidgetAPISpendSummary) -> Color {
        summary.amount == nil || summary.freshness != .live
            ? HeadroomWidgetStyle.secondaryText(scheme: scheme)
            : .primary
    }

    private func accessibilityText(_ summary: WidgetAPISpendSummary, status: APISpendRowStatus) -> String {
        var parts = [
            summary.displayName,
            APISpendPresentation.amountText(summary) ?? "no amount",
        ]
        if summary.amount != nil {
            parts.append(APISpendPresentation.directionTerm(kind: summary.semanticKind))
        }
        if let badge = status.badge {
            parts.append(badge)
        }
        return parts.joined(separator: ", ")
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    init(_ tint: HeadroomTint) {
        self = Color(tint.color).opacity(tint.opacity)
    }
}
