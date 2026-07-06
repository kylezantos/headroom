import HeadroomCore
import SwiftUI

struct HeadroomLargeWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    // Shared by the tiles (their horizontal inset) and the footer (its trailing inset),
    // so the timestamp lines up with the % column instead of hugging the corner radius.
    private let tileInset: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Usage")
                    .font(.system(size: 19, weight: .semibold))
                Spacer(minLength: 0)
                WidgetAppIconMark(size: 20)
            }
            ForEach(envelope.providers) { provider in
                LargeProviderTile(provider: provider, now: now, inset: tileInset)
            }
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) {
                Text("from Mac · \(updated)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, tileInset)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

private struct LargeProviderTile: View {
    let provider: WidgetProviderSummary
    let now: Date
    var inset: CGFloat = 12

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            WidgetUsageMeter(window: window(.weekly), fallbackLabel: "Weekly", now: now, showsResetInline: true, prominent: true)
            WidgetUsageMeter(window: window(.fiveHour), fallbackLabel: "5-hour", now: now, showsResetInline: true, prominent: true)
            ForEach(provider.extraCounterWindows) { window in
                WidgetUsageMeter(window: window, fallbackLabel: window.label, now: now, showsResetInline: true, prominent: true)
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetTile()
    }

    private var header: some View {
        HStack(spacing: 6) {
            WidgetProviderIcon(providerID: provider.id, size: 20)
            Text(provider.displayName)
                .font(.system(size: 15, weight: .semibold))
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
            if let renewalDate = provider.renewalDate {
                Text("Renews \(renewalDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
            }
        }
    }

    private func window(_ kind: WidgetWindowKind) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }
}
