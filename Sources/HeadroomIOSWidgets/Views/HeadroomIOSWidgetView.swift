import SwiftUI
import WidgetKit

/// iPhone Continuity widget. Mirrors the macOS widget composition (small/medium/large in
/// `Sources/HeadroomWidgets/Views`) so both families read identically (R1/R3); only the
/// platform-specific WidgetKit chrome — `.containerBackground` and `.widgetURL` — and the
/// shared color values (via `IOSWidgetStyle`) live on this side.
struct HeadroomIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetContentMargins) private var contentMargins
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: HeadroomIOSWidgetEntry

    var body: some View {
        ZStack {
            // The OS 26 Liquid Glass presentation composites a translucent sheen over the
            // `containerBackground` layer (bright at the widget's top edge, fading by
            // mid-tile — measured ~+28 RGB at top on both platforms), which made the top
            // provider card sit on a lighter surround than the bottom one. Content is not
            // veiled, so the background is drawn here in the content layer instead —
            // `contentMarginsDisabled` lets it bleed to the container edges, and the
            // system's own margins are re-applied around the actual content below. The
            // `containerBackground` copy remains for accented rendering and contexts that
            // strip backgrounds (StandBy / lock screen), where the system look should win.
            if showsContainerBackground && renderingMode == .fullColor {
                HeadroomWidgetContainerBackground()
            }
            stateContent
                .padding(contentMargins)
        }
        .containerBackground(for: .widget) {
            HeadroomWidgetContainerBackground()
        }
        .widgetURL(URL(string: "headroom://usage"))
    }

    @ViewBuilder
    private var stateContent: some View {
        switch entry.state {
        case .content(let envelope):
            content(envelope)
        case .disabled:
            IOSWidgetStatusView(title: "Sync Paused", message: "Enable iPhone sync on your Mac.")
        case .setupNeeded:
            IOSWidgetStatusView(title: "iCloud Needed", message: "Enable iCloud for Headroom.")
        case .waitingForMac:
            IOSWidgetStatusView(title: "Waiting for Mac", message: "Open Headroom on your Mac.")
        case .corrupt:
            IOSWidgetStatusView(title: "Unreadable Data", message: "Refresh Headroom on your Mac.")
        case .incompatibleSchema:
            IOSWidgetStatusView(title: "Update Needed", message: "Update Headroom on both devices.")
        }
    }

    @ViewBuilder
    private func content(_ envelope: WidgetSnapshotEnvelope) -> some View {
        switch family {
        case .systemSmall:
            small(envelope)
        case .systemMedium:
            medium(envelope)
        default:
            large(envelope)
        }
    }

    // MARK: - Small

    // Mirrors `HeadroomSmallWidgetView`: a "Weekly left" header over one line per
    // weekly-style window. Quota-only and footer-free so the small family stays glanceable
    // and can fit three weekly lines (R3).
    private func small(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weekly left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(envelope.providers) { provider in
                    let windows = provider.weeklyDisplayWindows
                    if windows.isEmpty {
                        providerWeeklyLine(provider)
                    } else {
                        ForEach(windows) { window in
                            smallWeeklyWindowLine(provider, window)
                        }
                    }
                }
            }
            .padding(.top, 9)
            Spacer(minLength: 0)
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the small family has room for three weekly lines.
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
    }

    private func smallLineTitle(_ provider: WidgetProviderSummary, _ window: WidgetWindowSummary) -> String {
        switch window.kind {
        case .weekly:
            return provider.displayName
        case .fiveHour:
            return window.label
        case .other:
            return window.label.replacingOccurrences(of: " weekly", with: "", options: .caseInsensitive)
        }
    }

    private func smallWeeklyWindowLine(_ provider: WidgetProviderSummary, _ window: WidgetWindowSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                providerIcon(provider.id, size: 12)
                Text(smallLineTitle(provider, window))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IOSWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text("\(Int(window.percentRemaining.rounded()))%")
                    .font(.system(size: 14).bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 36, alignment: .trailing)
            }
            IOSWidgetUsageBar(
                percentRemaining: window.percentRemaining,
                severity: window.severity
            )
        }
    }

    // Fallback for a provider with no weekly-style window: a compact line that dims when
    // the window is missing (mirrors macOS `WidgetProviderWeeklyLine`).
    private func providerWeeklyLine(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                providerIcon(provider.id, size: 12)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IOSWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(percent(provider.weeklyWindow))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(provider.weeklyWindow == nil ? IOSWidgetStyle.secondaryText(scheme: scheme) : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 36, alignment: .trailing)
            }
            IOSWidgetUsageBar(
                percentRemaining: provider.weeklyWindow?.percentRemaining ?? 0,
                severity: provider.weeklyWindow?.severity ?? .healthy,
                dimmed: provider.weeklyWindow == nil
            )
        }
    }

    // MARK: - Medium

    // Mirrors `HeadroomMediumWidgetView`: provider columns as the primary content, an
    // optional compact API-spend row under a hairline, and a freshness footer. No "Usage"
    // title or app-icon mark (R3).
    private func medium(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if envelope.apiSpendProviders.isEmpty {
                Spacer(minLength: 0)
                mediumProviderColumns(envelope.providers)
                Spacer(minLength: 0)
                mediumFooter(generatedAt: envelope.generatedAt, prefix: "from Mac · ")
            } else {
                mediumProviderColumns(envelope.providers)
                Spacer(minLength: 6)
                Rectangle()
                    .fill(IOSWidgetStyle.hairline(scheme: scheme))
                    .frame(height: 1)
                HStack(alignment: .center, spacing: 8) {
                    iosAPISpendCompactRow(envelope.apiSpendProviders)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    mediumFooter(generatedAt: envelope.generatedAt, prefix: "", fillsWidth: false)
                }
            }
        }
        // KTD1: rely on WidgetKit's default content margins for the outer margin;
        // keep only a small residual so the two-column meters do not feel cramped.
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func mediumFooter(generatedAt: Date, prefix: String, fillsWidth: Bool = true) -> some View {
        if let updated = Countdown.updatedLabel(capturedAt: generatedAt, now: entry.date) {
            Text("\(prefix)\(updated)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func mediumProviderColumns(_ providers: [WidgetProviderSummary]) -> some View {
        if providers.count <= 1 {
            ForEach(providers) { provider in
                providerColumn(provider)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    providerColumn(provider)
                    if index < providers.count - 1 {
                        Rectangle()
                            .fill(IOSWidgetStyle.hairline(scheme: scheme))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func providerColumn(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                providerIcon(provider.id, size: 18)
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IOSWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                if provider.freshness.needsAttention {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(IOSWidgetStyle.severityColor(for: .low, scheme: scheme))
                }
            }
            IOSWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", compact: true)
            IOSWidgetUsageMeter(window: window(.fiveHour, in: provider), fallbackLabel: "5-hour", compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Large

    // Mirrors `HeadroomLargeWidgetView`: provider cards, an optional API-spend section,
    // and a trailing freshness footer. No "Usage"
    // title or app-icon mark (R3).
    private func large(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(envelope.providers) { provider in
                    largeProviderSection(provider)
                        .largeProviderCard()
                }
            }
            if !envelope.apiSpendProviders.isEmpty {
                Rectangle()
                    .fill(IOSWidgetStyle.hairline(scheme: scheme))
                    .frame(height: 1)
                    .padding(.vertical, 13)
                iosAPISpendLargeSection(envelope.apiSpendProviders)
            }
            Spacer(minLength: 0)
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) {
                Text("from Mac · \(updated)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    private func largeProviderSection(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            largeSectionHeader(provider)
            IOSWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", now: entry.date, showsResetInline: true, prominent: true)
            IOSWidgetUsageMeter(window: window(.fiveHour, in: provider), fallbackLabel: "5-hour", now: entry.date, showsResetInline: true, prominent: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func largeSectionHeader(_ provider: WidgetProviderSummary) -> some View {
        HStack(spacing: 6) {
            providerIcon(provider.id, size: 20)
            Text(provider.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IOSWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                .lineLimit(1)
            if let planLabel = provider.planLabel {
                Text(planLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(IOSWidgetStyle.barTrack(scheme: scheme), in: Capsule())
            }
            Spacer(minLength: 4)
            if provider.freshness.needsAttention {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(IOSWidgetStyle.severityColor(for: .low, scheme: scheme))
            }
        }
    }

    // MARK: - API spend

    private func iosAPISpendCompactRow(_ summaries: [WidgetAPISpendSummary]) -> some View {
        HStack(spacing: 6) {
            ForEach(summaries) { summary in
                HStack(spacing: 4) {
                    providerIcon(summary.id, size: 11)
                    Text(APISpendPresentation.amountText(summary) ?? "—")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(apiAmountColor(summary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                    if summary.freshness.needsAttention {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(IOSWidgetStyle.severityColor(for: .low, scheme: scheme))
                    }
                }
                .layoutPriority(1)
            }
        }
    }

    private func iosAPISpendLargeSection(_ summaries: [WidgetAPISpendSummary]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("API Spend")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                if let periodLabel = summaries.first?.periodLabel {
                    Text(periodLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                }
            }
            ForEach(summaries) { summary in
                HStack(spacing: 7) {
                    providerIcon(summary.id, size: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(IOSWidgetStyle.textAccent(for: summary.id, scheme: scheme))
                            .lineLimit(1)
                        if !apiSpendDetailText(summary).isEmpty {
                            Text(apiSpendDetailText(summary))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(APISpendPresentation.amountText(summary) ?? "—")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(apiAmountColor(summary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                }
            }
        }
    }

    private func apiSpendDetailText(_ summary: WidgetAPISpendSummary) -> String {
        switch summary.freshness {
        case .pending, .stale:
            return APISpendPresentation.statusText(
                freshness: summary.freshness,
                capturedAt: summary.capturedAt,
                now: entry.date
            ) ?? ""
        case .live:
            return ""
        }
    }

    private func apiAmountColor(_ summary: WidgetAPISpendSummary) -> Color {
        APISpendPresentation.amountText(summary) == nil || summary.freshness != .live
            ? IOSWidgetStyle.secondaryText(scheme: scheme)
            : .primary
    }

    // MARK: - Helpers

    private func window(_ kind: WidgetWindowKind, in provider: WidgetProviderSummary) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private func symbol(for id: String) -> String {
        switch id {
        case ProviderID.claude.raw: "sparkle"
        case ProviderID.codex.raw: "chevron.left.forwardslash.chevron.right"
        default: "circle.dashed"
        }
    }

    @ViewBuilder
    private func providerIcon(_ id: String, size: CGFloat) -> some View {
        // Optical-size correction inside a fixed slot (shared via HeadroomCore) so Claude
        // and Codex read as equal weight, matching the app.
        let scale = CGFloat(HeadroomBrandMark.opticalScale(for: id))
        if let assetName = assetName(for: id) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size * scale, height: size * scale)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol(for: id))
                .resizable()
                .scaledToFit()
                .frame(width: size * scale, height: size * scale)
                .frame(width: size, height: size)
                .foregroundStyle(accent(for: id))
                .accessibilityHidden(true)
        }
    }

    private func assetName(for id: String) -> String? {
        switch id {
        case ProviderID.claude.raw: "ClaudeBrandIcon"
        case ProviderID.codex.raw: "CodexBrandIcon"
        default: nil
        }
    }

    private func accent(for id: String) -> Color {
        IOSWidgetStyle.accent(for: id)
    }
}

private struct IOSWidgetUsageMeter: View {
    let window: WidgetWindowSummary?
    let fallbackLabel: String
    var now: Date?
    var showsResetInline = false
    var compact = false
    // The large widget's sections read as premium, so their meters get bumped type and a
    // taller bar than the medium/small families.
    var prominent = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 5 : (compact ? 2 : 4)) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window?.label ?? fallbackLabel)
                    .font(labelFont)
                    .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                if let resetText {
                    Text("· \(resetText)")
                        .font(resetFont)
                        .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 2)
                Text(percentText)
                    .font(percentFont)
                    .foregroundStyle(window == nil ? IOSWidgetStyle.secondaryText(scheme: scheme) : .primary)
            }
            IOSWidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil,
                height: prominent ? 8 : 6
            )
        }
    }

    private var labelFont: Font {
        prominent ? .system(size: 13, weight: .medium) : (compact ? .system(size: 11, weight: .medium) : .caption)
    }

    private var resetFont: Font {
        prominent ? .system(size: 11).monospacedDigit() : .caption2.monospacedDigit()
    }

    private var percentFont: Font {
        // Medium (compact) percent reads at 14pt bold monospaced per the redesign (R3/KTD4).
        prominent ? .system(size: 16, weight: .bold).monospacedDigit() : (compact ? .system(size: 14, weight: .bold).monospacedDigit() : Font.caption.bold().monospacedDigit())
    }

    private var percentText: String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private var resetText: String? {
        guard let window, showsResetInline else { return nil }
        if let label = window.resetLabel { return label }
        guard let now else { return nil }
        if window.resetsAt <= now { return "Resets now" }
        return "Resets in \(Countdown.string(to: window.resetsAt, now: now))"
    }
}

private struct IOSWidgetUsageBar: View {
    let percentRemaining: Double
    let severity: WidgetUsageSeverity
    var dimmed = false
    var height: CGFloat = 6

    @Environment(\.colorScheme) private var scheme

    private var fraction: Double {
        min(1, max(0, percentRemaining / 100))
    }

    private func fillWidth(in availableWidth: Double) -> Double {
        guard fraction > 0 else { return 0 }
        return max(4, availableWidth * fraction)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(IOSWidgetStyle.barTrack(scheme: scheme))
                Capsule()
                    .fill(dimmed ? IOSWidgetStyle.secondaryText(scheme: scheme) : IOSWidgetStyle.severityColor(for: severity, scheme: scheme))
                    .frame(width: fillWidth(in: geo.size.width))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private enum IOSWidgetStyle {
    static func accent(for id: String) -> Color {
        switch id {
        case ProviderID.claude.raw: return Color(HeadroomBrandColorValues.claude)
        case ProviderID.codex.raw: return Color(HeadroomBrandColorValues.codex)
        default: return .secondary
        }
    }

    // R2: wraps the shared HeadroomWidgetColorValues so macOS and iOS cannot drift.
    static func textAccent(for id: String, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id, dark: scheme == .dark) else { return .secondary }
        return Color(rgb)
    }

    static func severityColor(for severity: WidgetUsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    static func secondaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark))
    }

    static func tertiaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark))
    }

    static func barTrack(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.barTrack(dark: scheme == .dark))
    }

    static func hairline(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.hairline(dark: scheme == .dark))
    }

    static func cardFill(scheme: ColorScheme) -> LinearGradient {
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

    static func cardRing(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileRing(dark: scheme == .dark))
    }

    static func cardTopRim(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileTopRim(dark: scheme == .dark))
    }

    static func cardEdgeShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileCloseShadow(dark: scheme == .dark))
    }

    static func cardCloseShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileAmbientShadow(dark: scheme == .dark))
    }

    static func cardAmbientShadow(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tileLongShadow(dark: scheme == .dark))
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

private struct IOSLargeProviderCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(cardShape)
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(IOSWidgetStyle.cardFill(scheme: scheme))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(IOSWidgetStyle.cardRing(scheme: scheme), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(IOSWidgetStyle.cardTopRim(scheme: scheme))
                    .frame(height: 1)
                    .padding(.horizontal, 7)
                    .allowsHitTesting(false)
            }
            .shadow(color: IOSWidgetStyle.cardEdgeShadow(scheme: scheme), radius: 1.5, x: 0, y: 1)
            .shadow(color: IOSWidgetStyle.cardCloseShadow(scheme: scheme), radius: scheme == .dark ? 11 : 6, x: 0, y: scheme == .dark ? 9 : 3)
            .shadow(color: IOSWidgetStyle.cardAmbientShadow(scheme: scheme), radius: 13, x: 0, y: 9)
    }
}

private extension View {
    func largeProviderCard() -> some View {
        modifier(IOSLargeProviderCardModifier())
    }
}
