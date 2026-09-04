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
        #expect(MirrorPresentation.resetText(for: live, now: now) == "Available")
        #expect(stale.utilization == 0)
        #expect(stale.resetSchedule == .unresolved(.absent))
        #expect(stale.observedAt == observedAt)
        #expect(MirrorPresentation.resetText(for: stale, now: now) == "Reset info unavailable")
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
}
