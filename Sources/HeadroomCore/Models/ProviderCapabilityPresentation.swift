public extension ProviderCapabilityState {
    /// B3T: Title Case, like every other button label (see `ProviderSetupOutcome`).
    ///
    /// PA11: `.checkNow` reads "Check Now" in every slot. "Check Again" used to appear in the
    /// same presentations for the same action, chosen only by whether the label landed in the
    /// primary or the secondary position — two words for one button make people wonder which
    /// one does something different. The footer keeps "Refresh" for the whole-app poll.
    var recoveryPresentation: ProviderRecoveryPresentation? {
        switch self {
        case .unknown, .discovering, .available:
            nil
        case .inconclusive:
            .init(
                status: "Couldn’t confirm where Claude Code is — will retry",
                primaryLabel: "Check Now",
                primaryAction: .checkNow,
                secondaryLabel: "Open Guided Setup",
                secondaryAction: .openClaudeSetup
            )
        case .confirmedAbsent:
            .init(
                status: "Install Claude Code to show usage",
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
