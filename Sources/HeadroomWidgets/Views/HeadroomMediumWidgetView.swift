import HeadroomCore
import SwiftUI

struct HeadroomMediumWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The two-column region flexes to fill the tile so the center rule reads as a
            // true column separator (full height, small symmetric inset) rather than a stub
            // tied to the text block. The footer / API-spend row sit below it either way.
            if envelope.apiSpendProviders.isEmpty {
                providerColumns
                footerText(prefix: "from Mac · ")
            } else {
                providerColumns
                Rectangle()
                    .fill(WidgetProviderStyle.hairline(scheme: scheme))
                    .frame(height: 1)
                HStack(alignment: .center, spacing: 8) {
                    WidgetAPISpendCompactRow(summaries: envelope.apiSpendProviders, now: now)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    footerText(prefix: "", fillsWidth: false)
                }
            }
        }
        // KTD1: rely on WidgetKit's default content margins for the outer margin;
        // keep only a small residual so the two-column meters do not feel cramped.
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    @ViewBuilder private var providerColumns: some View {
        if envelope.providers.count <= 1 {
            ForEach(envelope.providers) { provider in
                MediumProviderColumn(provider: provider)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(envelope.providers) { provider in
                    MediumProviderColumn(provider: provider)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay {
                // The column rule is drawn as a full-height overlay rather than an inline
                // sibling so it spans the entire two-column band — headers included — and
                // isn't pulled short by how each column's content distributes vertically.
                // Two equal-width columns with a symmetric gap put the tile's horizontal
                // centre inside that gap, so a centred 1pt rule lands cleanly between them.
                // Guarded to the 2-provider layout, which is the app's invariant.
                if envelope.providers.count == 2 {
                    Rectangle()
                        .fill(WidgetProviderStyle.hairline(scheme: scheme))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder private func footerText(prefix: String, fillsWidth: Bool = true) -> some View {
        if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) {
            Text("\(prefix)\(updated)")
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .trailing)
        }
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                if provider.freshness.needsAttention {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetProviderStyle.severityColor(for: .low, scheme: scheme))
                }
            }
            WidgetUsageMeter(window: window(.weekly), fallbackLabel: "Weekly", compact: true)
            WidgetUsageMeter(window: window(.fiveHour), fallbackLabel: "5-hour", compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func window(_ kind: WidgetWindowKind) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }
}
