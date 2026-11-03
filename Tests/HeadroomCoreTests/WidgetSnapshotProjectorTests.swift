import Testing
import Foundation
@testable import HeadroomCore

struct WidgetSnapshotProjectorTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let reset = Date(timeIntervalSince1970: 2_100_000)

    @Test func liveProvidersProjectWeeklySummaries() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),
                    UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
                ], plan: "max", at: now),
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                ], plan: "pro", at: now),
            ],
            providerOrder: [.claude, .codex],
            displayNames: [.claude: "Claude", .codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.status == .enabled)
        #expect(envelope.providers.count == 2)
        #expect(envelope.weeklyProviders[0].weeklyWindow?.percentRemaining == 60)
        #expect(envelope.weeklyProviders[1].weeklyWindow?.percentRemaining == 75)
    }

    @Test func widgetProvidersHonorSelectionOrderAndCap() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [.claude, .codex, .grok, .cursor],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            widgetProviderSelection: [.grok, .cursor, .claude],
            generatedAt: now
        )

        #expect(envelope.widgetProviderSelection == ["grok", "cursor"])
        #expect(envelope.widgetProviders.map(\.id) == ["grok", "cursor"])
    }

    @Test func widgetProvidersFallBackWhenSelectionHasNoAvailableProvider() {
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: WidgetSnapshotProjector.project(
                snapshots: [:],
                providerOrder: [.claude, .codex],
                displayNames: [:],
                renewalDate: { _ in nil },
                widgetsEnabled: true,
                generatedAt: now
            ).providers,
            widgetProviderSelection: ["future-provider"]
        )

        #expect(envelope.widgetProviders.map(\.id) == ["claude", "codex"])
    }

    @Test func widgetProvidersFallBackToFirstTwoProviders() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [.claude, .codex, .grok],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.widgetProviderSelection == nil)
        #expect(envelope.widgetProviders.map(\.id) == ["claude", "codex"])

        let emptySelection = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [.claude, .codex, .grok],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            widgetProviderSelection: [],
            generatedAt: now
        )
        #expect(emptySelection.widgetProviders.map(\.id) == ["claude", "codex"])
    }

    @Test func missingWeeklyWindowOnlyAffectsThatProvider() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
                ], at: now),
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.claude, .codex],
            displayNames: [.claude: "Claude", .codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.weeklyProviders[0].weeklyWindow == nil)
        #expect(envelope.weeklyProviders[1].weeklyWindow?.percentRemaining == 70)
    }

    @Test func bankedResetsDoNotChangeTheWidgetEnvelope() {
        let base = UsageSnapshot(
            providerID: .codex,
            windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)],
            planLabel: "plus",
            capturedAt: now,
            freshness: .live
        )
        let withSpare = UsageSnapshot(
            providerID: .codex,
            windows: base.windows,
            planLabel: base.planLabel,
            bankedResets: 2,
            capturedAt: now,
            freshness: .live
        )
        let plain = WidgetSnapshotProjector.project(
            snapshots: [.codex: base],
            providerOrder: [.codex],
            displayNames: [.codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )
        let counted = WidgetSnapshotProjector.project(
            snapshots: [.codex: withSpare],
            providerOrder: [.codex],
            displayNames: [.codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )
        #expect(counted == plain)
    }

    @Test func staleProviderCarriesSafeMessageAndPriorWindows() {
        let snapshot = UsageSnapshot(
            providerID: .claude,
            windows: [UsageWindow(kind: .weekly, utilization: 95, resetsAt: reset)],
            planLabel: nil,
            capturedAt: now,
            freshness: .stale(.needsReauth("Run `claude`"))
        )
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.claude: snapshot],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        guard case .stale(let message, let needsAttention) = envelope.providers[0].freshness else {
            Issue.record("expected stale provider")
            return
        }
        #expect(message == "Run `claude`")
        #expect(needsAttention)
        #expect(envelope.providers[0].weeklyWindow?.severity == .critical)
    }

    @Test func unresolvedResetProjectionPreservesLiveAndStaleSemantics() {
        let observedAt = now.addingTimeInterval(-300)
        let liveWindow = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.absent)
        )
        let staleWindow = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.absent),
            freshness: .stale(observedAt: observedAt)
        )

        let live = WidgetSnapshotProjector.project(
            snapshots: [.claude: .live(.claude, windows: [liveWindow], at: now)],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        ).providers[0].windows[0]
        let stale = WidgetSnapshotProjector.project(
            snapshots: [.claude: .live(.claude, windows: [staleWindow], at: now)],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        ).providers[0].windows[0]

        #expect(live.utilization == 0)
        #expect(live.resetSchedule == .unresolved(.absent))
        #expect(live.observedAt == now)
        #expect(Countdown.resetText(schedule: live.resetSchedule, utilization: live.utilization, isLive: live.freshness.isLive, now: now) == "Available")
        #expect(stale.utilization == 0)
        #expect(stale.resetSchedule == .unresolved(.absent))
        #expect(stale.observedAt == observedAt)
        #expect(Countdown.resetText(schedule: stale.resetSchedule, utilization: stale.utilization, isLive: stale.freshness.isLive, now: now) == "Reset info unavailable")
    }

    @Test func disabledExportContainsNoProviderData() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.claude: .live(.claude, windows: [UsageWindow(kind: .weekly, utilization: 5, resetsAt: reset)])],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: false,
            apiSpendSnapshots: [
                .codex: APISpendSnapshot(
                    providerID: .codex,
                    displayName: "OpenAI API",
                    amount: 12.34,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now,
                    freshness: .live
                ),
            ],
            apiSpendProviderOrder: [.codex],
            generatedAt: now
        )

        #expect(envelope.status == .disabled)
        #expect(envelope.providers.isEmpty)
        #expect(envelope.apiSpendProviders.isEmpty)
    }

    @Test func enabledAPISpendProjectsInProviderOrder() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            apiSpendSnapshots: [
                .codex: APISpendSnapshot(
                    providerID: .codex,
                    displayName: "OpenAI API",
                    amount: 12.3,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now,
                    freshness: .live
                ),
                .claude: APISpendSnapshot(
                    providerID: .claude,
                    displayName: "Anthropic API",
                    amount: 4,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now.addingTimeInterval(-60),
                    freshness: .live
                ),
            ],
            apiSpendProviderOrder: [.claude, .codex],
            generatedAt: now
        )

        #expect(envelope.apiSpendProviders.map(\.id) == ["claude", "codex"])
        #expect(envelope.apiSpendProviders[0].displayName == "Anthropic API")
        #expect(envelope.apiSpendProviders[0].amount == 4)
        #expect(envelope.apiSpendProviders[0].currency == "usd")
        #expect(envelope.apiSpendProviders[0].periodLabel == "Current month")
        #expect(envelope.apiSpendProviders[0].capturedAt == now.addingTimeInterval(-60))
        #expect(envelope.apiSpendProviders[0].freshness == .live)
    }

    @Test func staleAPISpendProjectsSafeFreshnessAndPriorAmount() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            apiSpendSnapshots: [
                .codex: APISpendSnapshot(
                    providerID: .codex,
                    displayName: "OpenAI API",
                    amount: 12.3,
                    currency: "usd",
                    periodLabel: "Last 30 days",
                    capturedAt: now,
                    freshness: .stale(.notLoggedIn("Add API key on Mac"))
                ),
            ],
            apiSpendProviderOrder: [.codex],
            generatedAt: now
        )

        let spend = envelope.apiSpendProviders[0]
        #expect(spend.amount == 12.3)
        #expect(spend.periodLabel == "Last 30 days")
        guard case .stale(let message, let needsAttention) = spend.freshness else {
            Issue.record("expected stale API spend")
            return
        }
        #expect(message == "Add API key on Mac")
        #expect(needsAttention)
        // The typed reason rides alongside so the companion can badge the same way the
        // Mac card does instead of collapsing every permanent failure to "Needs setup".
        #expect(spend.attention == .missingKey)
    }

    @Test func rejectedAPISpendKeyProjectsItsOwnAttention() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            apiSpendSnapshots: [
                .claude: .stale(
                    providerID: .claude,
                    displayName: "Anthropic API",
                    periodLabel: "September",
                    reason: .needsReauth("Anthropic admin key rejected")
                ),
            ],
            apiSpendProviderOrder: [.claude],
            generatedAt: now
        )

        #expect(envelope.apiSpendProviders[0].attention == .keyRejected)
    }

    @Test func nonSubscriptionAllowanceWindowsAreFilteredOutOfWidgets() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                    UsageWindow(kind: .other("GPT-5.3"), utilization: 90, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.codex],
            displayNames: [.codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.map(\.kind) == [.weekly])
    }

    @Test func codexSparkWindowsCanBeIncludedInWidgetSnapshots() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                    UsageWindow(kind: .other("codex-spark 5h"), utilization: 40, resetsAt: reset),
                    UsageWindow(kind: .other("GPT-5.3-Codex-Spark weekly"), utilization: 93, resetsAt: reset),
                    UsageWindow(kind: .other("GPT-5.3"), utilization: 90, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.codex],
            displayNames: [.codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            showsCodexSparkCounters: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.map(\.kind) == [
            .weekly,
            .other("codex-spark 5h"),
            .other("GPT-5.3-Codex-Spark weekly"),
        ])
        #expect(envelope.providers[0].extraCounterWindows.count == 2)
        #expect(envelope.providers[0].weeklyDisplayWindows.map(\.label) == ["Weekly", "GPT-5.3-Codex-Spark weekly"])
        #expect(envelope.providers[0].limitingExtraWeeklyWindow?.compactLabel == "Spark")
        #expect(envelope.providers[0].limitingExtraWeeklyWindow?.roundedPercentRemaining == 7)
    }

    @Test func sparkWindowSettingDoesNotExposeNonCodexWindows() {
        // The spark counter setting is Codex-only: a Claude spark-labeled window that is
        // not a weekly sub-limit must not leak in on its back.
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .other("claude spark 5h"), utilization: 10, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            showsCodexSparkCounters: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.isEmpty)
    }

    @Test func claudeWeeklySubLimitsSurfaceInWidgets() {
        // Claude's model-specific weekly sub-limit ("Weekly (Fable)") rides with the
        // weekly window into the widget, independent of the Codex spark setting, so a
        // more restrictive value can appear as compact large-widget header context.
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
                    UsageWindow(kind: .fiveHour, utilization: 5, resetsAt: reset),
                    UsageWindow(kind: .other("Weekly (Fable)"), utilization: 62, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.map(\.kind) == [
            .weekly,
            .fiveHour,
            .other("Weekly (Fable)"),
        ])
        #expect(envelope.providers[0].extraWeeklyWindows.map(\.label) == ["Weekly (Fable)"])
        #expect(envelope.providers[0].limitingExtraWeeklyWindow?.compactLabel == "Fable")
        #expect(envelope.providers[0].limitingExtraWeeklyWindow?.roundedPercentRemaining == 38)
    }

    @Test func retainedClaudeSubLimitCarriesLastKnownStateIntoWidgets() {
        let observedAt = now.addingTimeInterval(-3_600)
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
                    UsageWindow(
                        kind: .other("Weekly (Fable)"),
                        utilization: 62,
                        resetsAt: reset,
                        freshness: .stale(observedAt: observedAt)
                    ),
                ], at: now),
            ],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].freshness == .live)
        #expect(
            envelope.providers[0].extraWeeklyWindows.first?.freshness
                == .stale(observedAt: observedAt)
        )
    }

    @Test func unavailableClaudeSubLimitDoesNotExposeItsOldPercentageToWidgets() {
        let unavailableSince = now.addingTimeInterval(-60)
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset),
                    UsageWindow(
                        kind: .other("Weekly (Fable)"),
                        utilization: 62,
                        resetsAt: reset,
                        freshness: .unavailable(since: unavailableSince)
                    ),
                ], at: now),
            ],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        let fable = envelope.providers[0].extraWeeklyWindows.first
        #expect(fable?.freshness == .unavailable(since: unavailableSince))
        #expect(fable?.displayPercentRemaining == nil)
        #expect(envelope.providers[0].limitingExtraWeeklyWindow == nil)
    }

    @Test func matchingWeeklySubLimitDoesNotAddWidgetHeaderStatus() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 8, resetsAt: reset),
                    UsageWindow(kind: .fiveHour, utilization: 48, resetsAt: reset),
                    UsageWindow(kind: .other("Weekly (Fable)"), utilization: 8, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].extraWeeklyWindows.count == 1)
        #expect(envelope.providers[0].limitingExtraWeeklyWindow == nil)
    }

    @Test func unknownProviderRoundTrips() throws {
        let other = ProviderID("other")
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [other: .live(other, windows: [UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset)])],
            providerOrder: [other],
            displayNames: [other: "Other"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: data)
        #expect(decoded.providers[0].id == "other")
        #expect(decoded.providers[0].windows[0].kind == .weekly)
    }

    @Test func periodAndUnknownWindowsSurviveForGenericProviders() {
        let other = ProviderID("other")
        let monthly = WindowKind.billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60)
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [other: .live(other, windows: [
                UsageWindow(kind: monthly, utilization: 20, resetsAt: reset),
                UsageWindow(kind: .other("Pool"), utilization: 40, resetsAt: reset),
            ])],
            providerOrder: [other],
            displayNames: [other: "Other"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.map(\.kind) == [.other("Monthly"), .other("Pool")])
    }

    @Test func cursorNamedPoolsPreserveTheirProjectionContract() {
        let duration = 30 * 24 * 60 * 60.0
        let schedule = ResetSchedule.scheduled(reset)
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.cursor: UsageSnapshot(
                providerID: .cursor,
                windows: [
                    UsageWindow(
                        kind: .billingPeriod(label: "Cursor Models", duration: duration),
                        utilization: 31,
                        resetSchedule: schedule,
                        resetLabel: "Resets Oct 1"
                    ),
                    UsageWindow(
                        kind: .billingPeriod(label: "Other Models", duration: duration),
                        utilization: 63,
                        resetSchedule: schedule,
                        resetLabel: "Resets Oct 1"
                    ),
                ],
                planLabel: "Pro+",
                capturedAt: now,
                freshness: .live
            )],
            providerOrder: [.cursor],
            displayNames: [.cursor: "Cursor"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        let windows = envelope.providers[0].windows
        #expect(windows.map(\.label) == ["Cursor Models", "Other Models"])
        #expect(windows.map(\.displayPercentRemaining) == [69, 37])
        #expect(windows.map(\.billingPeriodDuration) == [duration, duration])
        #expect(windows.map(\.resetSchedule) == [schedule, schedule])
        #expect(windows.map(\.resetLabel) == ["Resets Oct 1", "Resets Oct 1"])
    }
}

// MARK: - Phone sync projection (iPhone parity U5: KTD5, KTD9, KTD13)

/// Store states for the parity checks, built the way the Mac's demo modes compose them.
@MainActor
enum PhoneDemoStores {
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_000_000.75)

    static func freshDefaults() -> UserDefaults {
        let suite = "headroom.phone-projection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The spend rows each scenario poses in the app (`AppComposition.demoSpendProviders`).
    static func spend(for scenario: DemoFixture.MultiAccountScenario?) -> [any APISpendProvider] {
        switch scenario {
        case .spendStates?:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpendKeyRejected),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                DemoSpendProvider(id: .grok, displayName: "xAI API", snapshot: DemoFixture.xaiBalanceSpend),
                DemoSpendProvider(id: .cursor, displayName: "Cursor on-demand", snapshot: DemoFixture.cursorOnDemandSpend),
            ]
        case .spendRetained?:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpendKeyRejectedRetained),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpendStaleRetained),
                DemoSpendProvider(id: .grok, displayName: "xAI API", snapshot: DemoFixture.xaiBalanceSpend),
                DemoSpendProvider(id: .cursor, displayName: "Cursor on-demand", snapshot: DemoFixture.cursorOnDemandSpend),
            ]
        default:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ]
        }
    }

    /// One `--demo <scenario>` store state after a full refresh. Fixture probes are read
    /// once up front so the envelope's simulated 4-second probes do not serialize.
    static func store(_ scenario: DemoFixture.MultiAccountScenario, widgetSpark: Bool) async -> UsageStore {
        let fixture = DemoFixture.multiFixture(for: scenario)
        let results = await withTaskGroup(of: (Int, UsageProviderFetchResult).self) { group in
            for (index, provider) in fixture.providers.enumerated() {
                group.addTask { (index, await provider.fetchResult()) }
            }
            var collected: [Int: UsageProviderFetchResult] = [:]
            for await (index, result) in group { collected[index] = result }
            return collected
        }
        let providers: [any UsageProvider] = fixture.providers.enumerated().map { index, provider in
            DemoUsageProvider(
                id: provider.id, displayName: provider.displayName,
                snapshot: results[index]!.snapshot, accountID: provider.accountID,
                capability: results[index]!.capability)
        }
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.syncToIPhoneEnabled = true
        preferences.showCodexSparkCountersInWidgets = widgetSpark
        let spend = spend(for: scenario)
        for provider in spend {
            if let surface = UsageSurface.api(for: provider.id) { preferences.setSurfaceEnabled(true, for: surface) }
        }
        for id in Set(fixture.accounts.map(\.providerID)) {
            if let surface = UsageSurface.subscription(for: id) { preferences.setSurfaceEnabled(true, for: surface) }
        }
        let continuity = UsageContinuityCache(defaults: defaults)
        for (key, snapshot) in fixture.continuitySnapshots { continuity.save(snapshot, for: key) }
        let registry = AccountRegistry(defaults: freshDefaults())
        registry.seed(fixture.accounts)
        let store = UsageStore(
            providers: providers, apiSpendProviders: spend, preferences: preferences,
            accounts: fixture.accounts, accountRegistry: registry,
            accountStorage: DemoAccountStorage(), continuityCache: continuity, now: { now })
        await store.refreshAll()
        return store
    }

    /// The bare `--demo` screenshot store (Claude + Codex with renewal dates set).
    static func singleStore(widgetSpark: Bool) async -> UsageStore {
        let preferences = Preferences(defaults: freshDefaults())
        preferences.syncToIPhoneEnabled = true
        preferences.showCodexSparkCountersInWidgets = widgetSpark
        preferences.setSurfaceEnabled(true, for: .anthropicAPI)
        preferences.setSurfaceEnabled(true, for: .openAIAPI)
        preferences.setRenewalDate(DemoFixture.renewalDate(for: .claude), for: .claude)
        preferences.setRenewalDate(DemoFixture.renewalDate(for: .codex), for: .codex)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            apiSpendProviders: spend(for: nil), preferences: preferences, now: { now })
        await store.refreshAll()
        return store
    }
}

@MainActor
@Suite
struct CompanionPhoneProjectionTests {
    typealias F = CompanionFixtures
    private let captured = Date(timeIntervalSince1970: 1_790_000_000.6)

    @Test func phoneSyncCanonicalizesTheSchema3ExportWhileTheLocalWidgetKeepsItsSource() throws {
        let reset = Date(timeIntervalSince1970: 1_790_003_600.4)
        let snapshot = UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(
                    kind: .fiveHour, utilization: 84.95, resetSchedule: .scheduled(reset),
                    resetLabel: "Resets 2:15pm", resetTimeZoneIdentifier: "America/New_York"),
                UsageWindow(kind: .other("GPT-5.3-Codex-Spark 5h"), utilization: 10, resetsAt: reset),
            ],
            planLabel: "Pro", capturedAt: captured,
            freshness: .stale(.transient("Couldn’t reach Codex — HTTP 502 from /wham")))
        func project(_ context: WidgetProjectionContext) -> WidgetSnapshotEnvelope {
            WidgetSnapshotProjector.project(
                snapshots: [.codex: snapshot], providerOrder: [.codex], displayNames: [.codex: "Codex"],
                renewalDate: { _ in Date(timeIntervalSince1970: 1_800_000_000) }, widgetsEnabled: true,
                widgetProviderSelection: [.codex], showsCodexSparkCounters: false,
                generatedAt: captured, context: context)
        }
        let local = project(.localWidget)
        #expect(local.providers[0].windows[0].resetLabel == "Resets 2:15pm")
        // KTD6.2: the Mac widget export normalizes too: 15.1 and Low, never 15.049999….
        #expect(local.providers[0].windows[0].percentRemaining == 15.1)
        #expect(local.providers[0].windows[0].severity == .low)
        #expect(local.providers[0].freshness == .stale(message: "Couldn’t reach Codex — HTTP 502 from /wham", needsAttention: false))
        #expect(local.providers[0].renewalDate != nil)

        let phone = project(.phoneSync(attention: [:]))
        #expect(phone.generatedAt == Date(timeIntervalSince1970: 1_790_000_000))
        let provider = try #require(phone.providers.first)
        #expect(provider.renewalDate == nil)
        #expect(provider.freshness == .stale(message: CompanionAttentionCopy.account(.retrying), needsAttention: false))
        let row = try #require(provider.windows.first)
        #expect(provider.windows.count == 1)
        #expect(row.resetLabel == nil && row.resetTimeZoneIdentifier == nil)
        #expect(row.resetSchedule == .scheduled(Date(timeIntervalSince1970: 1_790_003_600)))
        #expect(row.observedAt == Date(timeIntervalSince1970: 1_790_000_000))
        // 100 − 84.95 is the 15.05 tie, which rounds away from zero to 15.1: Low, not Critical.
        #expect(row.percentRemaining == 15.1 && row.severity == .low)
        #expect(row.utilization == 84.95)

        // A session overlay names the typed category; permanence still comes from the source.
        let overlaid = WidgetSnapshotProjector.project(
            snapshots: [.codex: snapshot], providerOrder: [.codex], displayNames: [:],
            renewalDate: { _ in nil }, widgetsEnabled: true, generatedAt: captured,
            context: .phoneSync(attention: [.codex: .finishingSignIn]))
        #expect(overlaid.providers[0].freshness
            == .stale(message: "Finishing sign-in on your Mac", needsAttention: false))
    }

    /// KTD9 / V13: case-insensitive duplicates take " · N" by stored order, skipping a
    /// literal the user already typed; empty labels fall back to a default name.
    @Test func titlesAreUniqueWithoutEmailsAndNeverCollideWithALiteral() {
        let accounts = [
            ProviderAccount(id: .primary, providerID: .claude, label: "Main", isBuiltIn: true),
            ProviderAccount(id: AccountID("a"), providerID: .claude, label: "Work"),
            ProviderAccount(id: AccountID("b"), providerID: .claude, label: " work "),
            ProviderAccount(id: AccountID("c"), providerID: .claude, label: "Work · 2"),
            ProviderAccount(id: AccountID("d"), providerID: .claude, label: "   "),
            ProviderAccount(id: AccountID("e"), providerID: .claude, label: "WORK"),
        ]
        let titles = CompanionPhoneProjection.titles(storedOrder: accounts)
        #expect(titles[.primary] == "Main")
        #expect(titles[AccountID("a")] == "Work")
        #expect(titles[AccountID("b")] == "work · 3")
        #expect(titles[AccountID("c")] == "Work · 2")
        #expect(titles[AccountID("d")] == "Account")
        #expect(titles[AccountID("e")] == "WORK · 4")
    }

    /// KTD13: one store state through the Mac projector (the paired schema-3 phone export)
    /// and through v4 projection plus the resolver's `primaryProjection()`, for every
    /// demo variant, with the Mac's widget Spark switch both ways. Equal apart from
    /// `generatedAt` (which the shared publish makes equal too).
    @Test func v3AndTheV4PrimaryProjectionAgreeForEveryDemoVariant() async throws {
        var variants: [(String, @MainActor (Bool) async -> UsageStore)] = [("single", { await PhoneDemoStores.singleStore(widgetSpark: $0) })]
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            variants.append((scenario.rawValue, { await PhoneDemoStores.store(scenario, widgetSpark: $0) }))
        }
        for (name, make) in variants {
            for widgetSpark in [false, true] {
                let store = await make(widgetSpark)
                var capture = store.companionCapture()
                capture.generation = 41
                #expect(capture.status == .enabled, "\(name)")
                let image = try CompanionPublishImage.fullImage(capture: capture, sourceID: F.macA, macAppVersion: "1.5 (40)")
                let resolution = CompanionSnapshotResolver.resolve(
                    CompanionResolverInput(
                        manifest: image.manifest, providerKeys: image.providers, v3: image.v3,
                        now: PhoneDemoStores.now.addingTimeInterval(5)))
                let content = try #require(resolution.snapshot.content, "\(name)")
                #expect(content.origin == .v4, "\(name)")
                for provider in content.providers {
                    #expect(provider.source == .v4(.manifestDigestMatched), "\(name) \(provider.id)")
                }
                let v3 = try #require(SyncedWidgetSnapshotCodec.decode(image.v3).envelope, "\(name)")
                let projection = try #require(resolution.snapshot.primaryProjection(), "\(name)")
                #expect(projection.generatedAt == v3.snapshot.generatedAt, "\(name)")
                #expect(projection.providers == v3.snapshot.providers, "\(name) spark=\(widgetSpark)")
                #expect(projection.apiSpendProviders == v3.snapshot.apiSpendProviders, "\(name)")
                #expect(projection.widgetProviderSelection == v3.snapshot.widgetProviderSelection, "\(name)")
                #expect(projection == v3.snapshot, "\(name) spark=\(widgetSpark)")
                // Every account the Mac tracks reaches the phone, in Make Main order (R2).
                for id in store.providerOrder {
                    #expect(
                        content.providers.first { $0.id == id.raw }?.accounts.compactMap(\.accountID)
                            == store.accounts(for: id).map(\.id.raw), "\(name) \(id)")
                }
            }
        }
    }

    /// V8 / KTD22: emails in account metadata, credentials and config paths never encode.
    @Test func encodedPhoneSyncCarriesNoEmailOrUpstreamIdentity() async throws {
        let store = await PhoneDemoStores.store(.duplicateLabels, widgetSpark: true)
        #expect(store.accounts(for: .claude).contains { store.snapshot(for: $0.key).accountEmail != nil })
        var capture = store.companionCapture()
        capture.generation = 3
        let image = try CompanionPublishImage.fullImage(capture: capture, sourceID: F.macA)
        let encoded = ([image.manifest, image.v3] + Array(image.providers.values))
            .map { String(decoding: $0, as: UTF8.self) }.joined()
        for banned in [
            "@", "example.com", "/Users/", ".claude", ".codex", "CLAUDE_CONFIG_DIR", "CODEX_HOME",
            "GROK_HOME", "COPILOT_HOME", ".copilot", "Application Support", "accountUuid", "oauthAccount", "auth.json", "email",
        ] {
            #expect(!encoded.contains(banned), "\(banned)")
        }
    }
}
