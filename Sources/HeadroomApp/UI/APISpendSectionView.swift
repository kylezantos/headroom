import SwiftUI
import AppKit
import HeadroomCore

struct APISpendSectionView: View {
    @Environment(\.colorScheme) private var scheme
    var store: UsageStore
    let now: Date
    let onOpenSettings: () -> Void

    var body: some View {
        let ids = store.apiSpendProviderOrder
        if !ids.isEmpty {
            // One raised panel with the header inside and hairline-separated rows — mirrors
            // the settings "API Spend" panel so the two surfaces share one language.
            VStack(alignment: .leading, spacing: 9) {
                Text("API Spend")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                VStack(spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        if index > 0 {
                            Divider().overlay(Color.primary.opacity(0.08))
                                .padding(.vertical, 7)
                        }
                        spendRow(store.apiSpendSnapshot(for: id))
                    }
                }
                // L4B: amounts and separators stop 34pt from the tile's right edge,
                // level with the percentages in the provider cards above, so the
                // popover's right edge reads as one line.
                .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
            }
            // Padding matches the provider cards above, so sibling tiles share one
            // padding and radius.
            .padding(13)
            .raisedTile(cornerRadius: 10)
        }
    }

    @ViewBuilder private func spendRow(_ snapshot: APISpendSnapshot) -> some View {
        let contextLabel = APISpendPresentation.contextLabel(
            kind: snapshot.kind,
            periodLabel: store.apiSpendPeriod.displayLabel(now: now)
        )
        // Badge, sub-line and button title all come from one Core decision, so a rejected
        // key can no longer be badged "Needs setup" next to an "Add key" button.
        let status = APISpendPresentation.rowStatus(
            freshness: snapshot.freshness,
            providerID: snapshot.providerID,
            displayName: snapshot.displayName
        )

        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snapshot.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Text("· \(contextLabel)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                }
                // The live "Updated N min ago" sub-line is dropped — the popover header
                // already carries one consolidated stamp. Non-live states keep their
                // status line because it carries information the header does not (U2).
                if snapshot.freshness != .live {
                    statusLine(status)
                }
            }
            Spacer(minLength: 8)
            amountView(snapshot, status: status)
        }
    }

    @ViewBuilder private func statusLine(_ status: APISpendRowStatus) -> some View {
        HStack(spacing: 6) {
            if let badge = status.badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeColor(status.tone))
            }
            if let message = status.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(status.tone == .quiet ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
    }

    private func badgeColor(_ tone: APISpendRowStatus.Tone) -> Color {
        switch tone {
        case .quiet, .neutral:
            .secondary
        case .warning:
            ProviderStyle.severityColor(for: .low, scheme: scheme)
        case .critical:
            // Text ink, not the bar fill — the badge is small type on the tile surface.
            ProviderStyle.criticalText(scheme: scheme)
        }
    }

    /// Amount and action stack instead of sharing one line: at the popover's 384pt a
    /// "Replace key…" button beside the total would eat the width the status message needs,
    /// so the button takes its own trailing line and the amount stays where it was.
    @ViewBuilder private func amountView(_ snapshot: APISpendSnapshot, status: APISpendRowStatus) -> some View {
        let amount = APISpendPresentation.amountText(amount: snapshot.amount, currency: snapshot.currency)

        VStack(alignment: .trailing, spacing: 3) {
            if let amount {
                amountLine(snapshot, amount: amount)
            }
            // Continuity keeps the last total on screen after the key stops working; the
            // button follows the key problem, not the absence of an amount, so a retained
            // number beside "Key rejected" is no longer a dead end.
            if status.showsCTA(hasAmount: amount != nil), let callToAction = status.callToAction {
                Button(callToAction, action: onOpenSettings)
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 7, verticalPadding: 3))
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder private func amountLine(_ snapshot: APISpendSnapshot, amount: String) -> some View {
        HStack(spacing: 3) {
            Text(amount)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(snapshot.freshness == .live ? .primary : .secondary)
                .privacySensitive()
            if let qualifier = APISpendPresentation.qualifier(kind: snapshot.kind) {
                Text(qualifier)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            }
            // Quiet escape hatch to top up: opens the provider's billing page (the
            // screen with the actual "Buy credits" control) — we never run the
            // purchase ourselves. Bare glyph per the popover's control language;
            // hover pill announces clickability.
            if let url = APISpendPresentation.addCreditsURL(for: snapshot.providerID) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(HoverButtonStyle(
                    horizontalPadding: 0,
                    verticalPadding: 0,
                    hoverForegroundColor: ProviderStyle.textAccent(for: snapshot.providerID, scheme: scheme)
                ))
                .delayedHelp("Open \(snapshot.displayName) billing to add credits")
                .accessibilityLabel("Add \(snapshot.displayName) credits")
            }
        }
    }
}
