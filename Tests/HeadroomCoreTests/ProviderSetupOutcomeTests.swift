import Foundation
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
            (.claudeTrustRequired, .openClaudeWorkspace, .checkNow, .boundedChecksAfterHandoff),
            (.claudeUnknownUI, .checkNow, .answerClaudeQuestion, .none),
            (.claudeStartupQuestion, .answerClaudeQuestion, .checkNow, .boundedChecksAfterHandoff),
            (.claudeTransientCapture, .checkNow, .openClaudeSetup, .none),
            (.codexCLIMissing, .installCodexCLI, nil, .none),
            (.codexAuthAbsent, .connectCodex, .connectCodexDeviceCode, .boundedChecksAfterHandoff),
            (.codexPermissionDenied, .showPrivacyGuidance, .checkNow, .none),
            (.codexUnsafePermissions, .reconnectCodex, .checkNow, .boundedChecksAfterHandoff),
            (.codexMalformedAuth, .reconnectCodex, .checkNow, .boundedChecksAfterHandoff),
            (.codexCredentialIO, .checkNow, nil, .none),
            (.codexRejectedAuth, .reconnectCodex, .checkNow, .boundedChecksAfterHandoff),
            (.codexSessionUnverified, .checkNow, .reconnectCodex, .none),
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
            (.cursorTrustRequired, .openCursorWorkspace, .checkNow, .boundedChecksAfterHandoff),
            (.cursorMCPApprovalRequired, .reviewCursorTools, .checkNow, .boundedChecksAfterHandoff),
            (.cursorUnknownUI, .checkNow, .connectCursor, .none),
            (.cursorTransientCapture, .checkNow, .connectCursor, .none),
            (.copilotCLIMissing, .installCopilotCLI, nil, .none),
            (.copilotSignedOut, .connectCopilot, .checkNow, .boundedChecksAfterHandoff),
            (.copilotLogsUnreadable, .checkNow, nil, .none),
            (.opencodeCLIMissing, .installOpenCodeCLI, .checkNow, .none),
            (.opencodeUpdateRequired, .updateOpenCode, .checkNow, .none),
            (.opencodeSignedOut, .connectOpenCode, .checkNow, .boundedChecksAfterHandoff),
            (.opencodeConsoleSignInRequired, .connectOpenCode, .checkNow, .boundedChecksAfterHandoff),
            (.opencodeSignInExpired, .connectOpenCode, .checkNow, .boundedChecksAfterHandoff),
            (.opencodeFormatChanged, .contactSupport, .checkNow, .none),
            (.opencodeTransientCapture, .checkNow, nil, .none),
        ]
        #expect(Set(expectations.map(\.0)) == Set(allSetupOutcomes))

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
        #expect(reason.providerSetupOutcome?.recoveryPresentation.primaryAction == .openClaudeWorkspace)
        #expect(reason.message == ProviderSetupOutcome.claudeTrustRequired.message)
    }

    /// AE3/KTD5: workspace approval is its own act. While it shared Sign In's action it
    /// staged Sign In's script, which on an account that is already signed in prints
    /// "already signed in", exits, and leaves the approval prompt to be detected again.
    @Test func claudeWorkspaceApprovalIsNotTheSignInAction() {
        let approval = ProviderSetupOutcome.claudeTrustRequired.recoveryPresentation
        #expect(approval.primaryAction == .openClaudeWorkspace)
        #expect(approval.primaryLabel == "Open Claude Workspace")
        #expect(ProviderSetupOutcome.claudeLoginRequired.recoveryPresentation.primaryAction
            == .openClaudeSetup)
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
        #expect(FailureReason.providerSetup(.cursorTrustRequired).isPermanent)
        #expect(FailureReason.providerSetup(.copilotCLIMissing).isPermanent)
        #expect(FailureReason.providerSetup(.copilotSignedOut).isPermanent)
        #expect(!FailureReason.providerSetup(.copilotLogsUnreadable).isPermanent)
    }

    /// KTD4/U1: only the two retryable OpenCode reads poll on; the rest wait for the user.
    @Test func openCodeOutcomesSplitIntoPermanentAndTransient() {
        for outcome in [ProviderSetupOutcome.opencodeCLIMissing, .opencodeUpdateRequired,
                        .opencodeSignedOut, .opencodeConsoleSignInRequired, .opencodeSignInExpired] {
            #expect(outcome.isPermanent, "\(outcome)")
            #expect(FailureReason.providerSetup(outcome).isPermanent)
        }
        for outcome in [ProviderSetupOutcome.opencodeFormatChanged, .opencodeTransientCapture] {
            #expect(!outcome.isPermanent, "\(outcome)")
            #expect(!FailureReason.providerSetup(outcome).isPermanent)
        }
    }

    /// KTD13: the default CLI name appends " CLI" itself, which is how Copilot once read
    /// "GitHub Copilot CLI CLI".
    @Test func openCodeNamesItsCLIOnce() {
        #expect(ProviderID.opencode.raw == "opencode")
        #expect(ProviderID.opencode.displayName == "OpenCode")
        #expect(ProviderSignInCopy.cliName(for: .opencode) == "OpenCode CLI")
        let message = ProviderSetupOutcome.opencodeCLIMissing.message
        #expect(message.components(separatedBy: "OpenCode CLI").count - 1 == 1)
        #expect(message == "OpenCode CLI isn’t installed on this Mac")
        for text in allPresentationStrings {
            #expect(!text.contains("CLI CLI"), "\(text) names its CLI twice")
        }
    }

    /// KTD21's copy table, row by row: status, primary and secondary.
    @Test func openCodeRecoveryCopyMatchesTheKTD21Table() {
        let rows: [(ProviderSetupOutcome, String, String, String?)] = [
            (.opencodeCLIMissing, "OpenCode CLI isn’t installed on this Mac", "Install OpenCode CLI", "Check Now"),
            (.opencodeUpdateRequired, "Go usage needs OpenCode 2.2 or newer", "About OpenCode 2", "Check Now"),
            (.opencodeSignedOut, "Sign in with the official OpenCode CLI", "Sign In", "Check Now"),
            (.opencodeConsoleSignInRequired, "Sign in to OpenCode Console to see Go usage", "Sign In", "Check Now"),
            (.opencodeSignInExpired, "Sign in again with the official OpenCode CLI", "Sign In Again", "Check Now"),
            (.opencodeTransientCapture, "Couldn’t read OpenCode usage\u{00A0}—\u{00A0}will retry", "Check Now", nil),
            (.opencodeFormatChanged,
             "Headroom can’t read OpenCode usage after an OpenCode change. Contact support",
             "Contact Support", "Check Now"),
        ]
        for (outcome, status, primary, secondary) in rows {
            let presentation = outcome.recoveryPresentation
            #expect(outcome.message == status, "\(outcome)")
            #expect(presentation.status == status, "\(outcome)")
            #expect(presentation.primaryLabel == primary, "\(outcome)")
            #expect(presentation.secondaryLabel == secondary, "\(outcome)")
            #expect(presentation.secondaryAction == (secondary == nil ? nil : .checkNow), "\(outcome)")
        }
        #expect(ProviderSignInCopy.status(for: .opencode, again: true)
            == ProviderSetupOutcome.opencodeSignInExpired.message)
    }

    /// KTD7: no Go plan is a live reading, not a failure, so its row comes off the
    /// snapshot's plan status. Every other provider has no such row.
    @Test func noGoPlanRowComesFromThePlanStatus() {
        let presentation = UsageSnapshot.PlanStatus.noActivePlan.recoveryPresentation(for: .opencode)
        #expect(presentation?.status == "No Go plan on this workspace")
        #expect(presentation?.primaryLabel == "See Go Plans")
        #expect(presentation?.primaryAction == .seeOpenCodeGoPlans)
        #expect(presentation?.secondaryLabel == "Check Now")
        #expect(presentation?.secondaryAction == .checkNow)
        #expect(presentation?.automaticPolicy == SetupAutomaticPolicy.none)
        for provider in [ProviderID.claude, .codex, .grok, .cursor, .copilot] {
            #expect(UsageSnapshot.PlanStatus.noActivePlan.recoveryPresentation(for: provider) == nil)
        }
    }

    /// KTD7: plan status is new and optional. Every existing caller stays nil, its stored
    /// value is permanent, and the snapshot's own transforms carry it forward.
    @Test func planStatusDefaultsNilAndSurvivesSnapshotTransforms() throws {
        let existing = UsageSnapshot(providerID: .copilot, windows: [], planLabel: nil, capturedAt: nil, freshness: .live)
        #expect(existing.planStatus == nil)
        #expect(UsageSnapshot.pending(for: .opencode).planStatus == nil)
        #expect(UsageSnapshot.stale(for: .opencode, reason: .transient("x")).planStatus == nil)

        let noPlan = UsageSnapshot(
            providerID: .opencode, windows: [], planLabel: nil,
            capturedAt: Date(timeIntervalSince1970: 1_000), freshness: .live, planStatus: .noActivePlan)
        #expect(noPlan.markedStale(.providerSetup(.opencodeTransientCapture)).planStatus == .noActivePlan)
        #expect(noPlan.withIdentity(nil).planStatus == .noActivePlan)
        #expect(noPlan.withAccountEmail("a@b.c").planStatus == .noActivePlan)
        #expect(noPlan.replacingWindows([]).planStatus == .noActivePlan)
        #expect(noPlan.fiveHourFirst().planStatus == .noActivePlan)

        #expect(UsageSnapshot.PlanStatus.noActivePlan.rawValue == "noActivePlan")
        let encoded = try JSONEncoder().encode(UsageSnapshot.PlanStatus.noActivePlan)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"noActivePlan\"")
        #expect(try JSONDecoder().decode(UsageSnapshot.PlanStatus.self, from: encoded) == .noActivePlan)
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
        #expect(ProviderSetupOutcome.copilotSignedOut.message == "Sign in with the official GitHub Copilot CLI")
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
        #expect(ProviderSetupOutcome.copilotCLIMissing.message == "GitHub Copilot CLI isn’t installed on this Mac")
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

    /// R7/KTD11 (2026-09-19 sign-in plan): the three phases come off the typed session
    /// state, never off `.waiting(attempt:)`'s retry counter — which the card's animation
    /// key deliberately flattens.
    @Test func thePhaseFollowsTheSessionStateAndTheOpenHandoff() {
        #expect(SetupWaitingPhase.resolve(
            state: .preparing,
            hasActiveHandoff: false,
            purpose: .setup
        ) == .openingTerminal)
        for attempt in [0, 3, 11] {
            #expect(SetupWaitingPhase.resolve(
                state: .waiting(attempt: attempt),
                hasActiveHandoff: true,
                purpose: .setup
            ) == .waitingForUser(.signIn))
        }
        #expect(SetupWaitingPhase.resolve(
            state: .verifying,
            hasActiveHandoff: false,
            purpose: .setup
        ) == .confirming(.signIn, reportedFinished: false))
        for state in [SetupSessionState.idle, .connected, .cancelled, .removed,
                      .blockedByOpenHandoff, .failed(.waitingTimedOut)] {
            #expect(SetupWaitingPhase.resolve(
                state: state,
                hasActiveHandoff: false,
                purpose: .setup
            ) == nil, "\(state) is not a waiting phase")
        }
    }

    /// KTD11: the wrapper's recorded completion is what tells "sign-in said it finished"
    /// apart from a window that closed with no verdict.
    @Test func confirmingDistinguishesAReportedFinishFromAnUnknownOne() {
        let finished = SetupWaitingPhase.resolve(
            state: .verifying,
            hasActiveHandoff: false,
            purpose: .setup,
            reportedCompletion: .succeeded
        )
        #expect(finished == .confirming(.signIn, reportedFinished: true))
        #expect(finished?.copy.title == "Confirming sign-in…")
        #expect(finished?.copy.body == "Terminal closed. Headroom is reading your usage.")

        for completion in [SetupHandoffCompletion.unknown, .failed] {
            let unknown = SetupWaitingPhase.resolve(
                state: .verifying,
                hasActiveHandoff: false,
                purpose: .setup,
                reportedCompletion: completion
            )
            #expect(unknown == .confirming(.signIn, reportedFinished: false))
            #expect(unknown?.copy.title == "Checking sign-in…")
            #expect(unknown?.copy.body
                == "Terminal closed. Headroom is checking whether sign-in finished.")
        }
    }

    /// R6: only the launch chosen *because the version could not be read* leaves the user at
    /// the CLI's own screen with a command to type. AE7's never-onboarded extra config shows
    /// the CLI's own login selector, so it keeps the plain sign-in copy.
    @Test func onlyAnUnreadableVersionAsksTheUserToTypeLogin() {
        let hinted = SetupWaitingPhase.resolve(
            state: .waiting(attempt: 0),
            hasActiveHandoff: true,
            purpose: .setup,
            interactiveReason: .versionUnreadable
        )
        #expect(hinted == .waitingForUser(.signInNeedsLoginCommand))
        #expect(hinted?.copy.token == SetupWaitingToken(text: "/login", isCommand: true))
        #expect(hinted?.copy.body
            == "In Terminal, type the command below and press Return, then finish in your browser.")

        for reason in [ClaudeInteractiveLaunchReason.neverOnboardedExtraAccount, nil] {
            let plain = SetupWaitingPhase.resolve(
                state: .waiting(attempt: 0),
                hasActiveHandoff: true,
                purpose: .setup,
                interactiveReason: reason
            )
            #expect(plain == .waitingForUser(.signIn))
            #expect(plain?.copy.token == nil)
        }
    }

    /// AE3/R5: a workspace-approval handoff is *always* the interactive launch, so keying the
    /// hint on the launch shape would have told every approval to sign in again. It keeps
    /// today's guidance and its literal trust-prompt option.
    @Test func aWorkspaceApprovalHandoffNeverSelectsTheLoginVariant() {
        for reason in [ClaudeInteractiveLaunchReason.versionUnreadable,
                       .neverOnboardedExtraAccount, nil] {
            let phase = SetupWaitingPhase.resolve(
                state: .waiting(attempt: 0),
                hasActiveHandoff: true,
                purpose: .trust,
                interactiveReason: reason
            )
            #expect(phase == .waitingForUser(.workspaceApproval))
            #expect(phase?.copy.title == "Waiting for approval…")
            #expect(phase?.copy.token
                == SetupWaitingToken(text: "“Yes, I trust this folder”", isCommand: false))
        }
        #expect(SetupWaitingPhase.resolve(
            state: .verifying,
            hasActiveHandoff: false,
            purpose: .trust
        )?.copy.title == "Checking approval…")
    }

    /// A startup question waits on the user, not on Headroom, and its recovery opens the
    /// interactive launch where the question is visible. Guided Setup's sign-in script exits
    /// on a signed-in account before the question can appear, so it is never offered.
    @Test func aStartupQuestionOpensClaudeCodeForTheUser() {
        let outcome = ProviderSetupOutcome.claudeStartupQuestion
        #expect(outcome.message == "Claude Code is waiting on a one-time question")
        #expect(outcome.isPermanent)
        #expect(FailureReason.providerSetup(outcome).isPermanent)
        #expect(!outcome.isNeverSignedIn)
        let presentation = outcome.recoveryPresentation
        #expect(presentation.status == outcome.message)
        #expect(presentation.primaryLabel == "Open Claude Code")
        #expect(presentation.primaryAction == .answerClaudeQuestion)
        #expect(presentation.secondaryLabel == "Check Now")
        #expect(presentation.secondaryAction == .checkNow)
        #expect(presentation.automaticPolicy == .boundedChecksAfterHandoff)
    }

    /// The unrecognized screen keeps its copy and Check Now, but its secondary no longer
    /// runs the sign-in script that could never show the screen. Transient capture, which
    /// shared that arm, keeps Guided Setup.
    @Test func anUnrecognizedScreenOffersClaudeCodeInsteadOfGuidedSetup() {
        let unknown = ProviderSetupOutcome.claudeUnknownUI.recoveryPresentation
        #expect(unknown.status == "Claude opened an unrecognized setup screen")
        #expect(unknown.primaryLabel == "Check Now")
        #expect(unknown.primaryAction == .checkNow)
        #expect(unknown.secondaryLabel == "Open Claude Code")
        #expect(unknown.secondaryAction == .answerClaudeQuestion)
        #expect(unknown.automaticPolicy == .none)

        let transient = ProviderSetupOutcome.claudeTransientCapture.recoveryPresentation
        #expect(transient.primaryLabel == "Check Now")
        #expect(transient.primaryAction == .checkNow)
        #expect(transient.secondaryLabel == "Open Guided Setup")
        #expect(transient.secondaryAction == .openClaudeSetup)
        #expect(transient.automaticPolicy == .none)
    }

    /// The startup question rides the `.trust` launch; only its staged reason gives it its
    /// own waiting and confirming copy. It names no option, because Headroom never answers.
    @Test func aStartupQuestionLaunchHasItsOwnWaitingCopy() {
        let waiting = SetupWaitingPhase.resolve(
            state: .waiting(attempt: 0),
            hasActiveHandoff: true,
            purpose: .trust,
            interactiveReason: .startupQuestion
        )
        #expect(waiting == .waitingForUser(.startupQuestion))
        #expect(waiting?.copy.title == "Waiting for Claude Code…")
        #expect(waiting?.copy.body
            == "Answer Claude Code’s question in Terminal. Headroom continues as soon as Claude Code is ready.")
        #expect(waiting?.copy.token == nil)

        let finished = SetupWaitingPhase.resolve(
            state: .verifying,
            hasActiveHandoff: false,
            purpose: .trust,
            interactiveReason: .startupQuestion,
            reportedCompletion: .succeeded
        )
        #expect(finished == .confirming(.startupQuestion, reportedFinished: true))
        #expect(finished?.copy.title == "Confirming…")
        #expect(finished?.copy.body == "Terminal closed. Headroom is reading your usage.")

        for completion in [SetupHandoffCompletion.unknown, .failed] {
            let unknown = SetupWaitingPhase.resolve(
                state: .verifying,
                hasActiveHandoff: false,
                purpose: .trust,
                interactiveReason: .startupQuestion,
                reportedCompletion: completion
            )
            #expect(unknown == .confirming(.startupQuestion, reportedFinished: false))
            #expect(unknown?.copy.title == "Checking Claude Code…")
            #expect(unknown?.copy.body
                == "Terminal closed. Headroom is checking whether Claude Code is ready.")
        }

        // The reason only means something on the `.trust` launch: a sign-in never borrows it.
        #expect(SetupWaitingPhase.resolve(
            state: .waiting(attempt: 0),
            hasActiveHandoff: true,
            purpose: .setup,
            interactiveReason: .startupQuestion
        ) == .waitingForUser(.signIn))
        // And a plain approval keeps its own prompt and literal option.
        let approval = SetupWaitingPhase.resolve(
            state: .waiting(attempt: 0),
            hasActiveHandoff: true,
            purpose: .trust
        )
        #expect(approval == .waitingForUser(.workspaceApproval))
        #expect(approval?.copy.token
            == SetupWaitingToken(text: "“Yes, I trust this folder”", isCommand: false))
    }

    /// The device-code handoffs Codex and Grok already offer keep their own line.
    @Test func aDeviceCodeHandoffKeepsItsOwnPrompt() {
        let phase = SetupWaitingPhase.resolve(
            state: .waiting(attempt: 0),
            hasActiveHandoff: true,
            purpose: .setup,
            mode: .deviceCode
        )
        #expect(phase == .waitingForUser(.deviceCode))
        #expect(phase?.copy.title == "Waiting for device code…")
    }

    /// KTD6: the old waiting body promised "Headroom checks this account automatically",
    /// which an exit-signalled handoff does not do — nothing is checked until the CLI
    /// process exits.
    @Test func noWaitingCopyPromisesAutomaticChecking() {
        for text in allWaitingPhaseStrings {
            #expect(!text.localizedCaseInsensitiveContains("automatically"),
                    "\(text) still promises automatic checking")
        }
    }

    /// R2B1/R2C6/PA11: the phase copy joins the same rules the outcome copy has always been
    /// held to — curly apostrophes, non-breaking em dashes, one sign-in verb, and no
    /// borrowed button labels.
    @Test func thePhaseCopyObeysTheSameRulesAsTheOutcomeCopy() {
        for text in allWaitingPhaseStrings {
            #expect(!text.isEmpty)
            #expect(!text.contains("'"), "\(text) carries a straight apostrophe")
            #expect(!text.localizedCaseInsensitiveContains("connect"),
                    "\(text) still names signing in \"connect\"")
            #expect(!text.localizedCaseInsensitiveContains("Check Again"))
            #expect(!text.localizedCaseInsensitiveContains("Refresh"))
            let characters = Array(text)
            for (index, character) in characters.enumerated() where character == "\u{2014}" {
                #expect(index > 0 && characters[index - 1] == "\u{00A0}",
                        "\(text) has a breaking space before its em dash")
                #expect(index + 1 < characters.count && characters[index + 1] == "\u{00A0}",
                        "\(text) has a breaking space after its em dash")
            }
        }
    }

    @Test func neverSignedInClassificationIsTyped() {
        #expect(ProviderSetupOutcome.claudeLoginRequired.isNeverSignedIn)
        #expect(ProviderSetupOutcome.codexAuthAbsent.isNeverSignedIn)
        #expect(ProviderSetupOutcome.grokAuthAbsent.isNeverSignedIn)
        #expect(ProviderSetupOutcome.cursorAuthAbsent.isNeverSignedIn)
        #expect(ProviderSetupOutcome.copilotSignedOut.isNeverSignedIn)
        #expect(!ProviderSetupOutcome.copilotLogsUnreadable.isNeverSignedIn)
        // KTD12: both OpenCode states with no Console sign-in wait four intervals on extras.
        #expect(ProviderSetupOutcome.opencodeSignedOut.isNeverSignedIn)
        #expect(ProviderSetupOutcome.opencodeConsoleSignInRequired.isNeverSignedIn)
        for outcome in [ProviderSetupOutcome.opencodeCLIMissing, .opencodeUpdateRequired,
                        .opencodeSignInExpired, .opencodeFormatChanged, .opencodeTransientCapture] {
            #expect(!outcome.isNeverSignedIn, "\(outcome)")
        }
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
    if let noPlan = UsageSnapshot.PlanStatus.noActivePlan.recoveryPresentation(for: .opencode) {
        strings.append(contentsOf: [noPlan.status, noPlan.primaryLabel])
        if let secondary = noPlan.secondaryLabel { strings.append(secondary) }
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

/// Every string the waiting-phase table can produce, so a copy rule is asserted across the
/// whole of it rather than the variants someone remembered.
private var allWaitingPhaseStrings: [String] {
    var phases: [SetupWaitingPhase] = [.openingTerminal]
    for prompt in SetupWaitingPrompt.allCases {
        phases.append(.waitingForUser(prompt))
        phases.append(.confirming(prompt, reportedFinished: true))
        phases.append(.confirming(prompt, reportedFinished: false))
    }
    return phases.flatMap { phase -> [String] in
        let copy = phase.copy
        return [copy.title, copy.body] + (copy.token.map { [$0.text] } ?? [])
    }
}

/// Every `ProviderSetupOutcome`, so a copy rule can be asserted across all of them without
/// the enum having to become `CaseIterable` in shipping code.
private let allSetupOutcomes: [ProviderSetupOutcome] = [
    .claudeCLIMissing, .claudeLoginRequired, .claudeTrustRequired, .claudeUnknownUI,
    .claudeStartupQuestion, .claudeTransientCapture,
    .codexCLIMissing, .codexAuthAbsent, .codexPermissionDenied, .codexUnsafePermissions,
    .codexMalformedAuth, .codexCredentialIO, .codexRejectedAuth, .codexSessionUnverified, .codexStorageMismatch,
    .codexCallbackIncomplete,
    .grokCLIMissing, .grokAuthAbsent, .grokPermissionDenied, .grokUnsafePermissions,
    .grokMalformedAuth, .grokCredentialIO, .grokRejectedAuth, .grokTransientCapture,
    .cursorCLIMissing, .cursorAuthAbsent, .cursorTrustRequired, .cursorMCPApprovalRequired,
    .cursorUnknownUI, .cursorTransientCapture,
    .copilotCLIMissing, .copilotSignedOut, .copilotLogsUnreadable,
    .opencodeCLIMissing, .opencodeUpdateRequired, .opencodeSignedOut, .opencodeConsoleSignInRequired,
    .opencodeSignInExpired, .opencodeFormatChanged, .opencodeTransientCapture,
]
