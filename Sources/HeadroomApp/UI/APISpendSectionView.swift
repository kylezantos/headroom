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
        let contextLabel: String
        let amount: String?

        var id: ProviderID { snapshot.providerID }
        var showsCTA: Bool { status.showsCTA(hasAmount: amount != nil) }
    }

    private func rowModel(for id: ProviderID) -> SpendRowModel {
        let snapshot = store.apiSpendSnapshot(for: id)
        // Badge, sub-line and button title all come from one Core decision, so a rejected
        // key can no longer be badged "Needs setup" next to an "Add key" button.
        return SpendRowModel(
            snapshot: snapshot,
            status: APISpendPresentation.rowStatus(
                freshness: snapshot.freshness,
                providerID: snapshot.providerID,
                displayName: snapshot.displayName
            ),
            contextLabel: APISpendPresentation.contextLabel(
                kind: snapshot.kind,
                periodLabel: store.apiSpendPeriod.displayLabel(now: now)
            ),
            amount: APISpendPresentation.amountText(amount: snapshot.amount, currency: snapshot.currency)
        )
    }

    // MARK: - Row

    @ViewBuilder private func spendRow(_ model: SpendRowModel) -> some View {
        let snapshot = model.snapshot
        // S5A: the state line sits where an account's meters sit — indented to the content
        // axis, one identity-to-meters gap below the name — so a stale spend row and a stale
        // account row have the same silhouette.
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: Self.topUpGap) {
                identityLine(model)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(model))
                topUpSlot(snapshot)
            }
            // The live "Updated N min ago" sub-line is dropped — the popover header
            // already carries one consolidated stamp. Non-live states keep their
            // status line because it carries information the header does not (U2).
            if snapshot.freshness != .live {
                statusLine(model.status)
                    .padding(.leading, IdentityRowMetrics.meterContentInset)
                    .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
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
            Text(model.snapshot.displayName)
                .font(.system(size: 15, weight: .medium))
                .kerning(-0.15)
                .foregroundStyle(ProviderStyle.accountTitleInk(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            periodChip(model.contextLabel)
            Spacer(minLength: 6)
            amountColumn(model)
                // S5A (Kyle): the amount never gives up width and never drops to a second
                // line — at the popover's 299pt content width the chip truncates first.
                .layoutPriority(2)
        }
    }

    /// The period reads as the plan chip does on an account row, so "September" and "Pro"
    /// are the same kind of object in the same slot.
    private func periodChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 5)
            // T1A: the plan pill's vertical padding, so both chips are ~16pt tall.
            .padding(.vertical, 3)
            .background(
                ClaudeSetupStyle.stepBackground(dark: scheme == .dark),
                in: Capsule()
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
    @ViewBuilder private func topUpSlot(_ snapshot: APISpendSnapshot) -> some View {
        if let url = APISpendPresentation.addCreditsURL(for: snapshot.providerID) {
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

    @ViewBuilder private func statusLine(_ status: APISpendRowStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let badge = status.badge {
                stateTag(badge, tone: status.tone)
            }
            if let message = status.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(status.tone == .quiet ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    // S5A: the message wraps instead of truncating — a clipped instruction
                    // is worse than a second line.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// S5A: every tag in the popover is a capsule, so these are too. Neutral and quiet take
    /// the identity row's "Stale" recipe; warning and critical take the meter's "Low" chip
    /// recipe, tinted by the tone's own text ink.
    @ViewBuilder private func stateTag(_ badge: String, tone: APISpendRowStatus.Tone) -> some View {
        switch tone {
        case .quiet, .neutral:
            Text(badge)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.18), in: Capsule())
        case .warning, .critical:
            let ink = badgeColor(tone)
            Text(badge)
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.2)
                .foregroundStyle(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(ink.opacity(0.16), in: Capsule())
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

    // MARK: - Card foot (P4C)

    /// P4C: every action the card offers collects in one trailing-aligned row at the bottom
    /// of the card, 8pt below the last row and 8pt apart, instead of hanging off the end of
    /// a row's sentence. B3A's regular chip is the card-foot size.
    @ViewBuilder private func actionRow(_ models: [SpendRowModel]) -> some View {
        let actionable = models.filter { $0.showsCTA && $0.status.callToAction != nil }
        if !actionable.isEmpty {
            let counts = actionable.reduce(into: [String: Int]()) { counts, model in
                counts[model.status.callToAction ?? "", default: 0] += 1
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(actionable) { model in
                    let cta = model.status.callToAction ?? ""
                    Button(counts[cta, default: 0] > 1 ? qualified(cta, for: model) : cta, action: onOpenSettings)
                        .buttonStyle(SetupChipButtonStyle(size: .regular))
                }
            }
            .padding(.top, 8)
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
