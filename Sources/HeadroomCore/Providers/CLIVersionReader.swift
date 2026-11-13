import Foundation

/// Reads each provider CLI's `--version` for the feedback email's diagnostics block
/// (2026-11-03 feedback plan, KTD3). Runs only when the feedback window opens, off the main
/// actor, with every provider read concurrently. `--version` is a local print on every
/// supported CLI; it signs nothing in and starts no session.
public enum CLIVersionReader {
    public typealias Resolve = @Sendable (ProviderID) -> String?
    public typealias LoginPath = @Sendable () -> String
    public typealias Run = @Sendable (_ executablePath: String, _ loginPath: String) -> String?

    /// The order the diagnostics block lists CLIs in.
    public static let providers: [ProviderID] = [.claude, .codex, .grok, .cursor, .copilot, .opencode]

    public static func versions(
        resolve: @escaping Resolve = defaultResolve,
        loginPath: @escaping LoginPath = defaultLoginPath,
        run: @escaping Run = defaultRun
    ) async -> [FeedbackDiagnostics.CLI] {
        let paths = await concurrently(providers) { resolve($0) }
        // One login-shell PATH lookup for every CLI, and none when nothing is installed.
        let path = paths.contains { $0 != nil } ? await offCooperativePool(loginPath) : ""
        let outputs = await concurrently(paths) { executable in
            executable.flatMap { run($0, path) }
        }
        return providers.indices.map { index in
            FeedbackDiagnostics.CLI(
                providerID: providers[index],
                version: paths[index] == nil ? .notInstalled : FeedbackCLIVersion(versionOutput: outputs[index])
            )
        }
    }

    /// The executable each provider's probe and sign-in handoff look for, found the same way
    /// (login shell, then the provider's fixed fallback paths).
    public static let defaultResolve: Resolve = { providerID in
        switch providerID {
        case .claude:
            CLIExecutableResolver.resolve(named: "claude", fallbackPaths: CLIExecutableLocator.claudeFixedFallbackPaths)
        case .codex: CodexCLI.resolveExecutable()
        case .grok: GrokCLI.resolveExecutable()
        case .cursor: CursorCLI.resolveExecutable()
        case .copilot: CopilotCLI.resolveExecutable()
        // U1 placeholder until U2's OpenCode resolver exists: the same login-shell lookup,
        // plus the official install script's `~/.opencode/bin`.
        case .opencode:
            CLIExecutableResolver.resolve(named: "opencode", fallbackPaths: [
                "\(NSHomeDirectory())/.opencode/bin/opencode",
                "/opt/homebrew/bin/opencode",
                "/usr/local/bin/opencode",
                "\(NSHomeDirectory())/.local/bin/opencode",
                "\(NSHomeDirectory())/.npm-global/bin/opencode",
            ])
        default: nil
        }
    }

    public static let defaultLoginPath: LoginPath = {
        CLIExecutableResolver.resolveLoginPath(
            fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        )
    }

    public static let defaultRun: Run = { path, loginPath in
        runVersion(executablePath: path, loginPath: loginPath, deadline: 5)
    }

    /// Nil when the CLI can't launch, exits non-zero, or misses the deadline. Stderr is
    /// discarded: nothing it prints may reach the email. `StdioChildProcess` rather than
    /// `Process`: its exit is read with `waitpid`, not a GCD-delivered termination handler,
    /// and its cleanup ends the whole process group if the CLI leaves a helper behind.
    static func runVersion(executablePath: String, loginPath: String, deadline: TimeInterval) -> String? {
        var environment = ProcessInfo.processInfo.environment
        // Node-based CLIs (`#!/usr/bin/env node`) need the login PATH from a Finder launch.
        environment["PATH"] = loginPath
        guard let process = StdioChildProcess.spawn(
            path: executablePath,
            arguments: [executablePath, "--version"],
            environment: environment,
            workingDirectory: NSHomeDirectory()
        ) else { return nil }
        defer { process.terminate() }

        let end = Date().addingTimeInterval(deadline)
        var output = Data()
        // Until end of file. A helper that keeps stdout open runs this to the deadline, and
        // the exit code below still decides.
        while Date() < end, output.count < 4_096, process.readOutput(into: &output, deadline: end) {}
        guard process.exitCode(within: max(0, end.timeIntervalSinceNow)) == 0 else { return nil }
        return String(decoding: output.prefix(4_096), as: UTF8.self)
    }

    /// Resolution and `--version` block on a login shell or a semaphore for up to seconds,
    /// so they run on GCD rather than tying up Swift's cooperative threads.
    private static func offCooperativePool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: work()) }
        }
    }

    private static func concurrently<Input: Sendable, T: Sendable>(
        _ inputs: [Input],
        _ work: @escaping @Sendable (Input) -> T
    ) async -> [T] {
        await withTaskGroup(of: (Int, T).self) { group in
            for (index, input) in inputs.enumerated() {
                group.addTask { (index, await offCooperativePool { work(input) }) }
            }
            var results = [T?](repeating: nil, count: inputs.count)
            for await (index, result) in group { results[index] = result }
            return results.map { $0! }
        }
    }
}
