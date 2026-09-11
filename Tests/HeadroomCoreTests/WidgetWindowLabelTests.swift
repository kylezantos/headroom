import Foundation
import Testing
@testable import HeadroomCore

/// WCW2 / WCW7: one accessor names a window, one accessor captions the small tile. Both are
/// display-only — nothing here touches the envelope's wire format.
struct WidgetWindowLabelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - WCW2 window labels

    @Test func subscriptionKindsGetTheirCanonicalShortNames() {
        #expect(window(kind: .weekly, label: "Weekly limit").widgetDisplayLabel == "Weekly")
        #expect(window(kind: .fiveHour, label: "Current session").widgetDisplayLabel == "5-hour")
    }

    /// A widget column is too narrow for "Weekly (Fable)"; the model name is the part that
    /// distinguishes the row from the weekly row above it.
    @Test func modelSubLimitsShortenToTheModelName() {
        #expect(window(kind: .other("Weekly (Fable)"), label: "Weekly (Fable)").widgetDisplayLabel == "Fable")
        #expect(window(kind: .other("Weekly (Opus)"), label: "Weekly (Opus)").widgetDisplayLabel == "Opus")
        #expect(window(kind: .other("Spark weekly"), label: "Spark weekly").widgetDisplayLabel == "Spark")
    }

    @Test func billingPeriodsKeepTheirOwnNoun() {
        #expect(billingWindow(label: "Monthly", duration: 30 * 24 * 3600).widgetDisplayLabel == "Monthly")
        #expect(billingWindow(label: "Weekly", duration: 7 * 24 * 3600).widgetDisplayLabel == "Weekly")
    }

    @Test func anUnnamedWindowFallsBackToUsage() {
        #expect(WidgetWindowSummary.fallbackLabel == "Usage")
        #expect(window(kind: .other(""), label: "").widgetDisplayLabel == "Usage")
        #expect(billingWindow(label: "", duration: 30 * 24 * 3600).widgetDisplayLabel == "Usage")
    }

    @Test func anUnrecognisedOtherWindowKeepsItsLabel() {
        #expect(window(kind: .other("Sonnet burst"), label: "Sonnet burst").widgetDisplayLabel == "Sonnet burst")
    }

    // MARK: - WCW7 period noun

    @Test func periodNounReadsThePrimaryWindow() {
        #expect(provider(windows: [window(kind: .weekly, label: "Weekly")]).periodNoun == "Weekly")
        #expect(
            provider(windows: [billingWindow(label: "Monthly", duration: 30 * 24 * 3600)]).periodNoun == "Monthly"
        )
    }

    @Test func aFiveHourOnlyProviderHasNoPeriodNoun() {
        #expect(provider(windows: [window(kind: .fiveHour, label: "Current session")]).periodNoun == nil)
    }

    @Test func aProviderWithNoWindowsHasNoPeriodNoun() {
        #expect(provider(windows: []).periodNoun == nil)
    }

    @Test func anUnrecognisedBillingNounIsNotCaptioned() {
        #expect(provider(windows: [billingWindow(label: "Quarterly", duration: 90 * 24 * 3600)]).periodNoun == nil)
    }

    // MARK: - WCW7 small header

    @Test func oneWeeklyProviderCaptionsTheTileWeekly() {
        #expect(envelope(providers: [provider(windows: [window(kind: .weekly, label: "Weekly")])])
            .smallHeaderTitle == "Weekly left")
    }

    @Test func twoWeeklyProvidersStillCaptionTheTileWeekly() {
        let weekly = provider(windows: [window(kind: .weekly, label: "Weekly"), window(kind: .fiveHour, label: "5-hour")])
        #expect(envelope(providers: [weekly, provider(id: "codex", windows: weekly.windows)])
            .smallHeaderTitle == "Weekly left")
    }

    @Test func twoMonthlyBillingProvidersCaptionTheTileMonthly() {
        let monthly = billingWindow(label: "Monthly", duration: 30 * 24 * 3600)
        #expect(
            envelope(providers: [
                provider(id: "grok", windows: [monthly]),
                provider(id: "cursor", windows: [monthly]),
            ]).smallHeaderTitle == "Monthly left"
        )
    }

    /// The caption has to be true of every row under it. A weekly provider beside a monthly
    /// one makes either noun a half-truth, so the tile says the honest thing instead.
    @Test func mixedPeriodsFallBackToUsage() {
        #expect(
            envelope(providers: [
                provider(id: "claude", windows: [window(kind: .weekly, label: "Weekly")]),
                provider(id: "cursor", windows: [billingWindow(label: "Monthly", duration: 30 * 24 * 3600)]),
            ]).smallHeaderTitle == "Usage left"
        )
    }

    @Test func aPendingProviderFallsBackToUsage() {
        var pending = provider(id: "codex", windows: [window(kind: .weekly, label: "Weekly")])
        pending = WidgetProviderSummary(
            id: pending.id,
            displayName: pending.displayName,
            planLabel: nil,
            freshness: .pending,
            windows: pending.windows,
            renewalDate: nil
        )
        #expect(
            envelope(providers: [
                provider(id: "claude", windows: [window(kind: .weekly, label: "Weekly")]),
                pending,
            ]).smallHeaderTitle == "Usage left"
        )
    }

    @Test func aProviderWithNoWindowsFallsBackToUsage() {
        #expect(
            envelope(providers: [
                provider(id: "claude", windows: [window(kind: .weekly, label: "Weekly")]),
                provider(id: "grok", windows: []),
            ]).smallHeaderTitle == "Usage left"
        )
    }

    @Test func anEmptyEnvelopeFallsBackToUsage() {
        #expect(envelope(providers: []).smallHeaderTitle == "Usage left")
    }

    /// Only the providers the widget actually draws can caption it.
    @Test func theHeaderReadsOnlyTheShownProviders() {
        let selected = envelope(
            providers: [
                provider(id: "claude", windows: [window(kind: .weekly, label: "Weekly")]),
                provider(id: "codex", windows: [window(kind: .weekly, label: "Weekly")]),
                provider(id: "cursor", windows: [billingWindow(label: "Monthly", duration: 30 * 24 * 3600)]),
            ],
            selection: ["claude", "codex"]
        )
        #expect(selected.smallHeaderTitle == "Weekly left")
    }

    // MARK: - Fixtures

    private func window(kind: WidgetWindowKind, label: String) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind,
            label: label,
            percentRemaining: 62,
            resetsAt: now.addingTimeInterval(3600),
            resetLabel: "Resets in 1h",
            severity: .healthy
        )
    }

    private func billingWindow(label: String, duration: TimeInterval) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .other(label),
            label: label,
            percentRemaining: 62,
            resetsAt: now.addingTimeInterval(duration),
            resetLabel: "Renews soon",
            severity: .healthy,
            billingPeriodDuration: duration
        )
    }

    private func provider(id: String = "claude", windows: [WidgetWindowSummary]) -> WidgetProviderSummary {
        WidgetProviderSummary(
            id: id,
            displayName: id.capitalized,
            planLabel: nil,
            freshness: .live,
            windows: windows,
            renewalDate: nil
        )
    }

    private func envelope(
        providers: [WidgetProviderSummary],
        selection: [String]? = nil
    ) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: providers,
            widgetProviderSelection: selection
        )
    }
}
