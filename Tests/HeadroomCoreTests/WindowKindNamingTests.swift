import Foundation
import Testing
@testable import HeadroomCore

/// Sep 2026: every surface names a window through `WindowKind.displayName`; Claude's model
/// rows read as the model alone while their stored identity keeps the full source label.
struct WindowKindNamingTests {
    @Test func claudeModelRowReadsAsTheModelAndSpeaksItsPeriod() {
        let fable = WindowKind.other("Weekly (Fable)")
        #expect(fable.displayName == "Fable")
        #expect(fable.spokenName == "Fable weekly")
        #expect(fable.menuBarTerm == "Fable weekly")
        #expect(fable.persistentID == "other:Weekly (Fable)")
    }

    @Test func codexModelRowsKeepTheirPeriodBecauseOneModelCanHaveTwo() {
        // CodexProvider builds "<model> \(kind.shortLabel)": "Weekly" and "5h".
        let weekly = WindowKind.other("GPT-5.3-Codex-Spark Weekly")
        #expect(weekly.displayName == "GPT-5.3-Codex-Spark · Weekly")
        #expect(weekly.spokenName == "GPT-5.3-Codex-Spark weekly")
        #expect(weekly.menuBarTerm == "GPT-5.3-Codex-Spark weekly")
        #expect(WindowKind.other("GPT-5.3-Codex-Spark weekly").displayName == "GPT-5.3-Codex-Spark · Weekly")
        let fiveHour = WindowKind.other("codex-spark 5h")
        #expect(fiveHour.displayName == "codex-spark · 5-hour")
        #expect(fiveHour.spokenName == "codex-spark 5-hour")
    }

    @Test func widgetCompactLabelSharesTheModelRowRule() {
        let summary = { (label: String) in
            WidgetWindowSummary(kind: .other(label), label: label, percentRemaining: 50, resetSchedule: .scheduled(Date(timeIntervalSince1970: 0)), resetLabel: nil, severity: .healthy)
        }
        #expect(summary("Weekly (Fable)").compactLabel == WindowKind.other("Weekly (Fable)").displayName)
        #expect(summary("Weekly ()").compactLabel == "Weekly ()")
    }

    @Test func plainKindsAndBillingPoolsAreUnchanged() {
        #expect(WindowKind.fiveHour.displayName == "5-hour")
        #expect(WindowKind.weekly.displayName == "Weekly")
        #expect(WindowKind.billingPeriod(label: "Cursor Models", duration: 1).displayName == "Cursor Models")
        #expect(WindowKind.other("Weekly ()").displayName == "Weekly ()")
        #expect(WindowKind.fiveHour.compactName == "5h")
        #expect(WindowKind.other("Weekly (Fable)").compactName == "Fable")
        #expect(WindowKind.other("Included").spokenName == "Included")
        #expect(WindowKind.billingPeriod(label: "Monthly", duration: 1).menuBarTerm == "monthly")
    }

    @Test func persistentIDsRoundTripAndIgnoreBillingDuration() {
        let kinds: [WindowKind] = [.fiveHour, .weekly, .other("Weekly (Fable)"), .billingPeriod(label: "Other Models", duration: 31 * 86_400)]
        for kind in kinds {
            #expect(WindowKind(persistentID: kind.persistentID)?.persistentID == kind.persistentID)
        }
        #expect(MenuBarWindowChoice.window(id: "billing:Other Models")
            .matches(.billingPeriod(label: "Other Models", duration: 28 * 86_400)))
        #expect(WindowKind(persistentID: "nonsense") == nil)
    }

    @Test func choiceRawValuesAndTitles() {
        #expect(MenuBarWindowChoice(rawValue: "weekly") == .weekly)
        #expect(MenuBarWindowChoice(rawValue: "fiveHour") == .fiveHour)
        #expect(MenuBarWindowChoice(rawValue: "closest") == .closest)
        #expect(MenuBarWindowChoice(rawValue: "") == nil)
        // Malformed stored values fall back to the default rather than listing a nameless choice.
        #expect(MenuBarWindowChoice(rawValue: "nonsense") == nil)
        #expect(MenuBarWindowChoice(rawValue: "billing:") == nil)
        #expect(MenuBarWindowChoice(rawValue: "other:") == nil)
        #expect(MenuBarWindowChoice.window(id: "other:Weekly (Fable)").title == "Fable")
        #expect(MenuBarWindowChoice.closest.title == "Closest to limit")
        #expect(MenuBarWindowChoice.closest.menuBarTerm == "closest to limit")
    }
}
