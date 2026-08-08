import SwiftUI
import AppKit
import HeadroomCore

@MainActor
func settingsRecoveryActions(
    snapshot: UsageSnapshot,
    account: ProviderAccount,
    setupState: SetupSessionState
) -> AccountsSettingsInteractions.RecoveryRowActions? {
    guard setupHandoffRefusalMessage(for: setupState) == nil else { return nil }
    return AccountsSettingsInteractions.recoveryRowActions(
        snapshot: snapshot,
        account: account
    )
}

/// Settings → Accounts (multi-account, Jul 2026): one tile managing every configured
/// subscription account. Grouped per provider — brand row with a live "n of 5" count
/// and an Add button, then one row per account: an editable label, a plain-language
/// status, and the account's actions (Sign in for a pending login, Remove for extras).
///
/// The built-in account is pinned and unremovable — it *is* the user's own CLI login —
/// so its row shows a quiet "CLI login" tag where extras get the trash affordance.
/// All sign-ins run through the official CLI in Terminal (compliance boundary
/// unchanged); this tile only opens that handoff and reflects the result.
struct AccountsSettingsTile: View {
    let store: UsageStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var labelDrafts: [AccountKey: String] = [:]
    @State private var removalCandidate: ProviderAccount?
    @State private var removalOrigin: AccountKey?
    @State private var removalInProgress: AccountKey?
    @State private var hoveredLabel: AccountKey?
    @FocusState private var focusedLabel: AccountKey?
    @FocusState private var focusedRemovalAction: AccountKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.2)
            SettingsHelpText(text: "Track several subscriptions side by side. Every account signs in through its official CLI in Terminal — Headroom never sees your credentials.")

            ForEach(Array(store.registeredProviderOrder.enumerated()), id: \.element) { index, providerID in
                if index > 0 {
                    Rectangle()
                        .fill(ClaudeSetupStyle.hairline(dark: colorScheme == .dark))
                        .frame(height: 1)
                        .padding(.vertical, 2)
                }
                providerGroup(providerID)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10, surface: .opaque)
        .confirmationDialog(
            "Remove this account?",
            isPresented: removalDialogPresented,
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { account in
            Button("Remove \(account.label)", role: .destructive) {
                removalInProgress = account.key
                Task { @MainActor in
                    let result = await AccountsSettingsInteractions.removeAccount(account, from: store)
                    removalInProgress = nil
                    guard result == .removed else {
                        restoreRemovalFocus()
                        return
                    }
                    withAnimation(reduceMotion ? nil : HeadroomMotion.settle) {
                        removalCandidate = nil
                    }
                    removalOrigin = nil
                }
            }
            Button("Cancel", role: .cancel) { restoreRemovalFocus() }
        } message: { account in
            Text("Its sign-in on this Mac is deleted with it. Your subscription is untouched.")
        }
        // Commit a pending rename when the field loses focus — Enter-only commit
        // silently discarded renames while still displaying the draft (code-review
        // finding).
        .onChange(of: focusedLabel) { previous, _ in
            if let previous, let account = account(for: previous) {
                commitLabel(for: account)
            }
        }
    }

    private func account(for key: AccountKey) -> ProviderAccount? {
        store.accounts(for: key.providerID).first { $0.key == key }
    }

    // MARK: - Provider group

    @ViewBuilder private func providerGroup(_ providerID: ProviderID) -> some View {
        let accounts = store.accounts(for: providerID)
        let capacity = store.accountCapacity(for: providerID)
        let capabilityState = store.providerCapabilities[providerID]?.state
        let capability = capabilityRecoveryPresentation(
            state: capabilityState,
            hasActiveSetupSession: accounts.contains(where: { SetupSessions.hasActiveHandoff(for: $0) })
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    ProviderLogoView(providerID: providerID, size: 15)
                    Text(store.displayNames[providerID] ?? providerID.raw.capitalized)
                }
                if capacity > 1 {
                    Text("\(accounts.count) of \(capacity)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Add Account…") { addAccount(for: providerID) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!store.canAddAccount(for: providerID))
                        .help(store.canAddAccount(for: providerID)
                              ? "Sign in another account via the official CLI"
                              : "Up to \(capacity) accounts per provider")
                } else {
                    Spacer(minLength: 12)
                }
            }
            if let capability, !accounts.isEmpty {
                ProviderCapabilityRecoveryView(
                    presentation: capability,
                    onPrimaryAction: {
                        AccountsSettingsInteractions.performCapabilityRecovery(
                            capability.recovery.primaryAction,
                            for: providerID,
                            in: store
                        )
                    },
                    onSecondaryAction: capability.recovery.secondaryAction.map { action in
                        {
                            AccountsSettingsInteractions.performCapabilityRecovery(
                                action,
                                for: providerID,
                                in: store
                            )
                        }
                    }
                )
                .padding(.leading, 16)
            }
            ForEach(accounts) { account in
                accountRow(account, capability: capability)
            }
            if let surface = UsageSurface.subscription(for: providerID),
               !store.isSurfaceEnabled(surface) {
                // Without this hint, an account added while the surface is off would
                // sit in "Needs sign-in" forever with no visible cause (code-review
                // finding) — the disabled surface means it's never polled.
                SettingsHelpText(text: "\(store.displayNames[providerID] ?? providerID.raw.capitalized) usage is turned off in Subscription Usage — accounts stay signed in but aren't fetched.")
            }
        }
        .animation(reduceMotion ? nil : HeadroomMotion.settle, value: accounts.map(\.id))
        .onAppear {
            SetupSessions.announceCapabilityIfNeeded(capabilityState, for: providerID)
        }
        .onChange(of: capabilityState) {
            SetupSessions.announceCapabilityIfNeeded(capabilityState, for: providerID)
        }
    }

    // MARK: - Account row

    private func accountRow(
        _ account: ProviderAccount,
        capability: CapabilityRecoveryPresentation?
    ) -> some View {
        let snapshot = store.snapshot(for: account.key)
        let removalState = store.accountRemovalStates[account.key]
        let setupState = SetupSessions.state(for: account)
        let setupFailure = SetupSessions.failureMessage(for: account)
        let capabilityRow = AccountsSettingsInteractions.capabilityRowPresentation(
            snapshot: snapshot,
            capability: capability
        )
        let recoveryActions = settingsRecoveryActions(
            snapshot: snapshot,
            account: account,
            setupState: setupState
        )
        let status = AccountStatus(
            snapshot: snapshot,
            waiting: isWaitingForSetup(account),
            blocked: {
                if case .blockedByProviderLogin = setupState { return true }
                return false
            }(),
            blockedByOpenHandoff: setupState == .blockedByOpenHandoff,
            setupFailed: setupFailure != nil,
            removalState: removalState
        )
        let isEditingLabel = focusedLabel == account.key || hoveredLabel == account.key
        let email = accountEmail(from: snapshot)
        let usesSecondLine = capability == nil
            && removalState == nil
            && recoveryActions?.usesSecondLine == true
        return VStack(alignment: .leading, spacing: usesSecondLine ? 5 : 1) {
            HStack(spacing: 8) {
                accountIdentity(account, email: email, isEditingLabel: isEditingLabel)
                if account.isBuiltIn {
                    Text("CLI login")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ClaudeSetupStyle.stepBackground(dark: colorScheme == .dark), in: Capsule())
                        .help("Uses the account your CLI is signed into")
                }
                Spacer(minLength: 8)
                if !usesSecondLine {
                    accountStatus(
                        capabilityRow,
                        snapshot: snapshot,
                        status: status,
                        setupFailure: setupFailure,
                        account: account
                    )
                    if capability == nil, removalState == nil {
                        recoveryButtons(
                            for: account,
                            status: status,
                            recoveryActions: recoveryActions
                        )
                    }
                }
                removalActions(for: account, removalState: removalState)
            }
            if usesSecondLine {
                HStack(spacing: 8) {
                    accountStatus(
                        capabilityRow,
                        snapshot: snapshot,
                        status: status,
                        setupFailure: setupFailure,
                        account: account
                    )
                    Spacer(minLength: 8)
                    recoveryButtons(
                        for: account,
                        status: status,
                        recoveryActions: recoveryActions
                    )
                }
                .padding(.leading, 6)
            }
        }
        // 16pt + the field's 6pt inner pad lands the label text at the 22pt provider-
        // name alignment axis.
        .padding(.leading, 16)
        .disabled(removalState == .removing)
        .onAppear { SetupSessions.announceFailureIfNeeded(for: account) }
        .onChange(of: setupState) {
            SetupSessions.announceFailureIfNeeded(for: account)
        }
    }

    @ViewBuilder private func accountIdentity(
        _ account: ProviderAccount,
        email: String?,
        isEditingLabel: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
                // Quiet at rest, but the affordance reveals on approach: a hover/focus fill
                // marks the label as editable (impeccable audit P1 — a plain field that
                // renders identically to static text hides the rename feature entirely).
                TextField("Account name", text: labelBinding(for: account))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focusedLabel, equals: account.key)
                    .onSubmit { commitLabel(for: account) }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(
                        Color.primary.opacity(isEditingLabel ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .onHover { hovering in
                        hoveredLabel = hovering ? account.key : (hoveredLabel == account.key ? nil : hoveredLabel)
                    }
                    .frame(maxWidth: 158, alignment: .leading)
                    .help("Click to rename this account")
                    .accessibilityLabel("\(account.label) account name")
                if let email {
                    // Under the (renameable) name, not beside it: the label is the user's
                    // word for the account and the address is what it actually resolves to,
                    // so managing accounts here means verifying one against the other. The
                    // 6pt inset + 158pt cap match the field above, so both sit on one text
                    // axis and a long address never shoves the status column around.
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: 158, alignment: .leading)
                        .help(email)
                        .accessibilityLabel("Signed in as \(email)")
                }
        }
    }

    @ViewBuilder private func accountStatus(
        _ capabilityRow: AccountsSettingsInteractions.CapabilityRowPresentation,
        snapshot: UsageSnapshot,
        status: AccountStatus,
        setupFailure: String?,
        account: ProviderAccount
    ) -> some View {
        capabilityStatusLabel(
            capabilityRow,
            snapshot: snapshot,
            fallbackStatus: status,
            setupFailure: setupFailure,
            setupMode: SetupSessions.mode(for: account),
            providerDisplayName: store.displayNames[account.providerID]
                ?? account.providerID.raw.capitalized
        )
    }

    @ViewBuilder private func recoveryButtons(
        for account: ProviderAccount,
        status: AccountStatus,
        recoveryActions: AccountsSettingsInteractions.RecoveryRowActions?
    ) -> some View {
        if status.needsRecovery || recoveryActions != nil {
            Button(status == .blocked
                   ? "Continue…"
                   : (recoveryActions?.primaryLabel
                      ?? (status == .setupFailed ? "Retry…" : "Sign In…"))) {
                if status == .blocked {
                    SetupSessions.continueSetup(for: account)
                } else if let recoveryActions {
                    SetupSessions.performRecovery(
                        recoveryActions.primaryAction,
                        for: account,
                        onRetry: { store.refreshAccountNow(account.key) }
                    )
                } else {
                    openSetup(for: account)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(
                recoveryActions?.primaryAccessibilityLabel
                    ?? "\(status == .blocked ? "Continue setup" : "Sign in") for \(account.label)"
            )
            if let secondaryLabel = recoveryActions?.secondaryLabel,
               let secondaryAction = recoveryActions?.secondaryAction {
                Button(secondaryLabel) {
                    SetupSessions.performRecovery(
                        secondaryAction,
                        for: account,
                        onRetry: { store.refreshAccountNow(account.key) }
                    )
                }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                .controlSize(.small)
                .accessibilityLabel(
                    recoveryActions?.secondaryAccessibilityLabel
                        ?? "\(secondaryLabel) for \(account.label)"
                )
            }
        }
    }

    @ViewBuilder private func removalActions(
        for account: ProviderAccount,
        removalState: AccountRemovalState?
    ) -> some View {
        // The trash slot is always laid out — hidden (not absent) on built-in rows —
        // so status text shares one right anchor down the whole list (audit P2).
            if removalState == .failed || removalState == .setupActive {
                Button("Retry") {
                    Task { @MainActor in
                        _ = await AccountsSettingsInteractions.removeAccount(account, from: store)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Retry removal of \(account.label)")
                .focused($focusedRemovalAction, equals: account.key)
                Button("Cancel") {
                    store.cancelAccountRemoval(account.key)
                    removalOrigin = account.key
                    restoreRemovalFocus()
                }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Cancel removal of \(account.label)")
            } else {
                Button {
                    removalOrigin = account.key
                    removalCandidate = account
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
                .foregroundStyle(.secondary)
                .help("Remove this account")
                .accessibilityLabel("Remove \(account.label)")
                .opacity(account.isBuiltIn ? 0 : 1)
                .disabled(account.isBuiltIn || removalState == .removing)
                .accessibilityHidden(account.isBuiltIn)
                .focused($focusedRemovalAction, equals: account.key)
            }
    }

    /// Nil for an account with no known address yet — a row can render before its first
    /// poll (or from a source without the claim), so the line collapses rather than
    /// holding a placeholder. Non-nil, not `.live`, is the gate: a stale row keeps the
    /// last-known address, which is exactly when "which login is this?" gets asked.
    private func accountEmail(from snapshot: UsageSnapshot) -> String? {
        guard let email = snapshot.accountEmail, !email.isEmpty else { return nil }
        return email
    }

    @ViewBuilder private func capabilityStatusLabel(
        _ presentation: AccountsSettingsInteractions.CapabilityRowPresentation,
        snapshot: UsageSnapshot,
        fallbackStatus: AccountStatus,
        setupFailure: String?,
        setupMode: SetupHandoffMode,
        providerDisplayName: String
    ) -> some View {
        switch presentation {
        case .standard:
            statusLabel(
                fallbackStatus,
                setupFailure: setupFailure,
                setupMode: setupMode,
                providerDisplayName: providerDisplayName
            )
        case .waitingForClaudeCode:
            Text("Waiting for Claude Code")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        case .retainedUsage:
            HStack(spacing: 7) {
                ForEach(Array(snapshot.windows.prefix(2).enumerated()), id: \.offset) { _, window in
                    Text("\(window.kind.shortLabel) \(store.usagePercentageMode.roundedPercentage(for: window))%")
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .opacity(0.68)
            .accessibilityLabel(
                "Last known usage. " + snapshot.windows.prefix(2).map {
                    "\($0.kind.shortLabel) \(store.usagePercentageMode.roundedPercentage(for: $0)) percent \(store.usagePercentageMode.term)"
                }.joined(separator: ", ")
            )
        }
    }

    @ViewBuilder private func statusLabel(
        _ status: AccountStatus,
        setupFailure: String?,
        setupMode: SetupHandoffMode,
        providerDisplayName: String
    ) -> some View {
        switch status {
        case .connected:
            Text("Connected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .fetching:
            Text("Fetching…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .waiting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(setupMode == .deviceCode ? "Waiting for device code…" : "Waiting for sign-in…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .stale:
            // Clock glyph separates "data gone old" from the affirmative "Connected" —
            // the two rendered identically before (impeccable audit P1). Restrained on
            // purpose: stale is usually a transient blip, not an alarm.
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                Text("Stale")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        case .needsSignIn:
            Text("Needs sign-in")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
        case .blocked:
            Text("Another \(providerDisplayName) login is open")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        case .setupFailed:
            Text(setupFailure ?? "Setup failed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
                .lineLimit(2)
        case .removing:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Removing…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .setupActive:
            Text("Close setup, then retry")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
        case .removalFailed:
            Text("Removal failed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
        }
    }

    // MARK: - Status

    enum AccountStatus {
        case connected, fetching, waiting, stale, needsSignIn, blocked, setupFailed
        case removing, setupActive, removalFailed

        init(
            snapshot: UsageSnapshot,
            waiting: Bool,
            blocked: Bool,
            blockedByOpenHandoff: Bool,
            setupFailed: Bool,
            removalState: AccountRemovalState?
        ) {
            switch removalState {
            case .removing: self = .removing; return
            case .setupActive: self = .setupActive; return
            case .failed: self = .removalFailed; return
            case nil: break
            }
            if blockedByOpenHandoff { self = .setupActive; return }
            if blocked { self = .blocked; return }
            if setupFailed { self = .setupFailed; return }
            switch snapshot.freshness {
            case .live:
                self = .connected
            case .pending:
                self = .fetching
            case .stale(let reason):
                if reason.isPermanent {
                    self = waiting ? .waiting : .needsSignIn
                } else {
                    self = .stale
                }
            }
        }

        var needsRecovery: Bool {
            self == .needsSignIn || self == .blocked || self == .setupFailed
        }
    }

    // MARK: - Actions

    /// Create the account and immediately open its official-CLI sign-in so the add
    /// flow is one gesture: click Add → Terminal opens → sign in → row goes live.
    private func addAccount(for providerID: ProviderID) {
        _ = withAnimation(reduceMotion ? nil : HeadroomMotion.settle) {
            AccountsSettingsInteractions.addAccount(
                for: providerID,
                to: store,
                openSetup: openSetup(for:)
            )
        }
    }

    private func openSetup(for account: ProviderAccount) {
        // Per-account retry: watching one sign-in must not re-probe the whole fleet
        // (each Claude account is a 20–30s CLI session — code-review finding).
        SetupSessions.openSetup(for: account, onRetry: { [store] in
            store.refreshAccountNow(account.key)
        })
    }

    private func isWaitingForSetup(_ account: ProviderAccount) -> Bool {
        SetupSessions.isWaiting(for: account)
    }

    // MARK: - Rename plumbing

    private func labelBinding(for account: ProviderAccount) -> Binding<String> {
        Binding(
            get: { labelDrafts[account.key] ?? account.label },
            set: { labelDrafts[account.key] = $0 }
        )
    }

    private func commitLabel(for account: ProviderAccount) {
        guard let draft = labelDrafts[account.key] else { return }
        AccountsSettingsInteractions.commitLabel(draft, for: account, in: store)
        labelDrafts[account.key] = nil
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(
            get: { removalCandidate != nil },
            set: {
                if !$0 {
                    removalCandidate = nil
                    if removalInProgress == nil { restoreRemovalFocus() }
                }
            }
        )
    }

    private func restoreRemovalFocus() {
        let key = removalOrigin
        removalCandidate = nil
        Task { @MainActor in
            await Task.yield()
            focusedRemovalAction = key
        }
    }
}
