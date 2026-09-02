import Foundation

/// Persisted catalog of configured subscription accounts (multi-account, Jul 2026).
/// UserDefaults-backed like `Preferences` — account metadata is non-secret (labels and
/// IDs only; credentials stay in each CLI's own config home, KTD4).
///
/// Invariants the registry maintains:
/// - Every provider has its built-in `.primary` account — unless the user stopped
///   tracking it while extras exist (persisted tombstone, Aug 2026). The user's
///   persisted primary choice is listed first when it is visible. A provider
///   never ends up with zero rows: the tombstone only takes effect alongside at least
///   one extra, and removing the last extra clears it.
/// - At most `maxPerProvider` accounts per provider (UI affordances are designed to 5).
///   A hidden built-in keeps its slot so resuming can never overflow the cap.
/// - Built-in accounts can be renamed and stop-tracked but never deleted — their config
///   home is the user's own CLI login, which Headroom must never touch.
public struct AccountRegistry: @unchecked Sendable { // UserDefaults is thread-safe
    public static let maxPerProvider = 5

    private let defaults: UserDefaults
    private static let storageKey = "providerAccounts.v1"
    private static let hiddenBuiltInsKey = "hiddenBuiltInAccounts.v1"
    private static let primaryAccountsKey = "primaryAccounts.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Accounts for one provider, with the selected primary first and the remaining
    /// rows in canonical built-in/creation order. The built-in account is synthesized
    /// when nothing is stored yet, so first launch after upgrade needs no migration.
    public func accounts(for providerID: ProviderID) -> [ProviderAccount] {
        let stored = load().filter { $0.providerID == providerID }
        // Treat persisted metadata as untrusted input: older builds, manual defaults
        // edits, or a torn write must not create duplicate rows or multiple built-ins.
        // Rebuild the provider slice in its canonical order while preserving the
        // stored creation order of valid extras.
        let persistedBuiltIn = stored.first { $0.isBuiltIn || $0.id == .primary }
        let builtIn = persistedBuiltIn.map {
            ProviderAccount(id: .primary, providerID: providerID, label: $0.label, isBuiltIn: true)
        } ?? .builtIn(for: providerID)
        var seen: Set<AccountID> = [.primary]
        let extras = stored.compactMap { account -> ProviderAccount? in
            guard !account.isBuiltIn, account.id != .primary,
                  seen.insert(account.id).inserted
            else { return nil }
            return account
        }
        // The tombstone hides the built-in row only while an extra exists — a torn
        // write or manual defaults edit can never leave a provider with zero rows.
        let hidden = hiddenBuiltIns()
        if hidden.contains(providerID) {
            if extras.isEmpty {
                // Orphaned tombstone (e.g. a crash between removeAccount's catalog
                // and tombstone writes): self-heal by clearing it now, so a future
                // addAccount can't silently re-hide a built-in the user never
                // stopped tracking. Persisting the subtraction happens only in this
                // torn state — the ordinary read path stays write-free.
                saveHiddenBuiltIns(hidden.subtracting([providerID]))
            } else {
                return applyingPrimarySelection(
                    to: Array(extras.prefix(Self.maxPerProvider - 1)),
                    for: providerID
                )
            }
        }
        return applyingPrimarySelection(
            to: Array(([builtIn] + extras).prefix(Self.maxPerProvider)),
            for: providerID
        )
    }

    public func canAddAccount(for providerID: ProviderID) -> Bool {
        countIncludingHidden(accounts(for: providerID), for: providerID) < Self.maxPerProvider
    }

    /// Create and persist a new account with a fresh ID and a default label
    /// ("Account 2", "Account 3", …). Nil once the provider is at the cap.
    @discardableResult
    public func addAccount(for providerID: ProviderID, label: String? = nil) -> ProviderAccount? {
        let visible = accounts(for: providerID)
        guard countIncludingHidden(visible, for: providerID) < Self.maxPerProvider else { return nil }
        let account = ProviderAccount(
            id: AccountID(UUID().uuidString.lowercased()),
            providerID: providerID,
            label: normalizedLabel(label) ?? defaultLabel(existing: visible)
        )
        save(allWithSeeds(for: providerID) + [account])
        return account
    }

    // MARK: - Built-in tracking (stop/resume)

    /// True while the provider's built-in row is tombstoned (hidden from `accounts(for:)`).
    public func isBuiltInHidden(for providerID: ProviderID) -> Bool {
        hiddenBuiltIns().contains(providerID)
    }

    /// Stop-tracking needs a surviving row: refused while the built-in is the only account.
    public func canStopTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        !isBuiltInHidden(for: providerID)
            && accounts(for: providerID).contains { !$0.isBuiltIn }
    }

    /// Hide the built-in account from the tracked list without touching its registry
    /// record, label, or (crucially) anything on disk — the CLI login stays untouched.
    @discardableResult
    public func stopTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        guard canStopTrackingBuiltIn(for: providerID) else { return false }
        saveHiddenBuiltIns(hiddenBuiltIns().union([providerID]))
        return true
    }

    /// Clear the tombstone; the built-in resurfaces with its persisted label while
    /// the provider's retained primary selection continues to determine row order.
    @discardableResult
    public func resumeTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        guard isBuiltInHidden(for: providerID) else { return false }
        saveHiddenBuiltIns(hiddenBuiltIns().subtracting([providerID]))
        return true
    }

    public func renameAccount(_ key: AccountKey, to label: String) {
        guard let normalized = normalizedLabel(label) else { return }
        var all = allWithSeeds(for: key.providerID)
        guard let index = all.firstIndex(where: { $0.key == key }) else { return }
        all[index].label = normalized
        save(all)
    }

    /// Persist the visible account that compact surfaces should follow. The pointer
    /// is deliberately retained when its row is later hidden or removed; reads fall
    /// back without writing and restore the choice if that same row resurfaces.
    @discardableResult
    public func promote(_ key: AccountKey) -> Bool {
        guard accounts(for: key.providerID).contains(where: { $0.key == key }) else { return false }
        var primary = primaryAccounts()
        primary[key.providerID] = key.accountID
        saveJSON(primary, key: Self.primaryAccountsKey)
        return true
    }

    /// Replace the stored catalog wholesale. Fixture/test seeding only — production
    /// mutations go through `addAccount`/`renameAccount`/`removeAccount`, which keep
    /// the invariants.
    public func seed(_ accounts: [ProviderAccount]) {
        save(accounts)
    }

    /// Remove a non-built-in account's registry entry. The caller owns removing its
    /// on-disk config home (`AccountStorage`) and any in-memory provider/snapshot.
    public func removeAccount(_ key: AccountKey) {
        let all = load()
        guard let target = all.first(where: { $0.key == key }), !target.isBuiltIn else { return }
        save(all.filter { $0.key != key })
        // Removing the last extra makes a tombstoned built-in the only possible row
        // again. Clear the tombstone so it resurfaces now — and so a future extra
        // doesn't silently re-hide it.
        if !accounts(for: key.providerID).contains(where: { !$0.isBuiltIn }) {
            saveHiddenBuiltIns(hiddenBuiltIns().subtracting([key.providerID]))
        }
    }

    // MARK: - Storage

    private func load() -> [ProviderAccount] {
        loadJSON([ProviderAccount].self, key: Self.storageKey) ?? []
    }

    private func save(_ accounts: [ProviderAccount]) {
        saveJSON(accounts, key: Self.storageKey)
    }

    private func hiddenBuiltIns() -> Set<ProviderID> {
        loadJSON(Set<ProviderID>.self, key: Self.hiddenBuiltInsKey) ?? []
    }

    private func saveHiddenBuiltIns(_ ids: Set<ProviderID>) {
        saveJSON(ids, key: Self.hiddenBuiltInsKey)
    }

    private func primaryAccounts() -> [ProviderID: AccountID] {
        loadJSON([ProviderID: AccountID].self, key: Self.primaryAccountsKey) ?? [:]
    }

    private func applyingPrimarySelection(
        to accounts: [ProviderAccount],
        for providerID: ProviderID
    ) -> [ProviderAccount] {
        guard let selectedID = primaryAccounts()[providerID],
              let selectedIndex = accounts.firstIndex(where: { $0.id == selectedID }),
              selectedIndex != accounts.startIndex
        else { return accounts }
        var reordered = accounts
        reordered.insert(reordered.remove(at: selectedIndex), at: 0)
        return reordered
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// Row count with a hidden built-in still occupying its slot — the cap gate, so
    /// resuming a tombstoned built-in can never push a provider past `maxPerProvider`.
    private func countIncludingHidden(_ visible: [ProviderAccount], for providerID: ProviderID) -> Int {
        let hiddenSlot = isBuiltInHidden(for: providerID)
            && !visible.contains(where: { $0.isBuiltIn })
        return visible.count + (hiddenSlot ? 1 : 0)
    }

    /// The full stored list, with the given provider's built-in seed materialized so a
    /// first mutation doesn't drop the implicit account.
    private func allWithSeeds(for providerID: ProviderID) -> [ProviderAccount] {
        var all = load()
        if !all.contains(where: { $0.providerID == providerID && $0.isBuiltIn }) {
            all.append(.builtIn(for: providerID))
        }
        return all
    }

    private func normalizedLabel(_ label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(40))
    }

    private func defaultLabel(existing: [ProviderAccount]) -> String {
        let used = Set(existing.map(\.label))
        var n = existing.count + 1
        while used.contains(ProviderAccount.extraDefaultLabel(ordinal: n)) { n += 1 }
        return ProviderAccount.extraDefaultLabel(ordinal: n)
    }
}
