import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
import HeadroomWidgetSharedUI
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif

/// U3 (iOS parity): the popover's API-spend row, platform-neutral. Every decision it shows —
/// title, context label, amount text, status, tone — is resolved by the host from Core
/// (`APISpendPresentation`); the row only lays it out. Store lookup, the card's chrome and
/// rhythm, the duplicate-CTA foot and anything that opens a page stay with the host.
public enum APISpendRowMetrics {
    /// S5A: the amount matches the meter numeral — 18pt semibold monospaced digits in a
    /// reserved column — so every spend total and every percentage share one right edge, and
    /// the digit roll happens inside a frame that never resizes.
    public static let amountSize: CGFloat = 18

    /// R2C8 (Fable, post-merge): the column reserves the widest total the card is *showing*
    /// (floor "$0.00"), not a fixed "$0,000.00" — the direction suffix costs the row ~33pt,
    /// and the fixed reservation truncated every spend title. Every amount still shares one
    /// right edge because all rows reserve the same measured width. KTD2: CoreText measures
    /// what `NSString.size(withAttributes:)` did for the same face.
    public static func amountColumnWidth(for amounts: [String], scale: CGFloat = 1) -> CGFloat {
        (amounts + ["$0.00"])
            .map { ceil(HeadroomWidgetFontMetrics.textWidth($0, size: amountSize * scale, weight: .semibold, mono: true)) }
            .max() ?? 0
    }

    /// VoiceOver hears the same phrase the row prints — figure then direction (R2C8).
    public static func accessibilityLabel(
        snapshot: APISpendSnapshot,
        contextLabel: String,
        amount: String?,
        status: APISpendRowStatus
    ) -> String {
        var parts = [snapshot.displayName, contextLabel]
        if let amount {
            parts.append("\(amount) \(APISpendPresentation.directionTerm(kind: snapshot.kind))")
        }
        if snapshot.freshness != .live {
            if let badge = status.badge { parts.append(badge) }
            if let message = status.message { parts.append(message) }
        }
        return parts.joined(separator: ", ")
    }
}

/// KTD3: where the period chip (or the state tag standing in its slot) goes when the line is
/// tight. The Mac keeps the characterized inline line; the phone's 1.15× spend line needs
/// ~344pt against ~323pt, so there the chip drops to a subline before the title truncates.
public enum APISpendChipFit: Sendable {
    case inline
    /// U21 (KTD3): chip inline, then chip in the subline, then — once even the bare title and
    /// the amount cannot share a line (xxLarge on a 390pt phone) — the chip and the amount
    /// share the subline under a full-width title, and last the title wraps between words
    /// beside the amount with the chip under it. Capsules never truncate, so the title is
    /// the only thing that gives, and it gives a word at a time.
    case sublineWhenTight
    /// CA-I5: `sublineWhenTight` without its inline rung. The phone's spend card decides once
    /// for every row, so when one row's chip must drop, every row's chip drops with it.
    case subline
}

public struct APISpendRow<Mark: View, Waiting: View, AmountDecoration: ViewModifier>: View {
    public let snapshot: APISpendSnapshot
    public let status: APISpendRowStatus
    /// X5: the host's title — Core's display name minus any qualifier the chip carries.
    public let title: String
    public let contextLabel: String
    public let amount: String?
    /// The card-wide reserved column (`APISpendRowMetrics.amountColumnWidth`), measured once
    /// per pass by the host so every row shares one right edge.
    public let amountColumnWidth: CGFloat
    public var scale: CGFloat = 1
    public var chipFit: APISpendChipFit = .inline
    /// U21 (KTD15): the phone's whole-surface dimming. The amount takes the same secondary
    /// ink a stale row's does — one demotion, never an opacity multiplier.
    public var dimmed = false
    private let mark: (CGFloat) -> Mark
    private let waitingLine: (String) -> Waiting
    private let amountDecoration: AmountDecoration

    /// `waitingLine` draws a pending row's sentence (the Mac's observes spend activity);
    /// `amountDecoration` wraps the amount before its column frame (the Mac's hover top-up).
    public init(
        snapshot: APISpendSnapshot,
        status: APISpendRowStatus,
        title: String,
        contextLabel: String,
        amount: String?,
        amountColumnWidth: CGFloat,
        scale: CGFloat = 1,
        chipFit: APISpendChipFit = .inline,
        dimmed: Bool = false,
        amountDecoration: AmountDecoration,
        @ViewBuilder mark: @escaping (CGFloat) -> Mark,
        @ViewBuilder waitingLine: @escaping (String) -> Waiting
    ) {
        self.snapshot = snapshot
        self.status = status
        self.title = title
        self.contextLabel = contextLabel
        self.amount = amount
        self.amountColumnWidth = amountColumnWidth
        self.scale = scale
        self.chipFit = chipFit
        self.dimmed = dimmed
        self.amountDecoration = amountDecoration
        self.mark = mark
        self.waitingLine = waitingLine
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        // S5A: the sentence sits where an account's meters sit — indented to the content
        // axis, below the name — so a stale spend row and a stale account row have the same
        // silhouette. R4A sets the rhythm: 6 inside the group (title → sentence), 12 outside
        // it (sentence → action row, from `CardActionRow`), 13 to the card edge.
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 0) {
                identity
                    // RM1: colour only — the tag ⇄ chip swap and the amount's ink — inside a
                    // fixed-height line, so this scope keeps its crossfade under Reduce Motion.
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                        value: snapshot.freshness
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(APISpendRowMetrics.accessibilityLabel(
                        snapshot: snapshot, contextLabel: contextLabel, amount: amount, status: status
                    ))
                // CMM5: the trailing gutter stays empty, exactly as it is on a meter row, so
                // the amount's digits end on the percentages' column. X5 still applies —
                // with no figure there is nothing to reserve.
                if amount != nil {
                    Color.clear.frame(width: IdentityRowMetrics.contentTrailingInset * scale, height: 1)
                }
            }
            // The live "Updated N min ago" sub-line is dropped — the popover header
            // already carries one consolidated stamp. Non-live states keep their
            // status line because it carries information the header does not (U2).
            if snapshot.freshness != .live, let message = status.message {
                // S2B: the account rows' own sentence, not a local copy of its recipe —
                // `StatusSentenceSeverity` carries the spend card's quiet and neutral inks
                // too. X5 (Kyle): `indented` is the leading on the content axis, and the
                // trailing inset stays 0, so the sentence runs to the card edge and wraps on
                // measure instead of tearing at 155pt.
                Group {
                    if snapshot.freshness == .pending {
                        waitingLine(message)
                    } else {
                        StatusSentence(text: message, severity: StatusSentenceSeverity.forSpendTone(status.tone), scale: scale)
                    }
                }
                    // CA-I5 review fix: the sentence wraps to whatever width the row gets, so
                    // it claims no ideal width of its own. Otherwise its unwrapped length
                    // decided the phone card's chip fit, and one stale row dropped every chip.
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                    // M4A: freshness is a colour-and-presence change, so the line fades in
                    // and out rather than sliding.
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
        }
        // S2A: the whole freshness change — dimmed numeral ink and the state line's
        // arrival — is one motion. RM1: the row's scope is `.movement`, so under Reduce
        // Motion the row's height snaps; the line's fade rides its transition, and the ink
        // keeps its crossfade on the identity line's own scope above.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
            value: snapshot.freshness
        )
    }

    @ViewBuilder private var identity: some View {
        switch chipFit {
        case .inline:
            identityLine(chip: .inline, titleKeepsIdealWidth: false)
        case .sublineWhenTight:
            // KTD3: `ViewThatFits` only rejects a line whose ideal width overflows, so the
            // inline candidate holds the title at its full width; the fallback lets the title
            // truncate only once the chip has already left for the subline. Never
            // `minimumScaleFactor`.
            ViewThatFits(in: .horizontal) {
                identityLine(chip: .inline, titleKeepsIdealWidth: true)
                sublineIdentity
                stackedIdentity
                wrappingIdentity
                amountBelowIdentity
            }
        case .subline:
            ViewThatFits(in: .horizontal) {
                sublineIdentity
                stackedIdentity
                wrappingIdentity
                amountBelowIdentity
            }
        }
    }

    /// CMM4: the chip hangs under its title on the content axis, at the gap an identity row
    /// keeps to the meters it heads.
    private var sublineIdentity: some View {
        VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap * scale) {
            identityLine(chip: .none, titleKeepsIdealWidth: true)
            chip
                .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        }
    }

    private enum ChipPlacement { case inline, none }

    /// U21 (KTD3): the phone's third rung. The title takes the whole line, and the chip and
    /// the amount share the subline — the amount still in its reserved column on the card's
    /// one right edge.
    private var stackedIdentity: some View {
        VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap * scale) {
            HStack(spacing: IdentityRowMetrics.spacing * scale) {
                mark(IdentityRowMetrics.markSlotWidth * scale)
                titleText(wraps: false)
                Spacer(minLength: 0)
            }
            HStack(spacing: IdentityRowMetrics.spacing * scale) {
                chip
                Spacer(minLength: 0)
                if amount != nil {
                    amountColumn
                        .layoutPriority(2)
                        .frame(height: IdentityRowMetrics.capsuleHeight * scale)
                }
            }
            .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        }
    }

    /// U21 (KTD3): the fourth rung. The title wraps between words beside the amount, both
    /// hung from the first line, and the chip keeps its subline. Its ideal width is the
    /// longest word's, so `ViewThatFits` takes it only while no word has to break.
    private var wrappingIdentity: some View {
        VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap * scale) {
            HStack(alignment: .top, spacing: IdentityRowMetrics.spacing * scale) {
                mark(IdentityRowMetrics.markSlotWidth * scale)
                    .frame(height: IdentityRowMetrics.capsuleHeight * scale)
                titleText(wraps: true)
                    .frame(idealWidth: longestTitleWordWidth, alignment: .leading)
                Spacer(minLength: 0)
                if amount != nil {
                    amountColumn
                        .layoutPriority(2)
                        .frame(height: IdentityRowMetrics.capsuleHeight * scale)
                }
            }
            chip
                .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        }
    }

    /// U21 (KTD3): the guaranteed fit, for the clamped accessibility sizes. The title takes
    /// the whole width and wraps, the amount drops to its own line on the card's right edge,
    /// and the chip closes the row.
    private var amountBelowIdentity: some View {
        VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap * scale) {
            HStack(alignment: .top, spacing: IdentityRowMetrics.spacing * scale) {
                mark(IdentityRowMetrics.markSlotWidth * scale)
                    .frame(height: IdentityRowMetrics.capsuleHeight * scale)
                titleText(wraps: true)
                Spacer(minLength: 0)
            }
            if amount != nil {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    amountColumn
                        .frame(height: IdentityRowMetrics.capsuleHeight * scale)
                }
            }
            chip
                .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        }
    }

    /// The widest single word of the title at its rendered size (CoreText, KTD2).
    private var longestTitleWordWidth: CGFloat {
        title.split(separator: " ")
            .map { ceil(HeadroomWidgetFontMetrics.textWidth(String($0), size: IdentityRowMetrics.titleSize * scale, weight: .semibold,
                kerning: IdentityRowMetrics.titleKerning * scale)) }
            .max() ?? 0
    }

    private func titleText(wraps: Bool) -> some View {
        Text(title)
            .font(.system(size: IdentityRowMetrics.titleSize * scale, weight: .semibold))
            .kerning(IdentityRowMetrics.titleKerning * scale)
            .accountTitleInk(for: snapshot.providerID)
            .lineLimit(wraps ? 2 : 1)
            .fixedSize(horizontal: !wraps, vertical: wraps)
            .widgetOpticalLeading(title, size: IdentityRowMetrics.titleSize * scale, weight: .semibold)
    }

    private func identityLine(chip placement: ChipPlacement, titleKeepsIdealWidth: Bool) -> some View {
        HStack(spacing: IdentityRowMetrics.spacing * scale) {
            mark(IdentityRowMetrics.markSlotWidth * scale)
            Text(title)
                // G1: semibold, matching the account titles above.
                // CMM10: the account title's own size, kerning and ink token, verbatim.
                .font(.system(size: IdentityRowMetrics.titleSize * scale, weight: .semibold))
                .kerning(IdentityRowMetrics.titleKerning * scale)
                // G1: the same neutral-or-brand ink preference the account titles read.
                .accountTitleInk(for: snapshot.providerID)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: titleKeepsIdealWidth, vertical: false)
                .layoutPriority(1)
                // OA1: the spend title shares the account titles' axis, so it shares their
                // optical alignment too.
                .widgetOpticalLeading(title, size: IdentityRowMetrics.titleSize * scale, weight: .semibold)
            if placement == .inline {
                chip
            }
            // PA7: zero, not 6 — the HStack already spends 6pt on either side of this spacer,
            // so a 6pt floor double-counted the gap and, once the capsule grew to 10.5pt, left
            // "Anthropic API" 2pt short beside the reserved "$0,000.00" column.
            Spacer(minLength: 0)
            if amount != nil {
                // CMM5 (Kyle, 2026-09-10): the host's top-up affordance sits to the *left* of
                // the amount instead of in the trailing gutter, so a spend row and a meter row
                // share the same three trailing columns — figure, suffix, empty 21pt gutter —
                // and one right edge. The amount is right-aligned regardless.
                amountColumn
                    // S5A (Kyle): the amount never gives up width and never drops to a second
                    // line — at the popover's 299pt content width the chip truncates first.
                    .layoutPriority(2)
                    // IA1 (Kyle, 2026-09-23): the 18pt amount's ~21pt line box made this row
                    // taller than an account's identity row, and the centred title dropped
                    // ~1pt below the account titles in the cards above. The amount now lays
                    // out in the capsule's 18pt box — the identity line's own height — and
                    // its digits, which are shorter than that, still centre on the title.
                    .frame(height: IdentityRowMetrics.capsuleHeight * scale)
            }
        }
    }

    /// X5 (Kyle): the state tag stands exactly where the period chip stands, in line with the
    /// title it belongs to — a billing period is meaningless once the figure is stale or
    /// absent. Live and pending rows keep the chip and carry no tag.
    @ViewBuilder private var chip: some View {
        if let shortBadge = status.shortBadge {
            stateTag(shortBadge, tone: status.tone)
        } else {
            periodChip(contextLabel)
        }
    }

    /// The period reads as the plan chip does on an account row, so "September" and "Pro"
    /// are the same kind of object in the same slot.
    private func periodChip(_ label: String) -> some View {
        Text(label)
            .kerning(IdentityRowMetrics.capsuleLabelKerning * scale)
            // PA7: the capsule owns the type; this row only chooses the ink.
            // R2C17: metadata ink is the plan pill's token, not system `.tertiary`.
            .foregroundStyle(ProviderStyle.planLabelInk(scheme: scheme))
            .lineLimit(1)
            // C6A: the shared identity-line capsule, so the period chip and the state tag
            // that stands in for it are the same object at the same height.
            // R2C17: the period is metadata, so it drops the fill and reads as a label —
            // the same split the plan pill it mirrors took.
            .identityMetadataLabel(scale: scale)
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
    private var amountColumn: some View {
        HStack(spacing: MeterSuffixColumn.gap * scale) {
            Text(amount ?? "")
                .font(.system(size: APISpendRowMetrics.amountSize * scale, weight: .semibold).monospacedDigit())
                .foregroundStyle(snapshot.freshness == .live && !dimmed ? .primary : .secondary)
                .lineLimit(1)
                // M1A: the total rolls to its new value on the same spring the meters use.
                .contentTransition(
                    HeadroomMotion.numericText(value: snapshot.amount ?? 0, reduceMotion: reduceMotion)
                )
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                    value: snapshot.amount
                )
                .privacySensitive()
                .modifier(amountDecoration)
                // S5A: every row's last digit lands on the numeral column's right edge.
                .frame(width: amountColumnWidth, alignment: .trailing)
            MeterSuffixLabel(term: APISpendPresentation.directionTerm(kind: snapshot.kind), scale: scale)
        }
    }

    /// S5A: every tag in the popover is a capsule, so these are too. Neutral and quiet take
    /// the identity row's "Stale" recipe; warning and critical take the meter's "Low" chip
    /// recipe, tinted by the tone's own text ink. C6A fixes the height for all four.
    private func stateTag(_ badge: String, tone: APISpendRowStatus.Tone) -> some View {
        let ink = badgeColor(tone)
        return Text(badge)
            .kerning(IdentityRowMetrics.capsuleLabelKerning * scale)
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
                    : nil,
                scale: scale
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
}

public extension APISpendRow where AmountDecoration == EmptyModifier {
    /// A host with nothing to hang on the amount — the phone.
    init(
        snapshot: APISpendSnapshot,
        status: APISpendRowStatus,
        title: String,
        contextLabel: String,
        amount: String?,
        amountColumnWidth: CGFloat,
        scale: CGFloat = 1,
        chipFit: APISpendChipFit = .inline,
        dimmed: Bool = false,
        @ViewBuilder mark: @escaping (CGFloat) -> Mark,
        @ViewBuilder waitingLine: @escaping (String) -> Waiting
    ) {
        self.init(
            snapshot: snapshot, status: status, title: title, contextLabel: contextLabel,
            amount: amount, amountColumnWidth: amountColumnWidth, scale: scale, chipFit: chipFit,
            dimmed: dimmed, amountDecoration: EmptyModifier(), mark: mark, waitingLine: waitingLine
        )
    }
}
