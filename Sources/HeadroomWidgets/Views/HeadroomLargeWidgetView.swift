import HeadroomCore
import SwiftUI

struct HeadroomLargeWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(envelope.providers) { provider in
                    LargeProviderSection(provider: provider, now: now)
                        .largeProviderCard()
                }
            }
            if !envelope.apiSpendProviders.isEmpty {
                Rectangle()
                    .fill(WidgetProviderStyle.hairline(scheme: scheme))
                    .frame(height: 1)
                    .padding(.vertical, 13)
                WidgetAPISpendSection(summaries: envelope.apiSpendProviders, now: now)
            }
            Spacer(minLength: 0)
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) {
                Text("from Mac · \(updated)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 13)
        .padding(.bottom, 12)
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
            if let planLabel = provider.planLabel {
                Text(planLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(WidgetProviderStyle.barTrack(scheme: scheme), in: Capsule())
            }
            Spacer(minLength: 4)
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
}
