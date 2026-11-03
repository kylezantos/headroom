import Foundation
import Darwin

public enum GrokUsageTransport: String, Sendable, Equatable {
    case stdio
    case http
}

public enum GrokUsageSourceResult: Sendable, Equatable {
    case payload(Data, transport: GrokUsageTransport)
    case methodUnavailable
    case cliNotFound
    case authAbsent
    case authPermissionDenied
    case authUnsafePermissions
    case authMalformed
    case authIOFailure
    case rejectedAuth
    case failure(FailureReason)
}

public protocol GrokUsageSource: Sendable {
    func fetchUsage() async -> GrokUsageSourceResult
}

public struct GrokCredential: Sendable, Equatable {
    let accessToken: String
    let userID: String
    /// Which x.ai account this login is, read from the same session record the token
    /// comes from. Nil whenever the field is absent or not a string — identity is
    /// display context, so it never makes an otherwise valid credential malformed.
    let email: String?

    init(accessToken: String, userID: String, email: String? = nil) {
        self.accessToken = accessToken
        self.userID = userID
        self.email = email
    }
}

public protocol GrokAuthReading: Sendable {
    func readGrokCredential() throws -> GrokCredential
}

public enum GrokAuthBlob {
    public static func parse(_ data: Data) throws -> GrokCredential {
        let root = try CredentialError.jsonObject(data)
        let candidates = root.keys.sorted().compactMap { scope -> (String, [String: Any])? in
            guard scope.hasPrefix("https://auth.x.ai::"),
                  let entry = root[scope] as? [String: Any]
            else { return nil }
            return (scope, entry)
        }
        guard let entry = candidates.first?.1,
              (entry["auth_mode"] as? String)?.lowercased() != "web_login",
              let token = entry["key"] as? String, !token.isEmpty,
              let userID = entry["user_id"] as? String, !userID.isEmpty
        else { throw CredentialError.malformed }
        // Best-effort identity out of the *same* selected record — never a second scan,
        // so the email always belongs to the account whose token we just took.
        return GrokCredential(accessToken: token, userID: userID, email: email(in: entry))
    }

    private static func email(in entry: [String: Any]) -> String? {
        AccountEmail.normalized(entry["email"] as? String)
    }
}

/// Production reader for the official CLI-owned `auth.json`. Only the bearer and user
/// identifier required by the official billing endpoint leave this boundary; neither is
/// ever logged or carried in a failure message.
public struct GrokAuthFileReader: GrokAuthReading {
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
                .appendingPathComponent(".grok/auth.json")
        self.readData = readData
        self.permissionsAreSafe = permissionsAreSafe
    }

    public func readGrokCredential() throws -> GrokCredential {
        do {
            let data = try readData(path)
            guard permissionsAreSafe(path) else { throw CredentialError.unsafePermissions }
            return try GrokAuthBlob.parse(data)
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

/// Calls the official CLI's JSON-RPC extension. Some released Grok Build versions
/// advertise ACP but return `-32601` for `x.ai/billing`; that result is deliberately
/// distinct so `GrokFallbackUsageSource` can switch to the CLI's HTTP billing endpoint.
public struct GrokACPUsageSource: GrokUsageSource {
    public let grokPath: String?
    public let workingDirectory: String
    public let environmentOverrides: [String: String]
    public let timeout: TimeInterval

    public init(
        grokPath: String? = GrokACPUsageSource.resolveGrokPath(),
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environmentOverrides: [String: String] = [:],
        timeout: TimeInterval = 8
    ) {
        self.grokPath = grokPath
        self.workingDirectory = workingDirectory
        self.environmentOverrides = environmentOverrides
        self.timeout = timeout
    }

    public static func resolveGrokPath() -> String? {
        CLIExecutableResolver.resolve(
            named: "grok",
            fallbackPaths: fallbackPaths
        )
    }

    static var fallbackPaths: [String] {
        [
            "\(NSHomeDirectory())/.local/bin/grok",
            "\(NSHomeDirectory())/.grok/bin/grok",
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok",
        ]
    }

    public func fetchUsage() async -> GrokUsageSourceResult {
        guard let grokPath, FileManager.default.isExecutableFile(atPath: grokPath) else {
            return .cliNotFound
        }
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread { [environmentOverrides] in
                continuation.resume(returning: Self.runBlocking(
                    grokPath: grokPath,
                    workingDirectory: workingDirectory,
                    environmentOverrides: environmentOverrides,
                    timeout: timeout
                ))
            }
        }
    }

    private static func runBlocking(
        grokPath: String,
        workingDirectory: String,
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) -> GrokUsageSourceResult {
        let environment = environment(
            inherited: ProcessInfo.processInfo.environment,
            overrides: environmentOverrides,
            loginPath: CLIExecutableResolver.resolveLoginPath(
                fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            )
        )
        guard let process = StdioChildProcess.spawn(
            path: grokPath,
            arguments: [grokPath, "agent", "stdio"],
            environment: environment,
            workingDirectory: workingDirectory
        ) else { return .failure(.transient("Couldn’t start Grok usage probe")) }
        defer { process.terminate() }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        let initialize: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": ["readTextFile": false, "writeTextFile": false],
                    "terminal": false,
                ],
                "_meta": [
                    "startupHints": [
                        "nonInteractive": true,
                        "skipGitStatus": true,
                        "skipProjectLayout": true,
                    ],
                    "clientType": "headroom",
                    "clientVersion": "1",
                ],
            ],
        ]
        guard writeJSONLine(initialize, to: process),
              let initializeResponse = readResponse(id: 1, from: process, buffer: &buffer, deadline: deadline),
              initializeResponse["result"] != nil
        else { return .failure(.transient("Couldn’t initialize Grok usage probe")) }

        let billing: [String: Any] = [
            "jsonrpc": "2.0", "id": 2, "method": "x.ai/billing", "params": [:],
        ]
        guard writeJSONLine(billing, to: process),
              let response = readResponse(id: 2, from: process, buffer: &buffer, deadline: deadline)
        else { return .failure(.transient("Couldn’t read Grok usage")) }

        if let error = response["error"] as? [String: Any],
           (error["code"] as? NSNumber)?.intValue == -32601 {
            return .methodUnavailable
        }
        guard let rawResult = response["result"], !(rawResult is NSNull),
              JSONSerialization.isValidJSONObject(rawResult),
              let data = try? JSONSerialization.data(withJSONObject: rawResult)
        else { return .failure(.transient("Couldn’t read Grok usage")) }
        return .payload(data, transport: .stdio)
    }

    private static func writeJSONLine(_ object: [String: Any], to process: StdioChildProcess) -> Bool {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        data.append(0x0A)
        return process.write(data)
    }

    private static func readResponse(
        id: Int,
        from process: StdioChildProcess,
        buffer: inout Data,
        deadline: Date
    ) -> [String: Any]? {
        while Date() < deadline {
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
                else { continue }
                if (object["id"] as? NSNumber)?.intValue == id { return object }
            }
            guard process.readOutput(into: &buffer, deadline: deadline) else { return nil }
        }
        return nil
    }

    static func environment(
        inherited: [String: String],
        overrides: [String: String],
        loginPath: String
    ) -> [String: String] {
        var result = inherited
        // The built-in account always means the official CLI default. A custom value
        // inherited from a Terminal launch must not silently select another account.
        if overrides["GROK_HOME"] == nil { result.removeValue(forKey: "GROK_HOME") }
        overrides.forEach { result[$0.key] = $0.value }
        result["PATH"] = loginPath
        return result
    }
}

/// HTTP fallback using the token the official CLI wrote. Requests are GET-only and
/// redirects are blocked by `UsageFetching`, matching the Codex credential posture.
public struct GrokHTTPUsageSource: GrokUsageSource {
    public static let endpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    private let authReader: any GrokAuthReading
    private let http: any UsageFetching

    public init(
        authReader: any GrokAuthReading = GrokAuthFileReader(),
        http: any UsageFetching = RedirectBlockingHTTPClient()
    ) {
        self.authReader = authReader
        self.http = http
    }

    public func fetchUsage() async -> GrokUsageSourceResult {
        let credential: GrokCredential
        do {
            credential = try authReader.readGrokCredential()
        } catch CredentialError.notLoggedIn {
            return .authAbsent
        } catch CredentialError.permissionDenied {
            return .authPermissionDenied
        } catch CredentialError.unsafePermissions {
            return .authUnsafePermissions
        } catch CredentialError.malformed {
            return .authMalformed
        } catch {
            return .authIOFailure
        }

        let headers = [
            "Authorization": "Bearer \(credential.accessToken)",
            "X-XAI-Token-Auth": "xai-grok-cli",
            "x-userid": credential.userID,
        ]
        switch await http.get(url: Self.endpoint, headers: headers) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let result):
            switch result.status {
            case 200: return .payload(result.body, transport: .http)
            case 401, 403: return .rejectedAuth
            default: return .failure(UsageWindowBuilder.genericFailure(for: result.status))
            }
        }
    }
}

/// Tries the official-client ACP extension first and falls back only when the released
/// CLI reports that the method does not exist. Other failures stay visible instead of
/// silently changing transport and obscuring a broken primary path.
public struct GrokFallbackUsageSource: GrokUsageSource {
    private let primary: any GrokUsageSource
    private let fallback: any GrokUsageSource

    public init(primary: any GrokUsageSource, fallback: any GrokUsageSource) {
        self.primary = primary
        self.fallback = fallback
    }

    public func fetchUsage() async -> GrokUsageSourceResult {
        let result = await primary.fetchUsage()
        if result == .methodUnavailable { return await fallback.fetchUsage() }
        return result
    }
}
