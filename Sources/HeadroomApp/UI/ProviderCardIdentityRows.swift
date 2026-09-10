import AppKit
import SwiftUI
import HeadroomCore

// MARK: - Unified identity row

enum IdentityRowMetrics {
    static let markSlotWidth: CGFloat = 15
    static let spacing: CGFloat = 6
    /// CMM4 (Kyle, 2026-09-10): the identity row's gap to what it heads — 4 over meters,
    /// 6 over a sign-in sentence. Frame units; ≈14pt / ≈12.5pt of ink in Micro.
    static let identityToMetersGap: CGFloat = 4
    static let identityToSentenceGap: CGFloat = 6
    /// CMM6: how far a chip row's first box hangs outside the text axis.
    static let chipBoxOutdent: CGFloat = 1
    static let meterContentInset = markSlotWidth + spacing
    /// L4B: the trailing gutter mirrors the label column instead of the mark. With the
    /// card's own 13pt padding this ends every identity row and every meter row 34pt from
    /// the card's right edge — the same 34pt the titles and meter labels start at — and
    /// leaves the provider mark hanging alone in its 13pt gutter.
    static let contentTrailingInset = meterContentInset
    /// C6A: one capsule height for everything that rides an identity line. Vertical padding
    /// could not deliver it — a 10.5pt tag's line box is taller than a 9.5pt pill's, so the
    /// same `vPad 3` produced 18/19/20 — and the drift is invisible until two capsules sit
    /// side by side. An explicit height with centred text cannot drift.
    static let capsuleHeight: CGFloat = 18

    /// PA7: one capsule *label* role to go with C6A's one capsule height. The six capsules
    /// were sharing a box while running 9.5 medium / 10 semibold / 10.5 semibold / 11
    /// semibold inside it, with kerning on two of the six — and the spend state tag swaps
    /// into the period chip's own slot, so "Rejected" changed size and weight in place where
    /// "September" had been. Capsules only read as peers if their labels are peers. Ink and
    /// fill stay per-recipe; only the type is shared.
    static let capsuleLabelSize: CGFloat = 10.5
    static let capsuleLabelWeight: Font.Weight = .medium
    static let capsuleLabelKerning: CGFloat = 0.2
}

/// R2C17: one capsule was carrying four meanings — plan (Max, Pro Lite), period (September),
/// measure (Remaining balance) and the freshness *warning* (Stale) all in the same grey
/// chrome, so "Work · Pro · Stale" read the warning as a third subscription tier. Things that
/// look the same must behave the same, so the family splits: metadata is a flat label, state
/// is a filled-and-outlined chip. These are the shared values that split needs.
enum IdentityCapsuleStyle {
    /// R2C17: the stale chip's fill, previously an untokenised `secondary.opacity(0.18)`
    /// written out once on the identity row and again in the spend view.
    static let staleFill = Color.secondary.opacity(0.18)
    /// CMM9: the plan / period pill — a step quieter than a state chip and without its ring.
    static let metadataFill = Color.secondary.opacity(0.12)

    /// R2C17: outlined-and-filled reads as state; flat reads as label. One hairline is the
    /// whole difference, so it lives here rather than at either call site.
    static let stateBorder = Color.secondary.opacity(0.35)
    static let stateBorderWidth: CGFloat = 1
}

extension View {
    /// C6A: the one identity-line capsule. Each recipe keeps its own horizontal padding and
    /// fill; the height is not negotiable. PA7 added the label role — set through the
    /// environment, so a call site that still declares `Text.font(_:)` would silently win.
    /// None do: the six recipes were stripped when this took the type over.
    ///
    /// R2C17 added `border`, defaulted off: only a state chip is outlined.
    func identityCapsule<Fill: ShapeStyle>(
        fill: Fill,
        horizontalPadding: CGFloat,
        border: Color? = nil
    ) -> some View {
        font(.system(
            size: IdentityRowMetrics.capsuleLabelSize,
            weight: IdentityRowMetrics.capsuleLabelWeight
        ))
        // PA7: kerning is applied on each capsule Text at the call site, not here — as a
        // View modifier it leaked into the sibling layout and truncated the spend title.
        .fixedSize()
        .frame(height: IdentityRowMetrics.capsuleHeight)
        .padding(.horizontal, horizontalPadding)
        .background(fill, in: Capsule())
        .overlay {
            if let border {
                Capsule().strokeBorder(border, lineWidth: IdentityCapsuleStyle.stateBorderWidth)
            }
        }
    }

    /// The metadata half of the split — plan, period, measure.
    ///
    /// CMM9 (Kyle, 2026-09-10): back in its own pill. R2C17 had flattened it to a bare label
    /// so that only *state* chips carried a fill; Kyle wants the plan and period "in their
    /// own dip like they used to be", just styled apart from Stale — so this is a quiet fill
    /// with no ring, and the state chips keep the fill-plus-hairline recipe.
    func identityMetadataLabel() -> some View {
        identityCapsule(fill: IdentityCapsuleStyle.metadataFill, horizontalPadding: 5)
    }
}

// MARK: - S2B status sentence

/// PA12: the outcome a sign-in row should *present*, which is not always the one Core
/// typed.
///
/// A just-added account carries the untyped `UsageStore.finishSignInMessage` preset until
/// its first probe returns, so two never-signed-in rows in the same card described one state
/// as two problems with two fixes: "Finish sign-in to add this account" + a bare **Sign In**
/// beside the typed "Sign in with the official Claude CLI" + **Open Claude Setup** /
/// **Check Now**. The preset now borrows its own provider's never-signed-in outcome, so both
/// rows read the same sentence and offer the same pair of actions. Anything Core already
/// typed passes through untouched, and an untyped failure that is *not* the add-account
/// preset still gets no invented recovery.
func presentedSetupOutcome(
    for reason: FailureReason,
    providerID: ProviderID
) -> ProviderSetupOutcome? {
    if let typed = reason.providerSetupOutcome { return typed }
    guard reason.message == UsageStore.finishSignInMessage else { return nil }
    return neverSignedInOutcome(for: providerID)
}

/// The typed "this account has never signed in" outcome per provider — the same four
/// `ProviderSetupOutcome.isNeverSignedIn` reports true for. Provider-scoped rather than
/// hard-wired to Claude's, because `UsageStore.addAccount` hands the preset to every
/// provider that can carry an extra account.
func neverSignedInOutcome(for providerID: ProviderID) -> ProviderSetupOutcome? {
    switch providerID {
    case .claude: .claudeLoginRequired
    case .codex: .codexAuthAbsent
    case .grok: .grokAuthAbsent
    case .cursor: .cursorAuthAbsent
    default: nil
    }
}

/// S2B: severity lives in the sentence's ink, so the mapping from state to ink is stated
/// once here rather than re-decided at each of the six former glyph sites.
enum StatusSentenceSeverity {
    /// Something needs the user, and the account is otherwise intact: sign in needed, a
    /// stale capture, a missing CLI, a handoff standing in the way.
    case attention
    /// The provider or the OS said no: a rejected sign-in, a denied read, a failed handoff.
    case critical
    /// A handoff is running. Not a severity at all — the row is mid-flight.
    case progress

    /// R2C5: `.attention` used to paint with the meter's Low amber, so an amber 38% Weekly bar
    /// could sit two rows above an amber "Sign in with the official Claude CLI" with no
    /// relationship between them — one colour, two meanings. Account lifecycle comes off the
    /// severity ramp onto the neutral label ink; the sentence is already 11.5 medium against
    /// 11 regular metadata, so weight and position carry it. `.critical` keeps the red,
    /// because a provider refusal genuinely is an error and is the card's only red.
    func ink(scheme: ColorScheme) -> Color {
        switch self {
        case .attention: ProviderStyle.meterLabelInk(scheme: scheme)
        case .critical: ProviderStyle.criticalText(scheme: scheme)
        case .progress: Color.secondary
        }
    }

    /// S2B: only the provider's own refusals earn the critical ink. Everything else is a
    /// state the user can walk out of, so it stays attention rather than shouting.
    static func forSetupOutcome(_ outcome: ProviderSetupOutcome?) -> StatusSentenceSeverity {
        switch outcome {
        case .codexRejectedAuth, .codexPermissionDenied, .codexUnsafePermissions,
             .grokRejectedAuth, .grokPermissionDenied, .grokUnsafePermissions:
            .critical
        default:
            .attention
        }
    }
}

/// S2B: the whole status line — no glyph, no state tag. 11.5 medium, inked by severity,
/// starting on the 34pt content axis (the 21pt inset inside the card's own 13pt padding),
/// wrapping freely and stopping at the card's own 13pt trailing edge.
struct StatusSentence: View {
    let text: String
    let severity: StatusSentenceSeverity
    /// False where the row supplies the axis itself — the waiting row's spinner occupies
    /// the 15pt mark slot, and the single-account setup notice sits above a guided card
    /// that starts at the card's own 13pt edge.
    var indented: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(severity.ink(scheme: scheme))
            // PB11: this sentence routinely runs to three lines in a 299pt card, and at
            // SF's default it was setting at ~1.22 leading while Settings' help text gets
            // 1.4. Two points brings the popover's wrapping prose into the same band.
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            // OA1: the sentence starts a line on the same content axis as the titles and
            // meter labels above it, so it hangs on the same optical edge they do.
            .opticalLeading(text, size: 11.5, weight: .medium)
            .padding(.leading, indented ? IdentityRowMetrics.meterContentInset : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one identity treatment used for provider-name and account-name rows (KTD9).
/// The mark owns the only brand color; account metadata and state remain neutral.
struct IdentityRow: View {
    let providerID: ProviderID
    let title: String
    let planLabel: String?
    let isMenuBarAccount: Bool
    let isStale: Bool
    let email: String?
    let showsPersistentEmail: Bool
    let showsConnectedChip: Bool
    /// R2C22: the capability card stamps the provider mark on its own header row *and* on
    /// every account row beneath it, so "✳ Claude" sat 7pt above "✳ Personal". A nested
    /// account row hides its mark and keeps the slot, so the title column never shifts.
    var showsMark: Bool = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// PB11: whether the tail truncation actually bit. Measured, not guessed — SwiftUI has
    /// no "did this Text truncate" signal, so the rendered width is compared against the
    /// string's intrinsic width in the same font.
    @State private var titleIsTruncated = false

    @ViewBuilder var body: some View {
        let email = normalizedEmail
        if let tooltip = rowHelp(email: email) {
            row(email: email)
                .help(tooltip)
        } else {
            row(email: email)
        }
    }

    private func row(email: String?) -> some View {
        HStack(spacing: IdentityRowMetrics.spacing) {
            if showsMark {
                ProviderLogoView(providerID: providerID, size: IdentityRowMetrics.markSlotWidth)
            } else {
                // R2C22: the slot stays reserved, so a nested row's title lands on the same
                // axis as the header row's above it.
                Color.clear.frame(
                    width: IdentityRowMetrics.markSlotWidth,
                    height: IdentityRowMetrics.markSlotWidth
                )
            }
            titleText
            if let planDisplayName {
                Text(planDisplayName)
                    .kerning(IdentityRowMetrics.capsuleLabelKerning)
                    // PA13: the plan pill carries its own token so the dark step is set by |Lc|, not system `.tertiary`.
                    .foregroundStyle(ProviderStyle.planLabelInk(scheme: scheme))
                    // CMM9: the plan pill, filled again; the state chip beside it carries
                    // the ring that tells the two apart.
                    .identityMetadataLabel()
            }
            // CMM9 (Kyle): the state chips sit *next to* the plan pill, leading-aligned,
            // rather than pushed to the row's trailing edge — one chip run reading
            // "Work · Pro · Stale" in order, not a tier on the left and a warning on the right.
            if isStale {
                staleTag
            }
            if showsConnectedChip {
                ConnectedChip()
                    .transition(.connectedChip(reduceMotion: reduceMotion))
            }
            if showsPersistentEmail, let email {
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
            Spacer(minLength: 6)
        }
        // L4B: trailing controls stop level with the meter rows below them.
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityIdentity(email: email))
    }

    /// T1A sized this off Kyle's Paper mock at 15pt on the `accountTitle` ink so the name
    /// labels its meters instead of competing with the popover's own 20pt bold header. G1
    /// restored `.semibold` — `.medium` on a recessive grey lost the row's anchor — and the
    /// ink is now the user's `AccountTitleInk` choice (neutral grey or the provider's brand
    /// tint). Kerning is unchanged throughout.
    private var titleText: some View {
        Text(title)
            .font(.system(size: Self.titleSize, weight: .semibold))
            .kerning(Self.titleKerning)
            .accountTitleInk(for: providerID)
            .lineLimit(1)
            .truncationMode(.tail)
            // PB11: measured on the Text itself, before the optical pull-back, so the
            // comparison is against the width the string was actually given.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                titleIsTruncated = Self.titleIsTruncated(title, renderedWidth: width)
            }
            // OA1: "Personal" and "Work" carry side bearings 0.66pt apart at this size, so
            // without this the title column visibly jitters account to account.
            .opticalLeading(title, size: Self.titleSize, weight: .semibold)
            // PB11: the account name identifies the row; the email is a detail the tooltip
            // has always carried anyway. Outranking the email's `layoutPriority(1)` stops a
            // long address eating the name it belongs to.
            .layoutPriority(2)
    }

    private static let titleSize: CGFloat = 15
    private static let titleKerning: CGFloat = -0.15

    /// PB11: the width the title wants, from the same real font metrics `OpticalLeading`
    /// reads. Kept separate from the comparison below so the predicate is testable without
    /// a render.
    static func titleIntrinsicWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: titleSize, weight: .semibold),
            .kern: titleKerning,
        ]).width
    }

    /// True once the row is narrower than the string needs. The half-point slack keeps
    /// sub-pixel layout rounding from claiming a truncation that never happened; a zero
    /// width is the pre-layout pass, not a truncation.
    static func titleIsTruncated(_ title: String, renderedWidth: CGFloat) -> Bool {
        guard renderedWidth > 0 else { return false }
        return renderedWidth + 0.5 < titleIntrinsicWidth(title)
    }

    /// L5D: the main account carries no visible marker. Order already says it — main is
    /// always its provider's first row — and a second capsule beside the plan badge made a
    /// busy title cluster busier, so the fact moves to this row's tooltip and to VoiceOver.
    /// One `.help` per row: nested help modifiers let the innermost win on macOS, so a
    /// separate tooltip on the title would swallow the email the row has always shown.
    ///
    /// PB11: a truncated title joins it. The tail ellipsis is the only place the row loses
    /// information the user cannot recover any other way, and the row already owns the one
    /// tooltip on this line.
    private func rowHelp(email: String?) -> String? {
        var lines: [String] = []
        if titleIsTruncated { lines.append(title) }
        if let email { lines.append(email) }
        if isMenuBarAccount { lines.append(Self.mainAccountHelp) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private var normalizedEmail: String? {
        guard let email, !email.isEmpty else { return nil }
        return email
    }

    /// Raw ids (`prolite`, `SuperGrok`) never reach the badge — Core owns the humanizing
    /// so the lenient provider models keep their verbatim value (#709).
    private var planDisplayName: String? {
        PlanLabelPresentation.displayName(planLabel)
    }

    /// S2B removed the status glyphs and left severity to the sentence's ink — but a
    /// transient-stale row renders no sentence at all (`stateContent` keeps its dimmed
    /// meters), so this tag survives as that state's only visible signal. C6A gives it the
    /// same 18pt as the plan pill beside it.
    private var staleTag: some View {
        Text("Stale")
            .kerning(IdentityRowMetrics.capsuleLabelKerning)
            // PA7: type comes from `identityCapsule` now.
            .foregroundStyle(.secondary)
            // R2C17: a state chip, so it keeps its fill and takes the hairline that tells it
            // apart from the flat plan label now sitting beside it.
            .identityCapsule(
                fill: IdentityCapsuleStyle.staleFill,
                horizontalPadding: 5,
                border: IdentityCapsuleStyle.stateBorder
            )
    }

    /// L5D: with the badge gone, the row tooltip and this VoiceOver phrase are the only
    /// places the fact is stated — keep them in step.
    static let mainAccountHelp = "Main account — shown in the menu bar and widgets"

    private func accessibilityIdentity(email: String?) -> String {
        var parts = [title]
        if let planDisplayName { parts.append("\(planDisplayName) plan") }
        if isMenuBarAccount { parts.append("Main account, shown in the menu bar and widgets") }
        if isStale { parts.append("Stale") }
        if let email { parts.append("signed in as \(email)") }
        if showsConnectedChip { parts.append("Connected") }
        return parts.joined(separator: ", ")
    }
}

private extension AnyTransition {
    /// M8A: a sign-in payoff earns a little arrival, so the chip enters on opacity plus a
    /// 0.96 scale; it leaves on opacity alone, because an exit that announces itself twice
    /// reads as an error. S2A drops the scale under Reduce Motion and keeps the fade.
    static func connectedChip(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity
        )
    }
}

private struct ConnectedChip: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                // R2B3: 9pt bold beside a 10.5 medium label was the heavier of the two at the
                // smaller size; semibold puts the glyph's stroke back in step with its word.
                .font(.system(size: 9, weight: .semibold))
            // PA7: the tallest label of the six took the shared role too; only the
            // checkmark keeps a font of its own, because it is a glyph, not a label.
            Text("Connected")
                .kerning(IdentityRowMetrics.capsuleLabelKerning)
        }
        .foregroundStyle(ClaudeSetupStyle.connectedInk(dark: scheme == .dark))
        // C6A: was the tallest of the three capsules at ~19–20pt; now the same 18 as the rest.
        .identityCapsule(
            fill: ClaudeSetupStyle.connectedBackground(dark: scheme == .dark),
            horizontalPadding: 8
        )
    }
}

// MARK: - Account section (multi-account rows)

/// One account's section inside a multi-account provider card. The round-6 unified identity
/// row carries its title and account-scoped state; a 22pt inter-account gap plus the meter
/// inset provides the G3 hierarchy without a band or divider (R15, R18, KTD18).
struct AccountSectionView: View {
    let entry: ProviderAccountEntry
    let providerDisplayName: String
    let identityTitle: String
    let showsPersistentEmail: Bool
    let percentageMode: UsagePercentageMode
    let meterStyle: MeterStyle
    let now: Date
    /// The selected primary account (`entries.first`) is the one the menu bar and widgets
    /// follow; its identity row carries the mark that explains which login drives the glyph.
    let isMenuBarAccount: Bool
    let showsStopWaiting: Bool
    let onRetry: () -> Void
    /// R2C22: false for the account rows nested under a capability card's own provider row.
    var showsMark: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsConnectedChip = false

    private var snapshot: UsageSnapshot { entry.snapshot }
    private var account: ProviderAccount { entry.account }
    /// R2M1: what the section's second animation scope keys on. See
    /// `providerCardSessionKey` — the raw state's retry counter must not restage anything.
    private var sessionKey: SetupSessionState {
        providerCardSessionKey(SetupSessions.state(for: account))
    }

    var body: some View {
        // G3/R4A: the identity binds to its meters; the 26pt inter-section gap in
        // `multiAccountBody` does the separating (proximity, not chrome). The whole section
        // is one VoiceOver container so the rotor can jump account-to-account instead of the
        // meters floating free of their identity row.
        //
        // CMM4 (Kyle, 2026-09-10) supersedes R2C2's 2. R2C2 chased a "≥2× group gap" ratio
        // and landed the title 12pt of ink over its first meter against 19pt meter-to-meter,
        // which made "Personal" pair with "Weekly" and orphan "5-hour". The account is the
        // group; inside it the title sits a touch tighter than the row step, not half of it.
        // Kyle picked the values off the side-by-side mock: 4 over meters (≈14pt ink), 6 over
        // a sign-in sentence (≈12.5pt ink, the pre-round value).
        VStack(alignment: .leading, spacing: identityToContentGap) {
            identityRow
            // M4A/S2A: the innermost scope around the switching body, so the crossfade —
            // not the section's height change — is what this animation drives. The wrapper
            // repeats the parent's spacing so it stays layout-neutral for the multi-view
            // `signInContent` branch. Fill and numeral roll are `UsageBarView`'s.
            VStack(alignment: .leading, spacing: identityToContentGap) {
                stateContent
            }
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion),
                value: snapshot.freshness
            )
            // R2M1: the second scope, on the session rather than the snapshot. A row swapping
            // its sign-in block for a waiting block is the same kind of body change
            // `freshness` already crossfades; without this it hard-cut.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                value: sessionKey
            )
            if showsStopWaiting,
               SetupSessions.state(for: account) != .blockedByOpenHandoff {
                // P4C/R4A/B3: the section's one action row, leading-aligned at the mark
                // column. The stack's own spacing supplies part of R4A's 12pt gap, so the
                // row adds the rest.
                //
                // R2C11 (Kyle): the row's max width now runs to the trailing edge of the
                // usage rows, so its chips wrap inside the same left/right bounds the meters
                // above them keep rather than running on to the card's own padding.
                CardActionRow(
                    topPadding: 10,
                    trailingInset: IdentityRowMetrics.contentTrailingInset
                ) {
                    StopWaitingButton(account: account, style: .chip(.small))
                }
                // R2M1: the row appears and disappears with the session, so it dissolves
                // rather than popping into a card that is already resizing under it.
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(identityTitle) account")
        // M4A/S2A: the section's own geometry — its height inside the 26pt account stack —
        // is travel, so Reduce Motion snaps it while the body above still crossfades.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
            value: snapshot.freshness
        )
        // R2M1: the movement half of the session scope — the section's height inside the
        // account stack when a waiting block replaces a taller sign-in block.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
            value: sessionKey
        )
        .onChange(of: snapshot.freshness) { evaluateConnectedPayoff() }
        .onAppear {
            evaluateConnectedPayoff()
            SetupSessions.announceFailureIfNeeded(for: account)
        }
        .onChange(of: SetupSessions.state(for: account)) {
            SetupSessions.announceFailureIfNeeded(for: account)
        }
    }

    private var identityRow: some View {
        return IdentityRow(
            providerID: account.providerID,
            title: identityTitle,
            planLabel: snapshot.planLabel,
            isMenuBarAccount: isMenuBarAccount,
            isStale: providerCardHasTransientStaleState(snapshot),
            email: snapshot.accountEmail,
            showsPersistentEmail: showsPersistentEmail,
            showsConnectedChip: showsConnectedChip,
            showsMark: showsMark
        )
    }

    /// CMM4: 6 over a sign-in sentence, 4 over meters or the skeleton that stands in for them.
    private var identityToContentGap: CGFloat {
        if case .stale(let reason) = snapshot.freshness, reason.isPermanent {
            return IdentityRowMetrics.identityToSentenceGap
        }
        return IdentityRowMetrics.identityToMetersGap
    }

    @ViewBuilder private var stateContent: some View {
        Group {
            switch snapshot.freshness {
            case .pending:
                accountSkeleton
            case .live:
                bars(dimmed: false)
            case .stale(let reason):
                if reason.isPermanent {
                    signInContent(reason)
                } else {
                    bars(dimmed: true)
                }
            }
        }
        .transition(.opacity)
    }

    private func bars(dimmed: Bool) -> some View {
        // M4A: account sections only ever render real accounts — the Appearance specimen is
        // single-account and never reaches here — so the arrival key is unconditional.
        UsageBarsStack(
            windows: snapshot.windows,
            percentageMode: percentageMode,
            now: now,
            dimmed: dimmed,
            meterStyle: meterStyle,
            arrivalKey: account.key
        )
        .padding(.leading, IdentityRowMetrics.meterContentInset)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }

    /// Permanent failure on one account: one inked sentence on its own line (S2B — no glyph,
    /// no tag), then one leading-aligned action row (P4C/B3) — so a dead login never
    /// dominates its healthy siblings and no control hides at the end of a sentence. While
    /// the handoff Terminal is open it becomes a quiet waiting row with a real-progress
    /// spinner (bound to the retry cycle, not decorative).
    @ViewBuilder private func signInContent(_ reason: FailureReason) -> some View {
        // PA12: the add-account preset borrows its provider's typed never-signed-in outcome,
        // so an untyped row stops being its own third dialect of "sign in".
        let outcome = presentedSetupOutcome(for: reason, providerID: account.providerID)
        let recoveryPresentation = outcome?.recoveryPresentation
        let setupState = SetupSessions.state(for: account)
        VStack(alignment: .leading, spacing: 6) {
            // R2M1: the four branches here are all session states, and swapping one for
            // another is a body change of exactly the kind `stateContent` already
            // crossfades. The scope that drives it is the section's `sessionKey` one.
            Group {
                if let refusalMessage = setupHandoffRefusalMessage(for: setupState) {
                    VStack(alignment: .leading, spacing: 0) {
                        StatusSentence(text: refusalMessage, severity: .attention)
                        CardActionRow(trailingInset: IdentityRowMetrics.contentTrailingInset) {
                            StopWaitingButton(account: account, style: .chip(.small))
                        }
                    }
                } else if case .blockedByProviderLogin = setupState {
                    VStack(alignment: .leading, spacing: 0) {
                        StatusSentence(
                            text: "Another \(providerDisplayName) sign-in is open",
                            severity: .attention
                        )
                        CardActionRow(trailingInset: IdentityRowMetrics.contentTrailingInset) {
                            Button("Continue Setup") { SetupSessions.continueSetup(for: account) }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                                .accessibilityLabel("Continue \(providerDisplayName) setup for \(account.label)")
                        }
                    }
                } else if isWaitingForSetup {
                    VStack(alignment: .leading, spacing: 0) {
                        // S2B: the spinner is the one thing besides a brand mark allowed in
                        // the mark column — it reports progress, not severity — and taking
                        // the 15pt slot still lands the sentence on the 34pt content axis.
                        HStack(alignment: .top, spacing: IdentityRowMetrics.spacing) {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: IdentityRowMetrics.markSlotWidth, height: 15)
                            StatusSentence(
                                text: SetupSessions.mode(for: account) == .deviceCode
                                    ? "Waiting for device code…"
                                    : "Waiting for sign-in…",
                                severity: .progress,
                                indented: false
                            )
                        }
                        // B3A: the bare accent label is gone — a waiting row's one control
                        // now carries the same resting container as the sign-in chip.
                        CardActionRow(trailingInset: IdentityRowMetrics.contentTrailingInset) {
                            Button("Check Now") { onRetry() }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        StatusSentence(
                            // PA12: the presented outcome's own message, so the borrowed
                            // recovery below is answering the sentence above it.
                            text: SetupSessions.failureMessage(for: account)
                                ?? outcome?.message
                                ?? reason.message,
                            severity: SetupSessions.failureMessage(for: account) != nil
                                ? .critical
                                : .forSetupOutcome(outcome)
                        )
                        // P4C/B3: both actions share one row, and a leading row reads in
                        // reading order — the primary first, its alternative after it.
                        // R2C11 (Kyle): leading-aligned on the account title's text axis
                        // — which `CardActionRow`'s default `labelInset` already is — and
                        // bounded on the right by the usage rows' own trailing edge, so a
                        // wrapped pair of chips sits inside the meters' left/right bounds.
                        // CMM4: 8, not R4A's 12 — the buttons are the sentence's own action
                        // and sat further from it than the sentence sat from its title.
                        CardActionRow(topPadding: 8, trailingInset: IdentityRowMetrics.contentTrailingInset) {
                            Button {
                                if let recoveryPresentation {
                                    SetupSessions.performRecovery(
                                        recoveryPresentation.primaryAction,
                                        for: account,
                                        onRetry: onRetry
                                    )
                                } else {
                                    SetupSessions.openSetup(for: account, onRetry: onRetry)
                                }
                            } label: {
                                Text(recoveryPresentation?.primaryLabel ?? "Sign In")
                            }
                            .buttonStyle(SetupChipButtonStyle(size: .small))
                            .accessibilityLabel("\(recoveryPresentation?.primaryLabel ?? "Sign In") for \(account.label)")
                            if let secondaryLabel = recoveryPresentation?.secondaryLabel,
                               let secondaryAction = recoveryPresentation?.secondaryAction {
                                Button(secondaryLabel) {
                                    SetupSessions.performRecovery(
                                        secondaryAction,
                                        for: account,
                                        onRetry: onRetry
                                    )
                                }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                            } else if SetupSessions.failureMessage(for: account) != nil {
                                Button("Check Now", action: onRetry)
                                    .buttonStyle(SetupChipButtonStyle(size: .small))
                            }
                        }
                    }
                }
            }
            if !snapshot.windows.isEmpty {
                bars(dimmed: true)
            }
        }
    }

    private var isWaitingForSetup: Bool {
        SetupSessions.isWaiting(for: account)
    }

    /// Account-scoped setup payoff: the chip belongs to the row whose login completed.
    private func evaluateConnectedPayoff() {
        guard case .live = snapshot.freshness, SetupSessions.isConnected(account) else { return }
        guard !showsConnectedChip else { return }
        // M8A/S2A: as in `ProviderCardView` — the transition owns the scale, so this stays
        // a crossfade and the fade survives Reduce Motion.
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion)) {
            showsConnectedChip = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
                showsConnectedChip = false
            }
            SetupSessions.settle(for: account)
        }
    }

    private var accountSkeleton: some View {
        SkeletonMeter(labelWidth: 72, valueWidth: 38, format: meterStyle.format)
            .padding(.leading, IdentityRowMetrics.meterContentInset)
            .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }
}
