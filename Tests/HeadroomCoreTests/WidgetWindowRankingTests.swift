import Foundation
import Testing
@testable import HeadroomCore

struct WidgetWindowRankingTests {
    typealias F = StyleFixture

    @Test func ranksByDisplayedValueWithStaleAlongsideLive() {
        let live40 = F.window(.weekly, label: "Weekly", percent: 40)
        let stale5 = F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 5, freshness: .stale(observedAt: F.now))
        #expect(WidgetWindowRanking.ranked([live40, stale5]).map(\.percentRemaining) == [5, 40])
    }

    @Test func unavailableWindowsRankLast() {
        let unavailable = F.window(.fiveHour, label: "5h", percent: 1, freshness: .unavailable(since: F.now))
        let live = F.window(.weekly, label: "Weekly", percent: 90)
        #expect(WidgetWindowRanking.ranked([unavailable, live]).map(\.kind) == [.weekly, .fiveHour])
    }

    @Test func equalValuesKeepSourceOrder() {
        let a = F.window(.fiveHour, label: "5h", percent: 50)
        let b = F.window(.weekly, label: "Weekly", percent: 50)
        #expect(WidgetWindowRanking.ranked([a, b]).map(\.kind) == [.fiveHour, .weekly])
        #expect(WidgetWindowRanking.ranked([b, a]).map(\.kind) == [.weekly, .fiveHour])
    }

    @Test func displayOrderIsFiveHourThenPeriodThenModelRows() {
        let fable = F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 61)
        let weekly = F.window(.weekly, label: "Weekly", percent: 38)
        let fiveHour = F.window(.fiveHour, label: "5h", percent: 72)
        #expect(WidgetWindowRanking.displayOrder([fable, weekly, fiveHour]).map(\.widgetDisplayLabel) == ["5-hour", "Weekly", "Fable"])
    }

    @Test func rolesNameEachKindOfWindow() {
        #expect(F.window(.fiveHour, label: "5h", percent: 1).widgetRole == .fiveHour)
        #expect(F.window(.weekly, label: "Weekly", percent: 1).widgetRole == .weekly)
        #expect(F.window(.other("Monthly"), label: "Monthly", percent: 1, billingPeriod: F.month).widgetRole == .pool)
        #expect(F.window(.other("Spark weekly"), label: "Spark weekly", percent: 1).widgetRole == .spark)
        #expect(F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 1).widgetRole == .model)
    }

    @Test func primarySubscriptionWindowSkipsAnUnavailablePool() {
        let cursor = F.cursor(cursorModels: 69, otherModels: 37, otherFreshness: .unavailable(since: F.now))
        #expect(cursor.primarySubscriptionWindow?.label == "Cursor Models")
    }
}
