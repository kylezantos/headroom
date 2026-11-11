import Foundation

/// The email a Grok account is signed in as. Injected so the provider can be tested
/// against a fixture credential instead of a real `auth.json`.
public protocol GrokAccountEmailReading: Sendable {
    /// The account email, or nil when the file is absent, unreadable, or carries no
    /// `email` field. Never throws: identity is display context, and a missing email
    /// must never downgrade an otherwise good usage capture (KTD7).
    func readAccountEmail() -> String?
    /// The same read as identity evidence (default-login plan, KTD1): a missing file or a
    /// record with no email is `.absent`; a file that is present but cannot be read or
    /// decoded is `.unreadable`.
    func readAccountIdentity() -> AccountIdentityRead
}

public extension GrokAccountEmailReading {
    func readAccountIdentity() -> AccountIdentityRead {
        let email = readAccountEmail()
        return AccountIdentity.grok(email: email).map { .identity($0, email: email) } ?? .absent
    }
}

/// Reads the email out of the *same* CLI-owned `auth.json` record the billing path
/// already selects, by reusing that path's `GrokAuthReading`. `GrokAuthFileReader` (fed
/// by `ProviderAccountConfiguration.grokAuthFile`) therefore stays the single place a
/// Grok credential path is resolved — an extra account's `GROK_HOME` is honoured because
/// the composition root hands this the reader it already built for that account, not
/// because a parallel resolver guesses the same directory again.
///
/// The credential itself never leaves this type: only the extracted email is returned.
public struct GrokCredentialEmailReader: GrokAccountEmailReading {
    private let authReader: any GrokAuthReading

    public init(authReader: any GrokAuthReading) {
        self.authReader = authReader
    }

    public func readAccountEmail() -> String? {
        AccountEmail.normalized((try? authReader.readGrokCredential())?.email)
    }

    public func readAccountIdentity() -> AccountIdentityRead {
        do {
            let email = AccountEmail.normalized(try authReader.readGrokCredential().email)
            return AccountIdentity.grok(email: email).map { .identity($0, email: email) } ?? .absent
        } catch CredentialError.notLoggedIn {
            return .absent
        } catch {
            return .unreadable
        }
    }
}
