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
        guard let value = (entry["email"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
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
        var input = [Int32](repeating: -1, count: 2)
        var output = [Int32](repeating: -1, count: 2)
        guard pipe(&input) == 0 else { return .failure(.transient("Couldn't start Grok usage probe")) }
        guard pipe(&output) == 0 else {
            close(input[0]); close(input[1])
            return .failure(.transient("Couldn't start Grok usage probe"))
        }
        guard fcntl(input[1], F_SETNOSIGPIPE, 1) != -1 else {
            close(input[0]); close(input[1]); close(output[0]); close(output[1])
            return .failure(.transient("Couldn't start Grok usage probe"))
        }
        let devNull = open("/dev/null", O_WRONLY)

        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, workingDirectory)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory)
        }
        posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        if devNull >= 0 { posix_spawn_file_actions_adddup2(&actions, devNull, STDERR_FILENO) }
        for fd in [input[0], input[1], output[0], output[1], devNull] where fd >= 0 {
            posix_spawn_file_actions_addclose(&actions, fd)
        }

        var attributes = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        let environment = environment(
            inherited: ProcessInfo.processInfo.environment,
            overrides: environmentOverrides,
            loginPath: CLIExecutableResolver.resolveLoginPath(
                fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            )
        )
        let environmentStrings = environment.map { "\($0.key)=\($0.value)" }
        let arguments = [grokPath, "agent", "stdio"]
        let cEnvironment = environmentStrings.map { strdup($0) } + [nil]
        let cArguments = arguments.map { strdup($0) } + [nil]
        defer {
            cEnvironment.forEach { free($0) }
            cArguments.forEach { free($0) }
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, grokPath, &actions, &attributes, cArguments, cEnvironment)
        close(input[0]); close(output[1])
        if devNull >= 0 { close(devNull) }
        guard spawnStatus == 0 else {
            close(input[1]); close(output[0])
            return .failure(.transient("Couldn't start Grok usage probe"))
        }
        defer {
            close(input[1]); close(output[0])
            terminateProcessGroup(pid)
        }

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
        guard writeJSONLine(initialize, to: input[1]),
              let initializeResponse = readResponse(id: 1, from: output[0], buffer: &buffer, deadline: deadline),
              initializeResponse["result"] != nil
        else { return .failure(.transient("Couldn't initialize Grok usage probe")) }

        let billing: [String: Any] = [
            "jsonrpc": "2.0", "id": 2, "method": "x.ai/billing", "params": [:],
        ]
        guard writeJSONLine(billing, to: input[1]),
              let response = readResponse(id: 2, from: output[0], buffer: &buffer, deadline: deadline)
        else { return .failure(.transient("Couldn't read Grok usage")) }

        if let error = response["error"] as? [String: Any],
           (error["code"] as? NSNumber)?.intValue == -32601 {
            return .methodUnavailable
        }
        guard let rawResult = response["result"], !(rawResult is NSNull),
              JSONSerialization.isValidJSONObject(rawResult),
              let data = try? JSONSerialization.data(withJSONObject: rawResult)
        else { return .failure(.transient("Couldn't read Grok usage")) }
        return .payload(data, transport: .stdio)
    }

    private static func writeJSONLine(_ object: [String: Any], to fd: Int32) -> Bool {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        data.append(0x0A)
        return data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                guard written > 0 else { return false }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    private static func readResponse(
        id: Int,
        from fd: Int32,
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

            let remainingMilliseconds = max(1, Int(deadline.timeIntervalSinceNow * 1_000))
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = Darwin.poll(&descriptor, 1, Int32(min(remainingMilliseconds, 250)))
            guard pollResult >= 0 else { return nil }
            guard pollResult > 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk.prefix(count))
        }
        return nil
    }

    private static func terminateProcessGroup(_ pid: pid_t) {
        guard pid > 0 else { return }
        var status: Int32 = 0
        let initial = waitpid(pid, &status, WNOHANG)
        if initial == pid || (initial == -1 && errno == ECHILD) { return }

        kill(-pid, SIGTERM)
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return }
            usleep(20_000)
        }
        kill(-pid, SIGKILL)
        let killDeadline = Date().addingTimeInterval(0.5)
        while Date() < killDeadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return }
            usleep(20_000)
        }
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
