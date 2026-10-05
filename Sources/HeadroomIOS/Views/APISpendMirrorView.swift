import SwiftUI

struct APISpendMirrorView: View {
    let summaries: [WidgetAPISpendSummary]
    let now: Date

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("API Spend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                .textCase(.uppercase)
                .tracking(0.4)

            VStack(spacing: 0) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 {
                        Divider()
                            .overlay(Color(styleTint: HeadroomWidgetColorValues.hairline(dark: scheme == .dark)))
                            .padding(.vertical, 8)
                    }
                    spendRow(summary)
                }
            }
        }
        .padding(17)
        .headroomTile()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("headroom.api-spend")
    }

    @ViewBuilder private func spendRow(_ summary: WidgetAPISpendSummary) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                titleLine(summary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    statusLine(summary)
                    Spacer(minLength: 8)
                    amountView(summary)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    titleLine(summary)
                    statusLine(summary)
                }
                Spacer(minLength: 8)
                amountView(summary)
                    .layoutPriority(1)
            }
        }
    }

    private func titleLine(_ summary: WidgetAPISpendSummary) -> some View {
        let contextLabel = APISpendPresentation.contextLabel(
            kind: summary.semanticKind,
            periodLabel: summary.periodLabel
        )

        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(summary.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("· \(contextLabel)")
                .font(.caption.weight(.medium))
                .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
        }
    }

    @ViewBuilder private func statusLine(_ summary: WidgetAPISpendSummary) -> some View {
        if let status = APISpendPresentation.companionStatusText(
            freshness: summary.freshness,
            attention: summary.attention
        ) {
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor(for: summary))
                .lineLimit(1)
        }
    }

    @ViewBuilder private func amountView(_ summary: WidgetAPISpendSummary) -> some View {
        if let amount = APISpendPresentation.amountText(summary) {
            Text(amount)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(summary.freshness == .live ? .primary : ProviderStyle.secondaryText(scheme: scheme))
                .privacySensitive()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
        } else {
            Text("—")
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Tone comes from the same Core mapping that chose the badge text, so a rejected key
    /// reads as critical here and as warning-only on a merely missing one. U8 (P40, R4):
    /// the warning tone is the neutral attention ink now, never the meters' amber; U21
    /// replaces this view with the shared spend rows.
    private func statusColor(for summary: WidgetAPISpendSummary) -> AnyShapeStyle {
        let tone = APISpendPresentation.rowStatus(
            freshness: summary.freshness,
            attention: summary.attention,
            providerID: ProviderID(summary.id),
            displayName: summary.displayName,
            kind: summary.semanticKind
        ).tone
        return StatusSentenceSeverity.forSpendTone(tone).ink(scheme: scheme)
    }
}
