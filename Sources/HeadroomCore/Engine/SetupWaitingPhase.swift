import Foundation

// KTD11 (2026-10-02 widget-styles plan): `SetupWaitingPhase` lives beside the coordinator
// because it resolves over coordinator types (`SetupSessionState`, `SetupHandoffPurpose`,
// `SetupHandoffMode`, `SetupHandoffCompletion`). `ProviderSetup.swift` is compiled into the
// iOS targets and those types are not, so keeping the phase there broke both iOS schemes.

/// R7/KTD11 (2026-09-19 sign-in plan): which of the three waiting phases a session is in.
/// It is a pure value over the typed session state rather than a field inside
/// `.waiting(attempt:)`, which `providerCardSessionKey` deliberately flattens — and every
/// phase change here coincides with a change to the coordinator's observed `states`
/// dictionary, which is what repaints the surfaces.
///
/// The old waiting body claimed "Headroom checks this account automatically", which stopped
/// being true for an exit-signalled handoff (KTD6): nothing is checked until the CLI process
/// exits.
public enum SetupWaitingPhase: Sendable, Equatable {
    /// Headroom is staging the script and handing it to Terminal.
    case openingTerminal
    /// The window is open and the next move is the user's.
    case waitingForUser(SetupWaitingPrompt)
    /// Terminal has closed and Headroom is reading the account. `reportedFinished` is the
    /// wrapper's own `.succeeded`, which distinguishes "sign-in said it finished" from a
    /// window that closed with no verdict.
    case confirming(SetupWaitingPrompt, reportedFinished: Bool)

    /// KTD11: the whole derivation, so a surface never assembles the phase itself.
    /// Returns nil when the session is not in a waiting phase at all — including the
    /// timeout, which is a typed failure with its own copy and its own actions (KTD12).
    public static func resolve(
        state: SetupSessionState,
        hasActiveHandoff: Bool,
        purpose: SetupHandoffPurpose?,
        mode: SetupHandoffMode = .standard,
        interactiveReason: ClaudeInteractiveLaunchReason? = nil,
        reportedCompletion: SetupHandoffCompletion? = nil,
        providerID: ProviderID? = nil
    ) -> SetupWaitingPhase? {
        let prompt = prompt(
            purpose: purpose,
            mode: mode,
            interactiveReason: interactiveReason,
            providerID: providerID
        )
        switch state {
        case .preparing:
            return .openingTerminal
        case .waiting, .verifying:
            return hasActiveHandoff
                ? .waitingForUser(prompt)
                : .confirming(prompt, reportedFinished: reportedCompletion == .succeeded)
        default:
            return nil
        }
    }

    /// R6/AE3: approval is always the interactive launch, so the `/login` hint has to be
    /// gated on the *reason* rather than on the launch shape — otherwise every approval
    /// handoff would tell the user to sign in again.
    private static func prompt(
        purpose: SetupHandoffPurpose?,
        mode: SetupHandoffMode,
        interactiveReason: ClaudeInteractiveLaunchReason?,
        providerID: ProviderID?
    ) -> SetupWaitingPrompt {
        // KTD11 (OpenCode plan): every OpenCode sign-in is the device-code login, whatever
        // mode the session was started in; a reset first asks which login to sign out.
        if providerID == .opencode {
            return purpose == .reset ? .deviceCodeAfterSignOut : .deviceCode
        }
        if purpose == .trust {
            // A startup question reuses the approval launch; only the reason recorded at
            // staging tells the two apart, so neither borrows the other's sentence.
            return interactiveReason == .startupQuestion ? .startupQuestion : .workspaceApproval
        }
        if mode == .deviceCode { return .deviceCode }
        guard purpose == .setup, interactiveReason == .versionUnreadable else { return .signIn }
        return .signInNeedsLoginCommand
    }

    public var copy: SetupWaitingCopy {
        switch self {
        case .openingTerminal:
            // Purpose-neutral on purpose: nothing has been asked of the user yet, and a
            // sign-in sentence here would be wrong for an approval handoff.
            return .init(
                title: "Opening Terminal…",
                body: "Headroom is handing this account to the official CLI."
            )
        case .waitingForUser(let prompt):
            return Self.waitingCopy(for: prompt)
        case .confirming(let prompt, let reportedFinished):
            return Self.confirmingCopy(for: prompt, reportedFinished: reportedFinished)
        }
    }

    private static func waitingCopy(for prompt: SetupWaitingPrompt) -> SetupWaitingCopy {
        switch prompt {
        case .signIn:
            // CA-P9 (COPY-03): "signing in in" read as a typo, and "Headroom continues" did
            // not say what the user would see.
            .init(
                title: "Waiting for sign-in…",
                body: "Finish signing in with your browser. Your usage shows up here when you’re done."
            )
        case .signInNeedsLoginCommand:
            .init(
                title: "Waiting for sign-in…",
                body: "In Terminal, type the command below and press Return, then finish in your browser.",
                token: .init(text: "/login", isCommand: true)
            )
        case .workspaceApproval:
            // R2C6: the sentence used to end "Headroom connects as soon as you approve" —
            // the one verb the sign-in vocabulary retired. CA-P9: every waiting body now ends
            // with what the user will see, as the sign-in body does.
            .init(
                title: "Waiting for approval…",
                body: "Choose the option below in Terminal. Your usage shows up here when you approve.",
                token: .init(text: "“Yes, I trust this folder”", isCommand: false)
            )
        case .startupQuestion:
            // No token: Headroom never answers the question, so it names no option to pick.
            .init(
                title: "Waiting for Claude Code…",
                body: "Answer Claude Code’s question in Terminal. Your usage shows up here when you’re done."
            )
        case .deviceCode:
            .init(
                title: "Waiting for device code…",
                body: "Follow the device-code steps in Terminal. Your usage shows up here when the code is accepted."
            )
        case .deviceCodeAfterSignOut:
            .init(
                title: "Waiting for device code…",
                body: "In Terminal, pick the login to sign out, then follow the device-code steps. Your usage shows up here when the code is accepted."
            )
        }
    }

    private static func confirmingCopy(
        for prompt: SetupWaitingPrompt,
        reportedFinished: Bool
    ) -> SetupWaitingCopy {
        if prompt == .workspaceApproval {
            return reportedFinished
                ? .init(
                    title: "Confirming approval…",
                    body: "Terminal closed. Headroom is reading your usage."
                )
                : .init(
                    title: "Checking approval…",
                    body: "Terminal closed. Headroom is checking whether the approval finished."
                )
        }
        if prompt == .startupQuestion {
            return reportedFinished
                ? .init(
                    title: "Confirming…",
                    body: "Terminal closed. Headroom is reading your usage."
                )
                : .init(
                    title: "Checking Claude Code…",
                    body: "Terminal closed. Headroom is checking whether Claude Code is ready."
                )
        }
        return reportedFinished
            ? .init(
                title: "Confirming sign-in…",
                body: "Terminal closed. Headroom is reading your usage."
            )
            : .init(
                title: "Checking sign-in…",
                body: "Terminal closed. Headroom is checking whether sign-in finished."
            )
    }
}
