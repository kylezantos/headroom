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

@MainActor
func settingsStopWaitingAccount(
    _ account: ProviderAccount,
    removalState: AccountRemovalState?,
    setupState: SetupSessionState,
    hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
) -> ProviderAccount? {
    guard hasActiveHandoff(account)
            || removalState == .setupActive
            || setupState == .blockedByOpenHandoff
    else { return nil }
    return account
}

func accountLabelFieldValue(
    for account: ProviderAccount,
    draft: String?,
    focusedAccountKey: AccountKey?
) -> String {
    focusedAccountKey == account.key ? (draft ?? account.label) : account.label
}

func acceptsAccountLabelDraftChange(
    for accountKey: AccountKey,
    focusedAccountKey: AccountKey?
) -> Bool {
    focusedAccountKey == accountKey
}

/// Settings → Accounts (multi-account, Jul 2026): one tile managing every configured
/// subscription account. Grouped per provider — brand row with a live "n of 5" count
/// and an Add button, then one row per account: an editable label, a plain-language
/// status, and the account's actions (Sign in for a pending login, Remove for extras).
///
/// The built-in account *is* the user's own CLI login, so it can never be deleted —
/// its row shows a quiet "CLI login" tag, and once another account exists it offers a
/// non-destructive "stop tracking" instead of the extras' trash affordance (which
/// deletes that account's Headroom-owned config home). A stop-tracked built-in can be
/// resurfaced from the provider header. All sign-ins run through the official CLI in
/// Terminal (compliance boundary unchanged); this tile only opens that handoff and
/// reflects the result.
struct AccountsSettingsTile: View {
    let store: UsageStore
    /// KTD3: resolved on the settings root so a pane switch neither blanks the badges nor
    /// re-reads every account's `.claude.json`.
    let duplicateLoginLabels: [AccountKey: String]
    /// R9: the provider group headers own the subscription switches, so the tile needs the
    /// root's surface binding (set + animate + `refreshNow()`) rather than a local toggle.
    let surfaceBinding: (UsageSurface) -> Binding<Bool>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var labelDrafts: [AccountKey: String] = [:]
    @State private var removalCandidate: ProviderAccount?
    @State private var resetCandidate: ProviderAccount?
    @State private var removalOrigin: AccountKey?
    @State private var removalInProgress: AccountKey?
    @State private var hoveredLabel: AccountKey?
    @FocusState private var focusedLabel: AccountKey?
    @FocusState private var focusedRemovalAction: AccountKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The pane scaffold prints "Accounts" above this tile (U2/U4), so the tile
            // carries no title of its own.
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
            removalCandidate?.isBuiltIn == true
                ? "Stop tracking this account?"
                : "Remove this account?",
            isPresented: removalDialogPresented,
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { account in
            // Stop-tracking is deliberately not `.destructive` — it hides the row and
            // deletes nothing, unlike extra-account removal.
            Button(
                account.isBuiltIn ? "Stop Tracking \(account.label)" : "Remove \(account.label)",
                role: account.isBuiltIn ? nil : .destructive
            ) {
                removalInProgress = account.key
                Task { @MainActor in
                    let result = await AccountsSettingsInteractions.removeAccount(account, from: store)
                    guard result == .removed else {
                        removalInProgress = nil
                        restoreRemovalFocus()
                        return
                    }
                    // M7A: every state a completed removal touches settles in one
                    // transaction, on the same `reorder` spring the list identity below
                    // carries, so the tile contracts while the row fades rather than after
                    // it. Dismissing the dialog in its own animation while the row left on
                    // another is what read as a second, later step.
                    withAnimation(
                        HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
                    ) {
                        removalInProgress = nil
                        removalCandidate = nil
                        removalOrigin = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { restoreRemovalFocus() }
        } message: { account in
            Text(account.isBuiltIn
                 ? "Headroom stops showing it. Your CLI stays signed in — nothing on this Mac is deleted."
                 : "Its sign-in on this Mac is deleted with it. Your subscription is untouched.")
        }
        .confirmationDialog(
            "Sign out and set up again?",
            isPresented: resetDialogPresented,
            titleVisibility: .visible,
            presenting: resetCandidate
        ) { account in
            Button("Sign Out & Set Up Again") {
                _ = AccountsSettingsInteractions.resetBuiltIn(account, in: store)
                resetCandidate = nil
                restoreRemovalFocus()
            }
            Button("Cancel", role: .cancel) { restoreRemovalFocus() }
        } message: { account in
            let provider = store.displayNames[account.providerID]
                ?? account.providerID.raw.capitalized
            Text("Signing in again switches the \(provider) CLI login across this Mac, including Terminal sessions. If you only want Headroom to show another login, add it as a separate account and use Make Main.")
        }
        // Commit a pending rename when the field loses focus — Enter-only commit
        // silently discarded renames while still displaying the draft (code-review
        // finding).
        .onChange(of: focusedLabel) { previous, _ in
            if let previous, let account = account(for: previous) {
                commitLabel(for: account)
            }
        }
        // R12: leaving Accounts — pane switch or window close — commits a typed rename
        // instead of discarding it. Focus loss already commits, but ⌘W tears the tile
        // down without moving focus first.
        .onDisappear { commitPendingLabels() }
    }

    private func account(for key: AccountKey) -> ProviderAccount? {
        store.accounts(for: key.providerID).first { $0.key == key }
    }

    // MARK: - Provider group

    @ViewBuilder private func providerGroup(_ providerID: ProviderID) -> some View {
        let accounts = store.accounts(for: providerID)
        let capacity = store.accountCapacity(for: providerID)
        let capabilityState = store.providerCapabilities[providerID]?.state
        let displayName = store.displayNames[providerID] ?? providerID.raw.capitalized
        let surface = UsageSurface.subscription(for: providerID)
        let presentation = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: displayName,
            accounts: accounts,
            capacity: capacity,
            hasFreeAccountSlot: store.canAddAccount(for: providerID),
            isSurfaceEnabled: surface.map { store.isSurfaceEnabled($0) } ?? true
        )
        let allCapability = capabilityRecoveryPresentation(
            state: capabilityState,
            hasActiveSetupSession: accounts.contains(where: { SetupSessions.hasActiveHandoff(for: $0) })
        )
        // R11: a provider that isn't fetched has nothing to say about its fetch health.
        let capability = presentation.hidesCapabilityBanner ? nil : allCapability
        // R11: VoiceOver follows the banner. Announcing a hidden capability failure would
        // both speak state the screen doesn't show and burn the per-provider dedupe entry,
        // so the announcement would be lost once the provider is switched back on.
        let announcedCapability = presentation.hidesCapabilityBanner ? nil : capabilityState
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    ProviderLogoView(providerID: providerID, size: 15)
                    Text(displayName)
                }
                if presentation.showsAccountCounter {
                    // A stop-tracked built-in is hidden from the list but keeps its
                    // registry slot, so count it — otherwise the header reads "4 of 5"
                    // while Add Account is disabled.
                    let usedSlots = accounts.count
                        + (store.isBuiltInTrackingStopped(for: providerID) ? 1 : 0)
                    Text("\(usedSlots) of \(capacity)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if presentation.showsAddAction {
                    // L11A: an off group dims as one unit, Add included. Both the enabled
                    // and disabled reasons come from `ProviderGroupPresentation` so the
                    // rule is tested rather than restated here.
                    Button("Add Account…") { addAccount(for: providerID) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!presentation.addAction.isEnabled)
                        .help(presentation.addAction.helpText)
                }
                if let surface {
                    subscriptionSwitch(
                        surface,
                        displayName: displayName,
                        presentation: presentation.subscriptionSwitch
                    )
                }
            }
            if let capability, !accounts.isEmpty {
                ProviderCapabilityRecoveryView(
                    presentation: capability,
                    stopWaitingAccount: accounts.first {
                        SetupSessions.hasActiveHandoff(for: $0)
                    },
                    // B3A: Settings keeps the leading row and the small chip; only the
                    // popover card foot takes P4C's trailing action row.
                    placement: .settingsGroup,
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
                accountRow(account, capability: capability, presentation: presentation)
                    // M7A: an added row arrives with the Settings reveal (4pt rise + blur
                    // + fade); a removed one only fades — `settingsReveal` is already
                    // asymmetric that way, so exits stay softer than entrances.
                    .transition(.settingsReveal)
            }
            if store.isBuiltInTrackingStopped(for: providerID) {
                // The way back from stop-tracking: resurface the CLI's own login and
                // fetch it right away. Quiet on purpose — it's an undo, not a feature.
                Button("Show CLI Account") {
                    _ = withAnimation(
                        HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
                    ) {
                        AccountsSettingsInteractions.resumeTrackingBuiltIn(
                            for: providerID,
                            in: store
                        )
                    }
                }
                // B3A: quiet still, but a control — the small chip owns its own font and ink,
                // so the per-site 11pt secondary label goes away. B3H keeps the resting
                // container here: on a Settings pane, beside native bordered controls, a
                // hover-only chip would read as a line of text until the pointer found it.
                .buttonStyle(SetupChipButtonStyle(size: .small, chrome: .resting))
                .help("Track the account your CLI is signed into again")
                .padding(.leading, 16)
            }
            if let offHelpText = presentation.offHelpText {
                // R11: one line naming the only consequence of "off". Without it, an
                // account added while the surface is off would look broken rather than
                // simply unpolled (code-review finding).
                SettingsHelpText(text: offHelpText)
            }
        }
        // M7A: the single scope for add / remove / Make Main. A row travels roughly its own
        // height, so the list rides the `reorder` spring — slower than `valueSpring`, and a
        // spring so a second Make Main mid-flight retargets instead of restarting. It is one
        // `.movement` scope on purpose: splitting the row's fade from the group's height
        // change is exactly what made the contraction land a beat late. Nothing between this
        // and the tile's `raisedTile` pins a height, so the tile follows the group per frame.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion),
            value: accounts.map(\.id)
        )
        .onAppear {
            SetupSessions.announceCapabilityIfNeeded(announcedCapability, for: providerID)
        }
        .onChange(of: capabilityState) {
            SetupSessions.announceCapabilityIfNeeded(announcedCapability, for: providerID)
        }
    }

    /// R9/R10: the provider's on/off switch now sits with the accounts it governs. Its
    /// binding is the root's (`setSurfaceEnabled` inside the settle animation, then a
    /// refresh), so turning a provider on fetches it immediately.
    private func subscriptionSwitch(
        _ surface: UsageSurface,
        displayName: String,
        presentation: AccountsSettingsInteractions.SubscriptionSwitchPresentation
    ) -> some View {
        Toggle(displayName, isOn: surfaceBinding(surface))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(!presentation.isEnabled)
            .help(presentation.helpText ?? "Fetch \(displayName) usage")
            .accessibilityLabel(presentation.accessibilityLabel)
    }

    // MARK: - Account row

    private func accountRow(
        _ account: ProviderAccount,
        capability: CapabilityRecoveryPresentation?,
        presentation: AccountsSettingsInteractions.ProviderGroupPresentation
    ) -> some View {
        let snapshot = store.snapshot(for: account.key)
        let removalState = store.accountRemovalStates[account.key]
        let setupState = SetupSessions.state(for: account)
        let setupFailure = SetupSessions.failureMessage(for: account)
        let capabilityRow = AccountsSettingsInteractions.capabilityRowPresentation(
            snapshot: snapshot,
            capability: capability
        )
        // R11: fetch-recovery ("Check Again", "Install…", "Reconnect…") is fetch state,
        // so it goes with the status text while the provider is off; the plain sign-in
        // affordance below is management and stays.
        let recoveryActions = presentation.hidesFetchRecovery
            ? nil
            : settingsRecoveryActions(
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
        // R2C6: the row prints the *popover's* sentence for this state ("Sign in with the
        // official Claude CLI") rather than a Settings-only "Needs sign-in". One act, one
        // wording — and read from Core's `ProviderSetupOutcome`, never duplicated here.
        let setupSentence: String? = {
            guard case .stale(let reason) = snapshot.freshness else { return nil }
            return reason.providerSetupOutcome?.message
        }()
        let usesSecondLine = capability == nil
            && removalState == nil
            && recoveryActions?.usesSecondLine == true
        return VStack(alignment: .leading, spacing: usesSecondLine ? 5 : 1) {
            HStack(spacing: 8) {
                accountIdentity(account, email: email, isEditingLabel: isEditingLabel)
                if account.isBuiltIn {
                    pillBadge("CLI login", help: "Uses the account your CLI is signed into")
                }
                if let original = duplicateLoginLabels[account.key] {
                    // Detection only — the user decides which record to keep; Headroom
                    // never merges or removes duplicate rows on its own.
                    pillBadge(
                        "Same login as \(original)",
                        help: "This row is signed in to the same Claude account as \(original). You can remove one without signing out of the other.",
                        accessibilityLabel: "\(account.label) uses the same login as \(original)"
                    )
                }
                Spacer(minLength: 8)
                // R2C11: the status stays in the trailing column whichever silhouette the row
                // takes. Only the *buttons* drop to a second line when there are two of them.
                // Moving the status with them meant two never-signed-in rows in one list
                // printed the same state in two different places, which reads as two states.
                if !presentation.hidesAccountStatus(isSetupState: status.isSetupState) {
                    accountStatus(
                        capabilityRow,
                        snapshot: snapshot,
                        status: status,
                        setupFailure: setupFailure,
                        setupSentence: setupSentence,
                        account: account
                    )
                }
                if !usesSecondLine, capability == nil, removalState == nil {
                    recoveryButtons(
                        for: account,
                        status: status,
                        recoveryActions: recoveryActions
                    )
                }
                removalActions(
                    for: account,
                    removalState: removalState,
                    setupState: setupState
                )
            }
            if usesSecondLine {
                HStack(spacing: 8) {
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
        // R11: dimmed, never disabled — "off" means "not fetched", so every management
        // control in the row still works. Matches the disabled-swatch step in
        // `MeterStyleTile`.
        .opacity(presentation.dimsAccountRows ? 0.45 : 1)
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
                    // R2M10/S3A: the fill's whole job is to reveal on approach, and it was the
                    // one hover in the app that snapped both ways — the only one outside a
                    // button style. Opacity only, so it keeps its timing under Reduce Motion.
                    .animation(
                        HeadroomMotion.resolved(
                            isEditingLabel ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut,
                            .crossfade,
                            reduceMotion: reduceMotion
                        ),
                        value: isEditingLabel
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
        setupSentence: String?,
        account: ProviderAccount
    ) -> some View {
        capabilityStatusLabel(
            capabilityRow,
            snapshot: snapshot,
            fallbackStatus: status,
            setupFailure: setupFailure,
            setupSentence: setupSentence,
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
            // PA12: no ellipsis on "Sign In". The popover's button for the same action has
            // never had one, and two surfaces spelling one action two ways reads as two
            // actions. ("Add Account…" and "Check for Updates…" keep theirs — those open a
            // further choice; signing in is the whole action.)
            //
            // R2B1: "Continue Setup", not "Continue…". The ellipsis promised a further choice
            // that never arrives — the button resumes the handoff already open — and a bare
            // "Continue" doesn't say what it continues. R2C6: the primary label otherwise
            // comes from Core's `ProviderSetupOutcome`, which owns the one sign-in verb.
            Button(status == .blocked
                   ? "Continue Setup"
                   : (recoveryActions?.primaryLabel
                      ?? (status == .setupFailed ? "Retry…" : "Sign In"))) {
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
                // B3A/B3H: bare beside a bordered primary was the worst mix in Settings; the
                // small chip gives it a resting container and its own font and ink, and it
                // keeps that container — its neighbour is a `.bordered` button.
                .buttonStyle(SetupChipButtonStyle(size: .small, chrome: .resting))
                .accessibilityLabel(
                    recoveryActions?.secondaryAccessibilityLabel
                        ?? "\(secondaryLabel) for \(account.label)"
                )
            }
        }
    }

    @ViewBuilder private func removalActions(
        for account: ProviderAccount,
        removalState: AccountRemovalState?,
        setupState: SetupSessionState
    ) -> some View {
        // The trash slot is always laid out — hidden (not absent) on built-in rows —
        // so status text shares one right anchor down the whole list (audit P2).
            if let stopWaitingAccount = settingsStopWaitingAccount(
                account,
                removalState: removalState,
                setupState: setupState
            ) {
                StopWaitingButton(
                    account: stopWaitingAccount,
                    onConfirmationPresented: { removalOrigin = stopWaitingAccount.key },
                    onStop: { AccountsSettingsInteractions.stopWaiting(for: $0, in: store) },
                    onDismiss: restoreRemovalFocus
                )
                .focused($focusedRemovalAction, equals: account.key)
            } else if removalState == .failed {
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
                if account.isBuiltIn {
                    let builtInActions = AccountsSettingsInteractions.builtInRowActions(for: account, in: store)
                    let promotion = AccountsSettingsInteractions.promotionState(for: account, in: store)
                    switch (builtInActions, promotion) {
                    case (.resetOnly, _):
                        Button { requestReset(account) } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
                        .foregroundStyle(.secondary)
                        .help("Sign out and set up this account again")
                        .accessibilityLabel("Sign out and set up \(account.label) again")
                        .focused($focusedRemovalAction, equals: account.key)
                    case (.resetAndStopTracking, .primary):
                        Menu {
                            Button("Sign Out & Set Up Again") { requestReset(account) }
                            Divider()
                            Button("Stop Tracking") {
                                removalOrigin = account.key
                                removalCandidate = account
                            }
                        } label: {
                            AccountActionsMenuGlyph()
                        }
                        .accountActionsMenuChrome()
                        .help("Account actions")
                        .accessibilityLabel("Actions for \(account.label)")
                        .focused($focusedRemovalAction, equals: account.key)
                    case (.resetAndStopTracking, .available):
                        Menu {
                            Button("Make Main") { makeMain(account) }
                            Divider()
                            Button("Sign Out & Set Up Again") { requestReset(account) }
                            Divider()
                            Button("Stop Tracking") {
                                removalOrigin = account.key
                                removalCandidate = account
                            }
                        } label: {
                            AccountActionsMenuGlyph()
                        }
                        .accountActionsMenuChrome()
                        .help("Account actions")
                        .accessibilityLabel("Actions for \(account.label), including Make Main")
                        .focused($focusedRemovalAction, equals: account.key)
                    case (.unavailable, _), (.resetAndStopTracking, .unavailable):
                        Color.clear
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                    }
                } else {
                    if AccountsSettingsInteractions.promotionState(for: account, in: store) == .available {
                        Menu {
                            Button("Make Main") { makeMain(account) }
                            Divider()
                            // R2B1: the act deletes this account's sign-in on the Mac, and its
                            // own confirmation is already `.destructive` — the menu item that
                            // opens it should look like what it opens. (Stop Tracking stays
                            // plain: it hides a row and deletes nothing.)
                            Button("Remove Account", role: .destructive) {
                                removalOrigin = account.key
                                removalCandidate = account
                            }
                        } label: {
                            AccountActionsMenuGlyph()
                        }
                        .accountActionsMenuChrome()
                        .help("Account actions")
                        .accessibilityLabel("Actions for \(account.label), including Make Main")
                        .focused($focusedRemovalAction, equals: account.key)
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
                        .disabled(removalState == .removing)
                        .focused($focusedRemovalAction, equals: account.key)
                    }
                }
            }
    }

    /// R2C21: the `•••` glyph, drawn to the same spec as the row's `arrow.clockwise` and
    /// `trash` — 11pt **regular**, not semibold. One stroke weight per icon set; the menus
    /// were the only heavier glyph in the column, which read as emphasis they don't carry.
    fileprivate struct AccountActionsMenuGlyph: View {
        var body: some View {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
        }
    }

    /// The row-tag capsule shared by "CLI login" and "Same login as X". Tokens live in
    /// `SettingsPillBadge` so the Menu Bar pane's "Off" tag renders the same badge.
    private func pillBadge(
        _ text: String,
        help helpText: String,
        accessibilityLabel: String? = nil
    ) -> some View {
        SettingsPillBadge(text: text)
            .help(helpText)
            .accessibilityLabel(accessibilityLabel ?? text)
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
        setupSentence: String?,
        setupMode: SetupHandoffMode,
        providerDisplayName: String
    ) -> some View {
        switch presentation {
        case .standard:
            statusLabel(
                fallbackStatus,
                setupFailure: setupFailure,
                setupSentence: setupSentence,
                setupMode: setupMode,
                providerDisplayName: providerDisplayName
            )
        case .waitingForClaudeCode:
            // R2B1: the ellipsis says the wait is ongoing, matching every other waiting
            // status in the window ("Waiting for sign-in…", "Fetching…").
            Text("Waiting for Claude Code…")
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
        setupSentence: String?,
        setupMode: SetupHandoffMode,
        providerDisplayName: String
    ) -> some View {
        switch status {
        case .connected:
            // PB13: the window's one affirmative-state treatment, shared with "Saved
            // securely" in API Spend. Plain secondary text rendered identically to Stale,
            // which is the opposite state.
            SettingsSuccessStatus(text: "Connected")
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
            // R2C6: the popover's own sentence, read from Core. Settings used to print
            // "Needs sign-in" beside a row whose button said "Sign In" and whose popover card
            // said "Sign in with the official Claude CLI" — one act under three names, which
            // makes people ask whether the three do different things.
            Text(setupSentence ?? "Sign in with the official \(providerDisplayName) CLI")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        case .blocked:
            // PB9: "sign-in", the word the popover and every other status here uses for this
            // event. "login" was the only place it was called something else.
            Text("Another \(providerDisplayName) sign-in is open")
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

        /// R11: sign-in and removal states are management, not fetch health, so they
        /// survive a provider whose subscription switch is off — that switch only stops
        /// fetching, and an in-flight sign-in still reports itself. (L11A dims Add
        /// Account while off; a handoff already under way is unaffected.)
        var isSetupState: Bool {
            self == .waiting || self == .setupActive || self == .setupFailed
                || self == .blocked || self == .removing || self == .removalFailed
        }
    }

    // MARK: - Actions

    /// Create the account and immediately open its official-CLI sign-in so the add
    /// flow is one gesture: click Add → Terminal opens → sign in → row goes live.
    private func addAccount(for providerID: ProviderID) {
        _ = withAnimation(
            HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
        ) {
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
            get: {
                accountLabelFieldValue(
                    for: account,
                    draft: labelDrafts[account.key],
                    focusedAccountKey: focusedLabel
                )
            },
            set: { value in
                guard acceptsAccountLabelDraftChange(
                    for: account.key,
                    focusedAccountKey: focusedLabel
                ) else { return }
                labelDrafts[account.key] = value
            }
        )
    }

    /// R12: the ⌘W / pane-switch backstop for focus-loss commit.
    private func commitPendingLabels() {
        guard !labelDrafts.isEmpty else { return }
        for providerID in store.registeredProviderOrder {
            for account in AccountsSettingsInteractions.pendingLabelCommits(
                drafts: labelDrafts,
                accounts: store.accounts(for: providerID)
            ) {
                commitLabel(for: account)
            }
        }
        labelDrafts.removeAll()
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

    private var resetDialogPresented: Binding<Bool> {
        Binding(
            get: { resetCandidate != nil },
            set: {
                if !$0 {
                    resetCandidate = nil
                    restoreRemovalFocus()
                }
            }
        )
    }

    private func requestReset(_ account: ProviderAccount) {
        removalOrigin = account.key
        resetCandidate = account
    }

    private func makeMain(_ account: ProviderAccount) {
        removalOrigin = account.key
        var feedback: AccountsSettingsInteractions.PromotionFeedback?
        withAnimation(
            HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
        ) {
            feedback = AccountsSettingsInteractions.makeMain(account, in: store)
        }
        guard let feedback else { return }
        Task { @MainActor in
            await Task.yield()
            focusedRemovalAction = feedback.accountKey
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: feedback.announcement,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }

    private func restoreRemovalFocus() {
        let key = removalOrigin
        removalCandidate = nil
        resetCandidate = nil
        Task { @MainActor in
            await Task.yield()
            focusedRemovalAction = key
        }
    }
}

private extension View {
    /// R2C21: one control language in the Accounts action column. The `•••` menus get the
    /// same chrome as the `arrow.clockwise` and `trash` glyphs beside them — `.button` menu
    /// style routed through `HoverButtonStyle`, so one hover pill, one press, and one ~38pt
    /// target serve all three. `.borderlessButton` gave the menus no hover, no press, a bare
    /// 22pt target, and an AppKit `⌄` the glyph set has nowhere else.
    func accountActionsMenuChrome() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
            .foregroundStyle(.secondary)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}
