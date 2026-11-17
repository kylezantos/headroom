import Foundation

// MARK: - Capture

/// The two quota pools Antigravity reports, keyed by bucket ID prefix, never by display text.
public enum AntigravityPool: String, Sendable, Equatable {
    /// `gemini-*` buckets: the "Gemini Models" group, which names Gemini 4 Argon among its models.
    case gemini
    /// `3p-*` buckets: the "Claude and GPT models" group.
    case claudeAndGPT
}

/// A bucket's `window` value.
public enum AntigravityWindow: String, Sendable, Equatable {
    case fiveHour
    case weekly
}

/// One bucket as the official client reported it.
public struct AntigravityBucket: Sendable, Equatable {
    public let pool: AntigravityPool
    public let window: AntigravityWindow
    /// `remaining_fraction`, clamped to 0...1.
    public let remainingFraction: Double
    /// Nil when the client gave no readable `reset_time`. A reset is never invented.
    public let resetsAt: Date?

    public init(pool: AntigravityPool, window: AntigravityWindow, remainingFraction: Double, resetsAt: Date?) {
        self.pool = pool
        self.window = window
        self.remainingFraction = remainingFraction
        self.resetsAt = resetsAt
    }
}

/// What one read found: the buckets the client reported, in its order, and the AI-credits
/// balance when `/credits` answered. A bucket the client omits is absent, never filled in.
public struct AntigravityUsage: Sendable, Equatable {
    public let buckets: [AntigravityBucket]
    /// Nil when `/credits` failed or printed something unreadable; that never fails the usage.
    public let credits: Double?

    public init(buckets: [AntigravityBucket], credits: Double?) {
        self.buckets = buckets
        self.credits = credits
    }
}

/// Where a format-changed result came from. Logged by stage only: never the output.
public enum AntigravityFormatStage: String, Sendable, Equatable {
    /// Exit 0 with no stdout.
    case output
    /// A no-turn answer for a command other than the one asked.
    case commandName
    /// `command.data` that does not decode as the usage payload.
    case usageData
    /// A usage payload with no bucket of a known pool and window.
    case usageValues
}

/// Why a reading is transient. Typed so diagnostics can count causes without any output.
public enum AntigravityTransientCause: String, Sendable, Equatable {
    case spawnFailed
    /// `--version` failed, timed out or printed no recognisable version.
    case unreadableVersion
    case deadline
    /// A nonzero exit or a signal with no usable answer.
    case unexpectedExit
    /// An `ERROR` result whose message says authentication failed or timed out, with no
    /// sign-in prompt seen on stderr. That alone does not prove the account is signed out.
    case authenticationFailed
    /// Any other `ERROR` result.
    case clientError
}

public enum AntigravityCaptureFailure: Sendable, Equatable {
    case cliMissing
    /// Older than `AntigravityCLIUsageSource.minimumVersion`.
    case updateRequired
    /// The client answered a read with a model turn or spent tokens, answered without the
    /// no-turn command payload, or printed an answer that can't show it cost no turn (over the
    /// size cap, or not the JSON result at exit 0). Sticky: no further read spawns the client until its resolved
    /// path, modification date or version changes, so a changed CLI or a user skill that takes
    /// over `/usage` can't turn every poll into a paid agent turn.
    case unsupportedClient
    /// The client printed its "Authentication required" sign-in prompt on stderr, the one
    /// positive evidence of a signed-out account. It opens an interactive Google sign-in in the
    /// browser and waits for it, so the read is ended at the prompt. Sticky: routine polls
    /// never spawn the client again until a user request (Refresh, or the check after the
    /// sign-in handoff), so a sign-out opens at most one browser sign-in.
    case signedOut
    case formatChanged(AntigravityFormatStage)
    case transient(AntigravityTransientCause)

    public var outcome: ProviderSetupOutcome {
        switch self {
        case .cliMissing: .antigravityCLIMissing
        case .updateRequired: .antigravityUpdateRequired
        case .unsupportedClient: .antigravityUnsupportedClient
        case .signedOut: .antigravitySignedOut
        case .formatChanged: .antigravityFormatChanged
        case .transient: .antigravityTransientCapture
        }
    }

    public var failureReason: FailureReason { .providerSetup(outcome) }
}

public enum AntigravityCapture: Sendable, Equatable {
    case usage(AntigravityUsage)
    case failed(AntigravityCaptureFailure)
}

/// The seam the Antigravity provider consumes. Antigravity is single-account, so a capture
/// takes no account home.
public protocol AntigravityUsageSource: Sendable {
    func capture() async -> AntigravityCapture
}

// MARK: - Commands

/// The closed set of client invocations. No caller can supply a prompt, a path or any other
/// argument. `--disable-slash-commands` is never passed: slash expansion is what routes
/// `/usage` and `/credits` to the client's no-turn answer.
enum AntigravityCommand: CaseIterable, Sendable {
    case version
    case usage
    case credits

    var arguments: [String] {
        switch self {
        case .version: ["--version"]
        case .usage: ["-p", "/usage", "--output-format", "json"]
        case .credits: ["-p", "/credits", "--output-format", "json"]
        }
    }

    var sizeCap: Int {
        switch self {
        case .version: 4_096
        case .usage, .credits: 64 * 1_024
        }
    }
}

/// What one spawn produced. `exitCode` is nil when the process was still running at the
/// deadline or died on a signal. Stderr is never kept: only whether it showed the sign-in
/// prompt.
struct AntigravityRunOutput: Sendable, Equatable {
    var exitCode: Int32?
    var stdout: Data
    var overflowed: Bool
    var timedOut: Bool
    /// The run was ended at the client's sign-in prompt (`AntigravitySignInPromptScanner`).
    var showedSignInPrompt = false
}

/// Matches the client's sign-in prompt across stderr reads. Holds only a short tail of what
/// it has seen, enough to find a marker split between two reads, and returns nothing else.
struct AntigravitySignInPromptScanner {
    /// agy 1.5.9 prints "Authentication required. Please visit the URL to log in:" followed
    /// by a Google sign-in URL, opens that page and waits up to 60 s.
    static let marker = Data("Authentication required".utf8)

    private var tail = Data()

    /// True once the marker has appeared in everything scanned so far.
    mutating func scan(_ chunk: Data) -> Bool {
        tail.append(chunk)
        if tail.range(of: Self.marker) != nil { return true }
        tail = Data(tail.suffix(Self.marker.count - 1))
        return false
    }
}

/// What `/credits` gave. Only a turn ever fails the reading; anything else leaves no badge.
enum AntigravityCreditsReading: Sendable, Equatable {
    case balance(Double)
    case unavailable
    case unsupportedClient
    case signedOut
}

// MARK: - Classification

/// Pure functions over exit status, stdout and whether stderr showed the sign-in prompt.
enum AntigravityUsageClassifier {
    static let successStatus = "SUCCESS"
    static let authenticationFailurePhrase = "authentication failed"

    /// Nil when the version passes the floor.
    static func classifyVersion(_ output: AntigravityRunOutput?) -> AntigravityCaptureFailure? {
        guard let version = readVersion(output) else { return .transient(.unreadableVersion) }
        return version < AntigravityCLIUsageSource.minimumVersion ? .updateRequired : nil
    }

    static func readVersion(_ output: AntigravityRunOutput?) -> AntigravityVersion? {
        guard let output, output.exitCode == 0, !output.overflowed else { return nil }
        return AntigravityVersion(versionOutput: String(decoding: output.stdout, as: UTF8.self))
    }

    static func showsSignInPrompt(_ stderr: Data) -> Bool {
        var scanner = AntigravitySignInPromptScanner()
        return scanner.scan(stderr)
    }

    static func classifyUsage(_ output: AntigravityRunOutput) -> AntigravityCapture {
        if output.showedSignInPrompt { return .failed(.signedOut) }
        // A started read whose output can't show it cost no turn stops polling, as a turn does.
        if output.overflowed { return .failed(.unsupportedClient) }
        guard let result = decodeResult(output.stdout) else {
            if output.timedOut { return .failed(.transient(.deadline)) }
            guard output.exitCode == 0 else { return .failed(.transient(.unexpectedExit)) }
            return .failed(printedSomething(output.stdout) ? .unsupportedClient : .formatChanged(.output))
        }
        // Checked before the exit status, so a failed turn still stops polling.
        guard result.provesNoTurn else { return .failed(.unsupportedClient) }
        guard result.status == successStatus else {
            let message = result.error?.lowercased() ?? ""
            return .failed(.transient(message.contains(authenticationFailurePhrase) ? .authenticationFailed : .clientError))
        }
        guard let command = result.command else { return .failed(.unsupportedClient) }
        guard command.name == "usage" else { return .failed(.formatChanged(.commandName)) }
        // A client that printed its full answer and then hung still returns it.
        if output.exitCode != 0, !output.timedOut { return .failed(.transient(.unexpectedExit)) }
        guard let payload = decodeLastLine(AntigravityUsageCommandDTO.self, from: output.stdout) else {
            return .failed(.formatChanged(.usageData))
        }
        let buckets = payload.command.data.groups.flatMap(\.buckets).compactMap(bucket)
        guard !buckets.isEmpty else { return .failed(.formatChanged(.usageValues)) }
        return .usage(AntigravityUsage(buckets: buckets, credits: nil))
    }

    static func classifyCredits(_ output: AntigravityRunOutput?) -> AntigravityCreditsReading {
        if output?.showedSignInPrompt == true { return .signedOut }
        guard let output else { return .unavailable }
        if output.overflowed { return .unsupportedClient }
        guard let result = decodeResult(output.stdout) else {
            let unproven = output.exitCode == 0 && !output.timedOut && printedSomething(output.stdout)
            return unproven ? .unsupportedClient : .unavailable
        }
        guard result.provesNoTurn else { return .unsupportedClient }
        guard result.status == successStatus else { return .unavailable }
        guard let command = result.command else { return .unsupportedClient }
        guard command.name == "credits", output.exitCode == 0 || output.timedOut,
              let payload = decodeLastLine(AntigravityCreditsCommandDTO.self, from: output.stdout)
        else { return .unavailable }
        let credits = payload.command.data.remainingCredits
        guard credits.isFinite, !(credits < 0) else { return .unavailable }
        return .balance(credits)
    }

    /// Buckets of an unknown pool or window are skipped rather than guessed into a row, and a
    /// bucket without a finite fraction is absent.
    private static func bucket(_ dto: AntigravityUsageCommandDTO.Bucket) -> AntigravityBucket? {
        guard let id = dto.id, let fraction = dto.remainingFraction, fraction.isFinite else { return nil }
        let pool: AntigravityPool
        if id.hasPrefix("gemini-") {
            pool = .gemini
        } else if id.hasPrefix("3p-") {
            pool = .claudeAndGPT
        } else {
            return nil
        }
        let window: AntigravityWindow
        switch dto.window {
        case "5h": window = .fiveHour
        case "weekly": window = .weekly
        default: return nil
        }
        return AntigravityBucket(
            pool: pool,
            window: window,
            remainingFraction: min(1, max(0, fraction)),
            resetsAt: dto.resetTime.flatMap(DateParsing.iso8601)
        )
    }

    /// Whether stdout holds anything but whitespace. An empty exit-0 answer started nothing.
    static func printedSomething(_ stdout: Data) -> Bool {
        !String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func decodeResult(_ stdout: Data) -> AntigravityResultDTO? {
        decodeLastLine(AntigravityResultDTO.self, from: stdout)
    }

    /// The whole stdout first, then the last non-empty line that decodes, so a line a plugin
    /// prints before the result does not hide it.
    private static func decodeLastLine<T: Decodable>(_ type: T.Type, from stdout: Data) -> T? {
        let decoder = JSONDecoder()
        if let whole = try? decoder.decode(type, from: stdout) { return whole }
        let lines = String(decoding: stdout, as: UTF8.self).split(whereSeparator: \.isNewline)
        for line in lines.reversed() where !line.allSatisfy(\.isWhitespace) {
            if let value = try? decoder.decode(type, from: Data(line.utf8)) { return value }
        }
        return nil
    }
}

// MARK: - CLI

/// The official Antigravity CLI: where to find it and where it runs.
public enum AntigravityCLI {
    public static let executableName = "agy"

    public static func resolveExecutable() -> String? {
        CLIExecutableResolver.resolve(named: executableName, fallbackPaths: fallbackPaths)
    }

    /// A Finder launch has a bare PATH, so these fixed paths still find the binary. Homebrew
    /// installs a plain binary at `/opt/homebrew/bin/agy`.
    static var fallbackPaths: [String] {
        [
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "\(NSHomeDirectory())/.local/bin/agy",
        ]
    }

    /// A Headroom-owned folder, because print mode treats its working folder as the workspace.
    public static var defaultWorkingDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Headroom/AntigravityProbe", isDirectory: true)
    }
}

// MARK: - Source

/// Runs the official client's read-only `/usage` answer, then `/credits`, and returns a typed
/// capture. Every answer must show zero turns and zero tokens, or the source stops spawning
/// the client (see `AntigravityCaptureFailure.unsupportedClient`).
public actor AntigravityCLIUsageSource: AntigravityUsageSource {
    public static let defaultDeadline: TimeInterval = 20
    public static let defaultVersionDeadline: TimeInterval = 10
    /// The version the bucket shape was captured on. The no-turn answer exists from 1.1.11,
    /// but older bucket shapes are unverified.
    public static let minimumVersion = AntigravityVersion(major: 1, minor: 5, patch: 9)

    private struct ExecutableKey: Equatable {
        let path: String
        let modified: Date
    }

    private struct Stop {
        let key: ExecutableKey?
        let version: AntigravityVersion?
    }

    private let resolveExecutable: @Sendable () -> String?
    private let resolveLoginPath: @Sendable () -> String
    private let inheritedEnvironment: @Sendable () -> [String: String]
    private let workingDirectory: String
    private let deadline: TimeInterval
    private let versionDeadline: TimeInterval
    /// Tests only: spawn `interpreter <executable> …` so fake CLIs run as `/bin/sh <script>`
    /// and never hit the "text file busy" race (BUGS.md).
    private let interpreter: String?

    private var resolved: (executable: String, loginPath: String)?
    private var passingVersion: (key: ExecutableKey, version: AntigravityVersion)?
    private var stop: Stop?
    /// Set by a sign-in prompt. Only a user request clears it.
    private var signedOut = false

    public init(
        resolveExecutable: @escaping @Sendable () -> String? = { AntigravityCLI.resolveExecutable() },
        resolveLoginPath: @escaping @Sendable () -> String = {
            CLIExecutableResolver.resolveLoginPath(
                fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            )
        },
        inheritedEnvironment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        workingDirectory: String = AntigravityCLI.defaultWorkingDirectory.path,
        deadline: TimeInterval = AntigravityCLIUsageSource.defaultDeadline,
        versionDeadline: TimeInterval = AntigravityCLIUsageSource.defaultVersionDeadline
    ) {
        self.init(
            resolveExecutable: resolveExecutable,
            resolveLoginPath: resolveLoginPath,
            inheritedEnvironment: inheritedEnvironment,
            workingDirectory: workingDirectory,
            deadline: deadline,
            versionDeadline: versionDeadline,
            interpreter: nil
        )
    }

    init(
        resolveExecutable: @escaping @Sendable () -> String?,
        resolveLoginPath: @escaping @Sendable () -> String,
        inheritedEnvironment: @escaping @Sendable () -> [String: String],
        workingDirectory: String,
        deadline: TimeInterval,
        versionDeadline: TimeInterval,
        interpreter: String?
    ) {
        self.resolveExecutable = resolveExecutable
        self.resolveLoginPath = resolveLoginPath
        self.inheritedEnvironment = inheritedEnvironment
        self.workingDirectory = workingDirectory
        self.deadline = deadline
        self.versionDeadline = versionDeadline
        self.interpreter = interpreter
    }

    public func capture() async -> AntigravityCapture {
        guard let (executable, loginPath) = await resolvedExecutable() else { return .failed(.cliMissing) }
        if signedOut {
            // Every routine read would open another browser sign-in.
            guard UserRequestedProbeContext.isUserRequested else { return .failed(.signedOut) }
            signedOut = false
        }
        var environment = inheritedEnvironment()
        environment["PATH"] = loginPath
        var preparedWorkingDirectory = false

        let key = Self.executableKey(for: executable)
        if let stop {
            passingVersion = nil
            if stop.key == key {
                // Routine polls never spawn a stopped client. A user request runs only the local
                // version print, which is the one way a version swapped behind an unchanged file
                // is noticed.
                guard UserRequestedProbeContext.isUserRequested else { return .failed(.unsupportedClient) }
                let output = await spawn(.version, executable: executable, environment: environment, prepared: &preparedWorkingDirectory)
                guard let version = AntigravityUsageClassifier.readVersion(output), version != stop.version else {
                    return .failed(.unsupportedClient)
                }
                if let key { passingVersion = (key, version) }
            }
            self.stop = nil
        }

        let version: AntigravityVersion
        if let key, let passing = passingVersion, passing.key == key {
            version = passing.version
        } else {
            passingVersion = nil
            let output = await spawn(.version, executable: executable, environment: environment, prepared: &preparedWorkingDirectory)
            guard let read = AntigravityUsageClassifier.readVersion(output) else {
                return .failed(.transient(.unreadableVersion))
            }
            if read < Self.minimumVersion { return .failed(.updateRequired) }
            version = read
            if let key { passingVersion = (key, read) }
        }
        if version < Self.minimumVersion { return .failed(.updateRequired) }

        guard let usageOutput = await spawn(.usage, executable: executable, environment: environment, prepared: &preparedWorkingDirectory) else {
            return .failed(.transient(.spawnFailed))
        }
        let usageCapture = AntigravityUsageClassifier.classifyUsage(usageOutput)
        guard case .usage(let usage) = usageCapture else {
            if usageCapture == .failed(.unsupportedClient) { stop = Stop(key: key, version: version) }
            if usageCapture == .failed(.signedOut) { signedOut = true }
            return usageCapture
        }

        let creditsOutput = await spawn(.credits, executable: executable, environment: environment, prepared: &preparedWorkingDirectory)
        switch AntigravityUsageClassifier.classifyCredits(creditsOutput) {
        case .balance(let credits):
            return .usage(AntigravityUsage(buckets: usage.buckets, credits: credits))
        case .unavailable:
            return usageCapture
        case .unsupportedClient:
            stop = Stop(key: key, version: version)
            return .failed(.unsupportedClient)
        case .signedOut:
            signedOut = true
            return .failed(.signedOut)
        }
    }

    /// Resolution runs a login shell, so a routine poll reuses the last path. A user request
    /// or a path that is no longer executable searches again. A missing CLI is never cached.
    private func resolvedExecutable() async -> (String, String)? {
        if let resolved, !UserRequestedProbeContext.isUserRequested,
           FileManager.default.isExecutableFile(atPath: resolved.executable) {
            return resolved
        }
        resolved = nil
        let resolveExecutable = resolveExecutable
        let resolveLoginPath = resolveLoginPath
        let found: ResolvedLaunch? = await Self.offCooperativePool {
            guard let path = resolveExecutable(), FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            return ResolvedLaunch(executable: path, loginPath: resolveLoginPath())
        }
        guard let found else { return nil }
        resolved = (found.executable, found.loginPath)
        return (found.executable, found.loginPath)
    }

    private struct ResolvedLaunch: Sendable {
        let executable: String
        let loginPath: String
    }

    private static func executableKey(for executable: String) -> ExecutableKey? {
        let target = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: target))?[.modificationDate] as? Date
        else { return nil }
        return ExecutableKey(path: target, modified: modified)
    }

    /// Creates the working directory before the first spawn of a capture, without an existence
    /// check, then runs the command.
    private func spawn(
        _ command: AntigravityCommand,
        executable: String,
        environment: [String: String],
        prepared: inout Bool
    ) async -> AntigravityRunOutput? {
        if !prepared {
            prepared = true
            try? FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
        }
        return await run(command, executable: executable, environment: environment)
    }

    private func run(
        _ command: AntigravityCommand,
        executable: String,
        environment: [String: String]
    ) async -> AntigravityRunOutput? {
        let interpreter = interpreter
        let workingDirectory = workingDirectory
        let deadline = command == .version ? versionDeadline : deadline
        return await Self.offCooperativePool {
            AntigravityProcessRunner.run(
                command,
                executable: executable,
                interpreter: interpreter,
                environment: environment,
                workingDirectory: workingDirectory,
                deadline: deadline
            )
        }
    }

    /// A run blocks for up to the deadline, so it gets its own thread rather than one of Swift's
    /// cooperative threads.
    private static func offCooperativePool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: work()) }
        }
    }
}

/// One spawn of the client through `StdioChildProcess`: its own session, stdin from
/// `/dev/null`, a size cap and a whole-group terminate. Stderr is watched only for the
/// sign-in prompt, which ends the run at once; its bytes are dropped.
enum AntigravityProcessRunner {
    static func run(
        _ command: AntigravityCommand,
        executable: String,
        interpreter: String?,
        environment: [String: String],
        workingDirectory: String,
        deadline: TimeInterval
    ) -> AntigravityRunOutput? {
        let launchPath = interpreter ?? executable
        let arguments = (interpreter.map { [$0, executable] } ?? [executable]) + command.arguments
        guard let process = StdioChildProcess.spawn(
            path: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            stdin: .nullDevice,
            stderr: .watch
        ) else { return nil }
        defer { process.terminate() }

        let end = Date().addingTimeInterval(deadline)
        var output = Data()
        var chunk = Data()
        var overflowed = false
        var errorOpen = true
        var scanner = AntigravitySignInPromptScanner()
        var showedSignInPrompt = false
        // Past the cap the rest is drained and dropped rather than left to fill the pipe.
        while Date() < end, process.readOutput(
            into: &chunk,
            errorOpen: &errorOpen,
            deadline: end,
            onError: { if scanner.scan($0) { showedSignInPrompt = true } }
        ) {
            // The client is now waiting on a browser sign-in it opened; the deferred terminate
            // ends it and anything it started.
            if showedSignInPrompt { break }
            if !overflowed {
                output.append(chunk)
                if output.count > command.sizeCap {
                    overflowed = true
                    output = Data()
                }
            }
            chunk.removeAll(keepingCapacity: true)
        }
        if showedSignInPrompt {
            return AntigravityRunOutput(
                exitCode: nil, stdout: Data(), overflowed: false, timedOut: false, showedSignInPrompt: true
            )
        }
        let exitCode = process.exitCode(within: max(0, end.timeIntervalSinceNow))
        return AntigravityRunOutput(
            exitCode: exitCode,
            stdout: output,
            overflowed: overflowed,
            timedOut: exitCode == nil && !(Date() < end)
        )
    }
}

/// `agy --version` prints a bare `1.5.9`.
public struct AntigravityVersion: Sendable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Anchored at the start of the trimmed output, so a warning line printed first is
    /// unreadable rather than guessed past.
    public init?(versionOutput: String) {
        let text = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.firstMatch(of: /^v?(\d+)\.(\d+)\.(\d+)/),
              let major = Int(match.1), let minor = Int(match.2), let patch = Int(match.3)
        else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
