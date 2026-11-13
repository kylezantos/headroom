import Foundation

// MARK: - Capture

/// One Go window as the official client reported it, already normalised by KTD6: a limited
/// window reads 100% used whatever percentage came with it.
public struct OpenCodeGoWindow: Sendable, Equatable {
    public let percentUsed: Double
    public let isLimited: Bool
    public let resetsAt: Date

    public init(percentUsed: Double, isLimited: Bool, resetsAt: Date) {
        self.percentUsed = percentUsed
        self.isLimited = isLimited
        self.resetsAt = resetsAt
    }
}

/// The three Go windows, by name, never by position (KTD6).
public struct OpenCodeGoUsage: Sendable, Equatable {
    public let rolling: OpenCodeGoWindow
    public let weekly: OpenCodeGoWindow
    public let monthly: OpenCodeGoWindow

    public init(rolling: OpenCodeGoWindow, weekly: OpenCodeGoWindow, monthly: OpenCodeGoWindow) {
        self.rolling = rolling
        self.weekly = weekly
        self.monthly = monthly
    }
}

/// Where a format-changed result came from. Logged by stage only (KTD4): never the output.
public enum OpenCodeFormatStage: String, Sendable, Equatable {
    /// Non-empty stdout that is not the expected JSON, or exit 0 JSON of another shape.
    case usageOutput
    /// The client's own schema check failed ("Decode error" / "Missing key").
    case clientDecode
    /// A Go block whose window has no finite reset or percentage (KTD6).
    case usageValues
    /// More stdout than the read's size cap.
    case outputTooLarge
    /// The client's operation list no longer has `experimental.usage.limits` (KTD4 follow-up).
    case operationMissing
}

/// Why a reading is transient. Typed so diagnostics can count causes without any output.
public enum OpenCodeTransientCause: String, Sendable, Equatable {
    case spawnFailed
    /// `--version` failed, timed out or printed no recognisable version (KTD3).
    case unreadableVersion
    /// The 50-second hard deadline passed (KTD5).
    case deadline
    /// Killed by a signal, or an exit status other than 0 or 1.
    case unexpectedExit
    /// "timed out", "Transport error" or a 5xx from the Console (KTD4).
    case consoleUnavailable
    /// "Location plugins did not finish activating": a refresh or a user plugin took longer
    /// than the client's five-second activation cap (U12).
    case pluginsNotActivated
    /// "Standalone server exited before reporting readiness": the child server died, for
    /// example on a locked database when another client started at the same instant (U12).
    case serverStartFailed
    /// Exit 1 with empty stdout while the operation still exists (KTD4 follow-up), or exit 1
    /// with stdout that is not JSON at all, such as a crash stack from a full disk.
    case clientFailed
    /// The operation-list follow-up itself failed.
    case operationListUnreadable
    /// The `auth list` follow-up after a `data: null` reading failed (exit, deadline, overflow
    /// or undecodable output). Every `--standalone` command can fail transiently (U12), so a
    /// failed list never decides signed out, a permanent state.
    case authListUnreadable
    /// An exit-1 message no rule recognises. Never a sign-in prompt (KTD4).
    case unrecognizedError
}

public enum OpenCodeCaptureFailure: Sendable, Equatable {
    case cliMissing
    case updateRequired
    case signedOut
    case consoleSignInRequired
    case signInExpired
    case formatChanged(OpenCodeFormatStage)
    case transient(OpenCodeTransientCause)

    public var outcome: ProviderSetupOutcome {
        switch self {
        case .cliMissing: .opencodeCLIMissing
        case .updateRequired: .opencodeUpdateRequired
        case .signedOut: .opencodeSignedOut
        case .consoleSignInRequired: .opencodeConsoleSignInRequired
        case .signInExpired: .opencodeSignInExpired
        case .formatChanged: .opencodeFormatChanged
        case .transient: .opencodeTransientCapture
        }
    }

    public var failureReason: FailureReason { .providerSetup(outcome) }
}

/// What one usage read found. It carries the windows and whether the workspace has a Go
/// plan, nothing else: no workspace, URL, label, email, token or raw output (R4, KTD19).
public enum OpenCodeCapture: Sendable, Equatable {
    case goUsage(OpenCodeGoUsage)
    /// A signed-in workspace without Go, or a Console sign-in with no workspace (KTD7, KTD20).
    case noGoPlan
    case failed(OpenCodeCaptureFailure)
}

/// KTD17: the seam U3's provider consumes. One instance serves every account; the home picks
/// which client state the read uses.
public protocol OpenCodeUsageSource: Sendable {
    func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture
    /// KTD8: drop any in-flight read for the home, so the next capture starts a fresh one.
    /// Synchronous, so a removal or reset boundary is in force before the store's next
    /// request can join the old read. Only the capture cache keeps anything to drop.
    func invalidate(home: OpenCodeAccountHome)
}

public extension OpenCodeUsageSource {
    func invalidate(home: OpenCodeAccountHome) {}
}

// MARK: - Commands

/// The closed set of client invocations (R5). No caller can supply an operation ID, a path or
/// any other argument: never `opencode service`, `auth export`, a model request or a login.
enum OpenCodeCommand: CaseIterable, Sendable {
    case version
    case usageLimits
    case authList
    case operationList

    /// KTD2 step 1: everything that talks to the server passes `--standalone`; only the local
    /// version print does not.
    var arguments: [String] {
        switch self {
        case .version: ["--version"]
        case .usageLimits: ["api", "--standalone", "experimental.usage.limits"]
        case .authList: ["auth", "list", "--standalone", "--format", "json"]
        case .operationList: ["api", "--standalone", "GET", "/openapi.json"]
        }
    }

    /// Explicit per read. The usage line and the auth list are a few hundred bytes; the
    /// OpenAPI document is about 350 KB on 2.2.5 (U12), so it gets its own, larger cap.
    var sizeCap: Int {
        switch self {
        case .version: 4_096
        case .usageLimits, .authList: 64 * 1_024
        case .operationList: 4 * 1_024 * 1_024
        }
    }
}

/// What one spawn produced. `exitCode` is nil when the process was still running at the
/// deadline or died on a signal.
struct OpenCodeRunOutput: Sendable, Equatable {
    var exitCode: Int32?
    var stdout: Data
    var overflowed: Bool
    var timedOut: Bool
}

// MARK: - Classification

/// KTD3, KTD4, KTD20 as pure functions over exit status and stdout. Stderr never exists here.
enum OpenCodeUsageClassifier {
    enum UsageStep: Sendable, Equatable {
        case done(OpenCodeCapture)
        /// `data: null`: tell signed out, API key and no-workspace apart (KTD20).
        case needsAuthList
        /// Exit 1, empty stdout: is the operation still there? (KTD4)
        case needsOperationList
    }

    /// The integrations whose connections mean "Console" (KTD20): `opencode` is the Console
    /// itself, `opencode-go` the separate key login OpenCode's own picker lists first.
    static let consoleIntegration = "opencode"
    static let goKeyIntegration = "opencode-go"
    /// An `opencode` connection made by a Console sign-in rather than a pasted key.
    static let consoleSignInMethods: Set<String> = ["oauth", "external"]
    static let usageOperationID = "experimental.usage.limits"
    static let usageOperationPath = "/api/experimental/usage/limits"

    /// U12: the child server died before it was ready (a locked database or a schema-migration
    /// race when another client started at the same instant). Printed as a plain stack on stdout.
    static let serverStartFailurePrefix = "Error: Standalone server exited before reporting readiness"

    /// Nil when the version passes the KTD3 gate.
    static func classifyVersion(_ output: OpenCodeRunOutput?) -> OpenCodeCaptureFailure? {
        guard let output, output.exitCode == 0, !output.overflowed,
              let version = OpenCodeVersion(versionOutput: String(decoding: output.stdout, as: UTF8.self))
        else { return .transient(.unreadableVersion) }
        return version < OpenCodeCLIUsageSource.minimumVersion ? .updateRequired : nil
    }

    /// KTD4's table. Every unmatched case falls to transient stale, never to a sign-in prompt.
    static func classifyUsage(_ output: OpenCodeRunOutput) -> UsageStep {
        if output.overflowed { return .done(.failed(.formatChanged(.outputTooLarge))) }
        let stdout = output.stdout

        switch output.exitCode {
        case 0:
            return classifySuccessLine(stdout)
        case nil where output.timedOut:
            // KTD5: a client that printed its reading and then hung still returns it. Any other
            // output at the deadline is not trusted.
            if let envelope = decodeEnvelope(stdout) { return step(for: envelope) }
            return .done(.failed(.transient(.deadline)))
        case 1:
            return classifyErrorLine(stdout)
        default:
            return .done(.failed(.transient(.unexpectedExit)))
        }
    }

    private static func classifySuccessLine(_ stdout: Data) -> UsageStep {
        guard let envelope = decodeEnvelope(stdout) else { return .done(.failed(.formatChanged(.usageOutput))) }
        return step(for: envelope)
    }

    /// On the built-in home the client loads the user's plugins, and one may print to stdout
    /// before the client's own line. The last non-empty line that decodes as the envelope is
    /// the reading; the whole stdout is tried first, for a client that pretty-prints.
    static func decodeEnvelope(_ stdout: Data) -> OpenCodeUsageEnvelopeDTO? {
        decodeLastLine(OpenCodeUsageEnvelopeDTO.self, from: stdout)
    }

    private static func decodeLastLine<T: Decodable>(_ type: T.Type, from stdout: Data) -> T? {
        let decoder = JSONDecoder()
        if let whole = try? decoder.decode(type, from: stdout) { return whole }
        let lines = String(decoding: stdout, as: UTF8.self).split(whereSeparator: \.isNewline)
        for line in lines.reversed() where !line.allSatisfy(\.isWhitespace) {
            if let value = try? decoder.decode(type, from: Data(line.utf8)) { return value }
        }
        return nil
    }

    private static func step(for envelope: OpenCodeUsageEnvelopeDTO) -> UsageStep {
        guard let data = envelope.data else { return .needsAuthList }
        guard let go = data.go else { return .done(.noGoPlan) }
        guard let usage = go.usage else { return .done(.failed(.formatChanged(.usageValues))) }
        return .done(.goUsage(usage))
    }

    private static func classifyErrorLine(_ stdout: Data) -> UsageStep {
        let text = String(decoding: stdout, as: UTF8.self)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // KTD4: a removed or renamed operation prints only to stderr, which is discarded.
            return .needsOperationList
        }
        if text.hasPrefix(serverStartFailurePrefix) { return .done(.failed(.transient(.serverStartFailed))) }
        if let message = decodeLastLine(OpenCodeErrorDTO.self, from: stdout)?.message {
            return .done(.failed(classifyErrorMessage(message)))
        }
        // JSON of another shape is a changed contract. Anything else (a crash stack from a full
        // disk or a permission error) is the client failing: transient, never "Contact support".
        if (try? JSONSerialization.jsonObject(with: stdout)) != nil {
            return .done(.failed(.formatChanged(.usageOutput)))
        }
        return .done(.failed(.transient(.clientFailed)))
    }

    /// Fixed phrases only, each pinned to a U12 capture. The message itself never leaves here.
    static func classifyErrorMessage(_ message: String) -> OpenCodeCaptureFailure {
        if message.contains("Reconnect OpenCode Console") || message.contains("(401 GET") {
            return .signInExpired
        }
        if message.contains("Location plugins did not finish activating") {
            return .transient(.pluginsNotActivated)
        }
        if message.contains("timed out") || message.contains("Transport error")
            || message.range(of: #"\(5[0-9]{2} "#, options: .regularExpression) != nil {
            return .transient(.consoleUnavailable)
        }
        if message.contains("Decode error") || message.contains("Missing key") {
            return .formatChanged(.clientDecode)
        }
        return .transient(.unrecognizedError)
    }

    /// KTD20, after a `data: null` reading. An `opencode` Console sign-in wins over any stored
    /// key (a sign-in adds a credential and keeps the old key, U12), then any key on either
    /// integration needs a Console sign-in, and otherwise the home is signed out. A failed read
    /// is transient: signed out is a permanent state, and every `--standalone` command can fail
    /// on its own (a child server that died, plugins that did not activate, the deadline).
    static func classifyAuthList(_ output: OpenCodeRunOutput?) -> OpenCodeCapture {
        guard let output, output.exitCode == 0, !output.overflowed,
              let integrations = try? JSONDecoder().decode([OpenCodeAuthIntegrationDTO].self, from: output.stdout)
        else { return .failed(.transient(.authListUnreadable)) }

        let console = integrations.filter { $0.id == consoleIntegration }.flatMap(\.connections)
        if console.contains(where: { connection in
            connection.method.map(consoleSignInMethods.contains) == true || connection.type == "external"
        }) {
            return .noGoPlan
        }
        let goKey = integrations.filter { $0.id == goKeyIntegration }.flatMap(\.connections)
        return console.isEmpty && goKey.isEmpty ? .failed(.signedOut) : .failed(.consoleSignInRequired)
    }

    /// KTD4's follow-up after an exit-1, empty-stdout read. The client resolves operation names
    /// from this same document, so the operation exists when either its path or its ID is there.
    static func classifyOperationList(_ output: OpenCodeRunOutput?) -> OpenCodeCapture {
        guard let output, output.exitCode == 0, !output.overflowed,
              let document = try? JSONSerialization.jsonObject(with: output.stdout) as? [String: Any],
              let paths = document["paths"] as? [String: Any]
        else { return .failed(.transient(.operationListUnreadable)) }

        if paths[usageOperationPath] != nil { return .failed(.transient(.clientFailed)) }
        let operationIDs = paths.values
            .compactMap { $0 as? [String: Any] }
            .flatMap(\.values)
            .compactMap { ($0 as? [String: Any])?["operationId"] as? String }
        return operationIDs.contains(usageOperationID)
            ? .failed(.transient(.clientFailed))
            : .failed(.formatChanged(.operationMissing))
    }

    /// KTD3: after a deadline, an overflow or stdout that is not JSON at all, the version is
    /// checked again on the next run.
    static func clearsVersionMemo(_ output: OpenCodeRunOutput) -> Bool {
        if output.timedOut || output.overflowed { return true }
        let trimmed = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Plugin text before a readable envelope is not another client.
        if decodeEnvelope(output.stdout) != nil { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) == nil
    }
}

// MARK: - Source

/// Runs the official client's own usage read (KTD1) for one account home and returns a typed
/// capture. Only the OpenCode lane calls it (KTD8). One instance serves every account, so the
/// resolved executable, the login PATH and the version memo are shared.
public actor OpenCodeCLIUsageSource: OpenCodeUsageSource {
    /// KTD5: a run can spend a long time refreshing an OAuth token, and killing a short-lived
    /// CLI mid-refresh is how Claude's `auth status` preflight abandoned renewals, so a run is
    /// never ended early. Past this, its process group is terminated.
    public static let defaultDeadline: TimeInterval = 50
    public static let defaultVersionDeadline: TimeInterval = 10
    /// KTD3: 1.x falls through to the TUI on `opencode api …`, and 2.0–2.1 have no usage read.
    public static let minimumVersion = OpenCodeVersion(major: 2, minor: 2, patch: 0)

    private struct VersionMemoKey: Equatable {
        let path: String
        let modified: Date
    }

    private let resolveExecutable: @Sendable () -> String?
    private let resolveLoginPath: @Sendable () -> String
    private let inheritedEnvironment: @Sendable () -> [String: String]
    private let workingDirectory: String
    private let deadline: TimeInterval
    private let versionDeadline: TimeInterval
    /// Tests only: spawn `interpreter <executable> …` so fake CLIs run as `/bin/sh <script>`
    /// and never hit the "text file busy" race (KTD17, BUGS.md).
    private let interpreter: String?

    private var resolved: (executable: String, loginPath: String)?
    private var passingVersion: VersionMemoKey?
    /// The binary last read as below the floor. A 1.x `--version` is not side-effect free (it
    /// appends to the user's real log and can reset `~/.cache/opencode`), so an unchanged
    /// too-old binary is not asked again on a timer poll. A user request always asks again,
    /// which is the only way a version-manager shim that swaps the version behind an
    /// unchanged file is noticed.
    private var tooOldVersion: VersionMemoKey?

    public init(
        resolveExecutable: @escaping @Sendable () -> String? = { OpenCodeCLI.resolveExecutable() },
        resolveLoginPath: @escaping @Sendable () -> String = {
            CLIExecutableResolver.resolveLoginPath(
                fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            )
        },
        inheritedEnvironment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        workingDirectory: String = OpenCodeCLI.defaultWorkingDirectory.path,
        deadline: TimeInterval = OpenCodeCLIUsageSource.defaultDeadline,
        versionDeadline: TimeInterval = OpenCodeCLIUsageSource.defaultVersionDeadline
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

    public func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        guard let (executable, loginPath) = await resolvedExecutable() else { return .failed(.cliMissing) }
        let environment = OpenCodeCLI.environment(inherited: inheritedEnvironment(), home: home, loginPath: loginPath)
        try? FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)

        let memoKey = Self.memoKey(for: executable)
        if let memoKey, memoKey == tooOldVersion, !UserRequestedProbeContext.isUserRequested {
            return .failed(.updateRequired)
        }
        if memoKey == nil || memoKey != passingVersion {
            passingVersion = nil
            tooOldVersion = nil
            let version = await run(.version, executable: executable, environment: environment)
            if let failure = OpenCodeUsageClassifier.classifyVersion(version) {
                // An unreadable version stays unmemoized: it is transient by definition.
                if failure == .updateRequired { tooOldVersion = memoKey }
                return .failed(failure)
            }
            passingVersion = memoKey
        }

        guard let usage = await run(.usageLimits, executable: executable, environment: environment) else {
            return .failed(.transient(.spawnFailed))
        }
        // KTD3: a shim can swap the version behind the same path, so anything that looks like
        // another client re-checks the version next time.
        if OpenCodeUsageClassifier.clearsVersionMemo(usage) { passingVersion = nil }

        switch OpenCodeUsageClassifier.classifyUsage(usage) {
        case .done(let capture):
            return capture
        case .needsAuthList:
            // KTD20: not memoized, so a Terminal sign-in or sign-out shows at the next poll.
            let list = await run(.authList, executable: executable, environment: environment)
            return OpenCodeUsageClassifier.classifyAuthList(list)
        case .needsOperationList:
            let list = await run(.operationList, executable: executable, environment: environment)
            return OpenCodeUsageClassifier.classifyOperationList(list)
        }
    }

    /// Resolution runs a login shell, so a routine poll reuses the last path (KTD3). A user
    /// request (Check Now, setup) or a path that is no longer executable searches again, so an
    /// install or a move is noticed. A missing CLI is never cached.
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

    private static func memoKey(for executable: String) -> VersionMemoKey? {
        let target = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: target))?[.modificationDate] as? Date
        else { return nil }
        return VersionMemoKey(path: target, modified: modified)
    }

    private func run(
        _ command: OpenCodeCommand,
        executable: String,
        environment: [String: String]
    ) async -> OpenCodeRunOutput? {
        let interpreter = interpreter
        let workingDirectory = workingDirectory
        let deadline = command == .version ? versionDeadline : deadline
        return await Self.offCooperativePool {
            OpenCodeProcessRunner.run(
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

/// One spawn of the client through `StdioChildProcess`, following `CLIVersionReader.runVersion`:
/// its own session, stdin from `/dev/null`, stderr discarded, a size cap and a whole-group
/// terminate.
enum OpenCodeProcessRunner {
    static func run(
        _ command: OpenCodeCommand,
        executable: String,
        interpreter: String?,
        environment: [String: String],
        workingDirectory: String,
        deadline: TimeInterval
    ) -> OpenCodeRunOutput? {
        let launchPath = interpreter ?? executable
        let arguments = (interpreter.map { [$0, executable] } ?? [executable]) + command.arguments
        guard let process = StdioChildProcess.spawn(
            path: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            // Nothing is ever written to the client, and the QA script runs it the same way.
            stdin: .nullDevice
        ) else { return nil }
        defer { process.terminate() }

        let end = Date().addingTimeInterval(deadline)
        var output = Data()
        var chunk = Data()
        var overflowed = false
        // Until end of file. Past the cap the rest is drained and dropped rather than left to
        // fill the pipe, so the client still finishes on its own (KTD5: never killed early).
        while Date() < end, process.readOutput(into: &chunk, deadline: end) {
            if !overflowed {
                output.append(chunk)
                if output.count > command.sizeCap {
                    overflowed = true
                    output = Data()
                }
            }
            chunk.removeAll(keepingCapacity: true)
        }
        let exitCode = process.exitCode(within: max(0, end.timeIntervalSinceNow))
        return OpenCodeRunOutput(
            exitCode: exitCode,
            stdout: output,
            overflowed: overflowed,
            timedOut: exitCode == nil && !(Date() < end)
        )
    }
}

/// `opencode --version` in either captured form: `opencode v2.2.5` or a bare `1.1.53` (KTD3).
public struct OpenCodeVersion: Sendable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// KTD3's pattern `^(?:opencode )?v?(\d+)\.(\d+)\.(\d+)`, anchored at the start of the
    /// trimmed output, so a warning line printed first is unreadable rather than guessed past.
    public init?(versionOutput: String) {
        let text = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.firstMatch(of: /^(?:opencode )?v?(\d+)\.(\d+)\.(\d+)/),
              let major = Int(match.1), let minor = Int(match.2), let patch = Int(match.3)
        else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

// MARK: - Capture cache

/// KTD8: coalesces in-flight captures per account home, so a user request during a timer probe
/// joins it instead of starting a second client. It keeps no finished result: one provider on
/// one serial lane is the only consumer, unlike Cursor's cache.
public actor OpenCodeUsageCaptureCache: OpenCodeUsageSource {
    private struct Entry {
        let id: UUID
        let generation: UInt64
        let task: Task<OpenCodeCapture, Never>
    }

    /// Per-home invalidation counters, outside the actor so `invalidate` is synchronous: the
    /// boundary holds from the moment the store draws it (KTD8).
    private final class Generations: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [OpenCodeAccountHome: UInt64] = [:]
        func current(_ home: OpenCodeAccountHome) -> UInt64 { lock.withLock { values[home, default: 0] } }
        func advance(_ home: OpenCodeAccountHome) { lock.withLock { values[home, default: 0] &+= 1 } }
    }

    private let source: any OpenCodeUsageSource
    private var inFlight: [OpenCodeAccountHome: Entry] = [:]
    private nonisolated let generations = Generations()

    public init(source: any OpenCodeUsageSource) {
        self.source = source
    }

    public func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        let generation = generations.current(home)
        // An entry from before an invalidation is never joined; it finishes on its own.
        if let entry = inFlight[home], entry.generation == generation { return await entry.task.value }
        let id = UUID()
        let source = source
        let task = Task { await source.capture(home: home) }
        inFlight[home] = Entry(id: id, generation: generation, task: task)
        let result = await task.value
        // A removal or reset may have dropped this entry and a newer capture taken its place.
        if inFlight[home]?.id == id { inFlight[home] = nil }
        return result
    }

    /// Account removal and `invalidateUsageForAccountReset` call this (through
    /// `UsageProvider.invalidateInFlightUsage`), so the next capture for the home starts a
    /// fresh read rather than joining one that began before the change.
    public nonisolated func invalidate(home: OpenCodeAccountHome) {
        generations.advance(home)
    }
}
