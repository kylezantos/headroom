#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import HeadroomCore

struct APISpendSectionView: View {
    @Environment(\.colorScheme) private var scheme
    /// CMM8: which row's amount the pointer is over; the top-up glyph reveals only there.
    @State private var hoveredTopUp: ProviderID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var store: UsageStore
    let now: Date
    let onOpenSettings: () -> Void

    /// S5A/U3: the amount's size lives with the shared row (`APISpendRowMetrics`); the top-up
    /// glyph below is centred on it.
    private static let amountSize = APISpendRowMetrics.amountSize

    /// S5A: the top-up glyph lives in the identity row's 21pt trailing gutter, to the right
    /// of the amount — 3pt gap plus an 18pt slot. The slot is reserved on every row (empty
    /// where the provider has no billing page), so no amount shifts because its neighbour
    /// can be topped up and this one cannot.
    private static let topUpSlotSize: CGFloat = 18
    /// PB12: the glyph's own size, matched to the numerals it sits beside rather than to
    /// its slot.
    private static let topUpGlyphSize: CGFloat = 13

    var body: some View {
        let _ = BenchCounters.hit("APISpendSectionView")
        let models = rowModels()
        if !models.isEmpty {
            // Measured once per pass, not once per row: every row reads it (2026-10-03 perf bench).
            let amountWidth = APISpendRowMetrics.amountColumnWidth(for: models.compactMap(\.amount))
            // S5A: no eyebrow and no divider. The card now speaks the provider cards'
            // language — identity rows on the shared content axis, chunked by the same 22pt
            // gap the account sections use, inside the byte-identical tile.
            VStack(alignment: .leading, spacing: 0) {
                // CMM7 (Kyle, 2026-09-10): the spend card takes the usage cards' rhythm, on
                // the same 13pt padding and the same identity-row recipe.
                // SP1 (Kyle, 2026-09-24): 26 is the gap between two account *blocks*. Two
                // one-line rows 26 apart pitched 44pt against the meter rows' 31 and read as
                // pinned to the card's top and bottom edges. Bare rows now sit one padding
                // apart, so the card is evenly spaced; a row carrying a status sentence is a
                // block again and keeps the account gap.
                VStack(alignment: .leading, spacing: Self.rowGap(for: models)) {
                    ForEach(models) { model in
                        spendRow(model, amountWidth: amountWidth)
                    }
                }
                actionRow(models)
            }
            // Padding matches the provider cards above (`PopoverCardMetrics.cardPadding`), so
            // sibling tiles share one padding and radius.
            .padding(PopoverCardMetrics.cardPadding)
            .raisedTile(cornerRadius: 10)
        }
    }

    /// SP1: the card's 13pt padding between bare one-line rows; the accounts' 26pt block gap
    /// once any row carries a status sentence under it.
    private static func rowGap(for models: [SpendRowModel]) -> CGFloat {
        let hasSentence = models.contains { $0.snapshot.freshness != .live && $0.status.message != nil }
        return hasSentence ? 26 : 13
    }

    // MARK: - Row model

    /// One row's Core decisions resolved once, so the card foot can ask which rows want a
    /// button without re-deriving every status a second time.
    private struct SpendRowModel: Identifiable {
        let snapshot: APISpendSnapshot
        let status: APISpendRowStatus
        /// The popover's own title (X5): Core's `displayName` minus any trailing qualifier
        /// that the chip now carries.
        let title: String
        let contextLabel: String
        let amount: String?

        var id: ProviderID { snapshot.providerID }
        var showsCTA: Bool { status.showsCTA(hasAmount: amount != nil) }
    }

    /// The period label is the same for every row, and formatting it is a date format, so it
    /// is resolved once per pass here rather than inside each row (2026-10-03 perf bench).
    private func rowModels() -> [SpendRowModel] {
        let order = store.apiSpendProviderOrder
        guard !order.isEmpty else { return [] }
        let periodLabel = store.apiSpendPeriod.displayLabel(now: now)
        return order.map { rowModel(for: $0, periodLabel: periodLabel) }
    }

    private func rowModel(for id: ProviderID, periodLabel: String) -> SpendRowModel {
        let snapshot = store.apiSpendSnapshot(for: id)
        let identity = APISpendPresentation.popoverIdentity(displayName: snapshot.displayName)
        let context = APISpendPresentation.contextLabel(
            kind: snapshot.kind,
            periodLabel: periodLabel
        )
        // Badge, sub-line and button title all come from one Core decision, so a rejected
        // key can no longer be badged "Needs setup" next to an "Add Key" button.
        return SpendRowModel(
            snapshot: snapshot,
            status: APISpendPresentation.rowStatus(
                freshness: snapshot.freshness,
                providerID: snapshot.providerID,
                displayName: snapshot.displayName,
                // The missing-key line names the figure the key unlocks, and xAI's row is a
                // prepaid balance rather than period spend.
                kind: snapshot.kind
            ),
            title: identity.title,
            // X5: a balance row's "Remaining balance" outranks the name's qualifier — it is
            // the one thing that explains what the figure beside it means.
            contextLabel: snapshot.kind == .balance ? context : (identity.chipOverride ?? context),
            amount: APISpendPresentation.amountText(amount: snapshot.amount, currency: snapshot.currency)
        )
    }

    // MARK: - Row

    /// U3: the row itself is the shared `APISpendRow`. The Mac keeps what is Mac-only: the
    /// logo, the waiting line that observes spend activity, and the hover top-up on the amount.
    private func spendRow(_ model: SpendRowModel, amountWidth: CGFloat) -> some View {
        let snapshot = model.snapshot
        return APISpendRow(
            snapshot: snapshot,
            status: model.status,
            title: model.title,
            contextLabel: model.contextLabel,
            amount: model.amount,
            amountColumnWidth: amountWidth,
            amountDecoration: SpendTopUpReveal(
                glyph: topUpGlyph(model, revealed: hoveredTopUp == snapshot.providerID),
                glyphSpan: Self.topUpGlyphSpan,
                help: topUpHelp(for: model) ?? "",
                onHover: { inside in
                    if inside {
                        hoveredTopUp = snapshot.providerID
                    } else if hoveredTopUp == snapshot.providerID {
                        hoveredTopUp = nil
                    }
                }
            ),
            mark: { ProviderLogoView(providerID: snapshot.providerID, size: $0) },
            waitingLine: { message in
                SpendWaitingLine(store: store, providerID: snapshot.providerID, message: message)
            }
        )
    }

    /// CMM10: the glyph's hit frame is 22pt so its hover pill is a real pill, not a sliver
    /// clipped against the digits; the frame overhangs the 7pt gap by its own margin so the
    /// "+" ink still sits `topUpToAmountGap` off the first digit.
    private static var topUpGlyphSpan: CGFloat {
        topUpHitSize + topUpToAmountGap - (topUpHitSize - topUpGlyphSize) / 2
    }

    /// Quiet escape hatch to top up: opens the provider's billing page (the screen with the
    /// actual "Buy credits" control) — we never run the purchase ourselves. Bare glyph per
    /// the popover's control language; B3A keeps `HoverButtonStyle` for glyph controls.
    /// CMM5: the gap between the glyph's ink and the amount it belongs to.
    private static let topUpToAmountGap: CGFloat = 7
    /// CMM10: the glyph's hit frame and hover pill.
    private static let topUpHitSize: CGFloat = 22

    /// CMM10: one sentence for the tooltip on both the amount and the glyph.
    private func topUpHelp(for model: SpendRowModel) -> String? {
        let snapshot = model.snapshot
        let offersTopUp = snapshot.freshness == .live || !model.status.keyNeedsAttention
        guard APISpendPresentation.addCreditsURL(for: snapshot.providerID) != nil, offersTopUp else { return nil }
        return "Opens \(snapshot.displayName) billing to add API funds"
    }

    @ViewBuilder private func topUpGlyph(_ model: SpendRowModel, revealed: Bool) -> some View {
        let snapshot = model.snapshot
        // X5 (Kyle): a rejected or unscoped key has no balance to top up, so there is no glyph.
        let offersTopUp = snapshot.freshness == .live || !model.status.keyNeedsAttention
        if let url = APISpendPresentation.addCreditsURL(for: snapshot.providerID), offersTopUp {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                // CMM8: back to the bare "+" (PB12) — inside a hover reveal it no longer
                // has to explain itself at rest, and the circle was the heavier of the two.
                Image(systemName: "plus")
                    .font(.system(size: Self.topUpGlyphSize, weight: .semibold))
                    // PB12: centred on the amount's ink, not on the slot's box. SF's cap
                    // centre rides lower inside a 13pt line box than inside an 18pt one.
                    .offset(y: OpticalCentering.inkCenterAlignment(
                        size: Self.topUpGlyphSize,
                        weight: .semibold,
                        matching: Self.amountSize,
                        referenceWeight: .semibold
                    ))
                    .frame(width: Self.topUpHitSize, height: Self.topUpHitSize)
            }
            .buttonStyle(HoverButtonStyle(
                horizontalPadding: 0,
                verticalPadding: 0,
                hoverForegroundColor: ProviderStyle.textAccent(for: snapshot.providerID, scheme: scheme)
            ))
            // R2M13: the app's other affordances use `.help(_:)`; AppKit's own delay is the delay.
            .help(topUpHelp(for: model) ?? "")
            .accessibilityLabel("Add \(snapshot.displayName) API funds")
            // CMM8: the reveal. Scale and slide are `.movement` on the S3A hover pair (in on
            // `hoverIn`, out on `hoverOut`) and snap under Reduce Motion; the fade is
            // `.crossfade` and keeps its timing (S2A). A hidden glyph takes no clicks.
            // MS4 (2026-09-25 motion audit): from 97%, not 60%, and a 4pt slide — the house
            // arrival scale (card parts, pill cards) — so the glyph resolves rather than pops.
            .scaleEffect(revealed ? 1 : 0.97)
            .offset(x: revealed ? 0 : 4)
            .animation(
                HeadroomMotion.resolved(
                    revealed ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut,
                    .movement,
                    reduceMotion: reduceMotion
                ),
                value: revealed
            )
            .opacity(revealed ? 1 : 0)
            .animation(
                HeadroomMotion.resolved(
                    revealed ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut,
                    .crossfade,
                    reduceMotion: reduceMotion
                ),
                value: revealed
            )
            .allowsHitTesting(revealed)
        }
    }

    // MARK: - Card foot (P4C)

    /// P4C: every action the card offers collects in one row at the bottom of the card
    /// instead of hanging off the end of a row's sentence. B3 (Kyle): the shared
    /// `CardActionRow` owns the alignment and the gap above it, and the chips are `.small`
    /// like every other card foot. B3X: no `labelInset` here — the spend sentences already
    /// sit on `IdentityRowMetrics.meterContentInset`, which is the row's default.
    @ViewBuilder private func actionRow(_ models: [SpendRowModel]) -> some View {
        let actionable = models.filter { $0.showsCTA && $0.status.callToAction != nil }
        if !actionable.isEmpty {
            let counts = actionable.reduce(into: [String: Int]()) { counts, model in
                counts[model.status.callToAction ?? "", default: 0] += 1
            }
            CardActionRow {
                ForEach(actionable) { model in
                    let cta = model.status.callToAction ?? ""
                    Button(counts[cta, default: 0] > 1 ? qualified(cta, for: model) : cta, action: onOpenSettings)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                }
            }
        }
    }

    /// Two chips reading "Add Key" side by side are indistinguishable, so a duplicated label
    /// takes its vendor. Core's CTAs are all "<Verb> Key", so the vendor slots in before the
    /// noun ("Replace Anthropic Key"); anything else falls back to a parenthetical.
    /// B3T: the qualified form stays Title Case too — it is the same button, just longer.
    /// R2B1: explicit templates instead of string surgery on the CTA.
    private func qualified(_ cta: String, for model: SpendRowModel) -> String {
        let vendor = APISpendPresentation.vendorName(from: model.snapshot.displayName)
        switch cta {
        case "Add Key": return "Add \(vendor) Key"
        case "Replace Key": return "Replace \(vendor) Key"
        default: return "\(cta) (\(vendor))"
        }
    }
}

/// CMM8 (Kyle, 2026-09-10): the top-up glyph takes no room at rest. It lives in an overlay
/// off the amount's leading edge and reveals only while the pointer is over the figure, so
/// the column reserves nothing for it. U3: applied by the shared row before its column frame,
/// exactly where the popover always attached it.
private struct SpendTopUpReveal<Glyph: View>: ViewModifier {
    let glyph: Glyph
    let glyphSpan: CGFloat
    let help: String
    let onHover: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                glyph.offset(x: -glyphSpan)
            }
            // The hover band covers the glyph's landing zone too (B3H's pad → shape →
            // unpad), so sliding onto the "+" keeps it revealed long enough to click.
            .padding(.leading, glyphSpan)
            .contentShape(Rectangle())
            .padding(.leading, -glyphSpan)
            .onHover(perform: onHover)
            // CMM10: the standard AppKit tooltip on the hover area itself, so the reveal
            // explains the "+" after the system delay without the pointer having to reach
            // the glyph. Only where a billing page exists.
            .help(help)
    }
}

/// R11: only this small waiting line observes spend activity; the shared spend card
/// retains its existing formatting and layout boundaries for all four providers.
struct SpendWaitingLine: View {
    let store: UsageStore
    let providerID: ProviderID
    let message: String

    static func motion(providerID: ProviderID, inFlight: Set<ProviderID>) -> LoadingMotion {
        inFlight.contains(providerID) ? .slosh : .still
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IdentityRowMetrics.spacing) {
            MiniPill(mode: Self.motion(providerID: providerID, inFlight: store.apiSpendInFlightProviders).miniPillMode)
                .foregroundStyle(.tertiary)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            StatusSentence(text: message, severity: .quiet, indented: false)
        }
        .padding(.leading, IdentityRowMetrics.meterContentInset)
    }
}
