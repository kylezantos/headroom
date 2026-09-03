import SwiftUI

struct APISpendMirrorView: View {
    let summaries: [WidgetAPISpendSummary]
    let now: Date
    var entranceDelay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("API Spend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                .textCase(.uppercase)
                .tracking(0.4)

            VStack(spacing: 0) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 {
                        Divider()
                            .overlay(HeadroomTheme.hairline(scheme))
                            .padding(.vertical, 8)
                    }
                    spendRow(summary)
                }
            }
        }
        .padding(17)
        .headroomTile()
        .opacity(reduceMotion || appeared ? 1 : 0)
        .offset(y: reduceMotion || appeared ? 0 : 10)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(HeadroomTheme.entranceAnimation.delay(entranceDelay)) {
                    appeared = true
                }
            }
        }
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
                .foregroundStyle(HeadroomTheme.tertiaryText(scheme))
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
                .foregroundStyle(summary.freshness == .live ? .primary : HeadroomTheme.secondaryText(scheme))
                .privacySensitive()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
        } else {
            Text("—")
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Tone comes from the same Core mapping that chose the badge text, so a rejected key
    /// reads as critical here and as warning-only on a merely missing one.
    private func statusColor(for summary: WidgetAPISpendSummary) -> Color {
        let tone = APISpendPresentation.rowStatus(
            freshness: summary.freshness,
            attention: summary.attention,
            displayName: summary.displayName
        ).tone
        switch tone {
        case .quiet:
            return HeadroomTheme.tertiaryText(scheme)
        case .neutral:
            return HeadroomTheme.secondaryText(scheme)
        case .warning:
            return HeadroomTheme.severityColor(for: .low, scheme: scheme)
        case .critical:
            return HeadroomTheme.severityColor(for: .critical, scheme: scheme)
        }
    }
}
