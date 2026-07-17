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
                .padding(expandedContentMargins)
        }
        .overlay(alignment: .topTrailing) {
            if isDemoMode {
                Text("DEMO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.tint, in: Capsule())
                    .padding(contentMargins)
                    .accessibilityLabel("Demo data")
            }
        }
        .containerBackground(for: .widget) {
            HeadroomWidgetContainerBackground()
        }
        .widgetURL(URL(string: "headroom://usage"))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// WidgetKit's stock margins are deliberately generous. Reclaim four points on the
    /// top and horizontal edges so the usage cards occupy more of the iPhone widget while
    /// preserving the system bottom inset for the trailing freshness label.
    private var expandedContentMargins: EdgeInsets {
        let reduction: CGFloat = 4
        return EdgeInsets(
            top: max(0, contentMargins.top - reduction),
            leading: max(0, contentMargins.leading - reduction),
            bottom: contentMargins.bottom,
            trailing: max(0, contentMargins.trailing - reduction)
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        switch entry.state {
        case .demo(let envelope):
            content(envelope)
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

    private var isDemoMode: Bool {
        if case .demo = entry.state { true } else { false }
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

    // Mirrors `HeadroomSmallWidgetView`: a "Weekly left" header over one line per provider
    // (the overall weekly window). Quota-only and footer-free so the small family stays
    // glanceable. Model-specific sub-limits (Claude's "Weekly (Fable)") are detail for the
    // large family and the popover; at this size a third line reads as a phantom provider.
    private func small(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weekly left")
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
            ForEach(envelope.providers) { provider in
                providerWeeklyLine(provider)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the meters have room to breathe.
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
    }

    // One prominent weekly line per provider — brand mark + name + percent + bar for the
    // provider's overall weekly window (mirrors macOS `WidgetProviderWeeklyLine`). Dims
    // when that window is missing rather than dropping the row.
    private func providerWeeklyLine(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                HeadroomWidgetProviderIcon(providerID: provider.id, size: 16)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(percent(provider.weeklyWindow))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(provider.weeklyWindow == nil ? HeadroomWidgetStyle.secondaryText(scheme: scheme) : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 42, alignment: .trailing)
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
                mediumFooter(generatedAt: envelope.generatedAt, prefix: freshnessPrefix)
            } else {
                mediumProviderColumns(envelope.providers)
                Spacer(minLength: 6)
                // Same shared strip as the large widget; the footer drops its freshness
                // prefix here because the medium tile's width carries icons + amounts too.
                HeadroomWidgetAPISpendStrip(
                    summaries: envelope.apiSpendProviders,
                    now: entry.date,
                    footerText: Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date)
                )
            }
        }
        // KTD1: rely on WidgetKit's default content margins for the outer margin;
        // keep only a small residual so the two-column meters do not feel cramped.
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func mediumFooter(generatedAt: Date, prefix: String) -> some View {
        if let updated = Countdown.updatedLabel(capturedAt: generatedAt, now: entry.date) {
            Text("\(prefix)\(updated)")
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
            if let fiveHourWindow = window(.fiveHour, in: provider) {
                HeadroomWidgetUsageMeter(window: fiveHourWindow, fallbackLabel: "5-hour", compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Large

    // Mirrors `HeadroomLargeWidgetView`: provider cards, an optional API-spend section,
    // and a trailing freshness footer. No "Usage"
    // title or app-icon mark (R3).
    private func large(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(envelope.providers) { provider in
                    largeProviderSection(provider)
                        .headroomWidgetLargeProviderCard()
                }
            }
            Spacer(minLength: 0)
            // The full spend section (title + named rows) overflows the large tile with two
            // provider cards above it, so spend gets the same one-line strip the medium
            // widget uses; the companion app carries names, period, and status detail.
            if envelope.apiSpendProviders.isEmpty {
                if let updated = largeFooterText(envelope) {
                    Text(updated)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 8)
                }
            } else {
                HeadroomWidgetAPISpendStrip(
                    summaries: envelope.apiSpendProviders,
                    now: entry.date,
                    footerText: largeFooterText(envelope)
                )
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    private func largeFooterText(_ envelope: WidgetSnapshotEnvelope) -> String? {
        Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date).map { "\(freshnessPrefix)\($0)" }
    }

    private func largeProviderSection(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            largeSectionHeader(provider)
            HeadroomWidgetUsageMeter(window: window(.weekly, in: provider), fallbackLabel: "Weekly", now: entry.date, showsResetInline: true, prominent: true)
            if let fiveHourWindow = window(.fiveHour, in: provider) {
                HeadroomWidgetUsageMeter(window: fiveHourWindow, fallbackLabel: "5-hour", now: entry.date, showsResetInline: true, prominent: true)
            }
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
            Spacer(minLength: 4)
            if let extraWindow = provider.limitingExtraWeeklyWindow {
                Text("\(extraWindow.compactLabel) \(extraWindow.roundedPercentRemaining)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(extraLimitColor(extraWindow))
                    .lineLimit(1)
                    .accessibilityLabel("\(extraWindow.compactLabel) limit, \(extraWindow.roundedPercentRemaining) percent left")
            }
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

    private func extraLimitColor(_ window: WidgetWindowSummary) -> Color {
        switch window.severity {
        case .healthy:
            HeadroomWidgetStyle.secondaryText(scheme: scheme)
        case .low, .critical:
            HeadroomWidgetStyle.severityColor(for: window.severity, scheme: scheme)
        }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private var freshnessPrefix: String {
        isDemoMode ? "sample · " : "from Mac · "
    }
}
