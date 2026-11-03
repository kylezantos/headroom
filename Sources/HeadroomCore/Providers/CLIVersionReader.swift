import Foundation

/// Reads each provider CLI's `--version` for the feedback email's diagnostics block
/// (2026-11-03 feedback plan, KTD3). Runs only when the feedback window opens, off the main
/// actor, one CLI at a time per provider but all providers concurrently. `--version` is a
/// local print on every supported CLI; it signs nothing in and starts no session.
public enum CLIVersionReader {
    public typealias Resolve = @Sendable (ProviderID) -> String?
    public typealias Run = @Sendable (_ executablePath: String) -> String?

    /// The order the diagnostics block lists CLIs in.
    public static let providers: [ProviderID] = [.claude, .codex, .grok, .cursor, .copilot]

    public static func versions(
        resolve: @escaping Resolve = defaultResolve,
        run: @escaping Run = defaultRun
    ) async -> [FeedbackDiagnostics.CLI] {
        await withTaskGroup(of: (Int, FeedbackDiagnostics.CLI).self) { group in
            for (index, providerID) in providers.enumerated() {
                group.addTask {
                    await Task.detached(priority: .utility) {
                        guard let path = resolve(providerID) else {
                            return (index, FeedbackDiagnostics.CLI(providerID: providerID, version: .notInstalled))
                        }
                        let version = FeedbackCLIVersion(versionOutput: run(path))
                        return (index, FeedbackDiagnostics.CLI(providerID: providerID, version: version))
                    }.value
                }
            }
            var results: [(Int, FeedbackDiagnostics.CLI)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// The same executable each provider's probe and sign-in handoff resolve.
    public static let defaultResolve: Resolve = { providerID in
        switch providerID {
        case .claude:
            CLIExecutableResolver.resolve(named: "claude", fallbackPaths: CLIExecutableLocator.claudeFixedFallbackPaths)
        case .codex: CodexCLI.resolveExecutable()
        case .grok: GrokCLI.resolveExecutable()
        case .cursor: CursorCLI.resolveExecutable()
        case .copilot: CopilotCLI.resolveExecutable()
        default: nil
        }
    }

    public static let defaultRun: Run = { path in
        runVersion(
            executablePath: path,
            loginPath: CLIExecutableResolver.resolveLoginPath(
                fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            ),
            deadline: 5
        )
    }

    /// Nil when the CLI can't launch, exits non-zero, or misses the deadline. Stderr is
    /// discarded: nothing it prints may reach the email.
    static func runVersion(executablePath: String, loginPath: String, deadline: TimeInterval) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]
        var environment = ProcessInfo.processInfo.environment
        // Node-based CLIs (`#!/usr/bin/env node`) need the login PATH from a Finder launch.
        environment["PATH"] = loginPath
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        // Collected as it arrives rather than read to end of file: a CLI that leaves a
        // background helper holding stdout open would otherwise block the read forever.
        let collected = CollectedOutput()
        output.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData) }
        defer { output.fileHandleForReading.readabilityHandler = nil }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        guard exited.wait(timeout: .now() + deadline) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        // The last chunk can land just after the exit signal.
        Thread.sleep(forTimeInterval: 0.05)
        return String(decoding: collected.data.prefix(4_096), as: UTF8.self)
    }

    private final class CollectedOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func append(_ chunk: Data) {
            lock.withLock { if buffer.count < 4_096 { buffer.append(chunk) } }
        }

        var data: Data { lock.withLock { buffer } }
    }
}
