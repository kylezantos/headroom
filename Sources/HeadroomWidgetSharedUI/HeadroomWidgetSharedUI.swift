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
        default: nil
        }
    }

    public static func accent(for id: String) -> Color {
        switch id {
        case ProviderID.claude.raw: return Color(HeadroomBrandColorValues.claude)
        case ProviderID.codex.raw: return Color(HeadroomBrandColorValues.codex)
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
        default: "circle.dashed"
        }
    }

    public static func severityColor(for severity: WidgetUsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
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

    public static func cardFill(scheme: ColorScheme) -> LinearGradient {
        let dark = scheme == .dark
        return LinearGradient(
            colors: [
                Color(HeadroomWidgetColorValues.tileFillTop(dark: dark)),
                Color(HeadroomWidgetColorValues.tileFillBottom(dark: dark))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static func cardRing(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileRing(dark: scheme == .dark))
    }

    public static func cardTopRim(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileTopRim(dark: scheme == .dark))
    }

    public static func cardCloseShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileCloseShadow(dark: scheme == .dark))
    }

    public static func cardAmbientShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileAmbientShadow(dark: scheme == .dark))
    }

    public static func cardLongShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileLongShadow(dark: scheme == .dark))
    }
}

public struct HeadroomWidgetProviderIcon: View {
    private let providerID: String
    private let size: CGFloat

    public init(providerID: String, size: CGFloat) {
        self.providerID = providerID
        self.size = size
    }

    public var body: some View {
        let scale = CGFloat(HeadroomBrandMark.opticalScale(for: providerID))
        if let assetName = HeadroomWidgetStyle.assetName(for: providerID) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size * scale, height: size * scale)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: HeadroomWidgetStyle.symbol(for: providerID))
                .resizable()
                .scaledToFit()
                .frame(width: size * scale, height: size * scale)
                .frame(width: size, height: size)
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
    private let prominent: Bool

    @Environment(\.colorScheme) private var scheme

    public init(
        window: WidgetWindowSummary?,
        fallbackLabel: String,
        now: Date? = nil,
        showsResetInline: Bool = false,
        compact: Bool = false,
        prominent: Bool = false
    ) {
        self.window = window
        self.fallbackLabel = fallbackLabel
        self.now = now
        self.showsResetInline = showsResetInline
        self.compact = compact
        self.prominent = prominent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 5 : (compact ? 2 : 4)) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(labelText)
                    .font(labelFont)
                    .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
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
                        .foregroundStyle(window == nil ? HeadroomWidgetStyle.secondaryText(scheme: scheme) : .primary)
                        .widgetAccentable()
                    Text("left")
                        .font(.footnote)
                        .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                        .minimumScaleFactor(0.82)
                }
                if window?.severity == .critical {
                    Text("Low")
                        .font(.footnote.weight(.semibold))
                        .kerning(0.2)
                        .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .critical, scheme: scheme))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            HeadroomWidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil,
                height: prominent ? 8 : 6
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(labelText) usage")
        .accessibilityValue(accessibilityValue)
    }

    private var labelFont: Font {
        prominent ? .subheadline.weight(.medium) : (compact ? .caption.weight(.medium) : .caption)
    }

    private var resetFont: Font {
        prominent ? .caption.monospacedDigit() : .caption2.monospacedDigit()
    }

    private var percentFont: Font {
        // The percentage is the glance value, so it outsizes its label. compact (the medium
        // widgets) was too timid at .subheadline — bump to .title3 so it reads at arm's length
        // without crowding the "left" suffix or the bar. prominent/default left as-is.
        prominent ? .title3.bold().monospacedDigit() : (compact ? .title3.bold().monospacedDigit() : .caption.bold().monospacedDigit())
    }

    private var percentText: String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private var labelText: String {
        window?.label ?? fallbackLabel
    }

    private var resetText: String? {
        guard let window, showsResetInline else { return nil }
        if let label = window.resetLabel { return label }
        guard let now else { return nil }
        if window.resetsAt <= now { return "Resets now" }
        return "Resets in \(Countdown.string(to: window.resetsAt, now: now))"
    }

    private var accessibilityValue: String {
        var parts = ["\(Int((window?.percentRemaining ?? 0).rounded())) percent remaining"]
        if let resetText {
            parts.append(resetText)
        }
        if window?.severity == .critical {
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
                    .fill(dimmed ? HeadroomWidgetStyle.secondaryText(scheme: scheme) : HeadroomWidgetStyle.severityColor(for: severity, scheme: scheme))
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
    }

    private func amountColor(_ summary: WidgetAPISpendSummary) -> Color {
        APISpendPresentation.amountText(summary) == nil || summary.freshness != .live
            ? HeadroomWidgetStyle.secondaryText(scheme: scheme)
            : .primary
    }
}

public struct HeadroomWidgetAPISpendSection: View {
    private let summaries: [WidgetAPISpendSummary]
    private let now: Date

    @Environment(\.colorScheme) private var scheme

    public init(summaries: [WidgetAPISpendSummary], now: Date) {
        self.summaries = summaries
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("API Spend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 8)
                if let periodLabel = summaries.first?.periodLabel {
                    Text(periodLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                }
            }
            ForEach(summaries) { summary in
                HStack(spacing: 7) {
                    HeadroomWidgetProviderIcon(providerID: summary.id, size: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HeadroomWidgetStyle.textAccent(for: summary.id, scheme: scheme))
                            .lineLimit(1)
                        if !detailText(summary).isEmpty {
                            Text(detailText(summary))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(APISpendPresentation.amountText(summary) ?? "—")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(amountColor(summary))
                        .privacySensitive()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                }
            }
        }
    }

    private func detailText(_ summary: WidgetAPISpendSummary) -> String {
        switch summary.freshness {
        case .pending, .stale:
            return APISpendPresentation.statusText(freshness: summary.freshness, capturedAt: summary.capturedAt, now: now) ?? ""
        case .live:
            return ""
        }
    }

    private func amountColor(_ summary: WidgetAPISpendSummary) -> Color {
        APISpendPresentation.amountText(summary) == nil || summary.freshness != .live
            ? HeadroomWidgetStyle.secondaryText(scheme: scheme)
            : .primary
    }
}

private struct HeadroomWidgetLargeProviderCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(cardShape)
    }

    @ViewBuilder
    private var cardShape: some View {
        if renderingMode == .fullColor {
            fullColorCard
        } else {
            // The macOS desktop de-emphasized (vibrant) pass maps the widget's luminance
            // onto a monochrome material, so an opaque tile fill plus soft shadows blow
            // out into a glowing white block with a halo. Drop the fill and shadows there
            // and keep only a hairline ring, matching how the medium widget reads in the
            // same state — separated surfaces, no glow. (Mirrors the containerBackground
            // gate in HeadroomWidgetView.)
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(HeadroomWidgetStyle.cardRing(scheme: scheme), lineWidth: 1)
        }
    }

    private var fullColorCard: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(HeadroomWidgetStyle.cardFill(scheme: scheme))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(HeadroomWidgetStyle.cardRing(scheme: scheme), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(HeadroomWidgetStyle.cardTopRim(scheme: scheme))
                    .frame(height: 1)
                    .padding(.horizontal, 7)
                    .allowsHitTesting(false)
            }
            .shadow(color: HeadroomWidgetStyle.cardCloseShadow(scheme: scheme), radius: 1.5, x: 0, y: 1)
            .shadow(color: HeadroomWidgetStyle.cardAmbientShadow(scheme: scheme), radius: scheme == .dark ? 11 : 6, x: 0, y: scheme == .dark ? 9 : 3)
            .shadow(color: HeadroomWidgetStyle.cardLongShadow(scheme: scheme), radius: 13, x: 0, y: 9)
    }
}

public extension View {
    func headroomWidgetLargeProviderCard() -> some View {
        modifier(HeadroomWidgetLargeProviderCardModifier())
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
