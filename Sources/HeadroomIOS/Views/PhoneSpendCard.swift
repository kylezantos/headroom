import SwiftUI

/// U21 (P45–P53, KTD3): the popover's API spend card at phone scale — the shared
/// `APISpendRow` for every row, no eyebrow and no divider, on the phone's opaque tile. Every
/// decision a row shows comes from Core's `CompanionSpendRowModel`; the phone adds the
/// KTD3 chip fit and the surface's one dimming (KTD15).
struct PhoneSpendCard: View {
    let summaries: [WidgetAPISpendSummary]
    let surfaceDimmed: Bool
    /// CA-P3: the cards' shared clock, so a retried figure's tag says how old it is.
    let now: Date
    /// KTD3: the host's one `@ScaledMetric` factor.
    let scale: CGFloat

    var body: some View {
        let rows = summaries.map { CompanionSpendRowModel($0, now: now) }
        // Measured once per pass so every row reserves the same column and the amounts share
        // one right edge with each other and with the percentages above (S5A, R2C8).
        let amountWidth = APISpendRowMetrics.amountColumnWidth(for: rows.compactMap(\.amount), scale: scale)
        // CA-I5: the chip placement is decided once for the card, like the amount column
        // above: every row inline only when every row fits inline, otherwise every chip on a
        // subline, so the chips start at one x under their titles.
        ViewThatFits(in: .horizontal) {
            rowStack(rows, amountWidth: amountWidth, chipFit: .inline)
            rowStack(rows, amountWidth: amountWidth, chipFit: .subline)
        }
        .padding(PhoneCardMetrics.cardPadding * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .headroomTile()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("headroom.api-spend")
    }

    private func rowStack(
        _ rows: [CompanionSpendRowModel], amountWidth: CGFloat, chipFit: APISpendChipFit
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.rowGap(for: rows) * scale) {
            ForEach(rows) { row in
                APISpendRow(
                    snapshot: row.snapshot,
                    status: row.status,
                    title: row.title,
                    contextLabel: row.contextLabel,
                    amount: row.amount,
                    amountColumnWidth: amountWidth,
                    scale: scale,
                    chipFit: chipFit,
                    dimmed: surfaceDimmed,
                    mark: { ProviderLogoView(providerID: row.snapshot.providerID.raw, slot: $0) },
                    waitingLine: { message in
                        // P24: nothing on the phone is working, so a pending row waits in the
                        // quiet ink with no loading row beside it.
                        StatusSentence(text: message, severity: .quiet, scale: scale)
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("headroom.spend.\(row.id)")
            }
        }
    }

    /// SP1 (the popover's rhythm): bare one-line rows sit one card padding apart; once any
    /// row carries a sentence under it, rows are blocks and keep the account gap.
    private static func rowGap(for rows: [CompanionSpendRowModel]) -> CGFloat {
        let hasSentence = rows.contains { $0.snapshot.freshness != .live && $0.status.message != nil }
        return hasSentence ? PhoneCardMetrics.accountGap : PhoneCardMetrics.cardPadding
    }
}
