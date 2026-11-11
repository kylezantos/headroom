import Foundation

@MainActor
extension UsageStore {
    /// Preset failure for a just-added account so its row appears instantly instead of
    /// waiting out a full (possibly 20–30s) probe of an account that isn't signed in yet.
    public nonisolated static let finishSignInMessage = "Finish sign-in to add this account"

    /// The engine list (default-login plan KTD8): the registry accounts with a provider
    /// instance, selected primary first. Merge acceptance, scheduling, setup and the
    /// promote write read membership from it. What a surface lists is `displayAccounts(for:)`.
    public func accounts(for providerID: ProviderID) -> [ProviderAccount] {
        accountsByProvider[providerID] ?? []
    }

    /// The engine list's main account. Surfaces that show "the main account" read
    /// `displayPrimaryKey(for:)`; the two agree until the one-row merge (U10).
    public func primaryAccount(for providerID: ProviderID) -> ProviderAccount? {
        accounts(for: providerID).first
    }

    // MARK: Display projection (default-login plan U7, KTD8)

    /// What every user-visible surface lists for a provider: the engine rows, then the
    /// visible remembered rows in stored order, minus any merged row. Equal to the engine
    /// list for a setup whose default login never changes (R15).
    public func displayProjection(for providerID: ProviderID) -> DisplayAccountsProjection {
        DisplayAccountsResolver.resolve(
            providerID: providerID,
            engine: accounts(for: providerID),
            remembered: rememberedAccountRows[providerID] ?? []
        )
    }

    public func displayAccounts(for providerID: ProviderID) -> [DisplayAccount] {
        displayProjection(for: providerID).rows
    }

    /// The row the menu bar, widgets, the Main badge and the "already main" guard follow.
    /// Never a remembered row (R12).
    public func displayPrimaryKey(for providerID: ProviderID) -> AccountKey? {
        displayProjection(for: providerID).primaryKey
    }

    public func attachSetupCoordinator(_ coordinator: SetupSessionCoordinator?) {
        setupCoordinator = coordinator
    }

    /// An isolated demo/capture owner releases its sources before awaiting scheduler teardown.
    public func waitForAccountProbesToFinish() async {
        await scheduler.waitUntilLanesIdle()
    }

    /// Reject any capture started before this reset boundary and drop retained usage
    /// so the next accepted result cannot merge windows from the previous login.
    public func invalidateUsageForAccountReset(_ key: AccountKey) {
        attachmentGenerations[key, default: 0] &+= 1
        // KTD14 (2026-09-19 sign-in plan): a deliberate sign-out is not an observed
        // change. Clearing the flag at the reset boundary — rather than reading the
        // coordinator's session purpose, which Stop Waiting and a settled failure both
        // erase — makes the exclusion hold however that session ends.
        signOutRecord?.clearLastKnownSignedIn(for: key)
        sessionReliabilityRecord?.endObservation(for: key)
        bankedResetAcknowledgements?.purge(for: key)
        notificationCoordinator?.purge(for: key)
        snapshots[key] = .pending(for: key.providerID)
        continuityCache?.remove(for: key)
        deferringRememberedRowExport { defaultLoginDidClear(key) }
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    /// KTD9 (2026-09-19 sign-in plan): the boundary an external handoff's Terminal exit
    /// draws. It rejects only captures launched before the exit — unlike the reset
    /// boundary it keeps the row's retained usage, because nothing here says the account
    /// changed login.
    public func invalidateUsageForHandoffBoundary(_ key: AccountKey) {
        attachmentGenerations[key, default: 0] &+= 1
    }

    public func canAddAccount(for providerID: ProviderID) -> Bool {
        guard let accountRegistry, providerFactory != nil,
              accounts(for: providerID).count < accountCapacity(for: providerID)
        else { return false }
        return accountRegistry.canAddAccount(for: providerID, capacity: accountCapacity(for: providerID))
    }

    public func accountCapacity(for providerID: ProviderID) -> Int {
        providers.first(where: { $0.id == providerID })?.accountCapacity ?? 1
    }

    @discardableResult
    public func addAccount(
        for providerID: ProviderID,
        label: String? = nil,
        id: AccountID? = nil
    ) -> ProviderAccount? {
        guard canAddAccount(for: providerID),
              let accountRegistry, let providerFactory,
              let account = accountRegistry.addAccount(
                  for: providerID, capacity: accountCapacity(for: providerID),
                  label: AccountRegistry.normalizedLabel(label) ?? defaultLoginLabelForNewAccount(for: providerID),
                  id: id
              )
        else { return nil }
        guard case .success = accountStorage.ensureDirectories(for: account) else {
            accountRegistry.removeAccount(account.key)
            return nil
        }
        let provider = providerFactory(account)
        providers.append(provider)
        scheduler.register(provider)
        accountsByProvider[providerID] = accountRegistry.accounts(for: providerID, capacity: accountCapacity(for: providerID))
        snapshots[account.key] = .stale(
            for: providerID,
            reason: .notLoggedIn(Self.finishSignInMessage)
        )
        // R17: a new account reaches the phone without waiting for a refresh.
        exportPhoneSyncSnapshot()
        return account
    }

    /// Adds a row for each ccswap account not yet tracked (and not removed by the user),
    /// then reads it. Rows read through `ccswap run`, so no second sign-in is needed.
    @discardableResult
    public func adoptCCSwapAccounts(emails: [String]) -> [ProviderAccount] {
        var added: [ProviderAccount] = []
        for email in emails {
            guard let id = CCSwapAccounts.accountID(email: email),
                  !ccswapDismissals.contains(email),
                  !accounts(for: .claude).contains(where: { $0.id == id }),
                  let account = addAccount(for: .claude, label: email, id: id)
            else { continue }
            added.append(account)
            refreshAccountNow(account.key)
        }
        return added
    }

    public func renameAccount(_ key: AccountKey, to label: String) {
        guard let accountRegistry else { return }
        accountRegistry.renameAccount(key, to: label)
        accountsByProvider[key.providerID] = accountRegistry.accounts(
            for: key.providerID, capacity: accountCapacity(for: key.providerID)
        )
        if let renamed = accounts(for: key.providerID).first(where: { $0.key == key }) {
            defaultLoginDidRename(key, to: renamed.label)
        }
        // R17 / KTD9: titles are resolved on the Mac, so a rename re-exports them.
        exportPhoneSyncSnapshot()
    }

    // MARK: Remembered accounts (default-login plan U5)

    /// Accounts the default login left, with their last reading (R6), in stored order.
    /// Not engine rows: they are never probed, never the main account and never fire a
    /// reminder (R12), and they do not count toward add-account capacity (KTD4). A row
    /// yields while another row reads its account (KTD12). Removed rows are left out
    /// unless `includingHidden`.
    public func rememberedAccounts(for providerID: ProviderID, includingHidden: Bool = false) -> [RememberedAccountSummary] {
        let rows = rememberedAccountRows[providerID] ?? []
        return includingHidden ? rows : rows.filter { !$0.isHidden }
    }

    /// R11. `key` is the remembered row's own key (`RememberedAccountSummary.key`). One
    /// record commit and one phone export; false, with nothing written, for no such row
    /// or an empty name.
    @discardableResult
    public func renameRememberedAccount(_ key: AccountKey, to label: String) -> Bool {
        defaultLoginRenameRemembered(key, to: label)
    }

    /// R11: hides the row until its account is the default login again. Its label, last
    /// reading and reminder state are kept for that return. One record commit.
    @discardableResult
    public func removeRememberedAccount(_ key: AccountKey) -> Bool {
        defaultLoginHideRemembered(key)
    }

    /// The "already main" guard reads the display primary; the promote write needs an
    /// engine row, so a remembered row is never offered Make Main (KTD12).
    public func canPromoteAccount(_ key: AccountKey) -> Bool {
        guard providerFactory != nil,
              accountRegistry != nil,
              displayPrimaryKey(for: key.providerID) != key
        else { return false }
        return accounts(for: key.providerID).contains(where: { $0.key == key })
    }

    /// Make this row the provider's primary consumer immediately. The targeted
    /// refresh updates its usage without fanning out into the full account fleet;
    /// current snapshots are exported first so compact surfaces flip synchronously.
    @discardableResult
    public func promoteAccount(_ key: AccountKey) -> Bool {
        guard canPromoteAccount(key),
              let accountRegistry,
              accountRegistry.promote(key)
        else { return false }
        accountsByProvider[key.providerID] = accountRegistry.accounts(
            for: key.providerID, capacity: accountCapacity(for: key.providerID)
        )
        refreshAccountNow(key)
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
        return true
    }

    @discardableResult
    public func removeAccount(_ key: AccountKey) async -> AccountRemovalResult {
        guard let accountRegistry,
              let account = accounts(for: key.providerID).first(where: { $0.key == key }),
              !account.isBuiltIn
        else { return .notAllowed }
        if let blocked = await setupHandoffBlock(for: account) { return blocked }
        removingAccounts.insert(key)
        accountRemovalStates[key] = .removing
        setupCoordinator?.markRemoving(key)
        let removal = await accountStorage.removeDirectories(for: account)
        guard case .success = removal else {
            removingAccounts.remove(key)
            if case .failure(.setupActive) = removal {
                accountRemovalStates[key] = .setupActive
                setupCoordinator?.markRemovalFailed(key)
                return .setupActive
            }
            accountRemovalStates[key] = .failed
            setupCoordinator?.markRemovalFailed(key)
            return .failed
        }
        accountRegistry.removeAccount(key)
        // A removed ccswap row stays removed; discovery would otherwise add it back.
        if let email = CCSwapAccounts.email(for: key.accountID) {
            ccswapDismissals.dismiss(email)
        }
        // KTD14: the account's history goes with its config home.
        signOutRecord?.purgeEvents(for: key)
        detachAccount(key)
        return .removed
    }

    public func isBuiltInTrackingStopped(for providerID: ProviderID) -> Bool {
        accountRegistry?.isBuiltInHidden(for: providerID) ?? false
    }

    public func canStopTrackingBuiltInAccount(for providerID: ProviderID) -> Bool {
        guard providerFactory != nil else { return false }
        return accountRegistry?.canStopTrackingBuiltIn(for: providerID) ?? false
    }

    public func canResetBuiltInAccount(for providerID: ProviderID) -> Bool {
        providerFactory != nil && accounts(for: providerID).contains(where: { $0.isBuiltIn })
    }

    @discardableResult
    public func stopTrackingBuiltInAccount(for providerID: ProviderID) async -> AccountRemovalResult {
        let key = AccountKey(providerID: providerID, accountID: .primary)
        guard canStopTrackingBuiltInAccount(for: providerID),
              let accountRegistry,
              let account = accounts(for: providerID).first(where: { $0.key == key })
        else { return .notAllowed }
        if let blocked = await setupHandoffBlock(for: account) { return blocked }
        guard accountRegistry.stopTrackingBuiltIn(for: providerID) else { return .notAllowed }
        detachAccount(key)
        return .removed
    }

    @discardableResult
    public func resumeTrackingBuiltInAccount(for providerID: ProviderID) -> ProviderAccount? {
        guard let accountRegistry, providerFactory != nil,
              accountRegistry.resumeTrackingBuiltIn(for: providerID),
              let account = accountRegistry.accounts(for: providerID).first(where: { $0.isBuiltIn })
        else { return nil }
        attachBuiltInProvider(account)
        accountsByProvider[providerID] = accountRegistry.accounts(for: providerID, capacity: accountCapacity(for: providerID))
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
        return account
    }

    private func setupHandoffBlock(for account: ProviderAccount) async -> AccountRemovalResult? {
        guard await accountStorage.setupHandoffIsActive(for: account) else { return nil }
        accountRemovalStates[account.key] = .setupActive
        return .setupActive
    }

    func detachAccount(_ key: AccountKey) {
        attachmentGenerations[key, default: 0] &+= 1
        // KTD14: the built-in row reuses `AccountID.primary` across stop and resume, so a
        // detached row's flag must not survive to make the resumed row's first signed-out
        // reading look like a sign-out Headroom observed.
        signOutRecord?.clearLastKnownSignedIn(for: key)
        sessionReliabilityRecord?.endObservation(for: key)
        bankedResetAcknowledgements?.purge(for: key)
        notificationCoordinator?.purge(for: key)
        providers.removeAll { $0.accountKey == key }
        scheduler.unregister(key)
        snapshots.removeValue(forKey: key)
        continuityCache?.remove(for: key)
        deferringRememberedRowExport { defaultLoginDidClear(key, removed: key.accountID != .primary) }
        accountsByProvider[key.providerID] = accountRegistry?.accounts(
            for: key.providerID, capacity: accountCapacity(for: key.providerID)
        ) ?? []
        reinstateBuiltInIfResurfaced(for: key.providerID)
        removingAccounts.remove(key)
        accountRemovalStates.removeValue(forKey: key)
        setupCoordinator?.markRemoved(key)
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    private func attachBuiltInProvider(_ account: ProviderAccount) {
        guard let providerFactory else { return }
        let provider = providerFactory(account)
        providers.append(provider)
        scheduler.register(provider)
        snapshots[account.key] = .pending(for: account.providerID)
        setupCoordinator?.markReinstated(account.key)
    }

    private func reinstateBuiltInIfResurfaced(for providerID: ProviderID) {
        guard let builtIn = accounts(for: providerID).first(where: { $0.isBuiltIn }),
              !providers.contains(where: { $0.accountKey == builtIn.key })
        else { return }
        attachBuiltInProvider(builtIn)
    }

    public func cancelAccountRemoval(_ key: AccountKey) {
        guard accountRemovalStates[key] == .failed || accountRemovalStates[key] == .setupActive else { return }
        accountRemovalStates.removeValue(forKey: key)
        setupCoordinator?.cancelRemoval(key)
    }
}
