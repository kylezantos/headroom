import Foundation
import Testing
@testable import HeadroomCore

/// R15 / WCW1 / WCW8: the widget styles' printed and spoken window strings, one test per branch.
struct WidgetWindowTextTests {
    typealias F = StyleFixture

    private let unavailable = F.window(.weekly, label: "Weekly", percent: 9, freshness: .unavailable(since: F.now))

    // MARK: percent and countdown

    @Test func percentRoundsAndUsesAnEmDashWithoutAValue() {
        #expect(WidgetWindowText.percent(F.window(.weekly, label: "Weekly", percent: 38.6)) == "39%")
        #expect(WidgetWindowText.percent(unavailable) == "—")
        #expect(WidgetWindowText.percent(nil) == "—")
    }

    @Test func countdownIsBareAndAbsentWhenUnavailable() {
        #expect(WidgetWindowText.countdown(F.window(.weekly, label: "Weekly", percent: 40, resetIn: 3 * 3_600), now: F.now) == "3h")
        #expect(WidgetWindowText.countdown(unavailable, now: F.now) == nil)
        #expect(WidgetWindowText.countdown(nil, now: F.now) == nil)
    }

    @Test func countdownSaysNowOnceTheResetIsReached() {
        let reached = F.window(.weekly, label: "Weekly", percent: 40, resetIn: -60)
        #expect(WidgetWindowText.countdown(reached, now: F.now) == "now")
        #expect(WidgetWindowText.accessibilityValue(reached, providerIsLive: true, now: F.now).hasSuffix("Resets now"))
    }

    // MARK: accessibilityValue

    @Test func aLiveHealthyWindowSpeaksItsValueAndReset() {
        let window = F.window(.weekly, label: "Weekly", percent: 72, resetIn: 3 * 3_600)
        #expect(WidgetWindowText.accessibilityValue(window, providerIsLive: true, now: F.now) == "72 percent left, Resets in 3h")
    }

    @Test func anUnavailableWindowSpeaksNoValueAndNoReset() {
        let spoken = WidgetWindowText.accessibilityValue(unavailable, providerIsLive: true, now: F.now)
        #expect(spoken == "unavailable")
        #expect(!spoken.contains("percent"))
        #expect(!spoken.contains("low"))
    }

    @Test func aStaleWindowIsLastKnownAndNeverLow() {
        let stale = F.window(.weekly, label: "Weekly", percent: 9, freshness: .stale(observedAt: F.now))
        let spoken = WidgetWindowText.accessibilityValue(stale, providerIsLive: true, now: F.now)
        #expect(spoken == "9 percent left, last known, Resets in 3h")
    }

    @Test func aWindowOfANonLiveProviderNeedsAttentionAndIsNeverLow() {
        let critical = F.window(.weekly, label: "Weekly", percent: 9)
        let spoken = WidgetWindowText.accessibilityValue(critical, providerIsLive: false, now: F.now)
        #expect(spoken == "9 percent left, provider needs attention, Resets in 3h")
    }

    @Test func aLiveCriticalWindowIsLow() {
        let critical = F.window(.weekly, label: "Weekly", percent: 9)
        #expect(WidgetWindowText.accessibilityValue(critical, providerIsLive: true, now: F.now) == "9 percent left, low, Resets in 3h")
    }

    @Test func noWindowIsNoReadingYet() {
        #expect(WidgetWindowText.accessibilityValue(nil, providerIsLive: true, now: F.now) == "no reading yet")
    }

    // MARK: providerAccessibility

    @Test func aPendingProviderIsWaiting() {
        let pending = F.recipe(.nestedMeter, .medium, [F.provider("claude", "Claude", freshness: .pending, [])]).providers[0]
        #expect(WidgetWindowText.providerAccessibility(pending, now: F.now) == WidgetStyleCopy.waiting)
    }

    /// R15: by default the windows read in the order the styles draw them — the hero (primary)
    /// first — not the popover's 5-hour-first order.
    @Test func providerWindowsReadHeroFirstByDefault() {
        let claude = F.recipe(.nestedMeter, .medium, [F.claude()]).providers[0]
        let spoken = WidgetWindowText.providerAccessibility(claude, now: F.now)
        let labels = spoken.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")[0] }
        #expect(labels == ["Weekly", "5-hour", "Fable"])
        #expect(claude.windows.first?.widgetRole == .fiveHour)
    }

    @Test func passedWindowsAreSpokenAsGiven() {
        let claude = F.recipe(.nestedMeter, .medium, [F.claude()]).providers[0]
        let ranked = WidgetWindowRanking.ranked(claude.windows)
        let spoken = WidgetWindowText.providerAccessibility(claude, windows: ranked, now: F.now)
        #expect(spoken.hasPrefix("Weekly: 38 percent left"))
    }

    /// WCM5-v: a provider with nothing to read speaks its reason, never an empty value.
    @Test func aStaleProviderWithNoWindowsSpeaksItsReason() {
        let signedOut = F.provider("claude", "Claude", freshness: .stale(message: " Sign in again ", needsAttention: true), [])
        let recipe = F.recipe(.nestedMeter, .large, [signedOut]).providers[0]
        #expect(WidgetWindowText.providerAccessibility(recipe, now: F.now) == "Sign in again")

        let silent = F.provider("claude", "Claude", freshness: .stale(message: "", needsAttention: true), [])
        let silentRecipe = F.recipe(.nestedMeter, .large, [silent]).providers[0]
        #expect(WidgetWindowText.providerAccessibility(silentRecipe, now: F.now) == "provider needs attention")
    }
}
