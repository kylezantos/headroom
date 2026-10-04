import SwiftUI
import AppKit
import HeadroomCore

/// M5A: the identity a meter-style crossfade swaps on. `MeterStyle` is `Equatable`, not
/// `Hashable`, so the swap keys on the drawn recipe; `resolvedShape` rather than `shape` is
/// deliberate, because Tube stays *stored* while Full is selected but renders as Chip, so
/// keying on the raw shape would dissolve a card into an identical copy of itself. It lives
/// beside the card rather than in the popover because the card is what gets swapped — the
/// Appearance specimen composes the same view and keys on the same recipe.
enum MeterRecipeKey {
    static func key(for style: MeterStyle) -> String {
        "\(style.format.rawValue).\(style.resolvedShape.rawValue).\(style.fill.rawValue)"
    }
}

/// One account's row data inside a provider card.
struct ProviderAccountEntry: Identifiable {
    let account: ProviderAccount
    let snapshot: UsageSnapshot
    var id: AccountID { account.id }
}

/// R13/KTD12 (2026-09-19 sign-in plan): Stop Waiting follows the *session*, not the open
/// handoff. `.verifying` has no handoff left — the window already closed — and the timeout
/// state's window is still the user's to close, so both had a surface with nothing on it
/// that worked. The handoff remains a fallback so nothing that relied on it regresses.
func setupSessionOffersStopWaiting(
    state: SetupSessionState,
    hasActiveHandoff: Bool
) -> Bool {
    switch state {
    case .preparing, .waiting, .verifying, .failed(.waitingTimedOut):
        true
    default:
        hasActiveHandoff
    }
}

@MainActor
func setupSessionOffersStopWaiting(for account: ProviderAccount) -> Bool {
    setupSessionOffersStopWaiting(
        state: SetupSessions.state(for: account),
        hasActiveHandoff: SetupSessions.hasActiveHandoff(for: account)
    )
}

@MainActor
func providerCardStopWaitingAccount(
    entries: [ProviderAccountEntry],
    offersStopWaiting: @MainActor (ProviderAccount) -> Bool = setupSessionOffersStopWaiting(for:)
) -> ProviderAccount? {
    entries.map(\.account).first(where: offersStopWaiting)
}

/// Deliberately still keyed on the open handoff: this is what refuses capability recovery
/// while a Terminal window owns the CLI, and verification after the window closes is not
/// that. Stop Waiting's own resolver above is the wider one.
@MainActor
func providerCardHasActiveSetupSession(
    entries: [ProviderAccountEntry],
    hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
) -> Bool {
    entries.map(\.account).contains(where: hasActiveHandoff)
}

func setupHandoffRefusalMessage(for state: SetupSessionState) -> String? {
    state == .blockedByOpenHandoff ? "Close setup, then retry" : nil
}

/// R13/KTD12: where a sign-in row's controls come from. Two failures own their action
/// outright, the waiting phases own theirs by having none of their own, and everything else
/// keeps today's typed recovery pair — which is why `.failed(.retryExhausted)` still hands
/// Codex, Grok and Cursor their Sign In and Check Now.
enum SetupRowRecovery: Equatable {
    /// R13: opening, waiting or confirming. The row's one control is Stop Waiting, which is
    /// rendered beside it; a Check Now here duplicated the checking Headroom already does.
    case sessionOnly
    /// KTD12: the bounded wait expired with the window still open. R6: and the too-old CLI,
    /// which re-stages rather than resuming — see `setupRowRecovery`.
    case tryAgain
    case outcomeRecovery
}

func setupRowRecovery(for state: SetupSessionState) -> SetupRowRecovery {
    switch state {
    case .preparing, .waiting, .verifying: .sessionOnly
    // R6: the too-old CLI joins the timeout on Try Again. A Check Now here was a dead end —
    // the account is signed out, so every refresh it forces reads "login required", which
    // the coordinator ignores, and the CLI version is re-read only when a handoff is staged.
    // Try Again with no open handoff is exactly that restaging, so an updated CLI is seen.
    case .failed(.waitingTimedOut), .failed(.updateRequired): .tryAgain
    default: .outcomeRecovery
    }
}

/// The chips a sign-in row renders, resolved outside the view so "no Check Now while
/// waiting" is provable without rendering one — on every provider, since this row is shared.
enum SetupRowChip: Equatable, Identifiable {
    case tryAgain
    case checkNow
    case recovery(SetupRecoveryAction, label: String)
    /// The untyped fallback for a row whose failure Core never typed.
    case signIn

    var label: String {
        switch self {
        case .tryAgain: "Try Again"
        case .checkNow: "Check Now"
        case .recovery(_, let label): label
        case .signIn: ProviderSignInCopy.button
        }
    }

    var id: String { label }
}

func setupRowChips(
    state: SetupSessionState,
    presentation: ProviderRecoveryPresentation?,
    hasFailureMessage: Bool
) -> [SetupRowChip] {
    switch setupRowRecovery(for: state) {
    case .sessionOnly:
        return []
    case .tryAgain:
        return [.tryAgain]
    case .outcomeRecovery:
        guard let presentation else {
            return hasFailureMessage ? [.signIn, .checkNow] : [.signIn]
        }
        var chips: [SetupRowChip] = [
            .recovery(presentation.primaryAction, label: presentation.primaryLabel),
        ]
        if let secondaryAction = presentation.secondaryAction,
           let secondaryLabel = presentation.secondaryLabel {
            chips.append(.recovery(secondaryAction, label: secondaryLabel))
        } else if hasFailureMessage {
            chips.append(.checkNow)
        }
        return chips
    }
}

/// KTD12: which shell the single-account Claude card renders. The timeout and the
/// too-old-CLI states are returning users with an account they have already set up once, so
/// they keep the compact waiting shell rather than falling through to the first-run
/// walkthrough's "Takes about 20 seconds" and its three numbered steps.
enum ClaudeSingleAccountShell: Equatable {
    case compactWaiting
    case firstRunWalkthrough
}

/// KTD12: the second line the compact shell prints under a failure sentence, or nil when
/// the sentence stands on its own.
@MainActor
func setupFailureDetail(for state: SetupSessionState) -> String? {
    guard case .failed(let failure) = state else { return nil }
    return SetupSessions.failureDetail(for: failure)
}

/// Review #4/#6 (2026-09-19 sign-in review): whether the coordinator's session — not the
/// snapshot's freshness — owns what this account's surfaces render. A reset blanks the row
/// to `.pending` (`UsageStore.invalidateUsageForAccountReset`) and its exit-signalled wait
/// schedules no check, so surfaces gated on a *stale* snapshot showed the fetching skeleton
/// for the whole browser login, and for a staging refused after it.
func setupSessionOwnsSurface(for state: SetupSessionState) -> Bool {
    setupRowRecovery(for: state) != .outcomeRecovery
}

func claudeSingleAccountShell(for state: SetupSessionState) -> ClaudeSingleAccountShell {
    // Derived rather than partitioned a second time: the two switches held the same five
    // states, so a state added to one could silently miss the other.
    setupSessionOwnsSurface(for: state) ? .compactWaiting : .firstRunWalkthrough
}

/// R2M1: every animation scope in a provider card keyed on `snapshot.freshness`, so pressing
/// "Open Claude Workspace" replaced a ~278pt Connect card with a ~190pt Waiting card, popped
/// in "Stop Waiting", swapped the header status, moved the next card up ~88pt and resized the
/// window in one frame — while `.pending → .live` in the same card got a coordinated crossfade
/// and spring. This is what the second scope keys on.
///
/// The raw state is not it: `.waiting(attempt:)` bumps its counter on every auto-retry, and a
/// counter that changes nothing on screen must not restage the card's crossfade. Normalizing
/// the attempt away is the whole job, which is why it is a free function — the rule is
/// testable without a card.
func providerCardSessionKey(_ state: SetupSessionState) -> SetupSessionState {
    if case .waiting = state { return .waiting(attempt: 0) }
    return state
}

func providerCardHasTransientStaleState(_ snapshot: UsageSnapshot) -> Bool {
    guard case .stale(let reason) = snapshot.freshness else { return false }
    return !reason.isPermanent
}

/// One provider's card (U7). Renders the explicit states off `snapshot.freshness`:
/// `.pending` first-run skeleton, `.live`, transient stale (last data kept, marked with
/// a "Stale" pill), permanent needs-reauth (actionable command), and — for Claude's
/// trust-required first run and Codex credential recovery — guided Connect/Waiting
/// cards that hand control to each provider's official CLI.
///
/// Multi-account (Jul/Sep 2026): the card takes one `ProviderAccountEntry` per configured
/// account. KTD9 gives single providers and account sections one 15pt neutral identity
/// row, while the popover-wide flip decides whether a lone row names its provider or its
/// account. G3 (R18) groups accounts with a 22pt gap and indents meters under the title.
/// The earlier eyebrow, hairline, filled H3a band, 21pt tinted provider header, and
/// account counter are all retired; the 640pt popover scroll cap absorbs taller stacks.
/// The guided full-size Connect/Waiting cards stay reserved for the single-account
/// first run — extra accounts get a compact inline sign-in row instead, since the
/// user explicitly created them from Settings and just needs the Terminal handoff.
///
/// Card padding remains the live-tuned 13pt on every side. KTD11 keeps email tooltip-only
/// unless a provider-local label is ambiguous, and KTD18 places plan, stale, menu-bar,
/// and Connected state on the relevant identity row.
struct ProviderCardView: View {
    let providerID: ProviderID
    let displayName: String
    let entries: [ProviderAccountEntry]
    let capabilityStatus: ProviderCapabilityStatus?
    let percentageMode: UsagePercentageMode
    let meterStyle: MeterStyle
    let anyProviderMultiAccount: Bool
    let now: Date
    let onRetrySetup: () -> Void
    var onRetryProvider: (() -> Void)? = nil
    /// Retry scoped to one account — the multi-account rows use this so watching one
    /// sign-in doesn't re-probe the whole fleet. Defaults to the whole-card retry.
    var onRetryAccount: ((ProviderAccount) -> Void)? = nil
    /// KTD4: off for the Settings > Appearance specimen. `SetupSessions` dedupes failure
    /// announcements per account and capability announcements *per provider*, so a preview
    /// card — even on a synthetic account id — would otherwise clear the real Claude
    /// capability entry and make the popover re-announce it.
    var announcesAccessibilityEvents: Bool = true
    var claimBankedResetReveal: ((AccountKey, Int?) -> Bool)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsConnectedChip = false
    @State private var isRevealingBankedResets = false
    @State private var bankedRevealCount: Int?
    @State private var bankedRevealTask: Task<Void, Never>?

    private var isMultiAccount: Bool { entries.count > 1 }
    private var primaryEntry: ProviderAccountEntry? { entries.first }
    private var snapshot: UsageSnapshot { primaryEntry?.snapshot ?? .pending(for: providerID) }
    private var primaryAccount: ProviderAccount {
        primaryEntry?.account ?? .builtIn(for: providerID)
    }
    private var hasActiveSetupSession: Bool {
        providerCardHasActiveSetupSession(entries: entries)
    }
    private var activeSetupAccount: ProviderAccount? {
        providerCardStopWaitingAccount(entries: entries)
    }
    /// R2M1: the card's second animation key. See `providerCardSessionKey`.
    private var sessionKey: SetupSessionState {
        providerCardSessionKey(SetupSessions.state(for: primaryAccount))
    }
    var body: some View {
        let _ = BenchCounters.hit("ProviderCardView")
        Group {
            if let presentation = capabilityRecoveryPresentation(
                   state: capabilityStatus?.state,
                   hasActiveSetupSession: hasActiveSetupSession,
                   hasRetainedReading: entries.contains { !$0.snapshot.windows.isEmpty }
               ) {
                capabilityBody(presentation)
            } else if isMultiAccount {
                multiAccountBody
            } else {
                singleAccountBody
            }
        }
        // 13pt pad / 9pt rhythm — one step above the large widget's 10/9 to account
        // for the popover's larger type (walked down from 20/14 → 16/11 → here).
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10)
        // M4A/S2A: this scope owns the *tile* — its padding, its raised shape, the height
        // it reports to the popover stack. That is travel, so Reduce Motion snaps it; the
        // body's crossfade is a separate scope below (`singleAccountContent`) and survives.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
            value: snapshot.freshness
        )
        // R2M1: the same tile scope, keyed on the session instead of the snapshot. Connect →
        // Waiting is the rarest moment in the app (first run, add account, reconnect) —
        // exactly where motion is welcome and where an ~88pt collapse reads as a glitch
        // rather than an answer. If the NSWindow resize steps live, drop this to `settle`.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
            value: sessionKey
        )
        .onAppear {
            evaluateConnectedPayoff()
            evaluateBankedResetReveal()
            announceSetupStateIfNeeded()
            announceCapabilityStateIfNeeded()
        }
        .onChange(of: snapshot.freshness) {
            evaluateConnectedPayoff()
            evaluateBankedResetReveal()
        }
        .onChange(of: snapshot.bankedResets) { evaluateBankedResetReveal() }
        .onChange(of: SetupSessions.state(for: primaryAccount)) {
            announceSetupStateIfNeeded()
        }
        .onChange(of: capabilityStatus?.state) {
            announceCapabilityStateIfNeeded()
        }
    }

    private func announceSetupStateIfNeeded() {
        guard announcesAccessibilityEvents else { return }
        SetupSessions.announceFailureIfNeeded(for: primaryAccount)
    }

    private func announceCapabilityStateIfNeeded() {
        guard announcesAccessibilityEvents else { return }
        SetupSessions.announceCapabilityIfNeeded(capabilityStatus?.state, for: providerID)
    }

    // MARK: - Single account (unchanged pre-multi-account layout)

    /// R2C22: the notice is about the *provider*, but the flat 10pt stack said it was about
    /// the first account — measured, "Install Claude Code" sat 14.5pt above "Personal", the
    /// same gap as "Personal" → "Weekly" and *smaller* than meter → meter. So the provider
    /// header and its notice become one group, and the accounts sit a full 26pt boundary
    /// below it — the same account gap `multiAccountBody` uses.
    private func capabilityBody(_ presentation: CapabilityRecoveryPresentation) -> some View {
        let providerAccounts = entries.map(\.account)
        return VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                IdentityRow(
                    providerID: providerID,
                    title: displayName,
                    planLabel: nil,
                    isMenuBarAccount: false,
                    isStale: false,
                    email: nil,
                    showsPersistentEmail: false,
                    showsConnectedChip: false
                )
                ProviderCapabilityRecoveryView(
                    presentation: presentation,
                    stopWaitingAccount: activeSetupAccount,
                    onPrimaryAction: {
                        performRecovery(
                            presentation.recovery.primaryAction,
                            for: primaryAccount,
                            onRetry: onRetryProvider ?? onRetrySetup
                        )
                    },
                    onSecondaryAction: presentation.recovery.secondaryAction.map { action in
                        {
                            performRecovery(action, for: primaryAccount, onRetry: onRetryProvider ?? onRetrySetup)
                        }
                    }
                )
            }
            if isMultiAccount {
                // T1A: the same 26pt account gap as `multiAccountBody` — one grouping rhythm
                // whether or not the capability notice is showing.
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(entries.filter { $0.snapshot.freshness != .pending }) { entry in
                        accountSection(
                            for: entry,
                            providerAccounts: providerAccounts,
                            showsStopWaiting: false,
                            // R2C22: the card already stamped the mark on its own header row
                            // above; a second copy per account row made "✳ Claude" and
                            // "✳ Personal" read as two provider titles 7pt apart.
                            showsMark: false
                        )
                    }
                }
            } else if !snapshot.windows.isEmpty {
                bars(for: snapshot, dimmed: true)
            }
        }
    }

    private var singleAccountBody: some View {
        // P4C: the card's actions end in one leading row, and `CardActionRow` owns R4A's 12pt
        // above it — so this stack no longer spaces its own children.
        VStack(alignment: .leading, spacing: 0) {
            singleAccountContentGroup
            if let activeSetupAccount, !singleAccountWaitingLineHostsStop {
                // B3X: this row follows whichever body rendered above it, and the four
                // bodies do not share one content axis — a guided setup card lays out at
                // its own edge, the compact recovery card behind its own 18pt mark, an
                // identity row on the 21pt axis. Ask the body rather than assume.
                CardActionRow(labelInset: singleAccountLabelInset) {
                    StopWaitingButton(account: activeSetupAccount, style: .chip(.small))
                }
                // R2M1: the row arrives and leaves with the session, so it dissolves into
                // the height change above rather than popping in on the same frame.
                .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
        }
        // R2M1: the crossfade half of the session split — the body dissolves while the tile
        // scope above rides the height on `valueSpring`. RM1: `.movement`, so under Reduce
        // Motion the height really does snap; the fades keep their 200ms on the transitions.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
            value: sessionKey
        )
    }

    /// B3X: mirrors the branch order of `singleAccountContent` exactly — change one and the
    /// other has to move with it, or the Stop Waiting chip drifts off the card's own axis.
    private var singleAccountLabelInset: CGFloat {
        if claudeSessionOwnedState != nil
            || claudeGuidedSetupOutcome != nil
            || snapshot.codexConnectionAction != nil {
            0
        } else {
            IdentityRowMetrics.meterContentInset
        }
    }

    /// V13b: true while the single-account recovery body is showing `CardRowWaitingLine`,
    /// which then carries Stop Waiting itself. Mirrors `singleAccountContent`'s branch order.
    private var singleAccountWaitingLineHostsStop: Bool {
        guard activeSetupAccount?.key == primaryAccount.key,
              claudeSessionOwnedState == nil,
              claudeGuidedSetupOutcome == nil,
              snapshot.codexConnectionAction == nil,
              providerSetupOutcome != nil else { return false }
        return SetupSessions.isWaiting(for: primaryAccount)
    }

    /// R2M1: `singleAccountContent`'s branches *are* the card's setup states — Connect,
    /// Waiting, the two access-recovery cards — so a session change inserts one and removes
    /// another. This Group is what carries the transition; the scope driving it is
    /// `singleAccountBody`'s `sessionKey` crossfade.
    private var singleAccountContentGroup: some View {
        Group { singleAccountContent }
            .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
    }

    @ViewBuilder private var singleAccountContent: some View {
        if let setupState = claudeSessionOwnedState {
            ClaudeWaitingCard(
                content: claudeWaitingCardContent(
                    state: setupState,
                    phase: SetupSessions.waitingPhase(for: primaryAccount),
                    hasActiveHandoff: SetupSessions.hasActiveHandoff(for: primaryAccount),
                    failureMessage: SetupSessions.failureMessage(for: primaryAccount),
                    failureDetail: setupFailureDetail(for: setupState)
                ),
                perform: { action in
                    performWaitingCardAction(action, for: primaryAccount)
                }
            )
        } else if let outcome = claudeGuidedSetupOutcome {
            VStack(alignment: .leading, spacing: 10) {
                setupFailureNotice(for: primaryAccount, onCheckNow: onRetrySetup)
                ClaudeConnectCard(
                    outcome: outcome,
                    onOpenSetup: {
                        performRecovery(
                            outcome.recoveryPresentation.primaryAction,
                            for: primaryAccount,
                            onRetry: onRetrySetup
                        )
                    }
                )
            }
        } else if let action = snapshot.codexConnectionAction {
            let presentation = providerSetupOutcome?.recoveryPresentation
            VStack(alignment: .leading, spacing: 13) {
                if SetupSessions.isWaiting(for: primaryAccount) {
                    CodexWaitingCard(
                        mode: SetupSessions.mode(for: primaryAccount),
                        onReopen: { SetupSessions.continueSetup(for: primaryAccount) }
                    )
                } else if action == .showPrivacyGuidance {
                    CodexAccessRecoveryCard(
                        kind: .permission,
                        onPrimaryAction: {
                            performRecovery(
                                presentation?.primaryAction ?? .showPrivacyGuidance,
                                for: primaryAccount,
                                onRetry: onRetrySetup
                            )
                        },
                        onCheckNow: onRetrySetup
                    )
                } else if action == .resolveStorage {
                    CodexAccessRecoveryCard(
                        kind: .storage,
                        onPrimaryAction: {
                            performRecovery(
                                presentation?.primaryAction ?? .resolveCodexStorage,
                                for: primaryAccount,
                                onRetry: onRetrySetup
                            )
                        },
                        onCheckNow: onRetrySetup
                    )
                } else {
                    setupFailureNotice(for: primaryAccount, onCheckNow: onRetrySetup)
                    CodexConnectCard(
                        action: action,
                        presentation: presentation,
                        onOpenSetup: {
                            performRecovery(
                                presentation?.primaryAction
                                    ?? (action == .reconnect ? .reconnectCodex : .connectCodex),
                                for: primaryAccount,
                                onRetry: onRetrySetup
                            )
                        },
                        onSecondaryAction: presentation?.secondaryAction.map { secondaryAction in
                            {
                                performRecovery(
                                    secondaryAction,
                                    for: primaryAccount,
                                    onRetry: onRetrySetup
                                )
                            }
                        }
                    )
                }
                if action == .reconnect, !snapshot.windows.isEmpty {
                    bars(for: snapshot, dimmed: true)
                }
            }
        } else if let outcome = providerSetupOutcome {
            // V13b (Kyle, 2026-10-03): the compact recovery card is now the same identity row
            // and action row a signed-out account shows in a multi-account card, so one account
            // and several read alike. It was a provider mark beside the status with chips below.
            let presentation = outcome.recoveryPresentation
            VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToSentenceGap) {
                accountIdentityRow(for: primaryEntry)
                if SetupSessions.isWaiting(for: primaryAccount) {
                    CardRowWaitingLine(account: primaryAccount, showsStopWaiting: singleAccountWaitingLineHostsStop)
                } else {
                    CardRowAction(
                        message: presentation.status,
                        severity: .forSetupOutcome(outcome),
                        accountLabel: primaryAccount.label,
                        primary: .init(label: presentation.primaryLabel, recovery: presentation.primaryAction) {
                            performRecovery(presentation.primaryAction, for: primaryAccount, onRetry: onRetrySetup)
                        },
                        secondary: presentation.secondaryAction.flatMap { action in
                            presentation.secondaryLabel.map { label in
                                .init(label: label, recovery: action) {
                                    performRecovery(action, for: primaryAccount, onRetry: onRetrySetup)
                                }
                            }
                        }
                    )
                }
            }
        } else {
            // R4A: in step with `AccountSectionView`'s identity→body gap — one grouping
            // rhythm whether the card carries one account or several.
            //
            // CMM4 (Kyle, 2026-09-10) supersedes R2C2's 2: the title sits a touch tighter
            // than the meter step, not half of it. See `AccountSectionView`.
            VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap) {
                accountIdentityRow(for: primaryEntry)
                content
            }
            // M4A/S2A: the `.pending → .live` body swap is opacity. This is the innermost
            // scope around the switching body, which is why it — not the tile scope above —
            // drives the `.transition`. RM1: `.movement`, and the fades in `content` carry
            // their own spring under Reduce Motion, so there only the height snaps.
            // The fill and numeral roll inside the inserted body belong to `UsageBarView`.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                value: snapshot.freshness
            )
        }
    }

    @ViewBuilder private func setupFailureNotice(
        for account: ProviderAccount,
        onCheckNow: @escaping () -> Void
    ) -> some View {
        if let message = SetupSessions.failureMessage(for: account) {
            // P4C/S2B: the warning keeps the whole line and wraps, with the critical ink
            // carrying the severity now the triangle is gone; "Check Now" drops to the
            // notice's own action row instead of sitting at the end of the sentence.
            // `indented: false` on purpose — this notice heads a guided Connect card whose
            // own content starts at the card's 13pt edge, so 34 would misalign the pair.
            // V13b: the failure sentence is its own Check Now row, boxed at the card's edge
            // (CMM6's 1pt outdent) because the guided card below lays out from there too.
            CardRowAction(
                message: message,
                severity: .critical,
                accountLabel: account.label,
                primary: .init(label: "Check Now", systemImage: "arrow.clockwise",
                               opensElsewhere: false, perform: onCheckNow),
                leadingInset: -IdentityRowMetrics.chipBoxOutdent,
                trailingInset: 0
            )
        }
    }

    // MARK: - Multi-account

    private var multiAccountBody: some View {
        let providerAccounts = entries.map(\.account)
        // G3: the inter-account gap chunks accounts without adding chrome; each section owns
        // its identity, so row mode has no separate provider header or account counter.
        // T1A widened it 22 → 26 to hold the grouping now the title sits at `.medium` and
        // the meter rows inside a section are 2pt tighter.
        return VStack(alignment: .leading, spacing: 26) {
            ForEach(entries) { entry in
                accountSection(
                    for: entry,
                    providerAccounts: providerAccounts,
                    showsStopWaiting: activeSetupAccount?.key == entry.account.key
                )
            }
        }
    }

    private func accountSection(
        for entry: ProviderAccountEntry,
        providerAccounts: [ProviderAccount],
        showsStopWaiting: Bool,
        showsMark: Bool = true
    ) -> some View {
        AccountSectionView(
            entry: entry,
            providerDisplayName: displayName,
            identityTitle: rowTitle(
                for: entry.account,
                in: providerAccounts,
                providerDisplayName: displayName
            ),
            showsPersistentEmail: showsPersistentEmail(
                for: entry.account,
                in: providerAccounts
            ),
            percentageMode: percentageMode,
            meterStyle: meterStyle,
            now: now,
            isMenuBarAccount: isMultiAccount && entry.id == entries.first?.id,
            showsStopWaiting: showsStopWaiting,
            onRetry: { (onRetryAccount ?? { _ in onRetrySetup() })(entry.account) },
            showsMark: showsMark,
            claimBankedResetReveal: claimBankedResetReveal
        )
    }

    /// Single-account reveal. Multi-account cards leave this to each `AccountSectionView`
    /// so two observers cannot acknowledge a credit with no capsule opening (KTD8).
    private func evaluateBankedResetReveal() {
        guard !isMultiAccount else { return }
        guard case .live = snapshot.freshness else {
            endBankedResetReveal()
            return
        }
        let count = snapshot.bankedResets
        if isRevealingBankedResets, bankedRevealCount != count {
            endBankedResetReveal()
        }
        guard claimBankedResetReveal?(primaryAccount.key, count) == true else { return }
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

    /// The guided-setup payoff: when either provider goes live after its Terminal handoff,
    /// stop only that provider's retries and show the "Connected" chip briefly.
    /// Single-account mode only — in multi-account mode each `AccountSectionView`
    /// settles its own session, and letting both observe the primary account raced
    /// nondeterministically (code-review finding).
    private func evaluateConnectedPayoff() {
        guard !isMultiAccount else { return }
        guard case .live = snapshot.freshness else { return }
        // Per-account, not per-view: a card rebuilt by the meter-style crossfade must not
        // replay a payoff that is already running for this connection.
        guard let payoffClaim = SetupSessions.claimConnectedPayoff(for: primaryAccount) else { return }
        // M8A/S2A: the chip's own transition drops the scale under Reduce Motion, so the
        // driving animation stays a crossfade here — silencing it would take the fade too.
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion)) {
            showsConnectedChip = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
                showsConnectedChip = false
            }
            SetupSessions.settle(for: primaryAccount, connectedPayoffClaim: payoffClaim)
        }
    }

    /// Review #4/#6: the session state while it owns the card, ahead of any outcome read off
    /// the snapshot. A reset blanks the snapshot to `.pending` before staging runs, so the
    /// compact shell was unreachable for the whole of "Sign Out & Set Up Again" — and for the
    /// update-required refusal that can follow it, which left the card actionless.
    private var claudeSessionOwnedState: SetupSessionState? {
        guard providerID == .claude else { return nil }
        let state = SetupSessions.state(for: primaryAccount)
        return setupSessionOwnsSurface(for: state) ? state : nil
    }

    /// Only typed Claude login/trust outcomes enter the guided Terminal handoff.
    private var claudeGuidedSetupOutcome: ProviderSetupOutcome? {
        guard providerID == .claude, case .stale(let reason) = snapshot.freshness else { return nil }
        switch reason.providerSetupOutcome {
        case .claudeLoginRequired, .claudeTrustRequired:
            return reason.providerSetupOutcome
        default:
            return nil
        }
    }

    private var providerSetupOutcome: ProviderSetupOutcome? {
        guard case .stale(let reason) = snapshot.freshness else { return nil }
        return reason.providerSetupOutcome
    }

    private func performRecovery(
        _ action: SetupRecoveryAction,
        for account: ProviderAccount,
        onRetry: @escaping () -> Void
    ) {
        SetupSessions.performRecovery(action, for: account, onRetry: onRetry)
    }

    private func performWaitingCardAction(
        _ action: ClaudeWaitingCardAction,
        for account: ProviderAccount
    ) {
        switch action {
        case .showTerminal:
            SetupSessions.showTerminal(for: account)
        case .tryAgain:
            SetupSessions.tryAgain(for: account, onRetry: onRetrySetup)
        }
    }

    private func accountIdentityRow(for entry: ProviderAccountEntry?) -> some View {
        let account = entry?.account ?? primaryAccount
        let providerAccounts = entries.map(\.account)
        let rowName = anyProviderMultiAccount
            ? rowTitle(for: account, in: providerAccounts, providerDisplayName: displayName)
            : displayName
        let persistentEmail = anyProviderMultiAccount
            && showsPersistentEmail(for: account, in: providerAccounts)
        return IdentityRow(
            providerID: providerID,
            title: rowName,
            planLabel: entry?.snapshot.planLabel,
            isMenuBarAccount: false,
            isStale: entry.map { providerCardHasTransientStaleState($0.snapshot) } ?? false,
            email: entry?.snapshot.accountEmail,
            showsPersistentEmail: persistentEmail,
            showsConnectedChip: showsConnectedChip,
            bankedResets: entry?.snapshot.bankedResets,
            isCritical: entry?.snapshot.hasLiveCriticalResettableWindow ?? false,
            isRevealing: isRevealingBankedResets
        )
    }

    /// SL1 (2026-09-25 motion audit): live and stale share one bars slot. As separate `switch`
    /// cases, every live ↔ stale flip removed one meter stack and inserted another, so the
    /// card held both for the crossfade — a full stack taller — and M3A′'s in-row stale fade
    /// never ran, because the rows were rebuilt rather than updated. Now only `dimmed`
    /// changes, and the rows repaint in place. The skeleton and the bars overlap in a ZStack
    /// for their one real swap, as the popover's card list does.
    @ViewBuilder private var content: some View {
        ZStack(alignment: .topLeading) {
            if case .pending = snapshot.freshness {
                pendingSkeleton
                    .transition(bodyFade)
            } else {
                VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap) {
                    if let reason = permanentFailure {
                        actionable(reason)
                            .transition(bodyFade)
                    }
                    if permanentFailure == nil || !snapshot.windows.isEmpty {
                        bars(for: snapshot, dimmed: !isLive)
                            .transition(bodyFade)
                    }
                }
                .transition(bodyFade)
            }
        }
    }

    /// RM1: the body swap's fade, self-timed under Reduce Motion.
    private var bodyFade: AnyTransition {
        HeadroomMotion.fade(HeadroomMotion.valueSpring, reduceMotion: reduceMotion)
    }

    private var isLive: Bool {
        if case .live = snapshot.freshness { return true }
        return false
    }

    private var permanentFailure: FailureReason? {
        if case .stale(let reason) = snapshot.freshness, reason.isPermanent { return reason }
        return nil
    }

    /// M4A: the Appearance specimen is inert (KTD4) and W4's `.id(meterStyle)` crossfade
    /// rebuilds it on every style change, so it never stages an arrival — the same
    /// `announcesAccessibilityEvents: false` that keeps the preview out of the real
    /// accessibility and setup state keeps it out of the arrival registry.
    ///
    /// M5A follow-up: the popover's own crossfade rebuilds this card on a style change too,
    /// but the arrival stays once-per-launch there because `ArrivalRegistry` keys on the
    /// account, not on view identity — a rebuilt row reads `hasLanded` and paints its live
    /// value on the first frame.
    private var meterArrivalKey: AccountKey? {
        announcesAccessibilityEvents ? primaryAccount.key : nil
    }

    private func bars(for snapshot: UsageSnapshot, dimmed: Bool) -> some View {
        UsageBarsStack(
            windows: snapshot.windows,
            percentageMode: percentageMode,
            now: now,
            dimmed: dimmed,
            meterStyle: meterStyle,
            arrivalKey: meterArrivalKey
        )
        .padding(.leading, IdentityRowMetrics.meterContentInset)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }

    /// Varied widths (audit UI-13): real content isn't two identical bars, so the
    /// skeleton previews the true shape rather than reading as "broken". The wait names
    /// the ~20–30s first Claude poll so the delay feels intentional, not hung.
    private var pendingSkeleton: some View {
        VStack(alignment: .leading, spacing: 9) {
            SkeletonMeter(labelWidth: 72, valueWidth: 42, format: meterStyle.format)
            SkeletonMeter(labelWidth: 86, valueWidth: 36, format: meterStyle.format)
            Text("Fetching usage…")
                // PB11: was `.caption2`, the only Dynamic-Type-scaled font in a card whose
                // every other size is fixed — so it drifted out of step with the meters
                // above it under a non-default text size.
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, IdentityRowMetrics.meterContentInset)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }

    /// Permanent failure the user can fix (UI-05) that is not one of the guided setup
    /// states: message + compact copyable command.
    @ViewBuilder private func actionable(_ reason: FailureReason) -> some View {
        // S2B: the triangle goes; the sentence's attention ink is the whole signal, and it
        // starts on the 34pt content axis with the meters and command row below it.
        VStack(alignment: .leading, spacing: 8) {
            StatusSentence(
                text: reason.message,
                severity: .forSetupOutcome(reason.providerSetupOutcome)
            )
            if let command = recoveryCommand {
                CommandRecoveryRow(command: command)
                    .padding(.leading, IdentityRowMetrics.meterContentInset)
            }
        }
    }

    /// The CLI command that recovers each provider (nil for unknown providers).
    private var recoveryCommand: String? {
        switch providerID {
        case .claude: return "claude"
        case .codex: return CodexCLI.loginCommand
        default: return nil
        }
    }
}

struct ProviderCapabilityRecoveryView: View {
    /// The same recovery block renders at a popover card's foot and inside the Accounts
    /// tile. B3A sizes the chips per surface and P4C only re-places the popover one — a
    /// Settings group keeps its leading row beside the tile's other controls.
    enum Placement {
        case cardFoot
        case settingsGroup

        /// B3: one chip recipe everywhere — the thin one. The property survives so the two
        /// placements still read as a deliberate pair rather than an accident.
        var chipSize: SetupChipButtonStyle.Size { .small }

        /// PA11b: B3H's per-room chrome is gone. Both rooms now carry the resting container,
        /// so the placement no longer has an opinion about it — this was the split that let
        /// "Install Claude Code" read as prose at a card foot while the same block read as a
        /// button in Settings.
        var chipChrome: SetupChipButtonStyle.Chrome { .resting }
    }

    let presentation: CapabilityRecoveryPresentation
    var stopWaitingAccount: ProviderAccount? = nil
    var placement: Placement = .cardFoot
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    var body: some View {
        // P4C/B3: three button languages used to share one row at three sizes. Every message
        // keeps its own line now and, at a card foot, all three actions collect in one
        // leading row starting at the mark column, primary first — the same order the
        // Settings group already used.
        VStack(alignment: .leading, spacing: 0) {
            switch placement {
            case .cardFoot:
                cardFoot
            case .settingsGroup:
                messages
                HStack(spacing: 8) {
                    primaryButton
                    secondaryButton
                    stopWaitingButton
                }
                .padding(.top, 8)
            }
        }
    }

    /// V13b (Kyle, 2026-10-03): at a card foot the status sentence is the primary action's
    /// row, the secondary trails it as a glyph, and Stop Waiting follows as a ✕ — the same
    /// language as an account row. A refused or disabled primary leaves an unboxed line that
    /// still carries whatever actions remain. Settings keeps its chips beside the tile's
    /// other controls.
    @ViewBuilder private var cardFoot: some View {
        let recovery = presentation.recovery
        VStack(alignment: .leading, spacing: 8) {
            if presentation.state(for: recovery.primaryAction) == .enabled {
                CardRowAction(
                    message: recovery.status,
                    accountLabel: nil,
                    primary: .init(label: recovery.primaryLabel, recovery: recovery.primaryAction,
                                   perform: onPrimaryAction),
                    secondary: secondaryRowAction
                ) {
                    stopWaitingGlyph
                }
            } else {
                CardRowStatusLine(message: recovery.status, severity: .attention) {
                    Color.clear.frame(height: 1)
                } trailing: {
                    if let secondaryRowAction {
                        CardRowGlyphButton(label: secondaryRowAction.label,
                                           systemImage: secondaryRowAction.systemImage,
                                           accountLabel: nil,
                                           action: secondaryRowAction.perform)
                    }
                    stopWaitingGlyph
                }
            }
            if let refusalMessage {
                CardRowStatusLine(message: refusalMessage, severity: .attention) {
                    Color.clear.frame(height: 1)
                } trailing: {
                    EmptyView()
                }
                .accessibilityLabel(refusalMessage)
            }
        }
    }

    private var secondaryRowAction: CardRowButtonAction? {
        guard let label = presentation.recovery.secondaryLabel,
              let action = presentation.recovery.secondaryAction,
              presentation.state(for: action) == .enabled,
              let onSecondaryAction else { return nil }
        return .init(label: label, recovery: action, perform: onSecondaryAction)
    }

    @ViewBuilder private var stopWaitingGlyph: some View {
        if let stopWaitingAccount {
            StopWaitingButton(account: stopWaitingAccount, style: .glyph)
        }
    }

    /// S2B: the triangle is gone from both lines. A missing or unconfirmed CLI is an
    /// attention state, and so is a handoff standing in the way of the retry — the same
    /// "Close setup, then retry" sentence an account row shows, so it takes the same ink.
    /// Indented only at a card foot, where an identity row sets the 34pt axis above it.
    private var messages: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusSentence(
                text: presentation.recovery.status,
                severity: .attention,
                indented: placement == .cardFoot
            )
            .accessibilityLabel("Claude Code availability. \(presentation.recovery.status)")
            if let refusalMessage {
                StatusSentence(
                    text: refusalMessage,
                    severity: .attention,
                    indented: placement == .cardFoot
                )
                .accessibilityLabel(refusalMessage)
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        if presentation.state(for: presentation.recovery.primaryAction) == .enabled {
            Button(presentation.recovery.primaryLabel, action: onPrimaryAction)
                .buttonStyle(SetupChipButtonStyle(size: placement.chipSize, chrome: placement.chipChrome))
        }
    }

    /// B3A: was a bare label with no font or ink of its own sitting beside a filled chip;
    /// it now takes the same chip so the row speaks one language.
    @ViewBuilder private var secondaryButton: some View {
        if let secondaryLabel = presentation.recovery.secondaryLabel,
           let secondaryAction = presentation.recovery.secondaryAction,
           presentation.state(for: secondaryAction) == .enabled,
           let onSecondaryAction {
            Button(secondaryLabel, action: onSecondaryAction)
                .buttonStyle(SetupChipButtonStyle(size: placement.chipSize, chrome: placement.chipChrome))
        }
    }

    @ViewBuilder private var stopWaitingButton: some View {
        if let stopWaitingAccount {
            StopWaitingButton(
                account: stopWaitingAccount,
                style: placement == .cardFoot ? .chip(.small) : .bordered
            )
        }
    }

    private var refusalMessage: String? {
        let actions = [presentation.recovery.primaryAction, presentation.recovery.secondaryAction]
            .compactMap { $0 }
        for action in actions {
            if case .refused(let message) = presentation.state(for: action) { return message }
        }
        return nil
    }
}

struct StopWaitingButton: View {
    /// B3A: one button, two surfaces. Inside a popover card it wears the chip, because a
    /// card foot must not mix a native bordered control with the chips beside it; a
    /// Settings row keeps the native small bordered button its neighbours use.
    enum Style: Equatable {
        case chip(SetupChipButtonStyle.Size)
        case bordered
        /// V13b: the trailing ✕ on an account's waiting line.
        case glyph
    }

    let account: ProviderAccount
    var style: Style = .bordered
    var onConfirmationPresented: () -> Void = {}
    var onStop: ((ProviderAccount) -> Void)? = nil
    var onDismiss: () -> Void = {}
    @State private var isConfirming = false

    var body: some View {
        button
            .accessibilityLabel("Stop waiting for setup for \(account.label)")
            .confirmationDialog(
                "Stop waiting for setup?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Stop Waiting") {
                    if let onStop {
                        onStop(account)
                    } else {
                        SetupSessions.forceCancel(for: account)
                    }
                    onDismiss()
                }
                Button("Keep Waiting", role: .cancel, action: onDismiss)
            } message: {
                Text("Headroom stops waiting immediately. The Terminal window may still be open; close it by hand if you no longer need it.")
            }
    }

    @ViewBuilder private var button: some View {
        let action = Button("Stop Waiting") {
            onConfirmationPresented()
            isConfirming = true
        }
        switch style {
        case .glyph:
            CardRowGlyphButton(label: "Stop Waiting", systemImage: "xmark", accountLabel: account.label) {
                onConfirmationPresented()
                isConfirming = true
            }
        case .chip(let size):
            action.buttonStyle(SetupChipButtonStyle(size: size))
        case .bordered:
            action
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

/// P4C/B3 (Sep 2026): the one action row every card and account section ends with —
/// **leading**-aligned, R4A's 12pt under the sentence it answers, 8pt between chips, the
/// primary chip first because a leading row reads left to right. Messages keep their own line
/// above it, so nothing sits at the trailing end of a sentence any more.
///
/// B3X (Kyle, Sep 2026): "have it line up with the messages and service title instead of the
/// icon." B3 aligned the chip's *box* to the mark column; what the eye reads is the chip's
/// **label**. So the row aligns its first label, not its first frame: it insets itself by
/// `labelInset` minus the chip's own horizontal padding, which lands the label exactly on
/// `labelInset`. At the default that is the 34pt content axis (13 card padding + 21) shared
/// by the identity title, the status sentence and every meter label.
///
/// PA11b brought the chip's container back at rest, so the box overhung the axis by its own
/// padding at all times rather than only on hover.
///
/// **CMM2 (Kyle, 2026-09-09) supersedes B3X's overhang:** "the edge should be left aligned
/// with the account title." With a resting container on every chip the box *is* the thing the
/// eye lines up, so the row now insets by `labelInset` itself and the chip's leading edge
/// lands on the title's text axis; the trailing edge likewise stops on the meters' right edge.
struct CardActionRow<Content: View>: View {
    /// Only for stacks whose own spacing already supplies part of R4A's 12pt gap.
    var topPadding: CGFloat = 12
    /// B3X: where the first chip's *label* starts, measured from this row's own leading edge.
    /// Cards whose sentences sit at their own edge (the guided setup cards, the setup-failure
    /// notice) pass 0; the inset then goes negative and the pill overhangs into the card's
    /// 13pt padding, which is the correct trade — the label is what has to agree.
    var labelInset: CGFloat = IdentityRowMetrics.meterContentInset
    /// R2C11 (Kyle): where the row's *max width* stops. An account's action row runs to the
    /// trailing edge of the usage rows above it, so its chips sit inside the same left/right
    /// bounds as the meters and a wrapped second line breaks on the same edge. Defaulted to 0
    /// because a card-level row — the guided setup cards, the spend tile — ends at the card's
    /// own padding, not at a meter column that isn't there.
    var trailingInset: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        ActionChipFlow(spacing: 8, lineSpacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // CMM2: the chip *box* sits on the axis; wrapped lines inherit it because
        // `ActionChipFlow` starts each line at `bounds.minX`.
        // CMM6 (Kyle, 2026-09-10): outdented by 1pt. Mechanically the box edge and the
        // title ink shared one x within 0.5pt; optically a filled, ringed box reads heavier
        // than a glyph's edge, so it hangs a hair outside the axis the way a bullet does.
        .padding(.leading, labelInset - IdentityRowMetrics.chipBoxOutdent)
        // R2C11: the trailing bound is the meter column's right edge, box-to-edge as well.
        .padding(.trailing, trailingInset)
        .padding(.top, topPadding)
    }
}

/// O15/V13b (Kyle, 2026-10-03; `design/on-card-row-button-variations.html`): an account
/// row's status sentence *is* its primary action, so the separate chip row is gone. Four
/// boxed chips across two signed-out accounts outweighed the meters; one quiet row per
/// account, with the secondary action reduced to a trailing glyph, is lighter and shorter.
///
/// The box sits on the account title's axis with CMM6's 1pt outdent, like the chips it
/// replaces. The action glyph sits inside the box, one column in from the brand mark, and the
/// sentence follows it. The action's own label ("Sign In") moves to the help tooltip and the
/// accessibility label, because the sentence already says what the click is for.
struct CardRowAction<Accessory: View>: View {
    typealias Action = CardRowButtonAction

    let message: String
    let severity: StatusSentenceSeverity
    /// Names the account in the accessibility label ("Sign In for Work"); nil on a
    /// provider-level row, which has no account to name.
    let accountLabel: String?
    let primary: Action
    let secondary: Action?
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    /// Extra trailing controls after the secondary glyph — the capability card's Stop Waiting.
    let accessory: Accessory

    init(
        message: String,
        severity: StatusSentenceSeverity = .attention,
        accountLabel: String?,
        primary: Action,
        secondary: Action? = nil,
        leadingInset: CGFloat = CardRowMetrics.titleAxisInset,
        trailingInset: CGFloat = IdentityRowMetrics.contentTrailingInset,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.message = message
        self.severity = severity
        self.accountLabel = accountLabel
        self.primary = primary
        self.secondary = secondary
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.accessory = accessory()
    }

    @Environment(\.colorScheme) private var scheme

    /// V6′ (Kyle, 2026-10-03): no per-provider accent — the action words take the sentence's
    /// full label ink and semibold against the secondary rest. Critical rows keep the red on
    /// the verb and the glyph rather than on the whole sentence.
    private var criticalInk: Color? {
        severity == .critical ? ProviderStyle.criticalText(scheme: scheme) : nil
    }

    private var actionInk: Color {
        criticalInk ?? ProviderStyle.meterLabelInk(scheme: scheme)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Button(action: primary.perform) {
                Text(Self.accented(message, verb: primary.label, ink: actionInk))
            }
                .buttonStyle(CardRowButtonStyle(
                    systemImage: primary.systemImage,
                    criticalInk: criticalInk,
                    showsArrow: primary.opensElsewhere
                ))
                .help(primary.label)
                .accessibilityLabel(accountLabel.map { "\(primary.label) for \($0)" } ?? primary.label)
                .accessibilityValue(message)
            if let secondary {
                CardRowGlyphButton(
                    label: secondary.label,
                    systemImage: secondary.systemImage,
                    accountLabel: accountLabel,
                    action: secondary.perform
                )
            }
            accessory
        }
        .cardRowAxis(leading: leadingInset, trailing: trailingInset)
    }

    /// V6: the words that name the action ("Sign in", "try again", "sign in again") take the
    /// action ink and semibold weight; the rest of the sentence stays secondary. The label is
    /// found in the sentence rather than added to it, so no copy changes. A sentence that
    /// doesn't contain its action ("Couldn't read Codex sign-in data" → Check Now) stays
    /// plain, and the tinted glyph is the only colour on the row.
    static func accented(_ message: String, verb: String, ink: Color) -> AttributedString {
        var text = AttributedString(message)
        if let range = text.range(of: verb, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].swiftUI.foregroundColor = ink
            text[range].swiftUI.font = .system(size: CardRowMetrics.fontSize, weight: .semibold)
        }
        return text
    }
}

extension CardRowAction where Accessory == EmptyView {
    init(
        message: String,
        severity: StatusSentenceSeverity = .attention,
        accountLabel: String?,
        primary: Action,
        secondary: Action? = nil,
        leadingInset: CGFloat = CardRowMetrics.titleAxisInset,
        trailingInset: CGFloat = IdentityRowMetrics.contentTrailingInset
    ) {
        self.init(message: message, severity: severity, accountLabel: accountLabel, primary: primary,
                  secondary: secondary, leadingInset: leadingInset, trailingInset: trailingInset) {
            EmptyView()
        }
    }
}

/// One action on a `CardRowAction`: the row itself, or its trailing glyph.
struct CardRowButtonAction {
    let label: String
    let systemImage: String
    /// Whether the click leaves Headroom (Terminal, a web page). Only those rows carry the
    /// trailing ↗; Check Now re-reads in place.
    var opensElsewhere: Bool = true
    let perform: () -> Void
}

extension CardRowButtonAction {
    /// A typed recovery action: the glyph and the ↗ come from where the action routes.
    @MainActor init(label: String, recovery: SetupRecoveryAction, perform: @escaping () -> Void) {
        let route = SetupSessions.recoveryRoute(for: recovery)
        self.init(label: label, systemImage: route.systemImage, opensElsewhere: route != .checkNow, perform: perform)
    }
}

/// V13b: a status line that has nothing to open (waiting on Terminal, a refused handoff) but
/// still lines up with `CardRowAction`: its leading view takes the glyph column and its
/// sentence starts where an action row's sentence does. Deliberately unboxed — a box would
/// say "click me" over a line that does nothing.
struct CardRowStatusLine<Leading: View, Trailing: View>: View {
    let message: String
    var severity: StatusSentenceSeverity = .progress
    var leadingInset: CGFloat = CardRowMetrics.titleAxisInset
    var trailingInset: CGFloat = IdentityRowMetrics.contentTrailingInset
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: CardRowMetrics.glyphGap) {
                leading
                    .frame(width: CardRowMetrics.glyphColumn)
                Text(message)
                    .font(.system(size: CardRowMetrics.fontSize, weight: .medium))
                    .foregroundStyle(severity.ink(scheme: scheme))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.leading, CardRowMetrics.leadingPadding)
            .padding(.vertical, CardRowMetrics.verticalPadding)
            trailing
        }
        .cardRowAxis(leading: leadingInset, trailing: trailingInset)
    }
}

/// V13b: an account waiting on its Terminal handoff. The spinner takes the action glyph's
/// column, so it sits under the terminal glyph of the row it replaced, and Stop Waiting is the
/// line's trailing glyph whenever this line is what's on screen (R13 keeps it reachable).
struct CardRowWaitingLine: View {
    let account: ProviderAccount
    let showsStopWaiting: Bool

    var body: some View {
        CardRowStatusLine(
            message: (SetupSessions.waitingPhase(for: account)
                ?? .waitingForUser(.signIn)).copy.title,
            severity: .progress
        ) {
            ProgressView()
                .controlSize(.mini)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        } trailing: {
            if showsStopWaiting {
                StopWaitingButton(account: account, style: .glyph)
            }
        }
    }
}

enum CardRowMetrics {
    static let fontSize: CGFloat = 11.5
    static let glyphSize: CGFloat = 11
    /// V13b: 14pt, not the brand mark's 15 — the narrowest column `apple.terminal` fits.
    static let glyphColumn: CGFloat = 14
    static let glyphGap: CGFloat = 6
    static let leadingPadding: CGFloat = 7
    static let trailingPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 6
    static let cornerRadius: CGFloat = 7
    /// A full-width row at the chips' 0.96 lurches; the mock settled on a hair of give.
    static let pressScale: CGFloat = 0.985
    /// CMM2/CMM6: the box on the account title's axis, hung 1pt outside it like the chips.
    static let titleAxisInset = IdentityRowMetrics.meterContentInset - IdentityRowMetrics.chipBoxOutdent
}

private extension View {
    /// CMM2/CMM6: box on the title axis by default. R2C11: the trailing edge is the meter
    /// column's, so the trailing glyph lines up with the usage rows above it. A card whose
    /// content starts at its own edge (the guided-setup failure notice) passes its own insets.
    func cardRowAxis(leading: CGFloat, trailing: CGFloat) -> some View {
        padding(.leading, leading)
            .padding(.trailing, trailing)
    }
}

/// V13b: the trailing secondary action — Check Now, Stop Waiting, Use Device Code — as a glyph
/// in the popover's glyph-only `HoverButtonStyle`. Its label lives in the tooltip and the
/// accessibility label.
struct CardRowGlyphButton: View {
    let label: String
    let systemImage: String
    let accountLabel: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(HoverButtonStyle(
            horizontalPadding: 7,
            verticalPadding: 7,
            hoverForegroundColor: ProviderStyle.meterLabelInk(scheme: scheme)
        ))
        .foregroundStyle(.tertiary)
        .help(label)
        .accessibilityLabel(accountLabel.map { "\(label) for \($0)" } ?? label)
    }
}

/// The account row's button on V13b's layout (Kyle, 2026-10-03). V13b's lit edge "feels
/// heavy"; V6 swapped it for a flat fill, which then matched the plan capsule, so the chrome is
/// now B's fill plus hairline (see `chrome`). From V6′ it keeps no provider accent, a semibold
/// action verb in label ink against a secondary rest, and the trailing ↗ on rows that leave
/// Headroom — it brightens and lifts a point up-and-right on hover. The rest of the sentence
/// rests one step dimmer than an account title and lifts with it.
struct CardRowButtonStyle: ButtonStyle {
    let systemImage: String
    /// Set on critical rows only: the glyph takes the red, everything else stays neutral.
    var criticalInk: Color? = nil
    var showsArrow: Bool = true

    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, systemImage: systemImage,
                  criticalInk: criticalInk, showsArrow: showsArrow, scheme: scheme)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let systemImage: String
        let criticalInk: Color?
        let showsArrow: Bool
        let scheme: ColorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        private var dark: Bool { scheme == .dark }
        private var lifted: Bool { hovering || configuration.isPressed }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: CardRowMetrics.cornerRadius, style: .continuous)
            let hoverAnimation = hovering ? HeadroomMotion.rowHoverIn : HeadroomMotion.rowHoverOut
            let pressAnimation = configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle
            HStack(alignment: .firstTextBaseline, spacing: CardRowMetrics.glyphGap) {
                Image(systemName: systemImage)
                    .font(.system(size: CardRowMetrics.glyphSize, weight: .medium))
                    .foregroundStyle(glyphStyle)
                    .frame(width: CardRowMetrics.glyphColumn)
                configuration.label
                    .font(.system(size: CardRowMetrics.fontSize, weight: .medium))
                    .foregroundStyle(textStyle)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if showsArrow {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(glyphStyle)
                        // The lift is movement, so it resolves on its own animation below and
                        // Reduce Motion keeps only the brightening.
                        .offset(x: lifted && !reduceMotion ? 1 : 0, y: lifted && !reduceMotion ? -1 : 0)
                        .animation(HeadroomMotion.resolved(hoverAnimation, .movement, reduceMotion: reduceMotion),
                                   value: lifted)
                }
            }
            .padding(.leading, CardRowMetrics.leadingPadding)
            .padding(.trailing, CardRowMetrics.trailingPadding)
            .padding(.vertical, CardRowMetrics.verticalPadding)
            .background { chrome(shape) }
            .contentShape(shape)
            // S2A: fill and ink are colour changes and keep their timing under Reduce Motion;
            // the press scale is the only movement.
            .animation(HeadroomMotion.resolved(hoverAnimation, .crossfade, reduceMotion: reduceMotion),
                       value: hovering)
            .animation(HeadroomMotion.resolved(pressAnimation, .crossfade, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? CardRowMetrics.pressScale : 1)
            .animation(HeadroomMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
            .onHover { hovering = $0 }
        }

        /// B (Kyle, 2026-10-03; `design/on-card-row-vs-plan-chip.html`): V6′'s flat grey fill
        /// was the plan capsule's material, so the row read as a long capsule. A lighter fill
        /// plus a 0.5pt edge separates them — the plan capsule has no edge. White over the dark
        /// card, black over the light one. (C, the recessed/raised plate, was tried live first.)
        private func chrome(_ shape: RoundedRectangle) -> some View {
            let base = dark ? Color.white : Color.black
            return shape
                .fill(base.opacity(Self.fillSteps[step]))
                .overlay(shape.strokeBorder(base.opacity(Self.edgeSteps[step]), lineWidth: 0.5))
        }

        private var step: Int { configuration.isPressed ? 2 : (hovering ? 1 : 0) }
        /// Hover is a small step on a control seen many times a day; the edge firming up does
        /// more of the work than the fill.
        private static let fillSteps: [Double] = [0.03, 0.055, 0.08]
        private static let edgeSteps: [Double] = [0.10, 0.14, 0.14]

        /// One concrete ink at two opacities, never `.secondary` ↔ a `Color`: SwiftUI can't
        /// interpolate a hierarchical style into a colour, so that swap hard-cut the whole
        /// sentence from dim to bright in one frame — the hover's flash.
        private var labelInk: Color { ProviderStyle.meterLabelInk(scheme: scheme) }

        private var textStyle: Color {
            labelInk.opacity(lifted ? 0.88 : 0.62)
        }

        /// The leading glyph and the ↗: dim at rest, brighter on hover; a critical row's red
        /// throughout.
        private var glyphStyle: Color {
            if let criticalInk { return criticalInk }
            return labelInk.opacity(lifted ? 0.78 : 0.42)
        }
    }
}

extension SetupRowChip {
    /// V13b: the glyph says where the click lands. `apple.terminal` is every handoff to the
    /// official CLI (Sign In, Try Again, workspace approval), `globe` opens a web page,
    /// `arrow.clockwise` re-reads the account.
    @MainActor var opensElsewhere: Bool { systemImage != "arrow.clockwise" }

    @MainActor var systemImage: String {
        switch self {
        case .tryAgain, .signIn: "apple.terminal"
        case .checkNow: "arrow.clockwise"
        case .recovery(let action, _): SetupSessions.recoveryRoute(for: action).systemImage
        }
    }
}

extension SetupSessions.RecoveryRoute {
    var systemImage: String {
        switch self {
        case .documentation, .privacyGuidance: "globe"
        // The device-code flow also runs in Terminal, but it sits beside a Terminal sign-in
        // as the alternative, so it needs a glyph of its own: the code is what you type.
        case .setup(.deviceCode): "number"
        case .setup, .workspaceTrust, .cursorTools: "apple.terminal"
        case .checkNow: "arrow.clockwise"
        }
    }
}

/// B3: a row that runs out of width wraps to a second leading-aligned line rather than
/// shrinking a chip or truncating a label — so every subview is measured at its ideal size
/// and a line break is the only thing that gives. Three chips only co-occur while a handoff
/// is open (`StopWaitingButton`), so the second line is the exception, not the resting state.
struct ActionChipFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let lines = lines(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var y = bounds.minY
        for line in lines(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func lines(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extended = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width
            if !current.indices.isEmpty, extended > maxWidth {
                lines.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = extended
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}


// MARK: - Shared meter building blocks

/// One meter stack for every card body — single-account, multi-account, dimmed.
/// A single definition so the two render paths can never drift apart. (H3a retired the
/// compact recipe: multi-account sections now render at the regular scale.)
struct UsageBarsStack: View {
    let windows: [UsageWindow]
    let percentageMode: UsagePercentageMode
    let now: Date
    let dimmed: Bool
    let meterStyle: MeterStyle
    /// M4A: passed straight through so both of an account's rows draw in together on the
    /// first live view of that account this launch. `nil` keeps a stack static.
    var arrivalKey: AccountKey? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if windows.isEmpty {
            // PB11: fixed size, in step with every other line in the card.
            Text("No usage data")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            // T1A: Micro tightens 12 → 10 so an account's rows read as one block under its
            // title. FS1 (Kyle, Sep 2026): Full goes the other way, 9 → 12 — three stacked
            // label-over-gauge rows at 9 packed into a wall, and the row's own internal gap
            // grew to 7, so the gap *between* rows has to stay clearly the larger of the two.
            VStack(spacing: meterStyle.format == .micro ? 10 : 12) {
                // RI1 (2026-09-25 motion audit): rows are keyed by window kind, not position.
                // Keyed by offset, a window appearing or leaving handed each row below it the
                // next row's window, so "Weekly 40%" rolled into "5-hour 12%" — motion that
                // claimed a value changed when a row had only moved. Now a row keeps its
                // window, and one that arrives or leaves fades.
                ForEach(Self.keyedRows(windows), id: \.key) { row in
                    UsageBarView(
                        window: row.window,
                        percentageMode: percentageMode,
                        now: now,
                        meterStyle: meterStyle,
                        dimmed: dimmed,
                        arrivalKey: arrivalKey
                    )
                    .transition(HeadroomMotion.fade(HeadroomMotion.valueSpring, reduceMotion: reduceMotion))
                }
            }
            // RI1: a poll that adds or ages out a row is otherwise an unanimated update, so
            // the row's fade never ran and the rows below it jumped. Keyed on the kinds only,
            // so a value change inside a row stays `UsageBarView`'s own landing.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                value: windows.map(\.kind)
            )
        }
    }
}

extension UsageBarsStack {
    /// RI1: a window's kind, plus which occurrence of that kind it is, so two windows that
    /// share a kind still get distinct, stable identities.
    struct RowKey: Hashable {
        let kind: WindowKind
        let occurrence: Int
    }

    nonisolated static func keyedRows(_ windows: [UsageWindow]) -> [(key: RowKey, window: UsageWindow)] {
        var seen: [WindowKind: Int] = [:]
        return windows.map { window in
            let occurrence = seen[window.kind, default: 0]
            seen[window.kind] = occurrence + 1
            return (RowKey(kind: window.kind, occurrence: occurrence), window)
        }
    }
}

/// Varied-width placeholder meter (audit UI-13): previews the true row shape so the
/// pending state reads intentional, not broken. Shared by both card paths.
struct SkeletonMeter: View {
    let labelWidth: CGFloat
    let valueWidth: CGFloat
    let format: GaugeFormat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch format {
        case .full:
            VStack(alignment: .leading, spacing: 5) {
                skeletonTextRow
                Capsule().fill(track).frame(height: MeterGeometry.fullTrackHeight)
            }
        case .micro:
            HStack {
                skeletonLabel
                Spacer(minLength: 6)
                Capsule()
                    .fill(track)
                    .frame(
                        width: MeterGeometry.microChipWidth,
                        height: MeterGeometry.microChipHeight
                    )
                skeletonValue
            }
        }
    }

    private var skeletonTextRow: some View {
        HStack {
            skeletonLabel
            Spacer(minLength: 6)
            skeletonValue
        }
    }

    private var skeletonLabel: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(track)
            .frame(width: labelWidth, height: 13)
    }

    private var skeletonValue: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(track)
            .frame(width: valueWidth, height: 13)
    }

    private var track: Color { ProviderStyle.barTrack(scheme: scheme) }
}

// MARK: - Shared command recovery row

/// Compact copyable command row shared by the single-account actionable state.
private struct CommandRecoveryRow: View {
    let command: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text("$ \(command)")
                // PB11: the same 11pt monospaced the setup cards' command disclosure uses.
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            // R2M9: the third of the app's copy buttons, on the same shared confirmation.
            CopyFeedbackButton(
                copy: copy,
                label: "Copy command",
                horizontalPadding: 4,
                verticalPadding: 4
            )
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(ClaudeSetupStyle.codeBackground(dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func copy() -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(command, forType: .string)
    }
}
