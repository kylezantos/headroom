import Foundation

/// Fixed WidgetKit envelope for screenshot demo mode (`--demo`), used to pose the iPhone
/// mirror without a live Mac + iCloud round-trip. It lives in the widget model layer
/// because the iOS app compiles only the widget-facing slice of Core (not `UsageModels`
/// or the provider-level `DemoFixture`). Numbers mirror `DemoFixture` so the popover,
/// the macOS widgets, and the iPhone all show the same moment.
public enum DemoScreenshotData {
    /// True when the app was launched with `--demo` (e.g. `simctl launch booted <id> --demo`).
    public static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    public static var envelope: WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: Date(),
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: ProviderID.claude.raw,
                    displayName: "Claude",
                    planLabel: "Max",
                    freshness: .live,
                    windows: [
                        window(.fiveHour, label: "5h", percent: 72, reset: "Resets 2:15pm", severity: .healthy),
                        window(.weekly, label: "weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                    ],
                    renewalDate: day(month: 7, day: 28)
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "Prolite",
                    freshness: .live,
                    windows: [
                        window(.fiveHour, label: "5h", percent: 91, reset: "Resets in 3h 12m", severity: .healthy),
                        window(.weekly, label: "weekly", percent: 64, reset: "Resets in 6d 4h", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 15)
                ),
            ]
        )
    }

    // MARK: Helpers

    private static func window(
        _ kind: WidgetWindowKind,
        label: String,
        percent: Double,
        reset: String,
        severity: WidgetUsageSeverity
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind,
            label: label,
            percentRemaining: percent,
            resetsAt: Date().addingTimeInterval(3 * 3_600),
            resetLabel: reset,
            severity: severity
        )
    }

    private static func day(month: Int, day: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year], from: Date())
        comps.month = month
        comps.day = day
        comps.hour = 10
        return Calendar.current.date(from: comps) ?? Date()
    }
}
