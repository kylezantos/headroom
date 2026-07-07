import SwiftUI
import WidgetKit

struct HeadroomIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeadroomIOSWidgetEntry

    var body: some View {
        Group {
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
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "headroom://usage"))
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

    private func small(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
            ForEach(envelope.weeklyProviders) { provider in
                providerWeeklyLine(provider)
            }
            Spacer(minLength: 0)
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) {
                Text("from Mac · \(updated)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
            }
        }
        // KTD1: system content margins carry the ~14pt effective outer margin; keep only
        // a minimal residual. Tune against the widget gallery.
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private func medium(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Usage")
                    .font(.headline)
                Spacer(minLength: 0)
                if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) {
                    Text(updated)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
                        .lineLimit(1)
                }
                IOSWidgetAppIconMark(size: 18)
            }
            if envelope.providers.count <= 1 {
                ForEach(envelope.providers) { provider in
                    providerColumn(provider)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                        providerColumn(provider)
                        if index < envelope.providers.count - 1 {
                            Rectangle()
                                .fill(IOSWidgetStyle.hairline(scheme: scheme))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        // KTD1: lean on WidgetKit's default content margins for the ~16pt effective
        // outer margin; keep only a minimal residual. Tune against the widget gallery.
        .padding(2)
    }

    private func large(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Usage")
                    .font(.system(size: 19, weight: .semibold))
                Spacer(minLength: 0)
                IOSWidgetAppIconMark(size: 20)
            }
            ForEach(envelope.providers) { provider in
                largeProviderTile(provider)
            }
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) {
                Text("from Mac · \(updated)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, largeTileInset)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // Shared by the tiles (their horizontal inset) and the footer (its trailing inset),
    // so the timestamp lines up with the % column instead of hugging the corner radius.
    private var largeTileInset: CGFloat { 12 }

    private func largeProviderTile(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
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
                        .foregroundStyle(IOSWidgetStyle.severityColor(for: .low))
                }
                if let renewalDate = provider.renewalDate {
                    Text("Renews \(renewalDate.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.system(size: 11))
                        .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                }
            }
            IOSWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", now: entry.date, showsResetInline: true, prominent: true)
            IOSWidgetUsageMeter(window: window(.fiveHour, in: provider), fallbackLabel: "5-hour", now: entry.date, showsResetInline: true, prominent: true)
        }
        .padding(.horizontal, largeTileInset)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .modifier(IOSWidgetTile())
    }

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

    private func providerColumn(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                providerIcon(provider.id, size: 15)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IOSWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if provider.freshness.needsAttention {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(IOSWidgetStyle.severityColor(for: .low))
                }
            }
            IOSWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", compact: true)
            IOSWidgetUsageMeter(window: window(.fiveHour, in: provider), fallbackLabel: "5-hour", compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func window(_ kind: WidgetWindowKind, in provider: WidgetProviderSummary) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private func symbol(for id: String) -> String {
        id == ProviderID.claude.raw ? "sparkles" : "terminal"
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

    @Environment(\.colorScheme) private var scheme
}

/// Mirror of the macOS `WidgetAppIconMark` (U1) so the medium/large iOS widget headers
/// carry the same rounded app-icon mark. Source art is the shared `AppIconMark` imageset;
/// rounding uses the `size * 0.22` continuous-corner recipe from `HeadroomAppIconView` (R2).
private struct IOSWidgetAppIconMark: View {
    var size: CGFloat = 18

    var body: some View {
        Image("AppIconMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: size * 0.16, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

private struct IOSWidgetUsageMeter: View {
    let window: WidgetWindowSummary?
    let fallbackLabel: String
    var now: Date?
    var showsResetInline = false
    var compact = false
    // The large widget's tiles read as a premium surface, so their meters get bumped
    // type and a taller bar than the medium/small families.
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
                    .fill(dimmed ? IOSWidgetStyle.secondaryText(scheme: scheme) : IOSWidgetStyle.severityColor(for: severity))
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

    static func textAccent(for id: String, scheme: ColorScheme) -> Color {
        switch (id, scheme) {
        case (ProviderID.claude.raw, .light): Color(red: 0.74, green: 0.36, blue: 0.13)
        case (ProviderID.claude.raw, .dark): Color(red: 0.91, green: 0.56, blue: 0.41)
        case (ProviderID.codex.raw, .light): Color(red: 0.20, green: 0.25, blue: 0.84)
        case (ProviderID.codex.raw, .dark): Color(red: 0.59, green: 0.63, blue: 1.00)
        default: .secondary
        }
    }

    static func severityColor(for severity: WidgetUsageSeverity) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity))
    }

    static func secondaryText(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.66) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.74)
    }

    static func tertiaryText(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.44) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.55)
    }

    static func barTrack(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)
    }

    static func hairline(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.09)
    }

    // Elevated tile surface for the large widget's provider cards. Light mode sits the
    // white card on the white widget background (defined purely by ring + ambient
    // shadow); dark mode lifts it a step above the near-black container.
    static func tileSurface(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.15) : .white
    }

    // The ring layer that replaces a border (KTD/Jakub elevation): a hairline in light,
    // a faint top-lit glow in dark.
    static func tileRing(scheme: ColorScheme) -> AnyShapeStyle {
        scheme == .dark
            ? AnyShapeStyle(LinearGradient(
                colors: [.white.opacity(0.14), .white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom))
            : AnyShapeStyle(Color.black.opacity(0.05))
    }
}

/// Elevated provider-tile surface for the iOS large widget. In accented/Liquid Glass
/// rendering, skip the opaque fill so WidgetKit does not flatten the tile into a mask.
private struct IOSWidgetTile: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background {
                if renderingMode == .fullColor {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(IOSWidgetStyle.tileSurface(scheme: scheme))
                        .shadow(color: ambient, radius: scheme == .dark ? 10 : 8, x: 0, y: scheme == .dark ? 8 : 4)
                        .shadow(color: ambientTight, radius: 2, x: 0, y: 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tileRing, lineWidth: 1)
            }
    }

    private var tileRing: AnyShapeStyle {
        renderingMode == .fullColor
            ? IOSWidgetStyle.tileRing(scheme: scheme)
            : AnyShapeStyle(IOSWidgetStyle.hairline(scheme: scheme))
    }

    private var ambient: Color { scheme == .dark ? .black.opacity(0.38) : .black.opacity(0.05) }
    private var ambientTight: Color { scheme == .dark ? .black.opacity(0.20) : .black.opacity(0.06) }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
