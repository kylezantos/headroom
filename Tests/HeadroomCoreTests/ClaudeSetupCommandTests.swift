import Foundation
import Testing
@testable import HeadroomCore

@Suite struct ClaudeSetupCommandTests {
    private let account = AccountKey(providerID: .claude, accountID: AccountID("extra"))

    @Test func builtInAndAdditionalDescriptorsUseExactRouting() {
        let builtIn = ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/Users/Test User/.local/bin/claude",
            loginPath: "/Users/Test User/.local/bin:/usr/bin:/bin",
            workspaceDirectory: "/Users/Test User/Library/Application Support/Headroom/ClaudeProbe",
            configDirectory: nil
        )
        let extra = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.nvm/bin/claude",
            loginPath: "/Users/Test User/.nvm/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space"
        )

        #expect(ClaudeSetupCommand.script(for: builtIn).contains("unset CLAUDE_CONFIG_DIR"))
        #expect(ClaudeSetupCommand.script(for: builtIn).contains("exec '/Users/Test User/.local/bin/claude'"))
        #expect(ClaudeSetupCommand.script(for: extra).contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(ClaudeSetupCommand.script(for: extra).contains("cd '/tmp/work space'"))
        #expect(ClaudeSetupCommand.script(for: extra).contains("exec '/Users/Test User/.nvm/bin/claude'"))
    }

    @Test func pathsWithQuotesStayOneShellTokenAndScriptsParse() throws {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/tmp/o'brien/bin/claude",
            loginPath: "/tmp/o'brien/bin:/usr/bin",
            workspaceDirectory: "/tmp/o'brien/work space",
            configDirectory: "/tmp/o'brien/config space"
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        #expect(script.contains("'/tmp/o'\\''brien/bin/claude'"))
        #expect(script.contains("'/tmp/o'\\''brien/work space'"))

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

    @Test func missingExecutableFailsClearlyWithoutGuessing() {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: nil,
            loginPath: "/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config"
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        #expect(script.contains("Claude Code CLI was not found"))
        #expect(script.contains("exit 127"))
        #expect(!script.contains("exec claude"))
    }

    // KTD5: an unresolved executable has no valid manual launch command — substituting
    // bare `claude` would hand the user the lookup Headroom already failed.
    @Test func manualCommandIsUnavailableWithoutAResolvedExecutable() {
        let command = ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: nil,
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space"
        ))

        #expect(command == nil)
    }

    @Test func manualCommandQuotesResolvedPathsAndPreservesAccountRouting() throws {
        let extra = try #require(ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.npm-global/o'brien/bin/claude",
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space"
        )))
        let builtIn = try #require(ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/Users/Test User/.npm-global/bin/claude",
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: nil
        )))

        // KTD3 (2026-09-19 sign-in plan): one routing construction for script and manual
        // command. A one-command env prefix binds only to the first command, so the
        // two-command sign-in form would overwrite the default login.
        #expect(extra == "umask 077 && mkdir -p '/tmp/work space' && cd '/tmp/work space' && (export CLAUDE_CONFIG_DIR='/tmp/config space' && '/Users/Test User/.npm-global/o'\\''brien/bin/claude')")
        #expect(builtIn == "umask 077 && mkdir -p '/tmp/work space' && cd '/tmp/work space' && (unset CLAUDE_CONFIG_DIR && '/Users/Test User/.npm-global/bin/claude')")
        for command in [extra, builtIn] {
            #expect(!command.hasSuffix(" claude"))
            #expect(!command.contains(account.accountID.raw))
            // KTD1: an `interactive` handoff never hands the user an `auth` subcommand.
            #expect(!command.contains("auth status"))
            #expect(!command.contains("auth login"))
        }
    }

    @Test func resetUsesOfficialLogoutThenLoginWithTheSameSafeAccountRouting() throws {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.npm-global/o'brien/bin/claude",
            loginPath: "/Users/Test User/.npm-global/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space",
            purpose: .reset
        )

        let script = ClaudeSetupCommand.script(for: descriptor)
        let manual = try #require(ClaudeSetupCommand.manualCommand(for: descriptor))
        let executable = "'/Users/Test User/.npm-global/o'\\''brien/bin/claude'"

        #expect(script.contains("\(executable) auth logout && \(executable) auth login"))
        #expect(manual.contains("\(executable) auth logout && \(executable) auth login"))
        #expect(script.contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(manual.contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(!script.contains("api.anthropic.com"))
        #expect(!manual.contains("api.anthropic.com"))

        let builtIn = ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/built-in work",
            configDirectory: nil,
            purpose: .reset
        )
        let builtInScript = ClaudeSetupCommand.script(for: builtIn)
        let builtInManual = try #require(ClaudeSetupCommand.manualCommand(for: builtIn))
        #expect(builtInScript.contains("unset CLAUDE_CONFIG_DIR"))
        #expect(builtInManual.contains("(unset CLAUDE_CONFIG_DIR && '/opt/homebrew/bin/claude' auth logout && '/opt/homebrew/bin/claude' auth login)"))
    }

    // KTD1: the `signIn` kind runs the status guard, then the official `auth login`.
    // The guard reads the `loggedIn` field — the one field every Headroom usage check
    // has always depended on — and only a literal true counts as signed in.
    @Test func signInScriptGuardsOnTheLoggedInFieldThenRunsTheOfficialLogin() throws {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/built-in work",
            configDirectory: nil,
            scriptKind: .signIn
        )
        let script = ClaudeSetupCommand.script(for: descriptor)

        #expect(script.contains("unset CLAUDE_CONFIG_DIR"))
        #expect(script.contains("'/opt/homebrew/bin/claude' auth status --json 2>/dev/null | grep -q"))
        #expect(script.contains("\"loggedIn\""))
        #expect(script.contains("'/opt/homebrew/bin/claude' auth login"))
        #expect(script.contains("already signed in"))
        // KTD1: the sign-in script replaces the bare launch, it does not wrap it.
        #expect(!script.contains("exec '/opt/homebrew/bin/claude'"))
        try expectParsesUnderZsh(script)
    }

    // KTD2: `auth status` prints the signed-in email and organization, so the window
    // Headroom opened shows none of it.
    @Test func signInScriptSendsTheStatusGuardOutputToTheNullDevice() {
        let script = ClaudeSetupCommand.script(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config",
            scriptKind: .signIn
        ))

        let statusRuns = script.ranges(of: "auth status")
        #expect(statusRuns.count == 1)
        for run in statusRuns {
            #expect(script[run.upperBound...].hasPrefix(" --json 2>/dev/null | grep -q"))
        }
    }

    @Test func signInScriptExportsTheExtraAccountConfigHomeBeforeBothCommands() throws {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.nvm/bin/claude",
            loginPath: "/Users/Test User/.nvm/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space",
            scriptKind: .signIn
        )
        let script = ClaudeSetupCommand.script(for: descriptor)

        let export = try #require(script.range(of: "export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        let status = try #require(script.range(of: "auth status"))
        let login = try #require(script.range(of: "auth login"))
        #expect(export.upperBound < status.lowerBound)
        #expect(export.upperBound < login.lowerBound)
        #expect(!script.contains("unset CLAUDE_CONFIG_DIR"))
        try expectParsesUnderZsh(script)
    }

    // KTD2: the invocation saves the login status, prints the result line, and returns
    // the saved status, so a failed sign-in is never recorded as `.succeeded` by the
    // wrapper's `exit $?`.
    @Test func signInInvocationReturnsTheSavedLoginStatusAfterTheResultLine() throws {
        let marker = SetupCompletionMarker(pendingPath: "/tmp/setup pending", completedPath: "/tmp/setup complete")
        let script = ClaudeSetupCommand.script(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config",
            completionMarker: marker,
            scriptKind: .signIn
        ))

        let capture = try #require(script.range(of: "headroom_signin_status=$?"))
        let resultLine = try #require(script.range(of: "Sign-in finished."))
        let statusReturn = try #require(script.range(of: "( exit $headroom_signin_status )"))
        #expect(capture.upperBound < resultLine.lowerBound)
        #expect(resultLine.upperBound < statusReturn.lowerBound)
        // The saved status is the last command before the wrapper's `exit $?`, so the
        // wrapper records sign-in's status and never the result line's echo.
        #expect(script[statusReturn.upperBound...].hasPrefix("\nexit $?"))
        try expectParsesUnderZsh(script)
    }

    // AE6: the copied manual command runs against the account's Headroom-owned config
    // folder, never the default login. KTD2/Review (2026-09-19 sign-in review): it runs
    // the same `loggedIn` guard the script runs, so `auth login` follows only an account
    // that is signed out and none of the status output — which names the signed-in email
    // and organization — reaches the user's own terminal.
    @Test func signInManualCommandGuardsOnTheLoggedInFieldInsideTheExportedSubshell() throws {
        let extra = try #require(ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.npm-global/o'brien/bin/claude",
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space",
            scriptKind: .signIn
        )))
        let builtIn = try #require(ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: nil,
            scriptKind: .signIn
        )))

        #expect(extra == "umask 077 && mkdir -p '/tmp/work space' && cd '/tmp/work space' && (export CLAUDE_CONFIG_DIR='/tmp/config space' && '/Users/Test User/.npm-global/o'\\''brien/bin/claude' auth status --json 2>/dev/null | grep -qE '\"loggedIn\"[[:space:]]*:[[:space:]]*true([[:space:]]*[,}]|$)' || '/Users/Test User/.npm-global/o'\\''brien/bin/claude' auth login)")
        #expect(builtIn == "umask 077 && mkdir -p '/tmp/work space' && cd '/tmp/work space' && (unset CLAUDE_CONFIG_DIR && '/opt/homebrew/bin/claude' auth status --json 2>/dev/null | grep -qE '\"loggedIn\"[[:space:]]*:[[:space:]]*true([[:space:]]*[,}]|$)' || '/opt/homebrew/bin/claude' auth login)")
        #expect(!extra.contains(account.accountID.raw))
        // The counterpart of `signInScriptSendsTheStatusGuardOutputToTheNullDevice`: the
        // one `auth status` in the copied line is the guard, and its output is piped into
        // `grep -q` with stderr discarded, so the terminal shows none of it.
        for command in [extra, builtIn] {
            let statusRuns = command.ranges(of: "auth status")
            #expect(statusRuns.count == 1)
            for run in statusRuns {
                #expect(command[run.upperBound...].hasPrefix(" --json 2>/dev/null | grep -q"))
            }
            try expectParsesUnderZsh(command)
        }
    }

    // KTD1: `interactive` stays today's bare launch byte-for-byte, so the render
    // harness and every caller that never names a kind are unchanged.
    @Test func interactiveKindIsTheDefaultAndKeepsTodaysScript() {
        let implied = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config"
        )
        let explicit = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config",
            scriptKind: .interactive
        )
        let script = ClaudeSetupCommand.script(for: implied)

        #expect(implied.scriptKind == .interactive)
        #expect(script == ClaudeSetupCommand.script(for: explicit))
        #expect(script.contains("Sign in with the Claude account you want to add, then approve the Headroom workspace if asked."))
        #expect(script.hasSuffix("exec '/opt/homebrew/bin/claude'"))
        #expect(!script.contains("auth status"))
        #expect(!script.contains("auth login"))
    }

    // KTD2: `.reset` keeps the official logout-then-login pair and gains the same
    // status-preserving result line, so its recorded status is still sign-in's.
    @Test func resetScriptGainsTheResultLineWithoutChangingItsRecordedStatus() throws {
        let marker = SetupCompletionMarker(pendingPath: "/tmp/setup pending", completedPath: "/tmp/setup complete")
        let executable = "'/opt/homebrew/bin/claude'"
        let script = ClaudeSetupCommand.script(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config",
            purpose: .reset,
            completionMarker: marker
        ))

        #expect(script.contains("\(executable) auth logout && \(executable) auth login"))
        let capture = try #require(script.range(of: "headroom_signin_status=$?"))
        let resultLine = try #require(script.range(of: "Sign-in finished."))
        let statusReturn = try #require(script.range(of: "( exit $headroom_signin_status )"))
        #expect(capture.upperBound < resultLine.lowerBound)
        #expect(resultLine.upperBound < statusReturn.lowerBound)
        #expect(script[statusReturn.upperBound...].hasPrefix("\nexit $?"))
        try expectParsesUnderZsh(script)
    }

    // KTD2, end to end against a local stub CLI: a failed `auth login` is recorded as
    // `.failed`, not masked by the result line's own echo.
    @Test func signInScriptRecordsAFailedLoginDespiteTheResultLine() throws {
        let run = try runSignInScript(authStatusJSON: #"{"loggedIn":false}"#, loginExitStatus: 7)

        #expect(run.terminationStatus == 7)
        #expect(run.completion == .failed)
        #expect(run.output.contains("Sign-in didn’t finish."))
        #expect(!run.output.contains("Sign-in finished."))
        #expect(run.ranLogin)
    }

    // R2/KTD2: an account signed in from the user's own Terminal between the click and
    // the script ends the handoff at 0 without starting a sign-in, and none of the
    // status output — which carries the email and organization — reaches the window.
    @Test func signInScriptStopsAtTheGuardWhenTheAccountIsAlreadySignedIn() throws {
        let run = try runSignInScript(
            authStatusJSON: #"{"loggedIn":true,"email":"person@example.com","organization":"Example Org"}"#,
            loginExitStatus: 7
        )

        #expect(run.terminationStatus == 0)
        #expect(run.completion == .succeeded)
        #expect(run.output.contains("already signed in"))
        #expect(!run.ranLogin)
        #expect(!run.output.contains("person@example.com"))
        #expect(!run.output.contains("Example Org"))
    }

    private struct SignInRun {
        let terminationStatus: Int32
        let output: String
        let ranLogin: Bool
        let completion: SetupHandoffCompletion?
    }

    /// Drives the generated script against a local stub that answers `auth status` and
    /// `auth login`. Never the real CLI, network or Keychain.
    private func runSignInScript(authStatusJSON: String, loginExitStatus: Int32) throws -> SignInRun {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-signin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let loginRan = directory.appendingPathComponent("login-ran")
        let stub = directory.appendingPathComponent("claude")
        try """
        #!/bin/zsh
        if [[ "$1" == "auth" && "$2" == "status" ]]; then
          print -r -- '\(authStatusJSON)'
          exit 1
        fi
        if [[ "$1" == "auth" && "$2" == "login" ]]; then
          print -r -- "ran" > '\(loginRan.path)'
          exit \(loginExitStatus)
        fi
        exit 99
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)

        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let scriptURL = directory.appendingPathComponent("setup.command")
        try ClaudeSetupCommand.script(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: stub.path,
            loginPath: "/usr/bin:/bin",
            workspaceDirectory: directory.path,
            configDirectory: directory.path,
            completionMarker: marker,
            scriptKind: .signIn
        )).write(to: scriptURL, atomically: true, encoding: .utf8)
        try AccountStorage.prepareSetupCompletionMarker(marker, mode: .standard, purpose: .setup)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.environment = ["TERM": "dumb"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let captured = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return SignInRun(
            terminationStatus: process.terminationStatus,
            output: String(decoding: captured, as: UTF8.self),
            ranLogin: FileManager.default.fileExists(atPath: loginRan.path),
            completion: AccountStorage.setupHandoffCompletion(marker: marker)
        )
    }

    @Test func signInScriptQuotesPathsAndCarriesNoProviderPayloadOrIdentity() throws {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/tmp/o'brien/bin/claude",
            loginPath: "/tmp/o'brien/bin:/usr/bin",
            workspaceDirectory: "/tmp/o'brien/work space",
            configDirectory: "/tmp/o'brien/config space",
            scriptKind: .signIn
        )
        let script = ClaudeSetupCommand.script(for: descriptor)

        #expect(script.contains("'/tmp/o'\\''brien/bin/claude'"))
        #expect(script.contains("'/tmp/o'\\''brien/work space'"))
        for forbidden in ["access_token", "Authorization", "backend-api", "api.anthropic.com", account.accountID.raw] {
            #expect(!script.localizedCaseInsensitiveContains(forbidden))
        }
        try expectParsesUnderZsh(script)
    }

    @Test func signInWithoutAResolvedExecutableStillFailsClearly() {
        let script = ClaudeSetupCommand.script(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: nil,
            loginPath: "/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config",
            scriptKind: .signIn
        ))

        #expect(script.contains("Claude Code CLI was not found"))
        #expect(script.contains("exit 127"))
        #expect(!script.contains("auth login"))
    }

    private func expectParsesUnderZsh(
        _ script: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
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
        #expect(process.terminationStatus == 0, sourceLocation: sourceLocation)
    }

    // AE6: an npm-derived launcher reaches the staged handoff with the account's
    // isolated config home, workspace, completion marker, and one-token quoting.
    @Test func npmDerivedLauncherKeepsExtraAccountIsolationInTheStagedScript() throws {
        let marker = SetupCompletionMarker(
            pendingPath: "/tmp/setup pending",
            completedPath: "/tmp/setup complete"
        )
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.npm-global/bin/claude",
            loginPath: "/Users/Test User/.npm-global/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space",
            completionMarker: marker
        )
        let script = ClaudeSetupCommand.script(for: descriptor)

        #expect(script.contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(script.contains("cd '/tmp/work space'"))
        #expect(script.contains("'/Users/Test User/.npm-global/bin/claude'"))
        #expect(script.contains("'/tmp/setup complete'"))
        #expect(!script.contains("exec claude"))

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

    @Test func generatedScriptContainsNoProviderPayloadOrIdentity() {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config"
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        for forbidden in ["access_token", "Authorization", "backend-api", account.accountID.raw] {
            #expect(!script.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func completionMarkerWrapperIsRedactedAndZshValid() throws {
        let marker = SetupCompletionMarker(pendingPath: "/tmp/setup pending", completedPath: "/tmp/setup complete")
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config",
            completionMarker: marker
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        #expect(script.contains("HEADROOM_SETUP_OWNER=\"${setup_purpose}:standard:${handoff_generation}:$$\""))
        #expect(script.contains("complete:${setup_purpose}:${handoff_generation}:${setup_status}"))
        #expect(!script.contains(account.accountID.raw))

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

    @Test func completionWrapperRecordsExitAndDeletesPendingScript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-wrapper-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("setup.command")
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let script = ClaudeSetupCommand.script(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/usr/bin/true",
            loginPath: "/usr/bin:/bin",
            workspaceDirectory: directory.path,
            configDirectory: directory.path,
            purpose: .reset,
            completionMarker: marker
        ))
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try AccountStorage.prepareSetupCompletionMarker(
            marker,
            mode: .standard,
            purpose: .reset
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.environment = ["TERM": "xterm-256color"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))
        #expect(!FileManager.default.fileExists(atPath: scriptURL.path))
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .succeeded)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .reset)
    }
}

@Suite struct ClaudeUsageWorkspaceTests {
    @Test func provisioningCreatesAnAbsentWorkspaceWithOwnerOnlyPermissions() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)

        #expect(!FileManager.default.fileExists(atPath: workspace.path))

        let provisioned = try ClaudeUsageWorkspace.ensureDirectory(at: workspace)
        var isDirectory: ObjCBool = false
        #expect(provisioned == workspace)
        #expect(FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        let attributes = try FileManager.default.attributesOfItem(atPath: workspace.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o700)
    }

    @Test func provisioningDoesNotRechmodAnExistingUsableWorkspace() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-existing-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workspace.path)

        #expect(try ClaudeUsageWorkspace.ensureDirectory(at: workspace) == workspace)
        let attributes = try FileManager.default.attributesOfItem(atPath: workspace.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o755)
    }

    // Brief 03 step 2: the workspace's local settings turn Remote Control auto-connect off.

    @Test func provisioningWritesOwnerOnlyRemoteControlOptOut() throws {
        let parent = temporaryParent("rc-optout")
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)

        try ClaudeUsageWorkspace.ensureDirectory(at: workspace)

        let settings = localSettingsURL(workspace)
        #expect(try permissions(of: settings) == 0o600)
        #expect(try permissions(of: settings.deletingLastPathComponent()) == 0o700)
        let object = try readObject(settings)
        #expect(object["remoteControlAtStartup"] as? Bool == false)
        #expect(object.count == 1)
    }

    @Test func optOutMergesIntoExistingSettingsAndFlipsATrue() throws {
        let parent = temporaryParent("rc-merge")
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let settings = localSettingsURL(workspace)
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(#"{"permissions":{"allow":["Bash(ls)"]},"remoteControlAtStartup":true}"#.utf8)
            .write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path)

        try ClaudeUsageWorkspace.ensureDirectory(at: workspace)

        let object = try readObject(settings)
        #expect(object["remoteControlAtStartup"] as? Bool == false)
        let permissionsBlock = object["permissions"] as? [String: Any]
        #expect(permissionsBlock?["allow"] as? [String] == ["Bash(ls)"])
        #expect(try permissions(of: settings) == 0o600)
    }

    @Test func optOutIsIdempotent() throws {
        let parent = temporaryParent("rc-idempotent")
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)
        try ClaudeUsageWorkspace.ensureDirectory(at: workspace)
        let settings = localSettingsURL(workspace)
        let first = try Data(contentsOf: settings)
        let firstModified = try FileManager.default.attributesOfItem(atPath: settings.path)[.modificationDate] as? Date

        try ClaudeUsageWorkspace.ensureDirectory(at: workspace)
        try ClaudeUsageWorkspace.ensureRemoteControlOptOut(in: workspace)

        #expect(try Data(contentsOf: settings) == first)
        let secondModified = try FileManager.default.attributesOfItem(atPath: settings.path)[.modificationDate] as? Date
        #expect(firstModified == secondModified)
    }

    @Test func optOutLeavesANonObjectSettingsFileAlone() throws {
        let parent = temporaryParent("rc-invalid")
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let settings = localSettingsURL(workspace)
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let original = Data("{ not json".utf8)
        try original.write(to: settings)

        // Provisioning still succeeds; the opt-out is best effort.
        #expect(try ClaudeUsageWorkspace.ensureDirectory(at: workspace) == workspace)
        #expect(try Data(contentsOf: settings) == original)
    }

    private func temporaryParent(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func localSettingsURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.local.json")
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private func readObject(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
