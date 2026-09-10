import Foundation
import Security

/// Codex credential access (U3). Claude no longer flows through here — it reads the
/// official `/usage` panel via the CLI (see `ClaudeProvider`), so the only remaining
/// credential is Codex's `~/.codex/auth.json` token. An `actor` for data-race-free
/// access under Swift 6 strict concurrency (KTD10).
public actor CredentialStore {
    private let codexReader: CodexAuthReading
    private let apiKeyStore: APIKeyStoring

    public init(
        codexReader: CodexAuthReading = CodexAuthFileReader(),
        apiKeyStore: APIKeyStoring = KeychainAPIKeyStore()
    ) {
        self.codexReader = codexReader
        self.apiKeyStore = apiKeyStore
    }

    public func codexAccessToken() async -> Result<String, FailureReason> {
        await codexSession().map(\.accessToken)
    }

    /// Token plus the signed-in account's email. Same typed failure mapping as
    /// `codexAccessToken()` — the email rides along so the provider doesn't have to read
    /// `auth.json` a second time just for identity.
    public func codexSession() async -> Result<CodexSession, FailureReason> {
        do {
            let credential = try codexReader.readCodexCredential()
            return .success(
                CodexSession(accessToken: credential.accessToken, accountEmail: credential.email)
            )
        } catch CredentialError.notLoggedIn {
            return .failure(.providerSetup(.codexAuthAbsent))
        } catch CredentialError.permissionDenied {
            return .failure(.providerSetup(.codexPermissionDenied))
        } catch CredentialError.unsafePermissions {
            return .failure(.providerSetup(.codexUnsafePermissions))
        } catch CredentialError.malformed {
            return .failure(.providerSetup(.codexMalformedAuth))
        } catch CredentialError.ioFailure {
            return .failure(.providerSetup(.codexCredentialIO))
        } catch CredentialError.keychainStatus {
            return .failure(.providerSetup(.codexCredentialIO))
        } catch {
            return .failure(.providerSetup(.codexCredentialIO))
        }
    }

    public func apiKey(for provider: APIKeyProvider) async -> Result<String, FailureReason> {
        do {
            let key = try apiKeyStore.readAPIKey(for: provider)
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.notLoggedIn("\(provider.credentialLabel) is empty"))
            }
            return .success(key)
        } catch CredentialError.notLoggedIn {
            // The provider's declared credential, article included: interpolating a vendor
            // name after "a" produced "Add a Anthropic admin API key", and named the wrong
            // credential for xAI, which takes a management key.
            let credential = APISpendCredentialDescriptor.forProvider(provider.providerID)
            return .failure(.notLoggedIn("Add \(credential.credentialNoun) in Settings"))
        } catch {
            return .failure(.notLoggedIn("\(provider.credentialLabel) unreadable"))
        }
    }

    public func saveAPIKey(_ key: String, for provider: APIKeyProvider) async -> Result<Void, FailureReason> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.notLoggedIn("\(provider.credentialLabel) is empty"))
        }
        do {
            try apiKeyStore.saveAPIKey(trimmed, for: provider)
            return .success(())
        } catch {
            return .failure(.transient("Couldn’t save \(provider.credentialLabel)"))
        }
    }

    public func deleteAPIKey(for provider: APIKeyProvider) async -> Result<Void, FailureReason> {
        do {
            try apiKeyStore.deleteAPIKey(for: provider)
            return .success(())
        } catch {
            return .failure(.transient("Couldn’t delete \(provider.credentialLabel)"))
        }
    }
}

extension APIKeyProvider {
    /// The stored credential named the way Settings → API Spend and the spend rows already
    /// name it — "Anthropic admin key", "xAI management key". `displayName` cannot carry
    /// these lines on its own: it is a row title, so `"\(displayName) API key"` rendered
    /// xAI's as "xAI API API key", and it calls every credential an "API key" when xAI's is
    /// a management key. Vendor and noun both come from the one
    /// `APISpendCredentialDescriptor` vocabulary that already fixed the missing-key line
    /// below, so no surface invents a second name for the same secret.
    var credentialLabel: String {
        let credential = APISpendCredentialDescriptor.forProvider(providerID)
        return "\(APISpendPresentation.vendorName(from: displayName)) \(credential.noun)"
    }
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    public init() {}

    public func readAPIKey(for provider: APIKeyProvider) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw CredentialError.notLoggedIn }
        guard status == errSecSuccess else { throw CredentialError.keychainStatus(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw CredentialError.malformed
        }
        return key
    }

    public func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        let data = Data(key.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychainStatus(status) }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialError.keychainStatus(addStatus) }
    }

    public func deleteAPIKey(for provider: APIKeyProvider) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychainStatus(status)
        }
    }
}
