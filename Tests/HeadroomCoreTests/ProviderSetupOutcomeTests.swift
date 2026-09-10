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
        #expect(presentation?.secondaryLabel == "Check Now")

        let outcome = ProviderSetupOutcome.claudeCLIMissing.recoveryPresentation
        #expect(outcome.primaryAction == .installClaudeCLI)
        #expect(outcome.secondaryAction == .checkNow)
        #expect(outcome.secondaryLabel == "Check Now")
    }

    // AE7/R7: incomplete discovery keeps the retry-oriented message and never claims
    // the CLI is absent.
    @Test func inconclusiveDiscoveryKeepsRetryRecoveryWithoutClaimingAbsence() {
        for issue in [CLIExecutableDiscoveryIssue.shellTimeout, .npmPrefixUnresolved] {
            let presentation = ProviderCapabilityState.inconclusive(issue).recoveryPresentation
            #expect(presentation?.primaryAction == .checkNow)
            #expect(presentation?.primaryLabel == "Check Now")
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

    /// PA11: one label per action. `.checkNow` used to read "Check Again" in a primary slot
    /// and "Check Now" in a secondary one — the same forced poll named two ways on adjacent
    /// cards. Every slot on both presentation surfaces now says "Check Now", and no label
    /// anywhere says "Check Again". "Refresh" stays reserved for the footer's whole-app poll
    /// and is deliberately never produced here.
    @Test func checkNowCarriesOneLabelInEverySlot() {
        var labels: [(String, SetupRecoveryAction?)] = []
        for outcome in allSetupOutcomes {
            let presentation = outcome.recoveryPresentation
            labels.append((presentation.primaryLabel, presentation.primaryAction))
            if let secondary = presentation.secondaryLabel {
                labels.append((secondary, presentation.secondaryAction))
            }
        }
        for state in [ProviderCapabilityState.inconclusive(.shellTimeout),
                      .inconclusive(.npmPrefixUnresolved),
                      .confirmedAbsent] {
            guard let presentation = state.recoveryPresentation else { continue }
            labels.append((presentation.primaryLabel, presentation.primaryAction))
            if let secondary = presentation.secondaryLabel {
                labels.append((secondary, presentation.secondaryAction))
            }
        }

        #expect(labels.contains { $0.1 == .checkNow })
        for (label, action) in labels {
            if action == .checkNow {
                #expect(label == "Check Now", "\(label) is bound to .checkNow")
            } else {
                #expect(label != "Check Now", "\(label) borrows the .checkNow label")
            }
            #expect(label != "Check Again")
            #expect(label != "Refresh")
        }
    }

    /// R2C6: one act, one verb. The flow used to alternate "sign in" / "connect" / "set up" /
    /// "needs sign-in" for the same click depending on which surface rendered it, so people
    /// had to work out whether the buttons did different things.
    @Test func signingInIsNamedOneWayInEverySentenceAndButton() {
        #expect(ProviderSetupOutcome.claudeLoginRequired.message == "Sign in with the official Claude CLI")
        #expect(ProviderSetupOutcome.codexAuthAbsent.message == "Sign in with the official Codex CLI")
        #expect(ProviderSetupOutcome.grokAuthAbsent.message == "Sign in with the official Grok Build CLI")
        #expect(ProviderSetupOutcome.cursorAuthAbsent.message == "Sign in with the official Cursor Agent CLI")
        #expect(ProviderSetupOutcome.codexRejectedAuth.message == "Sign in again with the official Codex CLI")
        #expect(ProviderSetupOutcome.grokRejectedAuth.message == "Sign in again with the official Grok Build CLI")

        for outcome in [ProviderSetupOutcome.claudeLoginRequired, .codexAuthAbsent,
                        .grokAuthAbsent, .cursorAuthAbsent] {
            #expect(outcome.recoveryPresentation.primaryLabel == "Sign In")
        }
        for outcome in [ProviderSetupOutcome.codexUnsafePermissions, .codexMalformedAuth,
                        .codexRejectedAuth, .grokUnsafePermissions, .grokMalformedAuth,
                        .grokRejectedAuth] {
            #expect(outcome.recoveryPresentation.primaryLabel == "Sign In Again")
        }
        #expect(ProviderSetupOutcome.cursorUnknownUI.recoveryPresentation.secondaryLabel == "Sign In Again")
    }

    /// R2C6: the retired synonyms may not come back on any surface. "Connect Codex",
    /// "Connect Grok", "Connect Cursor", "Reconnect …" and "Connect with the official …"
    /// all named the act the Claude card beside them called signing in.
    @Test func retiredSignInSynonymsAreGoneFromTheWholeSet() {
        for text in allPresentationStrings {
            #expect(!text.localizedCaseInsensitiveContains("connect"),
                    "\(text) still names signing in \"connect\"")
        }
    }

    /// R2C6: PA10's popover header, the guided setup card and the Settings account row read
    /// one vocabulary because they read one source.
    @Test func headerAndCardTitleShareTheSignInVocabulary() {
        #expect(ProviderSignInCopy.header(for: .claude) == "Sign in to Claude to begin")
        #expect(ProviderSignInCopy.header(for: .codex) == "Sign in to Codex to begin")
        #expect(ProviderSignInCopy.header(for: .codex, again: true) == "Sign in to Codex again")
        #expect(ProviderSignInCopy.cardTitle(for: .claude) == "Sign in to Claude")
        #expect(ProviderSignInCopy.cardTitle(for: .codex) == "Sign in to Codex")
        #expect(ProviderSignInCopy.cardTitle(for: .codex, again: true) == "Sign in to Codex again")
        #expect(ProviderSignInCopy.status(for: .claude) == ProviderSetupOutcome.claudeLoginRequired.message)
    }

    /// R2C7: the sentence states the cause; the button names the act. "Install Claude Code
    /// to show usage" sat directly above **Install Claude Code** on four providers at once.
    @Test func capabilityCopyStatesTheCauseInsteadOfRestatingItsButton() {
        let absent = ProviderCapabilityState.confirmedAbsent.recoveryPresentation
        #expect(absent?.status == "Headroom can’t find the Claude Code CLI on this Mac")
        #expect(absent?.primaryLabel == "Install Claude Code")
        #expect(absent?.status.localizedCaseInsensitiveContains("install") == false)

        #expect(ProviderSetupOutcome.claudeCLIMissing.message == "Headroom can’t find the Claude Code CLI on this Mac")
        #expect(ProviderSetupOutcome.codexCLIMissing.message == "Codex CLI isn’t installed on this Mac")
        #expect(ProviderSetupOutcome.grokCLIMissing.message == "Grok Build CLI isn’t installed on this Mac")
        #expect(ProviderSetupOutcome.cursorCLIMissing.message == "Cursor Agent CLI isn’t installed on this Mac")
        for outcome in [ProviderSetupOutcome.claudeCLIMissing, .codexCLIMissing,
                        .grokCLIMissing, .cursorCLIMissing] {
            #expect(outcome.message != outcome.recoveryPresentation.primaryLabel)
        }
    }

    /// R2C7: a card still showing retained numbers has to reconcile them with the failure
    /// above them, or the reader is left to decide which half to believe.
    @Test func retainedReadingChangesOnlyTheCapabilitySentence() {
        let retained = ProviderCapabilityState.confirmedAbsent.recoveryPresentation(hasRetainedReading: true)
        #expect(retained?.status == "Headroom can’t find the Claude Code CLI\u{00A0}—\u{00A0}showing the last reading")
        #expect(retained?.primaryAction == .installClaudeCLI)
        #expect(retained?.secondaryAction == .checkNow)
        #expect(retained?.status != ProviderCapabilityState.confirmedAbsent.recoveryPresentation?.status)
        // Only `confirmedAbsent` carries a retained-reading variant; the rest are unchanged.
        #expect(ProviderCapabilityState.inconclusive(.shellTimeout).recoveryPresentation(hasRetainedReading: true)?.status
            == ProviderCapabilityState.inconclusive(.shellTimeout).recoveryPresentation?.status)
        #expect(ProviderCapabilityState.available.recoveryPresentation(hasRetainedReading: true) == nil)
    }

    /// R2B1: the nbsp-around-em-dash rule applies to the whole set or to none of it. Half of
    /// the dashes used to be bare, so the same construction wrapped two ways depending on
    /// which case produced it — and an em dash could start a line.
    @Test func everyEmDashInTheSetIsNonBreakingOnBothSides() {
        for text in allPresentationStrings {
            let characters = Array(text)
            for (index, character) in characters.enumerated() where character == "\u{2014}" {
                #expect(index > 0 && characters[index - 1] == "\u{00A0}",
                        "\(text) has a breaking space before its em dash")
                #expect(index + 1 < characters.count && characters[index + 1] == "\u{00A0}",
                        "\(text) has a breaking space after its em dash")
            }
        }
    }

    /// PB1/R2B1: typographic apostrophes in every user-facing string.
    @Test func everySentenceInTheSetUsesCurlyApostrophes() {
        for text in allPresentationStrings {
            #expect(!text.contains("'"), "\(text) carries a straight apostrophe")
        }
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

/// Every user-facing string the two presentation surfaces can produce, so a copy rule
/// (R2C6's one verb, R2B1's non-breaking dashes and curly apostrophes) is asserted across
/// the whole set rather than the handful of cases someone remembered.
private var allPresentationStrings: [String] {
    var strings: [String] = []
    for outcome in allSetupOutcomes {
        let presentation = outcome.recoveryPresentation
        strings.append(contentsOf: [outcome.message, presentation.status, presentation.primaryLabel])
        if let secondary = presentation.secondaryLabel { strings.append(secondary) }
    }
    for state in [ProviderCapabilityState.inconclusive(.shellTimeout),
                  .inconclusive(.npmPrefixUnresolved),
                  .confirmedAbsent] {
        for retained in [false, true] {
            guard let presentation = state.recoveryPresentation(hasRetainedReading: retained) else { continue }
            strings.append(contentsOf: [presentation.status, presentation.primaryLabel])
            if let secondary = presentation.secondaryLabel { strings.append(secondary) }
        }
    }
    return strings
}

/// Every `ProviderSetupOutcome`, so a copy rule can be asserted across all of them without
/// the enum having to become `CaseIterable` in shipping code.
private let allSetupOutcomes: [ProviderSetupOutcome] = [
    .claudeCLIMissing, .claudeLoginRequired, .claudeTrustRequired, .claudeUnknownUI,
    .claudeTransientCapture,
    .codexCLIMissing, .codexAuthAbsent, .codexPermissionDenied, .codexUnsafePermissions,
    .codexMalformedAuth, .codexCredentialIO, .codexRejectedAuth, .codexStorageMismatch,
    .codexCallbackIncomplete,
    .grokCLIMissing, .grokAuthAbsent, .grokPermissionDenied, .grokUnsafePermissions,
    .grokMalformedAuth, .grokCredentialIO, .grokRejectedAuth, .grokTransientCapture,
    .cursorCLIMissing, .cursorAuthAbsent, .cursorUnknownUI, .cursorTransientCapture,
]
