import Foundation

/// A rise worth announcing (R15): the account now banks `count`, up from `previousCount`.
public struct BankedResetProposal: Sendable, Equatable {
    public let account: AccountKey
    public let count: Int
    public let previousCount: Int

    public init(account: AccountKey, count: Int, previousCount: Int) {
        self.account = account
        self.count = count
        self.previousCount = previousCount
    }
}

/// What one fresh Codex poll means for the banked-reset notice.
public enum BankedResetNotificationDecision: Sendable, Equatable {
    /// Not a fresh live Codex count, or the count is unchanged.
    case ignore
    /// Write now, post nothing: a first-seen count, a drop, or a rise while the switch is
    /// off (AE6: turning the switch on must not replay a rise it was off for).
    case record(count: Int)
    /// Post, then record `proposal.count` only if the post succeeds (KTD6).
    case notify(BankedResetProposal)
}

/// One account's last live banked-reset count, as seen by the notice.
public struct BankedResetNotificationBaselineEntry: Codable, Equatable, Sendable {
    public let account: AccountKey
    public let count: Int

    public init(account: AccountKey, count: Int) {
        self.account = account
        self.count = count
    }
}

/// KTD7: the notice's own per-account baseline. `BankedResetAcknowledgements` reads a
/// missing record as zero and belongs to the popover capsule; here a missing record
/// means "seed silently", so the first count Headroom ever sees never fires. Purged at
/// the same lifecycle sites as the acknowledgements.
public struct BankedResetNotificationBaseline: @unchecked Sendable { // UserDefaults is thread-safe
    public static let maxEntries = BankedResetAcknowledgements.maxEntries

    private static let storageKey = "bankedResetNotificationBaseline.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func baselineCount(for key: AccountKey) -> Int? {
        load().entries.first { $0.account == key }?.count
    }

    /// Pure read: decides against the stored baseline without writing. The caller applies
    /// `.record` at once and a `.notify` count after a successful post.
    public func decide(snapshot: UsageSnapshot, account: AccountKey, isEnabled: Bool) -> BankedResetNotificationDecision {
        Self.decide(snapshot: snapshot, account: account, isEnabled: isEnabled, baseline: baselineCount(for: account))
    }

    /// R15: only a fresh live Codex poll that reports a count moves anything. A failed
    /// poll's retained count and an unreported (nil) count change nothing.
    public static func decide(
        snapshot: UsageSnapshot,
        account: AccountKey,
        isEnabled: Bool,
        baseline: Int?
    ) -> BankedResetNotificationDecision {
        guard snapshot.providerID == .codex,
              snapshot.freshness == .live,
              let count = snapshot.bankedResets
        else { return .ignore }
        guard let baseline else { return .record(count: count) }
        if count == baseline { return .ignore }
        guard count > baseline, isEnabled else { return .record(count: count) }
        return .notify(BankedResetProposal(account: account, count: count, previousCount: baseline))
    }

    public func record(count: Int, for key: AccountKey) {
        var stored = load()
        guard stored.entries.first(where: { $0.account == key })?.count != count else { return }
        stored.entries.removeAll { $0.account == key }
        stored.entries.append(BankedResetNotificationBaselineEntry(account: key, count: count))
        if stored.entries.count > Self.maxEntries {
            stored.entries.removeFirst(stored.entries.count - Self.maxEntries)
        }
        save(stored)
    }

    public func purge(for key: AccountKey) {
        var stored = load()
        let remaining = stored.entries.filter { $0.account != key }
        guard remaining.count != stored.entries.count else { return }
        stored.entries = remaining
        save(stored)
    }

    private struct Stored: Codable {
        var entries: [BankedResetNotificationBaselineEntry] = []
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
