import CryptoKit
import Foundation

/// Which upstream account a reading came from (default-login plan, KTD1). Read as
/// metadata from the official CLI's own files; only a SHA-256 digest of the upstream id
/// is kept, in memory and on disk, following `CopilotLoginMemory`. The digest keeps
/// upstream ids out of storage. It is not a privacy control: the email is already
/// stored locally for display.
public struct AccountIdentity: Sendable, Equatable, Hashable, Codable {
    /// Strong: a stable upstream account id (Codex). Weak: an email or login name, which
    /// can be renamed or reused, so it relabels a row but never remembers or merges one
    /// (KTD13).
    public enum Strength: String, Sendable, Codable {
        case strong
        case weak
    }

    /// The version of the canonical digest input below. A stored digest with another
    /// version means "adopt again", never "the identity changed" (KTD1).
    public static let currentDigestVersion = 1

    public let providerID: ProviderID
    public let strength: Strength
    public let digest: String
    public let digestVersion: Int

    public init(providerID: ProviderID, strength: Strength, digest: String, digestVersion: Int) {
        self.providerID = providerID
        self.strength = strength
        self.digest = digest
        self.digestVersion = digestVersion
    }

    /// Codex: `tokens.account_id` from the `auth.json` the request's own token came from.
    public static func codex(accountID: String?) -> AccountIdentity? {
        make(.codex, field: "account_id", value: accountID, strength: .strong)
    }

    /// Grok exposes an email only, and its ACP path reads its login separately from the
    /// file, so this names the file's account rather than proving who was billed.
    public static func grok(email: String?) -> AccountIdentity? {
        make(.grok, field: "email", value: email, strength: .weak)
    }

    public static func cursor(email: String?) -> AccountIdentity? {
        make(.cursor, field: "email", value: email, strength: .weak)
    }

    public static func copilot(login: String?) -> AccountIdentity? {
        make(.copilot, field: "login", value: login, strength: .weak)
    }

    /// The canonical input is fixed: version, provider, field name and the value trimmed
    /// and lowercased (upstream ids are UUID-shaped and emails compare case-blind).
    /// Changing any part of it needs a new `currentDigestVersion`; the golden vectors in
    /// `AccountIdentityTests` pin it.
    private static func make(
        _ providerID: ProviderID,
        field: String,
        value: String?,
        strength: Strength
    ) -> AccountIdentity? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty
        else { return nil }
        let canonical = "headroom.identity.v\(currentDigestVersion)|\(providerID.raw)|\(field)|\(normalized)"
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return AccountIdentity(
            providerID: providerID,
            strength: strength,
            digest: digest,
            digestVersion: currentDigestVersion
        )
    }
}

/// One read of a CLI's identity metadata.
public enum AccountIdentityRead: Sendable, Equatable {
    /// The file (or status call) names an account.
    case identity(AccountIdentity, email: String?)
    /// The read succeeded and names no account, or there is no file at all.
    case absent
    /// The source is present but could not be read or decoded.
    case unreadable

    public var identity: AccountIdentity? {
        if case .identity(let identity, _) = self { return identity }
        return nil
    }

    public var email: String? {
        if case .identity(_, let email) = self { return email }
        return nil
    }
}

/// What the identity reads around one usage reading say about whose reading it is (KTD2).
public enum AccountIdentityOutcome: Sendable, Equatable {
    /// Every read agrees on one account.
    case known(AccountIdentity)
    /// Every read succeeded and none names an account.
    case absent
    /// A read failed, or two reads disagree: the login was changing. The reading is
    /// refused rather than filed under either account.
    case unreadable

    public var identity: AccountIdentity? {
        if case .known(let identity) = self { return identity }
        return nil
    }

    /// Combines the read taken before the usage read with the one taken after it.
    public static func bracketing(
        before: AccountIdentityRead,
        after: AccountIdentityRead
    ) -> AccountIdentityOutcome {
        switch (before, after) {
        case (.identity(let first, _), .identity(let second, _)):
            return first == second ? .known(first) : .unreadable
        case (.absent, .absent):
            return .absent
        default:
            return .unreadable
        }
    }
}
