import Testing
import Foundation
@testable import HeadroomCore

/// The demo fixtures stand in for provider output, so they carry the parser's order
/// (5-hour first). Display order is a separate, later step: `UsageStore.appDisplaySnapshot`
/// applies `UsageSnapshot.weeklyFirst()` before the popover draws, and the Settings
/// `AppearanceSpecimen` must apply the same — it was the surface that drifted (pre-ship craft
/// audit, 2026-09-08; corrected 2026-09-10).
struct DemoFixtureWindowOrderTests {
    private func kinds(_ snapshot: UsageSnapshot) -> [WindowKind] {
        snapshot.windows.map(\.kind)
    }

    /// The specimen renders the popover's order, not the fixture's.
    @Test func specimenSnapshotRendersWeeklyFirstLikeThePopover() {
        let displayed = DemoFixture.settingsSpecimenSnapshot.weeklyFirst()
        #expect(kinds(displayed) == [.weekly, .fiveHour, .other("Weekly (Fable)")])
        #expect(kinds(DemoFixture.claudeSnapshot.weeklyFirst()) == [.weekly, .fiveHour, .other("Weekly (Fable)")])
    }

    @Test func weeklyFirstIsStableAndIdempotent() {
        let resetsAt = Date().addingTimeInterval(3_600)
        let snapshot = UsageSnapshot(
            providerID: .claude,
            windows: [
                UsageWindow(kind: .other("Weekly (Zulu)"), utilization: 10, resetsAt: resetsAt),
                UsageWindow(kind: .fiveHour, utilization: 40, resetsAt: resetsAt),
                UsageWindow(kind: .other("Weekly (Alpha)"), utilization: 30, resetsAt: resetsAt),
                UsageWindow(kind: .weekly, utilization: 20, resetsAt: resetsAt),
            ],
            planLabel: nil,
            capturedAt: nil,
            freshness: .live
        )
        let once = snapshot.weeklyFirst()
        #expect(kinds(once) == [.weekly, .fiveHour, .other("Weekly (Zulu)"), .other("Weekly (Alpha)")])
        #expect(once.weeklyFirst() == once)
    }

    @Test func claudeDemoSnapshotUsesTheParserOrder() {
        let snapshot = DemoFixture.claudeSnapshot
        #expect(kinds(snapshot) == kinds(
            UsageSnapshot(
                providerID: snapshot.providerID,
                windows: ClaudeUsageParser.sortedForDisplay(snapshot.windows),
                planLabel: snapshot.planLabel,
                capturedAt: snapshot.capturedAt,
                freshness: snapshot.freshness
            )
        ))
        #expect(kinds(snapshot) == [.fiveHour, .weekly, .other("Weekly (Fable)")])
    }

    /// The two other Claude fixtures on the same screen as the demo popover.
    @Test func everyClaudeFixtureLeadsWithTheFiveHourWindow() {
        for snapshot in [
            DemoFixture.claudeSnapshot,
            DemoFixture.settingsSpecimenSnapshot,
            DemoFixture.claudePartialCaptureSnapshot,
        ] {
            #expect(kinds(snapshot) == ClaudeUsageParser.sortedForDisplay(snapshot.windows).map(\.kind))
        }
    }

    /// The multi-account scenarios build their windows through `demoAccount`, so a single
    /// drift there would reorder every account in every scenario at once.
    @Test func everyMultiAccountFixtureUsesTheParserOrder() async {
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            let fixture = DemoFixture.multiFixture(for: scenario)
            for provider in fixture.providers {
                let snapshot = await provider.fetchSnapshot()
                #expect(kinds(snapshot) == ClaudeUsageParser.sortedForDisplay(snapshot.windows).map(\.kind))
            }
            for snapshot in fixture.continuitySnapshots.values {
                #expect(kinds(snapshot) == ClaudeUsageParser.sortedForDisplay(snapshot.windows).map(\.kind))
            }
        }
    }

    @Test func sortedForDisplayKeepsEqualRankRowsInSourceOrder() {
        let resetsAt = Date().addingTimeInterval(3_600)
        let windows = [
            UsageWindow(kind: .other("Weekly (Zulu)"), utilization: 10, resetsAt: resetsAt),
            UsageWindow(kind: .weekly, utilization: 20, resetsAt: resetsAt),
            UsageWindow(kind: .other("Weekly (Alpha)"), utilization: 30, resetsAt: resetsAt),
            UsageWindow(kind: .fiveHour, utilization: 40, resetsAt: resetsAt),
        ]
        #expect(ClaudeUsageParser.sortedForDisplay(windows).map(\.kind) == [
            .fiveHour,
            .weekly,
            .other("Weekly (Zulu)"),
            .other("Weekly (Alpha)"),
        ])
    }

    /// `--demo multi-4` was offering Cursor an "Add Account…" the product does not have.
    @Test func demoCursorProviderDeclaresTheShippingSingleAccountCapacity() {
        let cursor = DemoUsageProvider(
            id: .cursor,
            displayName: "Cursor",
            snapshot: DemoFixture.cursorSnapshot
        )
        // Matches `CursorProvider.accountCapacity`, pinned to 1 because no config-home
        // isolation equivalent to `CLAUDE_CONFIG_DIR` exists for `cursor-agent`.
        #expect(cursor.accountCapacity == 1)

        let claude = DemoUsageProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: DemoFixture.claudeSnapshot
        )
        #expect(claude.accountCapacity == AccountRegistry.maxPerProvider)
    }
}
