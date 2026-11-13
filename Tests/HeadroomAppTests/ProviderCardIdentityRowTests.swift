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
        let intrinsic = IdentityRowText.titleIntrinsicWidth("Personal")
        #expect(intrinsic > 0)
        #expect(IdentityRowText.titleIsTruncated("Personal", renderedWidth: intrinsic + 10) == false)
        #expect(IdentityRowText.titleIsTruncated("Personal", renderedWidth: intrinsic) == false)
        #expect(IdentityRowText.titleIsTruncated("Personal", renderedWidth: intrinsic - 12) == true)
    }

    /// Sub-pixel layout rounding must not claim a truncation that never happened.
    @Test func aQuarterPointShortOfIdealIsNotTruncation() {
        let intrinsic = IdentityRowText.titleIntrinsicWidth("Work")
        #expect(IdentityRowText.titleIsTruncated("Work", renderedWidth: intrinsic - 0.25) == false)
    }

    /// The pre-layout pass reports zero, which is not a truncation — otherwise every row
    /// would flash a redundant tooltip on its first frame.
    @Test func aZeroWidthIsThePreLayoutPassNotATruncation() {
        #expect(IdentityRowText.titleIsTruncated("A very long account label", renderedWidth: 0) == false)
    }

    /// U3/KTD3: the phone's title is 1.15× in size *and* kerning, so the truncation test
    /// measures the string at the scale it renders, not the popover's.
    @Test func truncationIsMeasuredAtTheRowsScale() {
        let popover = IdentityRowText.titleIntrinsicWidth("Personal")
        let phone = IdentityRowText.titleIntrinsicWidth("Personal", scale: 1.15)
        #expect(phone == HeadroomWidgetFontMetrics.textWidth(
            "Personal", size: 15 * 1.15, weight: .semibold, kerning: -0.15 * 1.15
        ))
        #expect(phone > popover)
        // A width that holds the popover title truncates the phone's.
        #expect(IdentityRowText.titleIsTruncated("Personal", renderedWidth: popover + 1) == false)
        #expect(IdentityRowText.titleIsTruncated("Personal", renderedWidth: popover + 1, scale: 1.15) == true)
    }

    /// A longer string needs more room, so it truncates at a width the shorter one survives.
    @Test func alongerTitleTruncatesSooner() {
        let short = IdentityRowText.titleIntrinsicWidth("Work")
        let long = IdentityRowText.titleIntrinsicWidth("Work — long-lived research account")
        #expect(long > short)
        #expect(IdentityRowText.titleIsTruncated("Work", renderedWidth: short + 4) == false)
        #expect(IdentityRowText.titleIsTruncated("Work — long-lived research account",
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
        let help = IdentityRowText.helpLines(
            title: "Personal",
            titleIsTruncated: true,
            email: "a@example.com",
            isMenuBarAccount: true,
            bankedHelp: banked
        )
        #expect(help == "Personal\na@example.com\n\(IdentityRowText.mainAccountHelp)\n\(banked)")
    }

    @Test func accessibilityPartsAppendTheBankedPhrase() {
        let label = IdentityRowText.accessibilityParts(
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

/// Default-login plan U8 (R7, R8, R16): a remembered row's popover presentation is keyed on
/// its kind. An engine row, stale or with an unavailable window, draws exactly as before.
@Suite
struct RememberedRowPresentationTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let utc = TimeZone(identifier: "UTC")!
    private let locale = Locale(identifier: "en_US_POSIX")

    /// AE2's aged snapshot: the 5-hour window reset three hours ago, the weekly one is ahead.
    private func agedSnapshot(readAt: Date) -> UsageSnapshot {
        let fiveHourReset = now.addingTimeInterval(-3 * 3_600)
        return UsageSnapshot(
            providerID: .claude,
            windows: [
                UsageWindow(kind: .fiveHour, utilization: 78, resetsAt: fiveHourReset,
                            freshness: .unavailable(since: fiveHourReset)),
                UsageWindow(kind: .weekly, utilization: 90, resetsAt: now.addingTimeInterval(2 * 86_400),
                            freshness: .stale(observedAt: readAt)),
            ],
            planLabel: "team", capturedAt: readAt, freshness: .stale(.transient("Last known usage"))
        )
    }

    private func entry(_ kind: DisplayAccountKind, readAgo: TimeInterval = 120) -> ProviderAccountEntry {
        let readAt = now.addingTimeInterval(-readAgo)
        return ProviderAccountEntry(
            account: ProviderAccount(id: AccountID("remembered-work"), providerID: .claude, label: "Work"),
            snapshot: agedSnapshot(readAt: readAt),
            kind: kind,
            lastReadAt: kind == .remembered ? readAt : nil
        )
    }

    private func presentation(_ entry: ProviderAccountEntry) -> AccountRowKindPresentation {
        AccountRowKindPresentation(entry: entry, now: now, timeZone: utc, locale: locale)
    }

    @Test func aRememberedRowCarriesLastReadInPlaceOfStale() {
        let shown = presentation(entry(.remembered))
        #expect(shown.lastReadLabel == "Last read 2 min ago")
        #expect(shown.isStale == false)
        #expect(shown.showsWindowState == false)
    }

    /// R8: one meter, one reset line, in window order, with the shared wording.
    @Test func aRememberedRowDrawsItsResetWindowAsOneLine() {
        let shown = presentation(entry(.remembered))
        let resetAt = now.addingTimeInterval(-3 * 3_600)
        #expect(shown.resetNotReadLines == [
            Countdown.resetNotReadLine(resetAt: resetAt, now: now, timeZone: utc, locale: locale),
            nil,
        ])
    }

    /// Keyed on kind, not freshness: the same stale snapshot with an unavailable window on an
    /// engine row keeps "Stale", its gauges and its retry.
    @Test func anEngineRowThatIsStaleRendersAsBefore() {
        let shown = presentation(entry(.engine))
        #expect(shown.isStale == providerCardHasTransientStaleState(entry(.engine).snapshot))
        #expect(shown.isStale)
        #expect(shown.lastReadLabel == nil)
        #expect(shown.resetNotReadLines.isEmpty)
        #expect(shown.showsWindowState)
        #expect(shown.dimsWholeRow == false)
        #expect(AccountSectionContent(freshness: entry(.engine).snapshot.freshness, kind: .engine) == .meters)
    }

    /// Mock dl-a2: the whole remembered row reads as secondary — labels and countdowns too,
    /// not only the gauge and number.
    @Test func aRememberedRowDimsItsWholeStack() {
        #expect(presentation(entry(.remembered)).dimsWholeRow)
    }

    /// R12: never probed, so no state of a remembered row reaches the session-owned or
    /// sign-in bodies, the only ones that draw Try Again, Check Now or a sign-in chip.
    @Test func aRememberedRowNeverDrawsARetryControl() {
        let states: [Freshness] = [
            .live,
            .pending,
            .stale(.transient("Last known usage")),
            .stale(.needsReauth("Sign in again")),
        ]
        for freshness in states {
            #expect(AccountSectionContent(freshness: freshness, kind: .remembered) == .meters)
        }
    }

    /// KTD8: a card of [engine row with no windows, remembered row with windows] has no
    /// retained reading, and the stop-waiting and active-handoff checks never ask about the
    /// remembered account.
    @MainActor @Test func theCardNeverCountsARememberedRowAsRetainedOrInSetup() {
        let engineAccount = ProviderAccount.builtIn(for: .claude)
        let engine = ProviderAccountEntry(
            account: engineAccount,
            snapshot: UsageSnapshot(providerID: .claude, windows: [], planLabel: nil, capturedAt: now,
                                    freshness: .stale(.transient("x")))
        )
        let remembered = entry(.remembered)
        #expect(!remembered.snapshot.windows.isEmpty)
        let entries = [engine, remembered]

        #expect(providerCardHasRetainedReading(entries: entries) == false)
        #expect(providerCardHasRetainedReading(entries: [remembered]) == false)

        var asked: [AccountKey] = []
        #expect(providerCardStopWaitingAccount(entries: entries, offersStopWaiting: {
            asked.append($0.key)
            return true
        }) == engineAccount)
        #expect(providerCardHasActiveSetupSession(entries: entries, hasActiveHandoff: {
            asked.append($0.key)
            return $0.key == remembered.account.key
        }) == false)
        #expect(!asked.contains(remembered.account.key))
    }

    /// The engine row's branches are unchanged.
    @Test func anEngineRowKeepsItsSetupBodies() {
        #expect(AccountSectionContent(freshness: .pending, kind: .engine) == .sessionOwned)
        #expect(AccountSectionContent(freshness: .stale(.needsReauth("Sign in again")), kind: .engine) == .signIn(.needsReauth("Sign in again")))
        #expect(AccountSectionContent(freshness: .stale(.transient("x")), kind: .engine) == .meters)
        #expect(AccountSectionContent(freshness: .live, kind: .engine) == .meters)
    }

    @Test func voiceOverSaysLastReadAndWhenForARememberedRow() {
        let shown = presentation(entry(.remembered, readAgo: 2 * 86_400))
        let label = IdentityRowText.accessibilityParts(
            title: "Work",
            planDisplayName: "Team",
            isMenuBarAccount: false,
            isStale: shown.isStale,
            email: nil,
            showsConnectedChip: false,
            bankedPhrase: nil,
            lastReadLabel: shown.lastReadLabel
        )
        #expect(label == "Work, Team plan, Last read 2 days ago")
        #expect(!label.contains("Stale"))
        // An engine stale row's phrase is unchanged.
        #expect(IdentityRowText.accessibilityParts(
            title: "Work", planDisplayName: "Team", isMenuBarAccount: false, isStale: true,
            email: nil, showsConnectedChip: false, bankedPhrase: nil
        ) == "Work, Team plan, Stale")
    }

    /// R16: no row, of either kind or role, carries a default-login marker in its tag, its
    /// tooltip or its VoiceOver phrase.
    @Test func noRowCarriesADefaultLoginMarker() {
        for kind in [DisplayAccountKind.engine, .remembered] {
            for isMain in [true, false] {
                let shown = presentation(entry(kind))
                let strings = [
                    shown.lastReadLabel ?? "",
                    IdentityRowText.helpLines(title: "Work", titleIsTruncated: true, email: "w@example.com",
                                              isMenuBarAccount: isMain, bankedHelp: nil) ?? "",
                    IdentityRowText.accessibilityParts(
                        title: "Work", planDisplayName: "Team", isMenuBarAccount: isMain,
                        isStale: shown.isStale, email: "w@example.com", showsConnectedChip: false,
                        bankedPhrase: nil, lastReadLabel: shown.lastReadLabel),
                    CompactAccountRowRecipe(
                        snapshot: entry(kind).snapshot, meterStyle: .default, percentageMode: .remaining,
                        now: now, requiresStandardSection: false, showsCodexSparkCounters: true,
                        isRemembered: kind == .remembered, lastReadAt: entry(kind).lastReadAt
                    ).tooltip,
                ]
                for string in strings {
                    #expect(!string.localizedCaseInsensitiveContains("default login"))
                }
            }
        }
    }
}

/// RI1: meter rows are keyed by window kind, so a row keeps its identity when a window above
/// it appears or leaves — the regression was "Weekly 40%" rolling into "5-hour 12%".
@Suite
struct UsageBarsStackRowKeyTests {
    private func window(_ kind: WindowKind) -> UsageWindow {
        UsageWindow(kind: kind, utilization: 40, resetsAt: Date(timeIntervalSince1970: 20))
    }

    @Test func rowsAreKeyedByKindInOrder() {
        let keys = UsageBarsStack.keyedRows([window(.fiveHour), window(.weekly)]).map(\.key)
        #expect(keys == [
            UsageBarsStack.RowKey(kind: .fiveHour, occurrence: 0),
            UsageBarsStack.RowKey(kind: .weekly, occurrence: 0),
        ])
    }

    @Test func aRowKeepsItsKeyWhenTheRowAboveItLeaves() {
        let before = UsageBarsStack.keyedRows([window(.fiveHour), window(.weekly), window(.other("Fable"))])
        let after = UsageBarsStack.keyedRows([window(.weekly), window(.other("Fable"))])
        #expect(Array(before.dropFirst().map(\.key)) == after.map(\.key))
    }

    @Test func repeatedKindsGetDistinctOccurrences() {
        let keys = UsageBarsStack.keyedRows([window(.other("Spark")), window(.other("Spark"))]).map(\.key)
        #expect(keys.map(\.occurrence) == [0, 1])
        #expect(Set(keys).count == 2)
    }
}

/// V13b/V6′ (2026-10-03): an account row's sentence is its primary action. These pin the two
/// decisions the row makes on its own — which words it marks as the action, and which glyph
/// (and ↗) an action gets from where it routes.
@Suite
@MainActor
struct CardRowActionTests {
    private func accentedRange(_ message: String, verb: String) -> String? {
        let text = CardRowAction<EmptyView>.accented(message, verb: verb, ink: .red)
        let marked = text.runs.filter { $0.swiftUI.font != nil }
        guard marked.count == 1, let run = marked.first else { return marked.isEmpty ? nil : "multiple" }
        return String(text[run.range].characters)
    }

    @Test func theActionWordsInsideTheSentenceAreTheOnesMarked() {
        #expect(accentedRange(ProviderSignInCopy.status(for: .claude), verb: ProviderSignInCopy.button) == "Sign in")
        #expect(accentedRange("Update Claude Code, then try again.", verb: "Try Again") == "try again")
        #expect(accentedRange("Codex sign-in isn’t stored privately — sign in again",
                              verb: ProviderSignInCopy.buttonAgain) == "sign in again")
    }

    /// No copy is invented: a sentence that doesn't name its action stays plain.
    @Test func aSentenceWithoutItsActionStaysPlain() {
        #expect(accentedRange("Couldn’t read Codex sign-in data", verb: "Check Now") == nil)
        #expect(String(CardRowAction<EmptyView>.accented("Sign-in wasn’t confirmed.", verb: "Sign In",
                                                         ink: .red).characters) == "Sign-in wasn’t confirmed.")
    }

    @Test func terminalHandoffsWebPagesAndRereadsEachGetTheirOwnGlyph() {
        for action in [SetupRecoveryAction.openClaudeSetup, .connectCodex, .reconnectCodex, .connectGrok,
                       .reconnectGrok, .connectCursor, .openClaudeWorkspace, .openCursorWorkspace,
                       .reviewCursorTools, .resolveCodexStorage, .connectCopilot, .connectOpenCode] {
            #expect(SetupSessions.recoveryRoute(for: action).systemImage == "apple.terminal")
        }
        for action in [SetupRecoveryAction.installClaudeCLI, .installCodexCLI, .installGrokCLI,
                       .installCursorAgent, .installCopilotCLI, .showPrivacyGuidance,
                       .installOpenCodeCLI, .updateOpenCode, .seeOpenCodeGoPlans] {
            #expect(SetupSessions.recoveryRoute(for: action).systemImage == "globe")
        }
        // Device code is the alternative beside a Terminal sign-in, so it can't share its glyph.
        #expect(SetupSessions.recoveryRoute(for: .connectCodexDeviceCode).systemImage == "number")
        #expect(SetupSessions.recoveryRoute(for: .checkNow).systemImage == "arrow.clockwise")
        #expect(SetupSessions.recoveryRoute(for: .contactSupport).systemImage == "envelope")
    }

    /// The ↗ promises the click leaves Headroom, so Check Now — a re-read in place — never
    /// carries it.
    @Test func onlyActionsThatLeaveHeadroomCarryTheArrow() {
        #expect(SetupRowChip.checkNow.opensElsewhere == false)
        #expect(SetupRowChip.recovery(.checkNow, label: "Check Now").opensElsewhere == false)
        #expect(SetupRowChip.tryAgain.opensElsewhere)
        #expect(SetupRowChip.signIn.opensElsewhere)
        #expect(SetupRowChip.recovery(.installClaudeCLI, label: "Install Claude Code").opensElsewhere)
        #expect(CardRowButtonAction(label: "Check Now", recovery: .checkNow, perform: {}).opensElsewhere == false)
        #expect(CardRowButtonAction(label: "Sign In", recovery: .connectGrok, perform: {}).opensElsewhere)
    }
}

/// U3: the spend row's VoiceOver phrase moved to the shared row with its layout; it still
/// reads the figure then its direction, and the state only when the row is not live.
@Suite
struct APISpendRowAccessibilityTests {
    private func snapshot(_ freshness: Freshness, kind: APISpendKind = .periodSpend) -> APISpendSnapshot {
        APISpendSnapshot(
            providerID: .claude, displayName: "Anthropic API", amount: 142.67, currency: "USD",
            periodLabel: "October", kind: kind, capturedAt: nil, freshness: freshness
        )
    }

    @Test func aLiveRowReadsItsFigureAndDirection() {
        let status = APISpendRowStatus(badge: nil, tone: .quiet, message: nil, callToAction: nil, remoteHint: nil)
        #expect(APISpendRowMetrics.accessibilityLabel(
            snapshot: snapshot(.live), contextLabel: "Oct", amount: "$142.67", status: status
        ) == "Anthropic API, Oct, $142.67 used")
        #expect(APISpendRowMetrics.accessibilityLabel(
            snapshot: snapshot(.live, kind: .balance), contextLabel: "Remaining balance", amount: "$142.67", status: status
        ) == "Anthropic API, Remaining balance, $142.67 left")
    }

    @Test func aStaleRowAddsItsBadgeAndMessage() {
        let status = APISpendRowStatus(
            badge: "Key rejected", shortBadge: "Rejected", tone: .critical,
            message: "The key was rejected", callToAction: "Replace Key", remoteHint: nil
        )
        #expect(APISpendRowMetrics.accessibilityLabel(
            snapshot: snapshot(.stale(.needsReauth("x"))), contextLabel: "Oct", amount: nil, status: status
        ) == "Anthropic API, Oct, Key rejected, The key was rejected")
    }
}
