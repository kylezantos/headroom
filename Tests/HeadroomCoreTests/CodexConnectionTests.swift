import Foundation
import Testing
@testable import HeadroomCore

struct CodexConnectionTests {
    @Test func missingCredentialsRequestInitialConnection() {
        let snapshot = UsageSnapshot.stale(
            for: .codex,
            reason: .providerSetup(.codexAuthAbsent)
        )

        #expect(snapshot.codexConnectionAction == .connect)
        #expect(CodexCLI.loginCommand == "codex login")
    }

    @Test func rejectedCredentialsRequestReconnectAndKeepWindows() {
        let window = UsageWindow(
            kind: .weekly,
            utilization: 42,
            resetsAt: Date(timeIntervalSince1970: 2_000_000)
        )
        let snapshot = UsageSnapshot(
            providerID: .codex,
            windows: [window],
            planLabel: "plus",
            capturedAt: Date(timeIntervalSince1970: 1_000_000),
            freshness: .stale(.needsReauth("Session expired — run `codex login` to reconnect"))
        )

        #expect(snapshot.codexConnectionAction == .reconnect)
        #expect(snapshot.windows == [window])
    }

    @Test func permissionAndStorageFailuresNeverRouteIntoLoginLoop() {
        let permission = UsageSnapshot.stale(for: .codex, reason: .providerSetup(.codexPermissionDenied))
        let mismatch = UsageSnapshot.stale(for: .codex, reason: .providerSetup(.codexStorageMismatch))

        #expect(permission.codexConnectionAction == .showPrivacyGuidance)
        #expect(mismatch.codexConnectionAction == .resolveStorage)
    }

    @Test func unrelatedStatesDoNotRequestCodexConnection() {
        let excluded: [UsageSnapshot] = [
            .pending(for: .codex),
            UsageSnapshot(
                providerID: .codex,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .live
            ),
            .stale(for: .codex, reason: .transient("Network unavailable")),
            .stale(for: .codex, reason: .decode("Couldn’t decode")),
            .stale(for: .codex, reason: .scopeDenied("Scope unavailable")),
            .stale(for: .claude, reason: .notLoggedIn("Run Claude")),
        ]

        for snapshot in excluded {
            #expect(snapshot.codexConnectionAction == nil)
        }
    }

    @Test func selectsExecutableFromLoginShellIncludingVersionManagers() {
        let executablePaths: Set<String> = [
            "/opt/homebrew/bin/codex",
            "/Users/test/.local/bin/codex",
            "/Users/test/.nvm/versions/node/v24.18.0/bin/codex",
        ]

        for path in executablePaths {
            #expect(
                CLIExecutableResolver.selectExecutable(
                    loginShellOutput: "__HEADROOM_EXECUTABLE__\n\(path)\n",
                    fallbackPaths: [],
                    isExecutable: executablePaths.contains
                ) == path
            )
        }
    }

    @Test func executableResolutionFallsBackAndFailsClosed() {
        let fallback = "/usr/local/bin/codex"
        #expect(
            CLIExecutableResolver.selectExecutable(
                loginShellOutput: "__HEADROOM_EXECUTABLE__\n/missing/codex\n",
                fallbackPaths: ["/also/missing", fallback],
                isExecutable: { $0 == fallback }
            ) == fallback
        )
        #expect(
            CLIExecutableResolver.selectExecutable(
                loginShellOutput: "__HEADROOM_EXECUTABLE__\n/missing/codex\n",
                fallbackPaths: ["/also/missing"],
                isExecutable: { _ in false }
            ) == nil
        )
    }

    @Test func executableResolutionIgnoresInteractiveShellStartupOutput() {
        let staleStartupPath = "/opt/homebrew/bin/codex"
        let resolvedPath = "/Users/test/.nvm/versions/node/v24/bin/codex"
        let output = "Welcome\n\(staleStartupPath)\n__HEADROOM_EXECUTABLE__\n\(resolvedPath)\n"

        #expect(
            CLIExecutableResolver.selectExecutable(
                loginShellOutput: output,
                fallbackPaths: [staleStartupPath],
                isExecutable: { $0 == staleStartupPath || $0 == resolvedPath }
            ) == resolvedPath
        )
    }

    @Test func loginPathResolutionIgnoresInteractiveShellStartupOutput() {
        let output = "Welcome to the shell\n__HEADROOM_PATH__/nvm/bin:/usr/bin\n"

        #expect(
            CLIExecutableResolver.selectLoginPath(
                loginShellOutput: output,
                fallback: "/usr/local/bin:/usr/bin"
            ) == "/nvm/bin:/usr/bin:/usr/local/bin:/usr/bin"
        )
        #expect(
            CLIExecutableResolver.selectLoginPath(
                loginShellOutput: "/untrusted/startup/output",
                fallback: "/usr/bin:/bin"
            ) == "/usr/bin:/bin"
        )
    }

    @Test func generatedLoginScriptUsesOnlyQuotedExecutableAndAllowlistedArgument() {
        let script = CodexCLI.loginScript(executablePath: "/Users/Test User/bin/cod'ex")

        #expect(script.contains("exec '/Users/Test User/bin/cod'\\''ex' -c cli_auth_credentials_store=file login"))
        #expect(script.contains("Headroom never receives your password or sign-in details"))
        #expect(!script.localizedCaseInsensitiveContains("access_token"))
        #expect(!script.localizedCaseInsensitiveContains("authorization"))
        #expect(!script.contains("backend-api"))
    }

    @Test func generatedLoginScriptsParseAsZsh() throws {
        for executablePath in ["/opt/homebrew/bin/codex", nil] as [String?] {
            let process = Process()
            let standardInput = Pipe()
            let standardError = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-n"]
            process.standardInput = standardInput
            process.standardError = standardError

            try process.run()
            standardInput.fileHandleForWriting.write(Data(CodexCLI.loginScript(executablePath: executablePath).utf8))
            try standardInput.fileHandleForWriting.close()
            process.waitUntilExit()

            let error = String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            #expect(process.terminationStatus == 0, "Generated login script failed zsh syntax validation: \(error)")
        }
    }

    @Test func missingExecutableScriptFailsClearlyWithoutGuessingACommand() {
        let script = CodexCLI.loginScript(executablePath: nil)

        #expect(script.contains("Codex CLI was not found"))
        #expect(script.contains("exit 127"))
        #expect(!script.contains("exec codex"))
    }
}
