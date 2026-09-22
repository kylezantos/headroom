import Foundation

/// One account's last announced banked-reset count. An array, not a dictionary:
/// a struct-keyed dictionary encodes as a flat alternating list, and a later
/// `CodingKeyRepresentable` conformance on `AccountKey` would orphan every record (KTD6).
public struct BankedResetAcknowledgement: Codable, Equatable, Sendable {
    public let account: AccountKey
    public let count: Int

    public init(account: AccountKey, count: Int) {
        self.account = account
        self.count = count
    }
}

/// Per-account memory of the banked-reset count Headroom has already announced.
/// A raise is claimed from the card; a drop is recorded here or from the store
/// so a credit redeemed while the popover was closed still announces the next grant.
public struct BankedResetAcknowledgements: @unchecked Sendable { // UserDefaults is thread-safe
    /// One entry per account, sized past the `multi-20` envelope (20 per provider
    /// across Claude, Codex, and Grok). `SignOutRecord.maxEvents` is too small.
    public static let maxEntries = AccountRegistry.testedEnvelope * 3 + 1

    private static let storageKey = "bankedResetAcknowledgements.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func acknowledgedCount(for key: AccountKey) -> Int? {
        load().entries.first { $0.account == key }?.count
    }

    /// Writes `currentCount` when it differs from the stored value. Returns true
    /// only when the count rose (a missing record reads as 0). Nil is not reported
    /// and changes nothing (R2).
    @discardableResult
    public func claimReveal(for key: AccountKey, currentCount: Int?) -> Bool {
        guard let currentCount else { return false }
        var stored = load()
        let previous = stored.entries.first { $0.account == key }?.count ?? 0
        if stored.entries.first(where: { $0.account == key })?.count != currentCount {
            stored.upsert(BankedResetAcknowledgement(account: key, count: currentCount))
            save(stored)
        }
        return currentCount > previous
    }

    /// Shrinks a stored count. Never raises, never claims, and does nothing when
    /// the count is nil or there is no stored value to lower.
    public func lower(for key: AccountKey, currentCount: Int?) {
        guard let currentCount else { return }
        var stored = load()
        guard let previous = stored.entries.first(where: { $0.account == key })?.count,
              currentCount < previous
        else { return }
        stored.upsert(BankedResetAcknowledgement(account: key, count: currentCount))
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
        var entries: [BankedResetAcknowledgement] = []

        mutating func upsert(_ entry: BankedResetAcknowledgement) {
            entries.removeAll { $0.account == entry.account }
            entries.append(entry)
            if entries.count > BankedResetAcknowledgements.maxEntries {
                entries.removeFirst(entries.count - BankedResetAcknowledgements.maxEntries)
            }
        }
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
