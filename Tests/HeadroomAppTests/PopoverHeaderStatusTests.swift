import Foundation
import HeadroomCore
import Testing
@testable import Headroom

/// PA10: the popover has one status slot, and the audit caught it contradicting the card it
/// labels — an expired session, a denied read and a misplaced sign-in all read "Sign in to Codex
/// to begin" over cards saying "Sign in to Codex again" or that signing in again will not help.
/// These pin the derivation to the same `CodexConnectionAction` the card switches on, and pin
/// the one verb ("Waiting for …") that the cards and account rows already use.
@Suite(.sharedAppState)
struct PopoverHeaderStatusTests {
    @Test func everyCodexActionGetsItsOwnHeaderLine() {
        #expect(PopoverHeaderStatusText.codex(action: .connect, isWaiting: false)
            == "Sign in to Codex to begin")
        #expect(PopoverHeaderStatusText.codex(action: .reconnect, isWaiting: false)
            == "Sign in to Codex again")
        #expect(PopoverHeaderStatusText.codex(action: .showPrivacyGuidance, isWaiting: false)
            == "Codex needs file access")
        #expect(PopoverHeaderStatusText.codex(action: .resolveStorage, isWaiting: false)
            == "Codex sign-in needs relocating")
    }

    /// The four lines are distinct — the whole point of PA10 is that the slot stops
    /// collapsing four states into one sentence.
    @Test func noTwoCodexActionsShareALine() {
        let actions: [CodexConnectionAction] = [
            .connect, .reconnect, .showPrivacyGuidance, .resolveStorage,
        ]
        let lines = Set(actions.map { PopoverHeaderStatusText.codex(action: $0, isWaiting: false) })
        #expect(lines.count == actions.count)
    }

    /// An open handoff outranks the action: whatever sent the user to Terminal, the header's
    /// job while they are there is to say Headroom is still watching. CA-P8: in the card's own
    /// words.
    @Test func anOpenHandoffOverridesEveryCodexAction() {
        for action in [
            CodexConnectionAction.connect, .reconnect, .showPrivacyGuidance, .resolveStorage,
        ] {
            #expect(PopoverHeaderStatusText.codex(action: action, isWaiting: true)
                == CodexWaitingCopy.title(mode: .standard, phase: nil))
        }
    }

    @Test func claudeKeepsItsTwoStagesPerOutcome() {
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeLoginRequired, isWaiting: false)
            == "Sign in to Claude to begin")
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: false)
            == "Sign in to Claude to begin")
    }

    /// CA-P8 (COPY-06): without a start time the header falls back to a phrase, and that
    /// phrase is the waiting card's own title. It used to key on the outcome while the card
    /// keyed on the handoff's phase, so the two could say "approval" and "sign-in" at once.
    @Test func theWaitingFallbackIsTheCardsOwnTitle() {
        let signIn = SetupWaitingPhase.waitingForUser(.signIn)
        let approval = SetupWaitingPhase.waitingForUser(.workspaceApproval)
        for outcome in [ProviderSetupOutcome.claudeLoginRequired, .claudeTrustRequired] {
            for phase in [signIn, approval] {
                let card = claudeWaitingCardContent(state: .waiting(attempt: 0), phase: phase,
                    hasActiveHandoff: true, failureMessage: nil, failureDetail: nil)
                #expect(PopoverHeaderStatusText.claude(outcome: outcome, isWaiting: true, phase: phase) == card.title)
            }
        }
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: true, phase: approval)
            == "Waiting for approval…")
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: true, phase: signIn)
            == "Waiting for sign-in…")
        for mode in [SetupHandoffMode.standard, .deviceCode] {
            for phase in [nil, signIn, SetupWaitingPhase.waitingForUser(.deviceCode)] {
                #expect(PopoverHeaderStatusText.codex(action: .reconnect, isWaiting: true, mode: mode, phase: phase)
                    == CodexWaitingCopy.title(mode: mode, phase: phase))
            }
        }
    }

    /// PA10: "Watching for …" is retired everywhere. The cards and account rows say "Waiting
    /// for …" and the header now matches them.
    @Test func theHeaderNeverSaysWatching() {
        var lines = [
            PopoverHeaderStatusText.claude(outcome: .claudeLoginRequired, isWaiting: true),
            PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: true),
            PopoverHeaderStatusText.claude(outcome: .claudeLoginRequired, isWaiting: false),
            PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: false),
        ]
        for action in [
            CodexConnectionAction.connect, .reconnect, .showPrivacyGuidance, .resolveStorage,
        ] {
            lines.append(PopoverHeaderStatusText.codex(action: action, isWaiting: true))
            lines.append(PopoverHeaderStatusText.codex(action: action, isWaiting: false))
        }
        #expect(lines.allSatisfy { !$0.contains("Watching") })
    }
}

/// R2M5: the slot used to collect `.live` captures and return nil for everything else, so
/// first run, an all-stale popover and a capability failure showed a card full of retained
/// numbers with no visible age anywhere. Since Sep 2026 the age lives in the footer beside
/// Refresh and the header speaks only for setup; these pin both lines and their precedence.
@Suite(.sharedAppState)
struct PopoverHeaderStatusResolverTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func input(
        setupText: String? = nil,
        waitingElapsed: TimeInterval? = nil,
        oldestLiveCapture: Date? = nil,
        newestCheck: Date? = nil
    ) -> PopoverHeaderStatusResolver.Input {
        PopoverHeaderStatusResolver.Input(
            setupText: setupText,
            waitingElapsed: waitingElapsed,
            oldestLiveCapture: oldestLiveCapture,
            newestCheck: newestCheck,
            now: now
        )
    }

    /// U3: the stamp's wording moved to Core (`FreshnessStampTests`); the footer keeps its
    /// slot identity, so each Core kind must land on its own `PopoverHeaderStatus.Kind`.
    @Test func theFooterMapsEveryCoreStampOntoItsOwnSlot() {
        let live = PopoverHeaderStatusResolver.freshness(input(oldestLiveCapture: now.addingTimeInterval(-8 * 60)))
        #expect(live == PopoverHeaderStatus(kind: .updated, text: "8 min ago", rollValue: 8))
        let retained = PopoverHeaderStatusResolver.freshness(input(newestCheck: now.addingTimeInterval(-12 * 60)))
        #expect(retained == PopoverHeaderStatus(kind: .lastChecked, text: "Checked 12 min ago", rollValue: 12))
        #expect(PopoverHeaderStatusResolver.freshness(input())
            == PopoverHeaderStatus(kind: .never, text: "Not checked yet", rollValue: nil))
    }

    /// The header is empty unless a setup card needs the user.
    @Test func theHeaderIsQuietWithoutSetup() {
        #expect(PopoverHeaderStatusResolver.setup(input(oldestLiveCapture: now)) == nil)
    }

    /// CA-P8 (POP-11, revisits PA10): while the setup card is in the visible stack the line
    /// would repeat its title 40pt above it, so the slot is empty; once the card has scrolled
    /// out of the viewport the phrase returns.
    @Test func theSetupPhraseShowsOnlyOnceTheCardHasScrolledOut() {
        for text in [
            PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: false),
            PopoverHeaderStatusText.codex(action: .connect, isWaiting: false),
            PopoverHeaderStatusText.codex(action: .reconnect, isWaiting: false),
        ] {
            var visible = input(setupText: text, oldestLiveCapture: now)
            visible.setupCardVisible = true
            #expect(PopoverHeaderStatusResolver.setup(visible) == nil)

            let scrolledOut = PopoverHeaderStatusResolver.setup(input(setupText: text, oldestLiveCapture: now))
            #expect(scrolledOut?.kind == .setup)
            #expect(scrolledOut?.text == text)
            // A phrase must never try to roll its letters into a number.
            #expect(scrolledOut?.rollValue == nil)
        }
    }

    /// The clock is not a repeat of the card, so it shows with the card on screen.
    @Test func theWaitingClockShowsWithTheCardOnScreen() {
        var visible = input(setupText: "Waiting for approval…", waitingElapsed: 12)
        visible.setupCardVisible = true
        #expect(PopoverHeaderStatusResolver.setup(visible)?.text == "Waiting 12s")
    }

    /// CA-P8: a card is scrolled out only when every piece of it is outside the viewport, and
    /// an unmeasured viewport (the offscreen harness) hides nothing.
    @Test func aCardIsScrolledOutOnlyWhenEveryPieceIsOutOfView() {
        let pieces: [(provider: ProviderID, minY: CGFloat, maxY: CGFloat)] = [
            (.claude, 0, 300), (.codex, 320, 700), (.codex, 0, 120),
        ]
        #expect(PopoverSetupCardVisibility.scrolledOutProviders(pieces: pieces, viewportTop: 0, viewportBottom: 640).isEmpty)
        #expect(PopoverSetupCardVisibility.scrolledOutProviders(pieces: pieces, viewportTop: 400, viewportBottom: 1040)
            == [.claude])
        #expect(PopoverSetupCardVisibility.scrolledOutProviders(pieces: pieces, viewportTop: 0, viewportBottom: 0).isEmpty)
    }

    /// CA-P8 review fix: a split card that unsplits leaves its second fragment's frame behind;
    /// pruning to the fragments drawn lets the header see the one card that is left.
    @MainActor @Test func aFragmentNoLongerDrawnStopsDecidingTheHeader() {
        let model = PopoverScrollModel()
        model.update(PopoverScrollMetrics(offset: 400, viewport: 640, content: 1_200))
        model.recordCardFrame(CGRect(x: 0, y: 0, width: 384, height: 300), fragmentID: "claude.0", providerID: .claude)
        // The unsplit card's old second piece, still inside the viewport.
        model.recordCardFrame(CGRect(x: 384, y: 500, width: 384, height: 200), fragmentID: "claude.1", providerID: .claude)
        #expect(model.scrolledOutProviders.isEmpty)
        model.pruneCardFrames(keeping: ["claude.0"])
        #expect(model.scrolledOutProviders == [.claude])
    }

    /// R2M12: the clock replaces the card's own title rather than repeating it.
    @Test func anOpenHandoffReplacesTheEchoWithAClock() {
        let status = PopoverHeaderStatusResolver.setup(
            input(setupText: "Waiting for approval…", waitingElapsed: 45)
        )
        #expect(status?.kind == .waiting)
        #expect(status?.text == "Waiting 45s")
        // WC1: the per-second clock never rolls.
        #expect(status?.rollValue == nil)
    }
}

/// R2M12: an open-ended wait needs a clock (Apple §16 status). The Connect card is explicit
/// about "Takes about 20 seconds" and the waiting state used to drop the thread entirely.
@Suite(.sharedAppState)
struct PopoverWaitingClockTests {
    @Test func secondsReadPlainlyForTheFirstMinute() {
        #expect(PopoverHeaderStatusText.waiting(elapsed: 0) == "Waiting 0s")
        #expect(PopoverHeaderStatusText.waiting(elapsed: 45) == "Waiting 45s")
        #expect(PopoverHeaderStatusText.waiting(elapsed: 59.9) == "Waiting 59s")
    }

    /// Zero-padded past the minute so the digits roll in place instead of the column
    /// jittering one glyph wider every ten seconds.
    @Test func pastAMinuteTheSecondsArePadded() {
        #expect(PopoverHeaderStatusText.waiting(elapsed: 60) == "Waiting 1m 00s")
        #expect(PopoverHeaderStatusText.waiting(elapsed: 125) == "Waiting 2m 05s")
        #expect(PopoverHeaderStatusText.waiting(elapsed: 3_599) == "Waiting 59m 59s")
    }

    @Test func anAbandonedHandoffDegradesToHoursAndMinutes() {
        #expect(PopoverHeaderStatusText.waiting(elapsed: 3_600) == "Waiting 1h 00m")
        #expect(PopoverHeaderStatusText.waiting(elapsed: 7_980) == "Waiting 2h 13m")
    }

    /// A clock is never negative, whatever the clock does behind it.
    @Test func aBackwardsClockNeverShowsNegativeTime() {
        #expect(PopoverHeaderStatusText.waiting(elapsed: -30) == "Waiting 0s")
    }
}

/// R2M1: the card's second animation scope keys on this, so a retry counter that changes
/// nothing on screen must not restage the crossfade.
@Suite(.sharedAppState)
struct ProviderCardSessionKeyTests {
    @Test func retryAttemptsCollapseToOneWaitingKey() {
        #expect(providerCardSessionKey(.waiting(attempt: 0)) == .waiting(attempt: 0))
        #expect(providerCardSessionKey(.waiting(attempt: 7)) == .waiting(attempt: 0))
    }

    @Test func everyOtherStateIsItsOwnKey() {
        let states: [SetupSessionState] = [
            .idle, .preparing, .verifying, .blockedByOpenHandoff, .connected,
            .cancelled, .removing, .removalFailed, .removed,
            .failed(.retryExhausted),
        ]
        for state in states {
            #expect(providerCardSessionKey(state) == state)
        }
        // The states the card actually swaps bodies between stay distinguishable.
        #expect(providerCardSessionKey(.idle) != providerCardSessionKey(.waiting(attempt: 3)))
        #expect(
            providerCardSessionKey(.failed(.terminalRejected))
                != providerCardSessionKey(.failed(.retryExhausted))
        )
    }

    /// KTD11 (2026-09-19 sign-in plan): the waiting phase is not carried inside
    /// `.waiting(attempt:)` precisely because this key flattens it. Every phase the surfaces
    /// distinguish therefore has to land on its own key, or a crossfade would be skipped.
    @Test func everyWaitingPhaseLandsOnItsOwnSessionKey() {
        let phaseStates: [SetupSessionState] = [
            .preparing, .waiting(attempt: 0), .verifying, .failed(.waitingTimedOut),
        ]
        let keys = phaseStates.map { providerCardSessionKey($0) }
        for (index, key) in keys.enumerated() {
            for other in keys[(index + 1)...] {
                #expect(key != other, "\(key) and \(other) share one animation key")
            }
        }
        // And the retry counter inside one phase still changes nothing.
        #expect(
            providerCardSessionKey(.waiting(attempt: 0))
                == providerCardSessionKey(.waiting(attempt: 9))
        )
    }
}


/// CA-MB3 (MB-F): which account carries the menu-bar source glyph. Pure over the store's
/// meters and the display list's main, so no store is stood up.
@Suite(.sharedAppState)
struct MenuBarPillSourceTests {
    private let claudeMain = AccountKey(providerID: .claude, accountID: .primary)
    private let claudeWork = AccountKey(providerID: .claude, accountID: AccountID("work"))
    private let codexMain = AccountKey(providerID: .codex, accountID: .primary)

    private func mains(_ id: ProviderID) -> AccountKey? {
        switch id {
        case .claude: claudeMain
        case .codex: codexMain
        default: nil
        }
    }

    private func meter(_ id: ProviderID?, automatic: Bool = false) -> MenuBarMeter {
        MenuBarMeter(
            summary: MenuBarSummary(text: "72%", providerID: id, detail: nil, isNeutral: id == nil),
            fill: 0.72,
            isAutomaticSummary: automatic
        )
    }

    private func flagged(_ meters: [MenuBarMeter], key: AccountKey, accounts: Int) -> Bool {
        IdentityRowText.feedsMenuBar(
            isPillSource: MenuBarPillSource.sourceKeys(meters: meters, displayPrimaryKey: mains).contains(key),
            providerAccountCount: accounts
        )
    }

    @Test func withClaudeInTheMenuBarOnlyItsMainAccountIsFlagged() {
        let meters = [meter(.claude), meter(.codex)]
        #expect(flagged(meters, key: claudeMain, accounts: 2))
        #expect(!flagged(meters, key: claudeWork, accounts: 2))
    }

    @Test func withClaudeOutOfTheMenuBarNoClaudeAccountIsFlagged() {
        let meters = [meter(.codex)]
        #expect(!flagged(meters, key: claudeMain, accounts: 2))
        #expect(!flagged(meters, key: claudeWork, accounts: 2))
    }

    @Test func automaticModeFlagsTheFollowedProvidersMainAccount() {
        #expect(flagged([meter(.claude, automatic: true)], key: claudeMain, accounts: 2))
        #expect(!flagged([meter(.codex, automatic: true)], key: claudeMain, accounts: 2))
        #expect(MenuBarPillSource.sourceKeys(meters: [meter(nil, automatic: true)], displayPrimaryKey: mains).isEmpty)
    }

    /// One account: the glyph would be noise.
    @Test func aProviderWithOneAccountIsNeverFlagged() {
        #expect(!flagged([meter(.claude)], key: claudeMain, accounts: 1))
    }
}

/// CA-P8, CA-F1: guards on the popover's sources for decisions a view test cannot reach.
@Suite(.sharedAppState)
struct PopoverSourceGuardTests {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// CA-P8 (POP-08): every guided setup card title is in primary ink; the brand lives in the
    /// mark and the CTA. Grok, Cursor, Copilot and OpenCode have no guided card (their setup
    /// is the account row), so these two files hold every setup title.
    @Test func setupCardTitlesUseNoBrandInk() throws {
        for path in ["Sources/HeadroomApp/UI/ClaudeSetupViews.swift", "Sources/HeadroomApp/UI/CodexSetupViews.swift"] {
            #expect(try !source(path).contains(".foregroundStyle(ProviderStyle.textAccent("), "\(path) tints a title")
        }
    }

    /// CA-F1 (MOT-10): under Reduce Motion the reorder scope resolves to nil, so the plain
    /// reveal hard-cut a new card in. Both popover insertions take the Reduce Motion form.
    @Test func popoverCardInsertionsUseTheReduceMotionReveal() throws {
        let popover = try source("Sources/HeadroomApp/UI/PopoverView.swift")
        #expect(!popover.contains(".transition(.settingsReveal)"))
        #expect(popover.components(separatedBy: ".transition(.settingsReveal(reduceMotion: reduceMotion))").count - 1 == 2)
    }
}
