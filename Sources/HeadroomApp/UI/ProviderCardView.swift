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
func providerCardHasActiveSetupSession(
    entries: [ProviderAccountEntry],
    hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
) -> Bool {
    entries.contains { hasActiveHandoff($0.account) }
}

func setupHandoffRefusalMessage(for state: SetupSessionState) -> String? {
    state == .blockedByOpenHandoff ? "Close setup, then retry" : nil
}

/// One provider's card (U7). Renders the explicit states off `snapshot.freshness`:
/// `.pending` first-run skeleton, `.live`, transient stale (last data kept, marked with
/// a "Stale" pill), permanent needs-reauth (actionable command), and — for Claude's
/// trust-required first run and Codex credential recovery — guided Connect/Waiting
/// cards that hand control to each provider's official CLI.
///
/// Multi-account (Jul 2026): the card takes one `ProviderAccountEntry` per configured
/// account. A single account renders exactly the pre-multi-account layout (no labels,
/// no bands — nothing changed for the common case). Two or more accounts stack labeled
/// sections inside the one provider card. G1 (Jul 2026 multi-account design review)
/// replaced the uppercase eyebrow + hairline dividers with a plain bold identity row per
/// account, grouped by an 18pt proximity gap — a filled band variant (H3a) was built and
/// reverted after live review: on the real glass card it read as slabs and zoned Claude
/// into sections while sibling cards stayed open (PRODUCT.md #1). The compact meter
/// recipe is dropped — every section renders at the regular scale, with the 640pt
/// popover scroll cap absorbing taller five-account stacks.
/// The guided full-size Connect/Waiting cards stay reserved for the single-account
/// first run — extra accounts get a compact inline sign-in row instead, since the
/// user explicitly created them from Settings and just needs the Terminal handoff.
///
/// Type + spacing were tuned in the mockup: 16pt bold card titles, 14pt vertical rhythm
/// between rows, 20pt card padding. Plan pills return in multi-account mode as the
/// natural differentiator ("Max" vs "Pro"); they stay hidden with one account
/// (density audit).
struct ProviderCardView: View {
    let providerID: ProviderID
    let displayName: String
    let entries: [ProviderAccountEntry]
    let capabilityStatus: ProviderCapabilityStatus?
    let percentageMode: UsagePercentageMode
    let now: Date
    let onRetrySetup: () -> Void
    /// Retry scoped to one account — the multi-account rows use this so watching one
    /// sign-in doesn't re-probe the whole fleet. Defaults to the whole-card retry.
    var onRetryAccount: ((ProviderAccount) -> Void)? = nil

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
        // A refresh replacing the pending skeleton (or a stale card recovering) cross-fades
        // and springs its height change rather than hard-cutting — the arrival of a poll
        // cycle, felt not flashed. Snaps instead under Reduce Motion.
        .animation(reduceMotion ? nil : HeadroomMotion.valueSpring, value: snapshot.freshness)
        .onAppear {
            evaluateConnectedPayoff()
            SetupSessions.announceFailureIfNeeded(for: primaryAccount)
            SetupSessions.announceCapabilityIfNeeded(
                capabilityStatus?.state,
                for: providerID
            )
        }
        .onChange(of: snapshot.freshness) { evaluateConnectedPayoff() }
        .onChange(of: SetupSessions.state(for: primaryAccount)) {
            SetupSessions.announceFailureIfNeeded(for: primaryAccount)
        }
        .onChange(of: capabilityStatus?.state) {
            SetupSessions.announceCapabilityIfNeeded(
                capabilityStatus?.state,
                for: providerID
            )
        }
    }

    // MARK: - Single account (unchanged pre-multi-account layout)

    private func capabilityBody(_ presentation: CapabilityRecoveryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ProviderCapabilityRecoveryView(
                presentation: presentation,
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
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(entries.filter { $0.snapshot.freshness != .pending }) { entry in
                        AccountSectionView(
                            entry: entry,
                            providerDisplayName: displayName,
                            percentageMode: percentageMode,
                            now: now,
                            isMenuBarAccount: entry.id == entries.first?.id,
                            onRetry: { (onRetryAccount ?? { _ in onRetrySetup() })(entry.account) }
                        )
                    }
                }
            } else if !snapshot.windows.isEmpty {
                bars(for: snapshot, dimmed: true)
            }
        }
    }

    @ViewBuilder private var singleAccountBody: some View {
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
            VStack(alignment: .leading, spacing: 9) {
                header
                content
            }
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
        // G1: sections stack at 18pt with no dividers — a real gap step above the 7pt
        // header-to-meters bind, so proximity alone carries the account grouping.
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: 18) {
                ForEach(entries) { entry in
                    AccountSectionView(
                        entry: entry,
                        providerDisplayName: displayName,
                        percentageMode: percentageMode,
                        now: now,
                        isMenuBarAccount: entry.id == entries.first?.id,
                        onRetry: { (onRetryAccount ?? { _ in onRetrySetup() })(entry.account) }
                    )
                }
            }
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
        guard SetupSessions.isConnected(primaryAccount) else { return }
        guard !showsConnectedChip else { return }
        withAnimation(reduceMotion ? nil : HeadroomMotion.valueSpring) { showsConnectedChip = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(reduceMotion ? nil : HeadroomMotion.settle) { showsConnectedChip = false }
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

    /// The per-card "Updated N min ago" was removed here — both providers poll on one
    /// cycle, so it reads once in the popover header (PopoverView) instead of twice.
    /// Header mirrors the large widget's recipe (icon ≈ 1.33× the title size, title in
    /// the shared brand text-accent) so popover and widgets read as one family.
    private var header: some View {
        HStack(spacing: 6) {
            ProviderLogoView(providerID: providerID, size: 21)
            Text(displayName)
                .font(.system(size: 16, weight: .semibold))
                .kerning(-0.2)
                .foregroundStyle(ProviderStyle.textAccent(for: providerID, scheme: scheme))
            if isMultiAccount {
                // Quiet count so a five-account stack announces its size up front.
                Text("\(entries.count) accounts")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 6)
            if showsConnectedChip {
                connectedChip
                    .transition(.opacity)
            }
        }
    }

    private var connectedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Connected")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(ClaudeSetupStyle.connectedInk(dark: scheme == .dark))
        .padding(.horizontal, 8).padding(.vertical, 2.5)
        .background(ClaudeSetupStyle.connectedBackground(dark: scheme == .dark), in: Capsule())
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
            stalePill(reason)
        }
    }

    private func bars(for snapshot: UsageSnapshot, dimmed: Bool) -> some View {
        // Single-account keeps the "Low" chip (chiplessCriticalInk defaults off).
        UsageBarsStack(
            windows: snapshot.windows,
            percentageMode: percentageMode,
            now: now,
            dimmed: dimmed
        )
    }

    /// Varied widths (audit UI-13): real content isn't two identical bars, so the
    /// skeleton previews the true shape rather than reading as "broken". The wait names
    /// the ~20–30s first Claude poll so the delay feels intentional, not hung.
    private var pendingSkeleton: some View {
        VStack(alignment: .leading, spacing: 9) {
            SkeletonMeter(labelWidth: 72, valueWidth: 42)
            SkeletonMeter(labelWidth: 86, valueWidth: 36)
            Text("Fetching usage…")
                .font(.caption2).foregroundStyle(.tertiary)
        }
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

    /// Small "Stale" flag + the transient reason, so a network blip is explicit rather
    /// than communicated only by a faint bar (which also reads as "disabled").
    private func stalePill(_ reason: FailureReason) -> some View {
        HStack(spacing: 6) {
            Text("Stale")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.20), in: Capsule())
            Text(reason.message)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
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

// MARK: - Account section (multi-account rows)

/// One account's section inside a multi-account provider card (H3a, Jul 2026 multi-account
/// design review): a full-bleed band header (account name + plan pill + optional menu-bar
/// mark) fencing the account's meters, with per-account failure affordances below. The band
/// replaced the earlier uppercase eyebrow + hairline divider — a filled strip reads as a
/// stronger group boundary while still sitting one hierarchy step below the brand row.
private struct AccountSectionView: View {
    let entry: ProviderAccountEntry
    let providerDisplayName: String
    let percentageMode: UsagePercentageMode
    let now: Date
    /// H3a: the built-in `.primary` account (`entries.first`) is the one the menu bar and
    /// widgets follow; its band carries a "menubar.rectangle" mark so the popover explains
    /// which login drives the always-visible glyph.
    let isMenuBarAccount: Bool
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var snapshot: UsageSnapshot { entry.snapshot }
    private var account: ProviderAccount { entry.account }

    var body: some View {
        // G1: 7pt binds the header to its meters; the 18pt inter-section gap in
        // `multiAccountBody` does the separating (proximity, not chrome). The whole section
        // is one VoiceOver container so the rotor can jump account-to-account instead of
        // the meters floating free of their identity row.
        VStack(alignment: .leading, spacing: 7) {
            identityRow
            stateContent
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(account.label) account")
        .animation(reduceMotion ? nil : HeadroomMotion.valueSpring, value: snapshot.freshness)
        .onChange(of: snapshot.freshness) { settleSetupIfLive() }
        .onAppear {
            settleSetupIfLive()
            SetupSessions.announceFailureIfNeeded(for: account)
        }
        .onChange(of: SetupSessions.state(for: account)) {
            SetupSessions.announceFailureIfNeeded(for: account)
        }
    }

    /// Identity header row (G1, Jul 2026 — supersedes the H3a band, which read as slabs on
    /// the live glass and zoned Claude into sections while sibling cards stayed open,
    /// PRODUCT.md #1). Set in the popover's one section-header register — the exact
    /// "API Spend" recipe (11pt bold uppercase, +0.5 tracking) — so account headers and
    /// the spend header speak the same grammar; a 13pt bold mixed-case pass (live review)
    /// sat too close to the meter labels' own register to separate. Secondary ink keeps it
    /// a header, not a peer of the bright numerals; grouping stays proximity-only via the
    /// inter-section gap in `multiAccountBody`.
    private var identityRow: some View {
        HStack(spacing: 6) {
            Text(account.label)
                .font(.system(size: 11, weight: .bold))
                // Primary ink, not the API Spend header's secondary (live review): the
                // account name is the section's identity anchor and reads washed-out at
                // .secondary on the glass card; size + case keep it a header regardless.
                .foregroundStyle(.primary)
                .textCase(.uppercase)
                .tracking(0.5)
                .lineLimit(1)
                .truncationMode(.tail)
            if let plan = snapshot.planLabel, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(ClaudeSetupStyle.stepBackground(dark: scheme == .dark), in: Capsule())
            }
            if isMenuBarAccount {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Shown in the menu bar")
            }
            if let email = accountEmail {
                // Identity check (Aug 2026): the label is user-chosen and can drift from
                // the login it names, so the signed-in address rides beside it in the plan
                // pill's tertiary register — metadata, not a second label. Inline rather
                // than a subordinate line so a five-account stack costs no extra height.
                // Negative layout priority yields width to the account name first, and
                // middle truncation keeps the domain visible on long addresses.
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                    .help(email)
            }
            Spacer(minLength: 6)
            if case .stale(let reason) = snapshot.freshness, !reason.isPermanent {
                staleTag
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityIdentity)
    }

    /// Nil whenever the account has no known address yet (pre-first-poll, or a source
    /// without the claim) — a normal state, so the row simply collapses. Gated on
    /// non-nil, never on `.live`: the last-known address persists across stale
    /// refreshes exactly like the plan pill.
    private var accountEmail: String? {
        guard let email = snapshot.accountEmail, !email.isEmpty else { return nil }
        return email
    }

    private var accessibilityIdentity: String {
        // Explicit label replaces the band's combined child labels, so re-state the
        // menu-bar mark here (H3a) — otherwise its "Shown in the menu bar" is dropped.
        var parts = ["\(account.label) account"]
        if let email = accountEmail { parts.append("signed in as \(email)") }
        if let plan = snapshot.planLabel, !plan.isEmpty { parts.append("\(plan) plan") }
        if isMenuBarAccount { parts.append("Shown in the menu bar") }
        return parts.joined(separator: ", ")
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
        // H3a: multi-account meters go chipless — critical windows paint the numeral instead
        // of stacking a "Low" chip under the band that already fences the account.
        UsageBarsStack(
            windows: snapshot.windows,
            percentageMode: percentageMode,
            now: now,
            dimmed: dimmed,
            chiplessCriticalInk: true
        )
    }

    /// Permanent failure on one account: a single compact row — the reason, then the
    /// Terminal handoff — so one dead login never dominates its healthy siblings.
    /// While the handoff Terminal is open it becomes a quiet waiting row with a
    /// real-progress spinner (bound to the retry cycle, not decorative).
    @ViewBuilder private func signInContent(_ reason: FailureReason) -> some View {
        let recoveryPresentation = reason.providerSetupOutcome?.recoveryPresentation
        let setupState = SetupSessions.state(for: account)
        VStack(alignment: .leading, spacing: 7) {
            if let refusalMessage = setupHandoffRefusalMessage(for: setupState) {
                HStack(spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(refusalMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
                    Spacer(minLength: 6)
                }
            } else if case .blockedByProviderLogin = setupState {
                HStack(spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Another \(providerDisplayName) sign-in is open")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("Continue setup") { SetupSessions.continueSetup(for: account) }
                        .buttonStyle(SetupChipButtonStyle())
                        .accessibilityLabel("Continue \(providerDisplayName) setup for \(account.label)")
                }
            } else if isWaitingForSetup {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(SetupSessions.mode(for: account) == .deviceCode
                         ? "Waiting for device code…"
                         : "Waiting for sign-in…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("Check now") { onRetry() }
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ClaudeSetupStyle.accentText(dark: scheme == .dark))
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
                    Text(SetupSessions.failureMessage(for: account) ?? reason.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
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
                        Label(recoveryPresentation?.primaryLabel ?? "Sign in", systemImage: "terminal")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(SetupChipButtonStyle())
                    .accessibilityLabel("\(recoveryPresentation?.primaryLabel ?? "Sign in") for \(account.label)")
                }
                if let secondaryLabel = recoveryPresentation?.secondaryLabel,
                   let secondaryAction = recoveryPresentation?.secondaryAction {
                    Button(secondaryLabel) {
                        SetupSessions.performRecovery(
                            secondaryAction,
                            for: account,
                            onRetry: onRetry
                        )
                    }
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ClaudeSetupStyle.accentText(dark: scheme == .dark))
                } else if SetupSessions.failureMessage(for: account) != nil {
                    Button("Check now", action: onRetry)
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ClaudeSetupStyle.accentText(dark: scheme == .dark))
                }
            }
            if !snapshot.windows.isEmpty {
                bars(dimmed: true)
            }
        }
    }

    private var staleTag: some View {
        Text("Stale")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.secondary.opacity(0.18), in: Capsule())
    }

    private var isWaitingForSetup: Bool {
        SetupSessions.isWaiting(for: account)
    }

    /// An account going live ends its handoff session and pending retries so the
    /// waiting row doesn't keep spinning (and retrying) after success.
    private func settleSetupIfLive() {
        guard case .live = snapshot.freshness, SetupSessions.isConnected(account) else { return }
        SetupSessions.settle(for: account)
    }

    private var accountSkeleton: some View {
        SkeletonMeter(labelWidth: 72, valueWidth: 38)
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
    /// H3a: multi-account sections opt into chipless critical numerals; single-account keeps
    /// the "Low" chip. Threaded down to every row so a stack renders one way.
    var chiplessCriticalInk: Bool = false

    var body: some View {
        if windows.isEmpty {
            Text("No usage data").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 9) {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(
                        window: window,
                        percentageMode: percentageMode,
                        now: now,
                        dimmed: dimmed,
                        chiplessCriticalInk: chiplessCriticalInk
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                RoundedRectangle(cornerRadius: 4).fill(ProviderStyle.barTrack(scheme: scheme)).frame(width: labelWidth, height: 13)
                Spacer(minLength: 6)
                RoundedRectangle(cornerRadius: 4).fill(ProviderStyle.barTrack(scheme: scheme)).frame(width: valueWidth, height: 13)
            }
            Capsule().fill(ProviderStyle.barTrack(scheme: scheme)).frame(height: 8)
        }
    }
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
