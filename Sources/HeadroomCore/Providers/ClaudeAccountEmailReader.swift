import Foundation

/// The email a Claude account is signed in as. Injected so the provider can be tested
/// against fixture JSON instead of a real `.claude.json`.
public protocol ClaudeAccountEmailReading: Sendable {
    /// The account email, or nil when the file is absent, unreadable, or carries no
    /// `oauthAccount.emailAddress`. Never throws: identity is display context, and a
    /// missing email must never downgrade an otherwise good usage capture (KTD7).
    func readAccountEmail() -> String?
    /// The account file as identity evidence (default-login plan, KTD1/KTD2), with the
    /// email from the same read. A missing file, or one with no `oauthAccount` block
    /// (signed out, gate V1), is `.absent`; a file that is present but cannot be read or
    /// decoded is `.unreadable`. Never throws.
    func readAccountIdentity() -> AccountIdentityRead
}

/// Decodes **only** `oauthAccount.emailAddress`, `oauthAccount.accountUuid` and
/// `oauthAccount.organizationUuid` out of `.claude.json`. The decoder declares those three
/// fields, so the rest of that file (project history, session state, tips, MCP config —
/// and every credential) can never be read into Headroom by accident.
public enum ClaudeAccountBlob {
    private struct Root: Decodable {
        struct OAuthAccount: Decodable {
            let emailAddress: String?
            let accountUuid: String?
            let organizationUuid: String?
        }
        let oauthAccount: OAuthAccount?
    }

    /// The file's account as identity evidence (KTD1). Undecodable JSON is `.unreadable`;
    /// no `oauthAccount` block, or ids that are not UUIDs, is `.absent`.
    public static func identityRead(in data: Data) -> AccountIdentityRead {
        guard let root = decode(data) else { return .unreadable }
        guard let account = root.oauthAccount,
              let identity = AccountIdentity.claude(
                  accountUUID: account.accountUuid,
                  organizationUUID: account.organizationUuid
              )
        else { return .absent }
        return .identity(identity, email: AccountEmail.normalized(account.emailAddress))
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
/// owns the file, Headroom only looks at the named `oauthAccount` fields of it.
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

    /// Upstream account uuid alone, same fail-safe contract as the email: nil when the
    /// file is absent, unreadable, or carries no UUID. The duplicate badge keys on
    /// `readAccountIdentity()` instead, so it and the default-login records agree.
    public func readAccountUUID() -> String? {
        guard let data = try? readData(path) else { return nil }
        return ClaudeAccountBlob.accountUUID(in: data)
    }

    /// One read of the file: identity and email together (KTD2).
    public func readAccountIdentity() -> AccountIdentityRead {
        let data: Data
        do {
            data = try readData(path)
        } catch {
            return Self.isMissingFile(error) ? .absent : .unreadable
        }
        return ClaudeAccountBlob.identityRead(in: data)
    }

    /// The file this reader opens: `~/.claude.json` for the built-in account,
    /// `<CLAUDE_CONFIG_DIR>/.claude.json` for an extra.
    public var accountFile: URL { path }

    /// A config home the CLI has not written yet is "no account", not a read failure.
    static func isMissingFile(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError,
           cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile {
            return true
        }
        if let posix = error as? POSIXError, posix.code == .ENOENT { return true }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOENT) { return true }
        if ns.domain == NSCocoaErrorDomain,
           ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError {
            return true
        }
        return false
    }
}

/// Flags Claude accounts whose config homes are signed in to the **same upstream
/// Claude login**. Detection only — Headroom never merges or removes rows on its own
/// (a user may keep two homes on one subscription deliberately); the settings UI
/// badges the duplicate so the user can decide which record to keep. The key is the
/// default-login identity (`AccountIdentity.claude`: `accountUuid` plus
/// `organizationUuid`, KTD1), so the badge and the default-login records can never
/// disagree about whether two homes hold one account — never the email.
public struct ClaudeDuplicateLoginDetector: Sendable {
    private let readIdentity: @Sendable (AccountID) -> AccountIdentity?

    public init(
        readIdentity: @escaping @Sendable (AccountID) -> AccountIdentity? = {
            ClaudeAccountEmailFileReader.forAccount($0).readAccountIdentity().identity
        }
    ) {
        self.readIdentity = readIdentity
    }

    /// For each Claude account signed in to the same upstream login as an earlier row,
    /// the earlier row's label ("Same login as Main"). Registry order decides which
    /// row counts as the original. Unreadable identity fails safe to "no claim".
    public func duplicateLabels(for accounts: [ProviderAccount]) -> [AccountKey: String] {
        var firstLabelByDigest: [String: String] = [:]
        var duplicates: [AccountKey: String] = [:]
        for account in accounts where account.providerID == .claude {
            guard let identity = readIdentity(account.id), identity.providerID == .claude else { continue }
            if let original = firstLabelByDigest[identity.digest] {
                duplicates[account.key] = original
            } else {
                firstLabelByDigest[identity.digest] = account.label
            }
        }
        return duplicates
    }
}
