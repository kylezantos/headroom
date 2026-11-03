import Foundation

/// Official GitHub Copilot CLI login handoff. Headroom observes only the wrapper's
/// redaction-safe exit marker and never reads or copies the stored login.
public enum CopilotCLI {
    public static let executableName = "copilot"
    public static let loginCommand = "copilot login"
    public static let installationURL = URL(string: "https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli")!

    /// These variables override the stored login (`copilot help environment`), and an
    /// inherited `COPILOT_HOME` would sign in somewhere the meter never reads, so the
    /// handoff clears all of them. `CopilotStatusSource` clears this same list for its server.
    static let clearedVariables = ["COPILOT_HOME", "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"]

    public static func resolveExecutable() -> String? {
        CopilotStatusSource.resolveExecutablePath()
    }

    public static func manualLoginCommand(executablePath: String) -> String {
        let unsets = clearedVariables.map { "-u \($0)" }.joined(separator: " ")
        return "env \(unsets) \(shellQuoted(executablePath)) login"
    }

    public static func loginScript(
        executablePath: String?,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        let introduction = """
        #!/bin/zsh
        clear
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        unset \(clearedVariables.joined(separator: " "))
        echo "Headroom is opening the official GitHub Copilot CLI sign-in flow."
        echo "Complete sign-in in the browser, then return to Headroom."
        echo "Headroom never receives your password or sign-in details."
        echo
        """

        guard let executablePath else {
            return introduction + "\n" + """
            echo "GitHub Copilot CLI was not found. Install it from \(installationURL.absoluteString)"
            echo "then run: \(loginCommand)"
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        let invocation = "\(executable) login"
        let launch = completionMarker.map {
            SetupCompletionCommand.wrap(invocation, marker: $0, mode: .standard)
        } ?? "exec \(invocation)"
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "GitHub Copilot CLI moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        \(launch)
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
