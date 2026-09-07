import Testing
@testable import HeadroomCore

@Suite struct ProviderSetupOutcomeTests {
    @Test func onlyConfirmedProviderAbsenceOffersInstallation() {
        #expect(ProviderCapabilityState.confirmedAbsent.recoveryPresentation?.primaryAction == .installClaudeCLI)
        #expect(ProviderCapabilityState.inconclusive(.shellTimeout).recoveryPresentation?.primaryAction == .checkNow)
        #expect(ProviderCapabilityState.available.recoveryPresentation == nil)
    }

    // AE5/R7: confirmed absence offers installation plus a fresh discovery check —
    // never a copied command that repeats the failed bare-name lookup.
    @Test func confirmedAbsenceOffersInstallationAndAFreshCheckOnly() {
        let presentation = ProviderCapabilityState.confirmedAbsent.recoveryPresentation
        #expect(presentation?.primaryAction == .installClaudeCLI)
        #expect(presentation?.secondaryAction == .checkNow)
        #expect(presentation?.secondaryLabel == "Check again")

        let outcome = ProviderSetupOutcome.claudeCLIMissing.recoveryPresentation
        #expect(outcome.primaryAction == .installClaudeCLI)
        #expect(outcome.secondaryAction == .checkNow)
        #expect(outcome.secondaryLabel == "Check again")
    }

    // AE7/R7: incomplete discovery keeps the retry-oriented message and never claims
    // the CLI is absent.
    @Test func inconclusiveDiscoveryKeepsRetryRecoveryWithoutClaimingAbsence() {
        for issue in [CLIExecutableDiscoveryIssue.shellTimeout, .npmPrefixUnresolved] {
            let presentation = ProviderCapabilityState.inconclusive(issue).recoveryPresentation
            #expect(presentation?.primaryAction == .checkNow)
            #expect(presentation?.primaryLabel == "Check again")
            #expect(presentation?.secondaryAction == .openClaudeSetup)
            #expect(presentation?.status != ProviderCapabilityState.confirmedAbsent.recoveryPresentation?.status)
            #expect(presentation?.status.localizedCaseInsensitiveContains("install") == false)
        }
    }

    @Test func everyProviderOutcomeHasOneTypedRecoveryPresentation() {
        let expectations: [(ProviderSetupOutcome, SetupRecoveryAction, SetupRecoveryAction?, SetupAutomaticPolicy)] = [
            (.claudeCLIMissing, .installClaudeCLI, .checkNow, .none),
            (.claudeLoginRequired, .openClaudeSetup, .checkNow, .boundedChecksAfterHandoff),
            (.claudeTrustRequired, .openClaudeSetup, .checkNow, .boundedChecksAfterHandoff),
            (.claudeUnknownUI, .checkNow, .openClaudeSetup, .none),
            (.claudeTransientCapture, .checkNow, .openClaudeSetup, .none),
            (.codexCLIMissing, .installCodexCLI, nil, .none),
            (.codexAuthAbsent, .connectCodex, .connectCodexDeviceCode, .boundedChecksAfterHandoff),
            (.codexPermissionDenied, .showPrivacyGuidance, .checkNow, .none),
            (.codexUnsafePermissions, .reconnectCodex, .checkNow, .boundedChecksAfterHandoff),
            (.codexMalformedAuth, .reconnectCodex, .checkNow, .boundedChecksAfterHandoff),
            (.codexCredentialIO, .checkNow, nil, .none),
            (.codexRejectedAuth, .reconnectCodex, .checkNow, .boundedChecksAfterHandoff),
            (.codexStorageMismatch, .resolveCodexStorage, .checkNow, .none),
            (.codexCallbackIncomplete, .reconnectCodex, .connectCodexDeviceCode, .none),
            (.grokCLIMissing, .installGrokCLI, nil, .none),
            (.grokAuthAbsent, .connectGrok, .connectGrokDeviceCode, .boundedChecksAfterHandoff),
            (.grokPermissionDenied, .showPrivacyGuidance, .checkNow, .none),
            (.grokUnsafePermissions, .reconnectGrok, .checkNow, .boundedChecksAfterHandoff),
            (.grokMalformedAuth, .reconnectGrok, .checkNow, .boundedChecksAfterHandoff),
            (.grokCredentialIO, .checkNow, nil, .none),
            (.grokRejectedAuth, .reconnectGrok, .checkNow, .boundedChecksAfterHandoff),
            (.grokTransientCapture, .checkNow, nil, .none),
            (.cursorCLIMissing, .installCursorAgent, nil, .none),
            (.cursorAuthAbsent, .connectCursor, .checkNow, .boundedChecksAfterHandoff),
            (.cursorUnknownUI, .checkNow, .connectCursor, .none),
            (.cursorTransientCapture, .checkNow, .connectCursor, .none),
        ]

        for (outcome, primaryAction, secondaryAction, automaticPolicy) in expectations {
            let presentation = outcome.recoveryPresentation
            #expect(presentation.primaryAction == primaryAction)
            #expect(presentation.secondaryAction == secondaryAction)
            #expect(presentation.automaticPolicy == automaticPolicy)
            #expect(!presentation.status.isEmpty)
            #expect(!presentation.primaryLabel.isEmpty)
        }
    }

    @Test func changingDisplayCopyCannotChangeRecoveryAction() {
        let reason = FailureReason.providerSetup(.claudeTrustRequired)
        #expect(reason.providerSetupOutcome == .claudeTrustRequired)
        #expect(reason.providerSetupOutcome?.recoveryPresentation.primaryAction == .openClaudeSetup)
        #expect(reason.message == ProviderSetupOutcome.claudeTrustRequired.message)
    }

    @Test func onlyTransientSetupOutcomesAreRetryableWithoutUserAction() {
        #expect(!FailureReason.providerSetup(.claudeTransientCapture).isPermanent)
        #expect(!FailureReason.providerSetup(.claudeUnknownUI).isPermanent)
        #expect(FailureReason.providerSetup(.claudeLoginRequired).isPermanent)
        #expect(FailureReason.providerSetup(.codexPermissionDenied).isPermanent)
        #expect(!FailureReason.providerSetup(.grokTransientCapture).isPermanent)
        #expect(FailureReason.providerSetup(.grokPermissionDenied).isPermanent)
        #expect(!FailureReason.providerSetup(.cursorTransientCapture).isPermanent)
        #expect(FailureReason.providerSetup(.cursorAuthAbsent).isPermanent)
    }

    @Test func neverSignedInClassificationIsTyped() {
        #expect(ProviderSetupOutcome.claudeLoginRequired.isNeverSignedIn)
        #expect(ProviderSetupOutcome.codexAuthAbsent.isNeverSignedIn)
        #expect(ProviderSetupOutcome.grokAuthAbsent.isNeverSignedIn)
        #expect(ProviderSetupOutcome.cursorAuthAbsent.isNeverSignedIn)
        #expect(!ProviderSetupOutcome.claudeCLIMissing.isNeverSignedIn)
        #expect(!ProviderSetupOutcome.codexRejectedAuth.isNeverSignedIn)
    }
}
