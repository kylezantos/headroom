import HeadroomCore
import SwiftUI

struct WidgetAPISpendCompactRow: View {
    let summaries: [WidgetAPISpendSummary]
    let now: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(summaries) { summary in
                compactItem(summary)
            }
        }
    }

    private func compactItem(_ summary: WidgetAPISpendSummary) -> some View {
        HStack(spacing: 4) {
            WidgetProviderIcon(providerID: summary.id, size: 11)
            Text(APISpendPresentation.amountText(summary) ?? "—")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(amountColor(summary))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            if summary.freshness.needsAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetProviderStyle.severityColor(for: .low, scheme: scheme))
            }
        }
        .layoutPriority(1)
    }

    private func amountColor(_ summary: WidgetAPISpendSummary) -> Color {
        APISpendPresentation.amountText(summary) == nil || summary.freshness != .live
            ? WidgetProviderStyle.secondaryText(scheme: scheme)
            : .primary
    }
}

struct WidgetAPISpendSection: View {
    let summaries: [WidgetAPISpendSummary]
    let now: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("API Spend")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                if let periodLabel = summaries.first?.periodLabel {
                    Text(periodLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                }
            }
            ForEach(summaries) { summary in
                HStack(spacing: 7) {
                    WidgetProviderIcon(providerID: summary.id, size: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WidgetProviderStyle.textAccent(for: summary.id, scheme: scheme))
                            .lineLimit(1)
                        if !detailText(summary).isEmpty {
                            Text(detailText(summary))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(APISpendPresentation.amountText(summary) ?? "—")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(amountColor(summary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                }
            }
        }
    }

    private func detailText(_ summary: WidgetAPISpendSummary) -> String {
        switch summary.freshness {
        case .pending, .stale:
            return APISpendPresentation.statusText(freshness: summary.freshness, capturedAt: summary.capturedAt, now: now) ?? ""
        case .live:
            return ""
        }
    }

    private func amountColor(_ summary: WidgetAPISpendSummary) -> Color {
        APISpendPresentation.amountText(summary) == nil || summary.freshness != .live
            ? WidgetProviderStyle.secondaryText(scheme: scheme)
            : .primary
    }
}
