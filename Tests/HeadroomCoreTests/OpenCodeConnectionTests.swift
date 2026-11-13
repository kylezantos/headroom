import Foundation
import Testing
@testable import HeadroomCore

/// U5 (OpenCode plan, KTD11): the Terminal sign-in script. Generated scripts run for real
/// against a fake `opencode` (`/bin/sh`), never a real client.
@Suite struct OpenCodeConnectionTests {
    private static let isolatedRoot = "/tmp/headroom oc/acct"
    private static let isolated = OpenCodeAccountHome.isolated(root: isolatedRoot)

    // MARK: - Script text

    @Test func extraAccountExportsAllFourXDGValuesBeforeTheLoginAndNeverAsAPrefix() {
        let script = OpenCodeCLI.loginScript(executablePath: "/opt/homebrew/bin/opencode", home: Self.isolated)
        let lines = script.components(separatedBy: "\n")
        let loginIndex = lines.firstIndex { $0.contains("auth login --standalone opencode --method device") }
        #expect(loginIndex != nil)
        for name in OpenCodeCLI.xdgVariables {
            let folder = String(name.dropFirst(4).dropLast(5)).lowercased()
            let export = "export \(name)='\(Self.isolatedRoot)/\(folder)'"
            let exportIndex = lines.firstIndex(of: export)
            #expect(exportIndex != nil, "missing \(export)")
            if let exportIndex, let loginIndex { #expect(exportIndex < loginIndex) }
        }
        // The login line itself is the bare quoted executable, never `XDG_…=… opencode`.
        if let loginIndex {
            #expect(lines[loginIndex] == "'/opt/homebrew/bin/opencode' auth login --standalone opencode --method device")
        }
    }

    @Test func builtInUnsetsXDGAndClearsEveryOpenCodeVariable() {
        let script = OpenCodeCLI.loginScript(executablePath: "/opt/homebrew/bin/opencode", home: .builtIn)
        #expect(script.contains("unset XDG_DATA_HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME"))
        #expect(script.contains("for name in ${(k)parameters[(I)OPENCODE_*]}; do unset \"$name\"; done"))
        #expect(!script.contains("export XDG_"))
        // The same lines the probe's rule produces: the two can never drift.
        for line in OpenCodeCLI.shellEnvironmentLines(for: .builtIn) { #expect(script.contains(line)) }
    }

    @Test func resetRunsLogoutThenLoginAndEndsWithTheLoginStatus() {
        let script = OpenCodeCLI.loginScript(
            executablePath: "/opt/homebrew/bin/opencode",
            home: .builtIn,
            purpose: .reset
        )
        let logout = script.range(of: "'/opt/homebrew/bin/opencode' auth logout --standalone opencode")
        let login = script.range(of: "'/opt/homebrew/bin/opencode' auth login --standalone opencode --method device")
        #expect(logout != nil && login != nil)
        if let logout, let login { #expect(logout.lowerBound < login.lowerBound) }
        #expect(!script.contains("auth logout --standalone opencode &&"))
        #expect(script.contains("pick it, then sign in to Console again") || script.contains("Pick it, then sign in to Console again"))
    }

    @Test func scriptsCarryNoWorkspaceEmailOrToken() {
        for purpose in [SetupHandoffPurpose.setup, .reset] {
            for home in [OpenCodeAccountHome.builtIn, Self.isolated] {
                let script = OpenCodeCLI.loginScript(
                    executablePath: "/opt/homebrew/bin/opencode",
                    home: home,
                    purpose: purpose,
                    completionMarker: SetupCompletionMarker(pendingPath: "/tmp/p", completedPath: "/tmp/c")
                )
                let manual = OpenCodeCLI.manualLoginCommand(
                    executablePath: "/opt/homebrew/bin/opencode", home: home, purpose: purpose
                )
                for text in [script, manual] {
                    #expect(!text.contains("wrk_"))
                    #expect(!text.localizedCaseInsensitiveContains("token"))
                    #expect(!text.contains("OPENCODE_API_KEY"))
                    #expect(text.firstMatch(of: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/) == nil)
                }
            }
        }
    }

    @Test func manualCommandNamesTheResolvedPathInsideAnExportedSubshell() {
        let manual = OpenCodeCLI.manualLoginCommand(executablePath: "/Users/t/.opencode/bin/opencode", home: Self.isolated)
        #expect(manual.hasPrefix("zsh -c '("))
        #expect(manual.contains("/Users/t/.opencode/bin/opencode"))
        #expect(manual.contains("export XDG_DATA_HOME="))
        #expect(manual.contains("auth login --standalone opencode --method device"))
    }

    @Test func installTextNamesTheTwoXDocsPage() {
        let script = OpenCodeCLI.loginScript(executablePath: nil, home: .builtIn)
        #expect(script.contains("OpenCode 2.2 or newer from https://opencode.ai/docs/"))
        #expect(script.contains("exit 127"))
    }

    // MARK: - Staging decisions

    @Test func versionGateRefusesOneXAndEarlyTwoXButStagesUnreadable() {
        #expect(OpenCodeCLI.signInSupport(versionOutput: "opencode v2.2.5\n") == .supported)
        #expect(OpenCodeCLI.signInSupport(versionOutput: "2.3.0") == .supported)
        #expect(OpenCodeCLI.signInSupport(versionOutput: "1.1.53\n") == .tooOld)
        #expect(OpenCodeCLI.signInSupport(versionOutput: "2.1.9") == .tooOld)
        #expect(OpenCodeCLI.signInSupport(versionOutput: nil) == .unreadable)
        #expect(OpenCodeCLI.signInSupport(versionOutput: "warning: x\n2.2.5") == .unreadable)
    }

    @Test func executableOverrideReachesExtraHomesOnly() {
        #expect(OpenCodeCLI.signInExecutable(for: .builtIn, override: "/stub/opencode", resolve: { "/real/opencode" })
            == "/real/opencode")
        #expect(OpenCodeCLI.signInExecutable(for: Self.isolated, override: "/stub/opencode", resolve: { "/real/opencode" })
            == "/stub/opencode")
        #expect(OpenCodeCLI.signInExecutable(for: Self.isolated, override: nil, resolve: { nil }) == nil)
    }

    @Test func installURLIsTheDocsPageThatListsTwoXInstalls() {
        #expect(OpenCodeCLI.installationURL.absoluteString == "https://opencode.ai/docs/")
    }

    // MARK: - Scripts run for real against a fake client

    @Test func extraScriptRunsLoginWithOnlyTheAccountsEnvironment() throws {
        let run = try FakeOpenCodeRun()
        let root = run.directory.appendingPathComponent("acct").path
        let result = try run.execute(OpenCodeCLI.loginScript(
            executablePath: FakeOpenCodeRun.fakePath, home: .isolated(root: root)
        ))
        #expect(result.status == 0)
        let log = run.log
        #expect(log.filter { $0.hasPrefix("argv:") } == ["argv:auth login --standalone opencode --method device"])
        let env = Set(log.filter { $0.hasPrefix("env:") })
        #expect(env == [
            "env:OPENCODE_DISABLE_AUTOUPDATE=1",
            "env:OPENCODE_DISABLE_MODELS_FETCH=1",
            "env:XDG_CACHE_HOME=\(root)/cache",
            "env:XDG_CONFIG_HOME=\(root)/config",
            "env:XDG_DATA_HOME=\(root)/data",
            "env:XDG_STATE_HOME=\(root)/state",
        ])
    }

    @Test func builtInScriptUnsetsXDGAndInheritedOpenCodeVariables() throws {
        let run = try FakeOpenCodeRun()
        let result = try run.execute(OpenCodeCLI.loginScript(executablePath: FakeOpenCodeRun.fakePath, home: .builtIn))
        #expect(result.status == 0)
        let env = Set(run.log.filter { $0.hasPrefix("env:") })
        #expect(env == ["env:OPENCODE_DISABLE_AUTOUPDATE=1", "env:OPENCODE_DISABLE_MODELS_FETCH=1"])
    }

    @Test func failedLoginIsTheRecordedStatus() throws {
        let run = try FakeOpenCodeRun(loginStatus: 3)
        let result = try run.executeWrapped(OpenCodeCLI.self, home: .builtIn, purpose: .setup)
        #expect(result.status == 3)
        #expect(result.completion == .failed)
        #expect(result.output.contains("Sign-in didn’t finish."))
    }

    @Test func successfulLoginRecordsSuccessThroughTheWrapper() throws {
        let run = try FakeOpenCodeRun()
        let result = try run.executeWrapped(OpenCodeCLI.self, home: .builtIn, purpose: .setup)
        #expect(result.status == 0)
        #expect(result.completion == .succeeded)
    }

    /// KTD11: logout exits 1 with no stored credential and 130 when cancelled. Either way
    /// login runs and its status is what the wrapper records.
    @Test(arguments: [Int32(0), 1, 130])
    func resetIgnoresLogoutStatusAndRecordsLogin(_ logoutStatus: Int32) throws {
        for loginStatus: Int32 in [0, 4] {
            let run = try FakeOpenCodeRun(loginStatus: loginStatus, logoutStatus: logoutStatus)
            let result = try run.executeWrapped(OpenCodeCLI.self, home: .builtIn, purpose: .reset)
            #expect(run.log.filter { $0.hasPrefix("argv:") } == [
                "argv:auth logout --standalone opencode",
                "argv:auth login --standalone opencode --method device",
            ])
            #expect(result.status == loginStatus)
            #expect(result.completion == (loginStatus == 0 ? .succeeded : .failed))
        }
    }

    /// A Ctrl-C during the logout picker ends only the logout: the wrapper's `exit 130` trap
    /// is suspended for it, so the login still runs.
    @Test func interruptDuringLogoutStillRunsLogin() throws {
        let run = try FakeOpenCodeRun(logoutStatus: 130, logoutInterruptsParent: true)
        let result = try run.executeWrapped(OpenCodeCLI.self, home: .builtIn, purpose: .reset)
        #expect(run.log.filter { $0.hasPrefix("argv:") }.last == "argv:auth login --standalone opencode --method device")
        #expect(result.status == 0)
        #expect(result.completion == .succeeded)
    }

    /// The clipboard fallback runs as pasted into any shell (here `/bin/sh -c`), routes both
    /// reset commands through the account's environment, and ends with the login's status.
    @Test func manualCommandRunsAsPastedWithTheAccountsEnvironment() throws {
        let run = try FakeOpenCodeRun(loginStatus: 5, logoutStatus: 1)
        let root = run.directory.appendingPathComponent("it's acct").path
        let command = OpenCodeCLI.manualLoginCommand(
            executablePath: FakeOpenCodeRun.fakePath, home: .isolated(root: root), purpose: .reset
        )
        let status = try run.executeShell(command)
        #expect(status == 5)
        let log = run.log
        #expect(log.filter { $0.hasPrefix("argv:") } == [
            "argv:auth logout --standalone opencode",
            "argv:auth login --standalone opencode --method device",
        ])
        #expect(log.filter { $0 == "env:XDG_DATA_HOME=\(root)/data" }.count == 2)
        #expect(!log.contains { $0.hasPrefix("env:OPENCODE_API_KEY") || $0.hasPrefix("env:OPENCODE_CONFIG=") })
    }

    @Test func missingCLIExits127WithInstallText() throws {
        let run = try FakeOpenCodeRun()
        let missing = try run.execute(OpenCodeCLI.loginScript(executablePath: nil, home: .builtIn))
        #expect(missing.status == 127)
        #expect(missing.output.contains("Install OpenCode 2.2 or newer from https://opencode.ai/docs/"))

        let moved = try run.execute(OpenCodeCLI.loginScript(
            executablePath: run.directory.appendingPathComponent("gone/opencode").path, home: .builtIn
        ))
        #expect(moved.status == 127)
        #expect(run.log.isEmpty)
    }

    @Test func wrappedScriptsParseAsZsh() throws {
        for purpose in [SetupHandoffPurpose.setup, .reset] {
            for home in [OpenCodeAccountHome.builtIn, Self.isolated] {
                let script = OpenCodeCLI.loginScript(
                    executablePath: "/opt/homebrew/bin/opencode",
                    home: home,
                    purpose: purpose,
                    completionMarker: SetupCompletionMarker(pendingPath: "/tmp/p", completedPath: "/tmp/c")
                )
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
        }
    }
}

/// One scratch directory per test, plus a fake `opencode` written once per process, so no
/// test writes an executable just before running it ("text file busy", BUGS.md). The fake
/// logs its arguments and every `XDG_*`/`OPENCODE_*` variable it sees, and exits with the
/// status the test's control files name.
private struct FakeOpenCodeRun {
    static let fakePath: String = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-fake-opencode-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("opencode").path
        let body = """
        #!/bin/sh
        c="$FAKE_OPENCODE_CONTROL"
        { printf 'argv:%s\\n' "$*"; env | grep -E '^(XDG_|OPENCODE_)' | sort | sed 's/^/env:/'; } >> "$c/log"
        s=0
        case "$1 $2" in
          "auth login") [ -f "$c/login-status" ] && s=$(cat "$c/login-status") ;;
          "auth logout")
            [ -f "$c/logout-status" ] && s=$(cat "$c/logout-status")
            [ -f "$c/logout-interrupt" ] && kill -INT "$PPID"
            ;;
        esac
        exit "$s"
        """
        FileManager.default.createFile(atPath: path, contents: Data(body.utf8), attributes: [.posixPermissions: 0o755])
        return path
    }()

    let directory: URL

    init(loginStatus: Int32 = 0, logoutStatus: Int32 = 0, logoutInterruptsParent: Bool = false) throws {
        _ = Self.fakePath
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-oc-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "\(loginStatus)".write(to: directory.appendingPathComponent("login-status"), atomically: true, encoding: .utf8)
        try "\(logoutStatus)".write(to: directory.appendingPathComponent("logout-status"), atomically: true, encoding: .utf8)
        if logoutInterruptsParent {
            FileManager.default.createFile(atPath: directory.appendingPathComponent("logout-interrupt").path, contents: nil)
        }
    }

    var log: [String] {
        ((try? String(contentsOf: directory.appendingPathComponent("log"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    struct Result {
        let status: Int32
        let output: String
        let completion: SetupHandoffCompletion?
    }

    func execute(_ script: String, marker: SetupCompletionMarker? = nil) throws -> Result {
        let scriptURL = directory.appendingPathComponent("setup-\(UUID().uuidString).command")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        // Hostile inherited values the script must clear before the client sees them.
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": directory.path,
            "TERM": "dumb",
            "FAKE_OPENCODE_CONTROL": directory.path,
            "XDG_DATA_HOME": "/should/not/reach/data",
            "XDG_STATE_HOME": "/should/not/reach/state",
            "OPENCODE_API_KEY": "inherited-not-a-secret",
            "OPENCODE_CONFIG": "/should/not/reach/config.json",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self),
            completion: marker.map { AccountStorage.setupHandoffCompletion(marker: $0) }
        )
    }

    func executeShell(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": directory.path,
            "FAKE_OPENCODE_CONTROL": directory.path,
            "XDG_DATA_HOME": "/should/not/reach/data",
            "OPENCODE_API_KEY": "inherited-not-a-secret",
            "OPENCODE_CONFIG": "/should/not/reach/config.json",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func executeWrapped(
        _: OpenCodeCLI.Type,
        home: OpenCodeAccountHome,
        purpose: SetupHandoffPurpose
    ) throws -> Result {
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("markers/pending").path,
            completedPath: directory.appendingPathComponent("markers/complete").path
        )
        try AccountStorage.prepareSetupCompletionMarker(marker, mode: .standard, purpose: purpose)
        return try execute(
            OpenCodeCLI.loginScript(
                executablePath: Self.fakePath, home: home, purpose: purpose, completionMarker: marker
            ),
            marker: marker
        )
    }
}
