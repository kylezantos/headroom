import Foundation

/// Official Grok Build login handoff. Headroom launches this command in Terminal and
/// observes only a redaction-safe completion marker; credentials remain CLI-owned.
public enum GrokCLI {
    public static let executableName = "grok"
    public static let loginCommand = "grok login"

    public static func resolveExecutable() -> String? {
        GrokACPUsageSource.resolveGrokPath()
    }

    public static func accountLoginCommand(
        grokHome: String?,
        mode: SetupHandoffMode = .standard,
        executablePath: String? = nil
    ) -> String {
        let home = grokHome.map { "GROK_HOME=\(shellQuoted($0)) " } ?? "env -u GROK_HOME "
        let executable = executablePath.map(shellQuoted) ?? "grok"
        return "\(home)\(executable) \(loginArguments(for: mode).joined(separator: " "))"
    }

    public static func loginScript(
        executablePath: String?,
        grokHome: String? = nil,
        mode: SetupHandoffMode = .standard,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        let accountExport = grokHome.map { "export GROK_HOME=\(shellQuoted($0))\n" } ?? "unset GROK_HOME\n"
        let accountNote = grokHome == nil ? "" : """
        echo "Sign in with the Grok account you want to add. This login is kept separate"
        echo "from your main Grok Build account."
        echo
        """
        let flowTitle = mode == .deviceCode
            ? "Headroom is opening the official Grok device-code sign-in flow."
            : "Headroom is opening the official Grok sign-in flow."
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
            echo "Grok Build CLI was not found. Install or update it, then run: \(loginCommand)"
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
          echo "The Grok Build CLI moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        \(launch)
        """
    }

    private static func loginArguments(for mode: SetupHandoffMode) -> [String] {
        ["login"] + (mode == .deviceCode ? ["--device-auth"] : [])
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
