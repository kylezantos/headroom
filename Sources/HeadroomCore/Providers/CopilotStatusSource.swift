import Foundation

public struct CopilotAccountStatus: Sendable, Equatable {
    public let login: String
    public let entitlement: Double?
    public let isUnlimited: Bool
    public let tokenBasedBilling: Bool
    public let reportedUsed: Double?
    public let reportedResetDate: Date?

    public init(
        login: String,
        entitlement: Double?,
        isUnlimited: Bool,
        tokenBasedBilling: Bool,
        reportedUsed: Double?,
        reportedResetDate: Date?
    ) {
        self.login = login
        self.entitlement = entitlement
        self.isUnlimited = isUnlimited
        self.tokenBasedBilling = tokenBasedBilling
        self.reportedUsed = reportedUsed
        self.reportedResetDate = reportedResetDate
    }
}

public enum CopilotStatusResult: Sendable, Equatable {
    case signedIn(CopilotAccountStatus)
    case signedOut
    case cliMissing
    case failure(FailureReason)
}

public protocol CopilotStatusSourcing: Sendable {
    func status() async -> CopilotStatusResult
}

/// Reads sign-in state and quota from the official CLI's local server. Only `ping`,
/// `auth.getStatus` and `account.getQuota` are ever sent, because `session.create` would
/// start a session on the user's account.
///
/// `usedRequests` and `resetDate` are passed on raw and uninterpreted. GitHub rounds the
/// first to 0.5%, the server caches it between reads, and the second holds the time of that
/// cached reading rather than a real reset, so the provider decides what they are worth.
public actor CopilotStatusSource: CopilotStatusSourcing {
    /// Each spawn writes a file to `~/.copilot/logs`, so timers share one reading.
    public static let cacheLifetime: TimeInterval = 60 * 60

    /// The server's framing and method set, verified against CLI 1.0.105.
    static let supportedProtocolVersion = 3

    private struct CachedReading {
        let result: CopilotStatusResult
        let readAt: Date
    }

    private let executablePath: @Sendable () -> String?
    private let workingDirectory: String
    private let inheritedEnvironment: @Sendable () -> [String: String]
    private let loginPath: @Sendable () -> String
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date
    private var cached: CachedReading?

    public init(
        executablePath: @escaping @Sendable () -> String? = { CopilotStatusSource.resolveExecutablePath() },
        workingDirectory: String = NSHomeDirectory(),
        inheritedEnvironment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        loginPath: @escaping @Sendable () -> String = {
            CLIExecutableResolver.resolveLoginPath(
                fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            )
        },
        timeout: TimeInterval = 15,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.inheritedEnvironment = inheritedEnvironment
        self.loginPath = loginPath
        self.timeout = timeout
        self.now = now
    }

    public static func resolveExecutablePath() -> String? {
        CLIExecutableResolver.resolve(named: "copilot", fallbackPaths: fallbackPaths)
    }

    /// `command -v` prints a user's `copilot` alias instead of a path, so these fixed paths
    /// are what finds the binary then, as well as from a bare Finder environment.
    static var fallbackPaths: [String] {
        [
            "/opt/homebrew/bin/copilot",
            "/usr/local/bin/copilot",
            "\(NSHomeDirectory())/.local/bin/copilot",
            "\(NSHomeDirectory())/.npm-global/bin/copilot",
        ]
    }

    public func status() async -> CopilotStatusResult {
        if !UserRequestedProbeContext.isUserRequested,
           let cached, now().timeIntervalSince(cached.readAt) < Self.cacheLifetime {
            return cached.result
        }
        let result = await readFromServer()
        switch result {
        case .signedIn, .signedOut:
            cached = CachedReading(result: result, readAt: now())
        case .cliMissing, .failure:
            cached = nil
        }
        return result
    }

    private func readFromServer() async -> CopilotStatusResult {
        let executablePath = executablePath
        let workingDirectory = workingDirectory
        let inheritedEnvironment = inheritedEnvironment
        let loginPath = loginPath
        let timeout = timeout
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                guard let path = executablePath(), FileManager.default.isExecutableFile(atPath: path) else {
                    continuation.resume(returning: .cliMissing)
                    return
                }
                continuation.resume(returning: Self.runBlocking(
                    path: path,
                    workingDirectory: workingDirectory,
                    environment: Self.environment(inherited: inheritedEnvironment(), loginPath: loginPath()),
                    timeout: timeout
                ))
            }
        }
    }

    /// Each of these selects another account, and "the account" means the CLI's default
    /// home `~/.copilot`.
    static func environment(inherited: [String: String], loginPath: String) -> [String: String] {
        var result = inherited
        for name in ["COPILOT_HOME", "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"] {
            result.removeValue(forKey: name)
        }
        result["PATH"] = loginPath
        return result
    }

    private static func runBlocking(
        path: String,
        workingDirectory: String,
        environment: [String: String],
        timeout: TimeInterval
    ) -> CopilotStatusResult {
        guard let process = StdioChildProcess.spawn(
            path: path,
            arguments: [path, "--headless", "--stdio", "--no-auto-update"],
            environment: environment,
            workingDirectory: workingDirectory
        ) else { return .failure(.transient("Couldn’t start the Copilot status check")) }
        defer { process.terminate() }

        var client = CopilotRPCClient(process: process, deadline: Date().addingTimeInterval(timeout))
        let unreadable = CopilotStatusResult.failure(.transient("Couldn’t read Copilot status"))

        guard let ping = client.call("ping", params: ["message": "headroom"]) else { return unreadable }
        guard ping["protocolVersion"] as? Int == supportedProtocolVersion else {
            return .failure(.transient("This Copilot CLI version isn’t supported yet"))
        }
        guard let auth = client.call("auth.getStatus"),
              let isAuthenticated = auth["isAuthenticated"] as? Bool
        else { return unreadable }
        guard isAuthenticated else { return .signedOut }
        guard let login = auth["login"] as? String,
              let quota = client.call("account.getQuota"),
              let status = parseStatus(login: login, quota: quota)
        else { return unreadable }
        return .signedIn(status)
    }

    private static func parseStatus(login: String, quota: [String: Any]) -> CopilotAccountStatus? {
        guard let snapshots = quota["quotaSnapshots"] as? [String: Any],
              let premium = snapshots["premium_interactions"] as? [String: Any]
        else { return nil }
        let isUnlimited = premium["isUnlimitedEntitlement"] as? Bool ?? false
        return CopilotAccountStatus(
            login: login,
            entitlement: isUnlimited ? nil : premium["entitlementRequests"] as? Double,
            isUnlimited: isUnlimited,
            tokenBasedBilling: premium["tokenBasedBilling"] as? Bool ?? false,
            reportedUsed: premium["usedRequests"] as? Double,
            reportedResetDate: DateParsing.iso8601(premium["resetDate"] as? String)
        )
    }
}

/// JSON-RPC 2.0 over LSP-style `Content-Length` framing, in both directions. One deadline
/// covers every call on a client.
private struct CopilotRPCClient {
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    let process: StdioChildProcess
    let deadline: Date
    private var nextID = 1
    private var buffer = Data()

    init(process: StdioChildProcess, deadline: Date) {
        self.process = process
        self.deadline = deadline
    }

    /// The call's `result`. Nil for a JSON-RPC error, a timeout or a closed pipe, which every
    /// caller treats alike. Error bodies are dropped unread because they can name the account.
    mutating func call(_ method: String, params: [String: Any] = [:]) -> [String: Any]? {
        let id = nextID
        nextID += 1
        let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        guard let body = try? JSONSerialization.data(withJSONObject: request),
              process.write(Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body)
        else { return nil }

        while Date() < deadline {
            while let message = nextMessage() {
                guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
                      object["id"] as? Int == id
                else { continue }
                return object["result"] as? [String: Any]
            }
            guard process.readOutput(into: &buffer, deadline: deadline) else { return nil }
        }
        return nil
    }

    private mutating func nextMessage() -> Data? {
        guard let terminator = buffer.range(of: Self.headerTerminator) else { return nil }
        let header = String(decoding: buffer[buffer.startIndex..<terminator.lowerBound], as: UTF8.self)
        let bodyStart = terminator.upperBound
        guard let length = Self.contentLength(in: header),
              buffer.distance(from: bodyStart, to: buffer.endIndex) >= length
        else { return nil }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return body
    }

    private static func contentLength(in header: String) -> Int? {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
