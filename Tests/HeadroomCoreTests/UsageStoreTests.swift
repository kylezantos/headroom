import Testing
import Foundation
@testable import HeadroomCore

/// U6 test scenarios: concurrent population, per-provider isolation, continuity on
/// stale, and the menu bar summary (lowest live window + provider identity).
@MainActor
struct UsageStoreTests {
    private let reset = Date(timeIntervalSince1970: 2_000_000)

    @Test func refreshPopulatesAllProviders() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude",
                         snapshot: .live(.claude, windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset)])),
            StubProvider(id: .codex, displayName: "Codex",
                         snapshot: .live(.codex, windows: [UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset)])),
        ])
        await store.refreshAll()
        #expect(store.snapshot(for: .claude).freshness == .live)
        #expect(store.snapshot(for: .codex).freshness == .live)
    }

    @Test func freshDefaultsDoNotFetchNewSubscriptionProviders() async {
        let claude = CountingProvider(id: .claude)
        let codex = CountingProvider(id: .codex)
        let grok = CountingProvider(id: .grok)
        let cursor = CountingProvider(id: .cursor)
        let store = UsageStore(
            providers: [claude, codex, grok, cursor],
            preferences: freshPreferences()
        )

        await store.refreshAll()

        #expect(claude.fetchCount == 1)
        #expect(codex.fetchCount == 1)
        #expect(grok.fetchCount == 0)
        #expect(cursor.fetchCount == 0)
    }

    @Test func codexPublishesBeforeSlowClaudeLaneCompletes() async {
        let firstClaude = SlowCountingProvider(id: .claude)
        let codex = StubProvider(
            id: .codex,
            displayName: "Codex",
            snapshot: .live(.codex, windows: [UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset)])
        )
        let store = makeStore(providers: [firstClaude, codex])
        let refresh = Task { await store.refreshAll() }
        await firstClaude.waitUntilFetchStarts()

        for _ in 0..<20 where store.snapshot(for: .codex).freshness != .live { await Task.yield() }
        #expect(store.snapshot(for: .codex).freshness == .live)
        #expect(store.snapshot(for: .claude).freshness == .pending)

        firstClaude.releaseFetch()
        await refresh.value
    }

    @Test func keyedCLILanesSerializePerProviderAndOverlapEachOther() async {
        let grokFirst = SlowCountingProvider(
            id: .grok,
            accountID: AccountID("grok-a"),
            pollingLane: .serial("grok-cli")
        )
        let grokSecond = SlowCountingProvider(
            id: .grok,
            accountID: AccountID("grok-b"),
            pollingLane: .serial("grok-cli")
        )
        let claude = SlowCountingProvider(
            id: .claude,
            pollingLane: .serial("claude-cli")
        )
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        let store = UsageStore(
            providers: [grokFirst, grokSecond, claude],
            preferences: preferences
        )

        let refresh = Task { await store.refreshAll() }
        await grokFirst.waitUntilFetchStarts()
        await claude.waitUntilFetchStarts()
        #expect(grokSecond.fetchCount == 0)

        grokFirst.releaseFetch()
        claude.releaseFetch()
        await grokSecond.waitUntilFetchStarts()
        #expect(grokSecond.fetchCount == 1)
        grokSecond.releaseFetch()
        await refresh.value
    }

    @Test func startsPendingBeforeAnyFetch() {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
        ])
        #expect(store.snapshot(for: .claude).freshness == .pending)
        #expect(store.menuBarSummary.isNeutral)
    }

    @Test func oneProviderFailureDoesNotAffectOther() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude",
                         snapshot: .live(.claude, windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset)])),
            StubProvider(id: .codex, displayName: "Codex",
                         snapshot: UsageSnapshot(providerID: .codex, windows: [], planLabel: nil,
                                                 capturedAt: nil, freshness: .stale(.transient("down")))),
        ])
        await store.refreshAll()
        #expect(store.snapshot(for: .claude).freshness == .live)   // unaffected
        if case .stale = store.snapshot(for: .codex).freshness {} else { Issue.record("codex should be stale") }
    }

    @Test func staleWithoutDataKeepsPriorWindows() async {
        // Continuity (KTD7): a later failure keeps the prior windows shown, dimmed.
        let provider = MutableStubProvider(id: .claude, displayName: "Claude",
            snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 40, resetsAt: .distantFuture),
            ]))
        let store = makeStore(providers: [provider])
        await store.refreshAll()
        #expect(store.snapshot(for: .claude).windows.count == 1)

        provider.set(UsageSnapshot(providerID: .claude, windows: [], planLabel: nil,
                                   capturedAt: nil, freshness: .stale(.transient("blip"))))
        await store.refreshAll()
        let after = store.snapshot(for: .claude)
        #expect(after.windows.count == 1)                       // prior data retained
        if case .stale = after.freshness {} else { Issue.record("should be stale") }
    }

    @Test func monthlyPeriodContinuityExpiresWithoutRenewingObservation() {
        let day: TimeInterval = 24 * 60 * 60
        let observedAt = Date(timeIntervalSince1970: 2_000_000)
        let resetsAt = observedAt.addingTimeInterval(30 * day)
        let kind = WindowKind.billingPeriod(label: "Monthly", duration: 30 * day)
        let prior = UsageSnapshot.live(.grok, windows: [
            UsageWindow(kind: kind, utilization: 35, resetsAt: resetsAt),
        ], at: observedAt)
        let failure = UsageSnapshot.stale(for: .grok, reason: .transient("down"))

        let retained = UsageContinuityPolicy.mergedSnapshot(
            failure,
            with: prior,
            at: observedAt.addingTimeInterval(2 * day)
        )
        #expect(retained.windows.first?.freshness == .stale(observedAt: observedAt))

        let unavailable = UsageContinuityPolicy.mergedSnapshot(
            failure,
            with: retained,
            at: resetsAt.addingTimeInterval(day)
        )
        #expect(unavailable.windows.first?.freshness == .unavailable(since: resetsAt))
        #expect(unavailable.windows.first?.utilization == 35)

        let removed = UsageContinuityPolicy.mergedSnapshot(
            failure,
            with: unavailable,
            at: resetsAt.addingTimeInterval(31 * day)
        )
        #expect(removed.windows.isEmpty)

        let recovered = UsageContinuityPolicy.mergedSnapshot(prior, with: unavailable, at: observedAt)
        #expect(recovered.windows.first?.freshness == .live)
    }

    @Test func partialClaudeLiveCaptureKeepsCurrentWeeklySubLimit() async {
        let initialCapture = Date(timeIntervalSince1970: 2_000_000)
        let partialCapture = Date(timeIntervalSince1970: 2_050_000)
        let nextCycleCapture = Date(timeIntervalSince1970: 2_200_000)
        let currentReset = Date(timeIntervalSince1970: 2_100_000)
        let nextReset = Date(timeIntervalSince1970: 2_700_000)
        let provider = MutableStubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 5, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: currentReset, resetLabel: "Resets Jul 23 at 9:59am"),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 39, resetsAt: currentReset, resetLabel: "Resets Jul 23 at 9:59am"),
            ], at: initialCapture)
        )
        let phoneExporter = SpyWidgetExporter()
        let preferences = freshPreferences()
        preferences.syncToIPhoneEnabled = true
        let store = UsageStore(
            providers: [provider],
            preferences: preferences,
            phoneSyncExporter: phoneExporter
        )

        await store.refreshAll()
        provider.set(.live(.claude, windows: [
            UsageWindow(kind: .fiveHour, utilization: 0, resetsAt: reset),
            UsageWindow(kind: .weekly, utilization: 25, resetsAt: currentReset, resetLabel: "Resets Jul 23 at 10am"),
        ], at: partialCapture))
        await store.refreshAll()

        #expect(store.snapshot(for: .claude).windows.map(\.kind) == [
            .fiveHour,
            .weekly,
            .other("Weekly (Fable)"),
        ])
        #expect(store.snapshot(for: .claude).freshness == .live)
        #expect(store.snapshot(for: .claude).capturedAt == partialCapture)
        #expect(
            store.snapshot(for: .claude).windows.first { $0.kind == .weekly }?.freshness
                == .live
        )
        #expect(
            store.snapshot(for: .claude).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                == .stale(observedAt: initialCapture)
        )
        #expect(phoneExporter.exports.last?.providers.first?.extraWeeklyWindows.map(\.compactLabel) == ["Fable"])
        #expect(
            phoneExporter.exports.last?.providers.first?.extraWeeklyWindows.first?.freshness
                == .stale(observedAt: initialCapture)
        )

        provider.set(.live(.claude, windows: [
            UsageWindow(kind: .fiveHour, utilization: 0, resetsAt: reset),
            UsageWindow(kind: .weekly, utilization: 0, resetsAt: nextReset, resetLabel: "Resets Jul 30 at 9:59am"),
        ], at: nextCycleCapture))
        await store.refreshAll()

        #expect(store.snapshot(for: .claude).windows.map(\.kind) == [
            .fiveHour,
            .weekly,
            .other("Weekly (Fable)"),
        ])
        #expect(
            store.snapshot(for: .claude).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                == .unavailable(since: currentReset)
        )

        let unavailableExpiryCapture = nextCycleCapture.addingTimeInterval(8 * 24 * 60 * 60)
        provider.set(.live(.claude, windows: [
            UsageWindow(
                kind: .weekly,
                utilization: 1,
                resetsAt: unavailableExpiryCapture.addingTimeInterval(7 * 24 * 60 * 60)
            ),
        ], at: unavailableExpiryCapture))
        await store.refreshAll()

        #expect(store.snapshot(for: .claude).windows.map(\.kind) == [.weekly])
    }

    @Test func freshClaudeSubLimitReplacesLastKnownState() async {
        let initialCapture = Date(timeIntervalSince1970: 2_000_000)
        let partialCapture = initialCapture.addingTimeInterval(60)
        let recoveredCapture = partialCapture.addingTimeInterval(60)
        let reset = recoveredCapture.addingTimeInterval(3_600)
        let provider = MutableStubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 39, resetsAt: reset),
            ], at: initialCapture)
        )
        let store = UsageStore(providers: [provider], preferences: freshPreferences())

        await store.refreshAll()
        provider.set(.live(.claude, windows: [
            UsageWindow(kind: .weekly, utilization: 26, resetsAt: reset),
        ], at: partialCapture))
        await store.refreshAll()
        #expect(
            store.snapshot(for: .claude).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                == .stale(observedAt: initialCapture)
        )

        provider.set(.live(.claude, windows: [
            UsageWindow(kind: .weekly, utilization: 27, resetsAt: reset),
            UsageWindow(kind: .other("Weekly (Fable)"), utilization: 41, resetsAt: reset),
        ], at: recoveredCapture))
        await store.refreshAll()

        let recovered = store.snapshot(for: .claude)
            .windows.first { $0.kind == .other("Weekly (Fable)") }
        #expect(recovered?.freshness == .live)
        #expect(recovered?.utilization == 41)
    }

    @Test func cachedClaudeSubLimitSurvivesPartialFirstRefreshAfterRelaunch() async {
        let relaunchCapture = Date()
        let initialCapture = relaunchCapture.addingTimeInterval(-60)
        let reset = relaunchCapture.addingTimeInterval(3_600)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let firstProcessCache = UsageContinuityCache(defaults: defaults)
        firstProcessCache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 5, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 39, resetsAt: reset),
            ], at: initialCapture),
            for: key
        )

        let provider = StubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 6, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 26, resetsAt: reset),
            ], at: relaunchCapture)
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            continuityCache: UsageContinuityCache(defaults: defaults),
            now: { relaunchCapture }
        )

        #expect(store.snapshot(for: key).windows.map(\.kind) == [
            .fiveHour,
            .weekly,
            .other("Weekly (Fable)"),
        ])
        if case .stale = store.snapshot(for: key).freshness {} else {
            Issue.record("restored launch data should be stale")
        }
        #expect(
            store.snapshot(for: key).windows.first { $0.kind == .weekly }?.freshness
                == .stale(observedAt: initialCapture)
        )

        await store.refreshAll()

        #expect(store.snapshot(for: key).windows.map(\.kind) == [
            .fiveHour,
            .weekly,
            .other("Weekly (Fable)"),
        ])
        #expect(store.snapshot(for: key).windows.first?.utilization == 6)
        #expect(store.snapshot(for: key).freshness == .live)
        #expect(
            store.snapshot(for: key).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                == .stale(observedAt: initialCapture)
        )
        #expect(
            store.snapshot(for: key).windows.first { $0.kind == .weekly }?.freshness
                == .live
        )
    }

    @Test func transientFailuresCannotKeepUnavailableClaudeSubLimitForever() async {
        let initialCapture = Date(timeIntervalSince1970: 2_000_000)
        let reset = initialCapture.addingTimeInterval(60)
        let unavailableCapture = reset.addingTimeInterval(60)
        let futureWeeklyReset = reset.addingTimeInterval(30 * 24 * 60 * 60)
        let dateSource = MutableDateSource(initialCapture)
        let provider = MutableStubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 39, resetsAt: reset),
            ], at: initialCapture)
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            now: dateSource.now
        )

        await store.refreshAll()
        provider.set(.live(.claude, windows: [
            UsageWindow(kind: .weekly, utilization: 26, resetsAt: futureWeeklyReset),
        ], at: unavailableCapture))
        await store.refreshAll()
        #expect(
            store.snapshot(for: .claude).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                == .unavailable(since: reset)
        )

        dateSource.set(reset.addingTimeInterval(8 * 24 * 60 * 60))
        provider.set(.stale(for: .claude, reason: .transient("blip")))
        await store.refreshAll()

        #expect(store.snapshot(for: .claude).windows.map(\.kind) == [.weekly])
        #expect(store.snapshot(for: .claude).windows.first?.freshness == .stale(observedAt: unavailableCapture))
    }

    @Test func cachedClaudeSubLimitWithUnknownResetSurvivesRelaunchAndPartialRefresh() async {
        let initialCapture = Date(timeIntervalSince1970: 2_000_000)
        let relaunchCapture = initialCapture.addingTimeInterval(60)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 39,
                    resetSchedule: .unresolved(.absent),
                    observedAt: initialCapture
                ),
            ], at: initialCapture),
            for: key
        )
        let provider = StubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [
                UsageWindow(
                    kind: .weekly,
                    utilization: 26,
                    resetsAt: relaunchCapture.addingTimeInterval(3_600)
                ),
            ], at: relaunchCapture)
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { relaunchCapture }
        )

        #expect(store.snapshot(for: key).windows.map(\.kind) == [.other("Weekly (Fable)")])

        await store.refreshAll()

        #expect(store.snapshot(for: key).windows.map(\.kind) == [
            .weekly,
            .other("Weekly (Fable)"),
        ])
        #expect(store.snapshot(for: key).freshness == .live)
        #expect(
            store.snapshot(for: key).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                == .stale(observedAt: initialCapture)
        )
    }

    @Test func cachedUnknownResetBecomesUnavailableAfterItsFallbackLifetime() {
        let initialCapture = Date(timeIntervalSince1970: 2_000_000)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 39,
                    resetSchedule: .unresolved(.absent),
                    observedAt: initialCapture
                ),
            ], at: initialCapture),
            for: key
        )

        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { initialCapture.addingTimeInterval(8 * 24 * 60 * 60) }
        )

        #expect(store.snapshot(for: key).freshness == .stale(.transient("Last known usage — refreshing")))
        #expect(store.snapshot(for: key).windows.first?.freshness == .unavailable(
            since: initialCapture.addingTimeInterval(7 * 24 * 60 * 60)
        ))

        let laterRelaunch = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { initialCapture.addingTimeInterval(15 * 24 * 60 * 60) }
        )

        #expect(laterRelaunch.snapshot(for: key).freshness == .pending)
    }

    @Test func genuinelyPastClaudeResetIsNotTreatedAsUnknown() {
        let restorationDate = Date(timeIntervalSince1970: 2_000_000)
        let capturedAt = restorationDate.addingTimeInterval(-60)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 92,
                    resetsAt: capturedAt.addingTimeInterval(-24 * 60 * 60),
                    resetLabel: "Resets Jan 5 at 9am"
                ),
            ], at: capturedAt),
            for: key
        )

        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { restorationDate }
        )

        #expect(store.snapshot(for: key).freshness == .stale(.transient("Last known usage — refreshing")))
        #expect(
            store.snapshot(for: key).windows.first?.freshness
                == .unavailable(since: capturedAt.addingTimeInterval(-24 * 60 * 60))
        )
    }

    @Test func codexResetAtCaptureIsNeverTreatedAsClaudeUnknownSentinel() {
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .codex, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 100, resetsAt: capturedAt),
            ], at: capturedAt),
            for: key
        )

        let store = UsageStore(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: .pending(for: .codex))],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { capturedAt.addingTimeInterval(60) }
        )

        #expect(store.snapshot(for: key).freshness == .pending)
    }

    @Test func repeatedPartialCapturesDoNotRenewUnknownResetFallbackLifetime() async {
        let initialCapture = Date(timeIntervalSince1970: 2_000_000)
        let weeklyReset = initialCapture.addingTimeInterval(14 * 24 * 60 * 60)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: weeklyReset),
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 39,
                    resetSchedule: .unresolved(.absent),
                    observedAt: initialCapture
                ),
            ], at: initialCapture),
            for: key
        )
        let provider = MutableStubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .pending(for: .claude)
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { initialCapture }
        )

        for day in 1...6 {
            let capturedAt = initialCapture.addingTimeInterval(Double(day) * 24 * 60 * 60)
            provider.set(.live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: weeklyReset),
            ], at: capturedAt))
            await store.refreshAll()
            #expect(store.snapshot(for: key).windows.map(\.kind) == [
                .weekly,
                .other("Weekly (Fable)"),
            ])
            #expect(store.snapshot(for: key).capturedAt == capturedAt)
            #expect(
                store.snapshot(for: key).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                    == .stale(observedAt: initialCapture)
            )
        }

        let relaunched = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { initialCapture.addingTimeInterval(7 * 24 * 60 * 60) }
        )

        #expect(relaunched.snapshot(for: key).windows.map(\.kind) == [
            .weekly,
            .other("Weekly (Fable)"),
        ])
        #expect(
            relaunched.snapshot(for: key).windows.first { $0.kind == .other("Weekly (Fable)") }?.freshness
                == .unavailable(since: initialCapture.addingTimeInterval(7 * 24 * 60 * 60))
        )
    }

    @Test func permanentFailureClearsPersistedContinuityBeforeRelaunch() async {
        let capture = Date(timeIntervalSince1970: 2_000_000)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: .distantFuture),
            ], at: capture),
            for: key
        )
        let signedOut = StubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired))
        )
        let store = UsageStore(
            providers: [signedOut],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { capture }
        )

        await store.refreshAll()

        #expect(cache.load()[key] == nil)
        let relaunched = UsageStore(
            providers: [signedOut],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { capture }
        )
        #expect(relaunched.snapshot(for: key).freshness == .pending)
    }

    @Test func claudeCapabilityFailureRetainsPersistedContinuityBeforeRelaunch() async {
        let capture = Date(timeIntervalSince1970: 2_000_000)
        let refresh = capture.addingTimeInterval(300)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: .distantFuture),
            ], at: capture),
            for: key
        )
        let unavailable = CapabilityStubProvider(
            id: .claude,
            accountID: .primary,
            displayName: "Claude",
            result: UsageProviderFetchResult(
                snapshot: .stale(for: .claude, reason: .transient("Claude capability unavailable")),
                capability: .inconclusive(.shellTimeout)
            )
        )
        let store = UsageStore(
            providers: [unavailable],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { refresh }
        )

        await store.refreshAll()

        let retained = cache.load()[key]
        #expect(retained?.capturedAt == capture)
        #expect(retained?.windows.first?.freshness == .live)

        let relaunched = UsageStore(
            providers: [unavailable],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { refresh }
        )
        #expect(relaunched.snapshot(for: key).capturedAt == capture)
        #expect(relaunched.snapshot(for: key).windows.first?.freshness == .stale(observedAt: capture))
        #expect(store.providerCapabilities[.claude]?.state == .inconclusive(.shellTimeout))
    }

    @Test func confirmedClaudeAbsenceWithNoHistoryDoesNotInventAccountSetup() async {
        let provider = CapabilityStubProvider(
            id: .claude,
            accountID: .primary,
            displayName: "Claude",
            result: UsageProviderFetchResult(
                snapshot: .pending(for: .claude),
                capability: .confirmedAbsent
            )
        )
        let store = UsageStore(providers: [provider], preferences: freshPreferences())

        await store.refreshAll()

        #expect(store.snapshot(for: .claude).windows.isEmpty)
        #expect(store.snapshot(for: .claude).freshness == .pending)
        #expect(store.providerCapabilities[.claude]?.state == .confirmedAbsent)
    }

    @Test func confirmedClaudeAbsencePreservesRetainedUsage() async {
        let capture = Date(timeIntervalSince1970: 2_000_000)
        let refresh = capture.addingTimeInterval(300)
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let defaults = freshContinuityDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: .distantFuture),
            ], at: capture),
            for: key
        )
        let provider = CapabilityStubProvider(
            id: .claude,
            accountID: .primary,
            displayName: "Claude",
            result: UsageProviderFetchResult(
                snapshot: .pending(for: .claude),
                capability: .confirmedAbsent
            )
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { refresh }
        )

        await store.refreshAll()

        let retained = store.snapshot(for: key)
        #expect(retained.capturedAt == capture)
        #expect(retained.windows.first?.utilization == 25)
        #expect(retained.windows.first?.freshness == .stale(observedAt: capture))
        #expect(store.providerCapabilities[.claude]?.state == .confirmedAbsent)
    }

    @Test func claudeCapabilityFailurePreservesPriorAccountSetupState() async {
        let provider = MutableCapabilityStubProvider(
            id: .claude,
            displayName: "Claude",
            result: UsageProviderFetchResult(
                snapshot: .stale(for: .claude, reason: .providerSetup(.claudeTrustRequired)),
                capability: .available
            )
        )
        let store = UsageStore(providers: [provider], preferences: freshPreferences())
        await store.refreshAll()
        #expect(store.snapshot(for: .claude).freshness == .stale(.providerSetup(.claudeTrustRequired)))

        provider.setResult(UsageProviderFetchResult(
            snapshot: .stale(for: .claude, reason: .transient("Claude capability unavailable")),
            capability: .inconclusive(.shellTimeout)
        ))
        await store.refreshAll()

        #expect(store.snapshot(for: .claude).freshness == .stale(.providerSetup(.claudeTrustRequired)))
        #expect(store.providerCapabilities[.claude]?.state == .inconclusive(.shellTimeout))
    }

    @Test func providerCapabilityFailureDoesNotSettleAccountSetupSession() async {
        let account = ProviderAccount.builtIn(for: .claude)
        let provider = CapabilityStubProvider(
            id: .claude,
            accountID: .primary,
            displayName: "Claude",
            result: UsageProviderFetchResult(
                snapshot: .stale(for: .claude, reason: .transient("Claude capability unavailable")),
                capability: .inconclusive(.shellTimeout)
            )
        )
        let store = UsageStore(providers: [provider], preferences: freshPreferences())
        let coordinator = SetupSessionCoordinator(
            retryDelays: [.seconds(60)],
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
        store.attachSetupCoordinator(coordinator)
        coordinator.begin(for: account)
        for _ in 0..<20 where coordinator.state(for: account.key) != .waiting(attempt: 0) {
            await Task.yield()
        }

        await store.refreshAll()

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    @Test func relaunchMarksExpiredCachedClaudeSubLimitUnavailable() {
        let restorationDate = Date(timeIntervalSince1970: 2_000_000)
        let capturedAt = restorationDate.addingTimeInterval(-3_600)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 39,
                    resetsAt: restorationDate.addingTimeInterval(-1)
                ),
            ], at: capturedAt),
            for: key
        )

        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { restorationDate }
        )

        #expect(store.snapshot(for: key).windows.map(\.kind) == [.other("Weekly (Fable)")])
        #expect(
            store.snapshot(for: key).windows.first?.freshness
                == .unavailable(since: restorationDate.addingTimeInterval(-1))
        )
        if case .stale = store.snapshot(for: key).freshness {} else {
            Issue.record("restored unavailable data should remain globally stale until refresh")
        }
    }

    @Test func relaunchDropsOnlyExpiredCachedWindows() {
        let restorationDate = Date(timeIntervalSince1970: 2_000_000)
        let defaults = freshContinuityDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 5, resetsAt: restorationDate.addingTimeInterval(-1)),
                UsageWindow(kind: .weekly, utilization: 25, resetsAt: restorationDate.addingTimeInterval(1)),
            ], at: restorationDate.addingTimeInterval(-60)),
            for: key
        )

        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: freshPreferences(),
            continuityCache: cache,
            now: { restorationDate }
        )

        #expect(store.snapshot(for: key).windows.map(\.kind) == [.weekly])
    }

    @Test func cachedWindowsNeverCrossAccountBoundaries() {
        let defaults = freshContinuityDefaults()
        let otherAccount = AccountKey(providerID: .claude, accountID: AccountID("work"))
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 39, resetsAt: .distantFuture),
            ]),
            for: otherAccount
        )

        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: freshPreferences(),
            continuityCache: cache
        )

        #expect(store.snapshot(for: .claude).windows.isEmpty)
        #expect(store.snapshot(for: .claude).freshness == .pending)
    }

    @Test func startIsIdempotent() async {
        // A second start() (e.g. the popover re-appearing) must not re-fetch or restart
        // the loop — the guard keeps exactly one initial refresh.
        let provider = CountingProvider(id: .claude)
        let store = makeStore(providers: [provider])
        await store.start()
        await store.start()
        #expect(provider.fetchCount == 1)
    }

    @Test func concurrentStartCoalescesInitialRefresh() async {
        let provider = SlowCountingProvider(id: .claude)
        let store = makeStore(providers: [provider])

        let firstStart = Task { await store.start() }
        await provider.waitUntilFetchStarts()
        let secondStart = Task { await store.start() }

        await secondStart.value
        #expect(provider.fetchCount == 1)

        provider.releaseFetch()
        await firstStart.value
        #expect(provider.fetchCount == 1)
    }

    @Test func startExportsRefreshedWidgetSnapshotWithoutClobberingCacheFirst() async {
        let exporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                ])),
            ],
            widgetExporter: exporter
        )

        await store.start()

        let exports = exporter.exports
        #expect(exports.count == 1)
        #expect(exports.first?.providers.first?.freshness == .live)
        #expect(exports.first?.providers.first?.weeklyWindow?.percentRemaining == 75)
    }

    @Test func menuBarSummaryDefaultsToLowestWeeklyWithIdentity() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 95, resetsAt: reset),     // ignored: 5h
                UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),       // 30% left
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),     // ignored: 5h
                UsageWindow(kind: .weekly, utilization: 80, resetsAt: reset),       // 20% left <- lowest weekly
            ])),
        ])
        await store.refreshAll()
        let summary = store.menuBarSummary
        #expect(summary.text == "20%")
        #expect(summary.providerID == .codex)
        #expect(summary.detail == "Codex weekly")
        #expect(!summary.isNeutral)
        #expect(summary.severity == .low)         // 20% left -> amber, not healthy
        #expect(!summary.needsAttention)
    }

    @Test func menuBarSummaryTracksSelectedProviderWeekly() async {
        let store = makeStore(source: .claude, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 95, resetsAt: reset),     // ignored: 5h
                UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),       // 60% left
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 90, resetsAt: reset),       // ignored: source is Claude
            ])),
        ])
        await store.refreshAll()
        let summary = store.menuBarSummary
        #expect(summary.text == "60%")
        #expect(summary.providerID == .claude)
        #expect(summary.detail == "Claude weekly")
        #expect(summary.severity == .healthy)
    }

    @Test func menuBarSummaryCarriesSeverityOfWeeklyWindow() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 95, resetsAt: reset),   // ignored: 5h
                UsageWindow(kind: .weekly, utilization: 88, resetsAt: reset),     // 12% left -> critical
            ])),
        ])
        await store.refreshAll()
        #expect(store.menuBarSummary.severity == .critical)
    }

    @Test func menuBarSummaryFlagsPermanentFailureEvenWhenNeutral() async {
        // A logged-out provider with no live data still surfaces attention in the bar.
        let store = makeStore(providers: [
            StubProvider(id: .codex, displayName: "Codex",
                         snapshot: .stale(for: .codex, reason: .needsReauth("Run `codex login`"))),
        ])
        await store.refreshAll()
        let summary = store.menuBarSummary
        #expect(summary.isNeutral)          // no live number to show
        #expect(summary.needsAttention)     // …but the glyph should still warn
    }

    @Test func transientFailureDoesNotFlagAttention() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
            ])),
            StubProvider(id: .codex, displayName: "Codex",
                         snapshot: .stale(for: .codex, reason: .transient("blip"))),
        ])
        await store.refreshAll()
        #expect(!store.menuBarSummary.needsAttention)   // transient ≠ needs the user
    }

    @Test func menuBarPercentageVisibilityPersistsThroughStore() {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: preferences
        )

        #expect(!store.showMenuBarPercentage)
        store.setShowMenuBarPercentage(true)
        #expect(store.showMenuBarPercentage)
        #expect(preferences.showMenuBarPercentage)
    }

    @Test func percentageModePersistsAndRecomputesMenuBarPresentation() async {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .claude
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 73, resetsAt: reset),
                ])),
            ],
            preferences: preferences
        )
        await store.refreshAll()

        #expect(store.usagePercentageMode == .remaining)
        #expect(store.menuBarSummary.text == "27%")
        #expect(store.menuBarSummary.percentageMode == .remaining)
        #expect(store.menuBarFill == 0.27)
        let severity = store.menuBarSummary.severity

        store.setUsagePercentageMode(.used)

        #expect(store.usagePercentageMode == .used)
        #expect(preferences.usagePercentageMode == .used)
        #expect(store.menuBarSummary.text == "73%")
        #expect(store.menuBarSummary.percentageMode == .used)
        #expect(store.menuBarFill == 0.73)
        #expect(store.menuBarSummary.severity == severity)
    }

    @Test func meterStyleSeedsPersistsAndNeverTriggersWidgetExport() {
        let preferences = freshPreferences()
        preferences.meterFormat = .full
        preferences.meterShape = .tube
        preferences.meterFill = .ghost
        let exporter = SpyWidgetExporter()
        let phoneExporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
            ],
            preferences: preferences,
            widgetExporter: exporter,
            phoneSyncExporter: phoneExporter
        )

        #expect(store.meterStyle == MeterStyle(format: .full, shape: .tube, fill: .ghost))

        let updated = MeterStyle(format: .micro, shape: .segmented, fill: .hueRamp)
        store.setMeterStyle(updated)

        #expect(store.meterStyle == updated)
        #expect(preferences.meterFormat == updated.format)
        #expect(preferences.meterShape == updated.shape)
        #expect(preferences.meterFill == updated.fill)
        #expect(exporter.exports.isEmpty)
        #expect(phoneExporter.exports.isEmpty)
    }

    @Test func menuBarFillTracksSelectedProviderWeekly() async {
        let store = makeStore(source: .claude, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),   // ignored
                UsageWindow(kind: .weekly, utilization: 65, resetsAt: reset),     // 35% left
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 5, resetsAt: reset),
            ])),
        ])
        await store.refreshAll()
        #expect(store.menuBarFill == 0.35)   // Claude weekly, not the tighter Codex or 5h
    }

    @Test func menuBarFillIsNilWhenSourceIsNone() async {
        let store = makeStore(source: .none, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),
            ])),
        ])
        await store.refreshAll()
        #expect(store.menuBarFill == nil)    // decoupled → static glyph
    }

    @Test func menuBarFillFallsBackWhenPreferredWindowIsUnavailable() async {
        let store = makeStore(source: .codex, providers: [
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),   // no weekly
            ])),
        ])
        await store.refreshAll()
        #expect(store.menuBarWindowSource(for: .codex) == .weekly)
        #expect(store.resolvedMenuBarWindowSource(for: .codex) == .fiveHour)
        #expect(store.menuBarFill == 0.8)
    }

    @Test func preferredWindowResumesWhenProviderReportsItAgain() async {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .codex
        preferences.setMenuBarWindowSource(.fiveHour, for: .codex)
        let provider = MutableStubProvider(
            id: .codex,
            displayName: "Codex",
            snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),
            ])
        )
        let store = UsageStore(providers: [provider], preferences: preferences)

        await store.refreshAll()
        #expect(store.resolvedMenuBarWindowSource(for: .codex) == .weekly)
        #expect(store.menuBarSummary.text == "30%")

        provider.set(.live(.codex, windows: [
            UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),
            UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),
        ]))
        await store.refreshAll()

        #expect(store.menuBarWindowSource(for: .codex) == .fiveHour)
        #expect(store.resolvedMenuBarWindowSource(for: .codex) == .fiveHour)
        #expect(store.menuBarSummary.text == "80%")
        #expect(store.menuBarSummary.detail == "Codex 5h")
    }

    @Test func menuBarProviderSelectionDropsProvidersMissingFromRegistry() {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: preferences
        )

        #expect(store.menuBarFillSource == .none)   // default
        store.setMenuBarFillSource(.both)
        #expect(store.menuBarFillSource == .providers([.claude]))
        #expect(preferences.menuBarFillSource == .providers([.claude]))
    }

    @Test func threeProviderMenuBarSetUsesRegistryOrderAcrossReloads() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        preferences.menuBarFillSource = .providers([.grok, .claude, .codex])
        let providers: [any UsageProvider] = [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 10, resetsAt: reset),
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
            ])),
            StubProvider(id: .grok, displayName: "Grok", snapshot: .live(.grok, windows: [
                UsageWindow(kind: .billingPeriod(label: "Monthly", duration: 30 * 86_400), utilization: 30, resetsAt: reset),
            ])),
        ]
        let store = UsageStore(providers: providers, preferences: preferences)
        await store.refreshAll()

        #expect(store.menuBarMeters.map(\.summary.providerID) == [.claude, .codex, .grok])
        let reloaded = UsageStore(providers: providers, preferences: preferences)
        await reloaded.refreshAll()
        #expect(reloaded.menuBarMeters.map(\.summary.providerID) == [.claude, .codex, .grok])
    }

    @Test func billingPeriodOnlyProviderFallsBackToItsRealWindow() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        preferences.menuBarFillSource = .providers([.grok])
        let store = UsageStore(providers: [
            StubProvider(id: .grok, displayName: "Grok", snapshot: .live(.grok, windows: [
                UsageWindow(
                    kind: .billingPeriod(label: "Monthly", duration: 30 * 86_400),
                    utilization: 36,
                    resetsAt: reset
                ),
            ])),
        ], preferences: preferences)
        await store.refreshAll()

        #expect(store.menuBarMeters.map(\.summary.text) == ["64%"])
        #expect(store.menuBarMeters.map(\.summary.detail) == ["Grok monthly"])
        #expect(store.resolvedMenuBarWindowSource(for: .grok) == nil)
        #expect(!store.hasSelectableMenuBarWindows(for: .grok))
    }

    @Test func menuBarMetersDefaultToSingleSummary() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 88, resetsAt: reset),
            ])),
        ])
        await store.refreshAll()
        let meters = store.menuBarMeters
        #expect(meters.count == 1)
        #expect(meters[0].summary.providerID == .codex)
        #expect(meters[0].summary.severity == .critical)
        #expect(meters[0].fill == nil)      // `.none` uses static vessel level.
    }

    @Test func menuBarMetersCanShowClaudeAndCodexSideBySide() async {
        let store = makeStore(source: .both, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 35, resetsAt: reset),      // 65% left
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 88, resetsAt: reset),      // 12% left
            ])),
        ])
        await store.refreshAll()
        let meters = store.menuBarMeters
        #expect(meters.count == 2)
        #expect(meters[0].summary.providerID == .claude)
        #expect(meters[0].summary.text == "65%")
        #expect(meters[0].summary.severity == .healthy)
        #expect(meters[0].fill == 0.65)
        #expect(meters[1].summary.providerID == .codex)
        #expect(meters[1].summary.text == "12%")
        #expect(meters[1].summary.severity == .critical)
        #expect(meters[1].fill == 0.12)
    }

    @Test func menuBarMetersUseIndependentProviderWindowSources() async {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .both
        preferences.setMenuBarWindowSource(.fiveHour, for: .codex)
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 60, resetsAt: reset),
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .fiveHour, utilization: 25, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 90, resetsAt: reset),
            ])),
        ], preferences: preferences)

        await store.refreshAll()

        #expect(store.menuBarWindowSource(for: .claude) == .weekly)
        #expect(store.menuBarWindowSource(for: .codex) == .fiveHour)
        #expect(store.menuBarMeters.map(\.summary.text) == ["40%", "75%"])
        #expect(store.menuBarMeters.map(\.summary.detail) == ["Claude weekly", "Codex 5h"])
    }

    @Test func usedModeAppliesToBothProviderMenuBarMeters() async {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .both
        preferences.usagePercentageMode = .used
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 35, resetsAt: reset),
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 88, resetsAt: reset),
            ])),
        ], preferences: preferences)

        await store.refreshAll()

        let meters = store.menuBarMeters
        #expect(meters.map(\.summary.text) == ["35%", "88%"])
        #expect(meters.map(\.summary.percentageMode) == [.used, .used])
        #expect(meters.map(\.fill) == [0.35, 0.88])
        #expect(meters.map(\.summary.severity) == [.healthy, .critical])
    }

    @Test func menuBarMetersInBothModeKeepProviderSpecificAttention() async {
        let store = makeStore(source: .both, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 10, resetsAt: reset),
            ])),
            StubProvider(id: .codex, displayName: "Codex",
                         snapshot: .stale(for: .codex, reason: .needsReauth("Run `codex login`"))),
        ])
        await store.refreshAll()
        let meters = store.menuBarMeters
        #expect(meters.count == 2)
        #expect(!meters[0].summary.needsAttention)
        #expect(meters[1].summary.providerID == .codex)
        #expect(meters[1].summary.isNeutral)
        #expect(meters[1].summary.needsAttention)
        #expect(meters[1].fill == nil)
    }

    @Test func appDisplaySnapshotCanHideCodexSparkCountersOnly() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        preferences.showCodexSparkCountersInApp = false
        let store = UsageStore(providers: [
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                UsageWindow(kind: .other("codex-spark 5h"), utilization: 40, resetsAt: reset),
                UsageWindow(kind: .other("GPT-5.3"), utilization: 50, resetsAt: reset),
            ])),
        ], preferences: preferences)

        await store.refreshAll()

        #expect(store.snapshot(for: .codex).windows.count == 3)
        #expect(store.appDisplaySnapshot(for: .codex).windows.map(\.kind) == [
            .weekly,
            .other("GPT-5.3"),
        ])

        store.setShowCodexSparkCountersInApp(true)
        #expect(store.appDisplaySnapshot(for: .codex).windows.count == 3)
    }

    @Test func menuBarWindowSourcePersistsPerProviderAndUpdatesPresentation() async {
        let preferences = freshPreferences()
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),   // 80% left
                UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),     // 30% left
            ])),
        ], preferences: preferences)

        await store.refreshAll()

        // Default: weekly drives the number and tooltip.
        #expect(store.menuBarSummary.text == "30%")
        #expect(store.menuBarSummary.detail == "Claude weekly")

        store.setMenuBarWindowSource(.fiveHour, for: .claude)
        #expect(store.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(preferences.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(store.menuBarSummary.text == "80%")
        #expect(store.menuBarSummary.detail == "Claude 5h")
    }

    @Test func appDisplaySnapshotOrdersWeeklyFirst() async {
        // Providers emit 5-hour first; the popover shows weekly first to match the
        // widgets. Unknown windows keep their provider-given order after the pair.
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 40, resetsAt: reset),
            ])),
        ])

        await store.refreshAll()

        #expect(store.appDisplaySnapshot(for: .claude).windows.map(\.kind) == [
            .weekly,
            .fiveHour,
            .other("Weekly (Fable)"),
        ])
        // The raw snapshot (widget export, menu bar) is untouched.
        #expect(store.snapshot(for: .claude).windows.first?.kind == .fiveHour)
    }


    @Test func appDisplaySnapshotRanksPeriodWithWeeklyAheadOfFiveHour() async {
        let monthly = WindowKind.billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60)
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        let store = UsageStore(
            providers: [StubProvider(id: .grok, displayName: "Grok", snapshot: .live(.grok, windows: [
                UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
                UsageWindow(kind: monthly, utilization: 20, resetsAt: reset),
                UsageWindow(kind: .other("Pool"), utilization: 30, resetsAt: reset),
            ]))],
            preferences: preferences
        )

        await store.refreshAll()

        #expect(store.appDisplaySnapshot(for: .grok).windows.map(\.kind) == [monthly, .fiveHour, .other("Pool")])
    }

    /// Fresh-suite preferences so tests never read the developer's real UserDefaults —
    /// a persisted menu-bar window source from actually using the app was leaking into
    /// the default-behavior expectations.
    private func freshPreferences() -> Preferences {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Preferences(defaults: defaults)
    }

    private func freshContinuityDefaults() -> UserDefaults {
        let suite = "headroom.continuity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Default-behavior store: stub providers on isolated (all-default) preferences.
    private func makeStore(providers: [any UsageProvider]) -> UsageStore {
        UsageStore(providers: providers, preferences: freshPreferences())
    }

    /// Store whose menu-bar fill source is pre-set, on an isolated defaults suite.
    private func makeStore(source: MenuBarFillSource, providers: [any UsageProvider]) -> UsageStore {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = source
        return UsageStore(providers: providers, preferences: preferences)
    }

    @Test func refreshExportsWidgetSnapshot() async {
        let exporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                ])),
            ],
            widgetExporter: exporter
        )

        await store.refreshAll()

        let exports = exporter.exports
        #expect(exports.count == 1)
        #expect(exports[0].providers[0].id == "claude")
        #expect(exports[0].providers[0].weeklyWindow?.percentRemaining == 70)
    }

    @Test func widgetSelectionDefaultsToFirstTwoEnabledProviders() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        let exporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
                StubProvider(id: .codex, displayName: "Codex", snapshot: .pending(for: .codex)),
                StubProvider(id: .grok, displayName: "Grok", snapshot: .pending(for: .grok)),
            ],
            preferences: preferences,
            widgetExporter: exporter
        )

        await store.refreshAll()

        #expect(exporter.exports.last?.widgetProviderSelection == ["claude", "codex"])
    }

    @Test func widgetSelectionUsesPrioritySetInProviderOrderAndCapsAtTwo() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        preferences.setSurfaceEnabled(true, for: .cursorSubscription)
        preferences.menuBarFillSource = .providers([.claude, .grok, .cursor])
        let exporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
                StubProvider(id: .codex, displayName: "Codex", snapshot: .pending(for: .codex)),
                StubProvider(id: .grok, displayName: "Grok", snapshot: .pending(for: .grok)),
                StubProvider(id: .cursor, displayName: "Cursor", snapshot: .pending(for: .cursor)),
            ],
            preferences: preferences,
            widgetExporter: exporter
        )

        await store.refreshAll()

        #expect(exporter.exports.last?.widgetProviderSelection == ["claude", "grok"])
        #expect(exporter.exports.last?.widgetProviders.map(\.id) == ["claude", "grok"])
    }

    @Test func disablingWidgetsExportsDisabledState() {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let exporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: preferences,
            widgetExporter: exporter
        )

        store.setWidgetsEnabled(false)

        #expect(!preferences.widgetsEnabled)
        #expect(exporter.exports.last?.status == .disabled)
        #expect(exporter.exports.last?.providers.isEmpty == true)
    }

    @Test func enablingWidgetSparkCountersReexportsSnapshot() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let exporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                    UsageWindow(kind: .other("codex-spark weekly"), utilization: 60, resetsAt: reset),
                ])),
            ],
            preferences: preferences,
            widgetExporter: exporter
        )

        await store.refreshAll()
        #expect(exporter.exports.last?.providers.first?.windows.map(\.kind) == [.weekly])

        store.setShowCodexSparkCountersInWidgets(true)

        #expect(preferences.showCodexSparkCountersInWidgets)
        #expect(exporter.exports.last?.providers.first?.windows.map(\.kind) == [
            .weekly,
            .other("codex-spark weekly"),
        ])
    }

    @Test func phoneSyncDefaultsOffAndExportsOnlyWhenEnabled() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let phoneExporter = SpyWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
                ])),
            ],
            preferences: preferences,
            phoneSyncExporter: phoneExporter
        )

        await store.refreshAll()
        #expect(!store.syncToIPhoneEnabled)
        #expect(phoneExporter.exports.last?.status == .disabled)
        #expect(phoneExporter.exports.last?.providers.isEmpty == true)

        store.setSyncToIPhoneEnabled(true)
        #expect(preferences.syncToIPhoneEnabled)
        #expect(phoneExporter.exports.last?.providers.first?.weeklyWindow?.percentRemaining == 80)
    }

    @Test func phoneSyncFailureDoesNotFailRefreshOrMutateProviderFreshness() async {
        let failingExporter = FailingWidgetExporter()
        let store = UsageStore(
            providers: [
                StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 10, resetsAt: reset),
                ])),
            ],
            phoneSyncExporter: failingExporter
        )

        await store.refreshAll()

        #expect(store.snapshot(for: .codex).freshness == .live)
        #expect(failingExporter.exportCount == 1)
    }

    @Test func apiSpendProvidersOnlyFetchWhenEnabled() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let spend = CountingSpendProvider(id: .codex, displayName: "OpenAI API")
        let store = UsageStore(
            providers: [],
            apiSpendProviders: [spend],
            preferences: preferences
        )

        await store.refreshAll()
        #expect(spend.fetchCount == 0)
        #expect(store.apiSpendProviderOrder.isEmpty)

        store.setSurfaceEnabled(true, for: .openAIAPI)
        await store.refreshAll()
        #expect(spend.fetchCount == 1)
        #expect(store.apiSpendProviderOrder == [.codex])
        #expect(store.apiSpendSnapshot(for: .codex).freshness == .live)
    }

    @Test func liveNonApplicableSpendIsHidden() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .cursorAPI)
        let spend = CountingSpendProvider(
            id: .cursor,
            displayName: "Cursor on-demand",
            snapshot: APISpendSnapshot(
                providerID: .cursor,
                displayName: "Cursor on-demand",
                amount: nil,
                currency: nil,
                periodLabel: "Resets Sep 1",
                capturedAt: Date(timeIntervalSince1970: 1_000),
                freshness: .live
            )
        )
        let store = UsageStore(
            providers: [],
            apiSpendProviders: [spend],
            preferences: preferences
        )

        #expect(store.apiSpendProviderOrder == [.cursor])
        await store.refreshAll()
        #expect(spend.fetchCount == 1)
        #expect(store.apiSpendProviderOrder.isEmpty)
    }

    @Test func surfaceToggleUpdatesObservableStateImmediately() {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let store = UsageStore(providers: [], preferences: preferences)

        #expect(!store.isSurfaceEnabled(.openAIAPI))
        store.setSurfaceEnabled(true, for: .openAIAPI)

        #expect(store.isSurfaceEnabled(.openAIAPI))
        #expect(store.enabledSurfaces.contains(.openAIAPI))
        #expect(preferences.isSurfaceEnabled(.openAIAPI))
    }

    @Test func unknownSubscriptionProviderIsExcludedInsteadOfUsingCodexSurface() {
        let unknown = ProviderID("future-provider")
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .codexSubscription)
        let store = UsageStore(
            providers: [StubProvider(id: unknown, displayName: "Future", snapshot: .pending(for: unknown))],
            preferences: preferences
        )

        #expect(store.providerOrder.isEmpty)
    }

    @Test func grokSubscriptionUsesItsOwnSurfaceToggle() {
        let preferences = freshPreferences()
        let provider = StubProvider(
            id: .grok,
            displayName: "Grok",
            snapshot: .pending(for: .grok)
        )
        let store = UsageStore(providers: [provider], preferences: preferences)

        #expect(store.providerOrder.isEmpty)
        store.setSurfaceEnabled(true, for: .grokSubscription)
        #expect(store.providerOrder == [.grok])
    }

    @Test func apiSpendOnlyRefreshDoesNotFetchSubscriptions() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let subscription = CountingProvider(id: .claude, displayName: "Claude")
        let spend = CountingSpendProvider(id: .codex, displayName: "OpenAI API")
        let store = UsageStore(
            providers: [subscription],
            apiSpendProviders: [spend],
            preferences: preferences
        )

        store.setSurfaceEnabled(true, for: .openAIAPI)
        await store.refreshAPISpendOnly()

        #expect(subscription.fetchCount == 0)
        #expect(spend.fetchCount == 1)
        #expect(store.apiSpendSnapshot(for: .codex).freshness == .live)
    }

    @Test func apiSpendOnlyRefreshExportsWidgetAndPhoneSnapshots() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        preferences.syncToIPhoneEnabled = true
        let widgetExporter = SpyWidgetExporter()
        let phoneExporter = SpyWidgetExporter()
        let spend = CountingSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: APISpendSnapshot(
            providerID: .codex,
            displayName: "OpenAI API",
            amount: 8.5,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date(timeIntervalSince1970: 4_000),
            freshness: .live
        ))
        let store = UsageStore(
            providers: [],
            apiSpendProviders: [spend],
            preferences: preferences,
            widgetExporter: widgetExporter,
            phoneSyncExporter: phoneExporter
        )

        store.setSurfaceEnabled(true, for: .openAIAPI)
        await store.refreshAPISpendOnly()

        #expect(widgetExporter.exports.last?.apiSpendProviders.first?.displayName == "OpenAI API")
        #expect(widgetExporter.exports.last?.apiSpendProviders.first?.amount == 8.5)
        #expect(phoneExporter.exports.last?.apiSpendProviders.first?.amount == 8.5)
    }

    @Test func apiSpendSurfaceToggleReexportsRemovedSpend() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        let exporter = SpyWidgetExporter()
        let spend = CountingSpendProvider(id: .codex, displayName: "OpenAI API")
        let store = UsageStore(
            providers: [],
            apiSpendProviders: [spend],
            preferences: preferences,
            widgetExporter: exporter
        )

        store.setSurfaceEnabled(true, for: .openAIAPI)
        await store.refreshAPISpendOnly()
        #expect(exporter.exports.last?.apiSpendProviders.map(\.id) == ["codex"])

        store.setSurfaceEnabled(false, for: .openAIAPI)

        #expect(exporter.exports.last?.apiSpendProviders.isEmpty == true)
    }
}
