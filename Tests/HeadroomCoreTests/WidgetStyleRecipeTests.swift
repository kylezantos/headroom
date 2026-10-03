import Foundation
import Testing
@testable import HeadroomCore

/// Fixture builders for the widget-style recipe suites (2026-10-02 widget-styles plan, U2).
enum StyleFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let week: TimeInterval = 7 * 24 * 3_600
    static let month: TimeInterval = 30 * 24 * 3_600

    static func window(
        _ kind: WidgetWindowKind,
        label: String,
        percent: Double,
        severity: WidgetUsageSeverity? = nil,
        freshness: WidgetWindowFreshness = .live,
        resetIn: TimeInterval = 3 * 3_600,
        billingPeriod: TimeInterval? = nil
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind,
            label: label,
            percentRemaining: percent,
            resetSchedule: .scheduled(now.addingTimeInterval(resetIn)),
            resetLabel: nil,
            severity: severity ?? WidgetUsageSeverity(UsageSeverity(percentRemaining: percent)),
            freshness: freshness,
            billingPeriodDuration: billingPeriod
        )
    }

    static func provider(
        _ id: String,
        _ name: String,
        plan: String? = nil,
        freshness: WidgetProviderFreshness = .live,
        _ windows: [WidgetWindowSummary]
    ) -> WidgetProviderSummary {
        WidgetProviderSummary(id: id, displayName: name, planLabel: plan, freshness: freshness, windows: windows, renewalDate: nil)
    }

    static func claude(fiveHour: Double = 72, weekly: Double = 38, fable: Double = 61) -> WidgetProviderSummary {
        provider("claude", "Claude", plan: "Max", [
            window(.fiveHour, label: "5h", percent: fiveHour),
            window(.weekly, label: "Weekly", percent: weekly, resetIn: 4 * 86_400),
            window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: fable, resetIn: 4 * 86_400),
        ])
    }

    static func codex(fiveHour: Double = 41, weekly: Double = 64, spark: Double? = nil) -> WidgetProviderSummary {
        var windows = [
            window(.fiveHour, label: "5h", percent: fiveHour),
            window(.weekly, label: "Weekly", percent: weekly, resetIn: 3 * 86_400),
        ]
        if let spark {
            windows.append(window(.other("Spark weekly"), label: "Spark weekly", percent: spark, resetIn: 3 * 86_400))
        }
        return provider("codex", "Codex", plan: "Pro Lite", windows)
    }

    static func grok(_ weekly: Double = 56) -> WidgetProviderSummary {
        provider("grok", "Grok", plan: "SuperGrok", [
            window(.other("Weekly"), label: "Weekly", percent: weekly, resetIn: 3 * 86_400, billingPeriod: week),
        ])
    }

    static func cursor(
        cursorModels: Double = 69,
        otherModels: Double = 37,
        otherFreshness: WidgetWindowFreshness = .live
    ) -> WidgetProviderSummary {
        provider("cursor", "Cursor", plan: "Pro+", [
            window(.other("Cursor Models"), label: "Cursor Models", percent: cursorModels, resetIn: 2 * 86_400, billingPeriod: month),
            window(.other("Other Models"), label: "Other Models", percent: otherModels, freshness: otherFreshness, resetIn: 2 * 86_400, billingPeriod: month),
        ])
    }

    static func envelope(_ providers: [WidgetProviderSummary], spend: Bool = false) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: providers,
            apiSpendProviders: spend
                ? [WidgetAPISpendSummary(id: "claude", displayName: "Anthropic API", amount: 142.67, currency: "usd", periodLabel: "Current month", capturedAt: now, freshness: .live)]
                : []
        )
    }

    static func recipe(_ style: WidgetLayoutStyle, _ family: WidgetFamily, _ providers: [WidgetProviderSummary], spend: Bool = false) -> WidgetStyleRecipe {
        WidgetStyleRecipe(style: style, family: family, envelope: envelope(providers, spend: spend))
    }
}

struct WidgetStyleRecipeTests {
    typealias F = StyleFixture

    // MARK: Provider selection (R6)

    @Test func smallVesselHeroAndLiquidLevelShowOneProvider() {
        for style in [WidgetLayoutStyle.vesselHero, .liquidLevel] {
            let recipe = F.recipe(style, .small, [F.claude(), F.codex()])
            #expect(recipe.providers.map(\.id) == ["claude"])
        }
    }

    @Test func otherSmallStylesShowBothProviders() {
        for style in [WidgetLayoutStyle.nestedMeter, .tightestFirst] {
            #expect(F.recipe(style, .small, [F.claude(), F.codex()]).providers.map(\.id) == ["claude", "codex"])
        }
    }

    @Test func oneProviderSmallStylesSkipAFirstProviderWithNoValueYet() {
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        let recipe = F.recipe(.vesselHero, .small, [pending, F.codex()])
        #expect(recipe.providers.map(\.id) == ["codex"])
    }

    @Test func oneProviderSmallStylesKeepTheFirstWhenNeitherHasAValue() {
        let a = F.provider("claude", "Claude", freshness: .pending, [])
        let b = F.provider("codex", "Codex", freshness: .pending, [])
        #expect(F.recipe(.liquidLevel, .small, [a, b]).providers.map(\.id) == ["claude"])
    }

    @Test func mediumAndLargeShowBothProvidersForEveryStyle() {
        for style in WidgetLayoutStyle.allCases {
            for family in [WidgetFamily.medium, .large] {
                #expect(F.recipe(style, family, [F.grok(), F.cursor()]).providers.map(\.id) == ["grok", "cursor"])
            }
        }
    }

    // MARK: Primary window and structure (R2)

    @Test func claudePrimaryIsWeeklyEvenWhenFiveHourIsLower() {
        let recipe = F.recipe(.nestedMeter, .medium, [F.claude(fiveHour: 10, weekly: 38)])
        #expect(recipe.providers[0].primary?.kind == .weekly)
        #expect(recipe.providers[0].hasSiblingPools == false)
    }

    @Test func nestedMeterClaudeHasWeeklyParentWithFiveHourAndFableRails() {
        let p = F.recipe(.nestedMeter, .large, [F.claude()]).providers[0]
        #expect(p.primary?.kind == .weekly)
        #expect(p.secondary.map(\.widgetDisplayLabel) == ["5-hour", "Fable"])
    }

    @Test func cursorPrimaryIsTheTightestPoolAndPoolsAreSiblings() {
        let p = F.recipe(.nestedMeter, .medium, [F.cursor(cursorModels: 69, otherModels: 37)]).providers[0]
        #expect(p.primary?.label == "Other Models")
        #expect(p.hasSiblingPools)
        #expect(p.secondary.map(\.label) == ["Cursor Models"])
    }

    @Test func cursorPrimarySkipsAnUnavailablePool() {
        let cursor = F.cursor(cursorModels: 69, otherModels: 37, otherFreshness: .unavailable(since: F.now))
        let p = F.recipe(.vesselHero, .medium, [cursor]).providers[0]
        #expect(p.primary?.label == "Cursor Models")
    }

    @Test func grokPrimaryIsItsSinglePoolWithNoSecondaryRows() {
        let p = F.recipe(.nestedMeter, .medium, [F.grok()]).providers[0]
        #expect(p.primary?.label == "Weekly")
        #expect(p.secondary.isEmpty)
        #expect(p.hasSiblingPools == false)
    }

    @Test func windowsFollowThePopoverOrder() {
        let p = F.recipe(.nestedMeter, .large, [F.codex(spark: 50)]).providers[0]
        #expect(p.windows.map(\.widgetDisplayLabel) == ["5-hour", "Weekly", "Spark"])
    }

    // MARK: Tightest First (R3)

    @Test func tightestFirstSmallAndMediumHeadlineEachProvidersOwnLowestWindow() {
        for family in [WidgetFamily.small, .medium] {
            let recipe = F.recipe(.tightestFirst, family, [F.claude(fiveHour: 72, weekly: 38, fable: 23), F.codex(fiveHour: 41, weekly: 64)])
            #expect(recipe.providers.map { $0.tightest?.widgetDisplayLabel } == ["Fable", "5-hour"])
        }
    }

    @Test func tightestFirstLargeHeadlinesTheLowestAcrossProviders() {
        let recipe = F.recipe(.tightestFirst, .large, [F.claude(fiveHour: 72, weekly: 38, fable: 61), F.codex(fiveHour: 41, weekly: 64)])
        #expect(recipe.rankedRows.first?.providerID == "claude")
        #expect(recipe.rankedRows.first?.window.kind == .weekly)
        #expect(recipe.rankedRows.map { Int($0.window.percentRemaining) } == [38, 41, 61, 64, 72])
    }

    @Test func tightestFirstLargeIncludesSparkInItsRanking() {
        let recipe = F.recipe(.tightestFirst, .large, [F.claude(), F.codex(spark: 12)])
        #expect(recipe.rankedRows.first?.window.widgetDisplayLabel == "Spark")
    }

    @Test func tightestFirstLetsAStaleLowerLimitHeadline() {
        let claude = F.provider("claude", "Claude", [
            F.window(.weekly, label: "Weekly", percent: 40),
            F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 5, freshness: .stale(observedAt: F.now)),
        ])
        let recipe = F.recipe(.tightestFirst, .large, [claude])
        #expect(recipe.rankedRows.first?.window.widgetDisplayLabel == "Fable")
        #expect(F.recipe(.tightestFirst, .small, [claude]).providers[0].tightest?.widgetDisplayLabel == "Fable")
    }

    @Test func tightestFirstLargeSheddingDropsTheLoosestRowsFirst() {
        let recipe = F.recipe(.tightestFirst, .large, [F.claude(), F.codex()])
        let ladder = recipe.rankedRowsLadder
        #expect(ladder.first?.count == 5)
        #expect(ladder.last?.count == 1)
        #expect(ladder[1].map { Int($0.window.percentRemaining) } == [38, 41, 61, 64])
    }

    // MARK: Shedding for the other styles (KTD10)

    @Test func secondaryLadderDropsSparkThenModelRowsButKeepsSubscriptionWindows() {
        let claude = F.claude()
        let codex = F.codex(spark: 50)
        let recipe = F.recipe(.nestedMeter, .large, [claude, codex])
        #expect(recipe.providers[0].secondaryLadder.map { $0.map(\.widgetDisplayLabel) } == [["5-hour", "Fable"], ["5-hour"]])
        #expect(recipe.providers[1].secondaryLadder.map { $0.map(\.widgetDisplayLabel) } == [["5-hour", "Spark"], ["5-hour"]])
    }

    // MARK: Liquid Level wash (KTD9)

    @Test func liquidLevelEmitsOneWashSegmentPerShownProvider() {
        let recipe = F.recipe(.liquidLevel, .medium, [F.claude(weekly: 38), F.codex(weekly: 64)])
        #expect(recipe.washSegments.map(\.providerID) == ["claude", "codex"])
        #expect(recipe.washSegments.map(\.fraction) == [0.38, 0.64])
        #expect(recipe.showsWashDivider)
    }

    @Test func liquidLevelWithOneProviderHasNoDivider() {
        let recipe = F.recipe(.liquidLevel, .large, [F.grok(56)])
        #expect(recipe.washSegments.map(\.fraction) == [0.56])
        #expect(recipe.showsWashDivider == false)
    }

    @Test func liquidLevelSegmentHasNoWashWhenThePrimaryHasNoValue() {
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        let recipe = F.recipe(.liquidLevel, .medium, [pending, F.codex()])
        #expect(recipe.washSegments[0].fraction == nil)
    }

    @Test func otherStylesHaveNoWash() {
        for style in [WidgetLayoutStyle.nestedMeter, .vesselHero, .tightestFirst] {
            #expect(F.recipe(style, .medium, [F.claude(), F.codex()]).washSegments.isEmpty)
        }
    }

    // MARK: Spend and footer (R14)

    @Test func spendAndFooterShowOnLargeOnly() {
        for style in WidgetLayoutStyle.allCases {
            #expect(F.recipe(style, .large, [F.claude()], spend: true).showsSpend)
            #expect(F.recipe(style, .large, [F.claude()], spend: false).showsSpend == false)
            #expect(F.recipe(style, .large, [F.claude()]).showsFooter)
            for family in [WidgetFamily.small, .medium] {
                #expect(F.recipe(style, family, [F.claude()], spend: true).showsSpend == false)
                #expect(F.recipe(style, family, [F.claude()]).showsFooter == false)
            }
        }
    }

    // MARK: Unavailable and pending (R11)

    @Test func aProviderWhoseOnlyWindowIsUnavailableHasNoDisplayValue() {
        let grok = F.provider("grok", "Grok", [
            F.window(.other("Weekly"), label: "Weekly", percent: 56, freshness: .unavailable(since: F.now), billingPeriod: F.week),
        ])
        let p = F.recipe(.nestedMeter, .medium, [grok]).providers[0]
        #expect(p.primary?.displayPercentRemaining == nil)
        #expect(p.isWaiting == false)
    }

    @Test func leftCaptionsNameThePeriodOrTheWindow() {
        let claude = F.recipe(.vesselHero, .medium, [F.claude()]).providers[0]
        #expect(WidgetStyleCopy.leftCaption(for: claude.primary!, in: claude) == "weekly left")
        let grok = F.recipe(.vesselHero, .medium, [F.grok()]).providers[0]
        #expect(WidgetStyleCopy.leftCaption(for: grok.primary!, in: grok) == "weekly left")
        let cursor = F.recipe(.vesselHero, .medium, [F.cursor()]).providers[0]
        #expect(WidgetStyleCopy.leftCaption(for: cursor.primary!, in: cursor) == "Other Models left")
        let fable = claude.windows.first { $0.widgetRole == .model }!
        #expect(WidgetStyleCopy.leftCaption(for: fable, in: claude) == "Fable left")
        let monthly = F.provider("x", "X", [F.window(.other("Monthly"), label: "Monthly", percent: 50, billingPeriod: F.month)])
        let m = F.recipe(.vesselHero, .medium, [monthly]).providers[0]
        #expect(WidgetStyleCopy.leftCaption(for: m.primary!, in: m) == "monthly left")
    }

    @Test func everyStyleFixtureResolvesWithASelection() {
        for name in DemoScreenshotData.styleFixtureNames {
            let envelope = DemoScreenshotData.styleFixture(name, now: F.now)
            #expect(envelope != nil, "\(name)")
            #expect(envelope?.widgetProviderSelection?.isEmpty == false, "\(name)")
        }
        #expect(DemoScreenshotData.styleFixture("nope", now: F.now) == nil)
    }

    @Test func aPendingProviderIsWaitingWithNoPrimary() {
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        let p = F.recipe(.nestedMeter, .medium, [pending]).providers[0]
        #expect(p.isWaiting)
        #expect(p.primary == nil)
    }
}

struct WidgetStyleSimplificationTests {
    typealias F = StyleFixture

    @Test func companionIsTheFiveHourWindowElseTheNextWindow() {
        #expect(F.recipe(.vesselHero, .medium, [F.claude()]).providers[0].companion?.kind == .fiveHour)
        #expect(F.recipe(.vesselHero, .medium, [F.cursor()]).providers[0].companion?.label == "Cursor Models")
        #expect(F.recipe(.vesselHero, .medium, [F.grok()]).providers[0].companion == nil)
    }

    @Test func demotingKeepsEveryFieldButFreshness() {
        let live = F.window(.weekly, label: "Weekly", percent: 40)
        let demoted = live.demotedToStale()
        #expect(demoted.freshness.isStale)
        #expect(demoted.percentRemaining == live.percentRemaining)
        #expect(demoted.resetSchedule == live.resetSchedule)
        #expect(demoted.severity == live.severity)
        let unavailable = F.window(.weekly, label: "Weekly", percent: 40, freshness: .unavailable(since: F.now))
        #expect(unavailable.demotedToStale() == unavailable)
    }

    @Test func aStaleProvidersWashTakesTheStaleWindow() {
        let codex = F.provider("codex", "Codex", freshness: .stale(message: "x", needsAttention: false), [
            F.window(.weekly, label: "Weekly", percent: 64),
        ])
        let recipe = F.recipe(.liquidLevel, .medium, [F.claude(), codex])
        #expect(recipe.washSegments[0].window?.freshness.isLive == true)
        #expect(recipe.washSegments[1].window?.freshness.isStale == true)
    }

    @Test func resetsInSaysNowAtTheReset() {
        #expect(WidgetStyleCopy.resetsIn("3h 15m") == "Resets in 3h 15m")
        #expect(WidgetStyleCopy.resetsIn("now") == "Resets now")
    }
}

struct WidgetStyleRecipeReviewTests {
    typealias F = StyleFixture

    private static let signedOut = F.provider(
        "claude", "Claude", freshness: .stale(message: "  Sign in with the official Claude CLI \n", needsAttention: true), []
    )

    // MARK: Tightest First large keeps windowless providers (R11)

    @Test func tightestFirstLargeKeepsAPendingProviderBesideRankedRows() {
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        let recipe = F.recipe(.tightestFirst, .large, [pending, F.codex()])
        #expect(recipe.providersWithoutRows.map(\.id) == ["claude"])
        #expect(recipe.providersWithoutRows.first?.isWaiting == true)
        #expect(recipe.rankedRows.map(\.providerID) == ["codex", "codex"])
    }

    @Test func tightestFirstLargeKeepsAStaleProviderWithNoWindows() {
        let recipe = F.recipe(.tightestFirst, .large, [Self.signedOut, F.codex()])
        #expect(recipe.providersWithoutRows.map(\.id) == ["claude"])
        #expect(recipe.providersWithoutRows.first?.isWaiting == false)
        #expect(recipe.rankedRows.map(\.providerID) == ["codex", "codex"])
    }

    @Test func providersWithoutRowsFollowProviderOrder() {
        // A widget shows at most two providers; with neither ranked, both stay, in order.
        let pending = F.provider("codex", "Codex", freshness: .pending, [])
        let recipe = F.recipe(.tightestFirst, .large, [Self.signedOut, pending])
        #expect(recipe.providersWithoutRows.map(\.id) == ["claude", "codex"])
        #expect(recipe.rankedRows.isEmpty)
    }

    @Test func providersWithoutRowsIsEmptyOutsideTightestFirstLarge() {
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        #expect(F.recipe(.tightestFirst, .large, [F.claude(), F.codex()]).providersWithoutRows.isEmpty)
        for style in WidgetLayoutStyle.allCases {
            for family in WidgetFamily.allCases where !(style == .tightestFirst && family == .large) {
                #expect(F.recipe(style, family, [pending, F.codex()]).providersWithoutRows.isEmpty, "\(style)/\(family)")
            }
        }
    }

    // MARK: Ladder rungs (KTD10)

    @Test func ladderRungCountIsTheLongestProviderLadder() {
        // Claude sheds Fable (2 rungs); Grok has nothing to shed (1 rung).
        let recipe = F.recipe(.nestedMeter, .large, [F.claude(), F.grok()])
        #expect(recipe.providers.map(\.secondaryLadder.count) == [2, 1])
        #expect(recipe.ladderRungCount == 2)
        #expect(F.recipe(.nestedMeter, .large, []).ladderRungCount == 1)
    }

    @Test func secondaryAtRungClampsAShorterLadderToItsLastRung() {
        let both = F.provider("x", "X", [
            F.window(.fiveHour, label: "5h", percent: 70),
            F.window(.weekly, label: "Weekly", percent: 50),
            F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 60),
            F.window(.other("Spark weekly"), label: "Spark weekly", percent: 80),
        ])
        let recipe = F.recipe(.nestedMeter, .large, [both, F.grok()])
        #expect(recipe.providers.map(\.secondaryLadder.count) == [3, 1])
        #expect(recipe.ladderRungCount == 3)
        let labels = { (p: WidgetStyleProviderRecipe, rung: Int) in p.secondary(atRung: rung).map(\.widgetDisplayLabel) }
        let x = recipe.providers[0], grok = recipe.providers[1]
        let claude = F.recipe(.nestedMeter, .large, [F.claude()]).providers[0]
        #expect(labels(x, 0) == ["5-hour", "Fable", "Spark"])
        #expect(labels(x, 1) == ["5-hour", "Fable"])
        #expect(labels(x, 2) == ["5-hour"])
        #expect(labels(claude, 0) == ["5-hour", "Fable"])
        #expect(labels(claude, 1) == ["5-hour"])
        #expect(labels(claude, 2) == ["5-hour"])
        for rung in 0..<recipe.ladderRungCount {
            #expect(grok.secondary(atRung: rung).isEmpty)
        }
        #expect(labels(claude, 99) == ["5-hour"])
        #expect(labels(claude, -1) == ["5-hour", "Fable"])
    }

    // MARK: Stale reason (WCM5-v)

    @Test func staleMessageIsTheTrimmedReasonOnlyWhenStale() {
        let stale = F.recipe(.nestedMeter, .large, [Self.signedOut]).providers[0]
        #expect(stale.staleMessage == "Sign in with the official Claude CLI")
        #expect(F.recipe(.nestedMeter, .large, [F.claude()]).providers[0].staleMessage == nil)
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        #expect(F.recipe(.nestedMeter, .large, [pending]).providers[0].staleMessage == nil)
        let blank = F.provider("claude", "Claude", freshness: .stale(message: "  ", needsAttention: false), [])
        #expect(F.recipe(.nestedMeter, .large, [blank]).providers[0].staleMessage == nil)
    }

    @Test func signedOutFixturePosesAWindowlessProviderThatNeedsAttention() throws {
        #expect(DemoScreenshotData.styleFixtureNames.contains("signedOut"))
        let envelope = try #require(DemoScreenshotData.styleFixture("signedOut", now: F.now))
        let providers = envelope.widgetProviders
        #expect(providers.map(\.id) == ["claude", "codex"])
        #expect(providers[0].windows.isEmpty)
        #expect(providers[0].freshness.needsAttention)
        #expect(providers[1].freshness == .live)
        let recipe = WidgetStyleRecipe(style: .tightestFirst, family: .large, envelope: envelope)
        #expect(recipe.providersWithoutRows.map(\.id) == ["claude"])
        #expect(recipe.providersWithoutRows.first?.staleMessage?.isEmpty == false)
    }
}
