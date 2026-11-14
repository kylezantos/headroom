import Foundation
import Testing
@testable import HeadroomCore

struct CountdownTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func approvedCountdownPrecision() {
        #expect(text(after: 6 * 86_400 + 4 * 3_600 + 37 * 60) == "Resets in 6d 4h")
        #expect(text(after: 6 * 86_400 + 37 * 60) == "Resets in 6d")
        #expect(text(after: 13 * 3_600 + 37 * 60) == "Resets in 13h 37m")
        #expect(text(after: 37 * 60) == "Resets in 37m")
    }

    @Test func immediateResetCopyStartsAtTheSourceBoundary() {
        #expect(text(after: 61) == "Resets in 1m")
        #expect(text(after: 60) == "Resets now")
        #expect(text(after: -60) == "Resets now")
    }

    /// R2M3: past the deadline the countdown holds "now" rather than blanking — the
    /// pre-reset percentage is still on screen until a fresh capture lands, and a missing
    /// label beside a stale number reads as a bug.
    @Test func countdownHoldsNowPastTheDeadline() {
        #expect(text(after: -61) == "Resets now")
        #expect(text(after: -37 * 60) == "Resets now")
        #expect(text(after: -4 * 3_600) == "Resets now")

        let elapsed = Countdown.resetLine(resetsAt: now.addingTimeInterval(-3_600), now: now)
        #expect(elapsed?.countdown == "now")
        #expect(elapsed?.shortCountdown == "now")
        #expect(elapsed?.tooltip == "Resets now")
    }

    /// The macOS meter and the widgets read the same helper, so an elapsed deadline can no
    /// longer say "now" on one surface and "Reset info unavailable" on the other.
    @Test func macAndWidgetSurfacesAgreeOnAnElapsedDeadline() {
        let window = UsageWindow(
            kind: .fiveHour,
            utilization: 72,
            resetSchedule: .scheduled(now.addingTimeInterval(-15 * 60))
        )
        #expect(window.resetSchedule.meterResetLine(now: now)?.countdown == "now")
        #expect(Countdown.resetText(for: window, now: now) == "Resets now")
    }

    /// A new capture is what ends the hold: a later deadline resumes the countdown.
    @Test func aFreshCaptureResumesTheCountdown() {
        #expect(text(after: 5 * 3_600) == "Resets in 5h")
    }

    @Test func availableRequiresFreshSameCaptureEvidence() {
        let liveZeroAbsent = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.absent)
        )
        let liveZeroElapsed = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.elapsed)
        )
        let liveNonzeroAbsent = UsageWindow(
            kind: .fiveHour,
            utilization: 12,
            resetSchedule: .unresolved(.absent)
        )
        let staleZeroAbsent = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.absent),
            freshness: .stale(observedAt: now.addingTimeInterval(-300))
        )

        #expect(Countdown.resetText(for: liveZeroAbsent, now: now) == "Available")
        #expect(Countdown.resetText(for: liveZeroElapsed, now: now) == "Available")
        #expect(Countdown.resetText(for: liveNonzeroAbsent, now: now) == "Reset info unavailable")
        #expect(Countdown.resetText(for: staleZeroAbsent, now: now) == "Reset info unavailable")
    }

    // MARK: CA-P3 / CA-P4

    /// CA-P3: a stale row's chip says when it was read, in the remembered row's words.
    @Test func aStaleReadSaysWhenItWasRead() {
        #expect(Countdown.staleReadLabel(capturedAt: now.addingTimeInterval(-14 * 60), now: now)
            == "Last read 14 min ago")
        #expect(Countdown.staleReadLabel(capturedAt: now.addingTimeInterval(-3 * 3_600), now: now)
            == "Last read 3 hr ago")
        #expect(Countdown.staleReadLabel(capturedAt: nil, now: now) == "Not refreshed")
        #expect(Countdown.staleReadLabel(capturedAt: now.addingTimeInterval(-14 * 60), now: now)
            == Countdown.lastReadLabel(capturedAt: now.addingTimeInterval(-14 * 60), now: now))
        #expect(Countdown.windowReadLabel(observedAt: now.addingTimeInterval(-60), now: now) == "Last read 1 min ago")
        #expect(Countdown.windowReadLabel(observedAt: nil, now: now) == "Last read")
    }

    @Test func theReadTooltipsSayWhy() {
        #expect(Countdown.staleReadHelp == "Couldn’t refresh this account. Headroom tries again on its next check.")
        #expect(Countdown.rememberedReadHelp(for: .claude)
            == "Not your current Claude login, so Headroom isn’t reading it. Sign in to it again, or add it in Settings › Accounts to keep it live.")
        for provider in [ProviderID.claude, .codex, .grok, .cursor, .copilot, .opencode] {
            #expect(Countdown.rememberedReadHelp(for: provider).contains(provider.displayName))
        }
    }

    /// CA-P4: never read reads "No reading yet"; aged out reads "No current reading"; neither
    /// is a number, and neither claims anything about use this month.
    @Test func anUnavailableWindowSaysWhetherItWasEverRead() {
        let neverRead = UsageWindow(kind: .weekly, utilization: 0, resetSchedule: .unresolved(.absent),
                                    freshness: .unavailable(since: now))
        let agedOut = UsageWindow(kind: .other("Weekly (Fable)"), utilization: 46,
                                  resetSchedule: .scheduled(now.addingTimeInterval(86_400)),
                                  freshness: .unavailable(since: now), observedAt: now.addingTimeInterval(-3_600))
        let live = UsageWindow(kind: .weekly, utilization: 20, resetSchedule: .scheduled(now.addingTimeInterval(60)))
        #expect(Countdown.unavailableLabel(for: neverRead) == "No reading yet")
        #expect(Countdown.unavailableLabel(for: agedOut) == "No current reading")
        #expect(Countdown.unavailableLabel(for: live) == nil)
        #expect(Countdown.unavailableHelp(for: agedOut, providerID: .claude)
            == "Claude didn’t report this limit in its last check.")
        #expect(Countdown.unavailableHelp(for: neverRead, providerID: .copilot)
            == "Copilot hasn’t reported a number for this limit yet.")
        #expect(Countdown.unavailableHelp(for: live, providerID: .claude) == nil)
        for text in [Countdown.noReadingYet, Countdown.noCurrentReading,
                     Countdown.unavailableHelp(for: neverRead, providerID: .copilot) ?? ""] {
            #expect(!text.localizedCaseInsensitiveContains("this month"))
            #expect(text.rangeOfCharacter(from: .decimalDigits) == nil)
        }
    }

    private func text(after interval: TimeInterval) -> String {
        let window = UsageWindow(
            kind: .weekly,
            utilization: 20,
            resetSchedule: .scheduled(now.addingTimeInterval(interval))
        )
        return Countdown.resetText(for: window, now: now)
    }
}
