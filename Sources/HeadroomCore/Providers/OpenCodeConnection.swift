import Foundation

/// Where one OpenCode account's client state lives (KTD10). The built-in account reads the
/// same default home a plain Terminal `opencode` uses; an extra account reads only the four
/// Headroom-owned XDG folders under its own root.
public enum OpenCodeAccountHome: Sendable, Hashable {
    case builtIn
    /// `root` holds `data`, `config`, `cache` and `state`. The token-refresh lock lives under
    /// state, so data and state always come from the same root (KTD10).
    case isolated(root: String)

    /// The XDG values the child gets, keyed by variable name. Empty for the built-in account,
    /// whose four variables are unset instead.
    public var xdgValues: [String: String] {
        guard case .isolated(let root) = self else { return [:] }
        let base = URL(fileURLWithPath: root, isDirectory: true)
        return [
            "XDG_DATA_HOME": base.appendingPathComponent("data", isDirectory: true).path,
            "XDG_CONFIG_HOME": base.appendingPathComponent("config", isDirectory: true).path,
            "XDG_CACHE_HOME": base.appendingPathComponent("cache", isDirectory: true).path,
            "XDG_STATE_HOME": base.appendingPathComponent("state", isDirectory: true).path,
        ]
    }
}

/// The official OpenCode 2.x client: where to find it, and the one environment rule every
/// spawn and the Terminal sign-in script share (KTD2, KTD10), the way Copilot's probe and
/// handoff share `CopilotCLI.clearedVariables`.
public enum OpenCodeCLI {
    public static let executableName = "opencode"

    /// KTD2 step 4: every inherited variable with this prefix is cleared, because each one can
    /// select another server, config, credential or home (`OPENCODE_API_KEY`,
    /// `OPENCODE_CONFIG`, `OPENCODE_SERVER_PASSWORD`, …) and the list grows upstream.
    public static let clearedVariablePrefix = "OPENCODE_"

    /// KTD10: set for an extra account, unset for the built-in one.
    public static let xdgVariables = ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"]

    /// KTD2 step 2: the only `OPENCODE_*` values a child gets. Without the models flag every
    /// run downloads an 11 MB model catalog that is cached for only five minutes. Without the
    /// autoupdate flag a background poll could upgrade the user's own CLI behind their back;
    /// the 2.2.5 binary reads it.
    public static let fixedVariables = [
        "OPENCODE_DISABLE_MODELS_FETCH": "1",
        "OPENCODE_DISABLE_AUTOUPDATE": "1",
    ]

    public static func resolveExecutable() -> String? {
        CLIExecutableResolver.resolve(named: executableName, fallbackPaths: fallbackPaths)
    }

    /// `command -v` prints an alias instead of a path, and a Finder launch has a bare PATH, so
    /// these fixed paths still find the binary: the official install script's `~/.opencode/bin`,
    /// Homebrew (whose `opencode` formula is 2.x, U12), and the usual npm and local prefixes.
    static var fallbackPaths: [String] {
        [
            "\(NSHomeDirectory())/.opencode/bin/opencode",
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            "\(NSHomeDirectory())/.local/bin/opencode",
            "\(NSHomeDirectory())/.npm-global/bin/opencode",
        ]
    }

    /// The child environment for one account (KTD2, KTD10): the inherited environment with
    /// every `OPENCODE_*` and XDG variable removed, then only the fixed flags, the account's own
    /// XDG values (none for the built-in account) and the login-shell PATH set.
    public static func environment(
        inherited: [String: String],
        home: OpenCodeAccountHome,
        loginPath: String
    ) -> [String: String] {
        var result = inherited.filter { key, _ in
            !key.hasPrefix(clearedVariablePrefix) && !xdgVariables.contains(key)
        }
        fixedVariables.forEach { result[$0.key] = $0.value }
        home.xdgValues.forEach { result[$0.key] = $0.value }
        result["PATH"] = loginPath
        return result
    }

    /// The same rule as zsh lines, for the Terminal sign-in script (U5), so the script can
    /// never drift from the probe. `(k)parameters[(I)…]` expands every parameter whose name
    /// matches, exported or not.
    public static func shellEnvironmentLines(for home: OpenCodeAccountHome) -> [String] {
        var lines = [
            "for name in ${(k)parameters[(I)\(clearedVariablePrefix)*]}; do unset \"$name\"; done",
            "unset \(xdgVariables.joined(separator: " "))",
        ]
        lines += fixedVariables.keys.sorted().map { "export \($0)=\(shellQuoted(fixedVariables[$0]!))" }
        lines += xdgVariables.compactMap { name in
            home.xdgValues[name].map { "export \(name)=\(shellQuoted($0))" }
        }
        return lines
    }

    /// KTD2 step 3: a Headroom-owned folder outside any git repo. Inside a repo the client runs
    /// seven git commands and records the repo as a project.
    public static var defaultWorkingDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Headroom/OpenCodeProbe", isDirectory: true)
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

// MARK: - Sign-in handoff (U5, KTD11)

/// What staging decides from one `opencode --version` read, before any Terminal opens.
public enum OpenCodeSignInSupport: Sendable, Equatable {
    case supported
    /// Below 2.2.0. 1.x falls through to its TUI on `api` and `auth`, so staging refuses
    /// instead of running either on it (KTD3).
    case tooOld
    /// The version could not be read. Like Claude's R6 rule, a version-format change must not
    /// lock everyone out of sign-in, so this stages; every 1.x build prints a readable version.
    case unreadable
}

extension OpenCodeCLI {
    /// KTD21/U12 step 8: the docs page now lists only 2.x installs (the `v2/install` script,
    /// Homebrew `opencode-v2`, npm `@opencode/cli`). The bare `opencode.ai/install` script and
    /// npm `opencode-ai` still give 1.x, so neither is named anywhere in Headroom.
    public static let installationURL = URL(string: "https://opencode.ai/docs/")!

    /// KTD11: the Console device-code login. It binds no callback port (U12 (b),
    /// `plugin/provider/opencode.ts`), so OpenCode needs no exclusive login slot.
    static let loginArguments = ["auth", "login", "--standalone", "opencode", "--method", "device"]
    /// KTD11: always opens an account picker; exits 1 with no stored credential and 130
    /// when cancelled, so its status is never what the handoff reports.
    static let logoutArguments = ["auth", "logout", "--standalone", "opencode"]

    public static func signInSupport(versionOutput: String?) -> OpenCodeSignInSupport {
        guard let output = versionOutput, let version = OpenCodeVersion(versionOutput: output) else {
            return .unreadable
        }
        return version < OpenCodeCLIUsageSource.minimumVersion ? .tooOld : .supported
    }

    /// KTD18: the DEBUG executable override reaches extra-account homes only, never the
    /// built-in one: 2.x migrates a 1.x home one way on first use.
    public static func signInExecutable(
        for home: OpenCodeAccountHome,
        override: String?,
        resolve: () -> String? = { OpenCodeCLI.resolveExecutable() }
    ) -> String? {
        if case .isolated = home, let override { return override }
        return resolve()
    }

    /// The one `--version` read staging makes, with the account's own probe environment
    /// (KTD2, KTD10). No `api` or `auth` command runs before the version passes.
    public static func readVersionOutput(
        executablePath: String,
        home: OpenCodeAccountHome,
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) async -> String? {
        let loginPath = CLIExecutableResolver.resolveLoginPath(
            fallback: "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        )
        let environment = environment(inherited: inherited, home: home, loginPath: loginPath)
        let workingDirectory = defaultWorkingDirectory.path
        try? FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
        let output: OpenCodeRunOutput? = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: OpenCodeProcessRunner.run(
                    .version,
                    executable: executablePath,
                    interpreter: nil,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    deadline: OpenCodeCLIUsageSource.defaultVersionDeadline
                ))
            }
        }
        guard let output, output.exitCode == 0 else { return nil }
        return String(decoding: output.stdout, as: UTF8.self)
    }

    /// The clipboard fallback (Terminal refused the script). An exported subshell, never a
    /// one-command env prefix, so a reset's logout and login both read this account's home.
    public static func manualLoginCommand(
        executablePath: String,
        home: OpenCodeAccountHome,
        purpose: SetupHandoffPurpose = .setup
    ) -> String {
        let executable = shellQuoted(executablePath)
        let login = ([executable] + loginArguments).joined(separator: " ")
        let commands = purpose == .reset
            ? "{ \(([executable] + logoutArguments).joined(separator: " ")); \(login); }"
            : login
        let routing = shellEnvironmentLines(for: home).joined(separator: "; ")
        // zsh only: `(k)parameters` in the shared clearing line is zsh syntax.
        return "zsh -c \(shellQuoted("(\(routing); \(commands))"))"
    }

    /// KTD11: the Terminal script. The account's environment comes from the same lines the
    /// probe's rule produces (`shellEnvironmentLines`), and the script ends with the login's
    /// own status, because `SetupCompletionCommand.wrap` records the last command's status.
    public static func loginScript(
        executablePath: String?,
        home: OpenCodeAccountHome,
        purpose: SetupHandoffPurpose = .setup,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        let guidance: [String]
        switch (purpose, home) {
        case (.reset, _):
            guidance = [
                "OpenCode will ask which login to sign out. Pick it, then sign in to Console again.",
            ]
        case (_, .builtIn):
            guidance = ["This signs in to OpenCode Console for your default OpenCode setup on this Mac."]
        case (_, .isolated):
            guidance = [
                "Sign in with the OpenCode Console account you want to add. This login is kept",
                "separate from your default OpenCode setup.",
            ]
        }
        let introduction = (
            [
                "#!/bin/zsh",
                "clear",
                "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH\"",
            ]
            + shellEnvironmentLines(for: home)
            + ["echo \"Headroom is opening the official OpenCode device-code sign-in.\""]
            + guidance.map { "echo \"\($0)\"" }
            + [
                "echo \"Follow the device-code instructions in this window, then return to Headroom.\"",
                "echo \"Headroom never receives your password or sign-in details.\"",
                "echo",
            ]
        ).joined(separator: "\n")

        guard let executablePath else {
            return introduction + "\n" + """
            echo "OpenCode CLI was not found. Install OpenCode 2.2 or newer from \(installationURL.absoluteString)"
            echo "then reopen Headroom and sign in again."
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        let invocation = signInInvocation(executable: executable, purpose: purpose)
        let launch = completionMarker.map {
            SetupCompletionCommand.wrap(invocation, marker: $0, mode: .standard)
        } ?? invocation
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "The OpenCode CLI moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        \(launch)
        """
    }

    /// KTD11: a reset's logout status is ignored (1 with no stored credential, 130 when the
    /// picker is cancelled) and the login always runs. While logout runs, Ctrl-C ends only
    /// logout: the wrapper's `exit 130` INT trap is swapped for a no-op and restored after.
    private static func signInInvocation(executable: String, purpose: SetupHandoffPurpose) -> String {
        let login = ([executable] + loginArguments).joined(separator: " ")
        let logout = purpose == .reset ? """
        trap ':' INT
        \(([executable] + logoutArguments).joined(separator: " "))
        trap 'exit 130' INT
        echo

        """ : ""
        return """
        typeset headroom_signin_status=0
        \(logout)\(login)
        headroom_signin_status=$?
        if (( headroom_signin_status == 0 )); then
          echo "\(finishedLine)"
        else
          echo "\(unfinishedLine)"
        fi
        ( exit $headroom_signin_status )
        """
    }

    private static let finishedLine = "Sign-in finished. Headroom is checking your OpenCode account."
    private static let unfinishedLine = "Sign-in didn’t finish. Return to Headroom to try again."
}

// MARK: - Test-client seams (KTD18)

/// What `--probe-opencode` reads: which home, and which executable. A nil executable means
/// the normal resolution (`OpenCodeCLI.resolveExecutable`).
public struct OpenCodeProbeTarget: Sendable, Equatable {
    public let home: OpenCodeAccountHome
    public let executable: String?

    public init(home: OpenCodeAccountHome, executable: String?) {
        self.home = home
        self.executable = executable
    }
}

/// KTD18: the launch arguments that let an agent run a downloaded 2.x client against the
/// stub Console while the user's PATH still has 1.x. `--opencode-executable` exists in DEBUG
/// builds only. It reaches extra-account homes and a probe that names `--opencode-home`,
/// never the built-in home: 2.x migrates a 1.x home one way on first use.
public enum OpenCodeLaunchArguments {
    public static let probeFlag = "--probe-opencode"
    public static let homeFlag = "--opencode-home"
    public static let executableFlag = "--opencode-executable"

    public static var buildAllowsExecutableOverride: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The override path, or nil in a release build, when absent, or when the flag has no
    /// value. Callers must still keep it away from the built-in home
    /// (`OpenCodeExecutableOverrideRouter`, `probeTarget`).
    public static func executableOverride(
        arguments: [String],
        buildAllowsOverride: Bool = buildAllowsExecutableOverride
    ) -> String? {
        guard buildAllowsOverride, let value = value(after: executableFlag, in: arguments) else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    /// Nil when `--opencode-home` is present without a value: the probe must not fall back
    /// to the built-in home when an isolated one was asked for.
    public static func probeTarget(
        arguments: [String],
        buildAllowsOverride: Bool = buildAllowsExecutableOverride
    ) -> OpenCodeProbeTarget? {
        guard arguments.contains(homeFlag) else {
            return OpenCodeProbeTarget(home: .builtIn, executable: nil)
        }
        guard let root = value(after: homeFlag, in: arguments) else { return nil }
        return OpenCodeProbeTarget(
            home: .isolated(root: URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.path),
            executable: executableOverride(arguments: arguments, buildAllowsOverride: buildAllowsOverride)
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value.isEmpty || value.hasPrefix("--") ? nil : value
    }
}

/// KTD18: sends extra-account homes to the overridden client and the built-in home to the
/// normal one, whatever the override says. Sits under the one shared capture cache (KTD8).
public struct OpenCodeExecutableOverrideRouter: OpenCodeUsageSource {
    private let standard: any OpenCodeUsageSource
    private let overridden: any OpenCodeUsageSource

    public init(standard: any OpenCodeUsageSource, overridden: any OpenCodeUsageSource) {
        self.standard = standard
        self.overridden = overridden
    }

    public func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        switch home {
        case .builtIn: await standard.capture(home: home)
        case .isolated: await overridden.capture(home: home)
        }
    }
}
