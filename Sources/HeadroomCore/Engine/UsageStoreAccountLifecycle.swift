import Foundation

@MainActor
extension UsageStore {
    /// Preset failure for a just-added account so its row appears instantly instead of
    /// waiting out a full (possibly 20–30s) probe of an account that isn't signed in yet.
    public nonisolated static let finishSignInMessage = "Finish sign-in to add this account"

    /// Accounts for a provider in display order, with its selected primary first.
    public func accounts(for providerID: ProviderID) -> [ProviderAccount] {
        accountsByProvider[providerID] ?? []
    }

    /// The account compact surfaces (menu bar, widgets) follow for a provider.
    public func primaryAccount(for providerID: ProviderID) -> ProviderAccount? {
        accounts(for: providerID).first
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
        bankedResetAcknowledgements?.purge(for: key)
        notificationCoordinator?.purge(for: key)
        snapshots[key] = .pending(for: key.providerID)
        continuityCache?.remove(for: key)
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
    public func addAccount(for providerID: ProviderID, label: String? = nil) -> ProviderAccount? {
        guard canAddAccount(for: providerID),
              let accountRegistry, let providerFactory,
              let account = accountRegistry.addAccount(
                  for: providerID, capacity: accountCapacity(for: providerID), label: label
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

    public func renameAccount(_ key: AccountKey, to label: String) {
        guard let accountRegistry else { return }
        accountRegistry.renameAccount(key, to: label)
        accountsByProvider[key.providerID] = accountRegistry.accounts(
            for: key.providerID, capacity: accountCapacity(for: key.providerID)
        )
        // R17 / KTD9: titles are resolved on the Mac, so a rename re-exports them.
        exportPhoneSyncSnapshot()
    }

    public func canPromoteAccount(_ key: AccountKey) -> Bool {
        guard providerFactory != nil,
              accountRegistry != nil,
              primaryAccount(for: key.providerID)?.key != key
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
        bankedResetAcknowledgements?.purge(for: key)
        notificationCoordinator?.purge(for: key)
        providers.removeAll { $0.accountKey == key }
        scheduler.unregister(key)
        snapshots.removeValue(forKey: key)
        continuityCache?.remove(for: key)
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
