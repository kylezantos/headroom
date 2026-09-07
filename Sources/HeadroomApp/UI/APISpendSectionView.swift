import SwiftUI
import AppKit
import HeadroomCore

struct APISpendSectionView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var store: UsageStore
    let now: Date
    let onOpenSettings: () -> Void

    /// S5A: the amount matches the meter numeral — 18pt semibold monospaced digits in a
    /// reserved column — so every spend total and every percentage in the popover share one
    /// right edge, and the digit roll happens inside a frame that never resizes.
    private static let amountSize: CGFloat = 18

    /// Measured from the same font the numeral renders in (mirrors
    /// `UsageBarView.percentColumnWidth`) rather than a hard-coded guess. "$0,000.00" is the
    /// widest total the card is designed to hold on one line.
    private static let amountColumnWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: amountSize, weight: .semibold)
        return ceil(("$0,000.00" as NSString).size(withAttributes: [.font: font]).width)
    }()

    /// S5A: the top-up glyph lives in the identity row's 21pt trailing gutter, to the right
    /// of the amount — 3pt gap plus an 18pt slot. The slot is reserved on every row (empty
    /// where the provider has no billing page), so no amount shifts because its neighbour
    /// can be topped up and this one cannot.
    private static let topUpSlotSize: CGFloat = 18
    private static let topUpGap = IdentityRowMetrics.contentTrailingInset - topUpSlotSize

    var body: some View {
        let models = store.apiSpendProviderOrder.map(rowModel(for:))
        if !models.isEmpty {
            // S5A: no eyebrow and no divider. The card now speaks the provider cards'
            // language — identity rows on the shared content axis, chunked by the same 22pt
            // gap the account sections use, inside the byte-identical tile.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(models) { model in
                        spendRow(model)
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

    private func rowModel(for id: ProviderID) -> SpendRowModel {
        let snapshot = store.apiSpendSnapshot(for: id)
        let identity = APISpendPresentation.popoverIdentity(displayName: snapshot.displayName)
        let context = APISpendPresentation.contextLabel(
            kind: snapshot.kind,
            periodLabel: store.apiSpendPeriod.displayLabel(now: now)
        )
        // Badge, sub-line and button title all come from one Core decision, so a rejected
        // key can no longer be badged "Needs setup" next to an "Add key" button.
        return SpendRowModel(
            snapshot: snapshot,
            status: APISpendPresentation.rowStatus(
                freshness: snapshot.freshness,
                providerID: snapshot.providerID,
                displayName: snapshot.displayName
            ),
            title: identity.title,
            // X5: a balance row's "Remaining balance" outranks the name's qualifier — it is
            // the one thing that explains what the figure beside it means.
            contextLabel: snapshot.kind == .balance ? context : (identity.chipOverride ?? context),
            amount: APISpendPresentation.amountText(amount: snapshot.amount, currency: snapshot.currency)
        )
    }

    // MARK: - Row

    @ViewBuilder private func spendRow(_ model: SpendRowModel) -> some View {
        let snapshot = model.snapshot
        // S5A: the sentence sits where an account's meters sit — indented to the content
        // axis, below the name — so a stale spend row and a stale account row have the same
        // silhouette. R4A sets the rhythm: 6 inside the group (title → sentence), 12 outside
        // it (sentence → action row, from `CardActionRow`), 13 to the card edge.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Self.topUpGap) {
                identityLine(model)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(model))
                // X5 (Kyle): with no figure there is nothing to reserve. The amount column
                // and the top-up slot collapse together rather than leaving 112pt of
                // reserved-and-empty line to the right of the title.
                if model.amount != nil {
                    topUpSlot(model)
                }
            }
            // The live "Updated N min ago" sub-line is dropped — the popover header
            // already carries one consolidated stamp. Non-live states keep their
            // status line because it carries information the header does not (U2).
            if snapshot.freshness != .live, let message = model.status.message {
                sentence(message, tone: model.status.tone)
                    // X5 (Kyle): leading on the content axis, trailing inset 0 — the
                    // sentence runs to 13pt from the card edge, so it wraps on measure
                    // instead of tearing at 155pt.
                    .padding(.leading, IdentityRowMetrics.meterContentInset)
                    .accessibilityHidden(true)
                    // M4A: freshness is a colour-and-presence change, so the line fades in
                    // and out rather than sliding.
                    .transition(.opacity)
            }
        }
        // S2A: the whole freshness change — dimmed numeral ink and the state line's
        // arrival — is one crossfade.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: snapshot.freshness
        )
    }

    private func identityLine(_ model: SpendRowModel) -> some View {
        HStack(spacing: IdentityRowMetrics.spacing) {
            ProviderLogoView(providerID: model.snapshot.providerID, size: IdentityRowMetrics.markSlotWidth)
            Text(model.title)
                // G1: semibold, matching the account titles above.
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.15)
                // G1: the same neutral-or-brand ink preference the account titles read.
                .accountTitleInk(for: model.snapshot.providerID)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            // X5 (Kyle): the state tag stands exactly where the period chip stands, in line
            // with the title it belongs to — a billing period is meaningless once the figure
            // is stale or absent. Live and pending rows keep the chip and carry no tag.
            if let shortBadge = model.status.shortBadge {
                stateTag(shortBadge, tone: model.status.tone)
            } else {
                periodChip(model.contextLabel)
            }
            Spacer(minLength: 6)
            if model.amount != nil {
                amountColumn(model)
                    // S5A (Kyle): the amount never gives up width and never drops to a second
                    // line — at the popover's 299pt content width the chip truncates first.
                    .layoutPriority(2)
            }
        }
    }

    /// The period reads as the plan chip does on an account row, so "September" and "Pro"
    /// are the same kind of object in the same slot.
    private func periodChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            // C6A: the shared identity-line capsule, so the period chip and the state tag
            // that stands in for it are the same object at the same height.
            .identityCapsule(
                fill: ClaudeSetupStyle.stepBackground(dark: scheme == .dark),
                horizontalPadding: 5
            )
    }

    /// S5A (Kyle): every amount — including the xAI balance row's — sits on the identity
    /// line in this one reserved column. The "remaining" qualifier is deliberately not drawn
    /// on macOS: the "Remaining balance" chip on the same line already says it. The string
    /// stays in Core for the widgets and the iPhone mirror.
    @ViewBuilder private func amountColumn(_ model: SpendRowModel) -> some View {
        let amount = model.amount
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
            .frame(width: Self.amountColumnWidth, alignment: .trailing)
    }

    /// Quiet escape hatch to top up: opens the provider's billing page (the screen with the
    /// actual "Buy credits" control) — we never run the purchase ourselves. Bare glyph per
    /// the popover's control language; B3A keeps `HoverButtonStyle` for glyph controls.
    @ViewBuilder private func topUpSlot(_ model: SpendRowModel) -> some View {
        let snapshot = model.snapshot
        // X5 (Kyle): a rejected or unscoped key has no balance to top up, so the glyph goes —
        // but the 18pt slot stays reserved, which is what keeps a retained amount on the same
        // right edge as the live ones (Cursor's URL-less row already proves the empty slot).
        let offersTopUp = snapshot.freshness == .live || !model.status.keyNeedsAttention
        if let url = APISpendPresentation.addCreditsURL(for: snapshot.providerID), offersTopUp {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: Self.topUpSlotSize, height: Self.topUpSlotSize)
            }
            .buttonStyle(HoverButtonStyle(
                horizontalPadding: 0,
                verticalPadding: 0,
                hoverForegroundColor: ProviderStyle.textAccent(for: snapshot.providerID, scheme: scheme)
            ))
            .delayedHelp("Open \(snapshot.displayName) billing to add credits")
            .accessibilityLabel("Add \(snapshot.displayName) credits")
        } else {
            Color.clear
                .frame(width: Self.topUpSlotSize, height: Self.topUpSlotSize)
        }
    }

    // MARK: - State line

    /// S2B: colour does the work. No glyph, and no tag at the head of the line — the tag has
    /// moved up to the identity line, and the sentence carries its own severity in ink. Same
    /// recipe as the account rows' `StatusSentence`; it is spelled out here rather than
    /// reused because two of the four spend tones (`.quiet`'s first-run line, `.neutral`'s
    /// retryable staleness) are hierarchical inks that `StatusSentenceSeverity` has no case
    /// for. The two that do overlap read their ink from that one table.
    private func sentence(_ message: String, tone: APISpendRowStatus.Tone) -> some View {
        Text(message)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(sentenceInk(tone))
            // S5A: the message wraps instead of truncating — a clipped instruction is worse
            // than a second line.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sentenceInk(_ tone: APISpendRowStatus.Tone) -> AnyShapeStyle {
        switch tone {
        case .quiet:
            AnyShapeStyle(.tertiary)
        case .neutral:
            AnyShapeStyle(.secondary)
        case .warning:
            AnyShapeStyle(StatusSentenceSeverity.attention.ink(scheme: scheme))
        case .critical:
            AnyShapeStyle(StatusSentenceSeverity.critical.ink(scheme: scheme))
        }
    }

    /// S5A: every tag in the popover is a capsule, so these are too. Neutral and quiet take
    /// the identity row's "Stale" recipe; warning and critical take the meter's "Low" chip
    /// recipe, tinted by the tone's own text ink. C6A fixes the height for all four.
    private func stateTag(_ badge: String, tone: APISpendRowStatus.Tone) -> some View {
        let ink = badgeColor(tone)
        return Text(badge)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.2)
            .foregroundStyle(ink)
            .lineLimit(1)
            // C6A: the same shared capsule as the period chip it stands in for.
            .identityCapsule(
                fill: tone == .quiet || tone == .neutral
                    ? Color.secondary.opacity(0.18)
                    : ink.opacity(0.16),
                horizontalPadding: 5
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
    /// like every other card foot.
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

    /// Two chips reading "Add key" side by side are indistinguishable, so a duplicated label
    /// takes its vendor. Core's CTAs are all "<verb> key", so the vendor slots in before the
    /// noun ("Replace Anthropic key"); anything else falls back to a parenthetical.
    private func qualified(_ cta: String, for model: SpendRowModel) -> String {
        let vendor = APISpendPresentation.vendorName(from: model.snapshot.displayName)
        guard cta.hasSuffix(" key") else { return "\(cta) (\(vendor))" }
        return "\(cta.dropLast(4)) \(vendor) key"
    }

    // MARK: - Accessibility

    private func accessibilityLabel(_ model: SpendRowModel) -> String {
        var parts = [model.snapshot.displayName, model.contextLabel]
        if let amount = model.amount { parts.append(amount) }
        if model.snapshot.freshness != .live {
            if let badge = model.status.badge { parts.append(badge) }
            if let message = model.status.message { parts.append(message) }
        }
        return parts.joined(separator: ", ")
    }
}
