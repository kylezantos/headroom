import Foundation

/// One limit's reset cycle and the rules already spent in it (KTD4). An array entry,
/// not a dictionary value, for the same reason as `BankedResetAcknowledgement`.
public struct UseItUpLedgerEntry: Codable, Equatable, Sendable {
    public let account: AccountKey
    /// `WindowKind.persistentID` of the limit.
    public let windowID: String
    public let deadline: Date
    /// KTD5 firing keys (`ReminderRule.firingKey`).
    public let firedKeys: [String]

    public init(account: AccountKey, windowID: String, deadline: Date, firedKeys: [String]) {
        self.account = account
        self.windowID = windowID
        self.deadline = deadline
        self.firedKeys = firedKeys
    }

    /// KTD4: a deadline within 30 minutes of the stored one is the same cycle. This
    /// absorbs Codex's `resetsInSeconds` drift and Claude's minute-resolution parse.
    public func isSameCycle(as other: Date) -> Bool {
        abs(other.timeIntervalSince(deadline)) <= UseItUpLedger.cycleTolerance
    }
}

/// Persisted per-limit cycle memory, so each rule fires at most once per limit per
/// reset cycle across relaunches (R12). Written only after a post succeeds (KTD6).
public struct UseItUpLedger: @unchecked Sendable { // UserDefaults is thread-safe
    public static let cycleTolerance: TimeInterval = 30 * 60
    /// KTD4: a cycle a day past its deadline can no longer be current.
    public static let pruneAge: TimeInterval = 24 * 60 * 60
    /// Several limits per account across the tested envelope; pruning by age keeps the
    /// real count far lower, so this only bounds a pathological clock.
    public static let maxEntries = BankedResetAcknowledgements.maxEntries * 8

    private static let storageKey = "useItUpLedger.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func entries() -> [UseItUpLedgerEntry] {
        load().entries
    }

    public func entry(for account: AccountKey, windowID: String) -> UseItUpLedgerEntry? {
        load().entries.first { $0.account == account && $0.windowID == windowID }
    }

    /// Writes `entry` for its limit. A stored entry in the same cycle keeps its fired
    /// keys; a different cycle is replaced. KTD5: keys for rules no longer in
    /// `activeFiringKeys` are dropped, and every entry a day past its deadline is pruned.
    public func record(_ entry: UseItUpLedgerEntry, activeFiringKeys: Set<String>, now: Date) {
        var stored = load()
        let existing = stored.entries.first { $0.account == entry.account && $0.windowID == entry.windowID }
        var keys = entry.firedKeys
        if let existing, existing.isSameCycle(as: entry.deadline) {
            keys = existing.firedKeys + keys.filter { !existing.firedKeys.contains($0) }
        }
        let merged = UseItUpLedgerEntry(
            account: entry.account,
            windowID: entry.windowID,
            deadline: entry.deadline,
            firedKeys: keys.filter(activeFiringKeys.contains)
        )
        stored.entries.removeAll {
            ($0.account == merged.account && $0.windowID == merged.windowID)
                || now.timeIntervalSince($0.deadline) > Self.pruneAge
        }
        stored.entries.append(merged)
        if stored.entries.count > Self.maxEntries {
            stored.entries.removeFirst(stored.entries.count - Self.maxEntries)
        }
        save(stored)
    }

    /// Default-login plan KTD5: replaces `account`'s entries with `entries`, re-keyed to
    /// it, when the account behind a row changes. Entries a day past their deadline are
    /// dropped, as `record` does. The stored format is unchanged.
    public func restore(_ entries: [UseItUpLedgerEntry], for account: AccountKey, now: Date) {
        var stored = load()
        stored.entries.removeAll { $0.account == account }
        stored.entries += entries
            .filter { !(now.timeIntervalSince($0.deadline) > Self.pruneAge) }
            .map { UseItUpLedgerEntry(account: account, windowID: $0.windowID, deadline: $0.deadline, firedKeys: $0.firedKeys) }
        if stored.entries.count > Self.maxEntries {
            stored.entries.removeFirst(stored.entries.count - Self.maxEntries)
        }
        save(stored)
    }

    public func purge(for account: AccountKey) {
        var stored = load()
        let remaining = stored.entries.filter { $0.account != account }
        guard remaining.count != stored.entries.count else { return }
        stored.entries = remaining
        save(stored)
    }

    private struct Stored: Codable {
        var entries: [UseItUpLedgerEntry] = []
    }

    private func load() -> Stored {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return Stored() }
        return stored
    }

    private func save(_ stored: Stored) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
