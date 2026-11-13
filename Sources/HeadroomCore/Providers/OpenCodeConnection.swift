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
