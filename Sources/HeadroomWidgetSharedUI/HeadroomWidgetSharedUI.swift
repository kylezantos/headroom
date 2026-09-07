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
    /// Increase Contrast. Text, the "Low" label, and the attention glyphs keep
    /// `severityColor`. See `HeadroomSeverityColorValues` for why the tiers differ.
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

    public static func secondaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark))
    }

    public static func tertiaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark))
    }

    public static func barTrack(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.barTrack(dark: scheme == .dark))
    }

    public static func hairline(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.hairline(dark: scheme == .dark))
    }

}

public struct HeadroomWidgetProviderIcon: View {
    private let providerID: String
    private let size: CGFloat

    public init(providerID: String, size: CGFloat) {
        self.providerID = providerID
        self.size = size
    }

    // OA2: same measured rule and leading alignment as the popover and the iOS app — the
    // imageset artwork is trimmed to its ink, the larger ink dimension is 13/15 of the slot
    // with the aspect preserved, and the leftover slot falls on the trailing side so every
    // provider's mark hangs on one axis.
    public var body: some View {
        let mark = HeadroomBrandMark.markSize(for: providerID, slot: Double(size))
        let markWidth = CGFloat(mark.width)
        let markHeight = CGFloat(mark.height)
        if let assetName = HeadroomWidgetStyle.assetName(for: providerID) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .frame(width: size, height: size, alignment: .leading)
                .accessibilityHidden(true)
        } else {
            Image(systemName: HeadroomWidgetStyle.symbol(for: providerID))
                .resizable()
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .frame(width: size, height: size, alignment: .leading)
                .foregroundStyle(HeadroomWidgetStyle.accent(for: providerID))
                .accessibilityHidden(true)
        }
    }
}

public struct HeadroomWidgetUsageMeter: View {
    private let window: WidgetWindowSummary?
    private let fallbackLabel: String
    private let now: Date?
    private let showsResetInline: Bool
    private let compact: Bool
    private let scale: LargeWidgetDensity.Scale?

    @Environment(\.colorScheme) private var scheme

    public init(
        window: WidgetWindowSummary?,
        fallbackLabel: String,
        now: Date? = nil,
        showsResetInline: Bool = false,
        compact: Bool = false,
        scale: LargeWidgetDensity.Scale? = nil
    ) {
        self.window = window
        self.fallbackLabel = fallbackLabel
        self.now = now
        self.showsResetInline = showsResetInline
        self.compact = compact
        self.scale = scale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: vStackSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(labelText)
                    .font(labelFont)
                    .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                if window?.freshness.isStale == true {
                    Text("· Last known")
                        .font(resetFont.weight(.medium))
                        .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                }
                if let resetText {
                    Text("· \(resetText)")
                        .font(resetFont)
                        .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 2)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(percentText)
                        .font(percentFont)
                        .foregroundStyle(
                            window == nil || window?.freshness.isLive == false
                                ? HeadroomWidgetStyle.secondaryText(scheme: scheme)
                                : .primary
                        )
                        .widgetAccentable()
                    if window?.displayPercentRemaining != nil {
                        Text("left")
                            .font(.footnote)
                            .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                            .minimumScaleFactor(0.82)
                    }
                }
                if window?.severity == .critical, window?.freshness.isLive == true {
                    Text("Low")
                        .font(.footnote.weight(.semibold))
                        .kerning(0.2)
                        .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .critical, scheme: scheme))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            HeadroomWidgetUsageBar(
                percentRemaining: window?.displayPercentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil || window?.freshness.isLive == false,
                height: barHeight
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(labelText) usage")
        .accessibilityValue(accessibilityValue)
    }

    private var vStackSpacing: CGFloat {
        if let scale {
            return CGFloat(scale.meterSpacing)
        }
        return compact ? 2 : 4
    }

    private var barHeight: CGFloat {
        if let scale {
            return CGFloat(scale.barHeight)
        }
        return 6
    }

    private var labelFont: Font {
        if let scale {
            switch scale {
            case .hero: return .subheadline.weight(.medium)
            case .standard: return .footnote.weight(.medium)
            case .dense: return .caption.weight(.medium)
            case .ultraDense: return .caption2.weight(.medium)
            }
        }
        return compact ? .caption.weight(.medium) : .caption
    }

    private var resetFont: Font {
        if let scale {
            switch scale {
            case .hero: return .caption.monospacedDigit()
            case .standard: return .caption.monospacedDigit()
            case .dense: return .caption2.monospacedDigit()
            case .ultraDense: return .caption2.monospacedDigit()
            }
        }
        return compact ? .caption.monospacedDigit() : .caption2.monospacedDigit()
    }

    private var percentFont: Font {
        if let scale {
            switch scale {
            case .hero: return .title3.bold().monospacedDigit()
            case .standard: return .headline.bold().monospacedDigit()
            case .dense: return .subheadline.bold().monospacedDigit()
            case .ultraDense: return .caption.bold().monospacedDigit()
            }
        }
        // The percentage is the glance value, so it outsizes its label. scale (the large
        // widget tiers) steps down from title3 (hero) through headline (standard) to subheadline (dense):
        // with four meters stacked across two cards, a 20pt title3 in every row builds a loud, cramped
        // right rail — stepping down per-tier keeps the number legible while the full-width bar already
        // carries the glance at that size.
        return compact ? .title3.bold().monospacedDigit() : .caption.bold().monospacedDigit()
    }

    private var percentText: String {
        guard let value = window?.displayPercentRemaining else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var labelText: String {
        window?.label ?? fallbackLabel
    }

    private var resetText: String? {
        guard let window, showsResetInline else { return nil }
        if window.freshness.isUnavailable { return "Unavailable" }
        guard let now else { return nil }
        return Countdown.resetText(
            schedule: window.resetSchedule,
            utilization: window.utilization,
            isLive: window.freshness.isLive,
            now: now
        )
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let value = window?.displayPercentRemaining {
            parts.append("\(Int(value.rounded())) percent remaining")
        }
        if window?.freshness.isStale == true {
            parts.append("Last known")
        }
        if window?.freshness.isUnavailable == true {
            parts.append("Unavailable")
        }
        if let resetText, window?.freshness.isUnavailable != true {
            parts.append(resetText)
        }
        if window?.severity == .critical, window?.freshness.isLive == true {
            parts.append("low")
        }
        return parts.joined(separator: ", ")
    }
}

public struct HeadroomWidgetUsageBar: View {
    private let percentRemaining: Double
    private let severity: WidgetUsageSeverity
    private let dimmed: Bool
    private let height: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init(percentRemaining: Double, severity: WidgetUsageSeverity, dimmed: Bool = false, height: CGFloat = 6) {
        self.percentRemaining = percentRemaining
        self.severity = severity
        self.dimmed = dimmed
        self.height = height
    }

    private var fraction: Double {
        min(1, max(0, percentRemaining / 100))
    }

    private func fillWidth(in availableWidth: Double) -> Double {
        guard fraction > 0 else { return 0 }
        return max(height, availableWidth * fraction)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HeadroomWidgetStyle.barTrack(scheme: scheme))
                Capsule()
                    .fill(dimmed
                        ? HeadroomWidgetStyle.secondaryText(scheme: scheme)
                        : HeadroomWidgetStyle.severityFill(
                            for: severity,
                            scheme: scheme,
                            increasedContrast: contrast == .increased
                        ))
                    .frame(width: fillWidth(in: geo.size.width))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

public struct HeadroomWidgetAPISpendCompactRow: View {
    private let summaries: [WidgetAPISpendSummary]
    private let now: Date

    @Environment(\.colorScheme) private var scheme

    public init(summaries: [WidgetAPISpendSummary], now: Date) {
        self.summaries = summaries
        self.now = now
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(summaries) { summary in
                compactItem(summary)
            }
        }
    }

    private func compactItem(_ summary: WidgetAPISpendSummary) -> some View {
        HStack(spacing: 4) {
            HeadroomWidgetProviderIcon(providerID: summary.id, size: 11)
            Text(APISpendPresentation.amountText(summary) ?? "—")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(amountColor(summary))
                .privacySensitive()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            if summary.freshness.needsAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .low, scheme: scheme))
            }
        }
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(summary))
    }

    private func accessibilityText(_ summary: WidgetAPISpendSummary) -> String {
        var parts = [summary.displayName, APISpendPresentation.amountText(summary) ?? "no amount"]
        if summary.freshness.needsAttention {
            parts.append("needs attention")
        }
        return parts.joined(separator: ", ")
    }

    private func amountColor(_ summary: WidgetAPISpendSummary) -> Color {
        APISpendPresentation.amountText(summary) == nil || summary.freshness != .live
            ? HeadroomWidgetStyle.secondaryText(scheme: scheme)
            : .primary
    }
}

/// The widget families' shared API-spend treatment: a hairline, an "API" prefix that keeps
/// the dollar amounts from reading as subscription cost, the compact per-provider amounts,
/// and the freshness footer fused onto the same line. Spend is a single glance scalar per
/// provider, so it never gets a titled section in a widget — the popover (and a future
/// dedicated spend widget) carry names, period, and status detail.
public struct HeadroomWidgetAPISpendStrip: View {
    private let summaries: [WidgetAPISpendSummary]
    private let now: Date
    private let footerText: String?

    @Environment(\.colorScheme) private var scheme

    public init(summaries: [WidgetAPISpendSummary], now: Date, footerText: String?) {
        self.summaries = summaries
        self.now = now
        self.footerText = footerText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle()
                .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
                .frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("API")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .accessibilityLabel("API spend")
                HeadroomWidgetAPISpendCompactRow(summaries: summaries, now: now)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let footerText {
                    Text(footerText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                }
            }
        }
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
