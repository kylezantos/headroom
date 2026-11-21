import Foundation
import Testing
@testable import HeadroomCore

/// "Show 5-hour windows" off hides Antigravity's 5-hour rows only while a weekly row still has
/// a number to show.
struct AntigravityFiveHourWindowsTests {
    private let now = Date(timeIntervalSince1970: 1_790_355_600)

    private func row(_ label: String, used: Double, freshness: UsageWindowFreshness = .live) -> UsageWindow {
        UsageWindow(kind: .other(label), utilization: used, resetsAt: now.addingTimeInterval(3_600), freshness: freshness)
    }

    private func visible(_ windows: [UsageWindow]) -> [WindowKind] {
        AntigravityFiveHourWindows.visibleWindows(windows, providerID: .antigravity, showsFiveHourWindows: false)
            .map(\.kind)
    }

    @Test func aUsableWeeklyRowHidesTheFiveHourRows() {
        let windows = [row("Gemini 5h", used: 10), row("Gemini weekly", used: 20), row("Other 5h", used: 5)]
        #expect(visible(windows) == [.other("Gemini weekly")])
    }

    @Test func unavailableWeeklyRowsKeepTheFiveHourRows() {
        let windows = [
            row("Gemini 5h", used: 10),
            row("Gemini weekly", used: 20, freshness: .unavailable(since: now)),
            row("Other weekly", used: .nan),
        ]
        #expect(visible(windows) == windows.map(\.kind))
    }

    @Test func oneUsableWeeklyRowIsEnough() {
        let windows = [
            row("Gemini 5h", used: 10),
            row("Gemini weekly", used: 20, freshness: .unavailable(since: now)),
            row("Other weekly", used: 30, freshness: .stale(observedAt: now)),
        ]
        #expect(visible(windows) == [.other("Gemini weekly"), .other("Other weekly")])
    }

    @Test func aFiveHourOnlyReadingKeepsItsRows() {
        let windows = [row("Gemini 5h", used: 10), row("Other 5h", used: 5)]
        #expect(visible(windows) == windows.map(\.kind))
    }

    @Test func theSwitchOnOrAnotherProviderChangesNothing() {
        let windows = [row("Gemini 5h", used: 10), row("Gemini weekly", used: 20)]
        #expect(AntigravityFiveHourWindows.visibleWindows(windows, providerID: .antigravity, showsFiveHourWindows: true)
            .count == 2)
        #expect(AntigravityFiveHourWindows.visibleWindows(windows, providerID: .cursor, showsFiveHourWindows: false)
            .count == 2)
    }
}
