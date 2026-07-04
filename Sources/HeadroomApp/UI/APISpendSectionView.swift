import SwiftUI
import HeadroomCore

struct APISpendSectionView: View {
    var store: UsageStore
    let now: Date
    let onOpenSettings: () -> Void

    var body: some View {
        let ids = store.apiSpendProviderOrder
        if !ids.isEmpty {
            // One raised panel with the header inside and hairline-separated rows — mirrors
            // the settings "API Spend" panel so the two surfaces share one language.
            VStack(alignment: .leading, spacing: 10) {
                Text("API Spend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                VStack(spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        if index > 0 {
                            Divider().overlay(Color.primary.opacity(0.08))
                                .padding(.vertical, 4)
                        }
                        spendRow(store.apiSpendSnapshot(for: id))
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(12)
            .raisedTile(cornerRadius: 12)
            .padding(.top, 2)
        }
    }

    @ViewBuilder private func spendRow(_ snapshot: APISpendSnapshot) -> some View {
        HStack(alignment: .center, spacing: 9) {
            ProviderLogoView(providerID: snapshot.providerID, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snapshot.displayName)
                        .font(.caption.weight(.medium))
                    Text(snapshot.periodLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                statusLine(snapshot)
            }
            Spacer(minLength: 8)
            amountView(snapshot)
        }
    }

    @ViewBuilder private func statusLine(_ snapshot: APISpendSnapshot) -> some View {
        switch snapshot.freshness {
        case .pending:
            Text("Waiting for cost data")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .live:
            if let updated = Countdown.updatedLabel(capturedAt: snapshot.capturedAt, now: now) {
                Text("Updated \(updated)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .stale(let reason):
            HStack(spacing: 6) {
                Text(reason.isPermanent ? "Needs setup" : "Stale")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(reason.isPermanent ? .orange : .secondary)
                Text(reason.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private func amountView(_ snapshot: APISpendSnapshot) -> some View {
        if let amount = snapshot.amount, let currency = snapshot.currency {
            Text(Self.format(amount: amount, currency: currency))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(snapshot.freshness == .live ? .primary : .secondary)
        } else {
            Button("Add key", action: onOpenSettings)
                .buttonStyle(HoverButtonStyle(horizontalPadding: 7, verticalPadding: 3))
                .font(.caption2)
        }
    }

    private static func format(amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency.uppercased()) \(String(format: "%.2f", amount))"
    }
}
