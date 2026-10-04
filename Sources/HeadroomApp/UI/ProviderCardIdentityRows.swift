#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import AppKit
import SwiftUI
import HeadroomCore

// MARK: - Unified identity row

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
    var bankedResets: Int? = nil
    var isCritical: Bool = false
    var isRevealing: Bool = false

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
            if planDisplayName != nil || (bankedResets ?? 0) > 0 {
                PlanCapsule(
                    planDisplayName: planDisplayName,
                    bankedResets: bankedResets,
                    isCritical: isCritical,
                    isRevealing: isRevealing
                )
            }
            // CMM9 (Kyle): the state chips sit *next to* the plan pill, leading-aligned,
            // rather than pushed to the row's trailing edge — one chip run reading
            // "Work · Pro · Stale" in order, not a tier on the left and a warning on the right.
            if isStale {
                staleTag
                    // RM1: the freshness scope around it is `.movement`, so the tag keeps
                    // its fade under Reduce Motion on its own.
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
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

    private static let titleSize = IdentityRowMetrics.titleSize
    private static let titleKerning = IdentityRowMetrics.titleKerning

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
        Self.helpLines(
            title: title,
            titleIsTruncated: titleIsTruncated,
            email: email,
            isMenuBarAccount: isMenuBarAccount,
            bankedHelp: PlanCapsulePresentation.helpLine(count: bankedResets)
        )
    }

    /// One tooltip, in a fixed order: truncated title, email, main-account note, banked resets.
    static func helpLines(
        title: String,
        titleIsTruncated: Bool,
        email: String?,
        isMenuBarAccount: Bool,
        bankedHelp: String?
    ) -> String? {
        var lines: [String] = []
        if titleIsTruncated { lines.append(title) }
        if let email { lines.append(email) }
        if isMenuBarAccount { lines.append(mainAccountHelp) }
        if let bankedHelp { lines.append(bankedHelp) }
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
        Self.accessibilityParts(
            title: title,
            planDisplayName: planDisplayName,
            isMenuBarAccount: isMenuBarAccount,
            isStale: isStale,
            email: email,
            showsConnectedChip: showsConnectedChip,
            bankedPhrase: PlanCapsulePresentation.accessibilityPhrase(count: bankedResets)
        )
    }

    static func accessibilityParts(
        title: String,
        planDisplayName: String?,
        isMenuBarAccount: Bool,
        isStale: Bool,
        email: String?,
        showsConnectedChip: Bool,
        bankedPhrase: String?
    ) -> String {
        var parts = [title]
        if let planDisplayName { parts.append("\(planDisplayName) plan") }
        if isMenuBarAccount { parts.append("Main account, shown in the menu bar and widgets") }
        if isStale { parts.append("Stale") }
        if let email { parts.append("signed in as \(email)") }
        if showsConnectedChip { parts.append("Connected") }
        if let bankedPhrase { parts.append(bankedPhrase) }
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
    var claimBankedResetReveal: ((AccountKey, Int?) -> Bool)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsConnectedChip = false
    @State private var isRevealingBankedResets = false
    @State private var bankedRevealCount: Int?
    @State private var bankedRevealTask: Task<Void, Never>?

    private var snapshot: UsageSnapshot { entry.snapshot }
    private var account: ProviderAccount { entry.account }

    var body: some View {
        // The session is read once per render and handed down. Every scope below wants the
        // same value, and the read stays here inside `body` so the `@Observable` coordinator
        // dependency is still registered.
        let setupState = SetupSessions.state(for: account)
        // R2M1: what the section's second animation scope keys on. See
        // `providerCardSessionKey` — the raw state's retry counter must not restage anything.
        let sessionKey = providerCardSessionKey(setupState)
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
        return VStack(alignment: .leading, spacing: identityToContentGap) {
            identityRow
            // M4A/S2A: the innermost scope around the switching body, so the crossfade —
            // not the section's height change — is what this animation drives. The wrapper
            // repeats the parent's spacing so it stays layout-neutral for the multi-view
            // `signInContent` branch. Fill and numeral roll are `UsageBarView`'s.
            VStack(alignment: .leading, spacing: identityToContentGap) {
                stateContent(setupState: setupState)
            }
            // RM1: both scopes are `.movement`; the fades in `stateContent` carry their own
            // timing under Reduce Motion, so there the section's height snaps.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                value: snapshot.freshness
            )
            // R2M1: the second scope, on the session rather than the snapshot. A row swapping
            // its sign-in block for a waiting block is the same kind of body change
            // `freshness` already crossfades; without this it hard-cut.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
                value: sessionKey
            )
            if showsStopWaiting, setupState != .blockedByOpenHandoff, !showsWaitingPhaseRow(setupState) {
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
                .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
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
        .onChange(of: snapshot.freshness) {
            evaluateConnectedPayoff()
            evaluateBankedResetReveal()
        }
        .onChange(of: snapshot.bankedResets) { evaluateBankedResetReveal() }
        .onAppear {
            evaluateConnectedPayoff()
            evaluateBankedResetReveal()
            SetupSessions.announceFailureIfNeeded(for: account)
        }
        .onChange(of: setupState) {
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
            showsMark: showsMark,
            bankedResets: snapshot.bankedResets,
            isCritical: snapshot.hasLiveCriticalResettableWindow,
            isRevealing: isRevealingBankedResets
        )
    }

    /// CMM4: 6 over a sign-in sentence, 4 over meters or the skeleton that stands in for them.
    private var identityToContentGap: CGFloat {
        if case .stale(let reason) = snapshot.freshness, reason.isPermanent {
            return IdentityRowMetrics.identityToSentenceGap
        }
        return IdentityRowMetrics.identityToMetersGap
    }

    /// SL1: live and transient stale are one branch, so a live ↔ stale flip repaints the rows
    /// in place (M3A′) instead of stacking two meter sets for the crossfade. The branches that
    /// do swap overlap in a ZStack.
    @ViewBuilder private func stateContent(setupState: SetupSessionState) -> some View {
        ZStack(alignment: .topLeading) {
            if case .pending = snapshot.freshness {
                // Review #6 (2026-09-19 sign-in review): a reset blanks this row to
                // `.pending` and then waits on the Terminal exit, scheduling no check — so
                // a skeleton here is the whole browser login with nothing said, and a
                // staging refused after it is an actionless one too.
                sessionOwnedRow(setupState: setupState)
                    .transition(HeadroomMotion.fade(HeadroomMotion.valueSpring, reduceMotion: reduceMotion))
            } else if case .stale(let reason) = snapshot.freshness, reason.isPermanent {
                signInContent(reason, setupState: setupState)
                    .transition(HeadroomMotion.fade(HeadroomMotion.valueSpring, reduceMotion: reduceMotion))
            } else {
                bars(dimmed: snapshot.freshness != .live)
                    .transition(HeadroomMotion.fade(HeadroomMotion.valueSpring, reduceMotion: reduceMotion))
            }
        }
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
    @ViewBuilder private func signInContent(
        _ reason: FailureReason,
        setupState: SetupSessionState
    ) -> some View {
        // PA12: the add-account preset borrows its provider's typed never-signed-in outcome,
        // so an untyped row stops being its own third dialect of "sign in".
        let outcome = presentedSetupOutcome(for: reason, providerID: account.providerID)
        let recoveryPresentation = outcome?.recoveryPresentation
        let failureMessage = SetupSessions.failureMessage(for: account)
        VStack(alignment: .leading, spacing: 6) {
            // R2M1: the four branches here are all session states, and swapping one for
            // another is a body change of exactly the kind `stateContent` already
            // crossfades. The scope that drives it is the section's `sessionKey` one.
            Group {
                if let refusalMessage = setupHandoffRefusalMessage(for: setupState) {
                    // V13b: nothing to open here, so an unboxed line on the action rows' text
                    // edge, with Stop Waiting as its trailing glyph.
                    CardRowStatusLine(message: refusalMessage, severity: .attention) {
                        Color.clear.frame(height: 1)
                    } trailing: {
                        StopWaitingButton(account: account, style: .glyph)
                    }
                } else if case .blockedByProviderLogin = setupState {
                    CardRowAction(
                        message: "Another \(providerDisplayName) sign-in is open",
                        accountLabel: account.label,
                        primary: .init(
                            label: "Continue \(providerDisplayName) Setup",
                            systemImage: "apple.terminal",
                            perform: { SetupSessions.continueSetup(for: account) }
                        )
                    )
                } else if isWaitingForSetup {
                    waitingPhaseRow
                } else {
                    failureRow(
                        setupState: setupState,
                        // PA12: the presented outcome's own message, so the borrowed
                        // recovery below is answering the sentence above it.
                        message: failureMessage ?? outcome?.message ?? reason.message,
                        severity: failureMessage != nil
                            ? .critical
                            : .forSetupOutcome(outcome),
                        presentation: recoveryPresentation,
                        hasFailureMessage: failureMessage != nil
                    )
                }
            }
            // RM1: a `Group` modifier reaches each branch, so every session swap here fades,
            // self-timed under Reduce Motion now the `sessionKey` scope is `.movement`.
            .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            if !snapshot.windows.isEmpty {
                bars(dimmed: true)
            }
        }
    }

    /// Review #6: the row a session owns while its snapshot carries nothing to read it off.
    /// `signInContent` composes the same two pieces once the row has its stale login outcome
    /// back, so the blanked row and the signed-out row cannot describe one state two ways.
    @ViewBuilder private func sessionOwnedRow(setupState: SetupSessionState) -> some View {
        Group {
            switch setupRowRecovery(for: setupState) {
            case .sessionOnly:
                waitingPhaseRow
            case .tryAgain:
                if let message = SetupSessions.failureMessage(for: account) {
                    failureRow(
                        setupState: setupState,
                        message: message,
                        severity: .critical,
                        presentation: nil,
                        hasFailureMessage: true
                    )
                } else {
                    accountSkeleton
                }
            case .outcomeRecovery:
                accountSkeleton
            }
        }
        // RM1: the same self-timed session fade as `signInContent`.
        .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
    }

    /// R7: the row states the phase it is actually in — opening Terminal, waiting for the
    /// user, or confirming after the window closed.
    ///
    /// S2B: the spinner is the one thing besides a brand mark allowed in the mark column —
    /// it reports progress, not severity — and taking the 15pt slot still lands the sentence
    /// on the 34pt content axis.
    ///
    /// R13/KTD12 (2026-09-19 sign-in plan): the row's Check Now is gone on every provider.
    /// Its one control is the Stop Waiting chip the section renders below, which R13 keeps
    /// reachable through the confirming phase.
    ///
    /// V13b (2026-10-03): the spinner moved from the mark column into the action glyph's
    /// column, so it sits under the terminal glyph of the row it replaced, and Stop Waiting
    /// became this line's trailing glyph instead of a chip row of its own.
    private var waitingPhaseRow: some View {
        CardRowWaitingLine(account: account, showsStopWaiting: hostsStopWaiting)
    }

    /// R13: Stop Waiting stays reachable through every session phase. While the waiting line
    /// is on screen it carries the control itself; otherwise the section's own row does.
    private var hostsStopWaiting: Bool {
        showsStopWaiting && SetupSessions.state(for: account) != .blockedByOpenHandoff
    }

    /// Whether `stateContent` is drawing `waitingPhaseRow` for this state — the same branch
    /// order `sessionOwnedRow` and `signInContent` take.
    private func showsWaitingPhaseRow(_ setupState: SetupSessionState) -> Bool {
        switch snapshot.freshness {
        case .pending:
            return setupRowRecovery(for: setupState) == .sessionOnly
        case .stale(let reason) where reason.isPermanent:
            if setupHandoffRefusalMessage(for: setupState) != nil { return false }
            if case .blockedByProviderLogin = setupState { return false }
            return isWaitingForSetup
        default:
            return false
        }
    }

    /// P4C/B3: both actions share one row, and a leading row reads in reading order — the
    /// primary first, its alternative after it. R2C11 (Kyle): leading-aligned on the account
    /// title's text axis — which `CardActionRow`'s default `labelInset` already is — and
    /// bounded on the right by the usage rows' own trailing edge, so a wrapped pair of chips
    /// sits inside the meters' left/right bounds. CMM4: 8, not R4A's 12 — the buttons are the
    /// sentence's own action and sat further from it than the sentence sat from its title.
    /// KTD12/R6: the chips come from `setupRowChips`, so the Try Again the timeout and the
    /// too-old CLI both get is the same decision the Settings row makes rather than a second
    /// copy of it here.
    private func failureRow(
        setupState: SetupSessionState,
        message: String,
        severity: StatusSentenceSeverity,
        presentation: ProviderRecoveryPresentation?,
        hasFailureMessage: Bool
    ) -> some View {
        let chips = setupRowChips(
            state: setupState,
            presentation: presentation,
            hasFailureMessage: hasFailureMessage
        )
        // V13b: the sentence is the primary chip and the second chip trails it as a glyph.
        // `setupRowChips` never returns more than two.
        return Group {
            if let primary = chips.first {
                CardRowAction(
                    message: message,
                    severity: severity,
                    accountLabel: account.label,
                    primary: rowAction(primary),
                    secondary: chips.dropFirst().first.map(rowAction)
                )
            } else {
                StatusSentence(text: message, severity: severity)
            }
        }
    }

    private func rowAction(_ chip: SetupRowChip) -> CardRowButtonAction {
        .init(label: chip.label, systemImage: chip.systemImage,
              opensElsewhere: chip.opensElsewhere, perform: { perform(chip) })
    }

    private var isWaitingForSetup: Bool {
        SetupSessions.isWaiting(for: account)
    }

    /// KTD12: every Check Now takes the same route as the one the Settings row and the
    /// recovery cards take — `performRecovery` re-runs Claude's executable search before it
    /// polls, and the other providers take its no-op branch straight through to `onRetry`.
    /// This chip used to call `onRetry` directly, which was the row alone skipping that search.
    private func perform(_ chip: SetupRowChip) {
        switch chip {
        case .tryAgain:
            SetupSessions.tryAgain(for: account, onRetry: onRetry)
        case .checkNow:
            SetupSessions.performRecovery(.checkNow, for: account, onRetry: onRetry)
        case .recovery(let action, _):
            SetupSessions.performRecovery(action, for: account, onRetry: onRetry)
        case .signIn:
            SetupSessions.openSetup(for: account, onRetry: onRetry)
        }
    }

    /// Opens the plan capsule once when this row first sees a higher live count (KTD8).
    private func evaluateBankedResetReveal() {
        guard case .live = snapshot.freshness else {
            endBankedResetReveal()
            return
        }
        let count = snapshot.bankedResets
        if isRevealingBankedResets, bankedRevealCount != count {
            endBankedResetReveal()
        }
        guard claimBankedResetReveal?(account.key, count) == true else { return }
        bankedRevealCount = count
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion)) {
            isRevealingBankedResets = true
        }
        bankedRevealTask?.cancel()
        bankedRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, bankedRevealCount == count else { return }
            withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
                isRevealingBankedResets = false
            }
        }
    }

    /// A count drop or a non-live row must close an in-flight reveal. The hold task
    /// only settles when the count still matches, so leaving it running would pin the
    /// capsule open (KTD8).
    private func endBankedResetReveal() {
        bankedRevealTask?.cancel()
        bankedRevealTask = nil
        bankedRevealCount = nil
        guard isRevealingBankedResets else { return }
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
            isRevealingBankedResets = false
        }
    }

    /// Account-scoped setup payoff: the chip belongs to the row whose login completed.
    private func evaluateConnectedPayoff() {
        guard case .live = snapshot.freshness else { return }
        guard !showsConnectedChip else { return }
        guard let payoffClaim = SetupSessions.claimConnectedPayoff(for: account) else { return }
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
            SetupSessions.settle(for: account, connectedPayoffClaim: payoffClaim)
        }
    }

    private var accountSkeleton: some View {
        SkeletonMeter(labelWidth: 72, valueWidth: 38, format: meterStyle.format)
            .padding(.leading, IdentityRowMetrics.meterContentInset)
            .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }
}
