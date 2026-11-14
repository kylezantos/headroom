import Foundation

@MainActor
extension UsageStore {
    /// Preset failure for a just-added account so its row appears instantly instead of
    /// waiting out a full (possibly 20–30s) probe of an account that isn't signed in yet.
    public nonisolated static let finishSignInMessage = "Finish sign-in to add this account"

    /// CA-P14 (UX-02): whether Stop Waiting on this row offers to remove the account, the one
    /// rule the popover and Settings both read. Only an added account that has never finished
    /// a sign-in: the row an abandoned Add Account leaves behind, with no reading, no email and
    /// a never-signed-in state (the add-account preset included). The built-in row, a
    /// remembered row and any account that has read before keep today's dialog. A `.pending`
    /// snapshot is no evidence either way (a restored extra is pending until its first probe),
    /// so it keeps today's dialog too.
    ///
    /// CA-P14 review fix: the snapshot forgets. A signed-out extra whose windows aged out, or
    /// that was relaunched (a permanent failure drops its continuity record), looks exactly
    /// like an abandoned Add Account, and confirming would delete a working account's config
    /// home. So the snapshot is necessary but not enough: `hasReadingOnRecord` is the store's
    /// durable history, and anything it cannot rule out keeps today's dialog.
    public nonisolated static func stopWaitingRemovesAccount(
        _ account: ProviderAccount,
        isRemembered: Bool,
        snapshot: UsageSnapshot,
        hasReadingOnRecord: Bool
    ) -> Bool {
        !account.isBuiltIn
            && !isRemembered
            && !hasReadingOnRecord
            && snapshot.windows.isEmpty
            && snapshot.capturedAt == nil
            && (snapshot.accountEmail ?? "").isEmpty
            && LaneSchedule.isNeverSignedIn(snapshot.freshness)
    }

    /// The store's reading of the rule for an engine row, from its own snapshot and records.
    public func stopWaitingRemovesAccount(_ account: ProviderAccount) -> Bool {
        Self.stopWaitingRemovesAccount(
            account,
            isRemembered: false,
            snapshot: snapshot(for: account.key),
            hasReadingOnRecord: hasReadingOnRecord(account.key)
        )
    }

    /// CA-P14 review fix: true unless the store can show this account never produced a
    /// reading. The evidence is the default-login slot record (`defaultLoginRecords.v1`), which
    /// survives sign-out and relaunch: every live reading with a readable or absent identity
    /// writes one (`DefaultLoginTransition.apply`), and only removing the account deletes it.
    /// That holds only for providers whose readings always carry an identity outcome, so any
    /// other provider (OpenCode reports none yet), a store without records, or a launch-time
    /// continuity record all count as "may have read". No new persisted field (AGENTS.md).
    public func hasReadingOnRecord(_ key: AccountKey) -> Bool {
        guard Self.providersRecordingEveryReading.contains(key.providerID),
              let state = defaultLoginState
        else { return true }
        if launchContinuity[key] != nil { return true }
        guard let slot = state.slot(for: key) else { return false }
        return slot.binding != nil || slot.lastAcceptedCapturedAt != nil || slot.parked != nil || slot.phase != .attached
    }

    /// The multi-account providers whose every live reading carries an identity outcome (the
    /// default-login plan's identity table), so a missing slot record means no reading.
    nonisolated static let providersRecordingEveryReading: Set<ProviderID> = [.claude, .codex, .grok]

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
            remembered: rememberedAccountRows[providerID] ?? [],
            mergeMap: displayMergeMaps[providerID] ?? [:]
        )
    }

    // MARK: One account, one row (default-login plan U10, KTD11)

    /// True for an engine row the one-row merge hides: a built-in whose account an extra
    /// row reads. It is still probed; it never reminds and never shows (KTD11).
    func isMergedAway(_ key: AccountKey) -> Bool {
        displayMergeMaps[key.providerID]?[key] != nil
    }

    /// Settles the one-row merge for a provider from its current gates. Called in the same
    /// turn as every gate change: a merged reading, a setup state, a removal, a reset, a
    /// detach or a resume. Returns whether the map changed. With `exports`, a change
    /// reaches the widgets and the phone once each; callers that export anyway pass false.
    @discardableResult
    func refreshDisplayMerge(for providerID: ProviderID, exports: Bool) -> Bool {
        let map = computeDisplayMerge(for: providerID)
        let previous = displayMergeMaps[providerID] ?? [:]
        guard map != previous else { return false }
        for (hidden, shown) in previous where map[hidden] != shown {
            handOverMergedReminders(hidden: hidden, shown: shown, entering: false)
        }
        // Before `merge` evaluates the shown row in this turn (KTD11).
        for (hidden, shown) in map where previous[hidden] != shown {
            handOverMergedReminders(hidden: hidden, shown: shown, entering: true)
        }
        if map.isEmpty {
            displayMergeMaps.removeValue(forKey: providerID)
        } else {
            displayMergeMaps[providerID] = map
        }
        if exports {
            exportWidgetSnapshot()
            exportPhoneSyncSnapshot()
        }
        return true
    }

    /// KTD11: while merged only the shown row reminds and acknowledges banked resets, so a
    /// hidden built-in that comes back still bound to the same account takes the shown
    /// row's state first; its next live reading then posts nothing already posted. Runs
    /// before any purge of the shown row (a removal settles the merge before it purges).
    /// A built-in that left the engine list, was reset, or now reads another account
    /// takes nothing: the state belongs to the shown row's account, not to the row.
    ///
    /// `entering` is the other direction: the built-in reminded while the rows were
    /// separate, so the shown row takes the built-in's state as the merge begins. Neither
    /// row's banked counts are then known to be the newer, so the shown row's counts only
    /// rise (a higher one of its own is what it last announced); a real drop is lowered by
    /// its next live reading, as `lower` and the baseline's silent drop record already do.
    private func handOverMergedReminders(hidden: AccountKey, shown: AccountKey, entering: Bool) {
        guard accounts(for: hidden.providerID).contains(where: { $0.key == hidden }),
              let state = defaultLoginState,
              let hiddenIdentity = knownIdentity(state.slot(for: hidden)),
              let shownIdentity = state.slot(for: shown)?.binding,
              hiddenIdentity == shownIdentity
        else { return }
        let (source, target) = entering ? (hidden, shown) : (shown, hidden)
        notificationCoordinator?.handOver(from: source, to: target, now: now(), raisesBankedBaselineOnly: entering)
        guard let acknowledgements = bankedResetAcknowledgements,
              let acknowledged = acknowledgements.acknowledgedCount(for: source)
        else { return }
        if entering, let stored = acknowledgements.acknowledgedCount(for: target), !(acknowledged > stored) { return }
        acknowledgements.restore(count: acknowledged, for: target)
    }

    /// The gate inputs, read only once the built-in holds a strong Known identity: for a
    /// setup with no merge that is one slot lookup per provider (R15).
    private func computeDisplayMerge(for providerID: ProviderID) -> [AccountKey: AccountKey] {
        guard let state = defaultLoginState else { return [:] }
        let engine = accounts(for: providerID)
        guard let builtIn = engine.first(where: \.isBuiltIn),
              let identity = knownIdentity(state.slot(for: builtIn.key)),
              identity.strength == .strong
        else { return [:] }
        return DisplayMergePlanner.mergeMap(engine.map { account in
            DisplayMergeInput(
                key: account.key,
                isBuiltIn: account.isBuiltIn,
                identity: account.key == builtIn.key ? identity : knownIdentity(state.slot(for: account.key)),
                freshness: snapshots[account.key]?.freshness,
                isInSetup: isInSetupForDisplayMerge(account.key)
            )
        })
    }

    /// A slot's identity is Known while readings name its bound account (phase attached).
    private func knownIdentity(_ slot: SlotRecord?) -> AccountIdentity? {
        guard let slot, slot.phase == .attached else { return nil }
        return slot.binding
    }

    private func isInSetupForDisplayMerge(_ key: AccountKey) -> Bool {
        removingAccounts.contains(key) || setupCoordinator?.state(for: key).holdsDisplayMerge == true
    }

    /// KTD11: a setup state began or ended on some row; the merge follows in the same turn.
    func setupStatesDidChange(_ providerIDs: Set<ProviderID>) {
        for id in registeredProviderOrder where providerIDs.contains(id) {
            refreshDisplayMerge(for: id, exports: true)
        }
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
        if setupCoordinator !== coordinator { setupCoordinator?.onStatesChange = nil }
        setupCoordinator = coordinator
        // U10: setup states are a merge gate (KTD11), so the store hears every change.
        coordinator?.onStatesChange = { [weak self] providerIDs in
            self?.setupStatesDidChange(providerIDs)
        }
        setupStatesDidChange(Set(registeredProviderOrder))
    }

    /// An isolated demo/capture owner releases its sources before awaiting scheduler teardown.
    public func waitForAccountProbesToFinish() async {
        await scheduler.waitUntilLanesIdle()
    }

    /// Reject any capture started before this reset boundary and drop retained usage
    /// so the next accepted result cannot merge windows from the previous login.
    public func invalidateUsageForAccountReset(_ key: AccountKey) {
        attachmentGenerations[key, default: 0] &+= 1
        // KTD8 (OpenCode plan): the next read after the reset must not join one in flight.
        providers.first { $0.accountKey == key }?.invalidateInFlightUsage()
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
        // U10: the reset clears the row's binding, so a merged built-in shows again here.
        refreshDisplayMerge(for: key.providerID, exports: false)
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    /// KTD9 (2026-09-19 sign-in plan): the boundary an external handoff's Terminal exit
    /// draws. It rejects only captures launched before the exit — unlike the reset
    /// boundary it keeps the row's retained usage, because nothing here says the account
    /// changed login.
    public func invalidateUsageForHandoffBoundary(_ key: AccountKey) {
        attachmentGenerations[key, default: 0] &+= 1
        // KTD8 (OpenCode plan): the check after the exit must start a fresh read, not join
        // one that began before it and whose result the generation bump already rejects.
        providers.first { $0.accountKey == key }?.invalidateInFlightUsage()
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
                  for: providerID, capacity: accountCapacity(for: providerID),
                  label: AccountRegistry.normalizedLabel(label) ?? defaultLoginLabelForNewAccount(for: providerID)
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
        // U10 (KTD11): a row being removed holds no merge, so a built-in merged into it
        // shows, with its own reading, before the row goes; no frame shows neither.
        refreshDisplayMerge(for: key.providerID, exports: true)
        setupCoordinator?.markRemoving(key)
        let removal = await accountStorage.removeDirectories(for: account)
        guard case .success = removal else {
            removingAccounts.remove(key)
            refreshDisplayMerge(for: key.providerID, exports: true)
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
        refreshDisplayMerge(for: providerID, exports: false)
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
        // KTD8 (OpenCode plan): a capture still running for the removed row is never joined.
        providers.first { $0.accountKey == key }?.invalidateInFlightUsage()
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
        // U10: the detached row leaves the merge in the same turn; the exports follow.
        refreshDisplayMerge(for: key.providerID, exports: false)
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
