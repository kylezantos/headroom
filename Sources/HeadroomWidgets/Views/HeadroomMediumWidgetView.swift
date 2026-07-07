import HeadroomCore
import SwiftUI

struct HeadroomMediumWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if envelope.providers.count <= 1 {
                ForEach(envelope.providers) { provider in
                    MediumProviderColumn(provider: provider)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                        MediumProviderColumn(provider: provider)
                        if index < envelope.providers.count - 1 {
                            Rectangle()
                                .fill(WidgetProviderStyle.hairline(scheme: scheme))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) {
                Text("from Mac · \(updated)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // KTD1: rely on WidgetKit's default content margins for the outer margin;
        // keep only a small residual so the two-column meters do not feel cramped.
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }
}

private struct MediumProviderColumn: View {
    let provider: WidgetProviderSummary

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                WidgetProviderIcon(providerID: provider.id, size: 18)
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                if provider.freshness.needsAttention {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetProviderStyle.severityColor(for: .low))
                }
            }
            WidgetUsageMeter(window: window(.weekly), fallbackLabel: "Weekly", compact: true)
            WidgetUsageMeter(window: window(.fiveHour), fallbackLabel: "5-hour", compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func window(_ kind: WidgetWindowKind) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }
}
