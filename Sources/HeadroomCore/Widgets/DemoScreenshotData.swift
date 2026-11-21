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
    /// A `--demo-variant` launch argument wins (KTD21); otherwise reads the
    /// `companionDemoVariant` key from the app-group defaults when available;
    /// falls back to "full" if the variant is unset or unrecognized.
    public static var envelope: WidgetSnapshotEnvelope {
        let variant = CompanionDemoLaunchOptions.current.variant?.rawValue
            ?? CompanionDemoModeStore.appGroup().variant
        return self.envelope(for: variant)
    }

    /// Resolves a named demo fixture variant to its WidgetSnapshotEnvelope.
    /// Unknown variants, and v4 variants with no content (paused, waiting), fall back to the
    /// `full` fixture.
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
        case "fiveProviders":
            return fiveProvidersEnvelope
        case "sixProviders":
            return sixProvidersEnvelope
        default:
            // U7: a v4 variant chosen in Explore Demo reaches build-33 hosts as its
            // main-account projection (KTD13) until they adopt the resolved snapshot.
            return CompanionDemoVariant(token: variant)
                .flatMap { CompanionDemoData.snapshot($0, now: Date()).primaryProjection() }
                ?? fullEnvelope
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
                            .other("Cursor Models"),
                            label: "Cursor Models",
                            percent: 69,
                            reset: "Resets Sep 1",
                            severity: .healthy,
                            billingPeriodDuration: 30 * 24 * 60 * 60
                        ),
                        window(
                            .other("Other Models"),
                            label: "Other Models",
                            percent: 37,
                            reset: "Resets Sep 1",
                            severity: .low,
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

    /// `fiveProviders`: the four-provider moment plus Copilot's monthly credit pool, which
    /// carries no plan label (Copilot plan U7). Numbers mirror `DemoFixture.copilotSnapshot`.
    private static var fiveProvidersEnvelope: WidgetSnapshotEnvelope {
        let four = fourProvidersEnvelope
        let copilot = WidgetProviderSummary(
            id: ProviderID.copilot.raw,
            displayName: "Copilot",
            planLabel: nil,
            freshness: .live,
            windows: [
                window(
                    .other("Monthly"),
                    label: "Monthly",
                    percent: 76,
                    reset: "Resets Dec 1",
                    severity: .healthy,
                    billingPeriodDuration: 30 * 24 * 60 * 60
                ),
            ],
            renewalDate: day(month: 12, day: 1)
        )
        return WidgetSnapshotEnvelope(
            generatedAt: four.generatedAt,
            status: four.status,
            providers: four.providers + [copilot],
            apiSpendProviders: four.apiSpendProviders
        )
    }

    /// `sixProviders` (OpenCode plan U9, KTD14): the five-provider moment plus OpenCode Go's
    /// three windows, with no plan label (KTD19) and no spend row. Numbers mirror
    /// `DemoFixture.opencodeSnapshot`. The Lock Screen demo reads this envelope, so a widget
    /// pinned to OpenCode shows a reading rather than "Off".
    private static var sixProvidersEnvelope: WidgetSnapshotEnvelope {
        let five = fiveProvidersEnvelope
        let opencode = WidgetProviderSummary(
            id: ProviderID.opencode.raw,
            displayName: "OpenCode",
            planLabel: nil,
            freshness: .live,
            windows: [
                window(.fiveHour, label: "5h", percent: 82, reset: "Resets 1:40pm", severity: .healthy),
                window(.weekly, label: "Weekly", percent: 53, reset: "Resets in 3d 6h", severity: .healthy),
                window(
                    .other("Monthly"),
                    label: "Monthly",
                    percent: 29,
                    reset: "Resets Dec 1",
                    severity: .low,
                    billingPeriodDuration: 30 * 24 * 60 * 60
                ),
            ],
            renewalDate: day(month: 12, day: 4)
        )
        // Mirrors `DemoFixture.antigravitySnapshot`.
        let antigravity = WidgetProviderSummary(
            id: ProviderID.antigravity.raw,
            displayName: "Antigravity",
            planLabel: "1,200 credits",
            freshness: .live,
            windows: [
                window(.other("Gemini 5h"), label: "Gemini 5h", percent: 66, reset: "Resets 2:10pm", severity: .healthy),
                window(.other("Gemini weekly"), label: "Gemini weekly", percent: 79, reset: "Resets in 4d 2h", severity: .healthy),
                window(.other("Other weekly"), label: "Other weekly", percent: 42, reset: "Resets in 4d 2h", severity: .healthy),
                window(.other("Other 5h"), label: "Other 5h", percent: 88, reset: "Resets 2:19pm", severity: .healthy),
            ],
            renewalDate: nil
        )
        return WidgetSnapshotEnvelope(
            generatedAt: five.generatedAt,
            status: five.status,
            providers: five.providers.flatMap { $0.id == ProviderID.copilot.raw ? [antigravity, $0] : [$0] } + [opencode],
            apiSpendProviders: five.apiSpendProviders
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

    // MARK: - Widget style fixtures (2026-10-02 widget-styles plan, U2)

    /// Named envelopes for the widget-style render harness (`--render-widgets`). Each sets a
    /// widget provider selection and varied reset times so every style's provider, pool,
    /// stale, unavailable and pending paths are posed against a fixed `now`.
    public static let styleFixtureNames = [
        "claudeCodex", "claudeGrok", "codexCursor", "grokCursor", "tightClaudeCursor",
        "sparkOn", "staleUnavailable", "pending", "firstPending", "pendingAll", "pendingPools", "pendingCodex", "pendingCursor",
        "signedOut", "cursorOnly", "spend", "claudeCopilot", "copilotNoReading",
        "claudeOpenCode", "openCodeLimited", "openCodeNoGo",
    ]

    public static func styleFixture(_ name: String, now: Date) -> WidgetSnapshotEnvelope? {
        func w(
            _ kind: WidgetWindowKind, _ label: String, _ percent: Double,
            resetIn: TimeInterval, freshness: WidgetWindowFreshness = .live, pool: TimeInterval? = nil
        ) -> WidgetWindowSummary {
            WidgetWindowSummary(
                kind: kind,
                label: label,
                percentRemaining: percent,
                resetSchedule: .scheduled(now.addingTimeInterval(resetIn)),
                resetLabel: nil,
                observedAt: freshness.observedAt,
                severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: percent)),
                freshness: freshness,
                billingPeriodDuration: pool
            )
        }
        let hour: TimeInterval = 3_600, day: TimeInterval = 86_400
        func claude(_ a: Double, _ b: Double, _ c: Double, fiveHourReset: TimeInterval = 3.25 * hour, weekReset: TimeInterval = 4.25 * day,
                    fable: WidgetWindowFreshness = .live) -> WidgetProviderSummary {
            WidgetProviderSummary(id: ProviderID.claude.raw, displayName: "Claude", planLabel: "Max", freshness: .live, windows: [
                w(.fiveHour, "5h", a, resetIn: fiveHourReset),
                w(.weekly, "Weekly", b, resetIn: weekReset),
                w(.other("Weekly (Fable)"), "Weekly (Fable)", c, resetIn: weekReset, freshness: fable),
            ], renewalDate: nil)
        }
        func codex(_ a: Double, _ b: Double, spark: Double? = nil, freshness: WidgetProviderFreshness = .live,
                   windowFreshness: WidgetWindowFreshness = .live) -> WidgetProviderSummary {
            var windows = [
                w(.fiveHour, "5h", a, resetIn: 2.1 * hour, freshness: windowFreshness),
                w(.weekly, "Weekly", b, resetIn: 3.1 * day, freshness: windowFreshness),
            ]
            if let spark { windows.append(w(.other("Spark weekly"), "Spark weekly", spark, resetIn: 3.1 * day)) }
            return WidgetProviderSummary(id: ProviderID.codex.raw, displayName: "Codex", planLabel: "Pro Lite",
                                         freshness: freshness, windows: windows, renewalDate: nil)
        }
        func grok(_ a: Double, freshness: WidgetWindowFreshness = .live) -> WidgetProviderSummary {
            WidgetProviderSummary(id: ProviderID.grok.raw, displayName: "Grok", planLabel: "SuperGrok", freshness: .live, windows: [
                w(.other("Weekly"), "Weekly", a, resetIn: 3.2 * day, freshness: freshness, pool: 7 * day),
            ], renewalDate: nil)
        }
        func cursor(_ a: Double, _ b: Double, resetIn: TimeInterval = 2.2 * day) -> WidgetProviderSummary {
            WidgetProviderSummary(id: ProviderID.cursor.raw, displayName: "Cursor", planLabel: "Pro+", freshness: .live, windows: [
                w(.other("Cursor Models"), "Cursor Models", a, resetIn: resetIn, pool: 30 * day),
                w(.other("Other Models"), "Other Models", b, resetIn: resetIn, pool: 30 * day),
            ], renewalDate: nil)
        }
        // Copilot plan U7: one monthly pool, no plan label. Before the first quota snapshot the
        // row is unavailable: it keeps its label and prints no number.
        func copilot(_ a: Double, freshness: WidgetWindowFreshness = .live) -> WidgetProviderSummary {
            WidgetProviderSummary(id: ProviderID.copilot.raw, displayName: "Copilot", planLabel: nil, freshness: .live, windows: [
                w(.other("Monthly"), "Monthly", a, resetIn: 18.2 * day, freshness: freshness, pool: 30 * day),
            ], renewalDate: nil)
        }
        // OpenCode plan U9: Go's three windows, no plan label (KTD19). A no-Go workspace sends
        // the plan name "No Go plan" and one unavailable Monthly row (KTD7, KTD16); a limited
        // window reaches widgets only as 0% left with its reset (KTD21: no limited flag).
        func opencode(_ a: Double, _ b: Double, _ c: Double) -> WidgetProviderSummary {
            WidgetProviderSummary(id: ProviderID.opencode.raw, displayName: "OpenCode", planLabel: nil, freshness: .live, windows: [
                w(.fiveHour, "5h", a, resetIn: 2.7 * hour),
                w(.weekly, "Weekly", b, resetIn: 3.25 * day),
                w(.other("Monthly"), "Monthly", c, resetIn: 19 * day, pool: 30 * day),
            ], renewalDate: nil)
        }
        let opencodeNoGo = WidgetProviderSummary(
            id: ProviderID.opencode.raw, displayName: "OpenCode", planLabel: "No Go plan", freshness: .live, windows: [
                w(.other("Monthly"), "Monthly", 100, resetIn: 19 * day,
                  freshness: .unavailable(since: now.addingTimeInterval(-11 * day)), pool: 30 * day),
            ], renewalDate: nil)
        func spendRow(_ id: ProviderID, _ name: String, _ amount: Double) -> WidgetAPISpendSummary {
            WidgetAPISpendSummary(id: id.raw, displayName: name, amount: amount, currency: "usd",
                                  periodLabel: "Current month", capturedAt: now, freshness: .live)
        }
        func envelope(_ providers: [WidgetProviderSummary], spend: [WidgetAPISpendSummary] = []) -> WidgetSnapshotEnvelope {
            WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(-4 * 60), status: .enabled, providers: providers,
                                   apiSpendProviders: spend, widgetProviderSelection: providers.map(\.id))
        }
        let pending = WidgetProviderSummary(id: ProviderID.claude.raw, displayName: "Claude", planLabel: "Max",
                                            freshness: .pending, windows: [], renewalDate: nil)
        func waiting(_ id: ProviderID, _ name: String) -> WidgetProviderSummary {
            WidgetProviderSummary(id: id.raw, displayName: name, planLabel: nil,
                                  freshness: .pending, windows: [], renewalDate: nil)
        }
        // WCM5-v: a provider that needs the user, with no retained window — large prints its reason.
        let signedOut = WidgetProviderSummary(id: ProviderID.claude.raw, displayName: "Claude", planLabel: "Max",
                                              freshness: .stale(message: ProviderSetupOutcome.claudeLoginRequired.message, needsAttention: true),
                                              windows: [], renewalDate: nil)
        switch name {
        case "claudeCodex": return envelope([claude(72, 38, 54), codex(41, 64)])
        case "claudeGrok": return envelope([claude(72, 38, 54), grok(56)])
        case "codexCursor": return envelope([codex(41, 64), cursor(69, 37)])
        case "grokCursor": return envelope([grok(56), cursor(69, 37)])
        case "tightClaudeCursor":
            return envelope([claude(12, 9, 23, fiveHourReset: 1.66 * hour, weekReset: 1.1 * day), cursor(31, 8, resetIn: 6.1 * day)])
        case "sparkOn": return envelope([claude(72, 38, 54), codex(41, 64, spark: 22)])
        case "staleUnavailable":
            return envelope([
                claude(72, 38, 5, fable: .stale(observedAt: now.addingTimeInterval(-2 * hour))),
                codex(41, 64, freshness: .stale(message: "Codex could not be read", needsAttention: false),
                      windowFreshness: .unavailable(since: now.addingTimeInterval(-6 * hour))),
            ])
        case "pending": return envelope([pending, codex(41, 64)])
        case "firstPending": return envelope([pending, grok(56)])
        case "pendingAll": return envelope([pending, waiting(.codex, "Codex")])
        case "pendingPools": return envelope([waiting(.grok, "Grok"), waiting(.cursor, "Cursor")])
        case "pendingCodex": return envelope([waiting(.codex, "Codex")])
        case "pendingCursor": return envelope([waiting(.cursor, "Cursor")])
        case "signedOut": return envelope([signedOut, codex(41, 64)])
        case "cursorOnly": return envelope([cursor(69, 37)])
        case "spend":
            return envelope([claude(72, 38, 54), codex(41, 64)],
                            spend: [spendRow(.claude, "Anthropic API", 142.67), spendRow(.codex, "OpenAI API", 58.90)])
        case "claudeCopilot": return envelope([claude(72, 38, 54), copilot(76)])
        case "copilotNoReading":
            return envelope([claude(72, 38, 54), copilot(100, freshness: .unavailable(since: now.addingTimeInterval(-day)))])
        case "claudeOpenCode": return envelope([claude(72, 38, 54), opencode(82, 53, 29)])
        case "openCodeLimited": return envelope([opencode(78, 36, 0), codex(41, 64)])
        case "openCodeNoGo": return envelope([claude(72, 38, 54), opencodeNoGo])
        default: return nil
        }
    }

    /// U3 (2026-10-04 Lock Screen plan): extra fixtures never enter the home job set.
    public static let lockScreenFixtureNames = styleFixtureNames + [
        "thirdProviderTightest", "pinnedAbsent", "cursorLonePool", "cursorIncluded", "resetReached", "full", "empty",
    ]

    public static func lockScreenFixture(_ name: String, now: Date) -> WidgetSnapshotEnvelope? {
        if let home = styleFixture(name, now: now) { return home }
        func window(_ label: String, percent: Double, resetIn: TimeInterval = 3 * 86_400) -> WidgetWindowSummary {
            WidgetWindowSummary(
                kind: .other(label), label: label, percentRemaining: percent,
                resetSchedule: .scheduled(now.addingTimeInterval(resetIn)), resetLabel: nil,
                severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: percent)),
                billingPeriodDuration: 30 * 86_400
            )
        }
        func cursor(_ windows: [WidgetWindowSummary]) -> WidgetProviderSummary {
            WidgetProviderSummary(id: ProviderID.cursor.raw, displayName: "Cursor", planLabel: "Pro+",
                                  freshness: .live, windows: windows, renewalDate: nil)
        }
        func envelope(_ providers: [WidgetProviderSummary], selection: [String]? = nil) -> WidgetSnapshotEnvelope {
            WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(-240), status: .enabled,
                                   providers: providers, widgetProviderSelection: selection ?? providers.map(\.id))
        }
        switch name {
        case "full", "empty":
            return envelope(["claude", "codex", "grok", "cursor", "antigravity", "copilot", "opencode"].map { id in
                WidgetProviderSummary(id: id, displayName: ProviderID(id).displayName, planLabel: nil,
                    freshness: .live, windows: [WidgetWindowSummary(kind: .weekly, label: "Weekly",
                        percentRemaining: name == "full" ? 100 : 0,
                        resetSchedule: .scheduled(now.addingTimeInterval(86_400)), resetLabel: nil,
                        severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: name == "full" ? 100 : 0)))], renewalDate: nil)
            })
        case "thirdProviderTightest":
            guard let base = styleFixture("claudeCodex", now: now) else { return nil }
            return envelope(base.providers + [cursor([window("Cursor Models", percent: 69), window("Other Models", percent: 8)])],
                            selection: [ProviderID.claude.raw, ProviderID.codex.raw])
        case "pinnedAbsent":
            return styleFixture("claudeCodex", now: now)
        case "cursorLonePool":
            return envelope([cursor([window("Cursor Models", percent: 69)])])
        case "cursorIncluded":
            return envelope([cursor([window("Included", percent: 37)])])
        case "resetReached":
            let reached = WidgetWindowSummary(kind: .weekly, label: "Weekly", percentRemaining: 8,
                                              resetSchedule: .scheduled(now.addingTimeInterval(-60)),
                                              resetLabel: nil, severity: .critical)
            return envelope([WidgetProviderSummary(id: ProviderID.claude.raw, displayName: "Claude", planLabel: "Max",
                                                  freshness: .live, windows: [reached], renewalDate: nil)])
        default: return nil
        }
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
