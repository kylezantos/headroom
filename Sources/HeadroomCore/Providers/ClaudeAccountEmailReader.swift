import Foundation

/// The email a Claude account is signed in as. Injected so the provider can be tested
/// against fixture JSON instead of a real `.claude.json`.
public protocol ClaudeAccountEmailReading: Sendable {
    /// The account email, or nil when the file is absent, unreadable, or carries no
    /// `oauthAccount.emailAddress`. Never throws: identity is display context, and a
    /// missing email must never downgrade an otherwise good usage capture (KTD7).
    func readAccountEmail() -> String?
}

/// Decodes **only** `oauthAccount.emailAddress` and `oauthAccount.accountUuid` out of
/// `.claude.json`. The decoder declares those two fields, so the rest of that file
/// (project history, session state, tips, MCP config — and every credential) can never
/// be read into Headroom by accident.
public enum ClaudeAccountBlob {
    private struct Root: Decodable {
        struct OAuthAccount: Decodable {
            let emailAddress: String?
            let accountUuid: String?
        }
        let oauthAccount: OAuthAccount?
    }

    public static func email(in data: Data) -> String? {
        AccountEmail.normalized(decode(data)?.oauthAccount?.emailAddress)
    }

    /// The stable upstream account identity — the safe deduplication key (emails can
    /// be reused across logins; the UUID cannot).
    public static func accountUUID(in data: Data) -> String? {
        nonEmpty(decode(data)?.oauthAccount?.accountUuid)
    }

    private static func decode(_ data: Data) -> Root? {
        try? JSONDecoder().decode(Root.self, from: data)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Production reader for the account file the official `claude` CLI writes.
///
/// `.claude.json` sits at the *root* of the CLI's config home — `~/.claude.json` for the
/// built-in account (home root, **not** inside `~/.claude/`), and
/// `<CLAUDE_CONFIG_DIR>/.claude.json` for an extra account, the same directory the probe
/// points the CLI at. Read-only, like every other Claude path here: the official client
/// owns the file, Headroom only looks at one field of it.
public struct ClaudeAccountEmailFileReader: ClaudeAccountEmailReading {
    private let path: URL
    private let readData: @Sendable (URL) throws -> Data

    public init(
        path: URL,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.path = path
        self.readData = readData
    }

    /// `configDirectory` is the account's `CLAUDE_CONFIG_DIR`; nil means the built-in
    /// account, which uses the CLI's own default location.
    public init(
        configDirectory: URL?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.init(
            path: Self.accountFileURL(configDirectory: configDirectory, userHome: userHome),
            readData: readData
        )
    }

    public static func accountFileURL(
        configDirectory: URL?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        (configDirectory ?? userHome).appendingPathComponent(".claude.json")
    }

    /// The reader for one account id, resolved the same way the probe resolves
    /// `CLAUDE_CONFIG_DIR`: `.primary` is the user's own CLI login, anything else is that
    /// account's Headroom-owned config home. Lets `ClaudeProvider` default correctly for
    /// both without the composition root threading a path through.
    public static func forAccount(_ accountID: AccountID) -> ClaudeAccountEmailFileReader {
        ClaudeAccountEmailFileReader(
            configDirectory: accountID == .primary
                ? nil
                : AccountStorage.claudeConfigDirectoryURL(forClaudeAccountID: accountID)
        )
    }

    /// Test seam: the resolved file path, so routing can be asserted without a filesystem.
    var accountFilePath: String { path.path }

    public func readAccountEmail() -> String? {
        guard let data = try? readData(path) else { return nil }
        return ClaudeAccountBlob.email(in: data)
    }

    /// Upstream account identity for duplicate-login detection, same fail-safe contract
    /// as the email: nil when the file is absent, unreadable, or carries no UUID.
    public func readAccountUUID() -> String? {
        guard let data = try? readData(path) else { return nil }
        return ClaudeAccountBlob.accountUUID(in: data)
    }
}

/// Flags Claude accounts whose config homes are signed in to the **same upstream
/// Claude login**. Detection only — Headroom never merges or removes rows on its own
/// (a user may keep two homes on one subscription deliberately); the settings UI
/// badges the duplicate so the user can decide which record to keep. Identity is
/// `oauthAccount.accountUuid`, the stable upstream key — never the email.
public struct ClaudeDuplicateLoginDetector: Sendable {
    private let readAccountUUID: @Sendable (AccountID) -> String?

    public init(
        readAccountUUID: @escaping @Sendable (AccountID) -> String? = {
            ClaudeAccountEmailFileReader.forAccount($0).readAccountUUID()
        }
    ) {
        self.readAccountUUID = readAccountUUID
    }

    /// For each Claude account signed in to the same upstream login as an earlier row,
    /// the earlier row's label ("Same login as Main"). Registry order decides which
    /// row counts as the original. Unreadable identity fails safe to "no claim".
    public func duplicateLabels(for accounts: [ProviderAccount]) -> [AccountKey: String] {
        var firstLabelByUUID: [String: String] = [:]
        var duplicates: [AccountKey: String] = [:]
        for account in accounts where account.providerID == .claude {
            guard let uuid = Self.canonicalIdentity(readAccountUUID(account.id)) else { continue }
            if let original = firstLabelByUUID[uuid] {
                duplicates[account.key] = original
            } else {
                firstLabelByUUID[uuid] = account.label
            }
        }
        return duplicates
    }

    /// Identity has to be UUID-*syntactic*, not merely non-empty: `.claude.json` is a
    /// local plaintext file, so a hand-edited or truncated `accountUuid` could otherwise
    /// make two unrelated homes match and wear a false "Same login as X" badge. Anything
    /// that isn't a UUID is treated as absent — the same fail-safe as an unreadable file.
    private static func canonicalIdentity(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: trimmed)
        else { return nil }
        return uuid.uuidString.lowercased()
    }
}
