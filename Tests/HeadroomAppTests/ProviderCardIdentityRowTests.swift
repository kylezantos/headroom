import HeadroomCore
import SwiftUI
import Testing
@testable import Headroom

/// PA12: a just-added account carried an untyped preset, so two never-signed-in rows in one
/// card described the same state as two different problems with two different fixes. These
/// pin the substitution — and pin that it is *only* the add-account preset that borrows.
@Suite
struct PresentedSetupOutcomeTests {
    @Test func theAddAccountPresetBorrowsItsProvidersNeverSignedInOutcome() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        #expect(presentedSetupOutcome(for: preset, providerID: .claude) == .claudeLoginRequired)
        #expect(presentedSetupOutcome(for: preset, providerID: .codex) == .codexAuthAbsent)
        #expect(presentedSetupOutcome(for: preset, providerID: .grok) == .grokAuthAbsent)
        #expect(presentedSetupOutcome(for: preset, providerID: .cursor) == .cursorAuthAbsent)
    }

    /// Every borrowed outcome is one Core already calls "never signed in", so the row cannot
    /// end up offering a recovery for a state it is not in.
    @Test func everyBorrowedOutcomeIsANeverSignedInOne() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        for providerID in [ProviderID.claude, .codex, .grok, .cursor] {
            let outcome = presentedSetupOutcome(for: preset, providerID: providerID)
            #expect(outcome?.isNeverSignedIn == true)
        }
    }

    /// The borrowed outcome carries both halves the audit found missing: the typed sentence
    /// and a two-action recovery, instead of "Finish sign-in to add this account" + a lone
    /// "Sign In".
    @Test func theBorrowedOutcomeSuppliesBothSentenceAndRecovery() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        let outcome = presentedSetupOutcome(for: preset, providerID: .claude)
        #expect(outcome?.message == ProviderSetupOutcome.claudeLoginRequired.message)
        #expect(outcome?.message != UsageStore.finishSignInMessage)
        let recovery = outcome?.recoveryPresentation
        // R2C6: one verb — a first sign-in is "Sign In" on every provider and surface.
        #expect(recovery?.primaryLabel == ProviderSignInCopy.button)
        #expect(recovery?.secondaryLabel == "Check Now")
    }

    /// PA12 unifies one preset, not every untyped failure. A real `notLoggedIn` from a probe
    /// keeps its own message and gets no invented recovery.
    @Test func anUnrelatedUntypedFailureIsLeftAlone() {
        let other = FailureReason.notLoggedIn("Not logged in")
        #expect(presentedSetupOutcome(for: other, providerID: .claude) == nil)
        #expect(presentedSetupOutcome(for: .transient("Timed out"), providerID: .claude) == nil)
    }

    /// Anything Core already typed passes straight through — the substitution never
    /// overwrites a diagnosis.
    @Test func typedOutcomesPassThroughUntouched() {
        let typed = FailureReason.providerSetup(.codexRejectedAuth)
        #expect(presentedSetupOutcome(for: typed, providerID: .codex) == .codexRejectedAuth)
        // Even when the provider disagrees with the outcome's own family.
        #expect(presentedSetupOutcome(for: typed, providerID: .claude) == .codexRejectedAuth)
    }

    /// An unknown provider gets nothing rather than a Claude-flavoured guess.
    @Test func anUnknownProviderBorrowsNothing() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        #expect(presentedSetupOutcome(for: preset, providerID: ProviderID("gemini")) == nil)
    }
}

/// R13/KTD12 (2026-09-19 sign-in plan): the shared sign-in row's chips. The row is one view
/// for Claude, Codex, Grok and Cursor, so a chip added for one provider appears on all four.
@Suite
struct SetupRowChipTests {
    private let providers: [ProviderID] = [.claude, .codex, .grok, .cursor]

    /// R13: the waiting surfaces lost Check Now on every provider. The row's one control is
    /// the Stop Waiting chip the section renders beside it.
    @MainActor @Test func noWaitingOrConfirmingRowOffersCheckNow() {
        for providerID in providers {
            guard let outcome = neverSignedInOutcome(for: providerID) else {
                Issue.record("\(providerID) has no never-signed-in outcome")
                continue
            }
            for state in [SetupSessionState.preparing, .waiting(attempt: 0),
                          .waiting(attempt: 4), .verifying] {
                let chips = setupRowChips(
                    state: state,
                    presentation: outcome.recoveryPresentation,
                    hasFailureMessage: false
                )
                #expect(chips.isEmpty, "\(providerID) still renders \(chips.map(\.label)) while \(state)")
            }
        }
    }

    /// KTD12: the timeout is Try Again and Stop Waiting only — no Check Now, no Sign In.
    @MainActor @Test func theTimeoutStateOffersTryAgainAlone() {
        let chips = setupRowChips(
            state: .failed(.waitingTimedOut),
            presentation: ProviderSetupOutcome.claudeLoginRequired.recoveryPresentation,
            hasFailureMessage: true
        )
        #expect(chips == [.tryAgain])
        #expect(!chips.map(\.label).contains("Check Now"))
        #expect(!chips.map(\.label).contains(ProviderSignInCopy.button))
        #expect(setupSessionOffersStopWaiting(
            state: .failed(.waitingTimedOut),
            hasActiveHandoff: true
        ))
    }

    /// R6: the too-old CLI keeps one action, and it is Try Again — the only control that
    /// re-reads the installed version, which is what tells Headroom the update landed.
    @MainActor @Test func theUpdateRequiredStateOffersTryAgainAlone() {
        let chips = setupRowChips(
            state: .failed(.updateRequired),
            presentation: ProviderSetupOutcome.claudeLoginRequired.recoveryPresentation,
            hasFailureMessage: true
        )
        #expect(chips == [.tryAgain])
        #expect(!chips.map(\.label).contains("Check Now"))
    }

    /// R6: the regression this replaced. A bare Check Now was the update-required state's
    /// one action on every surface, and nothing a check returns can clear the failure —
    /// the account is signed out, so every refresh reads "login required", which the
    /// coordinator ignores, and the CLI version is only re-read when a handoff is staged.
    /// No surface may hand this state a lone Check Now again.
    @MainActor @Test func noSurfaceOffersABareCheckNowForUpdateRequired() {
        let state = SetupSessionState.failed(.updateRequired)
        #expect(setupRowRecovery(for: state) != .outcomeRecovery)

        for presentation in [ProviderSetupOutcome.claudeLoginRequired.recoveryPresentation,
                             ProviderSetupOutcome.claudeTrustRequired.recoveryPresentation] {
            for hasFailureMessage in [true, false] {
                let chips = setupRowChips(
                    state: state,
                    presentation: presentation,
                    hasFailureMessage: hasFailureMessage
                )
                #expect(chips == [.tryAgain])
                #expect(chips.map(\.label) != ["Check Now"])
            }
        }

        for hasActiveHandoff in [true, false] {
            let actions = claudeWaitingCardActions(state: state, hasActiveHandoff: hasActiveHandoff)
            #expect(actions == [.tryAgain])
            #expect(actions.map(\.label) != ["Check Now"])
        }
    }

    /// R6: with no handoff left open — which is where a refused staging leaves the account —
    /// Try Again starts a fresh one, and staging is what re-reads the CLI version.
    @MainActor @Test func updateRequiredTryAgainStartsAFreshHandoff() {
        #expect(SetupSessions.tryAgainRoute(hasActiveHandoff: false, purpose: nil)
            == .startNewHandoff(.setup))
        #expect(SetupSessions.tryAgainRoute(hasActiveHandoff: false, purpose: .setup)
            == .startNewHandoff(.setup))
    }

    /// R6/KTD12: neither session-owned failure offers Stop Waiting once its window is gone,
    /// and only the timeout prints a second line about a window that is still open.
    @MainActor @Test func updateRequiredHasNoSessionToStopAndNoSecondLine() {
        #expect(!setupSessionOffersStopWaiting(
            state: .failed(.updateRequired),
            hasActiveHandoff: false
        ))
        #expect(SetupSessions.failureDetail(for: .updateRequired) == nil)
        #expect(SetupSessions.failureDetail(for: .waitingTimedOut) != nil)
    }

    /// The providers that still reach the 55-second ladder keep the pair their sentence
    /// names. Nothing in KTD12 touches `.retryExhausted`.
    @MainActor @Test func retryExhaustedKeepsSignInAndCheckNowOnACodexRow() {
        let chips = setupRowChips(
            state: .failed(.retryExhausted),
            presentation: ProviderSetupOutcome.codexAuthAbsent.recoveryPresentation,
            hasFailureMessage: true
        )
        #expect(chips.map(\.label) == [ProviderSignInCopy.button, "Use Device Code"])

        let rejected = setupRowChips(
            state: .failed(.retryExhausted),
            presentation: ProviderSetupOutcome.codexRejectedAuth.recoveryPresentation,
            hasFailureMessage: true
        )
        #expect(rejected.map(\.label) == ["Sign In Again", "Check Now"])
    }

    /// An untyped failure keeps the fallback the row has always rendered.
    @MainActor @Test func anUntypedRowKeepsItsSignInFallback() {
        #expect(setupRowChips(state: .idle, presentation: nil, hasFailureMessage: false)
            == [.signIn])
        #expect(setupRowChips(state: .idle, presentation: nil, hasFailureMessage: true)
            == [.signIn, .checkNow])
    }

    /// KTD12: Try Again is its own action. Borrowing `.checkNow` would have broken PA11's
    /// one-label rule, which `checkNowCarriesOneLabelInEverySlot` enforces in Core.
    @MainActor @Test func tryAgainIsNeverLabelledCheckNow() {
        #expect(SetupRowChip.tryAgain.label == "Try Again")
        #expect(ClaudeWaitingCardAction.tryAgain.label == "Try Again")
        for chip in [SetupRowChip.tryAgain, .checkNow, .signIn] where chip != .checkNow {
            #expect(chip.label != "Check Now")
        }
    }
}

/// KTD11/KTD12: the single-account Claude card's shell and the chips inside it.
@Suite
struct ClaudeWaitingCardContentTests {
    /// KTD12: a returning user whose wait timed out must not be handed the first-run
    /// walkthrough. The compact shell keeps the timeout sentence instead.
    @MainActor @Test func theTimeoutStateKeepsTheCompactShellNotTheConnectCard() {
        #expect(claudeSingleAccountShell(for: .failed(.waitingTimedOut)) == .compactWaiting)
        #expect(claudeSingleAccountShell(for: .failed(.updateRequired)) == .compactWaiting)
        for state in [SetupSessionState.preparing, .waiting(attempt: 0), .verifying] {
            #expect(claudeSingleAccountShell(for: state) == .compactWaiting)
        }
        for state in [SetupSessionState.idle, .connected, .cancelled,
                      .failed(.closedBeforeSignIn), .failed(.retryExhausted),
                      .failed(.terminalRejected)] {
            #expect(claudeSingleAccountShell(for: state) == .firstRunWalkthrough,
                    "\(state) should still get the first-run walkthrough")
        }
    }

    /// R14: Show Terminal is rendered only while a handoff is open, so the confirming phase
    /// — whose window has already closed — never offers it.
    @MainActor @Test func showTerminalAppearsOnlyWhileAHandoffIsOpen() {
        #expect(claudeWaitingCardActions(
            state: .waiting(attempt: 0),
            hasActiveHandoff: true
        ) == [.showTerminal])
        #expect(claudeWaitingCardActions(
            state: .verifying,
            hasActiveHandoff: false
        ).isEmpty)
        #expect(claudeWaitingCardActions(
            state: .failed(.waitingTimedOut),
            hasActiveHandoff: true
        ) == [.tryAgain])
        #expect(claudeWaitingCardActions(
            state: .failed(.updateRequired),
            hasActiveHandoff: false
        ) == [.tryAgain])
    }

    /// The compact shell takes its title and body from the Core phase table while waiting,
    /// and from the typed failure once the wait has ended.
    @MainActor @Test func theShellSwapsPhaseCopyForFailureCopy() {
        let waiting = claudeWaitingCardContent(
            state: .waiting(attempt: 0),
            phase: .waitingForUser(.signIn),
            hasActiveHandoff: true,
            failureMessage: nil,
            failureDetail: nil
        )
        #expect(waiting.title == "Waiting for sign-in…")
        #expect(waiting.showsProgress)
        #expect(waiting.actions == [.showTerminal])

        let timedOut = claudeWaitingCardContent(
            state: .failed(.waitingTimedOut),
            phase: nil,
            hasActiveHandoff: true,
            failureMessage: "Sign-in wasn’t confirmed.",
            failureDetail: "Terminal is still open. Finish there, or try again to keep waiting."
        )
        #expect(timedOut.title == "Sign-in wasn’t confirmed.")
        #expect(timedOut.detail == "Terminal is still open. Finish there, or try again to keep waiting.")
        // A stalled wait is not progress.
        #expect(!timedOut.showsProgress)
        #expect(timedOut.token == nil)
        #expect(timedOut.actions == [.tryAgain])
    }

    /// Review #4/#6 (2026-09-19 sign-in review): the shell and the row's recovery are one
    /// partition of the session states, derived rather than hand-written twice. Two copies
    /// drifted once already; a state added to one must never miss the other.
    @MainActor @Test func theShellAndTheRowRecoveryAgreeForEverySessionState() {
        for state in everySetupSessionState {
            let expected: ClaudeSingleAccountShell = setupRowRecovery(for: state) == .outcomeRecovery
                ? .firstRunWalkthrough
                : .compactWaiting
            #expect(claudeSingleAccountShell(for: state) == expected,
                    "\(state) disagrees with its row recovery")
            #expect(setupSessionOwnsSurface(for: state) == (expected == .compactWaiting))
        }
    }

    /// Review #4/#6: the states a blanked (`.pending`) row is in for the whole of a
    /// "Sign Out & Set Up Again" — the wait itself, and a staging refused before it. Both
    /// are the session's to render; neither may fall back to the fetching skeleton.
    @MainActor @Test func aResetsWaitingAndRefusedStatesAreOwnedByTheSession() {
        for state in [SetupSessionState.preparing, .waiting(attempt: 0), .verifying,
                      .failed(.waitingTimedOut), .failed(.updateRequired)] {
            #expect(setupSessionOwnsSurface(for: state))
        }
        for state in [SetupSessionState.idle, .connected, .cancelled,
                      .failed(.closedBeforeSignIn), .blockedByOpenHandoff] {
            #expect(!setupSessionOwnsSurface(for: state))
        }

        // The card's content comes from the session, not from a stale snapshot's outcome.
        let waiting = claudeWaitingCardContent(
            state: .waiting(attempt: 0),
            phase: .waitingForUser(.signIn),
            hasActiveHandoff: true,
            failureMessage: nil,
            failureDetail: nil
        )
        #expect(waiting.title == "Waiting for sign-in…")
        let refused = claudeWaitingCardContent(
            state: .failed(.updateRequired),
            phase: nil,
            hasActiveHandoff: false,
            failureMessage: "Update Claude Code, then try again.",
            failureDetail: nil
        )
        #expect(refused.title == "Update Claude Code, then try again.")
        #expect(refused.actions == [.tryAgain])
    }

    /// Review #2 (2026-09-19 sign-in review): the version gate refused this CLI, so the
    /// card must not also offer a copyable command that launches it. Every other shell
    /// state keeps the disclosure.
    @MainActor @Test func theUpdateRequiredShellOffersNoManualCommand() {
        #expect(!claudeWaitingCardContent(
            state: .failed(.updateRequired),
            phase: nil,
            hasActiveHandoff: false,
            failureMessage: "Update Claude Code, then try again.",
            failureDetail: nil
        ).showsManualCommand)

        for state in [SetupSessionState.preparing, .waiting(attempt: 0), .verifying,
                      .failed(.waitingTimedOut)] {
            #expect(claudeWaitingCardContent(
                state: state,
                phase: .waitingForUser(.signIn),
                hasActiveHandoff: true,
                failureMessage: nil,
                failureDetail: nil
            ).showsManualCommand, "\(state) should still offer the manual command")
        }
    }

    /// The `/login` hint reaches the card as the same quiet bordered token the approval
    /// variant uses, so the literal is set apart from the prose rather than bolded in it.
    @MainActor @Test func theLoginHintReachesTheCardAsAToken() {
        let content = claudeWaitingCardContent(
            state: .waiting(attempt: 0),
            phase: .waitingForUser(.signInNeedsLoginCommand),
            hasActiveHandoff: true,
            failureMessage: nil,
            failureDetail: nil
        )
        #expect(content.token == SetupWaitingToken(text: "/login", isCommand: true))
    }
}

/// PA7 + PB11 on the identity row itself.
@Suite
struct IdentityRowMetricsTests {
    /// PA7: C6A unified the six capsules' height but left 9.5 medium / 10 semibold / 10.5
    /// semibold / 11 semibold inside them. One label role, stated once, applied by
    /// `identityCapsule` — so a call site cannot re-introduce a tier by declaring its own
    /// font.
    @Test func theCapsuleCarriesOneLabelRole() {
        #expect(IdentityRowMetrics.capsuleLabelSize == 10.5)
        #expect(IdentityRowMetrics.capsuleLabelWeight == Font.Weight.medium)
        #expect(IdentityRowMetrics.capsuleLabelKerning == 0.2)
        #expect(IdentityRowMetrics.capsuleHeight == 18)
    }

    /// PB11: the title tooltip needs a truthful truncation signal. A row wide enough for the
    /// string is not truncated; a narrower one is.
    @Test func truncationIsMeasuredAgainstTheStringsOwnWidth() {
        let intrinsic = IdentityRow.titleIntrinsicWidth("Personal")
        #expect(intrinsic > 0)
        #expect(IdentityRow.titleIsTruncated("Personal", renderedWidth: intrinsic + 10) == false)
        #expect(IdentityRow.titleIsTruncated("Personal", renderedWidth: intrinsic) == false)
        #expect(IdentityRow.titleIsTruncated("Personal", renderedWidth: intrinsic - 12) == true)
    }

    /// Sub-pixel layout rounding must not claim a truncation that never happened.
    @Test func aQuarterPointShortOfIdealIsNotTruncation() {
        let intrinsic = IdentityRow.titleIntrinsicWidth("Work")
        #expect(IdentityRow.titleIsTruncated("Work", renderedWidth: intrinsic - 0.25) == false)
    }

    /// The pre-layout pass reports zero, which is not a truncation — otherwise every row
    /// would flash a redundant tooltip on its first frame.
    @Test func aZeroWidthIsThePreLayoutPassNotATruncation() {
        #expect(IdentityRow.titleIsTruncated("A very long account label", renderedWidth: 0) == false)
    }

    /// A longer string needs more room, so it truncates at a width the shorter one survives.
    @Test func alongerTitleTruncatesSooner() {
        let short = IdentityRow.titleIntrinsicWidth("Work")
        let long = IdentityRow.titleIntrinsicWidth("Work — long-lived research account")
        #expect(long > short)
        #expect(IdentityRow.titleIsTruncated("Work", renderedWidth: short + 4) == false)
        #expect(IdentityRow.titleIsTruncated("Work — long-lived research account",
                                             renderedWidth: short + 4) == true)
    }
}

/// `SetupSessionState` carries associated values, so it cannot be `CaseIterable`. This is
/// the hand-kept enumeration the partition tests sweep — every case, and every typed
/// failure, with one representative payload each.
private let everySetupSessionState: [SetupSessionState] = [
    .idle,
    .preparing,
    .waiting(attempt: 0),
    .waiting(attempt: 3),
    .verifying,
    .blockedByOpenHandoff,
    .blockedByProviderLogin(
        providerID: .codex,
        active: AccountKey(providerID: .codex, accountID: .primary)
    ),
    .connected,
    .cancelled,
    .removing,
    .removalFailed,
    .removed,
] + [
    SetupSessionFailure.executableMissing,
    .updateRequired,
    .stagingFailed,
    .terminalRejected,
    .pasteboardFailed,
    .retryExhausted,
    .waitingTimedOut,
    .closedBeforeSignIn,
    .provider(.claudeLoginRequired),
    .provider(.claudeTrustRequired),
    .providerCapability(.confirmedAbsent),
    .providerCapability(.inconclusive(.shellTimeout)),
].map(SetupSessionState.failed)

@Suite
struct IdentityRowHelpTests {
    private let banked = "2 banked resets — a full reset refreshes the 5-hour and weekly windows"

    @Test func helpLinesJoinTitleEmailMainAndBankedInOrder() {
        let help = IdentityRow.helpLines(
            title: "Personal",
            titleIsTruncated: true,
            email: "a@example.com",
            isMenuBarAccount: true,
            bankedHelp: banked
        )
        #expect(help == "Personal\na@example.com\n\(IdentityRow.mainAccountHelp)\n\(banked)")
    }

    @Test func accessibilityPartsAppendTheBankedPhrase() {
        let label = IdentityRow.accessibilityParts(
            title: "Personal",
            planDisplayName: "Plus",
            isMenuBarAccount: true,
            isStale: false,
            email: "a@example.com",
            showsConnectedChip: false,
            bankedPhrase: "2 banked resets available — a full reset refreshes the 5-hour and weekly windows"
        )
        #expect(label == "Personal, Plus plan, Main account, shown in the menu bar and widgets, signed in as a@example.com, 2 banked resets available — a full reset refreshes the 5-hour and weekly windows")
    }
}
