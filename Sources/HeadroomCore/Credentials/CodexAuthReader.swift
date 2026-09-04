import Foundation

/// Reads the Codex credential. Injected so tests use fixture data instead of the
/// real `~/.codex/auth.json`.
public protocol CodexAuthReading: Sendable {
    func readCodexCredential() throws -> CodexCredential
}

/// Parses `~/.codex/auth.json`. Structure:
/// `{ auth_mode, OPENAI_API_KEY, tokens: { access_token, id_token, refresh_token,
/// account_id }, last_refresh }`.
public enum CodexAuthBlob {
    public static func parse(_ data: Data) throws -> CodexCredential {
        let root = try CredentialError.jsonObject(data)
        guard
            let tokens = root["tokens"] as? [String: Any],
            let access = tokens["access_token"] as? String
        else { throw CredentialError.malformed }
        let lastRefresh = DateParsing.iso8601(root["last_refresh"] as? String)
        return CodexCredential(
            accessToken: access,
            refreshToken: tokens["refresh_token"] as? String,
            accountID: tokens["account_id"] as? String,
            lastRefresh: lastRefresh,
            // Identity only, and best-effort: a missing/unreadable id_token must not make
            // an otherwise valid credential malformed.
            email: AccountEmail.normalized(
                (tokens["id_token"] as? String).flatMap { JWTClaims.string("email", in: $0) }
            )
        )
    }
}

/// Reads one string claim out of a JWT payload. This is a local metadata read of a token
/// the official `codex` CLI already wrote to disk — the payload is decoded, never
/// verified (Headroom is not a relying party), never sent anywhere, and the token itself
/// never leaves this type: only the extracted claim is returned.
enum JWTClaims {
    static func string(_ name: String, in token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = base64URLDecoded(String(segments[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let value = claims[name] as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    /// base64url → base64: swap the URL-safe alphabet back and restore the padding JWT
    /// segments omit. A segment whose length leaves 1 byte over is not valid base64 and
    /// falls out as nil.
    private static func base64URLDecoded(_ segment: String) -> Data? {
        var text = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder > 0 {
            text.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: text)
    }
}

/// Production reader for `~/.codex/auth.json` (filesystem-gated, non-sandboxed — KTD2).
public struct CodexAuthFileReader: CodexAuthReading {
    private let path: URL
    private let readData: @Sendable (URL) throws -> Data
    private let permissionsAreSafe: @Sendable (URL) -> Bool

    public init(
        path: URL? = nil,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        permissionsAreSafe: @escaping @Sendable (URL) -> Bool = {
            AccountStorage.credentialFilePermissionsAreSafe(at: $0)
        }
    ) {
        self.path = path
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
        self.readData = readData
        self.permissionsAreSafe = permissionsAreSafe
    }

    public func readCodexCredential() throws -> CodexCredential {
        do {
            let data = try readData(path)
            guard permissionsAreSafe(path) else { throw CredentialError.unsafePermissions }
            return try CodexAuthBlob.parse(data)
        } catch let error as CredentialError {
            throw error
        } catch let error as CocoaError {
            switch error.code {
            case .fileNoSuchFile, .fileReadNoSuchFile:
                throw CredentialError.notLoggedIn
            case .fileReadNoPermission:
                throw CredentialError.permissionDenied
            default:
                throw CredentialError.ioFailure
            }
        } catch {
            throw CredentialError.ioFailure
        }
    }
}
