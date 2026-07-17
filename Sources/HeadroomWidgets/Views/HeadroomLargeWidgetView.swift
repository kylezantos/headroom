import HeadroomCore
import SwiftUI

struct HeadroomLargeWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(envelope.providers) { provider in
                    LargeProviderSection(provider: provider, now: now)
                        .largeProviderCard()
                }
            }
            Spacer(minLength: 0)
            // The full spend section (title + named rows) overflows the 360pt tile with two
            // provider cards above it, so spend gets the same one-line strip the medium
            // widget uses; the popover carries names, period, and status detail.
            if envelope.apiSpendProviders.isEmpty {
                if let updated {
                    Text(updated)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 8)
                }
            } else {
                WidgetAPISpendStrip(summaries: envelope.apiSpendProviders, now: now, footerText: updated)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    private var updated: String? {
        Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now).map { "from Mac · \($0)" }
    }
}

private struct LargeProviderSection: View {
    let provider: WidgetProviderSummary
    let now: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            WidgetUsageMeter(window: window(.weekly), fallbackLabel: "Weekly", now: now, showsResetInline: true, prominent: true)
            WidgetUsageMeter(window: window(.fiveHour), fallbackLabel: "5-hour", now: now, showsResetInline: true, prominent: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            WidgetProviderIcon(providerID: provider.id, size: 20)
            Text(provider.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
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
                    .foregroundStyle(WidgetProviderStyle.severityColor(for: .low, scheme: scheme))
            }
        }
    }

    private func window(_ kind: WidgetWindowKind) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }

    private func extraLimitColor(_ window: WidgetWindowSummary) -> Color {
        switch window.severity {
        case .healthy:
            WidgetProviderStyle.secondaryText(scheme: scheme)
        case .low, .critical:
            WidgetProviderStyle.severityColor(for: window.severity, scheme: scheme)
        }
    }
}
