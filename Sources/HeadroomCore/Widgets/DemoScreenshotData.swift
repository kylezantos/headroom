import Foundation

/// Fixed WidgetKit envelope for screenshot demo mode (`--demo`), used to pose the iPhone
/// mirror without a live Mac + iCloud round-trip. It lives in the widget model layer
/// because the iOS app compiles the widget-facing slice of Core but not the provider-level
/// `DemoFixture`. Numbers mirror `DemoFixture` so the popover,
/// the macOS widgets, and the iPhone all show the same moment.
public enum DemoScreenshotData {
    // Window order matches `ClaudeUsageParser.displayRank` (5-hour, then the weekly pool,
    // then model rows) because these envelopes stand in for a real projection, which carries
    // the provider's order; the macOS widgets re-rank weekly-first at display time and the
    // phone mirror shows the projection as-is. `DemoScenarioParityTests` holds the "full"
    // envelope to the Mac fixture.
    /// True when the app was launched with `--demo` (e.g. `simctl launch booted <id> --demo`).
    public static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    /// The current demo envelope variant, selecting from the named fixtures below.
    /// Reads the `companionDemoVariant` key from the app-group defaults when available;
    /// falls back to "full" if the variant is unset or unrecognized.
    public static var envelope: WidgetSnapshotEnvelope {
        let variant = CompanionDemoModeStore.appGroup().variant
        return self.envelope(for: variant)
    }

    /// Resolves a named demo fixture variant to its WidgetSnapshotEnvelope.
    /// Unknown variants fall back to the `full` fixture.
    public static func envelope(for variant: String) -> WidgetSnapshotEnvelope {
        switch variant {
        case "noSpend":
            return noSpendEnvelope
        case "claudeOnly":
            return claudeOnlyEnvelope
        case "claudeOnlyNoSpend":
            return claudeOnlyNoSpendEnvelope
        case "codexFiveHourReturns":
            return codexFiveHourReturnsEnvelope
        case "attention":
            return attentionEnvelope
        case "fourProviders":
            return fourProvidersEnvelope
        default:
            return fullEnvelope
        }
    }

    // MARK: - Named Fixtures

    /// `full`: Claude weekly+5h+Fable, Codex weekly, spend on → 7 rows, regular tier
    private static var fullEnvelope: WidgetSnapshotEnvelope {
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
                        window(.weekly, label: "Weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                        window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 54, reset: "Resets Jul 9", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 28)
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "Prolite",
                    freshness: .live,
                    windows: [
                        window(.weekly, label: "Weekly", percent: 64, reset: "Resets in 6d 4h", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 15)
                ),
            ],
            apiSpendProviders: [
                spend(
                    id: ProviderID.claude.raw,
                    displayName: "Anthropic API",
                    amount: 142.67
                ),
                spend(
                    id: ProviderID.codex.raw,
                    displayName: "OpenAI API",
                    amount: 58.90
                ),
            ]
        )
    }

    /// `noSpend`: Claude weekly+5h+Fable, Codex weekly, spend off → 6 rows, regular tier
    private static var noSpendEnvelope: WidgetSnapshotEnvelope {
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
                        window(.weekly, label: "Weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                        window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 54, reset: "Resets Jul 9", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 28)
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "Prolite",
                    freshness: .live,
                    windows: [
                        window(.weekly, label: "Weekly", percent: 64, reset: "Resets in 6d 4h", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 15)
                ),
            ],
            apiSpendProviders: []
        )
    }

    /// `claudeOnly`: Claude weekly+5h+Fable, no Codex, spend on → 5 rows, roomy tier
    private static var claudeOnlyEnvelope: WidgetSnapshotEnvelope {
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
                        window(.weekly, label: "Weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                        window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 54, reset: "Resets Jul 9", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 28)
                ),
            ],
            apiSpendProviders: [
                spend(
                    id: ProviderID.claude.raw,
                    displayName: "Anthropic API",
                    amount: 142.67
                ),
            ]
        )
    }

    /// `claudeOnlyNoSpend`: Claude weekly+5h+Fable, no Codex, spend off → 4 rows, roomy tier
    private static var claudeOnlyNoSpendEnvelope: WidgetSnapshotEnvelope {
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
                        window(.weekly, label: "Weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                        window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 54, reset: "Resets Jul 9", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 28)
                ),
            ],
            apiSpendProviders: []
        )
    }

    /// `codexFiveHourReturns`: Claude weekly+5h+Fable, Codex weekly+5h, spend on → 8 rows, compact tier
    private static var codexFiveHourReturnsEnvelope: WidgetSnapshotEnvelope {
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
                        window(.weekly, label: "Weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                        window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 54, reset: "Resets Jul 9", severity: .healthy),
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
                        window(.weekly, label: "Weekly", percent: 64, reset: "Resets in 6d 4h", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 15)
                ),
            ],
            apiSpendProviders: [
                spend(
                    id: ProviderID.claude.raw,
                    displayName: "Anthropic API",
                    amount: 142.67
                ),
                spend(
                    id: ProviderID.codex.raw,
                    displayName: "OpenAI API",
                    amount: 58.90
                ),
            ]
        )
    }

    /// `attention`: Claude weekly+5h+Fable (stale), Codex weekly, spend on → 7 rows, regular tier
    private static var attentionEnvelope: WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: Date(),
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: ProviderID.claude.raw,
                    displayName: "Claude",
                    planLabel: "Max",
                    freshness: .stale(message: "Data unavailable", needsAttention: true),
                    windows: [
                        window(.fiveHour, label: "5h", percent: 72, reset: "Resets 2:15pm", severity: .healthy),
                        window(.weekly, label: "Weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                        window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 54, reset: "Resets Jul 9", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 28)
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "Prolite",
                    freshness: .live,
                    windows: [
                        window(.weekly, label: "Weekly", percent: 64, reset: "Resets in 6d 4h", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 15)
                ),
            ],
            apiSpendProviders: [
                spend(
                    id: ProviderID.claude.raw,
                    displayName: "Anthropic API",
                    amount: 142.67
                ),
                spend(
                    id: ProviderID.codex.raw,
                    displayName: "OpenAI API",
                    amount: 58.90
                ),
            ]
        )
    }

    /// `fourProviders`: Claude + Codex (rolling windows) beside Grok + Cursor
    /// (billing-period meters, which project to `.other` widget windows), spend on. The
    /// four-provider screenshot/QA scenario (U12) — exercises every brand mark at once.
    /// Numbers mirror `DemoFixture.grokSnapshot`/`cursorSnapshot`.
    private static var fourProvidersEnvelope: WidgetSnapshotEnvelope {
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
                        window(.weekly, label: "Weekly", percent: 38, reset: "Resets Jul 9", severity: .low),
                        window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 54, reset: "Resets Jul 9", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 28)
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "Prolite",
                    freshness: .live,
                    windows: [
                        window(.weekly, label: "Weekly", percent: 64, reset: "Resets in 6d 4h", severity: .healthy),
                    ],
                    renewalDate: day(month: 7, day: 15)
                ),
                WidgetProviderSummary(
                    id: ProviderID.grok.raw,
                    displayName: "Grok",
                    planLabel: "SuperGrok",
                    freshness: .live,
                    windows: [
                        window(
                            .other("Weekly"),
                            label: "Weekly",
                            percent: 56,
                            reset: "Resets in 3d",
                            severity: .healthy,
                            billingPeriodDuration: 7 * 24 * 60 * 60
                        ),
                    ],
                    renewalDate: day(month: 8, day: 4)
                ),
                WidgetProviderSummary(
                    id: ProviderID.cursor.raw,
                    displayName: "Cursor",
                    planLabel: "Pro+",
                    freshness: .live,
                    windows: [
                        window(
                            .other("Monthly"),
                            label: "Monthly",
                            percent: 69,
                            reset: "Resets Sep 1",
                            severity: .healthy,
                            billingPeriodDuration: 30 * 24 * 60 * 60
                        ),
                    ],
                    renewalDate: day(month: 9, day: 1)
                ),
            ],
            apiSpendProviders: [
                spend(
                    id: ProviderID.claude.raw,
                    displayName: "Anthropic API",
                    amount: 142.67
                ),
                spend(
                    id: ProviderID.codex.raw,
                    displayName: "OpenAI API",
                    amount: 58.90
                ),
            ]
        )
    }

    // MARK: - Settings preview

    /// L9P: the frozen envelope behind the Settings › Widgets & iPhone preview strip.
    ///
    /// Unlike the `--demo` variants above it pins every date, so the small and medium
    /// tiles in Settings render the same picture on every pass — Settings is not a
    /// live-data surface, and a preview whose "Updated N min ago" footer ticked would
    /// invite the reader to trust it as real. Two providers with two windows each is the
    /// widget's own shape: `widgetProviders` caps the list at two, and small/medium show
    /// the overall period window (plus the 5-hour window on medium).
    public static let settingsPreviewNow = Date(timeIntervalSince1970: 1_800_000_000)

    public static let settingsPreviewEnvelope = WidgetSnapshotEnvelope(
        generatedAt: settingsPreviewNow.addingTimeInterval(-4 * 60),
        status: .enabled,
        providers: [
            WidgetProviderSummary(
                id: ProviderID.claude.raw,
                displayName: "Claude",
                planLabel: "Max",
                freshness: .live,
                windows: [
                    fixedWindow(.fiveHour, label: "5h", percent: 72, reset: "Resets 2:15 PM", severity: .healthy),
                    fixedWindow(.weekly, label: "Weekly", percent: 38, reset: "Resets Monday", severity: .low),
                ],
                renewalDate: nil
            ),
            WidgetProviderSummary(
                id: ProviderID.codex.raw,
                displayName: "Codex",
                planLabel: "Pro Lite",
                freshness: .live,
                windows: [
                    fixedWindow(.fiveHour, label: "5h", percent: 41, reset: "Resets 4:05 PM", severity: .healthy),
                    fixedWindow(.weekly, label: "Weekly", percent: 64, reset: "Resets in 6d 4h", severity: .healthy),
                ],
                renewalDate: nil
            ),
        ],
        apiSpendProviders: []
    )

    private static func fixedWindow(
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
            resetsAt: settingsPreviewNow.addingTimeInterval(3 * 3_600),
            resetLabel: reset,
            severity: severity
        )
    }

    // MARK: Helpers

    private static func window(
        _ kind: WidgetWindowKind,
        label: String,
        percent: Double,
        reset: String,
        severity: WidgetUsageSeverity,
        billingPeriodDuration: TimeInterval? = nil
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind,
            label: label,
            percentRemaining: percent,
            resetsAt: Date().addingTimeInterval(3 * 3_600),
            resetLabel: reset,
            severity: severity,
            billingPeriodDuration: billingPeriodDuration
        )
    }

    private static func spend(id: String, displayName: String, amount: Double) -> WidgetAPISpendSummary {
        WidgetAPISpendSummary(
            id: id,
            displayName: displayName,
            amount: amount,
            currency: "usd",
            periodLabel: "Current month",
            capturedAt: Date(),
            freshness: CommandLine.arguments.contains("--demo-stale-api-spend")
                ? .stale(message: "Demo cost data is stale", needsAttention: false)
                : .live
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
