import Foundation
import Testing
@testable import HeadroomCore

struct CopilotConnectionTests {
    private static let marker = SetupCompletionMarker(
        pendingPath: "/tmp/copilot pending",
        completedPath: "/tmp/copilot complete"
    )

    @Test func scriptRunsTheResolvedExecutablesLoginAndParsesAsZsh() throws {
        let script = CopilotCLI.loginScript(
            executablePath: "/Users/test/.local/bin/copilot",
            completionMarker: Self.marker
        )
        #expect(script.contains("'/Users/test/.local/bin/copilot' login"))
        #expect(script.contains("unset COPILOT_HOME COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN"))
        #expect(script.contains("complete:${setup_purpose}:${handoff_generation}:${setup_status}"))
        #expect(try Self.parsesAsZsh(script))
    }

    @Test func clipboardFallbackNamesTheResolvedPathAndClearsOverrides() {
        #expect(CopilotCLI.manualLoginCommand(executablePath: "/opt/homebrew/bin/copilot")
            == "env -u COPILOT_HOME -u COPILOT_GITHUB_TOKEN -u GH_TOKEN -u GITHUB_TOKEN '/opt/homebrew/bin/copilot' login")
        #expect(CopilotCLI.manualLoginCommand(executablePath: "/tmp/it's/copilot")
            .hasSuffix("'/tmp/it'\\''s/copilot' login"))
    }

    @Test func missingExecutablePrintsInstallGuidanceAndExits127() throws {
        let script = CopilotCLI.loginScript(executablePath: nil)
        #expect(script.contains(CopilotCLI.installationURL.absoluteString))
        #expect(script.contains("exit 127"))
        #expect(try Self.parsesAsZsh(script))
    }

    @Test func handoffClearsTokenAndHomeOverridesBeforeRunningTheOfficialCLI() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-copilot-login-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("copilot")
        try """
        #!/bin/zsh
        [[ "$1" == login && -z "${COPILOT_HOME-}" && -z "${COPILOT_GITHUB_TOKEN-}" && -z "${GH_TOKEN-}" && -z "${GITHUB_TOKEN-}" ]]
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let script = root.appendingPathComponent("login.command")
        try CopilotCLI.loginScript(executablePath: executable.path)
            .write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        process.environment = [
            "TERM": "xterm-256color",
            "COPILOT_HOME": "/tmp/wrong-home",
            "COPILOT_GITHUB_TOKEN": "test-override",
            "GH_TOKEN": "test-override",
            "GITHUB_TOKEN": "test-override",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func signedOutRoutesToSignInAndMissingCLIToInstall() {
        #expect(ProviderSetupOutcome.copilotSignedOut.recoveryPresentation.primaryAction == .connectCopilot)
        #expect(ProviderSetupOutcome.copilotCLIMissing.recoveryPresentation.primaryAction == .installCopilotCLI)
    }

    /// An unreadable log is never a sign-in problem: Check Now re-reads the logs and no
    /// action opens Terminal.
    @Test func unreadableLogsOfferOnlyAFreshCheck() {
        let presentation = ProviderSetupOutcome.copilotLogsUnreadable.recoveryPresentation
        #expect(presentation.primaryAction == .checkNow)
        #expect(presentation.secondaryAction == nil)
        #expect(!ProviderSetupOutcome.copilotLogsUnreadable.isPermanent)
    }

    private static func parsesAsZsh(_ script: String) throws -> Bool {
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n"]
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
