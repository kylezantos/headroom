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
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
            ForEach(envelope.weeklyProviders) { provider in
                providerWeeklyLine(provider)
            }
            Spacer(minLength: 0)
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) {
                Text("from Mac / \(updated)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
            }
        }
        .padding(12)
    }

    private func medium(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Headroom")
                    .font(.headline)
                Spacer()
                Text(Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) ?? "")
                    .font(.caption2)
                    .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
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
        .padding(12)
    }

    private func large(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Headroom")
                    .font(.headline)
                Spacer()
                Text(Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) ?? "")
                    .font(.caption)
                    .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
            }
            ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                providerSection(provider)
                if index < envelope.providers.count - 1 {
                    Rectangle()
                        .fill(IOSWidgetStyle.hairline(scheme: scheme))
                        .frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func providerWeeklyLine(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                providerIcon(provider.id, size: 13)
                Text(provider.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(IOSWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(percent(provider.weeklyWindow))
                    .font(.callout.bold().monospacedDigit())
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

    private func providerSection(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                providerIcon(provider.id, size: 16)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
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
            }
            IOSWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", now: entry.date, showsResetInline: true)
            IOSWidgetUsageMeter(window: window(.fiveHour, in: provider), fallbackLabel: "5-hour", now: entry.date, showsResetInline: true)
            if let renewalDate = provider.renewalDate {
                Text("Renews \(renewalDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2)
                    .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
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
        if let assetName = assetName(for: id) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol(for: id))
                .resizable()
                .scaledToFit()
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

private struct IOSWidgetUsageMeter: View {
    let window: WidgetWindowSummary?
    let fallbackLabel: String
    var now: Date?
    var showsResetInline = false
    var compact = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window?.label ?? fallbackLabel)
                    .font(compact ? .caption2.weight(.medium) : .caption)
                    .foregroundStyle(IOSWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                if let resetText {
                    Text("/ \(resetText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(IOSWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 2)
                Text(percentText)
                    .font((compact ? Font.caption2 : Font.caption).bold().monospacedDigit())
                    .foregroundStyle(window == nil ? IOSWidgetStyle.secondaryText(scheme: scheme) : .primary)
            }
            IOSWidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil
            )
        }
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
        .frame(height: 6)
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
        switch severity {
        case .healthy: return Color(HeadroomSeverityColorValues.healthy)
        case .low: return Color(HeadroomSeverityColorValues.low)
        case .critical: return Color(HeadroomSeverityColorValues.critical)
        }
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
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
