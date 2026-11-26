import Foundation

/// Parsed read-only balance from Google's official `colab` CLI (`colab --auth=oauth2 usage`).
public struct AntigravityGPUCredits: Sendable, Equatable {
    public let balanceUnits: Double
    public let usageRatePerHour: Double?
    public let activeAssignments: Int?

    public init(balanceUnits: Double, usageRatePerHour: Double? = nil, activeAssignments: Int? = nil) {
        self.balanceUnits = balanceUnits
        self.usageRatePerHour = usageRatePerHour
        self.activeAssignments = activeAssignments
    }
}

/// What one `colab usage` check returned. Failures degrade cleanly to `.unavailable` and never
/// fail the Antigravity quota snapshot.
public enum AntigravityGPUCreditsReading: Sendable, Equatable {
    case balance(AntigravityGPUCredits)
    case unavailable
}

/// Injectable seam consumed by `AntigravityProvider` when `AntigravityGPUCreditsMode != .off`.
public protocol AntigravityGPUCreditsSource: Sendable {
    func capture() async -> AntigravityGPUCreditsReading
}

/// Pure parser for Google's official `colab usage` text output:
/// ```
/// Current balance: 2608.04 compute units
/// Usage rate: 0.00/hr
/// Active assignments: 0
/// ```
public enum ColabUsageParser {
    public static func parse(_ output: String) -> AntigravityGPUCredits? {
        var balance: Double?
        var rate: Double?
        var active: Int?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()

            if lower.hasPrefix("current balance:") {
                let valuePart = line.dropFirst("current balance:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = firstFiniteNumber(in: valuePart), parsed >= 0 {
                    balance = parsed
                }
            } else if lower.hasPrefix("usage rate:") {
                let valuePart = line.dropFirst("usage rate:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = firstFiniteNumber(in: valuePart), parsed >= 0 {
                    rate = parsed
                }
            } else if lower.hasPrefix("active assignments:") {
                let valuePart = line.dropFirst("active assignments:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = firstFiniteNumber(in: valuePart), parsed >= 0 {
                    active = Int(parsed.rounded())
                }
            }
        }

        guard let balance else { return nil }
        return AntigravityGPUCredits(
            balanceUnits: balance,
            usageRatePerHour: rate,
            activeAssignments: active
        )
    }

    private static func firstFiniteNumber(in text: String) -> Double? {
        let token = text.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first.map(String.init) ?? ""
        let normalized = token.replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

/// Official `colab` CLI reader (`google-colab-cli`), strictly read-only (`colab --auth=oauth2 usage`).
/// Owns no credentials, never reads OAuth files or cookies, discards stderr, and bounds both
/// wall clock and stdout so a broken CLI can never stall Antigravity polling.
public struct ColabCLIGPUCreditsSource: AntigravityGPUCreditsSource {
    public struct CommandOutput: Sendable, Equatable {
        public let exitCode: Int32?
        public let stdout: Data

        public init(exitCode: Int32?, stdout: Data) {
            self.exitCode = exitCode
            self.stdout = stdout
        }
    }

    public typealias ResolveExecutable = @Sendable (_ name: String) -> String?
    public typealias RunCommand = @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval, _ maxBytes: Int) -> CommandOutput

    private static let timeoutSeconds: TimeInterval = 12
    private static let stdoutCapBytes = 4_096

    private let resolveExecutable: ResolveExecutable
    private let runCommand: RunCommand

    public init(
        resolveExecutable: @escaping ResolveExecutable = ColabCLIGPUCreditsSource.defaultResolve,
        runCommand: @escaping RunCommand = ColabCLIGPUCreditsSource.defaultRun
    ) {
        self.resolveExecutable = resolveExecutable
        self.runCommand = runCommand
    }

    public func capture() async -> AntigravityGPUCreditsReading {
        guard let invocation = resolvedInvocation() else { return .unavailable }
        let output = await Task.detached(priority: .utility) { [runCommand] in
            runCommand(invocation.executable, invocation.arguments, Self.timeoutSeconds, Self.stdoutCapBytes)
        }.value
        guard output.exitCode == 0,
              let text = String(data: output.stdout, encoding: .utf8),
              let parsed = ColabUsageParser.parse(text)
        else { return .unavailable }
        return .balance(parsed)
    }

    private func resolvedInvocation() -> (executable: String, arguments: [String])? {
        if let colabPath = resolveExecutable("colab") {
            return (colabPath, ["--auth=oauth2", "usage"])
        }
        if let uvxPath = resolveExecutable("uvx") {
            return (uvxPath, ["--from", "google-colab-cli", "colab", "--auth=oauth2", "usage"])
        }
        return nil
    }

    public static func defaultResolve(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbacks = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
        ]
        return CLIExecutableResolver.resolve(named: name, fallbackPaths: fallbacks)
    }

    public static func defaultRun(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        maxBytes: Int
    ) -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = CLIExecutableResolver.resolveLoginPath(
            fallback: env["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        )
        process.environment = env

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandOutput(exitCode: nil, stdout: Data())
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return CommandOutput(exitCode: nil, stdout: Data())
        }

        let data = stdoutPipe.fileHandleForReading.readData(ofLength: maxBytes)
        return CommandOutput(exitCode: process.terminationStatus, stdout: data)
    }
}
