import HeadroomCore
import SwiftUI

struct HeadroomMediumWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Headroom")
                .font(.headline)
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
        }
        .padding(12)
    }
}

private struct MediumProviderColumn: View {
    let provider: WidgetProviderSummary

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                WidgetProviderIcon(providerID: provider.id, size: 15)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
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
