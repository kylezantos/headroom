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
    @Environment(\.colorScheme) private var scheme
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
                VStack(alignment: .leading, spacing: 22) {
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
        VStack(alignment: .leading, spacing: 10) {
            singleAccountContent
            if let activeSetupAccount {
                HStack {
                    Spacer(minLength: 0)
                    StopWaitingButton(account: activeSetupAccount)
                }
            }
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
            VStack(alignment: .leading, spacing: 7) {
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Setup failed. \(message)")
                Spacer(minLength: 4)
                Button("Check now", action: onCheckNow)
                    .buttonStyle(SetupChipButtonStyle())
            }
        }
    }

    // MARK: - Multi-account

    private var multiAccountBody: some View {
        let providerAccounts = entries.map(\.account)
        // G3: the 22pt gap chunks accounts without adding chrome; each section owns its
        // identity, so row mode has no separate provider header or account counter.
        return VStack(alignment: .leading, spacing: 22) {
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
        // Single-account keeps the "Low" chip (chiplessCriticalInk defaults off).
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
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.leading, IdentityRowMetrics.meterContentInset)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }

    /// Permanent failure the user can fix (UI-05) that is not one of the guided setup
    /// states: message + compact copyable command.
    @ViewBuilder private func actionable(_ reason: FailureReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
            if let command = recoveryCommand {
                CommandRecoveryRow(command: command)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                ProviderLogoView(providerID: providerID, size: 18)
                Text(presentation.status)
                    .font(.system(size: 12.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Setup needed. \(presentation.status)")
            HStack(spacing: 10) {
                Button(presentation.primaryLabel, action: onPrimaryAction)
                    .buttonStyle(.borderedProminent)
                if let secondaryLabel = presentation.secondaryLabel,
                   let onSecondaryAction {
                    Button(secondaryLabel, action: onSecondaryAction)
                        .buttonStyle(SetupChipButtonStyle())
                }
            }
        }
    }
}

struct ProviderCapabilityRecoveryView: View {
    let presentation: CapabilityRecoveryPresentation
    var stopWaitingAccount: ProviderAccount? = nil
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(presentation.recovery.status, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Claude Code availability. \(presentation.recovery.status)")
            HStack(spacing: 10) {
                if presentation.state(for: presentation.recovery.primaryAction) == .enabled {
                    Button(presentation.recovery.primaryLabel, action: onPrimaryAction)
                        .buttonStyle(SetupChipButtonStyle())
                }
                if let secondaryLabel = presentation.recovery.secondaryLabel,
                   let secondaryAction = presentation.recovery.secondaryAction,
                   presentation.state(for: secondaryAction) == .enabled,
                   let onSecondaryAction {
                    Button(secondaryLabel, action: onSecondaryAction)
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                }
                if let stopWaitingAccount {
                    StopWaitingButton(account: stopWaitingAccount)
                }
            }
            if let refusalMessage {
                Text(refusalMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(refusalMessage)
            }
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
    let account: ProviderAccount
    var onConfirmationPresented: () -> Void = {}
    var onStop: ((ProviderAccount) -> Void)? = nil
    var onDismiss: () -> Void = {}
    @State private var isConfirming = false

    var body: some View {
        Button("Stop waiting") {
            onConfirmationPresented()
            isConfirming = true
        }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
    /// H3a: multi-account sections opt into chipless critical numerals; single-account keeps
    /// the "Low" chip. Threaded down to every row so a stack renders one way.
    var chiplessCriticalInk: Bool = false
    /// M4A: passed straight through so both of an account's rows draw in together on the
    /// first live view of that account this launch. `nil` keeps a stack static.
    var arrivalKey: AccountKey? = nil

    var body: some View {
        if windows.isEmpty {
            Text("No usage data").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: meterStyle.format == .micro ? 12 : 9) {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(
                        window: window,
                        percentageMode: percentageMode,
                        now: now,
                        meterStyle: meterStyle,
                        dimmed: dimmed,
                        chiplessCriticalInk: chiplessCriticalInk,
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
                .font(.caption.monospaced())
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
