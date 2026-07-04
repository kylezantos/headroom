import HeadroomCore
import SwiftUI

struct HeadroomLargeWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Headroom")
                    .font(.headline)
                Spacer()
                Text(Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) ?? "")
                    .font(.caption)
                    .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
            }
            ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                LargeProviderSection(provider: provider, now: now)
                if index < envelope.providers.count - 1 {
                    Rectangle()
                        .fill(WidgetProviderStyle.hairline(scheme: scheme))
                        .frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct LargeProviderSection: View {
    let provider: WidgetProviderSummary
    let now: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WidgetProviderIcon(providerID: provider.id, size: 16)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                if let planLabel = provider.planLabel {
                    Text(planLabel)
                        .font(.system(size: 9, weight: .semibold))
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
                        .foregroundStyle(WidgetProviderStyle.severityColor(for: .low))
                }
            }
            WidgetUsageMeter(window: window(.weekly), fallbackLabel: "Weekly", now: now, showsResetInline: true)
            WidgetUsageMeter(window: window(.fiveHour), fallbackLabel: "5-hour", now: now, showsResetInline: true)
            if let renewalDate = provider.renewalDate {
                Text("Renews \(renewalDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2)
                    .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func window(_ kind: WidgetWindowKind) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }
}
