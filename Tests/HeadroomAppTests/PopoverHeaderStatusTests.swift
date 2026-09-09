import HeadroomCore
import Testing
@testable import Headroom

/// PA10: the popover has one status slot, and the audit caught it contradicting the card it
/// labels — an expired session, a denied read and a misplaced sign-in all read "Connect Codex
/// to begin" over cards saying "Reconnect Codex" or that signing in again will not help.
/// These pin the derivation to the same `CodexConnectionAction` the card switches on, and pin
/// the one verb ("Waiting for …") that the cards and account rows already use.
@Suite
struct PopoverHeaderStatusTests {
    @Test func everyCodexActionGetsItsOwnHeaderLine() {
        #expect(PopoverHeaderStatusText.codex(action: .connect, isWaiting: false)
            == "Connect Codex to begin")
        #expect(PopoverHeaderStatusText.codex(action: .reconnect, isWaiting: false)
            == "Reconnect Codex")
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
            == "Set up Claude to begin")
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
