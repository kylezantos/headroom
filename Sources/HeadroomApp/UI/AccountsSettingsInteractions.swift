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
            return .refused("Close setup, then retry")
        default:
            return .enabled
        }
    }
}

func capabilityRecoveryPresentation(
    state: ProviderCapabilityState?,
    hasActiveSetupSession: Bool
) -> CapabilityRecoveryPresentation? {
    guard let recovery = state?.recoveryPresentation else { return nil }
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
        var usesSecondLine: Bool {
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

    /// R11: "off" means "not fetched", never "unmanageable". Fetch-derived chrome (status
    /// text, fetch-recovery buttons, the provider capability banner) disappears and the
    /// rows dim, while Add Account, sign-in, rename, removal, stop-tracking and "Show CLI
    /// Account" stay live — Grok and Cursor ship off, so a first account must be reachable
    /// before the switch is ever turned on.
    struct ProviderGroupPresentation: Equatable {
        let subscriptionSwitch: SubscriptionSwitchPresentation
        let isFetching: Bool
        let showsAccountCounter: Bool
        let showsAddAction: Bool

        var dimsAccountRows: Bool { !isFetching }
        var hidesAccountStatus: Bool { !isFetching }
        var hidesFetchRecovery: Bool { !isFetching }
        var hidesCapabilityBanner: Bool { !isFetching }
        var offHelpText: String? {
            isFetching ? nil : "Not fetched while this provider is off."
        }
        /// Always true — stated as a value so R11's promise is asserted, not assumed.
        var allowsAccountManagement: Bool { true }
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

    static func providerGroupPresentation(
        providerDisplayName: String,
        accounts: [ProviderAccount],
        capacity: Int,
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
            showsAddAction: multiAccount
        )
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

    @discardableResult
    static func resetBuiltIn(
        _ account: ProviderAccount,
        in store: UsageStore,
        beginReset: @MainActor (ProviderAccount) -> Void = SetupSessions.resetSetup(for:)
    ) -> Bool {
        guard account.isBuiltIn,
              store.canResetBuiltInAccount(for: account.providerID)
        else { return false }
        beginReset(account)
        return true
    }

    static func promotionState(
        for account: ProviderAccount,
        in store: UsageStore
    ) -> PromotionState {
        if store.primaryAccount(for: account.providerID)?.key == account.key { return .primary }
        return store.canPromoteAccount(account.key) ? .available : .unavailable
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

    /// Provider capability belongs to the shared executable, so the notice always binds
    /// its recovery to the selected primary account. Check Again's callback consequently
    /// refreshes one account after forced discovery instead of sweeping every configured login.
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
            (refresh ?? store.refreshAccountNow)(primary.key)
        }
        return true
    }
}
