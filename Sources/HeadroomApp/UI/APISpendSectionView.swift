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

    /// S5A: the amount matches the meter numeral — 18pt semibold monospaced digits in a
    /// reserved column — so every spend total and every percentage in the popover share one
    /// right edge, and the digit roll happens inside a frame that never resizes.
    private static let amountSize: CGFloat = 18

    /// Measured from the same font the numeral renders in (mirrors
    /// `UsageBarView.percentColumnWidth`) rather than a hard-coded guess.
    ///
    /// R2C8 (Fable, post-merge): the column reserves the widest total the card is *showing*
    /// (floor "$0.00"), not a fixed "$0,000.00". The direction suffix Kyle asked for costs
    /// the row ~33pt, and with the fixed reservation every spend title truncated in the live
    /// capture ("Anthropi…", "OpenAI…", "xA…"). Every amount still shares one right edge
    /// because all rows reserve the same measured width.
    private static func amountColumnWidth(for amounts: [String]) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: amountSize, weight: .semibold)
        let widest = (amounts + ["$0.00"])
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        return widest
    }

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
            let amountWidth = Self.amountColumnWidth(for: models.compactMap(\.amount))
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
            // Padding matches the provider cards above, so sibling tiles share one
            // padding and radius.
            .padding(13)
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

    @ViewBuilder private func spendRow(_ model: SpendRowModel, amountWidth: CGFloat) -> some View {
        let snapshot = model.snapshot
        // S5A: the sentence sits where an account's meters sit — indented to the content
        // axis, below the name — so a stale spend row and a stale account row have the same
        // silhouette. R4A sets the rhythm: 6 inside the group (title → sentence), 12 outside
        // it (sentence → action row, from `CardActionRow`), 13 to the card edge.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                identityLine(model, amountWidth: amountWidth)
                    // RM1: colour only — the tag ⇄ chip swap and the amount's ink — inside a
                    // fixed-height line, so this scope keeps its crossfade under Reduce Motion.
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                        value: snapshot.freshness
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(model))
                // CMM5: the trailing gutter stays empty, exactly as it is on a meter row, so
                // the amount's digits end on the percentages' column. X5 still applies —
                // with no figure there is nothing to reserve.
                if model.amount != nil {
                    Color.clear.frame(width: IdentityRowMetrics.contentTrailingInset, height: 1)
                }
            }
            // The live "Updated N min ago" sub-line is dropped — the popover header
            // already carries one consolidated stamp. Non-live states keep their
            // status line because it carries information the header does not (U2).
            if snapshot.freshness != .live, let message = model.status.message {
                // S2B: the account rows' own sentence, not a local copy of its recipe —
                // `StatusSentenceSeverity` now carries the spend card's quiet and neutral
                // inks too. X5 (Kyle): `indented` is the leading on the content axis, and the
                // trailing inset stays 0, so the sentence runs to 13pt from the card edge and
                // wraps on measure instead of tearing at 155pt.
                StatusSentence(
                    text: message,
                    severity: StatusSentenceSeverity.forSpendTone(model.status.tone)
                )
                    .accessibilityHidden(true)
                    // M4A: freshness is a colour-and-presence change, so the line fades in
                    // and out rather than sliding.
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
        }
        // S2A: the whole freshness change — dimmed numeral ink and the state line's
        // arrival — is one motion. RM1: the row's scope is `.movement`, so under Reduce
        // Motion the row's height snaps; the line's fade rides its transition, and the ink
        // keeps its crossfade on the identity line's own scope below.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
            value: snapshot.freshness
        )
    }

    private func identityLine(_ model: SpendRowModel, amountWidth: CGFloat) -> some View {
        HStack(spacing: IdentityRowMetrics.spacing) {
            ProviderLogoView(providerID: model.snapshot.providerID, size: IdentityRowMetrics.markSlotWidth)
            Text(model.title)
                // G1: semibold, matching the account titles above.
                // CMM10: the account title's own size, kerning and ink token, verbatim.
                .font(.system(size: IdentityRowMetrics.titleSize, weight: .semibold))
                .kerning(IdentityRowMetrics.titleKerning)
                // G1: the same neutral-or-brand ink preference the account titles read.
                .accountTitleInk(for: model.snapshot.providerID)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                // OA1: the spend title shares the account titles' axis, so it shares their
                // optical alignment too.
                .opticalLeading(model.title, size: IdentityRowMetrics.titleSize, weight: .semibold)
            // X5 (Kyle): the state tag stands exactly where the period chip stands, in line
            // with the title it belongs to — a billing period is meaningless once the figure
            // is stale or absent. Live and pending rows keep the chip and carry no tag.
            if let shortBadge = model.status.shortBadge {
                stateTag(shortBadge, tone: model.status.tone)
            } else {
                periodChip(model.contextLabel)
            }
            // PA7: zero, not 6 — the HStack already spends 6pt on either side of this spacer,
            // so a 6pt floor double-counted the gap and, once the capsule grew to 10.5pt, left
            // "Anthropic API" 2pt short beside the reserved "$0,000.00" column.
            Spacer(minLength: 0)
            if model.amount != nil {
                // CMM5 (Kyle, 2026-09-10): the top-up glyph sits to the *left* of the amount
                // instead of in the trailing gutter, so a spend row and a meter row share the
                // same three trailing columns — figure, suffix, empty 21pt gutter — and one
                // right edge. Nothing is reserved when a provider has no billing page; the
                // amount is right-aligned regardless.
                amountColumn(model, width: amountWidth)
                    // S5A (Kyle): the amount never gives up width and never drops to a second
                    // line — at the popover's 299pt content width the chip truncates first.
                    .layoutPriority(2)
                    // IA1 (Kyle, 2026-09-23): the 18pt amount's ~21pt line box made this row
                    // taller than an account's identity row, and the centred title dropped
                    // ~1pt below the account titles in the cards above. The amount now lays
                    // out in the capsule's 18pt box — the identity line's own height — and
                    // its digits, which are shorter than that, still centre on the title.
                    .frame(height: IdentityRowMetrics.capsuleHeight)
            }
        }
    }

    /// The period reads as the plan chip does on an account row, so "September" and "Pro"
    /// are the same kind of object in the same slot.
    private func periodChip(_ label: String) -> some View {
        Text(label)
            .kerning(IdentityRowMetrics.capsuleLabelKerning)
            // PA7: the capsule owns the type; this row only chooses the ink.
            // R2C17: metadata ink is the plan pill's token, not system `.tertiary`.
            .foregroundStyle(ProviderStyle.planLabelInk(scheme: scheme))
            .lineLimit(1)
            // C6A: the shared identity-line capsule, so the period chip and the state tag
            // that stands in for it are the same object at the same height.
            // R2C17: the period is metadata, so it drops the fill and reads as a label —
            // the same split the plan pill it mirrors took.
            .identityMetadataLabel()
    }

    /// S5A (Kyle): every amount — including the xAI balance row's — sits on the identity
    /// line in this one reserved column.
    ///
    /// R2C8 (Kyle): and it carries its direction. "$58.90" read as money spent on the OpenAI
    /// row and money remaining on the xAI row directly below it, with nothing but a grey
    /// capsule — which elsewhere holds "September" and "Pro Lite" — to tell them apart. The
    /// suffix is the meter rows' own "used"/"left" object in the shared `MeterSuffixColumn`,
    /// so the amount's digits land on the same right edge as the percentages above them and
    /// the two figures read as one family rather than two.
    @ViewBuilder private func amountColumn(_ model: SpendRowModel, width: CGFloat) -> some View {
        let amount = model.amount
        let providerID = model.snapshot.providerID
        let revealed = hoveredTopUp == providerID
        // CMM10: the glyph's hit frame is 22pt so its hover pill is a real pill, not a sliver
        // clipped against the digits; the frame overhangs the 7pt gap by its own margin so
        // the "+" ink still sits `topUpToAmountGap` off the first digit.
        let glyphSpan = Self.topUpHitSize + Self.topUpToAmountGap - (Self.topUpHitSize - Self.topUpGlyphSize) / 2
        HStack(spacing: MeterSuffixColumn.gap) {
            Text(amount ?? "")
                .font(.system(size: Self.amountSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(model.snapshot.freshness == .live ? .primary : .secondary)
                .lineLimit(1)
                // M1A: the total rolls to its new value on the same spring the meters use.
                .contentTransition(
                    HeadroomMotion.numericText(value: model.snapshot.amount ?? 0, reduceMotion: reduceMotion)
                )
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                    value: model.snapshot.amount
                )
                .privacySensitive()
                // CMM8 (Kyle, 2026-09-10): the top-up glyph takes no room at rest. It lives in
                // an overlay off the amount's leading edge and reveals only while the pointer
                // is over the figure, so the column reserves nothing for it.
                .overlay(alignment: .leading) {
                    topUpGlyph(model, revealed: revealed)
                        .offset(x: -glyphSpan)
                }
                // The hover band covers the glyph's landing zone too (B3H's pad → shape →
                // unpad), so sliding onto the "+" keeps it revealed long enough to click.
                .padding(.leading, glyphSpan)
                .contentShape(Rectangle())
                .padding(.leading, -glyphSpan)
                .onHover { inside in
                    if inside {
                        hoveredTopUp = providerID
                    } else if hoveredTopUp == providerID {
                        hoveredTopUp = nil
                    }
                }
                // CMM10: the standard AppKit tooltip on the hover area itself, so the reveal
                // explains the "+" after the system delay without the pointer having to
                // reach the glyph. Only where a billing page exists.
                .help(topUpHelp(for: model) ?? "")
                // S5A: every row's last digit lands on the numeral column's right edge.
                .frame(width: width, alignment: .trailing)
            MeterSuffixLabel(term: APISpendPresentation.directionTerm(kind: model.snapshot.kind))
        }
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

    // MARK: - State line

    /// S5A: every tag in the popover is a capsule, so these are too. Neutral and quiet take
    /// the identity row's "Stale" recipe; warning and critical take the meter's "Low" chip
    /// recipe, tinted by the tone's own text ink. C6A fixes the height for all four.
    private func stateTag(_ badge: String, tone: APISpendRowStatus.Tone) -> some View {
        let ink = badgeColor(tone)
        return Text(badge)
            .kerning(IdentityRowMetrics.capsuleLabelKerning)
            // PA7: the tag stands in the period chip's own slot, so it must not change size
            // or weight in place — "Rejected" is now the same object as "September".
            .foregroundStyle(ink)
            .lineLimit(1)
            // C6A: the same shared capsule as the period chip it stands in for.
            // R2C17: a state chip keeps its kind-tinted fill, and the neutral tones take
            // the one named stale recipe rather than a second copy of `0.18`.
            .identityCapsule(
                fill: tone == .quiet || tone == .neutral
                    ? IdentityCapsuleStyle.staleFill
                    : ink.opacity(0.16),
                horizontalPadding: 5,
                border: tone == .quiet || tone == .neutral
                    ? IdentityCapsuleStyle.stateBorder
                    : nil
            )
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

    // MARK: - Accessibility

    private func accessibilityLabel(_ model: SpendRowModel) -> String {
        var parts = [model.snapshot.displayName, model.contextLabel]
        // R2C8: VoiceOver hears the same phrase the row prints — figure then direction.
        if let amount = model.amount {
            parts.append("\(amount) \(APISpendPresentation.directionTerm(kind: model.snapshot.kind))")
        }
        if model.snapshot.freshness != .live {
            if let badge = model.status.badge { parts.append(badge) }
            if let message = model.status.message { parts.append(message) }
        }
        return parts.joined(separator: ", ")
    }
}
