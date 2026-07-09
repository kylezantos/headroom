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
            snapshot: .live(.claude, windows: [UsageWindow(kind: .fiveHour, utilization: 40, resetsAt: reset)]))
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

    @Test func menuBarFillIsNilWithoutAWeeklyWindow() async {
        let store = makeStore(source: .codex, providers: [
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),   // no weekly
            ])),
        ])
        await store.refreshAll()
        #expect(store.menuBarFill == nil)
    }

    @Test func menuBarFillSourcePersistsThroughStore() {
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
        #expect(store.menuBarFillSource == .both)
        #expect(preferences.menuBarFillSource == .both)
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

    @Test func menuBarFollowsSelectedWindowSource() async {
        let store = makeStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: reset),   // 80% left
                UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),     // 30% left
            ])),
        ])

        await store.refreshAll()

        // Default: weekly drives the number and tooltip.
        #expect(store.menuBarSummary.text == "30%")
        #expect(store.menuBarSummary.detail == "Claude weekly")

        store.setMenuBarWindowSource(.fiveHour)
        #expect(store.menuBarWindowSource == .fiveHour)
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

    /// Fresh-suite preferences so tests never read the developer's real UserDefaults —
    /// a persisted menu-bar window source from actually using the app was leaking into
    /// the default-behavior expectations.
    private func freshPreferences() -> Preferences {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Preferences(defaults: defaults)
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
