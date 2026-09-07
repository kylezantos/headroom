public extension ProviderCapabilityState {
    var recoveryPresentation: ProviderRecoveryPresentation? {
        switch self {
        case .unknown, .discovering, .available:
            nil
        case .inconclusive:
            .init(
                status: "Couldn't confirm where Claude Code is — will retry",
                primaryLabel: "Check again",
                primaryAction: .checkNow,
                secondaryLabel: "Open guided setup",
                secondaryAction: .openClaudeSetup
            )
        case .confirmedAbsent:
            .init(
                status: "Install Claude Code to show usage",
                primaryLabel: "Install Claude Code",
                primaryAction: .installClaudeCLI,
                // R7: a confirmed-absent CLI has no manual command to copy; the only
                // useful second action is a fresh forced discovery search.
                secondaryLabel: "Check again",
                secondaryAction: .checkNow
            )
        }
    }
}
