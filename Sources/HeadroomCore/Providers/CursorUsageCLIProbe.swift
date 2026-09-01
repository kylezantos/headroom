import Foundation
import Darwin

public enum CursorAuthStatus: Sendable, Equatable {
    case loggedIn
    case loggedOut
    case unsupported
    case transient
}

/// Drives the official Cursor Agent TUI only far enough to open `/usage`. The command
/// is a free status surface: no prompt is submitted and no model request is made.
public struct CursorUsageCLIProbe: CursorUsageSource {
    public let cursorPath: String?
    public let workingDirectory: String
    public let bootTimeout: TimeInterval
    public let panelTimeout: TimeInterval

    public init(
        cursorPath: String? = CursorUsageCLIProbe.resolveCursorPath(),
        workingDirectory: String = CursorUsageCLIProbe.defaultWorkspace.path,
        bootTimeout: TimeInterval = 20,
        panelTimeout: TimeInterval = 20
    ) {
        self.cursorPath = cursorPath
        self.workingDirectory = workingDirectory
        self.bootTimeout = bootTimeout
        self.panelTimeout = panelTimeout
    }

    public func capturePanel() async -> CursorPanelResult {
        guard let cursorPath, FileManager.default.isExecutableFile(atPath: cursorPath) else {
            return .cliNotFound
        }
        do {
            try FileManager.default.createDirectory(
                atPath: workingDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: workingDirectory
            )
        } catch {
            return .transientCapture
        }

        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                switch Self.runAuthStatus(cursorPath: cursorPath) {
                case .loggedOut:
                    continuation.resume(returning: .loginRequired)
                case .unsupported:
                    continuation.resume(returning: .unknownUI)
                case .transient:
                    continuation.resume(returning: .transientCapture)
                case .loggedIn:
                    continuation.resume(returning: Self.runBlocking(
                        cursorPath: cursorPath,
                        workingDirectory: workingDirectory,
                        boot: bootTimeout,
                        panel: panelTimeout
                    ))
                }
            }
        }
    }

    public static var defaultWorkspace: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Headroom/CursorProbe", isDirectory: true)
    }

    public static func resolveCursorPath() -> String? {
        CLIExecutableResolver.resolve(
            named: "cursor-agent",
            fallbackPaths: fallbackPaths
        )
    }

    static var fallbackPaths: [String] {
        [
            "\(NSHomeDirectory())/.local/bin/cursor-agent",
            "/opt/homebrew/bin/cursor-agent",
            "/usr/local/bin/cursor-agent",
        ]
    }

    static func classifyAuthStatus(_ data: Data) -> CursorAuthStatus {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authenticated = object["isAuthenticated"] as? Bool
        else { return .unsupported }
        return authenticated ? .loggedIn : .loggedOut
    }

    private static func runAuthStatus(cursorPath: String) -> CursorAuthStatus {
        guard let data = captureStatusJSON(
            cursorPath: cursorPath,
            timeout: 5,
            isSufficient: { classifyAuthStatus($0) != .unsupported }
        ) else { return .transient }
        return classifyAuthStatus(data)
    }

    /// Runs the official `cursor-agent status --format json` — a free, read-only status
    /// command that makes no model request and mutates no auth state — and returns its
    /// stdout, or nil when the process can't start, the deadline passes, or stdout can't
    /// be read. Shared by the auth gate and `CursorStatusEmailProbe` so there is exactly
    /// one spawn / hard-deadline / process-group-kill path for this command.
    /// `isSufficient` lets a caller stop as soon as the bytes so far answer its question.
    static func captureStatusJSON(
        cursorPath: String,
        timeout: TimeInterval,
        isSufficient: (Data) -> Bool = { _ in false }
    ) -> Data? {
        var output = [Int32](repeating: -1, count: 2)
        guard pipe(&output) == 0 else { return nil }
        let devNull = open("/dev/null", O_RDWR)

        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        if devNull >= 0 {
            posix_spawn_file_actions_adddup2(&actions, devNull, STDIN_FILENO)
            posix_spawn_file_actions_adddup2(&actions, devNull, STDERR_FILENO)
        }
        for fd in [output[0], output[1], devNull] where fd >= 0 {
            posix_spawn_file_actions_addclose(&actions, fd)
        }

        var attributes = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        let arguments = [cursorPath, "status", "--format", "json"]
        let environment = environment(workingDirectory: FileManager.default.currentDirectoryPath)
        let cArguments = arguments.map { strdup($0) } + [nil]
        let cEnvironment = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            cArguments.forEach { free($0) }
            cEnvironment.forEach { free($0) }
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, cursorPath, &actions, &attributes, cArguments, cEnvironment)
        close(output[1])
        if devNull >= 0 { close(devNull) }
        guard spawnStatus == 0 else {
            close(output[0])
            return nil
        }
        defer {
            close(output[0])
            terminateProcessGroup(pid)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var descriptor = pollfd(fd: output[0], events: Int16(POLLIN), revents: 0)
        while Date() < deadline {
            let ready = poll(&descriptor, 1, 100)
            guard ready >= 0 else { return nil }
            guard ready > 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 4_096)
            let count = read(output[0], &chunk, chunk.count)
            guard count > 0 else { return data }
            data.append(contentsOf: chunk.prefix(count))
            if isSufficient(data) { return data }
        }
        return nil
    }

    private static func runBlocking(
        cursorPath: String,
        workingDirectory: String,
        boot: TimeInterval,
        panel: TimeInterval
    ) -> CursorPanelResult {
        var master: Int32 = -1
        var slave: Int32 = -1
        var window = winsize(ws_row: 45, ws_col: 140, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &window) == 0 else { return .transientCapture }

        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, workingDirectory)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory)
        }
        posix_spawn_file_actions_adddup2(&actions, slave, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, slave, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, slave, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, master)

        var attributes = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        let arguments = [cursorPath, "--mode", "ask", "--trust", "--workspace", workingDirectory]
        var env = environment(workingDirectory: workingDirectory)
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = "140"
        env["LINES"] = "45"
        let cArguments = arguments.map { strdup($0) } + [nil]
        let cEnvironment = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            cArguments.forEach { free($0) }
            cEnvironment.forEach { free($0) }
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, cursorPath, &actions, &attributes, cArguments, cEnvironment)
        close(slave)
        guard spawnStatus == 0 else { close(master); return .transientCapture }

        func teardown() {
            terminateProcessGroup(pid)
            close(master)
        }

        var buffer = Data()
        // Ink asks the terminal for its background color before its first paint. A raw
        // openpty has no emulator to answer OSC 11, so respond with a neutral dark
        // terminal value; otherwise Cursor waits forever and the probe sees only the
        // query escape sequence.
        usleep(100_000)
        writeText("\u{1B}]11;rgb:0000/0000/0000\u{07}", to: master)
        _ = drainUntil(
            master: master,
            maxSeconds: boot,
            into: &buffer,
            condition: isReadyPrompt
        )
        let bootText = ANSI.strip(String(decoding: buffer, as: UTF8.self))
        guard isReadyPrompt(bootText)
        else {
            teardown()
            return bootText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .transientCapture : .unknownUI
        }

        usleep(1_500_000)
        writeText("/usage", to: master)
        var autocompleteBuffer = Data()
        _ = drainUntil(
            master: master,
            maxSeconds: 3,
            into: &autocompleteBuffer,
            condition: isUsageAutocompleteSelected
        )
        let autocompleteText = ANSI.strip(String(decoding: autocompleteBuffer, as: UTF8.self))
        guard isUsageAutocompleteSelected(autocompleteText) else {
            teardown()
            return .unknownUI
        }
        // `/usage` is registered by Cursor as autoExecuteOnAccept. One Enter invokes
        // that positively selected status command; if this behavior changes, the panel
        // check below fails closed rather than sending a second Enter as a model prompt.
        writeText("\u{1B}[13u", to: master)
        var panelBuffer = Data()
        drain(master: master, maxSeconds: panel, quiet: 4, into: &panelBuffer)
        teardown()

        let captured = ANSI.strip(String(decoding: panelBuffer, as: UTF8.self))
        guard captured.localizedCaseInsensitiveContains("Monthly plan and on-demand usage"),
              captured.localizedCaseInsensitiveContains("Included")
        else { return .transientCapture }
        return .panel(captured)
    }

    /// Positive allowlist for the normal Cursor Agent input surface. Product banners
    /// also appear on onboarding and update screens, so they never authorize typing by
    /// themselves.
    static func isReadyPrompt(_ strippedText: String) -> Bool {
        strippedText.localizedCaseInsensitiveContains("Cursor Agent")
            && strippedText.localizedCaseInsensitiveContains("Ask (shift+tab to cycle)")
    }

    /// Cursor paints an arrow beside the active slash-command completion. Requiring the
    /// arrow-selected `/usage` row ensures the only Enter we send cannot submit arbitrary
    /// text when the command is absent or renamed. The live TUI pads the arrow-to-command
    /// gap with a variable number of spaces (e.g. `→  /usage`), so match one-or-more
    /// spaces rather than a single literal one; the trailing boundary keeps `/usage` a
    /// whole token so `/usages`-style commands can never satisfy the gate.
    static func isUsageAutocompleteSelected(_ strippedText: String) -> Bool {
        strippedText.contains(/→\s+\/usage(?:\s|$)/)
    }

    private static func terminateProcessGroup(_ pid: pid_t) {
        guard pid > 0 else { return }
        var status: Int32 = 0
        let initial = waitpid(pid, &status, WNOHANG)
        if initial == pid || (initial == -1 && errno == ECHILD) { return }

        kill(-pid, SIGTERM)
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return }
            usleep(20_000)
        }
        kill(-pid, SIGKILL)
        // Cursor's bundled Node runtime can linger in Darwin's exiting state after
        // SIGKILL. Never turn the probe's hard deadline into an unbounded reap.
        let killDeadline = Date().addingTimeInterval(0.5)
        while Date() < killDeadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return }
            usleep(20_000)
        }
    }

    private static func environment(workingDirectory: String) -> [String: String] {
        var result = ProcessInfo.processInfo.environment
        // Subscription usage is tied to the official browser login. Do not let a
        // Terminal-only API key or custom endpoint silently select a different account.
        result.removeValue(forKey: "CURSOR_API_KEY")
        result.removeValue(forKey: "CURSOR_API_ENDPOINT")
        result["PATH"] = CLIExecutableResolver.resolveLoginPath(
            fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        )
        result["LANG"] = result["LANG"] ?? "en_US.UTF-8"
        result["PWD"] = workingDirectory
        return result
    }

    private static func writeText(_ text: String, to fd: Int32) {
        _ = text.withCString { write(fd, $0, strlen($0)) }
    }

    private static func drain(
        master: Int32,
        maxSeconds: TimeInterval,
        quiet: TimeInterval,
        into buffer: inout Data
    ) {
        let deadline = Date().addingTimeInterval(maxSeconds)
        var lastData = Date()
        var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while Date() < deadline {
            let ready = poll(&descriptor, 1, 200)
            if ready > 0, descriptor.revents & Int16(POLLIN) != 0 {
                let count = read(master, &chunk, chunk.count)
                if count > 0 {
                    buffer.append(contentsOf: chunk.prefix(count))
                    lastData = Date()
                } else {
                    break
                }
            } else if Date().timeIntervalSince(lastData) > quiet {
                break
            }
        }
    }

    private static func drainUntil(
        master: Int32,
        maxSeconds: TimeInterval,
        into buffer: inout Data,
        condition: (String) -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(maxSeconds)
        var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while Date() < deadline {
            let ready = poll(&descriptor, 1, 200)
            if ready > 0, descriptor.revents & Int16(POLLIN) != 0 {
                let count = read(master, &chunk, chunk.count)
                guard count > 0 else { return false }
                buffer.append(contentsOf: chunk.prefix(count))
                if condition(ANSI.strip(String(decoding: buffer, as: UTF8.self))) {
                    return true
                }
            }
        }
        return false
    }
}
