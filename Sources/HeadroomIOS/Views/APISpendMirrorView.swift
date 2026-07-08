import SwiftUI

struct APISpendMirrorView: View {
    let summaries: [WidgetAPISpendSummary]
    let now: Date
    var entranceDelay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("API Spend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 8)
                if let periodLabel = summaries.first?.periodLabel {
                    Text(periodLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HeadroomTheme.tertiaryText(scheme))
                        .lineLimit(1)
                }
            }

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
    }

    private func spendRow(_ summary: WidgetAPISpendSummary) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ProviderLogoView(providerID: summary.id, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                statusLine(summary)
            }
            Spacer(minLength: 8)
            amountView(summary)
        }
    }

    @ViewBuilder private func statusLine(_ summary: WidgetAPISpendSummary) -> some View {
        if let status = APISpendPresentation.statusText(
            freshness: summary.freshness,
            capturedAt: summary.capturedAt,
            now: now
        ) {
            HStack(spacing: 6) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(statusColor(for: summary.freshness))
                    .lineLimit(1)
                if case .stale(let message, _) = summary.freshness {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(HeadroomTheme.tertiaryText(scheme))
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private func amountView(_ summary: WidgetAPISpendSummary) -> some View {
        if let amount = APISpendPresentation.amountText(summary) {
            Text(amount)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(summary.freshness == .live ? .primary : HeadroomTheme.secondaryText(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
        } else {
            Text("—")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusColor(for freshness: WidgetProviderFreshness) -> Color {
        switch freshness {
        case .pending:
            HeadroomTheme.tertiaryText(scheme)
        case .live:
            HeadroomTheme.tertiaryText(scheme)
        case .stale(_, let needsAttention):
            needsAttention ? HeadroomTheme.severityColor(for: .low, scheme: scheme) : HeadroomTheme.secondaryText(scheme)
        }
    }
}
