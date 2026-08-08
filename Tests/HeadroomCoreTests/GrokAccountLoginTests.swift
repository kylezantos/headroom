import Foundation
import Testing
@testable import HeadroomCore

/// The account-scoped Grok handoff routes the official CLI through `GROK_HOME`.
/// Generated scripts contain only the executable, allowlisted arguments, and paths.
@Suite struct GrokAccountLoginTests {
    @Test func builtInLoginCommandUsesTheDefaultCLIHome() {
        #expect(GrokCLI.accountLoginCommand(grokHome: nil) == "env -u GROK_HOME grok login")
    }

    @Test func extraAccountCommandExportsGrokHomeQuoted() {
        let command = GrokCLI.accountLoginCommand(
            grokHome: "/Users/x/Library/Application Support/Headroom/Accounts/grok/abc"
        )
        #expect(command == "GROK_HOME='/Users/x/Library/Application Support/Headroom/Accounts/grok/abc' grok login")
    }

    @Test func deviceCodeUsesTheSameIsolatedAccountHome() {
        let command = GrokCLI.accountLoginCommand(grokHome: "/tmp/grok-home", mode: .deviceCode)
        let script = GrokCLI.loginScript(
            executablePath: "/opt/homebrew/bin/grok",
            grokHome: "/tmp/grok-home",
            mode: .deviceCode
        )

        #expect(command == "GROK_HOME='/tmp/grok-home' grok login --device-auth")
        #expect(script.contains("export GROK_HOME='/tmp/grok-home'"))
        #expect(script.contains("exec '/opt/homebrew/bin/grok' login --device-auth"))
        #expect(script.contains("device-code instructions"))
    }

    @Test func twoDeviceCodeScriptsRemainBoundToDistinctCredentialHomes() throws {
        let accountsBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-grok-device-code-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: accountsBase) }
        let accounts = [
            ProviderAccount(id: AccountID("grok-personal"), providerID: .grok, label: "Personal", isBuiltIn: false),
            ProviderAccount(id: AccountID("grok-work"), providerID: .grok, label: "Work", isBuiltIn: false),
        ]

        let bindings = try accounts.map { account in
            let home = try AccountStorage.ensureDirectories(for: account, baseDirectoryURL: accountsBase)
            let configuredHome = ProviderAccountConfiguration.make(
                for: account,
                accountsBase: accountsBase
            ).grokHomeDirectory
            let script = GrokCLI.loginScript(
                executablePath: "/opt/homebrew/bin/grok",
                grokHome: configuredHome?.path,
                mode: .deviceCode
            )
            return (home, configuredHome, script)
        }

        #expect(bindings[0].0 != bindings[1].0)
        for binding in bindings {
            #expect(binding.0 == binding.1)
            #expect(FileManager.default.fileExists(atPath: binding.0.path))
            #expect(binding.2.contains("export GROK_HOME='\(binding.0.path)'"))
            #expect(binding.2.contains("exec '/opt/homebrew/bin/grok' login --device-auth"))
        }
        #expect(!bindings[0].2.contains(bindings[1].0.path))
        #expect(!bindings[1].2.contains(bindings[0].0.path))
    }

    @Test func generatedScriptIsRedactedAndParsesAsZsh() throws {
        let sensitiveSentinel = "credential-material-must-never-appear"
        let script = GrokCLI.loginScript(
            executablePath: "/opt/homebrew/bin/grok",
            grokHome: "/tmp/grok-home",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/setup pending",
                completedPath: "/tmp/setup complete"
            )
        )

        #expect(!script.contains(sensitiveSentinel))
        #expect(script.contains("'/opt/homebrew/bin/grok' login"))
        #expect(script.contains("complete:${setup_status}"))
        #expect(script.contains("print -r -- \"standard:$$\""))

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
        #expect(process.terminationStatus == 0)
    }

    @Test func accountHomeWithSingleQuoteIsShellSafe() {
        let command = GrokCLI.accountLoginCommand(grokHome: "/tmp/o'brien")
        #expect(command.contains("'/tmp/o'\\''brien'"))
    }
}
