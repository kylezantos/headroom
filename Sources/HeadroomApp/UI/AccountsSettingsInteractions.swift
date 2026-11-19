import Foundation
import HeadroomCore

enum CapabilityRecoveryActionState: Equatable {
    case enabled
    case refused(String)
}

/// Provider-wide recovery stays separate from account snapshots. This wrapper adds only
/// surface state: an open Terminal handoff keeps the notice visible while retry/setup
/// actions explain why they cannot start another handoff yet.
struct CapabilityRecoveryPresentation: Equatable {
    let recovery: ProviderRecoveryPresentation
    let hasActiveSetupSession: Bool

    func state(for action: SetupRecoveryAction) -> CapabilityRecoveryActionState {
        guard hasActiveSetupSession else { return .enabled }
        switch action {
        case .checkNow, .openClaudeSetup:
            return .refused("Close setup, then try again")
        default:
            return .enabled
        }
    }
}

/// R2C7: `hasRetainedReading` is true when the same card still draws usage from an earlier
/// capture, so the sentence can say the reading is the last one rather than ignore it.
func capabilityRecoveryPresentation(
    state: ProviderCapabilityState?,
    hasActiveSetupSession: Bool,
    hasRetainedReading: Bool = false
) -> CapabilityRecoveryPresentation? {
    guard let recovery = state?.recoveryPresentation(hasRetainedReading: hasRetainedReading) else { return nil }
    return CapabilityRecoveryPresentation(
        recovery: recovery,
        hasActiveSetupSession: hasActiveSetupSession
    )
}

struct CapabilityAnnouncementDedupe {
    private var lastStates: [ProviderID: ProviderCapabilityState] = [:]

    mutating func announcement(
        for providerID: ProviderID,
        state: ProviderCapabilityState?
    ) -> String? {
        guard lastStates[providerID] != state else { return nil }
        lastStates[providerID] = state
        guard let status = state?.recoveryPresentation?.status else { return nil }
        return "Claude Code availability. \(status)"
    }
}

/// App-boundary account actions shared by the Settings controls and their deterministic tests.
/// Provider effects remain injected: adding an account invokes only the selected account's
/// official-CLI handoff, while persistence and cleanup stay owned by `UsageStore`.
@MainActor
enum AccountsSettingsInteractions {
    enum PromotionState: Equatable {
        case unavailable
        case primary
        case available
    }

    struct PromotionFeedback: Equatable {
        let accountKey: AccountKey
        let announcement: String
    }

    enum BuiltInRowActions: Equatable {
        case unavailable
        case resetOnly
        case resetAndStopTracking
    }
    struct RecoveryRowActions: Equatable {
        let presentation: ProviderRecoveryPresentation
        let accountLabel: String

        var primaryLabel: String { presentation.primaryLabel }
        var primaryAction: SetupRecoveryAction { presentation.primaryAction }
        var primaryAccessibilityLabel: String { "\(primaryLabel) for \(accountLabel)" }
        var secondaryLabel: String? { presentation.secondaryLabel }
        var secondaryAction: SetupRecoveryAction? { presentation.secondaryAction }
        var secondaryAccessibilityLabel: String? {
            secondaryLabel.map { "\($0) for \(accountLabel)" }
        }
        /// CA-S3: a second recovery action exists. It leads the row's "…" menu; the row
        /// itself shows one button only (overturns craft round 2's R2C11 second button line).
        var hasSecondaryAction: Bool {
            secondaryLabel != nil && secondaryAction != nil
        }
    }

    /// R9/R10 (KTD6): the provider group header's subscription switch. The switch is the
    /// only thing "off" governs — it decides whether Headroom *fetches* the provider, so
    /// its disabled state exists purely to stop a flip mid-handoff, never to lock the
    /// group's account management.
    struct SubscriptionSwitchPresentation: Equatable {
        let isEnabled: Bool
        /// Non-nil only while disabled: the tooltip that names the blocking sign-in (R10).
        let helpText: String?
        let accessibilityLabel: String
    }

    /// L11A: the group header's "Add Account…" button. It stays *shown* wherever the
    /// provider is multi-account — a control that vanishes is harder to learn than one
    /// that is dimmed — and carries its own reason for being unavailable.
    enum AddAccountActionState: Equatable {
        case enabled(help: String)
        case disabled(help: String)

        var isEnabled: Bool {
            if case .enabled = self { return true }
            return false
        }

        var helpText: String {
            switch self {
            case .enabled(let help), .disabled(let help): help
            }
        }
    }

    /// R11: "off" means "not fetched", never "unmanageable". Fetch-derived chrome (status
    /// text, fetch-recovery buttons, the provider capability banner) disappears and the
    /// rows dim, while sign-in, rename, removal, stop-tracking and "Show CLI Account"
    /// stay live.
    ///
    /// L11A revises R11 for one control: "Add Account…" now dims with the rest of the
    /// group. It was left live so a first account could be created before the switch had
    /// ever been turned on, but that made the one full-contrast control in an off group
    /// the one that does the most. The switch itself stays enabled, so the first-account
    /// path costs one extra click and nothing else.
    struct ProviderGroupPresentation: Equatable {
        let subscriptionSwitch: SubscriptionSwitchPresentation
        let isFetching: Bool
        let showsAccountCounter: Bool
        let showsAddAction: Bool
        let addAction: AddAccountActionState

        var dimsAccountRows: Bool { !isFetching }
        /// R11: only *fetch-derived* status hides while the provider is off. Sign-in the
        /// user starts anyway ("Waiting for sign-in…", setup failure, blocked, removal)
        /// is management state and must stay visible, or the handoff looks like nothing
        /// happened (code-review finding).
        func hidesAccountStatus(isSetupState: Bool) -> Bool {
            !isFetching && !isSetupState
        }
        var hidesFetchRecovery: Bool { !isFetching }
        var hidesCapabilityBanner: Bool { !isFetching }
        /// R2B1: one constant, shared with the Menu Bar pane's Off-tag tooltip, so the two
        /// statements of this rule cannot drift — they already disagreed on the full stop.
        var offHelpText: String? {
            isFetching ? nil : SettingsCopy.providerOffNotice
        }
    }

    static func subscriptionSwitchPresentation(
        providerDisplayName: String,
        accounts: [ProviderAccount],
        isSurfaceEnabled: Bool,
        hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
    ) -> SubscriptionSwitchPresentation {
        let accessibilityLabel = "\(providerDisplayName) subscription"
        guard accounts.contains(where: hasActiveHandoff) else {
            return SubscriptionSwitchPresentation(
                isEnabled: true,
                helpText: nil,
                accessibilityLabel: accessibilityLabel
            )
        }
        // R10: an open Terminal handoff owns the provider until it resolves; flipping the
        // switch under it would either drop the account it is about to produce or start
        // polling a half-written config home.
        let direction = isSurfaceEnabled ? "off" : "on"
        return SubscriptionSwitchPresentation(
            isEnabled: false,
            helpText: "Finish or stop the sign-in in progress before turning \(providerDisplayName) \(direction)",
            accessibilityLabel: accessibilityLabel
        )
    }

    /// A provider's standing help line under its group, shown whether or not it is fetched.
    /// Only OpenCode has one (KTD21): each home reads one Console workspace.
    static func providerGroupNote(for providerID: ProviderID) -> String? {
        providerID == .opencode ? SettingsCopy.opencodeWorkspaceScope : nil
    }

    static func providerGroupPresentation(
        providerDisplayName: String,
        accounts: [ProviderAccount],
        capacity: Int,
        hasFreeAccountSlot: Bool,
        isSurfaceEnabled: Bool,
        hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
    ) -> ProviderGroupPresentation {
        // Cursor is deliberately single-account (no config-home isolation), so its header
        // carries the switch alone — a "1 of 1" counter and a permanently disabled Add
        // would be noise.
        let multiAccount = capacity > 1
        return ProviderGroupPresentation(
            subscriptionSwitch: subscriptionSwitchPresentation(
                providerDisplayName: providerDisplayName,
                accounts: accounts,
                isSurfaceEnabled: isSurfaceEnabled,
                hasActiveHandoff: hasActiveHandoff
            ),
            isFetching: isSurfaceEnabled,
            showsAccountCounter: multiAccount,
            showsAddAction: multiAccount,
            addAction: addAccountActionState(
                providerDisplayName: providerDisplayName,
                capacity: capacity,
                hasFreeAccountSlot: hasFreeAccountSlot,
                isSurfaceEnabled: isSurfaceEnabled
            )
        )
    }

    /// L11A. Ordering is load-bearing: capacity outranks the subscription switch, because
    /// turning a full provider back on would not free a slot — "Turn Grok on to add an
    /// account" there would send the user through the switch for nothing.
    ///
    /// An open Terminal handoff deliberately does *not* block this. It holds the
    /// subscription switch (R10) because flipping mid-handoff would strand the account the
    /// handoff is about to produce, but starting a second sign-in is legitimate.
    nonisolated static func addAccountActionState(
        providerDisplayName: String,
        capacity: Int,
        hasFreeAccountSlot: Bool,
        isSurfaceEnabled: Bool
    ) -> AddAccountActionState {
        guard hasFreeAccountSlot else {
            // A single-account provider (Cursor) is a design bound, not a tested envelope.
            return .disabled(help: capacity <= 1
                ? "\(providerDisplayName) supports one account"
                : "Tested up to \(capacity) accounts per provider")
        }
        guard isSurfaceEnabled else {
            // PB9: no full stop — the other two tooltips in this very function have none, and
            // a single-sentence tooltip is a label, not prose.
            return .disabled(help: "Turn \(providerDisplayName) on to add an account")
        }
        return .enabled(help: "Sign in another account via the official CLI")
    }

    /// CA-S5 (SET-07, COPY-11) overturns the multi-account plan's R15 (2026-09-19 polling
    /// plan), which showed "3 of 20" on every multi-account header: a count with a
    /// denominator reads as a plan allowance, and 20 is a tested envelope, not a limit. The
    /// counter now appears only within two of the envelope and reads "Tested up to 20" there.
    /// Nil hides it; a single-account provider (Cursor, Copilot) never shows one.
    nonisolated static let accountCounterLeadIn = 2

    nonisolated static func accountCounterText(usedSlots: Int, capacity: Int) -> String? {
        guard capacity > 1, usedSlots >= capacity - accountCounterLeadIn else { return nil }
        return usedSlots >= capacity ? "Tested up to \(capacity)" : "\(usedSlots) of \(capacity)"
    }

    // MARK: CA-S5: the default login's words

    /// CA-S5 (COPY-11): the built-in row's badge. "CLI login" named a mechanism; the row is
    /// the account the provider's CLI in Terminal is signed in to, which CONCEPTS.md and the
    /// code already call the default login.
    nonisolated static let defaultLoginBadge = "Default"
    nonisolated static let defaultLoginSection = "Default login"
    nonisolated static let showDefaultLoginTitle = "Show Default Login"

    nonisolated static func showDefaultLoginHelp(for providerID: ProviderID) -> String {
        "Track the account \(ProviderSignInCopy.cliProductName(for: providerID)) in Terminal is signed in to again"
    }

    /// CA-S9 (COPY-07): what the email-names switch adds beyond its label.
    nonisolated static let emailNamesHelp =
        "Shows on this Mac and a synced iPhone or iPad. Turn it off to get your own names back."

    // MARK: CA-S3: three slots per row

    /// CA-S3 (SET-01, UX-04): the one thing a row's trailing slot holds, at a fixed minimum
    /// width so every row's slot ends on one x. Overturns craft round 2's R2C11, which kept the
    /// status trailing and dropped a second button onto its own line, so the column moved with
    /// the number of buttons.
    enum RowTrailing: Equatable {
        case connected
        /// "Fetching…", "Removing…", beside the row's loading vessel.
        case progress(String)
        /// The stale clock or a remembered row's tag: "Last read 14 min ago".
        case lastRead(String, help: String)
        case waitingForClaudeCode
        case retainedUsage
        case stopWaiting
        case button(RowButton)
        case none
    }

    /// The single native small button a row may carry.
    enum RowButton: Equatable {
        /// The typed recovery's primary (`RecoveryRowActions.primaryLabel`).
        case recovery(String)
        case signIn
        case continueSetup
        /// The bounded wait expired, or the CLI is too old (`SetupRowRecovery.tryAgain`).
        case tryAgainSetup
        case tryAgainFailedSetup
        case tryAgainRemoval

        var label: String {
            switch self {
            case .recovery(let label): label
            case .signIn: ProviderSignInCopy.button
            case .continueSetup: "Continue Setup"
            // CA-S8 (COPY-09): "Try Again" everywhere. Settings said "Retry…" and "Retry"
            // where the popover said "Try Again" for the same act.
            case .tryAgainSetup, .tryAgainFailedSetup, .tryAgainRemoval: SetupRowChip.tryAgain.label
            }
        }
    }

    /// CA-S3: the action that used to be the row's second button. It leads the menu.
    enum RowMenuLead: Equatable {
        case secondaryRecovery(String)
        case tryAgainSetup
        case cancelRemoval

        var label: String {
            switch self {
            case .secondaryRecovery(let label): label
            case .tryAgainSetup: SetupRowChip.tryAgain.label
            case .cancelRemoval: "Cancel Removal"
            }
        }
    }

    /// CA-S3: the identity's second line when the row has something to say. Nil leaves the
    /// account's email there.
    struct RowSecondLine: Equatable {
        enum Tone: Equatable {
            /// R2C5: a lifecycle sentence in the meter-label ink, never the amber ramp.
            case label
            case secondary
            case warning
        }

        let text: String
        let tone: Tone
        var help: String? = nil
        var lineLimit: Int = 1
    }

    struct RowSlots: Equatable {
        let secondLine: RowSecondLine?
        let trailing: RowTrailing
        let menuLead: RowMenuLead?
    }

    struct RowSlotInput {
        var status: AccountsSettingsTile.AccountStatus
        var isRemembered = false
        var rememberedLabel: String? = nil
        /// The provider is off and the status is fetch state (R11).
        var hidesStatus = false
        var capabilityRow: CapabilityRowPresentation = .standard
        var removalState: AccountRemovalState? = nil
        var setupRecovery: SetupRowRecovery = .outcomeRecovery
        var offersStopWaiting = false
        /// False for a remembered row, which is never probed (R12).
        var offersRecovery = true
        var recoveryActions: RecoveryRowActions? = nil
        var setupFailure: String? = nil
        var setupWaitingTitle: String? = nil
        var isDeviceCode = false
        var providerDisplayName: String
        /// `Countdown.staleReadLabel(capturedAt:now:)` for this row's reading.
        var staleLabel: String
        var setupSentence: String? = nil
    }

    /// CA-S3: every row, every provider and every state resolves to the same three slots:
    /// identity (with this second line), one trailing state or button, and the menu.
    nonisolated static func rowSlots(_ input: RowSlotInput) -> RowSlots {
        var lead: RowMenuLead?
        let trailing: RowTrailing
        let button = rowButton(input)
        if input.removalState == .removing {
            trailing = .progress("Removing…")
        } else if input.offersStopWaiting {
            // R13: during a handoff the row's one control is Stop Waiting. A timed-out wait
            // also offers Try Again, which moves into the menu.
            trailing = .stopWaiting
            if input.offersRecovery, input.setupRecovery == .tryAgain { lead = .tryAgainSetup }
        } else if input.removalState == .failed {
            trailing = .button(.tryAgainRemoval)
            lead = .cancelRemoval
        } else if input.isRemembered {
            trailing = input.rememberedLabel.map {
                .lastRead($0, help: rememberedStatusHelp)
            } ?? .none
        } else if input.capabilityRow == .waitingForClaudeCode {
            trailing = .waitingForClaudeCode
        } else if input.capabilityRow == .retainedUsage {
            trailing = .retainedUsage
        } else if let button {
            trailing = .button(button)
            if case .recovery = button, let actions = input.recoveryActions, actions.hasSecondaryAction,
               let label = actions.secondaryLabel {
                lead = .secondaryRecovery(label)
            }
        } else if input.hidesStatus {
            trailing = .none
        } else {
            switch input.status {
            case .connected: trailing = input.setupWaitingTitle == nil ? .connected : .none
            case .fetching: trailing = .progress("Fetching…")
            case .stale: trailing = .lastRead(input.staleLabel, help: Countdown.staleReadHelp)
            default: trailing = .none
            }
        }
        return RowSlots(
            secondLine: rowSecondLine(input, trailing: trailing),
            trailing: trailing,
            menuLead: lead
        )
    }

    private nonisolated static func rowButton(_ input: RowSlotInput) -> RowButton? {
        guard input.offersRecovery, input.capabilityRow == .standard, input.removalState == nil else {
            return nil
        }
        switch input.setupRecovery {
        case .sessionOnly:
            return nil
        case .tryAgain:
            return .tryAgainSetup
        case .outcomeRecovery:
            guard input.status.needsRecovery || input.recoveryActions != nil else { return nil }
            // R2B1: "Continue Setup" resumes the handoff already open.
            if input.status == .blocked { return .continueSetup }
            if let actions = input.recoveryActions { return .recovery(actions.primaryLabel) }
            return input.status == .setupFailed ? .tryAgainFailedSetup : .signIn
        }
    }

    private nonisolated static func rowSecondLine(_ input: RowSlotInput, trailing: RowTrailing) -> RowSecondLine? {
        guard !input.isRemembered else { return nil }
        switch input.removalState {
        case .setupActive: return RowSecondLine(text: "Close setup, then try again", tone: .warning)
        case .failed: return RowSecondLine(text: "Removal failed", tone: .warning)
        case .removing: return nil
        case nil: break
        }
        if input.hidesStatus, !input.status.isSetupState { return nil }
        switch input.status {
        case .waiting:
            return RowSecondLine(
                text: input.setupWaitingTitle
                    ?? (input.isDeviceCode ? "Waiting for device code…" : "Waiting for sign-in…"),
                tone: .secondary
            )
        case .connected:
            return input.setupWaitingTitle.map { RowSecondLine(text: $0, tone: .secondary) }
        case .blocked:
            // PB9: "sign-in", the word every other status here uses for this event.
            return RowSecondLine(text: "Another \(input.providerDisplayName) sign-in is open", tone: .secondary)
        case .setupFailed:
            return RowSecondLine(
                text: input.setupFailure ?? "Sign-in failed",
                tone: .warning,
                help: input.setupFailure,
                lineLimit: 2
            )
        case .setupActive:
            return RowSecondLine(text: "Close setup, then try again", tone: .warning)
        case .needsSignIn:
            guard input.capabilityRow == .standard else { return nil }
            // CA-S3 (UX-04) overturns craft round 2's R2C6, which printed the popover's
            // sentence ("Sign in with the official Claude CLI") beside a button that says
            // "Sign In": one act said twice in one row. The line now names the state and the
            // button names the act; the sentence stays in the tooltip.
            let presentation = input.recoveryActions?.presentation
            // CA-P5: only a sign-in row reads "Not signed in" / "Signed out". A verb-first
            // recovery ("Approve Headroom’s folder") contains its own act, which used to send
            // it down the sign-in branch.
            let signsIn = presentation.map {
                [ProviderSignInCopy.button, ProviderSignInCopy.buttonAgain].contains($0.primaryLabel)
            } ?? true
            let text: String
            if let presentation, !signsIn {
                text = presentation.shortStatus
            } else if presentation?.primaryLabel == ProviderSignInCopy.buttonAgain {
                text = "Signed out"
            } else {
                text = "Not signed in"
            }
            return RowSecondLine(
                text: text,
                tone: .label,
                help: presentation?.rowHelp ?? input.setupSentence
            )
        case .stale:
            // One state or one button: when a button holds the slot, the reading's age moves
            // to the identity's second line instead of being dropped.
            guard case .button = trailing else { return nil }
            return RowSecondLine(text: input.staleLabel, tone: .secondary, help: Countdown.staleReadHelp)
        case .fetching, .removing, .removalFailed:
            return nil
        }
    }

    // MARK: CA-S3: the row's "…" menu

    enum RowMenuItem: Equatable {
        case lead(RowMenuLead)
        case makeMain
        case signOutAndSetUpAgain
        case stopTracking
        case removeAccount(destructive: Bool)
    }

    /// CA-S3: the menu every row ends with, in sections a divider separates. The secondary
    /// recovery action, when there is one, is its first item. Empty means the slot is held
    /// open but draws nothing, so the trailing edge stays put.
    nonisolated static func rowMenuSections(
        lead: RowMenuLead?,
        isBuiltIn: Bool,
        isRemembered: Bool,
        builtInActions: BuiltInRowActions,
        promotion: PromotionState
    ) -> [[RowMenuItem]] {
        if lead == .cancelRemoval { return [[.lead(.cancelRemoval)]] }
        var sections: [[RowMenuItem]] = []
        if let lead { sections.append([.lead(lead)]) }
        if isRemembered {
            // R11: a remembered row's removal only hides it, so it is not destructive.
            sections.append([.removeAccount(destructive: false)])
        } else if isBuiltIn {
            switch (builtInActions, promotion) {
            case (.resetOnly, _):
                sections.append([.signOutAndSetUpAgain])
            case (.resetAndStopTracking, .primary):
                sections += [[.signOutAndSetUpAgain], [.stopTracking]]
            case (.resetAndStopTracking, .available):
                sections += [[.makeMain], [.signOutAndSetUpAgain], [.stopTracking]]
            case (.unavailable, _), (.resetAndStopTracking, .unavailable):
                break
            }
        } else {
            if promotion == .available { sections.append([.makeMain]) }
            sections.append([.removeAccount(destructive: true)])
        }
        return sections
    }

    // MARK: CA-P14: stopping an Add Account removes the row it made

    /// CA-P14: Stop Waiting's "Remove Account", on both surfaces (the rule that offers it is
    /// `UsageStore.stopWaitingRemovesAccount`). The handoff is abandoned first, so the store's
    /// open-handoff guard does not refuse the removal it was asked for.
    static func stopWaitingAndRemove(
        _ account: ProviderAccount,
        from store: UsageStore,
        forceCancel: @MainActor (ProviderAccount) -> Void = SetupSessions.forceCancel(for:)
    ) async -> AccountRemovalResult {
        stopWaiting(for: account, in: store, forceCancel: forceCancel)
        return await store.removeAccount(account.key)
    }

    /// R12: leaving Accounts (pane switch or window close) must not silently discard a
    /// typed rename. Uses the same rule as `commitLabel` so the caller commits exactly the
    /// drafts that would change something, in the list's own order.
    nonisolated static func pendingLabelCommits(
        drafts: [AccountKey: String],
        accounts: [ProviderAccount]
    ) -> [ProviderAccount] {
        accounts.filter { account in
            guard let draft = drafts[account.key] else { return false }
            return pendingRename(draft, for: account) != nil
        }
    }

    /// The same sweep over the display rows (default-login plan U7), so a typed rename of
    /// a remembered row commits to the record store like any other.
    nonisolated static func pendingLabelCommits(
        drafts: [AccountKey: String],
        rows: [DisplayAccount]
    ) -> [DisplayAccount] {
        rows.filter { row in
            guard let draft = drafts[row.key] else { return false }
            return pendingRename(draft, for: row.account) != nil
        }
    }

    enum CapabilityRowPresentation: Equatable {
        case standard
        case waitingForClaudeCode
        case retainedUsage
    }

    nonisolated static func capabilityRowPresentation(
        snapshot: UsageSnapshot,
        capability: CapabilityRecoveryPresentation?
    ) -> CapabilityRowPresentation {
        guard capability != nil else { return .standard }
        return snapshot.windows.isEmpty ? .waitingForClaudeCode : .retainedUsage
    }

    nonisolated static func recoveryRowActions(
        snapshot: UsageSnapshot,
        account: ProviderAccount
    ) -> RecoveryRowActions? {
        guard case .stale(let reason) = snapshot.freshness,
              let presentation = reason.providerSetupOutcome?.recoveryPresentation
        else { return nil }
        return RecoveryRowActions(presentation: presentation, accountLabel: account.label)
    }

    @discardableResult
    static func addAccount(
        for providerID: ProviderID,
        to store: UsageStore,
        openSetup: (ProviderAccount) -> Void
    ) -> ProviderAccount? {
        guard let account = store.addAccount(for: providerID) else { return nil }
        openSetup(account)
        return account
    }

    @discardableResult
    static func commitLabel(
        _ draft: String,
        for account: ProviderAccount,
        in store: UsageStore
    ) -> Bool {
        guard let trimmed = pendingRename(draft, for: account) else { return false }
        store.renameAccount(account.key, to: trimmed)
        return true
    }

    /// KTD8: a rename follows the row's kind. A remembered row's label lives in the record
    /// store, so it never reaches the registry.
    @discardableResult
    static func commitLabel(
        _ draft: String,
        for row: DisplayAccount,
        in store: UsageStore
    ) -> Bool {
        switch row.kind {
        case .engine:
            return commitLabel(draft, for: row.account, in: store)
        case .remembered:
            guard let trimmed = pendingRename(draft, for: row.account) else { return false }
            return store.renameRememberedAccount(row.key, to: trimmed)
        }
    }

    /// The one rule for "this draft renames the account": trimmed, non-empty, and
    /// different from the current label. Shared by the commit path and the
    /// leave-Accounts sweep so the two can never disagree (R12).
    nonisolated static func pendingRename(_ draft: String, for account: ProviderAccount) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != account.label else { return nil }
        return trimmed
    }

    /// Built-in rows route to the non-destructive stop-tracking path — their config
    /// home is the user's own CLI login, which Headroom never deletes. Extras keep the
    /// destructive removal that deletes their Headroom-owned config home.
    static func removeAccount(
        _ account: ProviderAccount,
        from store: UsageStore
    ) async -> AccountRemovalResult {
        account.isBuiltIn
            ? await store.stopTrackingBuiltInAccount(for: account.providerID)
            : await store.removeAccount(account.key)
    }

    // MARK: Remembered rows (default-login plan U8)

    /// The removal dialog's title, by row kind: stop-tracking for the built-in row, removal
    /// for an extra or a remembered row.
    nonisolated static func removalDialogTitle(for row: DisplayAccount) -> String {
        row.account.isBuiltIn && !row.isRemembered ? "Stop tracking this account?" : "Remove this account?"
    }

    /// R11: a remembered row's removal only hides it, and it returns when its account is the
    /// default login again, so the dialog says both, plainly, and says nothing is deleted.
    nonisolated static func removalDialogMessage(for row: DisplayAccount) -> String {
        if row.isRemembered {
            return "It stays hidden until your CLI is signed in to this account again. Nothing is deleted."
        }
        return row.account.isBuiltIn
            ? "Headroom stops showing it. Your CLI stays signed in, and nothing on this Mac is deleted."
            : "Its sign-in on this Mac is deleted with it. Your subscription is untouched."
    }

    /// R11: removing a remembered row deletes nothing, so its confirm button is not
    /// destructive; neither is stop-tracking. Only an extra's removal deletes its sign-in.
    nonisolated static func removalIsDestructive(for row: DisplayAccount) -> Bool {
        !row.account.isBuiltIn && !row.isRemembered
    }

    /// U8 (R7): the status a remembered row prints in Settings, the popover's own tag
    /// ("Last read 2 min ago"). Nil only when nothing records when it was read.
    nonisolated static func rememberedStatus(lastReadAt: Date?, snapshot: UsageSnapshot, now: Date) -> String? {
        Countdown.lastReadLabel(capturedAt: lastReadAt ?? snapshot.capturedAt, now: now)
    }

    /// U8: the status line's tooltip. A remembered row is never read on its own; it goes
    /// live when the CLI is signed in to it again, or as an account added with Add Account.
    nonisolated static let rememberedStatusHelp =
        "Headroom reads this account again when your CLI is signed in to it. To keep it live alongside your current login, add it with Add Account…"

    /// KTD8: removing a remembered row hides it in the record store (R11); it deletes no
    /// config home and writes no registry tombstone. Engine rows keep their two paths.
    static func removeAccount(
        _ row: DisplayAccount,
        from store: UsageStore
    ) async -> AccountRemovalResult {
        switch row.kind {
        case .engine:
            return await removeAccount(row.account, from: store)
        case .remembered:
            return store.removeRememberedAccount(row.key) ? .removed : .notAllowed
        }
    }

    /// Shared Settings/popover action for an abandoned Terminal handoff. The store
    /// cleanup makes a prior `.setupActive` removal refusal immediately retryable.
    static func stopWaiting(
        for account: ProviderAccount,
        in store: UsageStore,
        forceCancel: @MainActor (ProviderAccount) -> Void = SetupSessions.forceCancel(for:)
    ) {
        forceCancel(account)
        store.cancelAccountRemoval(account.key)
    }

    static func builtInRowActions(
        for account: ProviderAccount,
        in store: UsageStore
    ) -> BuiltInRowActions {
        guard account.isBuiltIn,
              store.canResetBuiltInAccount(for: account.providerID)
        else { return .unavailable }
        return store.canStopTrackingBuiltInAccount(for: account.providerID)
            ? .resetAndStopTracking
            : .resetOnly
    }

    // MARK: One account, one row (default-login plan U10)

    /// KTD11: the built-in row the one-row merge hides, if any. Its row shows through the
    /// extra that reads the same account, so its own actions move to the provider header.
    static func mergedBuiltIn(for providerID: ProviderID, in store: UsageStore) -> ProviderAccount? {
        let merged = store.displayProjection(for: providerID).mergeMap.keys
        guard !merged.isEmpty else { return nil }
        return store.accounts(for: providerID).first { $0.isBuiltIn && merged.contains($0.key) }
    }

    /// U10: what the provider header offers for a merged built-in. `.unavailable` when
    /// nothing is merged, so a setup with no merge draws the header as before (R15).
    static func mergedBuiltInActions(for providerID: ProviderID, in store: UsageStore) -> BuiltInRowActions {
        guard let builtIn = mergedBuiltIn(for: providerID, in: store) else { return .unavailable }
        return builtInRowActions(for: builtIn, in: store)
    }

    /// The "Sign out and set up again?" message. For the built-in OpenCode account it is
    /// also the D7 warning, so a reset from Settings asks once, not twice.
    static func resetDialogMessage(for account: ProviderAccount, providerDisplayName: String) -> String {
        if account.providerID == .opencode {
            return BuiltInSignInConfirmation.message(for: .reset)
        }
        return "Signing in again switches the \(providerDisplayName) default login across this Mac, including Terminal sessions. If you only want Headroom to show another login, add it as a separate account and use Make Main."
    }

    @discardableResult
    static func resetBuiltIn(
        _ account: ProviderAccount,
        in store: UsageStore,
        beginReset: @MainActor (ProviderAccount) -> Void = { SetupSessions.resetSetup(for: $0) }
    ) -> Bool {
        guard account.isBuiltIn,
              store.canResetBuiltInAccount(for: account.providerID)
        else { return false }
        beginReset(account)
        return true
    }

    /// The Main badge reads the display primary (KTD8); a remembered row is never main
    /// and never offered Make Main (KTD12).
    static func promotionState(
        for account: ProviderAccount,
        in store: UsageStore
    ) -> PromotionState {
        if store.displayPrimaryKey(for: account.providerID) == account.key { return .primary }
        return store.canPromoteAccount(account.key) ? .available : .unavailable
    }

    static func promotionState(
        for row: DisplayAccount,
        in store: UsageStore
    ) -> PromotionState {
        row.isRemembered ? .unavailable : promotionState(for: row.account, in: store)
    }

    @discardableResult
    static func makeMain(
        _ account: ProviderAccount,
        in store: UsageStore
    ) -> PromotionFeedback? {
        guard store.promoteAccount(account.key) else { return nil }
        return PromotionFeedback(
            accountKey: account.key,
            announcement: "\(account.label) is now Main"
        )
    }

    /// Undo for stop-tracking: resurface the CLI's own login and fetch it right away.
    @discardableResult
    static func resumeTrackingBuiltIn(
        for providerID: ProviderID,
        in store: UsageStore
    ) -> ProviderAccount? {
        guard let account = store.resumeTrackingBuiltInAccount(for: providerID) else { return nil }
        store.refreshAccountNow(account.key)
        return account
    }

    /// Provider capability belongs to the shared executable: the handoff binds to the
    /// selected primary, while Check Again refreshes every account of this provider (R18).
    @discardableResult
    static func performCapabilityRecovery(
        _ action: SetupRecoveryAction,
        for providerID: ProviderID,
        in store: UsageStore,
        perform: (SetupRecoveryAction, ProviderAccount, @escaping () -> Void) -> Void = {
            SetupSessions.performRecovery($0, for: $1, onRetry: $2)
        },
        refresh: ((AccountKey) -> Void)? = nil
    ) -> Bool {
        guard let primary = store.primaryAccount(for: providerID) else { return false }
        perform(action, primary) {
            if let refresh {
                for account in store.accounts(for: providerID) { refresh(account.key) }
            } else {
                store.refreshProviderNow(providerID)
            }
        }
        return true
    }
}
