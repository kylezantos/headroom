import HeadroomCore
import SwiftUI

struct WidgetProviderRow: View {
    let provider: WidgetProviderSummary
    let showsDetails: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WidgetProviderIcon(providerID: provider.id, size: 16)
                Text(provider.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(WidgetProviderStyle.accent(for: provider.id))
                Spacer()
                if provider.freshness.needsAttention {
                    Label("Check", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                WidgetUsageMeter(window: provider.subscriptionWindows.first { $0.kind == .weekly }, fallbackLabel: "Weekly")
                WidgetUsageMeter(window: provider.subscriptionWindows.first { $0.kind == .fiveHour }, fallbackLabel: "5h")
            }
            if showsDetails {
                WidgetProviderDetails(provider: provider, now: now)
            }
        }
    }
}

private struct WidgetProviderDetails: View {
    let provider: WidgetProviderSummary
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(provider.subscriptionWindows) { window in
                Text("\(window.label): \(window.resetLabel ?? Countdown.string(to: window.resetsAt, now: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let renewalDate = provider.renewalDate {
                Text("Renews \(renewalDate, format: .dateTime.month(.abbreviated).day())")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
