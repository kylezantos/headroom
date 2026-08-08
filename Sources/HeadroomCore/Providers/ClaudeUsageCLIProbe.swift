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
    /// `planHint` is the subscription tier from `claude auth status --json` — the
    /// print-mode report omits the "· Claude Max" header the panel carries, so the
    /// provider falls back to this when the text yields no tier.
    case panel(text: String, planHint: String?)
    /// The CLI booted into a first-run screen (theme picker / login-method selector) —
    /// this config home has no signed-in account. Typed here, at the layer that saw
    /// the screen, so the provider never re-derives it from marker strings.
    case loginRequired
    case workspaceTrustRequired
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
    case unknown
    case noOutput
}

public enum ClaudeAuthStatus: Sendable, Equatable {
    case loggedIn
    case loggedOut
    case unsupported
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

    public init(
        locator: any CLIExecutableLocating = CLIExecutableLocator.claude(),
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environmentOverrides: [String: String] = [:],
        bootTimeout: TimeInterval = 30,
        panelTimeout: TimeInterval = 26
    ) {
        self.locator = locator
        self.workingDirectory = workingDirectory
        self.environmentOverrides = environmentOverrides
        self.bootTimeout = bootTimeout
        self.panelTimeout = panelTimeout
    }

    public func capturePanel() async -> ClaudePanelResult {
        for attempt in 0...1 {
            let location = await locator.locate()
            switch location {
            case .confirmedAbsent:
                return .cliNotFound
            case .inconclusive(let issue):
                return .cliInconclusive(issue)
            case .available(let claudePath, _):
                let result = await capture(at: claudePath)
                switch result {
                case .result(let panel):
                    return panel
                case .launchNotFound where attempt == 0:
                    await locator.invalidate(path: claudePath, reason: .launchNotFound)
                case .launchNotFound:
                    return .cliInconclusive(.launchRace)
                }
            }
        }
        return .cliInconclusive(.launchRace)
    }

    private func capture(at claudePath: String) async -> ExecutableCaptureResult {
        // Run the blocking process and pty work off the cooperative pool.
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread { [environmentOverrides] in
                let authResult = Self.runAuthCheck(
                    claudePath: claudePath,
                    environmentOverrides: environmentOverrides
                )
                guard case .status(let auth) = authResult else {
                    continuation.resume(returning: .launchNotFound)
                    return
                }
                switch auth.status {
                case .loggedOut:
                    continuation.resume(returning: .result(.loginRequired))
                    return
                case .unsupported:
                    continuation.resume(returning: .result(.unknownUI))
                    return
                case .loggedIn:
                    break
                }
                // Print-first capture: `claude -p "/usage"` writes the settled report
                // in one shot — no TUI repaints to garble labels and no partial paint
                // for the separately fetched model rows, which is the failure class
                // that intermittently dropped "Weekly (Fable)". Any miss (old CLI,
                // unparseable output, timeout) falls back to the PTY panel unchanged.
                switch Self.runPrintUsage(
                    claudePath: claudePath,
                    workingDirectory: workingDirectory,
                    environmentOverrides: environmentOverrides
                ) {
                case .report(let report):
                    continuation.resume(returning: .result(.panel(text: report, planHint: auth.planHint)))
                    return
                case .launchNotFound:
                    continuation.resume(returning: .launchNotFound)
                    return
                case .unavailable:
                    break
                }
                let result = Self.runBlocking(
                    claudePath: claudePath,
                    workingDirectory: workingDirectory,
                    environmentOverrides: environmentOverrides,
                    boot: bootTimeout,
                    panel: panelTimeout,
                    planHint: auth.planHint
                )
                continuation.resume(returning: result)
            }
        }
    }

    /// Resolve `claude` via the user's login shell so a Finder-launched app (bare PATH)
    /// still finds an nvm/homebrew install. Falls back to common locations.
    public static func resolveClaudePath() -> String? {
        CLIExecutableResolver.resolve(
            named: "claude",
            fallbackPaths: [
                "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                "\(NSHomeDirectory())/.local/bin/claude",
            ]
        )
    }

    /// The user's real PATH via a login shell, so a Finder-launched app (bare PATH)
    /// still resolves node/nvm the way the terminal does. Falls back to a sane default.
    private static func loginPath() -> String {
        let fallback = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return CLIExecutableResolver.resolveLoginPath(fallback: fallback)
    }

    /// Decode only the stable boolean from `claude auth status --json`. Unknown output
    /// never falls through to the interactive probe, because doing so could type into a
    /// new first-run surface.
    static func classifyAuthStatus(_ data: Data) -> ClaudeAuthStatus {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = object["loggedIn"] as? Bool
        else { return .unsupported }
        return loggedIn ? .loggedIn : .loggedOut
    }

    /// The subscription tier from `auth status --json` ("max" → "Max"), mapped
    /// through an allowlist so an unknown future value never becomes a garbled pill.
    static func subscriptionPlanHint(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["subscriptionType"] as? String
        else { return nil }
        switch type.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "free": return "Free"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return nil
        }
    }

    struct AuthCheck: Sendable {
        let status: ClaudeAuthStatus
        let planHint: String?
    }

    private enum ExecutableCaptureResult: Sendable {
        case result(ClaudePanelResult)
        case launchNotFound
    }

    private enum AuthCheckResult: Sendable {
        case status(AuthCheck)
        case launchNotFound
    }

    private enum PrintUsageResult: Sendable {
        case report(String)
        case unavailable
        case launchNotFound
    }

    private enum ProcessOutputResult: Sendable {
        case data(Data)
        case failed
        case launchNotFound
    }

    private static func runAuthCheck(
        claudePath: String,
        environmentOverrides: [String: String]
    ) -> AuthCheckResult {
        switch runForOutput(
            claudePath: claudePath,
            arguments: ["auth", "status", "--json"],
            environmentOverrides: environmentOverrides,
            deadline: 5
        ) {
        case .launchNotFound:
            return .launchNotFound
        case .failed:
            return .status(AuthCheck(status: .unsupported, planHint: nil))
        case .data(let data):
            return .status(AuthCheck(
                status: classifyAuthStatus(data),
                planHint: subscriptionPlanHint(data)
            ))
        }
    }

    /// Gate for the print-first capture. 2.1.217 is the oldest CLI verified to run
    /// `/usage` locally under `-p`; an unverified older build could forward it to the
    /// model as a prompt — spending real usage every poll — so anything below the
    /// floor (or unparseable) stays on the PTY path.
    static func printUsageSupported(versionOutput: String) -> Bool {
        guard let version = parsedVersion(versionOutput) else { return false }
        return version >= (2, 1, 217)
    }

    public static func versionBand(
        executablePath: String,
        environmentOverrides: [String: String] = [:]
    ) async -> ClaudeCLIVersionBand {
        await Task.detached(priority: .utility) {
            switch runForOutput(
                claudePath: executablePath,
                arguments: ["--version"],
                environmentOverrides: environmentOverrides,
                deadline: 5
            ) {
            case .launchNotFound, .failed:
                return .unknown
            case .data(let data):
                return classifyVersionBand(String(decoding: data, as: UTF8.self))
            }
        }.value
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

    /// One-shot non-interactive capture: `claude -p "/usage"` prints the full settled
    /// usage report (same compliant principle — the official client makes the request,
    /// this reads its stdout). Returns nil unless the output parses into at least one
    /// usage window, so a cost report, an error, or model chatter can never be
    /// mistaken for the panel.
    private static func runPrintUsage(
        claudePath: String,
        workingDirectory: String,
        environmentOverrides: [String: String]
    ) -> PrintUsageResult {
        let versionData: Data
        switch runForOutput(
            claudePath: claudePath,
            arguments: ["--version"],
            environmentOverrides: environmentOverrides,
            deadline: 5
        ) {
        case .launchNotFound: return .launchNotFound
        case .failed: return .unavailable
        case .data(let data): versionData = data
        }
        guard printUsageSupported(versionOutput: String(decoding: versionData, as: UTF8.self)) else {
            return .unavailable
        }
        let data: Data
        switch runForOutput(
            claudePath: claudePath,
            arguments: ["-p", "/usage", "--no-session-persistence"],
            environmentOverrides: environmentOverrides,
            workingDirectory: workingDirectory,
            deadline: 20
        ) {
        case .launchNotFound: return .launchNotFound
        case .failed: return .unavailable
        case .data(let value): data = value
        }
        let text = ANSI.strip(String(decoding: data, as: UTF8.self))
        return ClaudeUsageParser.parse(text).isEmpty ? .unavailable : .report(text)
    }

    /// Spawn `claude` with pipes (no pty), enforce a hard deadline, and return stdout.
    /// A timeout returns nil rather than partial output — callers treat that as "this
    /// surface is unavailable" and degrade. Output is read after exit, which is safe
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
            return .failed
        }
        process.waitUntilExit()
        return .data(output.fileHandleForReading.readDataToEndOfFile())
    }

    // MARK: pty mechanics

    private static func runBlocking(
        claudePath: String,
        workingDirectory: String,
        environmentOverrides: [String: String],
        boot: TimeInterval,
        panel: TimeInterval,
        planHint: String? = nil
    ) -> ExecutableCaptureResult {
        var master: Int32 = -1
        var slave: Int32 = -1
        var win = winsize(ws_row: 45, ws_col: 140, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &win) == 0 else {
            return .result(.transientCapture)
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
        let env = envDict.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let argv = [claudePath]
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
            return spawnResult == ENOENT ? .launchNotFound : .result(.transientCapture)
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
        let bootText = String(decoding: buffer, as: UTF8.self)
        switch classifyBootText(ANSI.strip(bootText)) {
        case .ready:
            break
        case .loginRequired:
            teardown()
            return .result(.loginRequired)
        case .trustRequired:
            teardown()
            return .result(.workspaceTrustRequired)
        case .unknown:
            teardown()
            return .result(.unknownUI)
        case .noOutput:
            teardown()
            return .result(.transientCapture)
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
        return .result(
            captured.isEmpty ? .transientCapture : .panel(text: captured, planHint: planHint)
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
        if text.localizedCaseInsensitiveContains("Quick safety check")
            || text.localizedCaseInsensitiveContains("trust this folder") {
            return .trustRequired
        }
        if isFirstRunScreen(text) { return .loginRequired }
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
