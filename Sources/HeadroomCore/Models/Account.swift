import Foundation

/// Stable identifier for one signed-in account under a provider. `.primary` is the
/// built-in account bound to the CLI's own default config (`~/.claude`, `~/.codex`) —
/// it always exists, so existing single-account installs upgrade with zero migration.
public struct AccountID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }

    public static let primary = AccountID("primary")

    public var description: String { raw }
}

/// One (provider, account) pair — the unit usage is fetched, keyed, and rendered by
/// once multiple subscriptions per provider exist.
public struct AccountKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let providerID: ProviderID
    public let accountID: AccountID

    public init(providerID: ProviderID, accountID: AccountID) {
        self.providerID = providerID
        self.accountID = accountID
    }

    public var description: String { "\(providerID.raw)/\(accountID.raw)" }
}

/// A configured subscription account. The built-in account reads the CLI's default
/// login; additional accounts get Headroom-owned config homes (`CLAUDE_CONFIG_DIR` /
/// `CODEX_HOME`) that the user signs into once via the official CLI — Headroom never
/// touches credentials itself (same compliance boundary as single-account).
public struct ProviderAccount: Identifiable, Sendable, Codable, Equatable, Hashable {
    public static let builtInDefaultLabel = "Main"

    public let id: AccountID
    public let providerID: ProviderID
    /// User-editable display label ("Personal", "Work"). Hidden in the UI while a
    /// provider has only one account, so single-account installs look unchanged.
    public var label: String
    /// True for the one account per provider bound to the CLI's default config.
    /// Built-in accounts can't be removed — they *are* the user's own CLI login.
    public let isBuiltIn: Bool

    public init(id: AccountID, providerID: ProviderID, label: String, isBuiltIn: Bool = false) {
        self.id = id
        self.providerID = providerID
        self.label = label
        self.isBuiltIn = isBuiltIn
    }

    public var key: AccountKey { AccountKey(providerID: providerID, accountID: id) }

    /// The built-in default account every provider starts with.
    public static func builtIn(for providerID: ProviderID) -> ProviderAccount {
        ProviderAccount(
            id: .primary,
            providerID: providerID,
            label: builtInDefaultLabel,
            isBuiltIn: true
        )
    }

    public static func extraDefaultLabel(ordinal: Int) -> String {
        "Account \(ordinal)"
    }

    public static func isDefaultLabel(_ label: String) -> Bool {
        if label == builtInDefaultLabel { return true }

        let prefix = "Account "
        guard label.hasPrefix(prefix) else { return false }
        let suffix = label.dropFirst(prefix.count).utf8
        guard let first = suffix.first, (49...57).contains(first) else { return false }
        return suffix.allSatisfy { (48...57).contains($0) }
    }
}
