public extension ProviderCapabilityState {
    /// B3T: Title Case, like every other button label (see `ProviderSetupOutcome`).
    ///
    /// PA11: `.checkNow` reads "Check Now" in every slot. "Check Again" used to appear in the
    /// same presentations for the same action, chosen only by whether the label landed in the
    /// primary or the secondary position — two words for one button make people wonder which
    /// one does something different. The footer keeps "Refresh" for the whole-app poll.
    var recoveryPresentation: ProviderRecoveryPresentation? {
        recoveryPresentation(hasRetainedReading: false)
    }

    /// R2C7: the sentence states the cause, the button names the act. "Install Claude Code
    /// to show usage" sat directly above **Install Claude Code**, spending the card's one
    /// explanatory line restating its own button.
    ///
    /// `hasRetainedReading` is true when the same card is still showing usage from an
    /// earlier capture — the live `capability-failure` capture puts three percentages and a
    /// "Stale" capsule under a sentence that never acknowledged them, leaving the reader to
    /// decide which half to believe.
    func recoveryPresentation(hasRetainedReading: Bool) -> ProviderRecoveryPresentation? {
        switch self {
        case .unknown, .discovering, .available:
            nil
        case .inconclusive:
            // CA-P9: two sentences, no em dash; the second is the retry sentence every
            // transient failure uses.
            .init(
                status: "Couldn’t confirm where Claude Code is. Headroom tries again on its next check.",
                primaryLabel: "Check Now",
                primaryAction: .checkNow,
                secondaryLabel: "Open Guided Setup",
                secondaryAction: .openClaudeSetup
            )
        case .confirmedAbsent:
            .init(
                status: ProviderSignInCopy.cliMissing(for: .claude, hasRetainedReading: hasRetainedReading),
                primaryLabel: "Install Claude Code",
                primaryAction: .installClaudeCLI,
                // R7: a confirmed-absent CLI has no manual command to copy; the only
                // useful second action is a fresh forced discovery search.
                secondaryLabel: "Check Now",
                secondaryAction: .checkNow
            )
        }
    }
}
