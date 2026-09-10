import Testing
import Foundation
@testable import HeadroomCore

/// The demo fixtures must render in the order a live capture does. `DemoFixture.claudeSnapshot`
/// had drifted to Weekly-before-5-hour, so every marketing shot disagreed with the popover —
/// and with the Settings `AppearanceSpecimen` on the same screen (pre-ship craft audit,
/// 2026-09-08).
struct DemoFixtureWindowOrderTests {
    private func kinds(_ snapshot: UsageSnapshot) -> [WindowKind] {
        snapshot.windows.map(\.kind)
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
