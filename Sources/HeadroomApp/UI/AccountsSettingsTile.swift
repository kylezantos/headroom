#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import Combine
import HeadroomCore

@MainActor
func settingsRecoveryActions(
    snapshot: UsageSnapshot,
    account: ProviderAccount,
    setupState: SetupSessionState
) -> AccountsSettingsInteractions.RecoveryRowActions? {
    guard setupHandoffRefusalMessage(for: setupState) == nil else { return nil }
    // R13/KTD12 (2026-09-19 sign-in plan): the row rendered Sign In *and* Check Now all
    // through a handoff, because `recoveryButtons` is gated on this being non-nil. While
    // the session owns its own controls — waiting, confirming, the timeout, a too-old CLI
    // — the outcome's fetch-recovery pair is suppressed the way a refusal already does.
    guard setupRowRecovery(for: setupState) == .outcomeRecovery else { return nil }
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
    guard setupSessionOffersStopWaiting(
              state: setupState,
              hasActiveHandoff: hasActiveHandoff(account)
          )
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
/// subscription account. Grouped per provider — brand row with an Add button and the
/// subscription switch, then one row per account in three slots (CA-S3): an editable label
/// with its status or email under it, one state or one button, and the account's "…" menu.
///
/// The built-in account *is* the user's own default login, so it can never be deleted —
/// its row shows a quiet "Default" tag, and once another account exists it offers a
/// non-destructive "stop tracking" instead of the extras' removal (which deletes that
/// account's Headroom-owned config home). A stop-tracked built-in can be resurfaced from
/// the provider header. All sign-ins run through the official CLI in
/// Terminal (compliance boundary unchanged); this tile only opens that handoff and
/// reflects the result.
struct AccountsSettingsTile: View {
    let store: UsageStore
    /// KTD3: resolved on the settings root so a pane switch neither blanks the badges nor
    /// re-reads every account's `.claude.json`.
    let duplicateLoginLabels: [AccountKey: String]
    /// R9: the provider group headers own the subscription switches, so the tile needs the
    /// root's surface binding (set + animate + provider-scoped due dispatch, KTD11) rather
    /// than a local toggle.
    let surfaceBinding: (UsageSurface) -> Binding<Bool>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var labelDrafts: [AccountKey: String] = [:]
    /// KTD8: a display row, so the confirmed removal follows the row's kind.
    @State private var removalCandidate: DisplayAccount?
    @State private var resetCandidate: ProviderAccount?
    @State private var removalOrigin: AccountKey?
    @State private var removalInProgress: AccountKey?
    @State private var hoveredLabel: AccountKey?
    /// CA-S3: the row whose name is showing its rename field; at rest a name is a label
    /// that truncates with an ellipsis.
    @State private var editingLabel: AccountKey?
    /// CA-M3: rows whose removal succeeded, held in their slot while their vessel drains.
    @State private var drainingRows: [ProviderID: [SettingsAccountDrainingRow]] = [:]
    @FocusState private var focusedLabel: AccountKey?
    @FocusState private var focusedRemovalAction: AccountKey?

    var body: some View {
        // The pane scaffold prints "Accounts" above this tile (U2/U4), so the tile carries no
        // title of its own. T3: the shared tile, so provider groups stand `groupToGroup` apart
        // like every other pane's groups; the old hand-rolled 10pt rhythm ran the intro line
        // into the first group. The bold group labels separate providers, so the hairline
        // between them went with it.
        //
        // CA-S4 (SET-10, COPY-04): the pane opens with its subject. The intro paragraph and
        // the display switch used to sit above the first provider; the switch now follows
        // the groups it applies to, and the trust promise is the tile's one footer sentence.
        SettingsTile {
            ForEach(store.registeredProviderOrder, id: \.self) { providerID in
                providerGroup(providerID)
            }

            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsSwitchRow(
                    title: "Use email addresses as account names",
                    isOn: Binding(
                        get: { store.useEmailAsAccountName },
                        set: { enabled in
                            commitPendingLabels()
                            focusedLabel = nil
                            store.setUseEmailAsAccountName(enabled)
                        }
                    )
                )
                // CA-S9 (COPY-07): where it shows and how to undo it, not the label again.
                SettingsHelpText(text: AccountsSettingsInteractions.emailNamesHelp)
            }

            SettingsHelpText(text: ProviderSignInCopy.accountsTrustFooter)
        }
        .confirmationDialog(
            removalCandidate.map(AccountsSettingsInteractions.removalDialogTitle(for:))
                ?? "Remove this account?",
            isPresented: removalDialogPresented,
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { row in
            let account = row.account
            // Stop-tracking is deliberately not `.destructive` — it hides the row and
            // deletes nothing, unlike extra-account removal. Removing a remembered row
            // only hides it too (R11).
            Button(
                account.isBuiltIn && !row.isRemembered
                    ? "Stop Tracking \(store.desktopAccountName(for: account))"
                    : "Remove \(store.desktopAccountName(for: account))",
                role: AccountsSettingsInteractions.removalIsDestructive(for: row) ? .destructive : nil
            ) {
                removalInProgress = account.key
                Task { @MainActor in
                    let result = await performRemoval(of: row) {
                        await AccountsSettingsInteractions.removeAccount(row, from: store)
                    }
                    guard result == .removed else {
                        removalInProgress = nil
                        restoreRemovalFocus()
                        return
                    }
                    // CA-M3: the row already holds its slot for the drain; this transaction
                    // only settles the dialog bookkeeping.
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
        } message: { row in
            Text(AccountsSettingsInteractions.removalDialogMessage(for: row))
        }
        .confirmationDialog(
            "Sign out and set up again?",
            isPresented: resetDialogPresented,
            titleVisibility: .visible,
            presenting: resetCandidate
        ) { account in
            Button("Sign Out & Set Up Again") {
                // D7 (OpenCode plan): this dialog is the built-in warning for a reset, so the
                // start is already confirmed and must not ask a second time.
                _ = AccountsSettingsInteractions.resetBuiltIn(
                    account,
                    in: store,
                    beginReset: { SetupSessions.resetSetup(for: $0, confirmed: true) }
                )
                resetCandidate = nil
                restoreRemovalFocus()
            }
            Button("Cancel", role: .cancel) { restoreRemovalFocus() }
        } message: { account in
            Text(AccountsSettingsInteractions.resetDialogMessage(
                for: account,
                providerDisplayName: store.displayNames[account.providerID]
                    ?? account.providerID.raw.capitalized
            ))
        }
        // Commit a pending rename when the field loses focus — Enter-only commit
        // silently discarded renames while still displaying the draft (code-review
        // finding).
        .onChange(of: focusedLabel) { previous, current in
            if let previous, let row = displayRow(for: previous) {
                commitLabel(for: row)
            }
            // CA-S3: the field gives way to the truncating label once it loses focus.
            if let previous, previous == editingLabel, current != previous { editingLabel = nil }
        }
        // R12: leaving Accounts — pane switch or window close — commits a typed rename
        // instead of discarding it. Focus loss already commits, but ⌘W tears the tile
        // down without moving focus first.
        .onDisappear {
            commitPendingLabels()
            // R12 follow-up: SwiftUI restores focus to the last focused `TextField`, so
            // without this the renamed row reopened wearing its editing chrome while its
            // siblings looked static.
            focusedLabel = nil
            editingLabel = nil
        }
        // R12: `onDisappear` is not guaranteed on app termination, so ⌘Q with a focused,
        // uncommitted draft could still discard it. Same single commit path, one more trigger.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            commitPendingLabels()
        }
    }

    private func displayRow(for key: AccountKey) -> DisplayAccount? {
        store.displayProjection(for: key.providerID).row(for: key)
    }

    // MARK: - Provider group

    @ViewBuilder private func providerGroup(_ providerID: ProviderID) -> some View {
        // Engine rows drive capacity, the counter, the switch and capability recovery;
        // the list draws the display rows, remembered ones after the engine rows (KTD8).
        let accounts = store.accounts(for: providerID)
        let rows = store.displayAccounts(for: providerID)
        // CA-M3: what is drawn, the store's rows plus any still draining in their slots.
        let items = SettingsAccountListItem.items(rows: rows, draining: drainingRows[providerID] ?? [])
        // U8: one read per provider, and only when a remembered row needs its last-read time.
        let lastReadAt: [AccountKey: Date] = rows.contains(where: \.isRemembered)
            ? Dictionary(
                store.rememberedAccounts(for: providerID).compactMap { summary in
                    summary.lastReadAt.map { (summary.key, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            : [:]
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
        VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    ProviderLogoView(providerID: providerID, size: 15)
                    SettingsGroupLabel(displayName)
                }
                if presentation.showsAccountCounter,
                   // CA-S5: absent until two short of the tested envelope. A stop-tracked
                   // built-in is hidden from the list but keeps its registry slot, so count
                   // it — otherwise the header reads "19 of 20" while Add Account is disabled.
                   let counter = AccountsSettingsInteractions.accountCounterText(
                       usedSlots: accounts.count + (store.isBuiltInTrackingStopped(for: providerID) ? 1 : 0),
                       capacity: capacity
                   ) {
                    Text(counter)
                        .font(SettingsType.help.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                mergedBuiltInMenu(for: providerID)
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
                // RM1: self-timed so it still fades under Reduce Motion.
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
                .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
            ForEach(items) { item in
                Group {
                    switch item {
                    case .live(let row):
                        accountRow(row, lastReadAt: lastReadAt[row.key], capability: capability, presentation: presentation)
                    case .draining(let draining):
                        SettingsAccountDrainingRowView(item: draining) {
                            finishDrain(draining, for: providerID)
                        }
                    }
                }
                .transition(SettingsAccountExit.transition(reduceMotion: reduceMotion))
            }
            if store.isBuiltInTrackingStopped(for: providerID) {
                // The way back from stop-tracking: resurface the CLI's own login and
                // fetch it right away. Quiet on purpose — it's an undo, not a feature.
                Button(AccountsSettingsInteractions.showDefaultLoginTitle) {
                    _ = withAnimation(
                        HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
                    ) {
                        AccountsSettingsInteractions.resumeTrackingBuiltIn(
                            for: providerID,
                            in: store
                        )
                    }
                }
                // CA-S3 (SET-11b): one button family in the pane, the native small bordered
                // button the rows and headers use. B3H's reason for a resting container
                // still holds, and the bordered button has one.
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(AccountsSettingsInteractions.showDefaultLoginHelp(for: providerID))
                .padding(.leading, 16)
            }
            if let note = AccountsSettingsInteractions.providerGroupNote(for: providerID) {
                SettingsHelpText(text: note)
            }
            if let offHelpText = presentation.offHelpText {
                // R11: one line naming the only consequence of "off". Without it, an
                // account added while the surface is off would look broken rather than
                // simply unpolled (code-review finding).
                SettingsHelpText(text: offHelpText)
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
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
            value: items.map(\.id)
        )
        .onAppear {
            SetupSessions.announceCapabilityIfNeeded(announcedCapability, for: providerID)
        }
        .onChange(of: capabilityState) {
            SetupSessions.announceCapabilityIfNeeded(announcedCapability, for: providerID)
        }
    }

    /// Default-login U10 (KTD11): while the default login shows through the extra row that
    /// reads the same account, the list draws that one row with its own actions, and the
    /// built-in's "Sign Out & Set Up Again" and stop-tracking live here. Nothing is drawn
    /// for a provider with no merge, so its header is unchanged (R15). No row is marked as
    /// the default login (R16).
    @ViewBuilder private func mergedBuiltInMenu(for providerID: ProviderID) -> some View {
        let actions = AccountsSettingsInteractions.mergedBuiltInActions(for: providerID, in: store)
        if actions != .unavailable,
           let builtIn = AccountsSettingsInteractions.mergedBuiltIn(for: providerID, in: store) {
            Menu {
                // CA-S5: "Default login", the name CONCEPTS.md and the row badge use.
                Section(AccountsSettingsInteractions.defaultLoginSection) {
                    Button("Sign Out & Set Up Again") { requestReset(builtIn) }
                    if actions == .resetAndStopTracking {
                        Button("Stop Tracking") {
                            removalOrigin = builtIn.key
                            removalCandidate = DisplayAccount(account: builtIn, kind: .engine)
                        }
                    }
                }
            } label: {
                AccountActionsMenuGlyph()
            }
            .accountActionsMenuChrome()
            .help("Default login actions")
            .accessibilityLabel("Actions for the \(store.displayNames[providerID] ?? providerID.raw) default login")
            .focused($focusedRemovalAction, equals: builtIn.key)
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

    /// CA-S3: the per-row facts both the live row and its drain need.
    private struct RowContext {
        let account: ProviderAccount
        let snapshot: UsageSnapshot
        let removalState: AccountRemovalState?
        let setupState: SetupSessionState
        let status: AccountStatus
        let capabilityRow: AccountsSettingsInteractions.CapabilityRowPresentation
        let recoveryActions: AccountsSettingsInteractions.RecoveryRowActions?
        let stopWaitingAccount: ProviderAccount?
        let email: String?
        let slots: AccountsSettingsInteractions.RowSlots
    }

    private func rowContext(
        _ row: DisplayAccount,
        lastReadAt: Date?,
        capability: CapabilityRecoveryPresentation?,
        presentation: AccountsSettingsInteractions.ProviderGroupPresentation,
        now: Date = Date()
    ) -> RowContext {
        let account = row.account
        // A remembered row is never probed: no sign-in, retry or recovery action (R12).
        let offersRecovery = row.kind.offersRetry
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
        // affordance is management and stays.
        let recoveryActions = presentation.hidesFetchRecovery || !offersRecovery
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
        let stopWaitingAccount = settingsStopWaitingAccount(
            account,
            removalState: removalState,
            setupState: setupState
        )
        let providerDisplayName = store.displayNames[account.providerID]
            ?? account.providerID.raw.capitalized
        let setupSentence: String? = {
            guard case .stale(let reason) = snapshot.freshness else { return nil }
            return reason.providerSetupOutcome?.message
        }()
        let slots = AccountsSettingsInteractions.rowSlots(.init(
            status: status,
            isRemembered: row.isRemembered,
            // U8 (R7): the popover's tag, as this row's state. It is not fetch state, so it
            // shows while the provider's switch is off too.
            rememberedLabel: row.isRemembered
                ? AccountsSettingsInteractions.rememberedStatus(lastReadAt: lastReadAt, snapshot: snapshot, now: now)
                : nil,
            hidesStatus: presentation.hidesAccountStatus(isSetupState: status.isSetupState),
            capabilityRow: capabilityRow,
            removalState: removalState,
            setupRecovery: setupRowRecovery(for: setupState),
            offersStopWaiting: stopWaitingAccount != nil,
            offersRecovery: offersRecovery,
            recoveryActions: recoveryActions,
            setupFailure: setupFailure,
            setupWaitingTitle: SetupSessions.waitingPhase(for: account)?.copy.title,
            isDeviceCode: SetupSessions.mode(for: account) == .deviceCode,
            providerDisplayName: providerDisplayName,
            // CA-P3: one phrase for an old reading, with its age.
            staleLabel: Countdown.staleReadLabel(capturedAt: snapshot.capturedAt, now: now),
            setupSentence: setupSentence
        ))
        return RowContext(
            account: account,
            snapshot: snapshot,
            removalState: removalState,
            setupState: setupState,
            status: status,
            capabilityRow: capabilityRow,
            recoveryActions: recoveryActions,
            stopWaitingAccount: stopWaitingAccount,
            email: accountEmail(from: snapshot),
            slots: slots
        )
    }

    private func accountRow(
        _ row: DisplayAccount,
        lastReadAt: Date?,
        capability: CapabilityRecoveryPresentation?,
        presentation: AccountsSettingsInteractions.ProviderGroupPresentation
    ) -> some View {
        let context = rowContext(row, lastReadAt: lastReadAt, capability: capability, presentation: presentation)
        let account = row.account
        let isEditingLabel = focusedLabel == account.key || hoveredLabel == account.key
        let loadingLevel = SettingsAccountLoadingState.displayedLevel(snapshot: store.appDisplaySnapshot(for: account.key),
            mode: store.usagePercentageMode, choice: store.menuBarWindowChoice(for: account.providerID))
        return AccountRowSlotsLayout {
            accountIdentity(row, email: context.email, secondLine: context.slots.secondLine,
                            isEditingLabel: isEditingLabel)
        } trailing: {
            HStack(spacing: 6) {
                SettingsAccountWaitPill(store: store, account: account, status: context.status,
                    waitingForClaudeCode: context.capabilityRow == .waitingForClaudeCode,
                    showsStatus: !presentation.hidesAccountStatus(isSetupState: context.status.isSetupState),
                    level: loadingLevel)
                trailingContent(row, context: context)
            }
        } menu: {
            accountMenu(row, context: context)
        }
        // R11: dimmed, never disabled — "off" means "not fetched", so every management
        // control in the row still works. Matches the disabled-swatch step in
        // `MeterStyleTile`.
        .opacity(presentation.dimsAccountRows ? 0.45 : 1)
        // RM1: the subscription switch's scope is `.movement`, so the dim carries its own
        // crossfade and keeps it under Reduce Motion.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: presentation.dimsAccountRows
        )
        .disabled(context.removalState == .removing)
        .onAppear { SetupSessions.announceFailureIfNeeded(for: account) }
        .onChange(of: context.setupState) {
            SetupSessions.announceFailureIfNeeded(for: account)
        }
    }

    @ViewBuilder private func accountIdentity(
        _ row: DisplayAccount,
        email: String?,
        secondLine: AccountsSettingsInteractions.RowSecondLine?,
        isEditingLabel: Bool
    ) -> some View {
        let account = row.account
        let emailIsName = store.useEmailAsAccountName && email != nil
        VStack(alignment: .leading, spacing: 1) {
            // CA-S3 (SET-01): the tags follow the name at 6pt on its baseline, as the approved
            // mock draws them, rather than at a fixed column 158pt in that left short names
            // apart from their tag. At rest the name takes the row's free width and ends in a
            // tail ellipsis; the tags never compress, so the name gives way first.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if emailIsName, let email {
                    Text(email)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .help(email)
                        .accessibilityLabel("\(email) account name")
                } else if editingLabel != account.key && focusedLabel != account.key {
                    // At rest: a label that truncates with an ellipsis, so a 40-character name
                    // never clips mid-glyph. A click swaps in the rename field below.
                    Button { beginRename(account.key) } label: {
                        Text(account.label)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(
                                Color.primary.opacity(isEditingLabel ? 0.06 : 0),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // R2M10/S3A: the approach fill, opacity only, so it keeps its timing under
                    // Reduce Motion.
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
                    .help("\(account.label)\nClick to rename this account")
                    .accessibilityLabel("\(store.desktopAccountName(for: account)) account name")
                    .accessibilityHint("Renames this account")
                } else {
                    // Quiet at rest, but the affordance reveals on approach: a hover/focus fill
                    // marks the label as editable (impeccable audit P1 — a plain field that
                    // renders identically to static text hides the rename feature entirely).
                    TextField("Account name", text: labelBinding(for: account))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focusedLabel, equals: account.key)
                        .onSubmit { commitLabel(for: row) }
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
                        // The rename field keeps its editing width; it scrolls a long name.
                        .frame(width: AccountRowMetrics.nameWidth, alignment: .leading)
                        .onAppear {
                            Task { @MainActor in
                                await Task.yield()
                                if editingLabel == account.key { focusedLabel = account.key }
                            }
                        }
                        .help("Click to rename this account")
                        .accessibilityLabel("\(store.desktopAccountName(for: account)) account name")
                }
                // CA-S3 (SET-01): the tags sit on the identity's first line, so they never
                // float mid-row between the name and the trailing column.
                if account.isBuiltIn {
                    // CA-S5 (COPY-11): "Default", the account the provider's CLI in Terminal
                    // is signed in to. "CLI login" named the mechanism.
                    pillBadge(
                        AccountsSettingsInteractions.defaultLoginBadge,
                        help: ProviderSignInCopy.defaultLoginHelp(for: account.providerID)
                    )
                }
                if let original = duplicateLoginLabels[account.key] {
                    // Detection only — the user decides which record to keep; Headroom
                    // never merges or removes duplicate rows on its own.
                    pillBadge(
                        "Same login as \(original)",
                        help: "This row is signed in to the same Claude account as \(original). You can remove one without signing out of the other.",
                        accessibilityLabel: "\(store.desktopAccountName(for: account)) uses the same login as \(original)"
                    )
                }
            }
            .lineLimit(1)
            if let secondLine {
                secondLineText(secondLine)
            } else if !emailIsName, let email {
                // Under the (renameable) name, not beside it: the label is the user's
                // word for the account and the address is what it actually resolves to,
                // so managing accounts here means verifying one against the other. The
                // 6pt inset matches the field above, so both sit on one text axis.
                Text(email)
                    .font(SettingsType.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .help(email)
                    .accessibilityLabel("Signed in as \(email)")
            }
        }
    }

    /// CA-S3 (SET-01, UX-04): the row's status, on the identity's second line where the
    /// email sits otherwise. It replaces the trailing status sentence of R2C6 and R2C11.
    private func secondLineText(_ line: AccountsSettingsInteractions.RowSecondLine) -> some View {
        Text(line.text)
            .font(line.tone == .warning ? .system(size: 11, weight: .medium) : SettingsType.help)
            .foregroundStyle(secondLineInk(line.tone))
            .lineLimit(line.lineLimit)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .help(line.help ?? line.text)
    }

    private func secondLineInk(_ tone: AccountsSettingsInteractions.RowSecondLine.Tone) -> Color {
        switch tone {
        // R2C5: a lifecycle sentence, not a measurement — it stays off the amber ramp.
        case .label: ProviderStyle.meterLabelInk(scheme: colorScheme)
        case .secondary: Color.secondary
        case .warning: ProviderStyle.severityColor(for: .low, scheme: colorScheme)
        }
    }

    /// CA-S3: exactly one state or one native small button.
    @ViewBuilder private func trailingContent(_ row: DisplayAccount, context: RowContext) -> some View {
        let account = row.account
        switch context.slots.trailing {
        case .connected:
            // PB13: the window's one affirmative-state treatment, shared with "Saved
            // securely" in API Spend.
            SettingsSuccessStatus(text: "Connected")
        case .progress(let text):
            Text(text)
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
        case .lastRead(let text, let help):
            // Clock glyph separates "data gone old" from the affirmative "Connected".
            // Restrained on purpose: an old reading is usually a transient blip.
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                Text(text)
                    .font(SettingsType.help.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
        case .waitingForClaudeCode:
            // R2B1: the ellipsis says the wait is ongoing, matching every other waiting
            // status in the window ("Waiting for sign-in…", "Fetching…").
            Text("Waiting for Claude Code…")
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
        case .retainedUsage:
            retainedUsage(context.snapshot)
        case .stopWaiting:
            if let stopWaitingAccount = context.stopWaitingAccount {
                StopWaitingButton(
                    account: stopWaitingAccount,
                    onConfirmationPresented: { removalOrigin = stopWaitingAccount.key },
                    onStop: { AccountsSettingsInteractions.stopWaiting(for: $0, in: store) },
                    onDismiss: restoreRemovalFocus,
                    // CA-P14 (UX-02): an abandoned Add Account offers to remove the row it
                    // made. Built-in rows and extras that ever signed in keep today's dialog.
                    onRemoveAccount: AccountsSettingsInteractions.stopWaitingRemovesAccount(
                        stopWaitingAccount, snapshot: context.snapshot
                    ) ? { removeAfterStoppingWait(row, account: $0) } : nil
                )
            }
        case .button(let button):
            Button(button.label) { perform(button, for: row, context: context) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(accessibilityLabel(for: button, account: account, context: context))
        case .none:
            EmptyView()
        }
    }

    private func retainedUsage(_ snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 7) {
            // KTD6.2: the popover row's integer; a row it would hide shows no figure here either.
            ForEach(Array(snapshot.windows.prefix(2).enumerated()), id: \.offset) { _, window in
                Text("\(window.kind.compactName) \(store.usagePercentageMode.displayedPercentage(for: window).map { "\($0)%" } ?? "—")")
            }
        }
        .font(SettingsType.help.monospacedDigit())
        .foregroundStyle(.secondary)
        .opacity(0.68)
        .accessibilityLabel(
            "Last known usage. " + snapshot.windows.prefix(2).map { window in
                store.usagePercentageMode.displayedPercentage(for: window).map {
                    "\(window.kind.spokenName) \($0) percent \(store.usagePercentageMode.term)"
                } ?? "\(window.kind.spokenName) not available"
            }.joined(separator: ", ")
        )
    }

    private func perform(
        _ button: AccountsSettingsInteractions.RowButton,
        for row: DisplayAccount,
        context: RowContext
    ) {
        let account = row.account
        switch button {
        case .recovery:
            guard let actions = context.recoveryActions else { return openSetup(for: account) }
            SetupSessions.performRecovery(
                actions.primaryAction,
                for: account,
                onRetry: { store.refreshAccountNow(account.key) }
            )
        case .signIn, .tryAgainFailedSetup:
            openSetup(for: account)
        case .continueSetup:
            SetupSessions.continueSetup(for: account)
        case .tryAgainSetup:
            tryAgainSetup(for: account)
        case .tryAgainRemoval:
            Task { @MainActor in
                _ = await performRemoval(of: row) {
                    await AccountsSettingsInteractions.removeAccount(row, from: store)
                }
            }
        }
    }

    /// KTD12 (2026-09-19 sign-in plan): not `.checkNow` and never labelled "Check Now" — Try
    /// Again brings the still-open window forward and resumes the wait (R10), or with none
    /// open stages a fresh handoff, which is what re-reads a too-old CLI's version (R6).
    private func tryAgainSetup(for account: ProviderAccount) {
        SetupSessions.tryAgain(
            for: account,
            onRetry: { store.refreshAccountNow(account.key) }
        )
    }

    private func accessibilityLabel(
        for button: AccountsSettingsInteractions.RowButton,
        account: ProviderAccount,
        context: RowContext
    ) -> String {
        let name = store.desktopAccountName(for: account)
        switch button {
        case .recovery:
            return context.recoveryActions?.primaryAccessibilityLabel ?? "\(button.label) for \(name)"
        case .signIn: return "Sign in for \(name)"
        case .continueSetup: return "Continue setup for \(name)"
        case .tryAgainSetup, .tryAgainFailedSetup: return "Try signing in again for \(name)"
        case .tryAgainRemoval: return "Try removing \(name) again"
        }
    }

    /// CA-S3: the row's third slot, always the "…" menu. The trash and reset glyphs that used
    /// to stand here in some rows put a different control at the same x in each row; a row
    /// with nothing to offer keeps the slot open so the trailing column still ends on one x.
    @ViewBuilder private func accountMenu(_ row: DisplayAccount, context: RowContext) -> some View {
        let account = row.account
        let sections = AccountsSettingsInteractions.rowMenuSections(
            lead: context.slots.menuLead,
            isBuiltIn: account.isBuiltIn,
            isRemembered: row.isRemembered,
            builtInActions: AccountsSettingsInteractions.builtInRowActions(for: account, in: store),
            promotion: AccountsSettingsInteractions.promotionState(for: row, in: store)
        )
        if sections.isEmpty {
            Color.clear
                .frame(width: AccountRowMetrics.menuSlotWidth, height: 22)
                .accessibilityHidden(true)
        } else {
            let offersMakeMain = sections.contains { $0.contains(.makeMain) }
            Menu {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 { Divider() }
                    ForEach(Array(section.enumerated()), id: \.offset) { _, item in
                        menuItem(item, row: row, context: context)
                    }
                }
            } label: {
                AccountActionsMenuGlyph()
            }
            .accountActionsMenuChrome()
            .help("Account actions")
            .accessibilityLabel(
                "Actions for \(store.desktopAccountName(for: account))\(offersMakeMain ? ", including Make Main" : "")"
            )
            .focused($focusedRemovalAction, equals: account.key)
        }
    }

    @ViewBuilder private func menuItem(
        _ item: AccountsSettingsInteractions.RowMenuItem,
        row: DisplayAccount,
        context: RowContext
    ) -> some View {
        let account = row.account
        switch item {
        case .lead(let lead):
            Button(lead.label) {
                switch lead {
                case .secondaryRecovery:
                    guard let action = context.recoveryActions?.secondaryAction else { return }
                    SetupSessions.performRecovery(
                        action,
                        for: account,
                        onRetry: { store.refreshAccountNow(account.key) }
                    )
                case .tryAgainSetup:
                    tryAgainSetup(for: account)
                case .cancelRemoval:
                    store.cancelAccountRemoval(account.key)
                    removalOrigin = account.key
                    restoreRemovalFocus()
                }
            }
            .accessibilityLabel(
                context.recoveryActions.flatMap { actions in
                    if case .secondaryRecovery = lead { return actions.secondaryAccessibilityLabel }
                    return nil
                } ?? "\(lead.label) for \(store.desktopAccountName(for: account))"
            )
        case .makeMain:
            Button("Make Main") { makeMain(account) }
        case .signOutAndSetUpAgain:
            Button("Sign Out & Set Up Again") { requestReset(account) }
        case .stopTracking:
            Button("Stop Tracking") {
                removalOrigin = account.key
                removalCandidate = row
            }
        case .removeAccount(let destructive):
            // R2B1: the act deletes this account's sign-in on the Mac, and its own
            // confirmation is already `.destructive` — the menu item that opens it should
            // look like what it opens. A remembered row's removal only hides it (R11).
            Button("Remove Account", role: destructive ? .destructive : nil) {
                removalOrigin = account.key
                removalCandidate = row
            }
        }
    }

    // MARK: - CA-M3: the drain

    /// CA-M3: runs a removal and, when it succeeds, holds the row in its slot for the drain.
    /// The row is captured before the store lets it go; it is inserted in the same main-actor
    /// turn the store detaches it, so no frame draws the list without it.
    private func performRemoval(
        of row: DisplayAccount,
        _ remove: () async -> AccountRemovalResult
    ) async -> AccountRemovalResult {
        let captured = drainingRow(for: row)
        let result = await remove()
        guard result == .removed,
              SettingsAccountExit.holdsSlot(reduceMotion: reduceMotion),
              let captured,
              !store.displayAccounts(for: row.account.providerID).contains(where: { $0.key == row.key })
        else { return result }
        drainingRows[row.account.providerID, default: []].append(captured)
        return result
    }

    private func removeAfterStoppingWait(_ row: DisplayAccount, account: ProviderAccount) {
        Task { @MainActor in
            _ = await performRemoval(of: row) {
                await AccountsSettingsInteractions.stopWaitingAndRemove(account, from: store)
            }
        }
    }

    private func drainingRow(for row: DisplayAccount) -> SettingsAccountDrainingRow? {
        let providerID = row.account.providerID
        let rows = store.displayAccounts(for: providerID)
        guard let index = rows.firstIndex(where: { $0.key == row.key }) else { return nil }
        let snapshot = store.snapshot(for: row.key)
        let email = accountEmail(from: snapshot)
        let emailIsName = store.useEmailAsAccountName && email != nil
        return SettingsAccountDrainingRow(
            row: row,
            title: emailIsName ? (email ?? row.label) : row.label,
            detail: emailIsName ? nil : email,
            level: SettingsAccountLoadingState.displayedLevel(
                snapshot: store.appDisplaySnapshot(for: row.key),
                mode: store.usagePercentageMode,
                choice: store.menuBarWindowChoice(for: providerID)
            ),
            index: index
        )
    }

    /// CA-M3: the drain is over and the row is transparent; now the gap closes on `reorder`.
    private func finishDrain(_ row: SettingsAccountDrainingRow, for providerID: ProviderID) {
        withAnimation(
            HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
        ) {
            drainingRows[providerID]?.removeAll { $0.id == row.id }
        }
    }

    /// R2C21: the `•••` glyph, 11pt **regular**, not semibold. One stroke weight per icon
    /// set; a heavier glyph read as emphasis it doesn't carry.
    fileprivate struct AccountActionsMenuGlyph: View {
        var body: some View {
            Image(systemName: "ellipsis")
                .font(SettingsType.help)
                .frame(width: 22, height: 22)
        }
    }

    /// The row-tag capsule shared by "Default" and "Same login as X". Tokens live in
    /// `SettingsPillBadge` so the Menu Bar pane's "Off" tag renders the same badge.
    private func pillBadge(
        _ text: String,
        help helpText: String,
        accessibilityLabel: String? = nil
    ) -> some View {
        SettingsPillBadge(text: text)
            // CA-S3: a tag never compresses; the name beside it truncates first.
            .fixedSize()
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
                // Review #6 (2026-09-19 sign-in plan): a reset blanks the row to `.pending`
                // and an exit-signalled handoff runs no check until Terminal closes, so an
                // open session has to outrank the blank reading here.
                self = waiting ? .waiting : .fetching
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
            for row in AccountsSettingsInteractions.pendingLabelCommits(
                drafts: labelDrafts,
                rows: store.displayAccounts(for: providerID)
            ) {
                commitLabel(for: row)
            }
        }
        labelDrafts.removeAll()
    }

    private func commitLabel(for row: DisplayAccount) {
        guard let draft = labelDrafts[row.key] else { return }
        AccountsSettingsInteractions.commitLabel(draft, for: row, in: store)
        labelDrafts[row.key] = nil
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

    /// CA-S3: a click on a name at rest shows its rename field, which takes focus once it
    /// is in the hierarchy.
    private func beginRename(_ key: AccountKey) {
        editingLabel = key
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

/// CA-S3: the row's fixed slot sizes. The trailing slot's 96pt minimum fits "Connected",
/// "Sign In" and "Stop Waiting" alike, so a short state never pulls the column in.
enum AccountRowMetrics {
    static let trailingMinWidth: CGFloat = 96
    /// The `•••` glyph's 22pt frame plus `HoverButtonStyle`'s 2pt each side.
    static let menuSlotWidth: CGFloat = 26
    /// The rename field's width while editing. At rest a name takes the row's free width.
    static let nameWidth: CGFloat = 158
    /// 16pt + the field's 6pt inner pad lands the label text at the 22pt provider-name axis.
    static let leadingInset: CGFloat = 16
}

/// CA-S3 (SET-01): the three slots every Accounts row lays out, live or draining: identity
/// (flexible), one state or button (trailing, fixed minimum), the menu (fixed). The trailing
/// column no longer moves with how many buttons a row has. Overturns craft round 2's R2C11.
struct AccountRowSlotsLayout<Identity: View, Trailing: View, Menu: View>: View {
    @ViewBuilder let identity: Identity
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let menu: Menu

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            identity
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .fixedSize()
                .frame(minWidth: AccountRowMetrics.trailingMinWidth, alignment: .trailing)
            menu
                .frame(width: AccountRowMetrics.menuSlotWidth)
        }
        .padding(.leading, AccountRowMetrics.leadingInset)
    }
}

/// CA-M3 (MOT-03): a removed row, drawn in the slot it held while its vessel drains. Its own
/// clock, so the tile's body renders once for the whole drain; `onDrained` closes the gap.
struct SettingsAccountDrainingRowView: View {
    let item: SettingsAccountDrainingRow
    let onDrained: () -> Void
    @State private var progress = 0.0

    var body: some View {
        AccountRowSlotsLayout {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                if let detail = item.detail {
                    Text(detail)
                        .font(SettingsType.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                }
            }
        } trailing: {
            SettingsAccountDrainPill(level: item.level)
        } menu: {
            Color.clear.frame(width: AccountRowMetrics.menuSlotWidth, height: 22)
        }
        .modifier(SettingsAccountDrainModifier(progress: progress))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(HeadroomMotion.drain) {
                progress = 1
            } completion: {
                onDrained()
            }
        }
    }
}

private extension View {
    /// R2C21: one control language in the Accounts action column: `.button` menu style routed
    /// through `HoverButtonStyle`, so one hover pill, one press and one ~26pt target.
    /// `.borderlessButton` gave the menus no hover, no press, a bare 22pt target, and an
    /// AppKit `⌄` the glyph set has nowhere else.
    func accountActionsMenuChrome() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
            .foregroundStyle(.secondary)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}
