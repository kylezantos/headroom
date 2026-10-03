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





    @Test func namedBillingPoolsChooseTheLowestRemainingValue() {
        let cursorModels = billingWindow(label: "Cursor Models", percentRemaining: 69)
        let otherModels = billingWindow(label: "Other Models", percentRemaining: 37)
        let cursor = provider(id: "cursor", windows: [cursorModels, otherModels])

        #expect(cursor.primarySubscriptionWindow?.label == "Other Models")
        #expect(cursor.displaySubscriptionWindows.map(\.label) == ["Cursor Models", "Other Models"])
    }

    @Test func equalBillingPoolsChooseTheFirstSourceRow() {
        let cursorModels = billingWindow(label: "Cursor Models", percentRemaining: 42)
        let otherModels = billingWindow(label: "Other Models", percentRemaining: 42)

        #expect(provider(id: "cursor", windows: [cursorModels, otherModels])
            .primarySubscriptionWindow?.label == "Cursor Models")
    }

    @Test func weeklyStillWinsBeforeTighterBillingPools() {
        let weekly = window(kind: .weekly, label: "Weekly")
        let tighterBilling = billingWindow(label: "Other Models", percentRemaining: 3)

        #expect(provider(windows: [tighterBilling, weekly]).primarySubscriptionWindow?.kind == .weekly)
    }

    // MARK: - WCW7 small header









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
        billingWindow(label: label, percentRemaining: 62, duration: duration)
    }

    private func billingWindow(
        label: String,
        percentRemaining: Double,
        duration: TimeInterval = 30 * 24 * 3600
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .other(label),
            label: label,
            percentRemaining: percentRemaining,
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
