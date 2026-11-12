import Foundation

/// W4 (Oct 2026): a user-requested refresh in
/// progress, which the popover footer turns into a one-line receipt. Moved to Models with
/// the receipt presentation (iPhone parity U6, KTD14.6) so the phone's check-now line and
/// the Mac footer share one vocabulary.
public struct RefreshProgress: Sendable, Equatable {
    public let total: Int
    public let completed: Int
    /// The account that finished most recently; nil until the first one does.
    public let lastLanded: AccountKey?

    public init(total: Int, completed: Int, lastLanded: AccountKey?) {
        self.total = total
        self.completed = completed
        self.lastLanded = lastLanded
    }
}

/// W4: the receipt for a refresh the user started — the Mac popover footer, and the
/// phone's check-now line (KTD14.6) from the Mac's receipt. Pure, so the copy is pinned by
/// tests without a store or a view.
public enum RefreshReceiptPresentation {
    public struct Line: Hashable, Sendable {
        /// The account's numbers came back live. A probe that ended stale is named without
        /// a check: its card already says what went wrong.
        public let checked: Bool
        public let text: String
        public let count: String?

        public init(checked: Bool, text: String, count: String?) {
            self.checked = checked
            self.text = text
            self.count = count
        }
    }

    /// Before anything lands: "Checking 3 accounts…".
    public static func checking(_ accounts: Int) -> Line {
        Line(checked: false, text: "Checking \(accounts) \(accounts == 1 ? "account" : "accounts")…", count: nil)
    }

    /// The last account to land and how far the refresh has come: "Claude Work", "2 of 3".
    public static func landed(title: String, live: Bool, completed: Int, total: Int) -> Line {
        Line(checked: live, text: title, count: "\(completed) of \(total)")
    }

    /// How a receipt names an account: the provider alone while it has one account (labels
    /// are hidden then), "Claude Work" once it has several.
    public static func title(providerName: String, accountTitle: String?, providerAccountCount: Int) -> String {
        guard providerAccountCount > 1, let accountTitle else { return providerName }
        return "\(providerName) \(accountTitle)"
    }

    /// The Mac footer (R4/R5): the recipe owns hand-back (`isResting` is its rest phase), and
    /// recorded outcomes own the checkmark.
    public static func line(run: UserRefreshRun?, isResting: Bool, now: Date,
                            title: (AccountKey) -> String) -> Line? {
        guard !isResting, let run else { return nil }
        let entries = run.entries.filter { $0.value.origin != .setupCheck && !($0.value.requestedAt > now) }
        guard !entries.isEmpty else { return nil }
        let arrived = entries.filter { $0.value.outcome != nil && $0.value.landedAt.map { !($0 > now) } == true }
        let latest = arrived.max {
            if $0.value.landedAt != $1.value.landedAt { return $0.value.landedAt! < $1.value.landedAt! }
            // Pinned fixtures may land together; a dictionary's iteration order is not a receipt order.
            return $0.key.description < $1.key.description
        }
        guard let latest else { return checking(entries.count) }
        return landed(title: title(latest.key), live: latest.value.outcome == .live,
                      completed: arrived.count, total: entries.count)
    }
}
