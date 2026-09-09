import SwiftUI
import AppKit
import HeadroomCore

/// One account's row data inside a provider card.
struct ProviderAccountEntry: Identifiable {
    let account: ProviderAccount
    let snapshot: UsageSnapshot
    var id: AccountID { account.id }
}

@MainActor
func providerCardStopWaitingAccount(
    entries: [ProviderAccountEntry],
    hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
) -> ProviderAccount? {
    entries.map(\.account).first(where: hasActiveHandoff)
}

@MainActor
func providerCardHasActiveSetupSession(
    entries: [ProviderAccountEntry],
    hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
) -> Bool {
    providerCardStopWaitingAccount(
        entries: entries,
        hasActiveHandoff: hasActiveHandoff
    ) != nil
}

func setupHandoffRefusalMessage(for state: SetupSessionState) -> String? {
    state == .blockedByOpenHandoff ? "Close setup, then retry" : nil
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
    /// Retry scoped to one account — the multi-account rows use this so watching one
    /// sign-in doesn't re-probe the whole fleet. Defaults to the whole-card retry.
    var onRetryAccount: ((ProviderAccount) -> Void)? = nil
    /// KTD4: off for the Settings > Appearance specimen. `SetupSessions` dedupes failure
    /// announcements per account and capability announcements *per provider*, so a preview
    /// card — even on a synthetic account id — would otherwise clear the real Claude
    /// capability entry and make the popover re-announce it.
    var announcesAccessibilityEvents: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsConnectedChip = false

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
    var body: some View {
        Group {
            if let presentation = capabilityRecoveryPresentation(
                   state: capabilityStatus?.state,
                   hasActiveSetupSession: hasActiveSetupSession
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
        .onAppear {
            evaluateConnectedPayoff()
            announceSetupStateIfNeeded()
            announceCapabilityStateIfNeeded()
        }
        .onChange(of: snapshot.freshness) { evaluateConnectedPayoff() }
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

    private func capabilityBody(_ presentation: CapabilityRecoveryPresentation) -> some View {
        let providerAccounts = entries.map(\.account)
        return VStack(alignment: .leading, spacing: 10) {
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
                        onRetry: onRetrySetup
                    )
                },
                onSecondaryAction: presentation.recovery.secondaryAction.map { action in
                    {
                        performRecovery(action, for: primaryAccount, onRetry: onRetrySetup)
                    }
                }
            )
            if isMultiAccount {
                // T1A: the same 26pt account gap as `multiAccountBody` — one grouping rhythm
                // whether or not the capability notice is showing.
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(entries.filter { $0.snapshot.freshness != .pending }) { entry in
                        accountSection(
                            for: entry,
                            providerAccounts: providerAccounts,
                            showsStopWaiting: false
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
            singleAccountContent
            if let activeSetupAccount {
                // B3X: this row follows whichever body rendered above it, and the four
                // bodies do not share one content axis — a guided setup card lays out at
                // its own edge, the compact recovery card behind its own 18pt mark, an
                // identity row on the 21pt axis. Ask the body rather than assume.
                CardActionRow(labelInset: singleAccountLabelInset) {
                    StopWaitingButton(account: activeSetupAccount, style: .chip(.small))
                }
            }
        }
    }

    /// B3X: mirrors the branch order of `singleAccountContent` exactly — change one and the
    /// other has to move with it, or the Stop Waiting chip drifts off the card's own axis.
    private var singleAccountLabelInset: CGFloat {
        if claudeGuidedSetupOutcome != nil || snapshot.codexConnectionAction != nil {
            0
        } else if providerSetupOutcome != nil {
            ProviderSetupRecoveryCard.contentInset
        } else {
            IdentityRowMetrics.meterContentInset
        }
    }

    @ViewBuilder private var singleAccountContent: some View {
        if let outcome = claudeGuidedSetupOutcome {
            if SetupSessions.isWaiting(for: primaryAccount) {
                ClaudeWaitingCard(
                    outcome: outcome,
                    onCheckNow: onRetrySetup,
                    onReopen: {
                        performRecovery(
                            outcome.recoveryPresentation.primaryAction,
                            for: primaryAccount,
                            onRetry: onRetrySetup
                        )
                    }
                )
            } else {
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
            }
        } else if let action = snapshot.codexConnectionAction {
            let presentation = providerSetupOutcome?.recoveryPresentation
            VStack(alignment: .leading, spacing: 13) {
                if SetupSessions.isWaiting(for: primaryAccount) {
                    CodexWaitingCard(
                        mode: SetupSessions.mode(for: primaryAccount),
                        onCheckNow: onRetrySetup,
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
            let presentation = outcome.recoveryPresentation
            ProviderSetupRecoveryCard(
                providerID: providerID,
                presentation: presentation,
                onPrimaryAction: {
                    performRecovery(
                        presentation.primaryAction,
                        for: primaryAccount,
                        onRetry: onRetrySetup
                    )
                },
                onSecondaryAction: presentation.secondaryAction.map { secondaryAction in
                    {
                        performRecovery(
                            secondaryAction,
                            for: primaryAccount,
                            onRetry: onRetrySetup
                        )
                    }
                }
            )
        } else {
            // R4A: 6, in step with `AccountSectionView`'s identity→body gap — one grouping
            // rhythm whether the card carries one account or several.
            VStack(alignment: .leading, spacing: 6) {
                accountIdentityRow(for: primaryEntry)
                content
            }
            // M4A/S2A: the `.pending → .live` body swap is opacity, so it keeps its timing
            // under Reduce Motion. This is the innermost scope around the switching body,
            // which is why it — not the tile scope above — drives the `.transition`.
            // The fill and numeral roll inside the inserted body belong to `UsageBarView`.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion),
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
            VStack(alignment: .leading, spacing: 0) {
                StatusSentence(text: message, severity: .critical, indented: false)
                    .accessibilityLabel("Setup failed. \(message)")
                // B3X: the sentence above is `indented: false`, so the chip label matches it
                // at the card's own edge rather than the 34pt axis it never reaches here.
                CardActionRow(labelInset: 0) {
                    Button("Check Now", action: onCheckNow)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                }
            }
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
        showsStopWaiting: Bool
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
            onRetry: { (onRetryAccount ?? { _ in onRetrySetup() })(entry.account) }
        )
    }

    /// The guided-setup payoff: when either provider goes live after its Terminal handoff,
    /// stop only that provider's retries and show the "Connected" chip briefly.
    /// Single-account mode only — in multi-account mode each `AccountSectionView`
    /// settles its own session, and letting both observe the primary account raced
    /// nondeterministically (code-review finding).
    private func evaluateConnectedPayoff() {
        guard !isMultiAccount else { return }
        guard case .live = snapshot.freshness else { return }
        guard SetupSessions.isConnected(primaryAccount) else { return }
        guard !showsConnectedChip else { return }
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
            SetupSessions.settle(for: primaryAccount)
        }
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
            showsConnectedChip: showsConnectedChip
        )
    }

    @ViewBuilder private var content: some View {
        Group {
            switch snapshot.freshness {
            case .pending:
                pendingSkeleton
            case .live:
                bars(for: snapshot, dimmed: false)
            case .stale(let reason):
                staleContent(reason)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func staleContent(_ reason: FailureReason) -> some View {
        if reason.isPermanent {
            actionable(reason)
            if !snapshot.windows.isEmpty { bars(for: snapshot, dimmed: true) }
        } else {
            bars(for: snapshot, dimmed: true)
        }
    }

    /// M4A: the Appearance specimen is inert (KTD4) and W4's `.id(meterStyle)` crossfade
    /// rebuilds it on every style change, so it never stages an arrival — the same
    /// `announcesAccessibilityEvents: false` that keeps the preview out of the real
    /// accessibility and setup state keeps it out of the arrival registry.
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

/// Compact fallback for typed setup outcomes that do not need the richer first-run
/// cards. Labels and available actions come directly from the core recovery table.
private struct ProviderSetupRecoveryCard: View {
    let providerID: ProviderID
    let presentation: ProviderRecoveryPresentation
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    /// B3X: this card carries its own mark column rather than the identity row's, so its
    /// content axis is its own 18pt mark plus 7pt gap — not `IdentityRowMetrics`' 21.
    private static let markSlotWidth: CGFloat = 18
    private static let markGap: CGFloat = 7
    static let contentInset = markSlotWidth + markGap

    var body: some View {
        // P4C/B3: status line first, then one leading action row — the primary first.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Self.markGap) {
                ProviderLogoView(providerID: providerID, size: Self.markSlotWidth)
                Text(presentation.status)
                    .font(.system(size: 12.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Setup needed. \(presentation.status)")
            // B3X: the chip labels land under the status text, not under the mark.
            CardActionRow(labelInset: Self.contentInset) {
                // B3: the last native control inside a popover card — a `.borderedProminent`
                // button beside two chips — becomes a chip. One recipe, position carries
                // primacy.
                Button(presentation.primaryLabel, action: onPrimaryAction)
                    .buttonStyle(SetupChipButtonStyle(size: .small))
                if let secondaryLabel = presentation.secondaryLabel,
                   let onSecondaryAction {
                    Button(secondaryLabel, action: onSecondaryAction)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                }
            }
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
            messages
            switch placement {
            case .cardFoot:
                CardActionRow {
                    primaryButton
                    secondaryButton
                    stopWaitingButton
                }
            case .settingsGroup:
                HStack(spacing: 8) {
                    primaryButton
                    secondaryButton
                    stopWaitingButton
                }
                .padding(.top, 8)
            }
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
/// PA11b brought the chip's container back at rest, so the box now overhangs the axis by its
/// own 10pt at all times rather than only on hover. That is still the right trade — B3X's
/// point was that the *label* is what has to agree with the sentence above it — and it is
/// the same overhang the footer's chips carry against the shell margin.
struct CardActionRow<Content: View>: View {
    /// Only for stacks whose own spacing already supplies part of R4A's 12pt gap.
    var topPadding: CGFloat = 12
    /// B3X: where the first chip's *label* starts, measured from this row's own leading edge.
    /// Cards whose sentences sit at their own edge (the guided setup cards, the setup-failure
    /// notice) pass 0; the inset then goes negative and the pill overhangs into the card's
    /// 13pt padding, which is the correct trade — the label is what has to agree.
    var labelInset: CGFloat = IdentityRowMetrics.meterContentInset
    @ViewBuilder let content: Content

    var body: some View {
        ActionChipFlow(spacing: 8, lineSpacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Every popover chip is `.small`, so its horizontal padding is the constant to
        // subtract; wrapped lines inherit it because `ActionChipFlow` starts each line at
        // `bounds.minX`.
        .padding(.leading, labelInset - SetupChipButtonStyle.Size.small.horizontalPadding)
        .padding(.top, topPadding)
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

    var body: some View {
        if windows.isEmpty {
            // PB11: fixed size, in step with every other line in the card.
            Text("No usage data")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            // T1A: Micro tightens 12 → 10 so an account's rows read as one block under its
            // title; Full stays 9, where the taller row already carries the separation.
            VStack(spacing: meterStyle.format == .micro ? 10 : 9) {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(
                        window: window,
                        percentageMode: percentageMode,
                        now: now,
                        meterStyle: meterStyle,
                        dimmed: dimmed,
                        arrivalKey: arrivalKey
                    )
                }
            }
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
            Button(action: copy) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 4, verticalPadding: 4))
            .foregroundStyle(.secondary)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(ClaudeSetupStyle.codeBackground(dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
