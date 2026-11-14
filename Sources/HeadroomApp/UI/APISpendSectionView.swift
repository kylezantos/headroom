#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import HeadroomCore

struct APISpendSectionView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.headroomTuning) private var tuning
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
                if store.accountLayout == .compact {
                    compactBody(models)
                } else {
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
                }
                actionRow(models)
            }
            // Padding matches the provider cards above, so sibling tiles share one
            // padding and radius; the column planner models the same pad.
            .padding(tuning.cardPadding)
            .raisedTile(cornerRadius: tuning.cardCornerRadius)
        }
    }

    /// SP1: the card's 13pt padding between bare one-line rows; the accounts' 26pt block gap
    /// once any row carries a status sentence under it.
    private static func rowGap(for models: [SpendRowModel]) -> CGFloat {
        let hasSentence = models.contains { $0.snapshot.freshness != .live && $0.status.message != nil }
        return hasSentence ? 26 : 13
    }

    // MARK: - Compact (CA-P11)

    /// CA-P11 (POP-10): with Compact on, the spend card draws in the Compact idiom: one
    /// header line naming the period and the direction once, then one 26pt line per vendor
    /// with its amount at the Compact cells' size, flush on the card's 13pt edge where the
    /// compact numerals above it end. In Standard the amounts sat 26pt inside that edge, so
    /// adjacent cards put their figures on two columns.
    private func compactBody(_ models: [SpendRowModel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CompactSpendHeader(trailingLabel: CompactSpendLayout.headerTrailingLabel(
                periodLabel: store.apiSpendPeriod.displayLabel(now: now),
                kinds: models.map(\.snapshot.kind)
            ))
            VStack(alignment: .leading, spacing: CompactAccountRow.rowGap) {
                ForEach(models) { model in
                    compactSpendRow(model, mixedKinds: CompactSpendLayout.hasMixedKinds(models.map(\.snapshot.kind)))
                }
            }
        }
    }

    private func compactSpendRow(_ model: SpendRowModel, mixedKinds: Bool) -> some View {
        let snapshot = model.snapshot
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: IdentityRowMetrics.spacing) {
                ProviderLogoView(providerID: snapshot.providerID, size: IdentityRowMetrics.markSlotWidth)
                    .frame(width: IdentityRowMetrics.markSlotWidth, height: IdentityRowMetrics.markSlotWidth)
                Text(model.title)
                    .font(.system(size: CompactSpendLayout.titleSize, weight: .semibold))
                    .kerning(IdentityRowMetrics.titleKerning)
                    .accountTitleInk(for: snapshot.providerID)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if snapshot.freshness != .live, let badge = model.status.shortBadge {
                    compactStateTag(badge, tone: model.status.tone)
                } else if let label = CompactSpendLayout.rowTag(
                    shortBadge: nil,
                    isLive: true,
                    contextLabel: model.contextLabel,
                    kind: snapshot.kind,
                    mixedKinds: mixedKinds
                ) {
                    // The period chip's recipe, as the Standard row draws "Balance".
                    Text(label)
                        .kerning(IdentityRowMetrics.capsuleLabelKerning)
                        .foregroundStyle(ProviderStyle.planLabelInk(scheme: scheme))
                        .lineLimit(1)
                        .identityMetadataLabel()
                }
                Spacer(minLength: 0)
                if let amount = model.amount {
                    Text(amount)
                        .font(.system(size: CompactSpendLayout.amountSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(snapshot.freshness == .live ? .primary : .secondary)
                        .lineLimit(1)
                        .contentTransition(
                            HeadroomMotion.numericText(value: snapshot.amount ?? 0, reduceMotion: reduceMotion)
                        )
                        .animation(
                            HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                            value: snapshot.amount
                        )
                        .privacySensitive()
                        .modifier(SpendTopUpReveal(
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
                        ))
                        .fixedSize()
                }
            }
            .frame(height: CompactAccountRow.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(APISpendRowMetrics.accessibilityLabel(
                snapshot: snapshot, contextLabel: model.contextLabel, amount: model.amount, status: model.status
            ))
            if snapshot.freshness != .live, let message = model.status.message {
                Group {
                    if snapshot.freshness == .pending {
                        SpendWaitingLine(store: store, providerID: snapshot.providerID, message: message)
                    } else {
                        StatusSentence(text: message, severity: StatusSentenceSeverity.forSpendTone(model.status.tone))
                    }
                }
                .accessibilityHidden(true)
                .padding(.bottom, CompactSpendLayout.sentenceBottomGap)
            }
        }
    }

    /// The Standard row's state tag (`APISpendRow`), so "Rejected" is the same object in
    /// both layouts: neutral tones take the stale recipe, warning and critical their ink.
    private func compactStateTag(_ badge: String, tone: APISpendRowStatus.Tone) -> some View {
        let ink: Color = switch tone {
        case .quiet, .neutral: .secondary
        case .warning: ProviderStyle.severityColor(for: .low, scheme: scheme)
        case .critical: ProviderStyle.criticalText(scheme: scheme)
        }
        let neutral = tone == .quiet || tone == .neutral
        return Text(badge)
            .kerning(IdentityRowMetrics.capsuleLabelKerning)
            .foregroundStyle(ink)
            .lineLimit(1)
            .identityCapsule(
                fill: neutral ? IdentityCapsuleStyle.staleFill : ink.opacity(0.16),
                horizontalPadding: 5,
                border: neutral ? IdentityCapsuleStyle.stateBorder : nil
            )
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
            // CA-P11: in Compact the action row starts on the names' axis past the mark, as
            // the rows above it do.
            CardActionRow {
                ForEach(actionable) { model in
                    // CA-S8 (COPY-12): a CTA names its vendor whenever the card holds more
                    // than one, so a lone "Replace Key" under four rows no longer leaves the
                    // user guessing which key. Only a duplicated label used to qualify.
                    Button(APISpendPresentation.cardCallToAction(
                        model.status.callToAction ?? "",
                        vendor: APISpendPresentation.vendorName(from: model.snapshot.displayName),
                        cardVendorCount: models.count
                    ), action: onOpenSettings)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                }
            }
        }
    }
}

/// CA-P11: the Compact spend card's decisions, pure so the header and the row tag are testable.
enum CompactSpendLayout {
    /// The Compact row's title, as `CompactAccountRow`'s.
    static let titleSize: CGFloat = 13
    /// The Compact cells' numeral size (`UsageBarView`'s compact percent), so a spend amount
    /// and a compact percentage read as one family on one edge.
    static let amountSize: CGFloat = 15
    static let sentenceBottomGap: CGFloat = 4

    /// "Nov · used": the period and the direction, once for the card. A card that mixes
    /// period spend and a prepaid balance states the period only; the balance row says
    /// "Balance" itself.
    static func headerTrailingLabel(periodLabel: String, kinds: [APISpendKind]) -> String {
        guard let first = kinds.first, !hasMixedKinds(kinds) else { return periodLabel }
        let context = APISpendPresentation.contextLabel(kind: first, periodLabel: periodLabel)
        return "\(context) · \(APISpendPresentation.directionTerm(kind: first))"
    }

    static func hasMixedKinds(_ kinds: [APISpendKind]) -> Bool {
        Set(kinds).count > 1
    }

    /// The tag beside a row's name: its state when it is not live, "Balance" on a balance row
    /// the header does not already explain, nothing otherwise (the header names the period).
    static func rowTag(shortBadge: String?, isLive: Bool, contextLabel: String, kind: APISpendKind, mixedKinds: Bool) -> String? {
        if !isLive, let shortBadge { return shortBadge }
        if kind == .balance, mixedKinds { return contextLabel }
        return nil
    }
}

/// CA-P11: the Compact spend card's one header line, in `CompactCardHeader`'s recipe: 11pt
/// tertiary over one hairline, the trailing label flush on the amounts' edge.
private struct CompactSpendHeader: View {
    let trailingLabel: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: IdentityRowMetrics.spacing) {
                Text("API spend")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(trailingLabel)
                    .lineLimit(1)
            }
            .font(.system(size: MeterSuffixColumn.size))
            .foregroundStyle(.tertiary)
            .frame(height: 16)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: CompactCardHeader.height)
        .accessibilityHidden(true)
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
