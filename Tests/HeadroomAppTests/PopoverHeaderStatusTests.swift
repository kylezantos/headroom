import Foundation
import HeadroomCore
import Testing
@testable import Headroom

/// PA10: the popover has one status slot, and the audit caught it contradicting the card it
/// labels — an expired session, a denied read and a misplaced sign-in all read "Sign in to Codex
/// to begin" over cards saying "Sign in to Codex again" or that signing in again will not help.
/// These pin the derivation to the same `CodexConnectionAction` the card switches on, and pin
/// the one verb ("Waiting for …") that the cards and account rows already use.
@Suite
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
    /// job while they are there is to say Headroom is still watching.
    @Test func anOpenHandoffOverridesEveryCodexAction() {
        for action in [
            CodexConnectionAction.connect, .reconnect, .showPrivacyGuidance, .resolveStorage,
        ] {
            #expect(PopoverHeaderStatusText.codex(action: action, isWaiting: true)
                == "Waiting for Codex sign-in…")
        }
    }

    @Test func claudeKeepsItsTwoStagesPerOutcome() {
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeLoginRequired, isWaiting: false)
            == "Sign in to Claude to begin")
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: false)
            == "Sign in to Claude to begin")
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeLoginRequired, isWaiting: true)
            == "Waiting for Claude sign-in…")
        #expect(PopoverHeaderStatusText.claude(outcome: .claudeTrustRequired, isWaiting: true)
            == "Waiting for approval…")
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
@Suite
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

    /// Beside Refresh the stamp needs no "Updated" verb.
    @Test func aLiveCaptureReadsAsABareAge() {
        let status = PopoverHeaderStatusResolver.freshness(
            input(oldestLiveCapture: now.addingTimeInterval(-8 * 60))
        )
        #expect(status.kind == .updated)
        #expect(status.text == "8 min ago")
        #expect(status.rollValue == 8)
    }

    @Test func aFreshCaptureReadsAsSentenceCase() {
        let status = PopoverHeaderStatusResolver.freshness(input(oldestLiveCapture: now))
        #expect(status.text == "Just now")
    }

    /// The whole point of R2M5: retained numbers on screen still carry a date, and say
    /// they are not live.
    @Test func nothingLiveFallsBackToTheNewestObservation() {
        let status = PopoverHeaderStatusResolver.freshness(
            input(newestCheck: now.addingTimeInterval(-12 * 60))
        )
        #expect(status.kind == .lastChecked)
        #expect(status.text == "Checked 12 min ago")
        #expect(status.rollValue == 12)
    }

    @Test func firstRunSaysSoRatherThanGoingSilent() {
        let status = PopoverHeaderStatusResolver.freshness(input())
        #expect(status.kind == .never)
        #expect(status.text == "Not checked yet")
        #expect(status.rollValue == nil)
    }

    /// The header is empty unless a setup card needs the user.
    @Test func theHeaderIsQuietWithoutSetup() {
        #expect(PopoverHeaderStatusResolver.setup(input(oldestLiveCapture: now)) == nil)
    }

    @Test func aSetupCardOwnsTheHeaderWhileItIsOnScreen() {
        let status = PopoverHeaderStatusResolver.setup(
            input(setupText: "Sign in to Claude to begin", oldestLiveCapture: now)
        )
        #expect(status?.kind == .setup)
        #expect(status?.text == "Sign in to Claude to begin")
        // A phrase must never try to roll its letters into a number.
        #expect(status?.rollValue == nil)
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
@Suite
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
@Suite
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
