import SwiftUI
import WidgetKit

/// iPhone Continuity widget. Mirrors the macOS widget composition (small/medium/large in
/// `Sources/HeadroomWidgets/Views`) so both families read identically (R1/R3); only the
/// platform-specific WidgetKit chrome — `.containerBackground` and `.widgetURL` — and the
/// shared color values (via `HeadroomWidgetStyle`) live on this side.
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
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
            ForEach(envelope.providers) { provider in
                let windows = provider.weeklyDisplayWindows
                if windows.isEmpty {
                    providerWeeklyLine(provider)
                        .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    ForEach(windows) { window in
                        smallWeeklyWindowLine(provider, window)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
            }
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
                HeadroomWidgetProviderIcon(providerID: provider.id, size: 16)
                Text(smallLineTitle(provider, window))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text("\(Int(window.percentRemaining.rounded()))%")
                    .font(.title3.bold().monospacedDigit())
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 42, alignment: .trailing)
            }
            HeadroomWidgetUsageBar(
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
                HeadroomWidgetProviderIcon(providerID: provider.id, size: 12)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(percent(provider.weeklyWindow))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(provider.weeklyWindow == nil ? HeadroomWidgetStyle.secondaryText(scheme: scheme) : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 36, alignment: .trailing)
            }
            HeadroomWidgetUsageBar(
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
                    .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
                    .frame(height: 1)
                HStack(alignment: .center, spacing: 8) {
                    HeadroomWidgetAPISpendCompactRow(summaries: envelope.apiSpendProviders, now: entry.date)
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
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
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
                            .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
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
                HeadroomWidgetProviderIcon(providerID: provider.id, size: 18)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                if provider.freshness.needsAttention {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .low, scheme: scheme))
                }
            }
            HeadroomWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", compact: true)
            HeadroomWidgetUsageMeter(window: window(.fiveHour, in: provider), fallbackLabel: "5-hour", compact: true)
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
                        .headroomWidgetLargeProviderCard()
                }
            }
            if !envelope.apiSpendProviders.isEmpty {
                Rectangle()
                    .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
                    .frame(height: 1)
                    .padding(.vertical, 13)
                HeadroomWidgetAPISpendSection(summaries: envelope.apiSpendProviders, now: entry.date)
            }
            Spacer(minLength: 0)
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) {
                Text("from Mac · \(updated)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
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
            HeadroomWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", now: entry.date, showsResetInline: true, prominent: true)
            HeadroomWidgetUsageMeter(window: window(.fiveHour, in: provider), fallbackLabel: "5-hour", now: entry.date, showsResetInline: true, prominent: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func largeSectionHeader(_ provider: WidgetProviderSummary) -> some View {
        HStack(spacing: 6) {
            HeadroomWidgetProviderIcon(providerID: provider.id, size: 20)
            Text(provider.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                .widgetAccentable()
                .lineLimit(1)
            if let planLabel = provider.planLabel {
                Text(planLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(HeadroomWidgetStyle.barTrack(scheme: scheme), in: Capsule())
            }
            Spacer(minLength: 4)
            if provider.freshness.needsAttention {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .low, scheme: scheme))
            }
        }
    }

    // MARK: - Helpers

    private func window(_ kind: WidgetWindowKind, in provider: WidgetProviderSummary) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }
}
