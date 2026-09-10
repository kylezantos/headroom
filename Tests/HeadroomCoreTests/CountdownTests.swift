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

    private func text(after interval: TimeInterval) -> String {
        let window = UsageWindow(
            kind: .weekly,
            utilization: 20,
            resetSchedule: .scheduled(now.addingTimeInterval(interval))
        )
        return Countdown.resetText(for: window, now: now)
    }
}
