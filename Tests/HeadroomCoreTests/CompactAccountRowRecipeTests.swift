import Foundation
import Testing
@testable import HeadroomCore

struct CompactAccountRowRecipeTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60

    private func window(
        _ kind: WindowKind,
        used: Double,
        resetIn: TimeInterval,
        freshness: UsageWindowFreshness = .live
    ) -> UsageWindow {
        UsageWindow(kind: kind, utilization: used, resetsAt: now.addingTimeInterval(resetIn), freshness: freshness)
    }

    private func snapshot(
        _ provider: ProviderID,
        _ windows: [UsageWindow],
        freshness: Freshness = .live
    ) -> UsageSnapshot {
        UsageSnapshot(providerID: provider, windows: windows, planLabel: nil, capturedAt: now, freshness: freshness)
    }

    private func recipe(
        _ snapshot: UsageSnapshot,
        style: MeterStyle = .default,
        mode: UsagePercentageMode = .remaining,
        requiresStandardSection: Bool = false,
        showsCodexSparkCounters: Bool = true
    ) -> CompactAccountRowRecipe {
        CompactAccountRowRecipe(
            snapshot: snapshot,
            meterStyle: style,
            percentageMode: mode,
            now: now,
            requiresStandardSection: requiresStandardSection,
            showsCodexSparkCounters: showsCodexSparkCounters
        )
    }

    // MARK: - Window choice (KTD7, R11, R12)

    @Test func claudeShowsFiveHourThenWeeklyAndCountsTheModelRow() {
        // Provider order puts weekly first; the row still leads with 5-hour.
        let result = recipe(snapshot(.claude, [
            window(.weekly, used: 60, resetIn: 3 * day),
            window(.fiveHour, used: 28, resetIn: 2 * hour),
            window(.other("Weekly (Fable)"), used: 10, resetIn: 3 * day),
        ]))
        #expect(result.content == .meters)
        #expect(result.shownWindows.map(\.window.kind) == [.fiveHour, .weekly])
        #expect(result.shownWindows.map(\.shortLabel) == ["5h", "wk"])
        #expect(result.overflowCount == 1)
        #expect(!result.fallsBackToStandard)
    }

    @Test func codexProliteWeeklyOnlyShowsOneMeter() {
        let result = recipe(snapshot(.codex, [window(.weekly, used: 40, resetIn: 4 * day)]))
        #expect(result.content == .meters)
        #expect(result.shownWindows.map(\.window.kind) == [.weekly])
        #expect(result.shownWindows.map(\.shortLabel) == ["wk"])
        #expect(result.overflowCount == 0)
    }

    @Test func codexShowsFiveHourAndWeeklyLabels() {
        let result = recipe(snapshot(.codex, [
            window(.fiveHour, used: 5, resetIn: 3 * hour),
            window(.weekly, used: 40, resetIn: 4 * day),
        ]))
        #expect(result.shownWindows.map(\.shortLabel) == ["5h", "wk"])
        #expect(result.overflowCount == 0)
    }

    @Test func cursorShowsBothNamedPools() {
        let result = recipe(snapshot(.cursor, [
            window(.billingPeriod(label: "Cursor Models", duration: 30 * day), used: 1, resetIn: 12 * day),
            window(.billingPeriod(label: "Other Models", duration: 30 * day), used: 3, resetIn: 12 * day),
        ]))
        #expect(result.content == .meters)
        #expect(result.shownWindows.map(\.shortLabel) == ["Models", "Other"])
        #expect(result.overflowCount == 0)
    }

    @Test func cursorIncludedOnlyShowsOneMeter() {
        let result = recipe(snapshot(.cursor, [
            window(.billingPeriod(label: "Included", duration: 30 * day), used: 37, resetIn: 12 * day),
        ]))
        #expect(result.shownWindows.map(\.shortLabel) == ["Included"])
        #expect(result.overflowCount == 0)
    }

    @Test func grokBillingPeriodShowsOneMeterWithItsPeriodShortName() {
        let monthly = recipe(snapshot(.grok, [
            window(.billingPeriod(label: "Monthly", duration: 30 * day), used: 20, resetIn: 9 * day),
        ]))
        #expect(monthly.shownWindows.map(\.shortLabel) == ["mo"])
        #expect(monthly.overflowCount == 0)

        let weekly = recipe(snapshot(.grok, [
            window(.billingPeriod(label: "Weekly", duration: 7 * day), used: 20, resetIn: 2 * day),
        ]))
        #expect(weekly.shownWindows.map(\.shortLabel) == ["wk"])

        // An undeclared duration stays the classifier's own honest label.
        let odd = recipe(snapshot(.grok, [window(.other("14d"), used: 20, resetIn: 2 * day)]))
        #expect(odd.shownWindows.map(\.shortLabel) == ["14d"])
    }

    /// Antigravity reports two pools with a 5-hour and a weekly row each. Compact's two
    /// meters show one row per pool, each pool's tighter one, in the order the provider
    /// emits them; the other two rows are counted and stay in the tooltip.
    @Test func antigravityShowsOneMeterPerPoolAndKeepsEveryRowInTheTooltip() {
        let reset = now.addingTimeInterval(2 * hour)
        let windows = AntigravityProvider.windows(for: [
            AntigravityBucket(pool: .gemini, window: .fiveHour, remainingFraction: 0.80, resetsAt: reset),
            AntigravityBucket(pool: .gemini, window: .weekly, remainingFraction: 0.60, resetsAt: reset),
            AntigravityBucket(pool: .claudeAndGPT, window: .fiveHour, remainingFraction: 0.10, resetsAt: reset),
            AntigravityBucket(pool: .claudeAndGPT, window: .weekly, remainingFraction: 0.50, resetsAt: reset),
        ])
        let result = recipe(snapshot(.antigravity, windows))
        #expect(result.content == .meters)
        #expect(result.shownWindows.map(\.window.kind) == [.other("Gemini weekly"), .other("Claude & GPT 5h")])
        #expect(result.shownWindows.map(\.shortLabel) == ["Gemini wk", "Other 5h"])
        #expect(result.overflowCount == 2)
        let tooltip = result.tooltip.split(separator: "\n").map(String.init)
        #expect(tooltip.count == 4)
        for name in ["Gemini weekly", "Gemini 5-hour", "Claude & GPT 5-hour", "Claude & GPT weekly"] {
            #expect(tooltip.contains { $0.hasPrefix("\(name):") }, "tooltip lacks \(name)")
        }

        // With one pool missing, the other pool's tighter row is the one meter.
        let geminiOnly = recipe(snapshot(.antigravity, Array(windows.prefix(2))))
        #expect(geminiOnly.shownWindows.map(\.window.kind) == [.other("Gemini weekly")])
        #expect(geminiOnly.overflowCount == 1)
    }

    /// The Compact header names each Antigravity column by pool and period, short enough for
    /// the 84pt cell. "Other" is the Claude & GPT pool, as Cursor's "Other" is its other pool.
    @Test func antigravityShortLabelsFitTheCompactColumn() {
        #expect(CompactAccountRowRecipe.shortLabel(for: .other("Gemini 5h")) == "Gemini 5h")
        #expect(CompactAccountRowRecipe.shortLabel(for: .other("Gemini weekly")) == "Gemini wk")
        #expect(CompactAccountRowRecipe.shortLabel(for: .other("Claude & GPT 5h")) == "Other 5h")
        #expect(CompactAccountRowRecipe.shortLabel(for: .other("Claude & GPT weekly")) == "Other wk")
    }

    @Test func unknownWindowsFallBackToSlotOrder() {
        let result = recipe(snapshot(.grok, [
            window(.other("Beta"), used: 10, resetIn: hour),
            window(.other("Alpha"), used: 20, resetIn: hour),
            window(.other("Gamma"), used: 30, resetIn: hour),
        ]))
        #expect(result.shownWindows.map(\.window.kind) == [.other("Beta"), .other("Alpha")])
        #expect(result.shownWindows.map(\.shortLabel) == ["Beta", "Alpha"])
        #expect(result.overflowCount == 1)
    }

    @Test func sparkCountersFollowTheStandardVisibilityRule() {
        let windows = [
            window(.fiveHour, used: 5, resetIn: 3 * hour),
            window(.weekly, used: 40, resetIn: 4 * day),
            window(.other("GPT-5.3-Codex-Spark Weekly"), used: 2, resetIn: 4 * day),
        ]
        let hidden = recipe(snapshot(.codex, windows), showsCodexSparkCounters: false)
        #expect(hidden.overflowCount == 0)
        #expect(!hidden.tooltip.localizedCaseInsensitiveContains("spark"))
        #expect(!hidden.accessibilityValue.localizedCaseInsensitiveContains("spark"))

        let shown = recipe(snapshot(.codex, windows), showsCodexSparkCounters: true)
        #expect(shown.overflowCount == 1)
        #expect(shown.tooltip.localizedCaseInsensitiveContains("spark"))

        // The rule is Codex-only, exactly like `UsageStore.filterCodexSparkCounters`.
        let claude = recipe(snapshot(.claude, [
            window(.fiveHour, used: 5, resetIn: 3 * hour),
            window(.other("Spark"), used: 1, resetIn: 3 * hour),
        ]), showsCodexSparkCounters: false)
        #expect(claude.shownWindows.count == 2)
    }

    // MARK: - Freshness (R11)

    @Test func staleWindowKeepsItsFreshnessAndUnavailableShowsNoValue() {
        let observed = now.addingTimeInterval(-10 * 60)
        let result = recipe(snapshot(.claude, [
            window(.fiveHour, used: 28, resetIn: 2 * hour, freshness: .stale(observedAt: observed)),
            window(.weekly, used: 60, resetIn: 3 * day, freshness: .unavailable(since: observed)),
        ]))
        #expect(result.content == .meters)
        #expect(result.shownWindows[0].window.freshness == .stale(observedAt: observed))
        #expect(result.shownWindows[0].displayedPercentage == 72)
        #expect(result.shownWindows[1].window.freshness == .unavailable(since: observed))
        #expect(result.shownWindows[1].displayedPercentage == nil)
        #expect(result.shownWindows[1].shortLabel == "wk")
        #expect(result.tooltip.contains("Last known 10 min ago"))
        #expect(result.tooltip.contains("Weekly: Unavailable"))
        #expect(!result.tooltip.contains("40%"))
    }

    @Test func transientStaleSnapshotStillShowsMetersDimmed() {
        let result = recipe(snapshot(.codex, [
            window(.fiveHour, used: 5, resetIn: 3 * hour),
        ], freshness: .stale(.transient("Network unavailable"))))
        #expect(result.content == .meters)
        #expect(result.isDimmed)
        #expect(result.shownWindows.count == 1)

        let live = recipe(snapshot(.codex, [window(.fiveHour, used: 5, resetIn: 3 * hour)]))
        #expect(!live.isDimmed)
    }

    @Test func percentageModeDrivesTheDisplayedValue() {
        let used = recipe(snapshot(.claude, [window(.fiveHour, used: 28, resetIn: 2 * hour)]), mode: .used)
        #expect(used.shownWindows[0].displayedPercentage == 28)
        #expect(used.tooltip.contains("28% used"))
        #expect(used.accessibilityValue.contains("28 percent used"))
    }

    // MARK: - Micro twin (R14)

    @Test func microTwinUsesTheShapeTheUserSees() {
        let fullTube = recipe(
            snapshot(.claude, [window(.fiveHour, used: 1, resetIn: hour)]),
            style: MeterStyle(format: .full, shape: .tube, fill: .ghost)
        )
        #expect(fullTube.meterStyle == MeterStyle(format: .micro, shape: .chip, fill: .ghost))

        let microTube = recipe(
            snapshot(.claude, [window(.fiveHour, used: 1, resetIn: hour)]),
            style: MeterStyle(format: .micro, shape: .tube, fill: .solid)
        )
        #expect(microTube.meterStyle == MeterStyle(format: .micro, shape: .tube, fill: .solid))

        let fullSegmented = recipe(
            snapshot(.claude, [window(.fiveHour, used: 1, resetIn: hour)]),
            style: MeterStyle(format: .full, shape: .segmented, fill: .hueRamp)
        )
        #expect(fullSegmented.meterStyle == MeterStyle(format: .micro, shape: .segmented, fill: .hueRamp))
    }

    @Test func microTwinIsCarriedOnSkeletonAndFallbackToo() {
        let style = MeterStyle(format: .full, shape: .tube, fill: .glass)
        let twin = MeterStyle(format: .micro, shape: .chip, fill: .glass)
        #expect(recipe(.pending(for: .claude), style: style).meterStyle == twin)
        #expect(recipe(.stale(for: .codex, reason: .notLoggedIn("x")), style: style).meterStyle == twin)
    }

    // MARK: - Standard fallback (R15)

    @Test func signedOutStatesFallBackToStandard() {
        let reasons: [FailureReason] = [
            .notLoggedIn("Not logged in"),
            .needsReauth("Sign in again"),
            .scopeDenied("Scope denied"),
            .providerSetup(.claudeLoginRequired),
            .providerSetup(.claudeTrustRequired),
            .providerSetup(.codexAuthAbsent),
            .providerSetup(.codexRejectedAuth),
            .providerSetup(.grokAuthAbsent),
            .providerSetup(.cursorAuthAbsent),
            .providerSetup(.cursorTrustRequired),
            .providerSetup(.claudeCLIMissing),
        ]
        for reason in reasons {
            let withRetained = recipe(snapshot(.claude, [window(.fiveHour, used: 5, resetIn: hour)], freshness: .stale(reason)))
            #expect(withRetained.content == .standardFallback, "\(reason)")
            #expect(withRetained.fallsBackToStandard)
            #expect(withRetained.shownWindows.isEmpty)
            #expect(withRetained.overflowCount == 0)
            let empty = recipe(.stale(for: .codex, reason: reason))
            #expect(empty.content == .standardFallback, "\(reason)")
        }
    }

    @Test func recoveryOutcomesFallBackEvenWhenTransient() {
        // The single-account card renders Check Now plus a recovery action for these
        // (ProviderCardView `providerSetupOutcome` branch), so Compact must not hide them.
        let reasons: [FailureReason] = [
            .providerSetup(.claudeTransientCapture),
            .providerSetup(.claudeUnknownUI),
            .providerSetup(.claudeStartupQuestion),
            .providerSetup(.codexCredentialIO),
            .providerSetup(.codexPermissionDenied),
            .providerSetup(.codexStorageMismatch),
            .providerSetup(.grokTransientCapture),
            .providerSetup(.cursorUnknownUI),
            .providerSetup(.cursorMCPApprovalRequired),
        ]
        for reason in reasons {
            let result = recipe(snapshot(.codex, [window(.weekly, used: 5, resetIn: day)], freshness: .stale(reason)))
            #expect(result.content == .standardFallback, "\(reason)")
        }
    }

    @Test func setupWaitingAndCapabilityFailureFallBackThroughTheAppFlag() {
        let live = snapshot(.claude, [window(.fiveHour, used: 5, resetIn: hour)])
        #expect(recipe(live, requiresStandardSection: true).content == .standardFallback)
        // A reset blanks the row to `.pending` while the session owns it.
        #expect(recipe(.pending(for: .claude), requiresStandardSection: true).content == .standardFallback)
    }

    @Test func pendingFirstReadingIsASkeletonNotAFallback() {
        let result = recipe(.pending(for: .cursor))
        #expect(result.content == .skeleton)
        #expect(!result.fallsBackToStandard)
        #expect(result.shownWindows.isEmpty)
        #expect(result.overflowCount == 0)
    }

    @Test func transientStaleWithNothingRetainedFallsBack() {
        // Standard says "No usage data"; a Compact row would have nothing to draw.
        #expect(recipe(.stale(for: .grok, reason: .transient("Timed out"))).content == .standardFallback)
        #expect(recipe(snapshot(.claude, [])).content == .standardFallback)
    }

    // MARK: - Tooltip and VoiceOver (R12, R13)

    @Test func tooltipAndAccessibilityListEveryWindowWithItsResetIncludingOverflow() {
        let result = recipe(snapshot(.claude, [
            window(.fiveHour, used: 28, resetIn: 2 * hour + 10 * 60),
            window(.weekly, used: 60, resetIn: 3 * day + 2 * hour),
            window(.other("Weekly (Fable)"), used: 90, resetIn: 5 * day),
        ]))
        #expect(result.overflowCount == 1)
        #expect(result.tooltip == """
        5-hour: 72% left · Resets in 2h 10m
        Weekly: 40% left · Resets in 3d 2h
        Fable weekly: 10% left · Resets in 5d
        """)
        #expect(result.accessibilityValue == [
            "5-hour: 72 percent left, Resets in 2h 10m",
            "Weekly: 40 percent left, Resets in 3d 2h",
            "Fable weekly: 10 percent left, critical, Resets in 5d",
        ].joined(separator: "; "))
    }

    @Test func dimmedRowNeverSpeaksCritical() {
        let result = recipe(snapshot(.claude, [
            window(.fiveHour, used: 95, resetIn: hour),
        ], freshness: .stale(.transient("x"))))
        #expect(!result.accessibilityValue.contains("critical"))
    }

    @Test func resetTextUsesTheSharedFormatter() {
        let line = window(.fiveHour, used: 1, resetIn: 45 * 60).resetSchedule.meterResetLine(now: now)
        let result = recipe(snapshot(.codex, [window(.fiveHour, used: 1, resetIn: 45 * 60)]))
        #expect(result.tooltip.hasSuffix(line!.tooltip))
    }

    // MARK: - KTD15 characterization (pinned before the at-limit rule)

    /// The shown labels and overflow count, the part of the recipe KTD15 may move.
    private func pin(_ result: CompactAccountRowRecipe) -> String {
        result.shownWindows.map(\.shortLabel).joined(separator: ",") + " +\(result.overflowCount)"
    }

    /// Today's output for every provider shape, with windows near but below their limit.
    /// KTD15 must leave each of these exactly as it is: labels never move until a limit is hit.
    @Test func characterizationBelowTheLimitNothingMoves() {
        let cases: [(UsageSnapshot, String)] = [
            (snapshot(.codex, [
                window(.fiveHour, used: 99, resetIn: 3 * hour),
                window(.weekly, used: 10, resetIn: 4 * day),
            ]), "5h,wk +0"),
            (snapshot(.claude, [
                window(.fiveHour, used: 10, resetIn: 2 * hour),
                window(.weekly, used: 20, resetIn: 3 * day),
                window(.other("Weekly (Fable)"), used: 99.9, resetIn: 3 * day),
            ]), "5h,wk +1"),
            (snapshot(.claude, [
                window(.weekly, used: 20, resetIn: 3 * day),
                window(.fiveHour, used: 10, resetIn: 2 * hour),
                window(.other("Weekly (Fable)"), used: 30, resetIn: 3 * day),
                window(.other("Weekly (Opus)"), used: 99, resetIn: 3 * day),
            ]), "5h,wk +2"),
            (snapshot(.cursor, [
                window(.billingPeriod(label: "Cursor Models", duration: 30 * day), used: 1, resetIn: 12 * day),
                window(.billingPeriod(label: "Other Models", duration: 30 * day), used: 3, resetIn: 12 * day),
            ]), "Models,Other +0"),
            (snapshot(.cursor, [
                window(.billingPeriod(label: "Cursor Models", duration: 30 * day), used: 1, resetIn: 12 * day),
                window(.billingPeriod(label: "Other Models", duration: 30 * day), used: 3, resetIn: 12 * day),
                window(.billingPeriod(label: "Included", duration: 30 * day), used: 98, resetIn: 12 * day),
            ]), "Models,Other +1"),
            (snapshot(.grok, [
                window(.billingPeriod(label: "Monthly", duration: 30 * day), used: 99, resetIn: 9 * day),
            ]), "mo +0"),
            (snapshot(.opencode, [
                window(.fiveHour, used: 10, resetIn: 2 * hour),
                window(.weekly, used: 50, resetIn: 3 * day),
                window(.billingPeriod(label: "Monthly", duration: 30 * day), used: 99, resetIn: 20 * day),
            ]), "5h,wk +1"),
        ]
        for (snapshot, expected) in cases {
            let result = recipe(snapshot)
            #expect(pin(result) == expected, "\(snapshot.providerID)")
            #expect(result.content == .meters)
        }
    }

    /// Two-window providers already show everything, so a window at its limit changes nothing.
    @Test func characterizationTwoWindowProvidersAtTheLimitStayPut() {
        let codex = recipe(snapshot(.codex, [
            window(.fiveHour, used: 100, resetIn: 3 * hour),
            window(.weekly, used: 10, resetIn: 4 * day),
        ]))
        #expect(pin(codex) == "5h,wk +0")
        let cursor = recipe(snapshot(.cursor, [
            window(.billingPeriod(label: "Cursor Models", duration: 30 * day), used: 1, resetIn: 12 * day),
            window(.billingPeriod(label: "Other Models", duration: 30 * day), used: 100, resetIn: 12 * day),
        ]))
        #expect(pin(cursor) == "Models,Other +0")
    }

    // MARK: - KTD15: a window at its limit takes a slot (every provider)

    private let monthly = OpenCodeProvider.monthlyKind

    private func limited(_ kind: WindowKind, resetIn: TimeInterval, freshness: UsageWindowFreshness = .live) -> UsageWindow {
        UsageWindow(kind: kind, utilization: 100, resetSchedule: .scheduled(now.addingTimeInterval(resetIn)),
                    freshness: freshness, isLimited: true)
    }

    @Test func aLimitedMonthlyTakesTheRoomiestSlotAndTheRowStaysMeters() {
        let result = recipe(snapshot(.opencode, [
            window(.fiveHour, used: 10, resetIn: 2 * hour),
            window(.weekly, used: 50, resetIn: 3 * day),
            limited(monthly, resetIn: 20 * day),
        ]))
        // 5-hour has the most room (90% left), so it goes behind "+1".
        #expect(pin(result) == "wk,mo +1")
        #expect(result.content == .meters)
        #expect(!result.fallsBackToStandard)
        #expect(result.shownWindows.last?.displayedPercentage == 0)
        // The overflowed window still reads in the tooltip.
        #expect(result.tooltip.contains("5-hour: 90% left"))
    }

    @Test func theRoomiestShownWindowIsTheOneReplaced() {
        let result = recipe(snapshot(.opencode, [
            window(.fiveHour, used: 50, resetIn: 2 * hour),
            window(.weekly, used: 10, resetIn: 3 * day),
            limited(monthly, resetIn: 20 * day),
        ]))
        #expect(pin(result) == "5h,mo +1")
    }

    @Test func aStaleWindowAtItsLimitTakesASlotButAnUnavailableOneNever() {
        let observed = now.addingTimeInterval(-10 * 60)
        let stale = recipe(snapshot(.opencode, [
            window(.fiveHour, used: 10, resetIn: 2 * hour, freshness: .stale(observedAt: observed)),
            window(.weekly, used: 50, resetIn: 3 * day, freshness: .stale(observedAt: observed)),
            limited(monthly, resetIn: 20 * day, freshness: .stale(observedAt: observed)),
        ], freshness: .stale(.transient("x"))))
        #expect(pin(stale) == "wk,mo +1")

        let unavailable = recipe(snapshot(.opencode, [
            window(.fiveHour, used: 10, resetIn: 2 * hour),
            window(.weekly, used: 50, resetIn: 3 * day),
            limited(monthly, resetIn: 20 * day, freshness: .unavailable(since: observed)),
        ]))
        #expect(pin(unavailable) == "5h,wk +1")
    }

    @Test func atOneHundredWithoutTheLimitedFlagStillTakesASlot() {
        // KTD15 keys on 100% used ("a limited window included"), not on the flag.
        let result = recipe(snapshot(.opencode, [
            window(.fiveHour, used: 10, resetIn: 2 * hour),
            window(.weekly, used: 50, resetIn: 3 * day),
            window(monthly, used: 100, resetIn: 20 * day),
        ]))
        #expect(pin(result) == "wk,mo +1")
    }

    @Test func allThreeLimitedKeepSourceOrder() {
        let result = recipe(snapshot(.opencode, [
            limited(.fiveHour, resetIn: 2 * hour),
            limited(.weekly, resetIn: 3 * day),
            limited(monthly, resetIn: 20 * day),
        ]))
        #expect(pin(result) == "5h,wk +1")
        #expect(result.content == .meters)
    }

    @Test func theSameRuleMovesAClaudeModelRowAndAThirdCursorPool() {
        let claude = recipe(snapshot(.claude, [
            window(.fiveHour, used: 10, resetIn: 2 * hour),
            window(.weekly, used: 20, resetIn: 3 * day),
            window(.other("Weekly (Fable)"), used: 100, resetIn: 3 * day),
        ]))
        #expect(pin(claude) == "wk,Fable +1")
        #expect(claude.content == .meters)

        let cursor = recipe(snapshot(.cursor, [
            window(.billingPeriod(label: "Cursor Models", duration: 30 * day), used: 40, resetIn: 12 * day),
            window(.billingPeriod(label: "Other Models", duration: 30 * day), used: 3, resetIn: 12 * day),
            window(.billingPeriod(label: "Included", duration: 30 * day), used: 100, resetIn: 12 * day),
        ]))
        #expect(pin(cursor) == "Models,Included +1")
    }

    @Test func twoOverflowedLimitsFillBothSlots() {
        let result = recipe(snapshot(.claude, [
            window(.fiveHour, used: 10, resetIn: 2 * hour),
            window(.weekly, used: 20, resetIn: 3 * day),
            window(.other("Weekly (Fable)"), used: 100, resetIn: 3 * day),
            window(.other("Weekly (Opus)"), used: 100, resetIn: 3 * day),
        ]))
        #expect(pin(result) == "Fable,Opus +2")
    }

    // MARK: - KTD7: the no-plan row keeps the Standard section (it carries an action)

    @Test func theNoGoRowFallsBackToStandard() {
        let noGo = UsageSnapshot(
            providerID: .opencode,
            windows: [UsageWindow(kind: monthly, utilization: 0, resetSchedule: .unresolved(.absent),
                                  freshness: .unavailable(since: now.addingTimeInterval(-day)))],
            planLabel: nil, capturedAt: now, freshness: .live, planStatus: .noActivePlan
        )
        #expect(recipe(noGo).content == .standardFallback)
        // A transient failure keeps the plan status and the fallback with it.
        #expect(recipe(noGo.markedStale(.providerSetup(.opencodeTransientCapture))).content == .standardFallback)
        // The same windows without the status are an ordinary row.
        #expect(recipe(noGo.replacingWindows(noGo.windows).withoutPlanStatusForTest()).content == .meters)
    }

    // MARK: - Header columns: a window under another kind's column names itself

    @Test func aWindowUnderAnotherColumnLabelsItself() {
        let result = recipe(snapshot(.opencode, [
            window(.fiveHour, used: 10, resetIn: 2 * hour),
            window(.weekly, used: 50, resetIn: 3 * day),
            limited(monthly, resetIn: 20 * day),
        ]))
        // A neighbour's row set the header to 5h, wk.
        let cells = result.placedWindows(columns: [.fiveHour, .weekly])
        #expect(cells.map { $0?.window.window.kind } == [monthly, .weekly])
        #expect(cells.map { $0?.ownLabel } == ["mo", nil])

        let matching = result.placedWindows(columns: [.weekly, monthly])
        #expect(matching.map { $0?.ownLabel } == [nil, nil])
        #expect(result.placedWindows(columns: []).map { $0?.ownLabel } == [nil, nil])
    }
}

private extension UsageSnapshot {
    func withoutPlanStatusForTest() -> UsageSnapshot {
        UsageSnapshot(providerID: providerID, windows: windows, planLabel: planLabel, capturedAt: capturedAt,
                      freshness: freshness)
    }
}

// MARK: - Remembered rows (default-login plan U8)

/// R7, R8, KTD10: a remembered row says when it was last read, and a window past its reset
/// says when it reset instead of a value. Keyed on row kind, never on freshness.
struct RememberedRowRecipeTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60
    private let utc = TimeZone(identifier: "UTC")!
    private let locale = Locale(identifier: "en_US_POSIX")

    private func window(
        _ kind: WindowKind,
        used: Double,
        resetIn: TimeInterval,
        freshness: UsageWindowFreshness
    ) -> UsageWindow {
        UsageWindow(kind: kind, utilization: used, resetsAt: now.addingTimeInterval(resetIn), freshness: freshness)
    }

    private func resetLine(_ resetIn: TimeInterval) -> String {
        Countdown.resetNotReadLine(resetAt: now.addingTimeInterval(resetIn), now: now, timeZone: utc, locale: locale)
    }

    /// The aged snapshot KTD10 serves: a window before its reset is stale with its own
    /// observation time; one past it is unavailable since its reset.
    private func agedSnapshot(readAgo: TimeInterval) -> UsageSnapshot {
        let readAt = now.addingTimeInterval(-readAgo)
        return UsageSnapshot(
            providerID: .claude,
            windows: [
                window(.fiveHour, used: 40, resetIn: -3 * hour,
                       freshness: .unavailable(since: now.addingTimeInterval(-3 * hour))),
                window(.weekly, used: 90, resetIn: 2 * day, freshness: .stale(observedAt: readAt)),
            ],
            planLabel: "team", capturedAt: readAt, freshness: .stale(.transient("Last known usage"))
        )
    }

    private func compact(_ snapshot: UsageSnapshot, remembered: Bool, lastReadAt: Date?) -> CompactAccountRowRecipe {
        CompactAccountRowRecipe(
            snapshot: snapshot, meterStyle: .default, percentageMode: .remaining, now: now,
            requiresStandardSection: false, showsCodexSparkCounters: true,
            isRemembered: remembered, lastReadAt: lastReadAt, timeZone: utc, locale: locale
        )
    }

    @Test func oneUnavailableWindowYieldsOneMeterAndOneResetLine() {
        let snapshot = agedSnapshot(readAgo: 2 * 60)
        let recipe = RememberedRowRecipe(
            windows: snapshot.windows, lastReadAt: snapshot.capturedAt, now: now, timeZone: utc, locale: locale
        )
        #expect(recipe.resetNotReadLines == [resetLine(-3 * hour), nil])
        #expect(recipe.lastReadLabel == "Last read 2 min ago")
    }

    @Test func theResetLineIsTheSharedWordingAndCarriesNoValue() {
        let line = resetLine(-3 * hour)
        #expect(line.hasPrefix("Reset "))
        #expect(line.hasSuffix(" · not read since"))
        #expect(!line.contains("%"))
    }

    /// A reading the aging pass has not reached yet still never states a value past reset.
    @Test func aStaleWindowPastItsResetIsAResetLineToo() {
        let stale = window(.weekly, used: 90, resetIn: -1, freshness: .stale(observedAt: now.addingTimeInterval(-day)))
        #expect(RememberedRowRecipe.resetNotReadLine(for: stale, now: now, timeZone: utc, locale: locale)
            == resetLine(-1))
        let ahead = window(.weekly, used: 90, resetIn: 60, freshness: .stale(observedAt: now.addingTimeInterval(-day)))
        #expect(RememberedRowRecipe.resetNotReadLine(for: ahead, now: now) == nil)
    }

    /// A window with no scheduled reset has no reset to name; it keeps the unavailable meter.
    @Test func aWindowWithNoScheduledResetKeepsItsMeter() {
        let unscheduled = UsageWindow(
            kind: .weekly, utilization: 10, resetSchedule: .unresolved(.absent),
            freshness: .unavailable(since: now.addingTimeInterval(-day))
        )
        let recipe = RememberedRowRecipe(windows: [unscheduled], lastReadAt: nil, now: now)
        #expect(recipe.resetNotReadLines == [nil])
        #expect(recipe.lastReadLabel == nil)
    }

    @Test func theCompactTooltipNamesTheLastReadTimeAndEachResetDate() {
        let snapshot = agedSnapshot(readAgo: 2 * day)
        let lastReadAt = now.addingTimeInterval(-2 * day)
        let recipe = compact(snapshot, remembered: true, lastReadAt: lastReadAt)

        #expect(recipe.content == .meters)
        #expect(recipe.rowStateLabel == "Last read 2 days ago")
        #expect(recipe.lastReadLabel == Countdown.lastReadLabel(capturedAt: lastReadAt, now: now))
        let weeklyReset = snapshot.windows[1].resetSchedule.meterResetLine(now: now)!.tooltip
        #expect(recipe.tooltip == [
            "5-hour: \(resetLine(-3 * hour))",
            "Weekly: 10% left · \(weeklyReset)",
        ].joined(separator: "\n"))
        // VoiceOver hears the same reset wording, and neither says "Last known" per window.
        #expect(recipe.accessibilityValue.contains(resetLine(-3 * hour)))
        #expect(!recipe.tooltip.contains("Last known"))
        #expect(!recipe.tooltip.contains("Stale"))
    }

    /// The cell past its reset prints no number, even before aging turns it unavailable.
    @Test func aCompactCellPastItsResetShowsNoNumber() {
        let snapshot = UsageSnapshot(
            providerID: .codex,
            windows: [window(.fiveHour, used: 40, resetIn: -hour,
                             freshness: .stale(observedAt: now.addingTimeInterval(-day)))],
            planLabel: nil, capturedAt: now.addingTimeInterval(-day), freshness: .stale(.transient("x"))
        )
        let recipe = compact(snapshot, remembered: true, lastReadAt: nil)
        #expect(recipe.shownWindows.map(\.displayedPercentage) == [nil])
        #expect(recipe.lastReadLabel == "Last read 1 day ago")
    }

    /// An engine row that is stale and has an unavailable window reads exactly as before.
    @Test func anEngineRowKeepsItsStaleWordingAndNumbers() {
        let snapshot = agedSnapshot(readAgo: 2 * 60)
        let engine = compact(snapshot, remembered: false, lastReadAt: nil)
        let before = CompactAccountRowRecipe(
            snapshot: snapshot, meterStyle: .default, percentageMode: .remaining, now: now,
            requiresStandardSection: false, showsCodexSparkCounters: true
        )
        #expect(engine == before)
        #expect(engine.rowStateLabel == "Stale")
        #expect(engine.lastReadLabel == nil)
        #expect(engine.shownWindows.map(\.displayedPercentage) == [nil, 10])
        #expect(engine.tooltip.contains("Unavailable"))
        #expect(engine.tooltip.contains("Last known 2 min ago"))
        #expect(!engine.tooltip.contains("not read since"))
    }

    @Test func aLiveEngineRowHasNoStateWord() {
        let live = UsageSnapshot(
            providerID: .claude,
            windows: [window(.weekly, used: 10, resetIn: day, freshness: .live)],
            planLabel: nil, capturedAt: now, freshness: .live
        )
        #expect(compact(live, remembered: false, lastReadAt: nil).rowStateLabel == nil)
    }
}
