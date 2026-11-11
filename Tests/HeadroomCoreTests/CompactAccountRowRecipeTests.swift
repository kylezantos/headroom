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
