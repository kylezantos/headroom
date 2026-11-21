import Foundation

/// The official Antigravity CLI's sign-in handoff. `agy acp --login` is the CLI's own
/// documented terminal sign-in ("Log in with Google interactively, then exit"), so its exit
/// is the completion signal. Headroom observes only the wrapper's redaction-safe exit marker
/// and never reads or copies the stored sign-in.
public extension AntigravityCLI {
    static let loginArguments = ["acp", "--login"]
    static let loginCommand = "agy acp --login"
    static let installationURL = URL(string: "https://antigravity.google/")!

    static func manualLoginCommand(executablePath: String) -> String {
        ([shellQuoted(executablePath)] + loginArguments).joined(separator: " ")
    }

    static func loginScript(
        executablePath: String?,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        let introduction = """
        #!/bin/zsh
        clear
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        echo "Headroom is opening the official Antigravity CLI sign-in."
        echo "Sign in with Google in the browser or follow the steps in this window, then return to Headroom."
        echo "Headroom never receives your password or sign-in details."
        echo
        """

        guard let executablePath else {
            return introduction + "\n" + """
            echo "Antigravity CLI was not found. Install it from \(installationURL.absoluteString)"
            echo "then run: \(loginCommand)"
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        let invocation = ([executable] + loginArguments).joined(separator: " ")
        let launch = completionMarker.map {
            SetupCompletionCommand.wrap(invocation, marker: $0, mode: .standard)
        } ?? "exec \(invocation)"
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "The Antigravity CLI moved or is no longer executable. Reopen Headroom and try again."
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
