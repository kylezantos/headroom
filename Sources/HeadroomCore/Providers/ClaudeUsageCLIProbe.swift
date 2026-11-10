import Foundation
import Darwin

/// The source of Claude usage text — injected so the provider can be tested with a
/// fixture panel instead of spawning the real CLI.
public protocol ClaudeUsageSource: Sendable {
    /// Returns the ANSI-stripped text of Claude Code's `/usage` panel, or nil when the
    /// CLI is missing / not logged in / the capture failed.
    func capturePanel() async -> ClaudePanelResult
}

/// Outcome of a capture attempt — lets the provider distinguish "no CLI" from a
/// transient read failure so it can show the right degrade message.
public enum ClaudePanelResult: Sendable, Equatable {
    /// `text` is the captured usage report (interactive panel or print-mode report).
    /// `planHint` is optional metadata supplied by a source. Routine CLI captures
    /// omit it rather than launching an additional auth command for a plan label.
    case panel(text: String, planHint: String?)
    /// The CLI booted into a first-run screen (theme picker / login-method selector) —
    /// this config home has no signed-in account. Typed here, at the layer that saw
    /// the screen, so the provider never re-derives it from marker strings.
    case loginRequired
    case workspaceTrustRequired
    /// Claude booted into a recognized one-time startup question (the Chrome onboarding)
    /// before its prompt. Like `unknownUI` the probe sends no input; unlike it, the
    /// screen is named so the card can say what is waiting.
    case startupQuestion
    /// Claude presented a surface Headroom does not positively recognize. The probe
    /// fails closed and sends no input.
    case unknownUI
    case cliNotFound
    case cliInconclusive(CLIExecutableDiscoveryIssue)
    case transientCapture
}

public enum ClaudeBootState: Sendable, Equatable {
    case ready
    case loginRequired
    case trustRequired
    case startupQuestion
    case unknown
    case noOutput
}

/// Retained for source compatibility; routine capture no longer probes auth status.
public enum ClaudeAuthStatus: Sendable, Equatable {
    case loggedIn
    case loggedOut
    case unsupported
}

/// Whether the resolved CLI can be handed the sign-in command (`ClaudeUsageCLIProbe
/// .signInSupport`). Three answers, because "too old" and "unreadable" take opposite
/// branches at staging.
public enum ClaudeCLISignInSupport: Sendable, Equatable {
    case supported
    case tooOld
    case unreadable
}

/// Drives the interactive `claude` CLI in a pseudo-terminal, sends `/usage`, and
/// returns the rendered panel text. This is the compliant path to the real 5-hour /
/// weekly windows: the official client makes the request (a free status fetch, no model
/// call), and this only reads what it prints.
///
/// Robustness is the whole point here — a TUI scrape is inherently fragile, so every
/// failure mode is contained: a hard wall-clock deadline, a guaranteed process-group
/// kill in all exit paths, "quiet-period" capture that survives the panel's multiple
/// re-renders, and login-shell PATH resolution so it finds `claude` even when launched
/// from Finder with a bare environment.
public struct ClaudeUsageCLIProbe: ClaudeUsageSource {
    public let locator: any CLIExecutableLocating
    public let workingDirectory: String
    /// Extra environment applied over the inherited env — how additional accounts
    /// route the CLI at their own config home (`CLAUDE_CONFIG_DIR`). Empty for the
    /// built-in account, which uses the user's default `~/.claude` login.
    public let environmentOverrides: [String: String]
    public let bootTimeout: TimeInterval
    public let panelTimeout: TimeInterval
    /// Deadline for `claude -p "/usage"`. A run that hits it is retried once with
    /// `printRetryTimeout` before the PTY fallback (see `runPrintUsage`).
    public let printTimeout: TimeInterval
    public let printRetryTimeout: TimeInterval

    public init(
        locator: any CLIExecutableLocating = CLIExecutableLocator.claude(),
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environmentOverrides: [String: String] = [:],
        bootTimeout: TimeInterval = 30,
        panelTimeout: TimeInterval = 26,
        printTimeout: TimeInterval = 20,
        printRetryTimeout: TimeInterval = 40
    ) {
        self.locator = locator
        self.workingDirectory = workingDirectory
        self.environmentOverrides = environmentOverrides
        self.bootTimeout = bootTimeout
        self.panelTimeout = panelTimeout
        self.printTimeout = printTimeout
        self.printRetryTimeout = printRetryTimeout
    }

    public func capturePanel() async -> ClaudePanelResult {
        await captureWithTrace().result
    }

    /// The capture plus a redaction-safe record of which stage decided it, for
    /// `--probe-claude`. One stale message used to cover several different failures
    /// (Brief 02); the trace names the stage without carrying any CLI output.
    public func captureWithTrace() async -> (result: ClaudePanelResult, trace: ClaudeCaptureTrace) {
        var trace = ClaudeCaptureTrace()
        for attempt in 0...1 {
            let location = await locator.locate()
            switch location {
            case .confirmedAbsent:
                return (.cliNotFound, trace)
            case .inconclusive(let issue):
                return (.cliInconclusive(issue), trace)
            case .available(let claudePath, _):
                let (result, attemptTrace) = await capture(at: claudePath)
                trace = attemptTrace
                switch result {
                case .result(let panel):
                    return (panel, trace)
                case .launchNotFound where attempt == 0:
                    await locator.invalidate(path: claudePath, reason: .launchNotFound)
                case .launchNotFound:
                    return (.cliInconclusive(.launchRace), trace)
                }
            }
        }
        return (.cliInconclusive(.launchRace), trace)
    }

    private func capture(at claudePath: String) async -> (ExecutableCaptureResult, ClaudeCaptureTrace) {
        // Run the blocking process and pty work off the cooperative pool.
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread { [environmentOverrides, printTimeout, printRetryTimeout] in
                var trace = ClaudeCaptureTrace()
                // Session-reliability KTD2: auth status can start renewal and exit
                // before persisting it. Usage itself supplies the recognized state.
                // Print-first capture: `claude -p "/usage"` writes the settled report
                // in one shot — no TUI repaints to garble labels and no partial paint
                // for the separately fetched model rows, which is the failure class
                // that intermittently dropped "Weekly (Fable)". Any miss (old CLI,
                // unparseable output, a timeout after its one retry) falls back to the
                // PTY panel, which carries the Remote Control opt-out.
                let print = Self.runPrintUsage(
                    claudePath: claudePath,
                    workingDirectory: workingDirectory,
                    environmentOverrides: environmentOverrides,
                    deadline: printTimeout,
                    retryDeadline: printRetryTimeout
                )
                trace.print = print.stage
                trace.printRetry = print.retryStage
                switch print.result {
                case .report(let report):
                    continuation.resume(returning: (.result(.panel(text: report, planHint: nil)), trace))
                    return
                case .loginRequired:
                    continuation.resume(returning: (.result(.loginRequired), trace))
                    return
                case .launchNotFound:
                    continuation.resume(returning: (.launchNotFound, trace))
                    return
                case .unavailable:
                    break
                }
                let arguments = Self.interactiveArguments(
                    claudePath: claudePath,
                    versionOutput: print.versionOutput
                )
                trace.ptyRemoteControlOptOut = arguments.contains("--settings")
                let (result, boot) = Self.runBlocking(
                    claudePath: claudePath,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environmentOverrides: environmentOverrides,
                    boot: bootTimeout,
                    panel: panelTimeout
                )
                trace.ptyBoot = boot.stage
                trace.ptyBootFingerprint = boot.fingerprint
                trace.ptyPanel = boot.panel
                continuation.resume(returning: (result, trace))
            }
        }
    }

    /// The user's real PATH via a login shell, so a Finder-launched app (bare PATH)
    /// still resolves node/nvm the way the terminal does. Falls back to a sane default.
    private static func loginPath() -> String {
        let fallback = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return CLIExecutableResolver.resolveLoginPath(fallback: fallback)
    }

    private enum ExecutableCaptureResult: Sendable {
        case result(ClaudePanelResult)
        case launchNotFound
    }

    private enum PrintUsageResult: Sendable {
        case report(String)
        case loginRequired
        case unavailable
        case launchNotFound
    }

    private struct PrintAttempt: Sendable {
        var result: PrintUsageResult
        var stage: ClaudePrintStage
        var retryStage: ClaudePrintStage? = nil
        /// Raw `--version` text, kept in memory only to choose the PTY's flags. It
        /// never reaches the trace.
        var versionOutput: String? = nil
    }

    private struct BootOutcome: Sendable {
        var stage: ClaudePTYBootStage
        var fingerprint: ClaudeBootFingerprint? = nil
        var panel: ClaudePTYPanelStage? = nil
    }

    private enum ProcessOutputResult: Sendable {
        case data(Data)
        case failed
        /// The deadline passed and the process was killed. Carries whatever stdout it
        /// had already written: some CLIs print the whole report, then hang on shutdown.
        case timedOut(partial: Data)
        case launchNotFound
    }

    /// Gate for the print-first capture. 2.1.217 is the oldest CLI verified to run
    /// `/usage` locally under `-p`; an unverified older build could forward it to the
    /// model as a prompt — spending real usage every poll — so anything below the
    /// floor (or unparseable) stays on the PTY path.
    public static func printUsageSupported(versionOutput: String) -> Bool {
        guard let version = parsedVersion(versionOutput) else { return false }
        return version >= (2, 1, 217)
    }

    /// KTD4 (2026-09-19 sign-in plan): the sign-in handoff's own floor, separate from
    /// `ClaudeCLIVersionBand` because that enum is printed by the redaction-safe
    /// diagnostic. A readable version below 2.1.41 blocks the handoff (R6) — those CLIs
    /// have not passed the supported sign-in contract — while an unreadable one
    /// keeps today's interactive launch, so a change
    /// to the CLI's version format cannot lock every user out of sign-in. Pure over the
    /// already-captured `--version` string: probing by running the subcommand risks an
    /// older CLI taking `auth login` as a paid model prompt.
    public static func signInSupport(versionOutput: String) -> ClaudeCLISignInSupport {
        guard let version = parsedVersion(versionOutput) else { return .unreadable }
        return version >= (2, 1, 41) ? .supported : .tooOld
    }

    /// KTD4 (2026-09-19 sign-in plan): the raw `--version` output, off the main actor, for
    /// callers that apply more than one floor to it — the sign-in handoff reads both
    /// `signInSupport` and `printUsageSupported` from a single capture. Nil when the CLI
    /// could not be launched or did not exit cleanly.
    public static func versionOutput(
        executablePath: String,
        environmentOverrides: [String: String] = [:]
    ) async -> String? {
        await Task.detached(priority: .utility) {
            switch runForOutput(
                claudePath: executablePath,
                arguments: ["--version"],
                environmentOverrides: environmentOverrides,
                deadline: 5
            ) {
            case .launchNotFound, .failed, .timedOut:
                return nil
            case .data(let data):
                return String(decoding: data, as: UTF8.self)
            }
        }.value
    }

    public static func versionBand(
        executablePath: String,
        environmentOverrides: [String: String] = [:]
    ) async -> ClaudeCLIVersionBand {
        guard let output = await versionOutput(
            executablePath: executablePath,
            environmentOverrides: environmentOverrides
        ) else { return .unknown }
        return classifyVersionBand(output)
    }

    static func classifyVersionBand(_ versionOutput: String) -> ClaudeCLIVersionBand {
        guard let version = parsedVersion(versionOutput) else { return .unknown }
        return version >= (2, 1, 217) ? .printSupported : .ptyFallback
    }

    private static func parsedVersion(_ output: String) -> (Int, Int, Int)? {
        guard let match = output.firstMatch(of: /(\d+)\.(\d+)\.(\d+)/),
              let major = Int(match.1),
              let minor = Int(match.2),
              let patch = Int(match.3)
        else { return nil }
        return (major, minor, patch)
    }

    /// The print-mode invocation. Deliberately left without the Remote Control opt-out:
    /// it is every user's hot path, the docs tie auto-connect to interactive processes,
    /// and a CLI that rejected an extra flag here would stop all Claude polling.
    static let printUsageArguments = ["-p", "/usage", "--no-session-persistence"]

    /// Per-launch opt-out for the PTY fallback (Brief 03). With Remote Control
    /// auto-connect on, every interactive `claude` registers a session at claude.ai/code,
    /// so each fallback probe used to leave a stray one. `--settings` applies to that
    /// process only and writes no file. `disableRemoteControl` refuses auto-start
    /// whatever turned it on; `remoteControlAtStartup: false` outranks a user-scope `true`.
    static let remoteControlOptOutSettings = #"{"disableRemoteControl":true,"remoteControlAtStartup":false}"#

    /// The interactive launch's argv. Inline-JSON `--settings` was verified in CLI 1.0.90,
    /// 1.0.128, 2.0.77, 2.1.216 and 2.1.303, whose settings schemas all keep unknown keys
    /// (passthrough); 1.0.50 has no such flag and would exit on it. A readable version
    /// below 1.0.90 therefore launches bare. An unreadable version keeps the opt-out: in
    /// practice that is a slow or reformatted current CLI, the kind that can auto-connect.
    public static func interactiveArguments(claudePath: String, versionOutput: String?) -> [String] {
        if let versionOutput, let version = parsedVersion(versionOutput), version < (1, 0, 90) {
            return [claudePath]
        }
        return [claudePath, "--settings", remoteControlOptOutSettings]
    }

    /// One-shot non-interactive capture: `claude -p "/usage"` prints the full settled
    /// usage report (same compliant principle — the official client makes the request,
    /// this reads its stdout). Returns nil unless the output parses into at least one
    /// usage window, so a cost report, an error, or model chatter can never be
    /// mistaken for the panel.
    ///
    /// A run that hits its deadline gets one retry with a longer one before the PTY. The
    /// usual cause is a cold start (just updated, slow network), which the interactive
    /// fallback would meet too, only slower and as an interactive session. Unparseable
    /// output is not retried: the same CLI would print the same thing.
    private static func runPrintUsage(
        claudePath: String,
        workingDirectory: String,
        environmentOverrides: [String: String],
        deadline: TimeInterval,
        retryDeadline: TimeInterval
    ) -> PrintAttempt {
        let versionText: String
        switch runForOutput(
            claudePath: claudePath,
            arguments: ["--version"],
            environmentOverrides: environmentOverrides,
            deadline: 5
        ) {
        case .launchNotFound: return PrintAttempt(result: .launchNotFound, stage: .launchFailed)
        case .failed, .timedOut: return PrintAttempt(result: .unavailable, stage: .versionUnavailable)
        case .data(let data): versionText = String(decoding: data, as: UTF8.self)
        }
        guard parsedVersion(versionText) != nil else {
            return PrintAttempt(result: .unavailable, stage: .versionUnreadable, versionOutput: versionText)
        }
        guard printUsageSupported(versionOutput: versionText) else {
            return PrintAttempt(result: .unavailable, stage: .versionBelowFloor, versionOutput: versionText)
        }
        let first = runPrintReport(
            claudePath: claudePath,
            workingDirectory: workingDirectory,
            environmentOverrides: environmentOverrides,
            deadline: deadline
        )
        var attempt = PrintAttempt(result: first.result, stage: first.stage, versionOutput: versionText)
        guard first.stage == .timedOut else { return attempt }
        let retry = runPrintReport(
            claudePath: claudePath,
            workingDirectory: workingDirectory,
            environmentOverrides: environmentOverrides,
            deadline: retryDeadline
        )
        attempt.result = retry.result
        attempt.retryStage = retry.stage
        return attempt
    }

    private static func runPrintReport(
        claudePath: String,
        workingDirectory: String,
        environmentOverrides: [String: String],
        deadline: TimeInterval
    ) -> (result: PrintUsageResult, stage: ClaudePrintStage) {
        let data: Data
        switch runForOutput(
            claudePath: claudePath,
            arguments: printUsageArguments,
            environmentOverrides: environmentOverrides,
            workingDirectory: workingDirectory,
            deadline: deadline
        ) {
        case .launchNotFound: return (.launchNotFound, .launchFailed)
        case .failed: return (.unavailable, .launchFailed)
        case .timedOut(let partial):
            // A CLI that printed the whole report and then hung on shutdown (hooks, MCP,
            // the upstream exit limitation) needs no retry and no PTY: every extra
            // launch is one more process that can be killed mid-renewal.
            switch classifyPrintOutput(partial) {
            case .report(let text): return (.report(text), .timedOutAfterReport)
            case .loginRequired: return (.loginRequired, .signedOut)
            default: return (.unavailable, .timedOut)
            }
        case .data(let value): data = value
        }
        switch classifyPrintOutput(data) {
        case .report(let text): return (.report(text), .report)
        case .loginRequired: return (.loginRequired, .signedOut)
        default: return (.unavailable, .unparseable)
        }
    }

    private static func classifyPrintOutput(_ data: Data) -> PrintUsageResult {
        let text = ANSI.strip(String(decoding: data, as: UTF8.self))
        if isSignedOutOutput(text) { return .loginRequired }
        return ClaudeUsageParser.parse(text).isEmpty ? .unavailable : .report(text)
    }

    /// Spawn `claude` with pipes (no pty), enforce a hard deadline, and return stdout.
    /// A timeout returns what the process had already written, tagged as such, so the
    /// caller decides whether it is usable. Output is read after exit, which is safe
    /// for these small reports; a pathological giant write would stall the child into
    /// the deadline kill and degrade the same way.
    private static func runForOutput(
        claudePath: String,
        arguments: [String],
        environmentOverrides: [String: String],
        workingDirectory: String? = nil,
        deadline seconds: TimeInterval
    ) -> ProcessOutputResult {
        let process = Process()
        let output = Pipe()
        let cwd = workingDirectory ?? FileManager.default.currentDirectoryPath
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = environment(
            inherited: ProcessInfo.processInfo.environment,
            overrides: environmentOverrides,
            loginPath: loginPath(),
            workingDirectory: cwd
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            let nsError = error as NSError
            return (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
                || !FileManager.default.fileExists(atPath: claudePath)
                ? .launchNotFound
                : .failed
        }

        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline { usleep(20_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return .timedOut(partial: drainWithoutBlocking(output.fileHandleForReading))
        }
        process.waitUntilExit()
        return .data(drainWithoutBlocking(output.fileHandleForReading))
    }

    /// Everything already in the pipe, without waiting for EOF. A process the CLI started
    /// (a hook, an MCP server) can outlive it and keep the write end open, which would
    /// block `readDataToEndOfFile()` past every deadline. Once the CLI has exited, all
    /// of its own output is already buffered, so stopping at "would block" loses none.
    static func drainWithoutBlocking(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return Data() }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(descriptor, &chunk, chunk.count)
            if count > 0 {
                data.append(contentsOf: chunk[0..<count])
            } else if count < 0, errno == EINTR {
                continue
            } else {
                break // EOF, or EAGAIN while another process holds the write end
            }
        }
        return data
    }

    // MARK: pty mechanics

    private static func runBlocking(
        claudePath: String,
        arguments argv: [String],
        workingDirectory: String,
        environmentOverrides: [String: String],
        boot: TimeInterval,
        panel: TimeInterval
    ) -> (ExecutableCaptureResult, BootOutcome) {
        var master: Int32 = -1
        var slave: Int32 = -1
        var win = winsize(ws_row: 45, ws_col: 140, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &win) == 0 else {
            return (.result(.transientCapture), BootOutcome(stage: .spawnFailed))
        }

        var fileActions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&fileActions)
        // Darwin exposed the chdir spawn action as `_np` from macOS 10.15 through
        // Sequoia, then standardized the unsuffixed symbol in Tahoe. Keep the working
        // directory as a spawn action on both paths so the child never races a
        // process-wide chdir and Finder-launched probes retain their stable workspace.
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&fileActions, workingDirectory)
        } else {
            posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
        }
        posix_spawn_file_actions_adddup2(&fileActions, slave, 0)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 2)
        posix_spawn_file_actions_addclose(&fileActions, master)

        var attr = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attr)
        // New session so the child leads its own process group (clean group-kill) and
        // the pty becomes its controlling terminal — the TUI needs a tty to render.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        // Inherit the user's environment (so a node-based `claude` shim finds `node`),
        // augmenting PATH via the login shell, and force a real TERM for TUI rendering.
        var envDict = environment(
            inherited: ProcessInfo.processInfo.environment,
            overrides: environmentOverrides,
            loginPath: loginPath(),
            workingDirectory: workingDirectory
        )
        envDict["TERM"] = "xterm-256color"
        envDict["COLUMNS"] = "140"
        envDict["LINES"] = "45"
        // The interactive counterpart of `--no-session-persistence` (documented in the
        // Claude Code environment-variable reference): probe launches add nothing to the
        // user's prompt history or `--resume` list. Unknown to older CLIs, and harmless.
        envDict["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
        let env = envDict.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let cEnv = env.map { strdup($0) } + [nil]
        let cArgv = argv.map { strdup($0) } + [nil]
        defer {
            cEnv.forEach { free($0) }
            cArgv.forEach { free($0) }
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attr)
        }

        let spawnResult = posix_spawn(&pid, claudePath, &fileActions, &attr, cArgv, cEnv)
        close(slave)
        guard spawnResult == 0 else {
            close(master)
            let outcome = BootOutcome(stage: .spawnFailed)
            return (spawnResult == ENOENT ? .launchNotFound : .result(.transientCapture), outcome)
        }

        // Guaranteed teardown regardless of how we leave.
        func teardown() {
            _ = write(master, "\u{03}", 1) // Ctrl-C
            kill(-pid, SIGTERM)
            // Reap with a short grace period, then SIGKILL.
            var status: Int32 = 0
            for _ in 0..<50 {
                if waitpid(pid, &status, WNOHANG) == pid { break }
                usleep(20_000)
            }
            kill(-pid, SIGKILL)
            waitpid(pid, &status, 0)
            close(master)
        }

        var buffer = Data()
        drain(master: master, maxSeconds: boot, quiet: 2.5, into: &buffer) // boot + prompt
        let bootText = ANSI.strip(String(decoding: buffer, as: UTF8.self))
        switch classifyBootText(bootText) {
        case .ready:
            break
        case .loginRequired:
            teardown()
            return (.result(.loginRequired), BootOutcome(stage: .loginRequired))
        case .trustRequired:
            teardown()
            return (.result(.workspaceTrustRequired), BootOutcome(stage: .trustRequired))
        case .startupQuestion:
            teardown()
            return (.result(.startupQuestion), BootOutcome(stage: .startupQuestion))
        case .unknown:
            teardown()
            let fingerprint = ClaudeBootFingerprint(rawByteCount: buffer.count, strippedText: bootText)
            return (.result(.unknownUI), BootOutcome(stage: .unrecognized, fingerprint: fingerprint))
        case .noOutput:
            teardown()
            return (.result(.transientCapture), BootOutcome(stage: .noOutput))
        }
        usleep(800_000) // let the input box settle before typing
        _ = "/usage".withCString { write(master, $0, strlen($0)) }
        usleep(500_000) // gap so the slash-command autocomplete resolves before Enter
        // Claude Code 2.1.200 can consume the first Enter to accept the `/usage`
        // autocomplete row; the second Enter executes the accepted command.
        _ = "\r".withCString { write(master, $0, strlen($0)) }
        usleep(250_000)
        _ = "\r".withCString { write(master, $0, strlen($0)) }
        // Longer quiet window than boot: the panel renders the primary limits first, then
        // pauses to compute the model-specific weekly sub-limits ("Current week (Fable)")
        // before painting the settled panel. On a cold start (e.g. right after an app
        // update) that pause can exceed a short quiet window, so a 2.5s drain concluded
        // before the sub-limit line rendered — the parser needs the clean line, so Fable
        // went missing until the next poll. 4s bridges that settle pause.
        drain(master: master, maxSeconds: panel, quiet: 4.0, into: &buffer) // the panel
        teardown()

        let captured = ANSI.strip(String(decoding: buffer, as: UTF8.self))
        if isSignedOutOutput(captured) {
            return (.result(.loginRequired), BootOutcome(stage: .ready, panel: .signedOut))
        }
        guard !captured.isEmpty else {
            return (.result(.transientCapture), BootOutcome(stage: .ready, panel: .empty))
        }
        // The result is unchanged either way (the provider types an unparseable panel as
        // a transient capture); the stage only lets the trace name the failure.
        let panelStage: ClaudePTYPanelStage = ClaudeUsageParser.parse(captured).isEmpty ? .unparseable : .parsed
        return (
            .result(.panel(text: captured, planHint: nil)),
            BootOutcome(stage: .ready, panel: panelStage)
        )
    }

    /// The one marker list for the CLI's first-run screens — shared by the boot bail
    /// (don't type into them) and the result typing (classify as `.loginRequired`),
    /// so the two can never drift apart.
    static func isFirstRunScreen(_ strippedText: String) -> Bool {
        strippedText.localizedCaseInsensitiveContains("Select login method")
            || strippedText.localizedCaseInsensitiveContains("Choose the text style")
    }

    /// Positive allowlist for PTY input. Login, trust, empty startup, and unknown/new
    /// onboarding all remain no-input states; only a recognized normal interactive
    /// prompt permits `/usage`.
    static func classifyBootText(_ strippedText: String) -> ClaudeBootState {
        let text = strippedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .noOutput }
        if isSignedOutOutput(text) { return .loginRequired }
        if text.localizedCaseInsensitiveContains("Quick safety check")
            || text.localizedCaseInsensitiveContains("trust this folder") {
            return .trustRequired
        }
        if isFirstRunScreen(text) { return .loginRequired }
        if isStartupQuestion(text) { return .startupQuestion }
        // Pre-2.1.218 CLIs painted a "? for shortcuts" hint on the ready prompt.
        if text.localizedCaseInsensitiveContains("? for shortcuts") { return .ready }
        // CLI 2.1.218 (Jul 2026) redesigned the boot paint: it dropped BOTH the
        // "? for shortcuts" hint and the "… for agents" tagline that the two branches
        // below keyed on, so this classifier fell through to .unknown and the app never
        // typed /usage. The new banner reads "Claude Code v2.1.218 / <model> · Claude
        // Max" with a `❯ Try "…"` input hint. Two positive markers still separate a
        // normal interactive REPL from a menu (login/trust/onboarding): the "❯" prompt
        // marker AND the empty-input `Try "…"` placeholder — a selection menu puts a real
        // choice after "❯" and never paints that placeholder. Requiring the placeholder
        // (not just the banner) keeps this a positive allowlist: login/onboarding screens
        // also contain "Claude Code", so banner + prompt alone would be too permissive.
        //
        // WHY containment, not a line-prefix split: 2.1.218 repaints via cursor
        // positioning, so the ANSI-stripped capture can arrive with carriage returns but
        // no line feeds — a split()+hasPrefix("❯") check is unreliable across that layout.
        let hasPromptMarker = text.contains("❯")
        if text.localizedCaseInsensitiveContains("Claude Code"),
           hasPromptMarker,
           text.localizedCaseInsensitiveContains("Try \"") {
            return .ready
        }
        // Legacy fallback: pre-2.1.218 prompt whose status line carried the "for agents"
        // tagline but no visible "Try …" placeholder (e.g. after the user typed).
        if text.localizedCaseInsensitiveContains("Claude Code"),
           text.localizedCaseInsensitiveContains("for agents"),
           hasPromptMarker {
            return .ready
        }
        return .unknown
    }

    /// CLI 2.1.312 (Oct 2026) stops a config whose global state (`.claude.json`, not
    /// settings, so no `--settings` flag skips it) lacks `hasCompletedClaudeInChromeOnboarding`
    /// on a "Claude in Chrome extension detected" question before the prompt. Recognized
    /// only so the card can name it; it stays a no-input state, because either answer
    /// changes the user's Claude settings. Both a heading and an option must match, so this
    /// stays a positive allowlist. The paint positions words with cursor moves that
    /// `ANSI.strip` turns into spaces, so the match runs on whitespace-collapsed text.
    static func isStartupQuestion(_ strippedText: String) -> Bool {
        let text = strippedText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.localizedCaseInsensitiveContains("Claude in Chrome extension detected")
            && (text.localizedCaseInsensitiveContains("keep browser tools off")
                || text.localizedCaseInsensitiveContains("use my browser"))
    }

    /// Returning users keep a normal REPL after sign-out. Its explicit login footer
    /// must win over ready-prompt markers (session review #1).
    private static func isSignedOutOutput(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("Not logged in")
            && text.localizedCaseInsensitiveContains("run /login")
    }

    static func environment(
        inherited: [String: String],
        overrides: [String: String],
        loginPath: String,
        workingDirectory: String
    ) -> [String: String] {
        var result = inherited
        // The built-in account always means the CLI default. A custom value inherited
        // from a Terminal launch must not silently select another account.
        if overrides["CLAUDE_CONFIG_DIR"] == nil { result.removeValue(forKey: "CLAUDE_CONFIG_DIR") }
        // An API key or bearer token in the environment (often set machine-wide through
        // launchctl) outranks the account's subscription login and turns `/usage` into a
        // cost report, so the row never reads. Headroom reads the subscription only; the
        // Cursor and Copilot probes drop their equivalents the same way.
        result.removeValue(forKey: "ANTHROPIC_API_KEY")
        result.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
        result["LANG"] = result["LANG"] ?? "en_US.UTF-8"
        result["PATH"] = loginPath
        result["PWD"] = workingDirectory
        for (key, value) in overrides { result[key] = value }
        return result
    }

    /// Read from the pty until `quiet` seconds pass with no new bytes, or `maxSeconds`
    /// elapse — captures the panel across its several re-renders without hanging.
    private static func drain(master: Int32, maxSeconds: TimeInterval, quiet: TimeInterval, into buffer: inout Data) {
        let deadline = Date().addingTimeInterval(maxSeconds)
        var lastData = Date()
        var pfd = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 65536)
        while Date() < deadline {
            let ready = poll(&pfd, 1, 200)
            if ready > 0, pfd.revents & Int16(POLLIN) != 0 {
                let n = read(master, &chunk, chunk.count)
                if n > 0 { buffer.append(contentsOf: chunk[0..<n]); lastData = Date() }
                else { break } // EOF / EIO — child gone
            } else if Date().timeIntervalSince(lastData) > quiet {
                break
            }
        }
    }
}

/// Strips ANSI/VT control sequences so the panel text can be parsed.
enum ANSI {
    static func strip(_ text: String) -> String {
        var out = text
        // ICU regex escapes use \xHH (not Swift's \u{..}). CSI sequences, charset
        // selects, OSC strings, and stray control bytes.
        for pattern in [
            #"\x1B\[[0-9;?]*[ -/]*[@-~]"#,
            #"\x1B[()][A-Za-z0-9]"#,
            #"\x1B[=>]"#,
            #"\x1B\][^\x07]*\x07"#,
            #"[\x00-\x08\x0B\x0C\x0E-\x1F]"#,
        ] {
            out = out.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return out
    }
}
