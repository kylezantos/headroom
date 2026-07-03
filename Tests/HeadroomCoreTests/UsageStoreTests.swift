import Testing
import Foundation
@testable import HeadroomCore

/// U6 test scenarios: concurrent population, per-provider isolation, continuity on
/// stale, and the menu bar summary (lowest live window + provider identity).
@MainActor
struct UsageStoreTests {
    private let reset = Date(timeIntervalSince1970: 2_000_000)

    @Test func refreshPopulatesAllProviders() async {
        let store = UsageStore(providers: [
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
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude)),
        ])
        #expect(store.snapshot(for: .claude).freshness == .pending)
        #expect(store.menuBarSummary.isNeutral)
    }

    @Test func oneProviderFailureDoesNotAffectOther() async {
        let store = UsageStore(providers: [
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
        let store = UsageStore(providers: [provider])
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
        let store = UsageStore(providers: [provider])
        await store.start()
        await store.start()
        #expect(provider.fetchCount == 1)
    }

    @Test func menuBarSummaryPicksLowestLiveWithIdentity() async {
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 42.5, resetsAt: reset),   // 57.5% left
                UsageWindow(kind: .weekly, utilization: 70, resetsAt: reset),       // 30% left  <- lowest
            ])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [
                UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),     // 90% left
            ])),
        ])
        await store.refreshAll()
        let summary = store.menuBarSummary
        #expect(summary.text == "30%")
        #expect(summary.providerID == .claude)
        #expect(summary.detail == "Claude weekly")
        #expect(!summary.isNeutral)
        #expect(summary.severity == .low)         // 30% left → amber, not healthy
        #expect(!summary.needsAttention)
    }

    @Test func menuBarSummaryCarriesSeverityOfTightestWindow() async {
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [
                UsageWindow(kind: .fiveHour, utilization: 95, resetsAt: reset),   // 5% left → critical
            ])),
        ])
        await store.refreshAll()
        #expect(store.menuBarSummary.severity == .critical)
    }

    @Test func menuBarSummaryFlagsPermanentFailureEvenWhenNeutral() async {
        // A logged-out provider with no live data still surfaces attention in the bar.
        let store = UsageStore(providers: [
            StubProvider(id: .codex, displayName: "Codex",
                         snapshot: .stale(for: .codex, reason: .needsReauth("Run `codex login`"))),
        ])
        await store.refreshAll()
        let summary = store.menuBarSummary
        #expect(summary.isNeutral)          // no live number to show
        #expect(summary.needsAttention)     // …but the glyph should still warn
    }

    @Test func transientFailureDoesNotFlagAttention() async {
        let store = UsageStore(providers: [
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
        store.setMenuBarFillSource(.codex)
        #expect(store.menuBarFillSource == .codex)
        #expect(preferences.menuBarFillSource == .codex)
    }

    /// Store whose menu-bar fill source is pre-set, on an isolated defaults suite.
    private func makeStore(source: MenuBarFillSource, providers: [any UsageProvider]) -> UsageStore {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
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
}
