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

    /// KTD6.2 (review #16): the menu bar prints, inks and fills from the same normalized
    /// reading as the popover row, so a fractional source can't read 16% in one and 15% in
    /// the other.
    @Test(arguments: [15.46, 15.05, 84.54, 15.04])
    func menuBarAgreesWithThePopoverReading(remaining: Double) async {
        let window = UsageWindow(kind: .weekly, utilization: 100 - remaining, resetsAt: reset)
        let reading = UsageMeterReading(window: window)
        for source in [MenuBarFillSource.auto, .claude] {
            let store = makeStore(source: source, providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [window])),
            ])
            await store.refreshAll()
            for mode in UsagePercentageMode.allCases {
                store.setUsagePercentageMode(mode)
                let printed = "\(reading.roundedPercentage(for: mode)!)%"
                // The pill arranger and Settings print through this same helper.
                #expect(mode.displayedPercentage(for: window) == reading.roundedPercentage(for: mode))
                #expect(store.menuBarSummary.text == printed)
                #expect(store.menuBarSummary.severity == reading.severity)
                let meter = store.providerMenuBarMeter(for: .claude)
                #expect(meter.summary.text == printed)
                #expect(meter.summary.severity == reading.severity)
                #expect(meter.fill == reading.fraction(for: mode))
                if source == .claude {
                    #expect(store.menuBarFill == reading.fraction(for: mode))
                }
            }
        }
    }

    @Test func menuBarPrintsTheNormalizedTenthLikeThePopover() async {
        let store = makeStore(source: .claude, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 84.54, resetsAt: reset),  // 15.46 left
            ])),
        ])
        await store.refreshAll()
        #expect(store.menuBarSummary.text == "16%")
        store.setUsagePercentageMode(.used)
        #expect(store.menuBarSummary.text == "85%")
        #expect(UsagePercentageMode.remaining.displayedPercentage(
            for: UsageWindow(kind: .weekly, utilization: 84.54, resetsAt: reset)) == 16)
        // A row the popover hides prints no figure on the other surfaces either.
        #expect(UsagePercentageMode.remaining.displayedPercentage(
            for: UsageWindow(kind: .weekly, utilization: 84.54, resetsAt: reset,
                             freshness: .unavailable(since: reset))) == nil)
    }

    /// G1A: popover-only, so the store mirrors the choice and writes it back without
    /// touching any projection — and a repeat set is a no-op.
    @Test func accountTitleInkSeedsPersistsAndNoOpsWhenUnchanged() {
        let preferences = freshPreferences()
        preferences.accountTitleInk = .brand
        preferences.syncToIPhoneEnabled = true
        let exporter = SpyWidgetExporter()
        let phoneExporter = SpyPhoneSync()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
            ],
            preferences: preferences,
            widgetExporter: exporter,
            phoneSyncExporter: phoneExporter
        )

        #expect(store.accountTitleInk == .brand)

        store.setAccountTitleInk(.neutral)
        #expect(store.accountTitleInk == .neutral)
        #expect(preferences.accountTitleInk == .neutral)

        // Proof the repeat set really short-circuits: nudge the stored value behind the
        // store's back, then re-set the value the store already holds. A guard-less
        // implementation would write `.neutral` back over it.
        preferences.accountTitleInk = .brand
        store.setAccountTitleInk(.neutral)
        #expect(store.accountTitleInk == .neutral)
        #expect(preferences.accountTitleInk == .brand)
        // Mac widgets carry no ink; the phone's display block does (iPhone parity KTD11),
        // so the one real change reached the phone once and the repeat set did not.
        #expect(exporter.exports.isEmpty)
        #expect(phoneExporter.captures.count == 1)
        #expect(phoneExporter.last?.display?.accountTitleInk == .neutral)
    }

    /// KTD8: the account layout sizes the Mac popover only, so the store mirrors it without
    /// reaching the widgets or the phone, and a repeat set is a no-op.
    @Test func accountLayoutSeedsPersistsAndStaysOffEveryProjection() {
        let preferences = freshPreferences()
        preferences.accountLayout = .compact
        preferences.syncToIPhoneEnabled = true
        let exporter = SpyWidgetExporter()
        let phoneExporter = SpyPhoneSync()
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
            ],
            preferences: preferences,
            widgetExporter: exporter,
            phoneSyncExporter: phoneExporter
        )

        #expect(store.accountLayout == .compact)

        store.setAccountLayout(.standard)
        #expect(store.accountLayout == .standard)
        #expect(preferences.accountLayout == .standard)

        preferences.accountLayout = .compact
        store.setAccountLayout(.standard)
        #expect(store.accountLayout == .standard)
        #expect(preferences.accountLayout == .compact)
        #expect(exporter.exports.isEmpty)
        #expect(phoneExporter.captures.isEmpty)
    }

    @Test func meterStyleSeedsPersistsAndNeverTriggersWidgetExport() {
        let preferences = freshPreferences()
        preferences.meterFormat = .full
        preferences.meterShape = .tube
        preferences.meterFill = .ghost
        preferences.syncToIPhoneEnabled = true
        let exporter = SpyWidgetExporter()
        let phoneExporter = SpyPhoneSync()
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
        // KTD11: the meter style travels in the phone's display block, never to widgets.
        #expect(phoneExporter.captures.count == 1)
        #expect(phoneExporter.last?.display?.meterStyle == updated)

        store.setMeterStyle(updated)
        #expect(exporter.exports.isEmpty)
        #expect(phoneExporter.captures.count == 1)
    }

    @Test func exportedWidgetSnapshotIsInvariantAcrossEveryMeterStyle() async throws {
        let generatedAt = Date(timeIntervalSince1970: 2_100_000_000)
        let snapshot = UsageSnapshot.live(
            .claude,
            windows: [
                UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),
                UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
            ],
            plan: "max",
            at: generatedAt.addingTimeInterval(-60)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        func encodedExport(for style: MeterStyle) async throws -> Data {
            let preferences = freshPreferences()
            preferences.meterStyle = style
            let exporter = SpyWidgetExporter()
            let store = UsageStore(
                providers: [
                    StubProvider(id: .claude, displayName: "Claude", snapshot: snapshot),
                ],
                preferences: preferences,
                widgetExporter: exporter
            )
            await store.refreshAll()
            store.exportWidgetSnapshot(generatedAt: generatedAt)
            return try encoder.encode(#require(exporter.exports.last))
        }

        let baseline = try await encodedExport(for: .default)
        for format in GaugeFormat.allCases {
            for shape in GaugeShape.allCases {
                for fill in GaugeFill.allCases {
                    let style = MeterStyle(format: format, shape: shape, fill: fill)
                    #expect(try await encodedExport(for: style) == baseline)
                }
            }
        }
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
        #expect(store.menuBarWindowChoice(for: .codex) == .weekly)
        #expect(store.resolvedMenuBarWindowKind(for: .codex) == .fiveHour)
        #expect(store.menuBarFill == 0.8)
    }

    @Test func preferredWindowResumesWhenProviderReportsItAgain() async {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .codex
        preferences.setMenuBarWindowChoice(.fiveHour, for: .codex)
        let provider = MutableStubProvider(
            id: .codex,
            displayName: "Codex",
            snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),
            ])
        )
        let store = UsageStore(providers: [provider], preferences: preferences)

        await store.refreshAll()
        #expect(store.resolvedMenuBarWindowKind(for: .codex) == .weekly)
        #expect(store.menuBarSummary.text == "30%")

        provider.set(.live(.codex, windows: [
            UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),
            UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),
        ]))
        await store.refreshAll()

        #expect(store.menuBarWindowChoice(for: .codex) == .fiveHour)
        #expect(store.resolvedMenuBarWindowKind(for: .codex) == .fiveHour)
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

    @Test func menuBarArrangerAddsMovesAndRemovesWithoutChangingOtherPreferences() {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        preferences.setSurfaceEnabled(true, for: .cursorSubscription)
        preferences.showMenuBarPercentage = true
        preferences.setMenuBarWindowChoice(.fiveHour, for: .codex)
        let ids: [ProviderID] = [.claude, .codex, .grok, .cursor]
        let providers: [any UsageProvider] = ids.map {
            StubProvider(id: $0, displayName: $0.raw, snapshot: .pending(for: $0))
        }
        let store = UsageStore(providers: providers, preferences: preferences)
        #expect(store.menuBarFillSource == .auto)
        for id in ids { store.addMenuBarProvider(id) }
        #expect(store.selectedMenuBarProviders == ids)
        store.moveMenuBarProvider(.cursor, before: .claude)
        #expect(store.selectedMenuBarProviders == [.cursor, .claude, .codex, .grok])
        store.moveMenuBarProvider(.claude, by: 1)
        #expect(store.selectedMenuBarProviders == [.cursor, .codex, .claude, .grok])
        store.moveMenuBarProvider(.cursor, before: nil)
        #expect(store.selectedMenuBarProviders == [.codex, .claude, .grok, .cursor])
        store.removeMenuBarProvider(.grok)
        store.addMenuBarProvider(.grok)
        #expect(store.selectedMenuBarProviders == [.codex, .claude, .cursor, .grok])
        #expect(store.providerOrder == ids)
        #expect(store.menuBarWindowChoice(for: .codex) == .fiveHour)
        store.setShowMenuBarPercentage(false)
        let reloaded = UsageStore(providers: providers, preferences: preferences)
        #expect(reloaded.selectedMenuBarProviders == store.selectedMenuBarProviders)
        #expect(!reloaded.showMenuBarPercentage)
        #expect(reloaded.menuBarWindowChoice(for: .codex) == .fiveHour)
    }

    /// The pill shelf drops a card between two pills, so an add can land at a position. It
    /// leaves the automatic summary exactly as the old "Add pill" button did.
    @Test func menuBarArrangerAddsAPillBeforeAVisiblePill() {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        preferences.setSurfaceEnabled(true, for: .cursorSubscription)
        let ids: [ProviderID] = [.claude, .codex, .grok, .cursor]
        let store = UsageStore(
            providers: ids.map { StubProvider(id: $0, displayName: $0.raw, snapshot: .pending(for: $0)) },
            preferences: preferences
        )
        #expect(store.menuBarFillSource == .auto)
        store.addMenuBarProvider(.codex, before: .claude)
        #expect(store.selectedMenuBarProviders == [.codex])
        store.addMenuBarProvider(.claude, before: .codex)
        #expect(store.selectedMenuBarProviders == [.claude, .codex])
        store.addMenuBarProvider(.grok, before: .codex)
        #expect(store.selectedMenuBarProviders == [.claude, .grok, .codex])
        // A target that is not a visible pill (here, the card being added) appends.
        store.addMenuBarProvider(.cursor, before: .cursor)
        #expect(store.selectedMenuBarProviders == [.claude, .grok, .codex, .cursor])
        // Already shown: the add is a no-op, not a move.
        store.addMenuBarProvider(.cursor, before: .claude)
        #expect(store.selectedMenuBarProviders == [.claude, .grok, .codex, .cursor])
    }

    @Test func menuBarArrangerRetainsDisabledProvidersAndRejectsInvalidEdits() {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .both
        preferences.menuBarProviderOrder = [.codex, ProviderID("unknown"), .codex, .claude]
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .pending(for: .codex)),
        ], preferences: preferences)
        #expect(store.selectedMenuBarProviders == [.codex, .claude])
        store.setSurfaceEnabled(false, for: .codexSubscription)
        #expect(store.selectedMenuBarProviders == [.claude])
        store.removeMenuBarProvider(.claude)
        store.addMenuBarProvider(.codex)
        store.addMenuBarProvider(ProviderID("unknown"))
        store.moveMenuBarProvider(.claude, before: ProviderID("unknown"))
        store.moveMenuBarProvider(.claude, by: Int.min)
        #expect(store.menuBarFillSource == .both)
        store.setSurfaceEnabled(true, for: .codexSubscription)
        #expect(store.selectedMenuBarProviders == [.codex, .claude])
        store.removeMenuBarProvider(.codex)
        store.removeMenuBarProvider(.claude)
        #expect(store.selectedMenuBarProviders == [.claude])
        store.setMenuBarFillSource(.auto)
        #expect(store.selectedMenuBarProviders.isEmpty)
        #expect(store.menuBarMeters.count == 1)
    }

    @Test func widgetSelectionCanChangeIndependentlyAndExportsImmediately() {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .both
        preferences.syncToIPhoneEnabled = true
        let exporter = SpyWidgetExporter()
        let phoneExporter = SpyWidgetExporter()
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .pending(for: .codex)),
        ], preferences: preferences, widgetExporter: exporter, phoneSyncExporter: phoneExporter)
        store.setWidgetPrioritySource(.codex)
        #expect(exporter.exports.last?.widgetProviderSelection == ["codex"])
        // iPhone widgets read the same selection from the phone envelope (R36).
        #expect(phoneExporter.exports.last?.widgetProviderSelection == ["codex"])
        #expect(store.menuBarFillSource == .both)
        store.setWidgetPrioritySource(.auto)
        #expect(preferences.widgetPriorityProviders == [])
        #expect(exporter.exports.last?.widgetProviderSelection == ["claude", "codex"])
        #expect(phoneExporter.exports.last?.widgetProviderSelection == ["claude", "codex"])
    }

    @Test func menuBarRestoresIndependentOrderForAllFourProviders() async {
        let defaults = UserDefaults(suiteName: "headroom.tests.\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        preferences.setSurfaceEnabled(true, for: .cursorSubscription)
        preferences.menuBarFillSource = .providers([.claude, .codex, .grok, .cursor])
        defaults.set(["cursor", "codex", "claude", "grok"], forKey: "menuBarProviderOrder")
        let ids: [ProviderID] = [.claude, .codex, .grok, .cursor]
        let providers = ids.map { StubProvider(id: $0, displayName: $0.raw, snapshot: .pending(for: $0)) }
        let exporter = SpyWidgetExporter()
        let store = UsageStore(providers: providers, preferences: preferences, widgetExporter: exporter)
        await store.refreshAll()

        #expect(store.menuBarMeters.map(\.summary.providerID) == [.cursor, .codex, .claude, .grok])
        #expect(store.providerOrder == ids)
        #expect(exporter.exports.last?.widgetProviderSelection == ["claude", "codex"])
        let reloaded = UsageStore(providers: providers, preferences: preferences)
        #expect(reloaded.menuBarMeters.map(\.summary.providerID) == [.cursor, .codex, .claude, .grok])
    }

    @Test func menuBarChangesPreserveExistingWidgetSelectionAcrossReloads() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .grokSubscription)
        preferences.menuBarFillSource = .providers([.claude, .grok])
        let providers: [any UsageProvider] = [ProviderID.claude, .codex, .grok].map {
            StubProvider(id: $0, displayName: $0.raw, snapshot: .pending(for: $0))
        }
        let store = UsageStore(providers: providers, preferences: preferences)
        store.setMenuBarFillSource(.codex)
        let exporter = SpyWidgetExporter()
        let reloaded = UsageStore(providers: providers, preferences: preferences, widgetExporter: exporter)
        await reloaded.refreshAll()
        #expect(reloaded.menuBarMeters.map(\.summary.providerID) == [.codex])
        #expect(exporter.exports.last?.widgetProviderSelection == ["claude", "grok"])
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
        #expect(store.resolvedMenuBarWindowKind(for: .grok) == .billingPeriod(label: "Monthly", duration: 30 * 86_400))
        #expect(!store.hasSelectableMenuBarWindows(for: .grok))
    }

    @Test func cursorMenuBarUsesTighterNamedPoolAndKeepsBothForAppDisplay() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .cursorSubscription)
        preferences.menuBarFillSource = .providers([.cursor])
        let duration = 30 * 86_400.0
        let cursorModels = WindowKind.billingPeriod(label: "Cursor Models", duration: duration)
        let otherModels = WindowKind.billingPeriod(label: "Other Models", duration: duration)
        let store = UsageStore(providers: [
            StubProvider(id: .cursor, displayName: "Cursor", snapshot: .live(.cursor, windows: [
                UsageWindow(kind: cursorModels, utilization: 31, resetsAt: reset),
                UsageWindow(kind: otherModels, utilization: 63, resetsAt: reset),
            ])),
        ], preferences: preferences)
        await store.refreshAll()

        #expect(store.menuBarSummary.text == "37%")
        #expect(store.menuBarSummary.detail == "Cursor other models")
        #expect(store.menuBarFill == 0.37)
        #expect(store.appDisplaySnapshot(for: .cursor).windows.map(\.kind) == [cursorModels, otherModels])
    }

    @Test func cursorMenuBarBreaksEqualPoolTieBySourceOrder() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .cursorSubscription)
        preferences.menuBarFillSource = .providers([.cursor])
        let duration = 30 * 86_400.0
        let store = UsageStore(providers: [
            StubProvider(id: .cursor, displayName: "Cursor", snapshot: .live(.cursor, windows: [
                UsageWindow(
                    kind: .billingPeriod(label: "Cursor Models", duration: duration),
                    utilization: 58,
                    resetsAt: reset
                ),
                UsageWindow(
                    kind: .billingPeriod(label: "Other Models", duration: duration),
                    utilization: 58,
                    resetsAt: reset
                ),
            ])),
        ], preferences: preferences)
        await store.refreshAll()

        #expect(store.menuBarSummary.detail == "Cursor cursor models")
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

    @Test func menuBarGhostTracksPendingMainsRatherThanNilFill() async {
        let pending = makeStore(source: .both, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .stale(for: .codex, reason: .notLoggedIn("signed out"))),
        ])
        #expect(pending.menuBarMeters.allSatisfy { $0.awaitingFirstReading })
        await pending.refreshAll()
        #expect(pending.menuBarMeters.map(\.awaitingFirstReading) == [true, false])
        #expect(pending.menuBarMeters.allSatisfy { $0.fill == nil })
        #expect(pending.menuBarMeters.map(\.sourceAccountKey) == [
            AccountKey(providerID: .claude, accountID: .primary), AccountKey(providerID: .codex, accountID: .primary),
        ])

        let unavailable = makeStore(source: .claude, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 10, resetsAt: reset, freshness: .unavailable(since: reset)),
            ])),
        ])
        await unavailable.refreshAll()
        #expect(unavailable.menuBarMeters[0].fill == nil)
        #expect(!unavailable.menuBarMeters[0].awaitingFirstReading)
    }

    @Test func automaticGhostNeedsNeutralSummaryAndAtLeastOnePendingMain() async {
        let mixed = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
            ])),
        ])
        #expect(mixed.menuBarMeters[0].awaitingFirstReading)
        await mixed.refreshAll()
        #expect(!mixed.menuBarMeters[0].awaitingFirstReading)
        #expect(mixed.menuBarMeters[0].isLiveReading)
        #expect(mixed.menuBarMeters[0].fill == nil)

        let signedOut = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .stale(for: .claude, reason: .notLoggedIn("signed out"))),
        ])
        await signedOut.refreshAll()
        #expect(!signedOut.menuBarMeters[0].awaitingFirstReading)
        #expect(!signedOut.menuBarMeters[0].isLiveReading)
    }

    @Test func menuBarFirstResultCarriesLiveProvenanceEvenWhenStaleHasANumber() async {
        let stale = UsageSnapshot(providerID: .claude, windows: [
            UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
        ], planLabel: nil, capturedAt: Date(), freshness: .stale(.transient("offline")))
        let store = makeStore(source: .claude, providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: stale),
        ])
        #expect(store.menuBarMeters[0].awaitingFirstReading)
        await store.refreshAll()
        #expect(!store.menuBarMeters[0].awaitingFirstReading)
        #expect(store.menuBarMeters[0].fill == 0.8)
        #expect(!store.menuBarMeters[0].isLiveReading)
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
        preferences.setMenuBarWindowChoice(.fiveHour, for: .codex)
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

        #expect(store.menuBarWindowChoice(for: .claude) == .weekly)
        #expect(store.menuBarWindowChoice(for: .codex) == .fiveHour)
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

    @Test func failedCodexPollKeepsLastKnownBankedResets() async {
        let provider = MutableStubProvider(id: .codex, displayName: "Codex", snapshot: UsageSnapshot(
            providerID: .codex,
            windows: [UsageWindow(kind: .weekly, utilization: 40, resetsAt: .distantFuture)],
            planLabel: "plus",
            bankedResets: 2,
            capturedAt: Date(),
            freshness: .live
        ))
        let store = makeStore(providers: [provider])
        await store.refreshAll()
        provider.set(.stale(for: .codex, reason: .transient("blip")))
        await store.refreshAll()
        let after = store.snapshot(for: .codex)
        #expect(after.bankedResets == 2)
        if case .stale = after.freshness {} else { Issue.record("should be stale") }
    }

    @Test func hidingSparkCountersKeepsBankedResets() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        preferences.showCodexSparkCountersInApp = false
        let store = UsageStore(providers: [
            StubProvider(id: .codex, displayName: "Codex", snapshot: UsageSnapshot(
                providerID: .codex,
                windows: [
                    UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                    UsageWindow(kind: .other("codex-spark 5h"), utilization: 40, resetsAt: reset),
                ],
                planLabel: "plus",
                bankedResets: 2,
                capturedAt: Date(),
                freshness: .live
            )),
        ], preferences: preferences)
        await store.refreshAll()
        #expect(store.appDisplaySnapshot(for: .codex).bankedResets == 2)
        #expect(store.appDisplaySnapshot(for: .codex).windows.map(\.kind) == [.weekly])
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

        store.setMenuBarWindowChoice(.fiveHour, for: .claude)
        #expect(store.menuBarWindowChoice(for: .claude) == .fiveHour)
        #expect(preferences.menuBarWindowChoice(for: .claude) == .fiveHour)
        #expect(store.menuBarSummary.text == "80%")
        #expect(store.menuBarSummary.detail == "Claude 5h")
    }

    // MARK: Menu-bar limit choice (per-limit IDs, Sep 2026)

    @Test func claudeModelRowIsAChoosableMenuBarLimit() async {
        let preferences = freshPreferences()
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 56, resetsAt: reset),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 7, resetsAt: reset),
            ])),
        ], preferences: preferences)
        await store.refreshAll()

        #expect(store.menuBarWindowOptions(for: .claude).map(\.title) == ["5-hour", "Weekly", "Fable", "Closest to limit"])

        let fable = MenuBarWindowChoice.window(id: "other:Weekly (Fable)")
        store.setMenuBarWindowChoice(fable, for: .claude)
        #expect(store.menuBarSummary.text == "93%")
        #expect(store.menuBarSummary.detail == "Claude Fable weekly")
        #expect(UsageStore(providers: [], preferences: preferences).menuBarWindowChoice(for: .claude) == fable)
    }

    @Test func cursorPoolsAreChoosableAndTheUnchosenWeeklyDefaultIsNotListed() async {
        let preferences = freshPreferences()
        preferences.setSurfaceEnabled(true, for: .cursorSubscription)
        preferences.menuBarFillSource = .providers([.cursor])
        let month: TimeInterval = 30 * 86_400
        let store = UsageStore(providers: [
            StubProvider(id: .cursor, displayName: "Cursor", snapshot: .live(.cursor, windows: [
                UsageWindow(kind: .billingPeriod(label: "Cursor Models", duration: month), utilization: 62, resetsAt: reset),
                UsageWindow(kind: .billingPeriod(label: "Other Models", duration: month), utilization: 3, resetsAt: reset),
            ])),
        ], preferences: preferences)
        await store.refreshAll()

        // The weekly default names a limit Cursor never had: it is not offered, and the
        // picker shows what the pill actually does — follow the lowest pool.
        #expect(store.menuBarWindowOptions(for: .cursor).map(\.title) == ["Cursor Models", "Other Models", "Closest to limit"])
        #expect(store.menuBarWindowPickerSelection(for: .cursor) == .closest)
        #expect(store.menuBarSummary.text == "38%")

        // A billing pool's identity ignores its declared duration, which varies by month.
        store.setMenuBarWindowChoice(.window(id: "billing:Other Models"), for: .cursor)
        #expect(store.menuBarWindowPickerSelection(for: .cursor) == .window(id: "billing:Other Models"))
        #expect(store.menuBarSummary.text == "97%")
    }

    @Test func aChosenLimitTheProviderStopsReportingStaysListedAndResumes() async {
        let preferences = freshPreferences()
        preferences.menuBarFillSource = .codex
        preferences.setMenuBarWindowChoice(.fiveHour, for: .codex)
        let provider = MutableStubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
            UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),
        ]))
        let store = UsageStore(providers: [provider], preferences: preferences)
        await store.refreshAll()

        let options = store.menuBarWindowOptions(for: .codex)
        #expect(options.map(\.title) == ["Weekly", "5-hour"])   // one real limit: nothing to be closest among
        #expect(options[1].window == nil)
        #expect(store.menuBarWindowPickerSelection(for: .codex) == .fiveHour)
        #expect(store.resolvedMenuBarWindowKind(for: .codex) == .weekly)

        provider.set(.live(.codex, windows: [
            UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
            UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),
        ]))
        await store.refreshAll()
        #expect(store.resolvedMenuBarWindowKind(for: .codex) == .fiveHour)
        #expect(store.menuBarSummary.text == "90%")
    }

    @Test func singleLimitProviderWithTheWeeklyDefaultHasNothingToChoose() async {
        let store = makeStore(source: .codex, providers: [
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),
            ])),
        ])
        await store.refreshAll()
        #expect(!store.hasSelectableMenuBarWindows(for: .codex))
    }

    @Test func unavailableRetainedRowIsNeverShownEvenWhenChosenOrLowest() async {
        let preferences = freshPreferences()
        preferences.setMenuBarWindowChoice(.window(id: "other:Weekly (Fable)"), for: .claude)
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 56, resetsAt: reset),
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 99,
                    resetsAt: reset,
                    freshness: .unavailable(since: reset)
                ),
            ])),
        ], preferences: preferences)
        await store.refreshAll()

        // Fable's old 1% would be the lowest; an unavailable row has no number to show.
        #expect(store.resolvedMenuBarWindowKind(for: .claude) == .weekly)
        #expect(store.menuBarSummary.text == "44%")
        #expect(store.menuBarWindowPickerSelection(for: .claude) == .window(id: "other:Weekly (Fable)"))
    }

    @Test func closestChoiceFollowsTheLowestLimit() async {
        let preferences = freshPreferences()
        preferences.setMenuBarWindowChoice(.closest, for: .claude)
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 88, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 56, resetsAt: reset),
            ])),
        ], preferences: preferences)
        await store.refreshAll()
        #expect(store.resolvedMenuBarWindowKind(for: .claude) == .fiveHour)
        #expect(store.menuBarSummary.text == "12%")
        #expect(store.menuBarSummary.detail == "Claude 5h")
    }

    @Test func codexSparkCountersAreOfferedOnlyWhileThePopoverShowsThem() async {
        let preferences = freshPreferences()
        preferences.showCodexSparkCountersInApp = false
        let store = UsageStore(providers: [
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                UsageWindow(kind: .other("GPT-5.3-Codex-Spark Weekly"), utilization: 0, resetsAt: reset),
            ])),
        ], preferences: preferences)
        await store.refreshAll()
        #expect(store.menuBarWindowOptions(for: .codex).map(\.title) == ["Weekly"])

        store.setShowCodexSparkCountersInApp(true)
        #expect(store.menuBarWindowOptions(for: .codex).map(\.title) == ["Weekly", "GPT-5.3-Codex-Spark · Weekly", "Closest to limit"])

        store.setMenuBarWindowChoice(.window(id: "other:GPT-5.3-Codex-Spark Weekly"), for: .codex)
        #expect(store.menuBarSummary.text == "100%")
        #expect(store.menuBarSummary.detail == "Codex GPT-5.3-Codex-Spark weekly")
    }

    @Test func pendingProviderKeepsItsPickerBeforeTheFirstFetch() {
        let preferences = freshPreferences()
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
        ], preferences: preferences)

        #expect(store.hasSelectableMenuBarWindows(for: .claude))
        #expect(store.menuBarWindowOptions(for: .claude).map(\.title) == ["Weekly", "Closest to limit"])
        #expect(store.menuBarWindowPickerSelection(for: .claude) == .weekly)
        #expect(store.resolvedMenuBarWindowKind(for: .claude) == nil)
    }

    @Test func explicitlyChosenUnavailableRowStaysListedAndSelected() async {
        let preferences = freshPreferences()
        let fable = MenuBarWindowChoice.window(id: "other:Weekly (Fable)")
        preferences.setMenuBarWindowChoice(fable, for: .claude)
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 56, resetsAt: reset),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 99, resetsAt: reset, freshness: .unavailable(since: reset)),
            ])),
        ], preferences: preferences)
        await store.refreshAll()

        let options = store.menuBarWindowOptions(for: .claude)
        #expect(options.map(\.title) == ["Weekly", "Fable", "Closest to limit"])
        #expect(options[1].window?.freshness.isUnavailable == true)
        #expect(store.menuBarWindowPickerSelection(for: .claude) == fable)
        #expect(store.resolvedMenuBarWindowKind(for: .claude) == .weekly)
    }

    @Test func appDisplaySnapshotOrdersFiveHourFirst() async {
        // The popover shows 5-hour, then weekly, then model rows, whatever order the
        // provider emitted them in.
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 40, resetsAt: reset),
                UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),
            ])),
        ])

        await store.refreshAll()

        #expect(store.appDisplaySnapshot(for: .claude).windows.map(\.kind) == [
            .fiveHour,
            .weekly,
            .other("Weekly (Fable)"),
        ])
        // The raw snapshot (widget export, menu bar) is untouched.
        #expect(store.snapshot(for: .claude).windows.first?.kind == .other("Weekly (Fable)"))
    }


    @Test func appDisplaySnapshotRanksFiveHourAheadOfPeriod() async {
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

        #expect(store.appDisplaySnapshot(for: .grok).windows.map(\.kind) == [.fiveHour, monthly, .other("Pool")])
    }

    /// R12/KTD9 (2026-09-19 sign-in plan): a check already in flight when the handoff's
    /// Terminal exits carries the pre-boundary generation, so it cannot settle the
    /// verification that follows the exit.
    @Test func handoffBoundaryRejectsACaptureLaunchedBeforeTerminalExited() async {
        let provider = SlowCountingProvider(id: .claude)
        let store = makeStore(providers: [provider])
        let key = AccountKey(providerID: .claude, accountID: .primary)

        let refresh = Task { await store.refreshAll() }
        await provider.waitUntilFetchStarts()
        store.invalidateUsageForHandoffBoundary(key)
        provider.releaseFetch()
        await refresh.value

        #expect(provider.fetchCount == 1)
        #expect(store.snapshot(for: .claude).freshness == .pending)
    }

    /// KTD9: unlike the reset boundary, the exit boundary only rejects in-flight results.
    /// A healthy row stays on screen while Headroom confirms the sign-in.
    @Test func handoffBoundaryLeavesAHealthySnapshotAlone() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude",
                         snapshot: .live(.claude, windows: [
                             UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                         ])),
        ])
        let key = AccountKey(providerID: .claude, accountID: .primary)
        await store.refreshAll()
        #expect(store.snapshot(for: .claude).freshness == .live)

        store.invalidateUsageForHandoffBoundary(key)

        #expect(store.snapshot(for: .claude).freshness == .live)
        #expect(store.snapshot(for: .claude).windows.map(\.kind) == [.weekly])
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

    // MARK: - Sign-out record (U6 / KTD14, 2026-09-19 sign-in plan)

    @Test func claudeSignOutAfterLiveUsageRecordsExactlyOneEvent() async {
        let clock = MutableDateSource(Date(timeIntervalSince1970: 1_000))
        let record = SignOutRecord(defaults: freshSignOutDefaults(), now: clock.now)
        let provider = MutableStubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)])
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            signOutRecord: record
        )

        await store.refreshAll()
        #expect(record.events.isEmpty)

        provider.set(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)))
        clock.set(Date(timeIntervalSince1970: 4_000))
        await store.refreshAll()
        await store.refreshAll()

        #expect(record.events.map(\.account) == [AccountKey(providerID: .claude, accountID: .primary)])
        #expect(record.events.map(\.detectedAt) == [Date(timeIntervalSince1970: 4_000)])
    }

    @Test func transientCaptureAndUnknownUIChangeNeitherFlagNorList() async {
        let record = SignOutRecord(defaults: freshSignOutDefaults(), now: { Date(timeIntervalSince1970: 1_000) })
        let provider = MutableStubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)])
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            signOutRecord: record
        )
        let key = AccountKey(providerID: .claude, accountID: .primary)

        await store.refreshAll()
        provider.set(.stale(for: .claude, reason: .providerSetup(.claudeTransientCapture)))
        await store.refreshAll()
        provider.set(.stale(for: .claude, reason: .providerSetup(.claudeUnknownUI)))
        await store.refreshAll()

        #expect(record.events.isEmpty)
        #expect(record.isLastKnownSignedIn(key))

        // The flag survived both, so the real sign-out that follows is still recorded.
        provider.set(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)))
        await store.refreshAll()
        #expect(record.events.count == 1)
    }

    @Test func signOutRecordIgnoresProvidersOtherThanClaude() async {
        let record = SignOutRecord(defaults: freshSignOutDefaults(), now: { Date(timeIntervalSince1970: 1_000) })
        let provider = MutableStubProvider(
            id: .codex,
            displayName: "Codex",
            snapshot: .live(.codex, windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)])
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            signOutRecord: record
        )

        await store.refreshAll()
        #expect(!record.isLastKnownSignedIn(AccountKey(providerID: .codex, accountID: .primary)))

        provider.set(.stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)))
        await store.refreshAll()

        #expect(record.events.isEmpty)
    }

    /// R16: a sign-out that happened while Headroom was closed is recorded once at the
    /// next launch, stamped with that launch's detection time.
    @Test func signOutObservedOnlyAfterRelaunchRecordsOneEventAtDetectionTime() async {
        let defaults = freshSignOutDefaults()
        let beforeQuit = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude",
                             snapshot: .live(.claude, windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)])),
            ],
            preferences: freshPreferences(),
            signOutRecord: SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 1_000) })
        )
        await beforeQuit.refreshAll()

        let afterRelaunch = SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 8_000) })
        let relaunched = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude",
                             snapshot: .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired))),
            ],
            preferences: freshPreferences(),
            signOutRecord: afterRelaunch
        )
        await relaunched.refreshAll()
        await relaunched.refreshAll()

        #expect(afterRelaunch.events.map(\.detectedAt) == [Date(timeIntervalSince1970: 8_000)])
    }

    /// KTD14: the reset boundary is the durable exclusion — it holds however the session
    /// ends, including a force-cancelled or settled-failed reset that then polls signed out.
    @Test func accountResetBoundaryClearsTheFlagSoTheResetSignOutIsNotRecorded() async {
        let record = SignOutRecord(defaults: freshSignOutDefaults(), now: { Date(timeIntervalSince1970: 1_000) })
        let provider = MutableStubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: .live(.claude, windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)])
        )
        let store = UsageStore(
            providers: [provider],
            preferences: freshPreferences(),
            signOutRecord: record
        )
        let key = AccountKey(providerID: .claude, accountID: .primary)

        await store.refreshAll()
        provider.set(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)))
        store.invalidateUsageForAccountReset(key)

        await store.refreshAll()
        await store.refreshAll()

        #expect(!record.isLastKnownSignedIn(key))
        #expect(record.events.isEmpty)
    }

    @Test func stopTrackingBuiltInClearsTheFlagSoTheResumedRowRecordsNothing() async {
        let defaults = freshSignOutDefaults()
        let record = SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 1_000) })
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude",
                             snapshot: .live(.claude, windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)])),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: SignOutTestStorage(),
            providerFactory: { account in
                AccountMutableStubProvider(
                    id: account.providerID,
                    accountID: account.id,
                    snapshot: .stale(for: account.providerID, reason: .providerSetup(.claudeLoginRequired))
                )
            },
            signOutRecord: record
        )
        let key = AccountKey(providerID: .claude, accountID: .primary)
        store.addAccount(for: .claude)
        await store.refreshAll()
        #expect(record.isLastKnownSignedIn(key))

        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(!record.isLastKnownSignedIn(key))

        // The built-in row reuses `AccountID.primary` across stop and resume, so a
        // signed-out reading on the resumed row must not read as a new sign-out.
        #expect(store.resumeTrackingBuiltInAccount(for: .claude) != nil)
        await store.refreshAll()

        #expect(record.events.isEmpty)
    }

    @Test func removingAnAccountPurgesItsEvents() async throws {
        let defaults = freshSignOutDefaults()
        let record = SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 1_000) })
        let store = UsageStore(
            providers: [
                StubProvider(id: .claude, displayName: "Claude",
                             snapshot: .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired))),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: SignOutTestStorage(),
            providerFactory: { account in
                AccountMutableStubProvider(
                    id: account.providerID,
                    accountID: account.id,
                    snapshot: .live(account.providerID, windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: Date(timeIntervalSince1970: 2_000_000))])
                )
            },
            signOutRecord: record
        )
        let added = try #require(store.addAccount(for: .claude))
        await store.refreshAll()
        let extraProvider = try #require(
            store.providers.first(where: { $0.accountKey == added.key }) as? AccountMutableStubProvider
        )
        extraProvider.set(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)))
        await store.refreshAll()
        #expect(record.events(for: added.key).count == 1)

        #expect(await store.removeAccount(added.key) == .removed)

        #expect(record.events(for: added.key).isEmpty)
        #expect(record.events.isEmpty)
        #expect(!record.isLastKnownSignedIn(added.key))
    }

    @Test func claimBankedResetRevealHonorsLiveCurrentAccountsOnly() async {
        let acknowledgements = BankedResetAcknowledgements(defaults: freshSignOutDefaults())
        let provider = MutableStubProvider(id: .codex, displayName: "Codex", snapshot: codexLive(count: 2))
        let store = UsageStore(providers: [provider], preferences: freshPreferences(), bankedResetAcknowledgements: acknowledgements)
        let key = AccountKey(providerID: .codex, accountID: .primary)
        let bare = UsageStore(providers: [provider], preferences: freshPreferences())
        #expect(!bare.claimBankedResetReveal(for: key, currentCount: 2))

        #expect(!store.claimBankedResetReveal(for: key, currentCount: 2))
        await store.refreshAll()
        #expect(store.claimBankedResetReveal(for: key, currentCount: 2))
        #expect(acknowledgements.acknowledgedCount(for: key) == 2)
        #expect(!store.claimBankedResetReveal(for: key, currentCount: 2))

        provider.set(.stale(for: .codex, reason: .transient("blip")))
        await store.refreshAll()
        acknowledgements.purge(for: key)
        #expect(acknowledgements.claimReveal(for: key, currentCount: 1))
        #expect(!store.claimBankedResetReveal(for: key, currentCount: 2))
        #expect(acknowledgements.acknowledgedCount(for: key) == 1)

        provider.set(codexLive(count: 2))
        await store.refreshAll()
        store.removingAccounts.insert(key)
        #expect(!store.claimBankedResetReveal(for: key, currentCount: 2))
        #expect(acknowledgements.acknowledgedCount(for: key) == 1)
        store.removingAccounts.remove(key)
        acknowledgements.purge(for: key)
        #expect(store.claimBankedResetReveal(for: key, currentCount: 2))
    }

    @Test func closedPopoverRedeemThenRegrantStillClaims() async {
        let acknowledgements = BankedResetAcknowledgements(defaults: freshSignOutDefaults())
        let provider = MutableStubProvider(id: .codex, displayName: "Codex", snapshot: codexLive(count: 2))
        let store = UsageStore(providers: [provider], preferences: freshPreferences(), bankedResetAcknowledgements: acknowledgements)
        let key = AccountKey(providerID: .codex, accountID: .primary)
        #expect(acknowledgements.claimReveal(for: key, currentCount: 2))

        provider.set(codexLive(count: 0))
        await store.refreshAll()
        #expect(acknowledgements.acknowledgedCount(for: key) == 0)

        provider.set(codexLive(count: 1))
        await store.refreshAll()
        #expect(acknowledgements.acknowledgedCount(for: key) == 0)
        #expect(acknowledgements.claimReveal(for: key, currentCount: 1))
    }

    @Test func stalePollDoesNotLowerBankedResetAcknowledgements() async {
        let acknowledgements = BankedResetAcknowledgements(defaults: freshSignOutDefaults())
        let provider = MutableStubProvider(id: .codex, displayName: "Codex", snapshot: codexLive(count: 2))
        let store = UsageStore(providers: [provider], preferences: freshPreferences(), bankedResetAcknowledgements: acknowledgements)
        let key = AccountKey(providerID: .codex, accountID: .primary)
        #expect(acknowledgements.claimReveal(for: key, currentCount: 2))
        provider.set(.stale(for: .codex, reason: .transient("blip")))
        await store.refreshAll()
        #expect(acknowledgements.acknowledgedCount(for: key) == 2)
    }

    @Test func rejectedGenerationDoesNotLowerBankedResetAcknowledgements() async {
        let acknowledgements = BankedResetAcknowledgements(defaults: freshSignOutDefaults())
        let store = UsageStore(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: codexLive(count: 2))],
            preferences: freshPreferences(),
            bankedResetAcknowledgements: acknowledgements
        )
        let key = AccountKey(providerID: .codex, accountID: .primary)
        await store.refreshAll()
        let generation = store.schedulerAttachmentGeneration(for: key)
        store.invalidateUsageForAccountReset(key)
        #expect(acknowledgements.acknowledgedCount(for: key) == nil)
        #expect(acknowledgements.claimReveal(for: key, currentCount: 2))
        let accepted = store.schedulerMerge(
            key: key,
            result: UsageProviderFetchResult(snapshot: codexLive(count: 0)),
            attachmentGeneration: generation
        )
        #expect(!accepted)
        #expect(acknowledgements.acknowledgedCount(for: key) == 2)
    }

    @Test func handoffBoundaryLeavesBankedResetAcknowledgements() {
        let acknowledgements = BankedResetAcknowledgements(defaults: freshSignOutDefaults())
        let store = UsageStore(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: codexLive(count: 2))],
            preferences: freshPreferences(),
            bankedResetAcknowledgements: acknowledgements
        )
        let key = AccountKey(providerID: .codex, accountID: .primary)
        #expect(acknowledgements.claimReveal(for: key, currentCount: 2))
        store.invalidateUsageForHandoffBoundary(key)
        #expect(acknowledgements.acknowledgedCount(for: key) == 2)
    }

    @Test func removeAccountPurgesOnlyThatBankedResetAcknowledgement() async throws {
        let defaults = freshSignOutDefaults()
        let acknowledgements = BankedResetAcknowledgements(defaults: defaults)
        let store = UsageStore(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: codexLive(count: 1))],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: SignOutTestStorage(),
            providerFactory: { account in
                AccountMutableStubProvider(id: account.providerID, accountID: account.id, snapshot: self.codexLive(count: 2))
            },
            bankedResetAcknowledgements: acknowledgements
        )
        let builtIn = AccountKey(providerID: .codex, accountID: .primary)
        #expect(acknowledgements.claimReveal(for: builtIn, currentCount: 1))
        let added = try #require(store.addAccount(for: .codex))
        #expect(acknowledgements.claimReveal(for: added.key, currentCount: 2))
        #expect(await store.removeAccount(added.key) == .removed)
        #expect(acknowledgements.acknowledgedCount(for: added.key) == nil)
        #expect(acknowledgements.acknowledgedCount(for: builtIn) == 1)
    }

    @Test func stopTrackingPurgesTheBuiltInAcknowledgementSoResumeClaimsAgain() async {
        let defaults = freshSignOutDefaults()
        let acknowledgements = BankedResetAcknowledgements(defaults: defaults)
        let store = UsageStore(
            providers: [StubProvider(id: .codex, displayName: "Codex", snapshot: codexLive(count: 2))],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: SignOutTestStorage(),
            providerFactory: { account in
                AccountMutableStubProvider(id: account.providerID, accountID: account.id, snapshot: self.codexLive(count: 2))
            },
            bankedResetAcknowledgements: acknowledgements
        )
        let builtIn = AccountKey(providerID: .codex, accountID: .primary)
        #expect(acknowledgements.claimReveal(for: builtIn, currentCount: 2))
        #expect(store.addAccount(for: .codex) != nil)
        #expect(await store.stopTrackingBuiltInAccount(for: .codex) == .removed)
        #expect(acknowledgements.acknowledgedCount(for: builtIn) == nil)
        #expect(store.resumeTrackingBuiltInAccount(for: .codex) != nil)
        #expect(acknowledgements.claimReveal(for: builtIn, currentCount: 2))
    }

    private func codexLive(count: Int?) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .codex,
            windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: .distantFuture)],
            planLabel: "plus",
            bankedResets: count,
            capturedAt: Date(),
            freshness: .live
        )
    }

    private func freshSignOutDefaults() -> UserDefaults {
        let suite = "headroom.signout.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

/// Account-scoped provider double whose snapshot can change between refreshes — the
/// multi-account counterpart of `MutableStubProvider`.
private final class AccountMutableStubProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    private let lock = NSLock()
    private var _snapshot: UsageSnapshot

    init(id: ProviderID, accountID: AccountID, displayName: String = "P", snapshot: UsageSnapshot) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self._snapshot = snapshot
    }

    func set(_ snapshot: UsageSnapshot) { lock.withLock { _snapshot = snapshot } }
    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { _snapshot } }
}

/// No-op storage so these tests never touch the real Application Support tree
/// (AGENTS.md: the suite is all mocked).
private struct SignOutTestStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .success(()) }
}
