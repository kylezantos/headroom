#if DEBUG
import Foundation

/// DEBUG-only sample content so the companion can be driven in the Simulator without a
/// Mac syncing over iCloud. Enabled by launching with the `HEADROOM_PREVIEW=1`
/// environment variable (set in the scheme or via `simctl launch`). Never ships — the
/// whole file is compiled out of Release. Mirrors the reference screenshot (Claude Max,
/// Codex Prolite) so the card styling can be reviewed against the approved mock.
enum CompanionPreviewSeed {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HEADROOM_PREVIEW"] == "1"
    }

    static func envelope(now: Date = Date()) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: now.addingTimeInterval(-4 * 60),
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: ProviderID.claude.raw,
                    displayName: "Claude",
                    planLabel: "max",
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .fiveHour,
                            label: "Session",
                            percentRemaining: 100,
                            resetsAt: now.addingTimeInterval(3 * 3600),
                            resetLabel: "Resets 3:09am",
                            severity: .healthy
                        ),
                        WidgetWindowSummary(
                            kind: .weekly,
                            label: "Weekly",
                            percentRemaining: 70,
                            resetsAt: now.addingTimeInterval(3 * 86_400),
                            resetLabel: "Resets Jul 9 at 10am",
                            severity: .healthy
                        )
                    ],
                    renewalDate: nil
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "prolite",
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .fiveHour,
                            label: "Session",
                            percentRemaining: 39,
                            resetsAt: now.addingTimeInterval(115 * 60),
                            resetLabel: nil,
                            severity: .low
                        ),
                        WidgetWindowSummary(
                            kind: .weekly,
                            label: "Weekly",
                            percentRemaining: 44,
                            resetsAt: now.addingTimeInterval((5 * 86_400) + (21 * 3600)),
                            resetLabel: nil,
                            severity: .low
                        )
                    ],
                    renewalDate: nil
                )
            ]
        )
    }
}
#endif
