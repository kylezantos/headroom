import Foundation

/// The official Codex CLI handoff owned by Headroom. Keeping the executable and
/// arguments here prevents provider copy, Terminal execution, and clipboard fallback
/// from drifting onto different login commands.
public enum CodexCLI {
    public static let executableName = "codex"
    public static let loginArguments = ["login"]
    public static let loginCommand = "codex login"
    public static let fileStoreOverride = "cli_auth_credentials_store=file"

    public static func resolveExecutable() -> String? {
        CLIExecutableResolver.resolve(
            named: executableName,
            fallbackPaths: [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "\(NSHomeDirectory())/.local/bin/codex",
            ]
        )
    }

    /// The manual login command for an account. Extra accounts route the CLI at their
    /// Headroom-owned home via `CODEX_HOME`; the built-in account (nil home) is the
    /// plain official command.
    public static func accountLoginCommand(
        codexHome: String?,
        mode: SetupHandoffMode = .standard
    ) -> String {
        let home = codexHome.map { "CODEX_HOME=\(shellQuoted($0)) " } ?? "env -u CODEX_HOME "
        return "\(home)codex \(loginArguments(for: mode).joined(separator: " "))"
    }

    /// Static, redaction-safe Terminal content. The only runtime values are an absolute
    /// executable path returned by `CLIExecutableResolver` and a Headroom-owned account
    /// home directory, each quoted as one shell token.
    public static func loginScript(
        executablePath: String?,
        codexHome: String? = nil,
        mode: SetupHandoffMode = .standard,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        let accountExport = codexHome.map { "export CODEX_HOME=\(shellQuoted($0))\n" } ?? "unset CODEX_HOME\n"
        let accountNote = codexHome == nil ? "" : """
        echo "Sign in with the ChatGPT account you want to add. This login is kept separate"
        echo "from your main Codex CLI account."
        echo
        """
        let flowTitle = mode == .deviceCode
            ? "Headroom is opening the official Codex device-code sign-in flow."
            : "Headroom is opening the official Codex sign-in flow."
        let flowInstruction = mode == .deviceCode
            ? "Follow the device-code instructions in this window, then return to Headroom."
            : "Complete sign-in in the browser, then return to Headroom."
        let introduction = """
        #!/bin/zsh
        clear
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        \(accountExport)echo "\(flowTitle)"
        echo "\(flowInstruction)"
        echo "Headroom never receives your password or sign-in details."
        echo
        \(accountNote)
        """

        guard let executablePath else {
            return introduction + "\n" + """
            echo "Codex CLI was not found. Install or update Codex, then run: \(loginCommand)"
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        let invocation = "\(executable) \(loginArguments(for: mode).joined(separator: " "))"
        let launch = completionMarker.map {
            SetupCompletionCommand.wrap(invocation, marker: $0, mode: mode)
        } ?? "exec \(invocation)"
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "The Codex CLI moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        \(launch)
        """
    }

    private static func loginArguments(for mode: SetupHandoffMode) -> [String] {
        ["-c", fileStoreOverride, "login"] + (mode == .deviceCode ? ["--device-auth"] : [])
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum CodexConnectionAction: Sendable, Equatable {
    case connect
    case reconnect
    case showPrivacyGuidance
    case resolveStorage
}

public extension UsageSnapshot {
    /// Only typed Codex credential failures enter guided setup. Network, decoding,
    /// scope, pending, live, and other-provider states retain their normal UI.
    var codexConnectionAction: CodexConnectionAction? {
        guard providerID == .codex, case .stale(let reason) = freshness else { return nil }
        switch reason {
        case .notLoggedIn:
            return .connect
        case .needsReauth:
            return .reconnect
        case .providerSetup(let outcome):
            switch outcome {
            case .codexAuthAbsent: return .connect
            case .codexUnsafePermissions, .codexMalformedAuth, .codexRejectedAuth,
                 .codexCallbackIncomplete: return .reconnect
            case .codexPermissionDenied: return .showPrivacyGuidance
            case .codexStorageMismatch: return .resolveStorage
            default: return nil
            }
        case .transient, .scopeDenied, .decode:
            return nil
        }
    }
}
