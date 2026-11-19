import Foundation

/// Deterministic sample data for producing clean, repeatable product screenshots
/// (the marketing site at headroom.zantos.co). Activated by the `--demo` launch
/// argument. These numbers are the single source of truth for the mock, so the
/// menu-bar popover, the macOS widgets, and the iPhone all show the same moment.
///
/// This exists because the real providers read live local state: Claude/Codex usage
/// can't be posed on demand, and API spend needs admin keys the screenshot machine
/// may not have. Demo mode swaps the providers for fixed snapshots; every surface
/// still renders the real UI.
public enum DemoFixture {
    /// Hosted tests must remain inert even when Xcode omits scheme launch arguments.
    public static var isEnabled: Bool {
        CommandLine.arguments.contains("--demo")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Fixed-anchor loading captures never inherit wall-clock reset or capture dates.
    public static func loadingSnapshot(for id: ProviderID, at date: Date) -> UsageSnapshot {
        let windows: [UsageWindow]
        switch id {
        case .claude:
            windows = [UsageWindow(kind: .fiveHour, utilization: 28, resetsAt: date.addingTimeInterval(11_700)),
                       UsageWindow(kind: .weekly, utilization: 62, resetsAt: date.addingTimeInterval(345_600))]
        case .codex:
            windows = [UsageWindow(kind: .weekly, utilization: 36, resetsAt: date.addingTimeInterval(540_000))]
        case .opencode:
            // OpenCode plan KTD6: Go's three windows, in the order the card reads them.
            windows = [UsageWindow(kind: .fiveHour, utilization: 18, resetsAt: date.addingTimeInterval(9_600)),
                       UsageWindow(kind: .weekly, utilization: 47, resetsAt: date.addingTimeInterval(281_000)),
                       UsageWindow(kind: OpenCodeProvider.monthlyKind, utilization: 71, resetsAt: date.addingTimeInterval(1_641_600))]
        default:
            windows = [UsageWindow(kind: .billingPeriod(label: "Monthly", duration: 2_592_000),
                                   utilization: 44, resetsAt: date.addingTimeInterval(1_036_800))]
        }
        return UsageSnapshot(providerID: id, windows: windows, planLabel: "Demo",
                             accountEmail: "demo@example.com", capturedAt: date, freshness: .live)
    }

    // MARK: Subscription usage

    public static var claudeSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .claude,
            // Sorted through the parser's own rank so this literal cannot drift from what a
            // live capture renders again — it had shipped Weekly-before-5-hour into every
            // marketing shot.
            windows: ClaudeUsageParser.sortedForDisplay([
                UsageWindow(kind: .fiveHour, utilization: 28, resetsAt: soon(hours: 3, minutes: 15, seconds: 30), resetLabel: "Resets 2:15pm"),
                UsageWindow(kind: .weekly, utilization: 62, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 46, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
            ]),
            planLabel: "Max",
            // Placeholder identity — demo fixtures ship in the repo, so they never carry
            // a real address.
            accountEmail: "personal@example.com",
            // ~2 min ago so the popover/scene reads "Updated 2 min ago" (matches the
            // widget assets in the marketing scene and the design artboard).
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    public static var codexSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(kind: .weekly, utilization: 36, resetsAt: soon(days: 6, hours: 4, minutes: 30), resetLabel: "Resets in 6d 4h"),
            ],
            planLabel: "Prolite",
            accountEmail: "personal@example.com",
            capturedAt: Date().addingTimeInterval(-135),  // ~2 min ago (see claudeSnapshot)
            freshness: .live
        )
    }

    /// Grok bills a single weekly credit pool (billing-period window), not Claude's
    /// rolling 5h/weekly pair — mirror the real shape so the demo card reads honestly.
    public static var grokSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .grok,
            windows: [
                UsageWindow(
                    kind: BillingPeriodWindowClassifier.kind(periodType: "weekly", durationSeconds: nil),
                    utilization: 44,
                    resetsAt: soon(days: 3, hours: 2, minutes: 30),
                    resetLabel: "Resets in 3d"
                ),
            ],
            planLabel: "SuperGrok",
            accountEmail: "personal@example.com",  // placeholder (see claudeSnapshot)
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    /// Cursor bills two monthly pools with one calendar reset. Distinct values keep the
    /// demo useful for spotting collapsed, duplicated, reordered, or omitted rows.
    public static var cursorSnapshot: UsageSnapshot {
        let resetsAt = soon(days: 12)
        let duration = 30 * 24 * 60 * 60.0
        return UsageSnapshot(
            providerID: .cursor,
            windows: [
                UsageWindow(
                    kind: .billingPeriod(label: "Cursor Models", duration: duration),
                    utilization: 31,
                    resetsAt: resetsAt,
                    resetLabel: "Resets Sep 1"
                ),
                UsageWindow(
                    kind: .billingPeriod(label: "Other Models", duration: duration),
                    utilization: 63,
                    resetsAt: resetsAt,
                    resetLabel: "Resets Sep 1"
                ),
            ],
            planLabel: "Pro+",
            accountEmail: "personal@example.com",  // placeholder (see claudeSnapshot)
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    /// Copilot bills one monthly credit pool that resets on the first of the UTC month, and
    /// the CLI reports no plan name, so the row carries none (U7, Copilot plan).
    public static var copilotSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .copilot,
            windows: [
                UsageWindow(
                    kind: BillingPeriodWindowClassifier.kind(periodType: "monthly", durationSeconds: nil),
                    utilization: 24,
                    resetsAt: soon(days: 18, minutes: 30),
                    resetLabel: "Resets Dec 1"
                ),
            ],
            planLabel: nil,
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    /// A signed-in Copilot account with no usage reading yet: live, with one unavailable
    /// row, exactly what `CopilotProvider` returns before the first quota snapshot. The row
    /// keeps its label and must never print a number (0 used would read as 100 left).
    public static var copilotNoReadingSnapshot: UsageSnapshot {
        let monthStart = Calendar(identifier: .gregorian).dateInterval(of: .month, for: Date())?.start ?? Date()
        return UsageSnapshot(
            providerID: .copilot,
            windows: [
                UsageWindow(
                    kind: BillingPeriodWindowClassifier.kind(periodType: "monthly", durationSeconds: nil),
                    utilization: 0,
                    resetSchedule: .unresolved(.absent),
                    freshness: .unavailable(since: monthStart)
                ),
            ],
            planLabel: nil,
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    /// OpenCode plan U9: a Go workspace's three windows, shaped the way `OpenCodeProvider`
    /// builds them (KTD6): 5-hour, weekly and a 30-day Monthly pool, with distinct values so
    /// a render tells them apart. Go reports no plan name, workspace or email (KTD19).
    public static var opencodeSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .opencode,
            windows: [
                // 18% used → 82% left: healthy.
                UsageWindow(kind: .fiveHour, utilization: 18, resetsAt: soon(hours: 2, minutes: 40, seconds: 30), resetLabel: "Resets 1:40pm"),
                // 47% used → 53% left: healthy, just above the low band.
                UsageWindow(kind: .weekly, utilization: 47, resetsAt: soon(days: 3, hours: 6, minutes: 30), resetLabel: "Resets in 3d 6h"),
                // 71% used → 29% left: low.
                UsageWindow(kind: OpenCodeProvider.monthlyKind, utilization: 71, resetsAt: soon(days: 19, minutes: 30), resetLabel: "Resets Dec 1"),
            ],
            planLabel: nil,
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    /// OpenCode plan U9 (KTD7): signed in to a workspace with no Go plan. Exactly what
    /// `OpenCodeProvider` returns: live, one Monthly row unavailable since the UTC month
    /// start, and `planStatus` `.noActivePlan`. The card draws "No Go plan on this workspace"
    /// with See Go Plans and no meter; the phone reads the plan name "No Go plan".
    public static var opencodeNoGoSnapshot: UsageSnapshot {
        let monthStart = CopilotLedgerCalculator.utcMonth(containing: Date()).lowerBound
        return UsageSnapshot(
            providerID: .opencode,
            windows: [
                UsageWindow(
                    kind: OpenCodeProvider.monthlyKind,
                    utilization: 0,
                    resetSchedule: .unresolved(.absent),
                    freshness: .unavailable(since: monthStart)
                ),
            ],
            planLabel: nil,
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live,
            planStatus: .noActivePlan
        )
    }

    /// OpenCode plan U9 (KTD6, KTD15, KTD21): the monthly window at its limit, with the
    /// source's own `limited` word and a future reset, so Standard draws the red limited
    /// sentence under the identity row and Compact gives the monthly window a slot (it would
    /// otherwise sit behind "+1"). The other two windows still have room.
    public static var opencodeLimitedSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .opencode,
            windows: [
                UsageWindow(kind: .fiveHour, utilization: 22, resetsAt: soon(hours: 4, minutes: 10, seconds: 30), resetLabel: "Resets 3:10pm"),
                UsageWindow(kind: .weekly, utilization: 64, resetsAt: soon(days: 2, hours: 3, minutes: 30), resetLabel: "Resets in 2d 3h"),
                UsageWindow(
                    kind: OpenCodeProvider.monthlyKind,
                    utilization: 100,
                    resetSchedule: .scheduled(soon(days: 9, minutes: 30)),
                    resetLabel: "Resets Nov 21",
                    isLimited: true
                ),
            ],
            planLabel: nil,
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    // MARK: Settings Appearance specimen (U3 / KTD4)

    /// Synthetic account behind the Settings > Appearance specimen card. Its id is
    /// deliberately unlike `.primary` and every `multiFixture` id: `ProviderCardView`
    /// keys per-account setup state off the account, so a colliding id would let an
    /// inert preview read — or clear — a real Claude account's state.
    public static let settingsSpecimenAccount = ProviderAccount(
        id: AccountID("settings-appearance-specimen"),
        providerID: .claude,
        label: "Main",
        isBuiltIn: false
    )

    /// The specimen's usage. Its three windows deliberately land one per severity band
    /// (healthy > 50% remaining, low ≤ 50%, critical ≤ 15%): the shipping demo snapshots
    /// never reach critical, so `Color as event` and `Hue ramp` would preview as the same
    /// neutral meters and the fill choice would look inert.
    public static var settingsSpecimenSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .claude,
            windows: [
                // 26% used → 74% left: healthy.
                UsageWindow(kind: .fiveHour, utilization: 26, resetsAt: soon(hours: 3, minutes: 15, seconds: 30), resetLabel: "Resets 2:15pm"),
                // 68% used → 32% left: low.
                UsageWindow(kind: .weekly, utilization: 68, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
                // 91% used → 9% left: critical.
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 91, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
            ],
            planLabel: "Max",
            // Placeholder identity (see `claudeSnapshot`); the specimen is announced as a
            // single opaque element, so VoiceOver never reads it either way.
            accountEmail: "personal@example.com",
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    // MARK: Partial capture (R2B2)

    /// R2B2: the per-window `.unavailable` state, which no shipped fixture posed. It is the
    /// real shape of a partial Claude `/usage` capture (see `UsageContinuityPolicy`): the
    /// session and overall weekly rows stay live while a separately rendered model row drops
    /// out, keeps its label, loses its percentage, and outlives its validity window. Stacked
    /// under two live rows it is the only way to see whether the reserved suffix column holds
    /// the gauge and the "—" on the live rows' axis.
    public static var claudePartialCaptureSnapshot: UsageSnapshot {
        let observed = Date().addingTimeInterval(-135)
        return UsageSnapshot(
            providerID: .claude,
            windows: [
                UsageWindow(kind: .fiveHour, utilization: 28, resetsAt: soon(hours: 3, minutes: 15, seconds: 30), resetLabel: "Resets 2:15pm"),
                UsageWindow(kind: .weekly, utilization: 62, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
                // Retained past its validity window: the row stays, the number does not.
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 46,
                    resetsAt: soon(days: 4, minutes: 30),
                    resetLabel: "Resets Jul 9",
                    freshness: .unavailable(since: observed.addingTimeInterval(-3_600)),
                    observedAt: observed.addingTimeInterval(-3_600)
                ),
            ],
            planLabel: "Max",
            accountEmail: "personal@example.com",  // placeholder (see claudeSnapshot)
            capturedAt: observed,
            freshness: .live
        )
    }

    // MARK: API spend (macOS only)

    public static var anthropicSpend: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .claude,
            displayName: "Anthropic API",
            amount: 142.67,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date(),
            freshness: .live
        )
    }

    public static var openAISpend: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .codex,
            displayName: "OpenAI API",
            amount: 58.90,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date(),
            freshness: .live
        )
    }

    /// X5 review fixture: the key was rejected and nothing was ever retained, so the row is
    /// the shape Kyle photographed — no figure at all. `.needsReauth` is what
    /// `APISpendAttention(reason:)` maps to `.keyRejected`
    /// (`APISpendPresentation.swift:22`), the status that pairs a "Rejected" identity-line
    /// tag with a "Replace Key" chip — the popover renders Core's own copy here, so the
    /// reason's message is provenance rather than the line the card shows. With `amount` nil
    /// the amount column and the top-up slot collapse (X5), which is the whole point of the
    /// fixture.
    public static var anthropicSpendKeyRejected: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .claude,
            displayName: "Anthropic API",
            amount: nil,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date().addingTimeInterval(-3 * 3_600),
            freshness: .stale(.needsReauth("Anthropic admin key rejected"))
        )
    }

    /// X5 review fixture: the other half of the rejected-key story — continuity kept the last
    /// total, so the column and the reserved (glyph-less) top-up slot both hold. Only the
    /// `spend-retained` scenario poses this, because the two shapes cannot coexist on one row.
    public static var anthropicSpendKeyRejectedRetained: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .claude,
            displayName: "Anthropic API",
            amount: 142.67,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date().addingTimeInterval(-3 * 3_600),
            freshness: .stale(.needsReauth("Anthropic admin key rejected"))
        )
    }

    /// X5 review fixture: retryable staleness with the figure retained — the neutral "Stale"
    /// tag, a `.secondary` sentence and no action chip (the next poll may clear it on its
    /// own), which no shipped fixture reaches.
    public static var openAISpendStaleRetained: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .codex,
            displayName: "OpenAI API",
            amount: 58.90,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date().addingTimeInterval(-2 * 3_600),
            freshness: .stale(.transient("Couldn’t reach OpenAI. Headroom tries again on its next check."))
        )
    }

    /// S5A review fixture: xAI bills a prepaid pool, so its row is the one `.balance` row in
    /// the popover. `periodLabel` mirrors `XAIAPISpendProvider`'s own "Prepaid balance"; the
    /// card's chip reads "Remaining balance" off the `kind`, not off this label.
    public static var xaiBalanceSpend: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .grok,
            displayName: "xAI API",
            amount: 58.90,
            currency: "usd",
            periodLabel: "Prepaid balance",
            kind: .balance,
            capturedAt: Date(),
            freshness: .live
        )
    }

    /// S5A review fixture: Cursor is the one spend provider with no `addCreditsURL`, so its
    /// row draws the reserved-but-empty 18pt top-up slot — the thing that keeps every amount
    /// on one right edge when a neighbour can be topped up and this one cannot. Mirrors
    /// `CursorOnDemandSpendProvider`: display name "Cursor on-demand", on-demand dollars in
    /// usd, and the parser's reset-style `periodLabel` (`CursorProvider.swift:252-259`); the
    /// popover chip reads the store's period, so this label only reaches the widget mirror.
    public static var cursorOnDemandSpend: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .cursor,
            displayName: "Cursor on-demand",
            amount: 12.40,
            currency: "usd",
            periodLabel: "Resets Sep 1",
            capturedAt: Date(),
            freshness: .live
        )
    }

    // MARK: Manual renewal dates ("Plan renews Jul 28" / "Renews Jul 15")

    public static func renewalDate(for id: ProviderID) -> Date? {
        switch id {
        case .claude: return day(month: 7, day: 28)
        case .codex: return day(month: 7, day: 15)
        case .grok: return day(month: 8, day: 4)
        case .cursor: return day(month: 9, day: 1)
        case .copilot: return day(month: 12, day: 1)
        case .opencode: return day(month: 12, day: 4)
        default: return nil
        }
    }

    // MARK: Helpers

    /// A future `resetsAt` for demo windows. The popover renders these live via
    /// `Countdown.resetText`, which *truncates* the remaining time — so callers add a
    /// small `minutes:`/`seconds:` buffer to keep the displayed value on the intended
    /// minute/hour despite the ~1s capture delay (KTD5: the popover derives reset text
    /// from `resetsAt`, not `resetLabel`).
    private static func soon(days: Int = 0, hours: Int = 0, minutes: Int = 0, seconds: Int = 0) -> Date {
        Date().addingTimeInterval(TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds))
    }

    private static func day(month: Int, day: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year], from: Date())
        comps.month = month
        comps.day = day
        comps.hour = 10
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - Multi-account fixtures (demo mode, Jul 2026)

extension DemoFixture {
    /// Multi-account layouts under review (H3a band design): two accounts, three, five
    /// (popover scroll — all render at the regular meter scale now), the 20-per-provider
    /// tested envelope (`multi-20`), and a mixed-health stack (one live, one waiting on
    /// sign-in, one transiently stale).
    ///
    /// Shared between the offscreen `PopoverRenderHarness` (design-review PNGs) and the
    /// live `--demo <scenario>` launch mode (interactive multi-account preview + genuine
    /// Liquid-Glass screenshots), so both draw from one fixture source (demo mode, Jul 2026).
    public enum MultiAccountScenario: String, CaseIterable, Sendable {
        /// KTD16: the app adds controlled requests and an inert typed setup lifecycle.
        case loading
        case multiTwo = "multi-2"
        case multiThree = "multi-3"
        case multiFive = "multi-5"
        /// Popover account layout plan: the reported case, 7 Claude + 1 Codex, which needs a
        /// second column (Standard) or the Compact rows to fit without scrolling.
        case multiSeven = "multi-7"
        /// R15 (2026-09-19 polling plan): the tested envelope — 20 Claude, 20 Codex, 20 Grok,
        /// 1 Cursor. Claude and Grok rows simulate a 4-second probe: 20 × 4 s spends the
        /// 2-minute interval's 120 s budget partway through the second pass, so the measured
        /// duty-cycle gate and the Settings cadence row are observable (3 s would sit exactly
        /// on the ceiling and never close it).
        case envelope = "multi-20"
        case multiMixed = "multi-mixed"
        /// Two Claude accounts under a provider-wide missing-CLI verdict: one retains
        /// last-known meters and one has never produced usage. Exercises U3 recovery UI.
        case capabilityFailure = "capability-failure"
        // All four providers, one built-in account each — the four-provider screenshot/QA
        // scenario (U12). Shows Claude/Codex's rolling windows beside Grok/Cursor's
        // billing-period meters, exercising every brand mark and window shape at once.
        case multiProviders = "multi-4"
        /// All four providers with their untouched built-in "Main" label. The identity
        /// resolver turns these into provider names only at presentation time (KTD10).
        case fourDefault = "four-default"
        /// Default labels plus a case-insensitive renamed collision, with distinct
        /// addresses so the persistent-email treatment visibly disambiguates every row.
        case duplicateLabels = "dup-labels"
        /// S5A: the same four provider cards as `multi-4`, but the API spend card poses the
        /// states no other scenario reaches — a rejected key holding a retained total, a
        /// plain live row, and xAI's prepaid balance. Every shipped spend fixture is `.live`
        /// period spend, so the tag, the wrapping message, the card-foot chip and the
        /// balance row's column alignment had no way to be seen in the live popover.
        case spendStates = "spend-states"
        /// R2B2: one Claude account whose model row has gone `.unavailable` while its
        /// session and weekly rows stay live — the partial-capture shape, and the only
        /// scenario that shows a row with no percentage under two rows that have one.
        case windowUnavailable = "window-unavailable"
        /// X5: the same four rows, but with both retained-figure states posed — a rejected
        /// key still showing its last total (column and reserved top-up slot held), and a
        /// retryable stale row. `spend-states` can only pose one shape per row, and the
        /// nil-amount collapse is the shape it exists to show.
        case spendRetained = "spend-retained"
        /// Codex banked resets: a long healthy title with two credits, one Critical account
        /// with one credit, a reported-zero Codex row, and a Claude row with no count.
        case bankedResets = "banked-resets"
        /// Copilot plan U7: every registered provider, one built-in account each. `multi-5`
        /// already means five accounts, so the name says providers.
        case fiveProviders = "five-providers"
        /// Copilot plan U7: a signed-in Copilot account before its first usage reading, beside
        /// a live Claude account. The Copilot row shows its label and no number.
        case copilotNoReading = "copilot-no-reading"
        /// OpenCode plan U9 (KTD14): every registered provider, one built-in account each.
        /// `five-providers` stays the five providers before OpenCode.
        case sixProviders = "six-providers"
        /// OpenCode plan U9 (KTD7): a Console sign-in whose workspace has no Go plan, beside a
        /// live Claude account. The card shows the sentence and See Go Plans, with no meter.
        case opencodeNoGo = "opencode-no-go"
        /// OpenCode plan U9 (KTD3, KTD21): an installed OpenCode older than 2.2, beside a live
        /// Claude account: "Go usage needs OpenCode 2.2 or newer" with About OpenCode 2.
        case opencodeUpdate = "opencode-update"
        /// OpenCode plan U9 (KTD15, KTD21): two OpenCode accounts, a healthy built-in and an
        /// extra whose monthly window is limited, beside a live Claude account. Standard shows
        /// the red limited sentence; Compact gives the limited monthly window a slot, where it
        /// names itself under the healthy row's 5-hour header column.
        case opencodeLimited = "opencode-limited"
        /// Default-login plan U11 (mock scenario A, steps 2 and 4; AE1, AE2): Claude and
        /// Codex each show a live default ("Personal") and two accounts the default login
        /// left. "Work" was read two minutes ago and is before both resets, so it is dimmed
        /// with its numbers; "Studio" was read two days ago and both its resets have passed,
        /// so it shows none. The remembered rows come from an in-memory record store seeded
        /// by `defaultLoginRecords`; nothing is read from a CLI file or the user's defaults.
        case remembered
        /// Default-login plan U10 (mock scenario B, step 2; AE4): the default login moved
        /// to the account "Account 2" already reads with its own sign-in, so Claude and Codex
        /// each show "Account 2" once, live, and "Esper Labs" dimmed with the work account's
        /// last reading. The built-in row is still read but hidden. The bindings come from an
        /// in-memory record store seeded by `defaultLoginRecords`, for Claude as for Codex:
        /// a demo launch reads no CLI file (`AppComposition.claudeIdentityReader` is nil).
        case merged
    }

    /// Canonical demo provider order, mirroring `AppComposition`'s subscription registry.
    /// Parity checks derive their expected provider list from this instead of hardcoding a
    /// Claude/Codex literal (KTD9 switch-site inventory).
    public static let registeredProviderOrder: [ProviderID] = [.claude, .codex, .grok, .cursor, .copilot, .opencode]

    /// One scenario resolved to its accounts + one fixture provider per account.
    public struct MultiAccountFixture: Sendable {
        public let accounts: [ProviderAccount]
        public let providers: [any UsageProvider]
        /// Optional last-known values posed before the first demo refresh. Capability
        /// failures intentionally withhold account snapshots, exactly like production.
        public let continuitySnapshots: [AccountKey: UsageSnapshot]
        /// Default-login plan U11: the encoded record envelope the scenario starts from.
        /// Nil for every scenario but `remembered` and `merged`, which leaves each other
        /// display list equal to its engine list (R15).
        public let defaultLoginRecords: Data?

        /// The inert record store every demo, render and bench host composes with: a fresh
        /// in-memory copy of the seed per store, so no run reads or writes the user's
        /// `defaultLoginRecords.v1` and none inherits another run's changes.
        public func makeDefaultLoginRecordStore() -> DemoDefaultLoginRecordStore {
            DemoDefaultLoginRecordStore(seed: defaultLoginRecords)
        }
    }

    /// One deterministic account fixture: label + plan + varied utilizations so the
    /// severity ramp (healthy/low/critical) and plan pills all appear in review shots.
    public static func demoAccount(
        provider providerID: ProviderID,
        id: String,
        label: String,
        plan: String,
        fiveHour: Double,
        weekly: Double,
        email: String? = nil,
        bankedResets: Int? = nil,
        freshness: Freshness = .live,
        builtIn: Bool = false,
        capability: ProviderCapabilityState? = nil,
        probeDuration: TimeInterval? = nil
    ) -> (account: ProviderAccount, provider: any UsageProvider) {
        let accountID: AccountID = builtIn ? .primary : AccountID(id)
        let account = ProviderAccount(id: accountID, providerID: providerID, label: label, isBuiltIn: builtIn)
        let windows: [UsageWindow]
        // Placeholder identity derived from the label ("Work" → work@example.com) — demo
        // fixtures ship in the repo, so they never carry a real address. An account still
        // waiting on sign-in has no email to show yet, same as it has no windows.
        var snapshotEmail: String? = email ?? "\(label.lowercased())@example.com"
        switch freshness {
        case .stale(let reason) where reason.isPermanent:
            windows = []
            snapshotEmail = nil
        default:
            windows = [
                UsageWindow(kind: .fiveHour, utilization: fiveHour, resetsAt: Date().addingTimeInterval(3.2 * 3600), resetLabel: "Resets 2:15pm"),
                UsageWindow(kind: .weekly, utilization: weekly, resetsAt: Date().addingTimeInterval(4 * 86_400), resetLabel: "Resets Jul 20"),
            ]
        }
        let snapshot = UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: plan,
            accountEmail: snapshotEmail,
            bankedResets: bankedResets,
            capturedAt: Date().addingTimeInterval(-135),
            freshness: freshness
        )
        return (
            account,
            DemoUsageProvider(
                id: providerID,
                displayName: providerID.displayName,
                snapshot: snapshot,
                accountID: accountID,
                capability: capability,
                probeDuration: probeDuration
            )
        )
    }

    /// R15: N deterministic accounts for one provider, the first built-in, with labels and
    /// utilizations spread from a seed so a 20-row list still shows every severity band.
    /// Grok rows pose the billing-period snapshot because `demoAccount`'s 5h/weekly pair
    /// is not that provider's window shape.
    public static func generatedAccounts(
        provider providerID: ProviderID,
        count: Int,
        probeDuration: TimeInterval? = nil
    ) -> [(account: ProviderAccount, provider: any UsageProvider)] {
        let plans = ["Max", "Pro", "Team", "Plus", "Prolite"]
        return (0..<count).map { index -> (account: ProviderAccount, provider: any UsageProvider) in
            let label = index == 0 ? "Personal" : "Account \(index + 1)"
            let id = "\(providerID.raw)-generated-\(index + 1)"
            if providerID == .grok {
                let accountID: AccountID = index == 0 ? .primary : AccountID(id)
                let account = ProviderAccount(id: accountID, providerID: .grok, label: label, isBuiltIn: index == 0)
                let provider: any UsageProvider = DemoUsageProvider(
                    id: .grok,
                    displayName: ProviderID.grok.displayName,
                    snapshot: grokSnapshot,
                    accountID: accountID,
                    probeDuration: probeDuration
                )
                return (account: account, provider: provider)
            }
            return demoAccount(
                provider: providerID,
                id: id,
                label: label,
                plan: plans[index % plans.count],
                fiveHour: Double((index * 37) % 100),
                weekly: Double((index * 53 + 11) % 100),
                builtIn: index == 0,
                probeDuration: probeDuration
            )
        }
    }

    /// The `multi-20` envelope without its simulated 4s probes, so one refresh lands every row
    /// at once: what the bench and the render harness measure and capture.
    public static func settledEnvelopePairs() -> [(account: ProviderAccount, provider: any UsageProvider)] {
        generatedAccounts(provider: .claude, count: 20)
            + generatedAccounts(provider: .codex, count: 20)
            + generatedAccounts(provider: .grok, count: 20)
            + [builtInProviderPair(provider: .cursor, snapshot: cursorSnapshot),
               builtInProviderPair(provider: .copilot, snapshot: copilotSnapshot)]
    }

    /// A single built-in account posed from a ready-made snapshot — used for the
    /// billing-period providers (Grok/Cursor) whose window shape doesn't fit `demoAccount`'s
    /// fixed 5h/weekly pair.
    private static func builtInProviderPair(
        provider providerID: ProviderID,
        snapshot: UsageSnapshot,
        label: String? = nil
    ) -> (account: ProviderAccount, provider: any UsageProvider) {
        let account = ProviderAccount(
            id: .primary,
            providerID: providerID,
            label: label ?? providerID.displayName,
            isBuiltIn: true
        )
        return (account, DemoUsageProvider(id: providerID, displayName: providerID.displayName, snapshot: snapshot, accountID: .primary))
    }

    private static func capabilityFailurePair(
        id: String,
        label: String,
        builtIn: Bool
    ) -> (account: ProviderAccount, provider: any UsageProvider) {
        let accountID: AccountID = builtIn ? .primary : AccountID(id)
        let account = ProviderAccount(
            id: accountID,
            providerID: .claude,
            label: label,
            isBuiltIn: builtIn
        )
        let provider = DemoUsageProvider(
            id: .claude,
            displayName: ProviderID.claude.displayName,
            snapshot: .pending(for: .claude),
            accountID: accountID,
            capability: .confirmedAbsent
        )
        return (account, provider)
    }

    public static func multiFixture(for scenario: MultiAccountScenario) -> MultiAccountFixture {
        var pairs: [(account: ProviderAccount, provider: any UsageProvider)] = []
        switch scenario {
        case .loading:
            pairs = registeredProviderOrder.map { id in
                builtInProviderPair(provider: id, snapshot: id == .codex
                    ? .stale(for: id, reason: .notLoggedIn(UsageStore.finishSignInMessage))
                    : loadingSnapshot(for: id, at: Date()))
            }
            let work = ProviderAccount(id: AccountID("loading-work"), providerID: .claude, label: "Work")
            let pending = ProviderAccount(id: AccountID("loading-pending"), providerID: .claude, label: "Pending")
            pairs += [
                (work, DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: loadingSnapshot(for: .claude, at: Date()), accountID: work.id)),
                (pending, DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude), accountID: pending.id)),
            ]
        case .multiTwo:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
                demoAccount(provider: .codex, id: "codex-main", label: "Main", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
            ]
        case .multiThree:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
                demoAccount(provider: .claude, id: "studio", label: "Studio", plan: "Max", fiveHour: 12, weekly: 41),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                demoAccount(provider: .codex, id: "codex-work", label: "Work", plan: "Pro", fiveHour: 54, weekly: 79),
            ]
        case .multiFive:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
                demoAccount(provider: .claude, id: "studio", label: "Studio", plan: "Max", fiveHour: 12, weekly: 41),
                demoAccount(provider: .claude, id: "agency", label: "Agency", plan: "Team", fiveHour: 47, weekly: 55),
                demoAccount(provider: .claude, id: "lab", label: "Lab", plan: "Pro", fiveHour: 93, weekly: 97),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                demoAccount(provider: .codex, id: "codex-work", label: "Work", plan: "Pro", fiveHour: 54, weekly: 79),
                demoAccount(provider: .codex, id: "codex-studio", label: "Studio", plan: "Plus", fiveHour: 22, weekly: 48),
            ]
        case .multiSeven:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
                demoAccount(provider: .claude, id: "studio", label: "Studio", plan: "Max", fiveHour: 12, weekly: 41),
                demoAccount(provider: .claude, id: "agency", label: "Agency", plan: "Team", fiveHour: 47, weekly: 55),
                demoAccount(provider: .claude, id: "lab", label: "Lab", plan: "Pro", fiveHour: 93, weekly: 97),
                demoAccount(provider: .claude, id: "client", label: "Client", plan: "Max", fiveHour: 64, weekly: 30),
                demoAccount(provider: .claude, id: "side", label: "Side", plan: "Pro", fiveHour: 85, weekly: 72),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
            ]
        case .envelope:
            pairs = generatedAccounts(provider: .claude, count: 20, probeDuration: 4)
                + generatedAccounts(provider: .codex, count: 20)
                + generatedAccounts(provider: .grok, count: 20, probeDuration: 4)
                + [builtInProviderPair(provider: .cursor, snapshot: cursorSnapshot),
                   builtInProviderPair(provider: .copilot, snapshot: copilotSnapshot)]
        case .multiMixed:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 0, weekly: 0,
                            freshness: .stale(.notLoggedIn(UsageStore.finishSignInMessage))),
                // S2B/B3: the only state that renders a *two*-chip action row — a typed
                // setup outcome carries both a primary and a secondary recovery, where the
                // bare `.notLoggedIn` row above it carries one. No `--demo` scenario reached
                // it, so the leading two-chip row had no way to be seen live.
                demoAccount(provider: .claude, id: "studio", label: "Studio", plan: "Max", fiveHour: 0, weekly: 0,
                            freshness: .stale(.providerSetup(.claudeLoginRequired))),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                demoAccount(provider: .codex, id: "codex-work", label: "Work", plan: "Pro", fiveHour: 54, weekly: 79,
                            freshness: .stale(.transient("Couldn’t reach Codex. Headroom tries again on its next check."))),
            ]
        case .capabilityFailure:
            pairs = [
                capabilityFailurePair(
                    id: "personal",
                    label: "Personal",
                    builtIn: true
                ),
                capabilityFailurePair(
                    id: "work",
                    label: "Work",
                    builtIn: false
                ),
            ]
        // S5A: `spend-states` differs from `multi-4` only in the spend snapshots the app
        // wires beside it, so the two share one account list — a second copy would drift.
        case .multiProviders, .spendStates, .spendRetained:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                builtInProviderPair(provider: .grok, snapshot: grokSnapshot),
                builtInProviderPair(provider: .cursor, snapshot: cursorSnapshot),
            ]
        case .fiveProviders:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                builtInProviderPair(provider: .grok, snapshot: grokSnapshot),
                builtInProviderPair(provider: .cursor, snapshot: cursorSnapshot),
                builtInProviderPair(provider: .copilot, snapshot: copilotSnapshot),
            ]
        case .copilotNoReading:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                builtInProviderPair(provider: .copilot, snapshot: copilotNoReadingSnapshot),
            ]
        case .sixProviders:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                builtInProviderPair(provider: .grok, snapshot: grokSnapshot),
                builtInProviderPair(provider: .cursor, snapshot: cursorSnapshot),
                builtInProviderPair(provider: .copilot, snapshot: copilotSnapshot),
                builtInProviderPair(provider: .opencode, snapshot: opencodeSnapshot),
            ]
        case .opencodeNoGo:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                builtInProviderPair(provider: .opencode, snapshot: opencodeNoGoSnapshot),
            ]
        case .opencodeUpdate:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                builtInProviderPair(
                    provider: .opencode,
                    snapshot: .stale(for: .opencode, reason: .providerSetup(.opencodeUpdateRequired))
                ),
            ]
        case .opencodeLimited:
            let work = ProviderAccount(id: AccountID("opencode-work"), providerID: .opencode, label: "Work")
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                builtInProviderPair(provider: .opencode, snapshot: opencodeSnapshot, label: "Personal"),
                (work, DemoUsageProvider(id: .opencode, displayName: ProviderID.opencode.displayName,
                                         snapshot: opencodeLimitedSnapshot, accountID: work.id)),
            ]
        case .remembered:
            // Mock scenario A: the default login moved to the personal account. Its live
            // numbers are the mock's (96% and 69% left).
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 4, weekly: 31, builtIn: true),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 4, weekly: 31, builtIn: true),
            ]
        case .merged:
            // Mock scenario B, step 2: gmail is 96% and 69% left, the same on the built-in
            // and on Account 2, since both read it.
            for providerID in [ProviderID.claude, .codex] {
                let prefix = providerID.raw
                pairs += [
                    demoAccount(provider: providerID, id: "\(prefix)-main", label: "Main", plan: "Max",
                                fiveHour: 4, weekly: 31, email: "m.example@gmail.example", builtIn: true),
                    demoAccount(provider: providerID, id: "\(prefix)-account-2", label: "Account 2", plan: "Max",
                                fiveHour: 4, weekly: 31, email: "m.example@gmail.example"),
                ]
            }
        case .windowUnavailable:
            pairs = [
                builtInProviderPair(provider: .claude, snapshot: claudePartialCaptureSnapshot, label: "Personal"),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
            ]
        case .fourDefault:
            pairs = [
                demoAccount(
                    provider: .claude,
                    id: "claude-main",
                    label: "Main",
                    plan: "Max",
                    fiveHour: 28,
                    weekly: 62,
                    email: "claude-main@example.com",
                    builtIn: true
                ),
                demoAccount(
                    provider: .codex,
                    id: "codex-main",
                    label: "Main",
                    plan: "Prolite",
                    fiveHour: 9,
                    weekly: 36,
                    email: "codex-main@example.com",
                    builtIn: true
                ),
                builtInProviderPair(provider: .grok, snapshot: grokSnapshot, label: "Main"),
                builtInProviderPair(provider: .cursor, snapshot: cursorSnapshot, label: "Main"),
            ]
        case .bankedResets:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(
                    provider: .codex,
                    id: "codex-main",
                    label: "Northwind Research Workspace",
                    plan: "Plus",
                    fiveHour: 9,
                    weekly: 36,
                    bankedResets: 2,
                    builtIn: true
                ),
                demoAccount(
                    provider: .codex,
                    id: "codex-critical",
                    label: "On call",
                    plan: "Plus",
                    fiveHour: 88,
                    weekly: 36,
                    bankedResets: 1
                ),
                demoAccount(
                    provider: .codex,
                    id: "codex-zero",
                    label: "Quiet",
                    plan: "Plus",
                    fiveHour: 22,
                    weekly: 48,
                    bankedResets: 0
                ),
            ]
        case .duplicateLabels:
            pairs = [
                demoAccount(
                    provider: .claude,
                    id: "main",
                    label: "Main",
                    plan: "Max",
                    fiveHour: 28,
                    weekly: 62,
                    email: "main@example.com",
                    builtIn: true
                ),
                demoAccount(
                    provider: .claude,
                    id: "second",
                    label: "Account 2",
                    plan: "Pro",
                    fiveHour: 71,
                    weekly: 88,
                    email: "second@example.com"
                ),
                demoAccount(
                    provider: .claude,
                    id: "work-primary",
                    label: "Work",
                    plan: "Max",
                    fiveHour: 12,
                    weekly: 41,
                    email: "work-primary@example.com"
                ),
                demoAccount(
                    provider: .claude,
                    id: "work-secondary",
                    label: "work",
                    plan: "Team",
                    fiveHour: 47,
                    weekly: 55,
                    email: "work-secondary@example.com"
                ),
            ]
        }
        let continuitySnapshots: [AccountKey: UsageSnapshot] = if scenario == .capabilityFailure {
            [AccountKey(providerID: .claude, accountID: .primary): claudeSnapshot]
        } else {
            [:]
        }
        let records: Data? = switch scenario {
        case .remembered: rememberedRecords(at: Date())
        case .merged: mergedRecords(at: Date())
        default: nil
        }
        return MultiAccountFixture(
            accounts: pairs.map(\.account),
            providers: pairs.map(\.provider),
            continuitySnapshots: continuitySnapshots,
            defaultLoginRecords: records
        )
    }

    /// U10: the `merged` scenario's record envelope. Each provider's built-in slot and its
    /// "Account 2" slot are bound to one strong identity, the gmail account, so the one-row
    /// merge shows "Account 2" alone; "Esper Labs" is the remembered work account, read two
    /// minutes ago (AE4). Fixture readings carry no identity, so no read changes the records.
    /// Placeholder digests only, posed from fixture data: a demo launch reads no CLI file
    /// (`AppComposition.claudeIdentityReader` is nil).
    static func mergedRecords(at now: Date) -> Data? {
        var state = DefaultLoginRecordsState()
        for providerID in [ProviderID.claude, .codex] {
            let prefix = providerID.raw
            let gmail = AccountIdentity(
                providerID: providerID, strength: .strong,
                digest: "demo-\(prefix)-gmail", digestVersion: AccountIdentity.currentDigestVersion
            )
            for accountID in [AccountID.primary, AccountID("\(prefix)-account-2")] {
                var slot = SlotRecord(key: AccountKey(providerID: providerID, accountID: accountID))
                slot.binding = gmail
                // The demo has no continuity record, and this build did not remove one by
                // accident: nothing to repair at launch (KTD6).
                slot.continuityRemoved = true
                state.slots.append(slot)
            }
            let readAt = now.addingTimeInterval(-120)
            var esper = RememberedAccount(
                id: AccountID("merged-\(prefix)-esper"),
                providerID: providerID,
                identity: AccountIdentity(
                    providerID: providerID, strength: .strong,
                    digest: "demo-\(prefix)-work", digestVersion: AccountIdentity.currentDigestVersion
                ),
                label: "Esper Labs",
                email: "m.example@work.example",
                lastReadAt: readAt
            )
            // Mock scenario B: 22% and 10% left, resets in 1h 08m and 2d 4h.
            esper.snapshot = StoredSnapshot(key: esper.key, snapshot: UsageSnapshot(
                providerID: providerID,
                windows: [
                    UsageWindow(kind: .fiveHour, utilization: 78, resetsAt: now.addingTimeInterval(68 * 60 + 30)),
                    UsageWindow(kind: .weekly, utilization: 90, resetsAt: now.addingTimeInterval(2 * 86_400 + 4 * 3_600 + 30 * 60)),
                ],
                planLabel: "Team",
                accountEmail: "m.example@work.example",
                capturedAt: readAt,
                freshness: .live
            ))
            state.remembered.append(esper)
        }
        return DefaultLoginRecordsCodec.encode(state)
    }

    /// U11: the `remembered` scenario's record envelope, relative to `now` like every other
    /// fixture's dates. Only remembered entries, no slots: the live rows carry no identity,
    /// so no reading changes the records and the rows stay posed for the whole run.
    ///
    /// Codex entries carry a strong identity digest of a placeholder id, as a real remembered
    /// Codex row would. Claude entries carry none, although a real remembered Claude row now
    /// would: a remembered row does not need one to be shown, and a demo launch reads no CLI
    /// file (`AppComposition.claudeIdentityReader` is nil), so no reading can rebind it.
    static func rememberedRecords(at now: Date) -> Data? {
        func entry(
            _ providerID: ProviderID,
            id: String,
            label: String,
            plan: String,
            readAgo: TimeInterval,
            fiveHour: (used: Double, resetsIn: TimeInterval),
            weekly: (used: Double, resetsIn: TimeInterval)
        ) -> RememberedAccount {
            let readAt = now.addingTimeInterval(-readAgo)
            let email = "\(label.lowercased())@example.com"  // placeholder (see claudeSnapshot)
            var account = RememberedAccount(
                id: AccountID(id),
                providerID: providerID,
                identity: providerID == .codex ? AccountIdentity.codex(accountID: "demo-\(id)") : nil,
                label: label,
                email: email,
                lastReadAt: readAt
            )
            let snapshot = UsageSnapshot(
                providerID: providerID,
                windows: [
                    UsageWindow(kind: .fiveHour, utilization: fiveHour.used, resetsAt: now.addingTimeInterval(fiveHour.resetsIn)),
                    UsageWindow(kind: .weekly, utilization: weekly.used, resetsAt: now.addingTimeInterval(weekly.resetsIn)),
                ],
                planLabel: plan,
                accountEmail: email,
                capturedAt: readAt,
                freshness: .live
            )
            account.snapshot = StoredSnapshot(key: account.key, snapshot: snapshot)
            return account
        }
        var remembered: [RememberedAccount] = []
        for (providerID, prefix) in [(ProviderID.claude, "claude"), (.codex, "codex")] {
            remembered += [
                // AE1: read two minutes ago, 22% and 10% left, both resets ahead (1h 08m, 2d 4h).
                entry(providerID, id: "remembered-\(prefix)-work", label: "Work",
                      plan: providerID == .claude ? "Team" : "Pro", readAgo: 120,
                      fiveHour: (78, 68 * 60 + 30), weekly: (90, 2 * 86_400 + 4 * 3_600 + 30 * 60)),
                // AE2: read two days ago; the 5-hour window reset three hours after the read
                // and the weekly one six hours ago, so no number is shown.
                entry(providerID, id: "remembered-\(prefix)-studio", label: "Studio",
                      plan: providerID == .claude ? "Pro" : "Plus", readAgo: 2 * 86_400,
                      fiveHour: (40, -2 * 86_400 + 3 * 3_600), weekly: (65, -6 * 3_600)),
            ]
        }
        return DefaultLoginRecordsCodec.encode(DefaultLoginRecordsState(remembered: remembered))
    }

    /// What `--demo` asked for (demo mode, Jul 2026). A bare `--demo` keeps the existing
    /// single-account screenshot fixtures (the marketing hero + widget App-Group export
    /// that `Scripts/capture-demo-screenshots.sh` relies on); `--demo <scenario>` opts into
    /// the isolated multi-account preview store. An unrecognized token is surfaced so the
    /// entry point can print the valid list and exit — never silently falling back.
    public enum DemoScenarioRequest: Sendable, Equatable {
        case notRequested                     // `--demo` absent
        case singleAccount                    // bare `--demo` (screenshot fixtures, unchanged)
        case multiAccount(MultiAccountScenario)
        case invalid(String)                  // `--demo <unknown-token>`
    }

    /// Parse the `--demo` request from process arguments. Injectable for tests. The token
    /// immediately after `--demo` selects a scenario; a following flag (or no token) is a
    /// bare `--demo`. Kept out of `isEnabled` so existing callers stay untouched.
    public static func scenarioRequest(arguments: [String] = CommandLine.arguments) -> DemoScenarioRequest {
        guard let flagIndex = arguments.firstIndex(of: "--demo") else { return .notRequested }
        let next = arguments.indices.contains(flagIndex + 1) ? arguments[flagIndex + 1] : nil
        guard let token = next, !token.hasPrefix("-") else { return .singleAccount }
        if let scenario = MultiAccountScenario(rawValue: token) { return .multiAccount(scenario) }
        return .invalid(token)
    }
}

/// A `UsageProvider` that returns a fixed snapshot — screenshot demo mode only.
/// Keychain stand-in for demo and render runs: every read reports "no key", so the API
/// Spend rows render their editor state and the process never touches the real Keychain.
/// The unsigned debug binary otherwise raises one macOS Keychain prompt per provider each
/// time Settings mounts, and "Always Allow" cannot stick because its signature changes on
/// every rebuild.
public struct DemoAPIKeyStore: APIKeyStoring {
    public init() {}
    public func readAPIKey(for provider: APIKeyProvider) throws -> String { throw CredentialError.notLoggedIn }
    public func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws { throw CredentialError.notLoggedIn }
    public func deleteAPIKey(for provider: APIKeyProvider) throws { throw CredentialError.notLoggedIn }
}

/// Default-login plan U11: the record store for demo, render, bench and hosted-test stores.
/// Held in memory and seeded from the fixture, so those hosts never read or write the
/// `defaultLoginRecords.v1` key in any defaults domain, the way the inert duplicate
/// detector never reads a `.claude.json`.
public final class DemoDefaultLoginRecordStore: DefaultLoginRecordStoring, @unchecked Sendable { // guarded by `lock`
    private let lock = NSLock()
    private var data: Data?
    private var writes = 0

    public init(seed: Data? = nil) { data = seed }

    public func read() -> Data? { lock.withLock { data } }

    public func write(_ data: Data) {
        lock.withLock {
            self.data = data
            writes += 1
        }
    }

    /// How many commits the store absorbed; tests use it to show writes land here.
    public var writeCount: Int { lock.withLock { writes } }
}

public struct DemoUsageProvider: UsageProvider {
    public let id: ProviderID
    public let accountID: AccountID
    public let displayName: String
    private let snapshot: UsageSnapshot
    private let capability: ProviderCapabilityState?
    /// R15: a simulated probe cost so the envelope demo exercises the measured duty-cycle
    /// gate (KTD4); nil returns the fixture instantly, as every other scenario expects.
    private let probeDuration: TimeInterval?
    public var reportsProviderCapability: Bool { capability != nil }

    /// Mirrors the shipping capacities so a demo pane cannot advertise an affordance the
    /// product does not have: Cursor is deliberately single-account (no config-home
    /// isolation equivalent to `CLAUDE_CONFIG_DIR`), which is why `CursorProvider` pins
    /// `accountCapacity` to 1. `--demo multi-4` was rendering it as "1 of 5" with an
    /// "Add Account…" button. Copilot is single-account for the same reason.
    public var accountCapacity: Int {
        id == .cursor || id == .copilot ? 1 : AccountRegistry.testedEnvelope
    }

    public init(
        id: ProviderID,
        displayName: String,
        snapshot: UsageSnapshot,
        accountID: AccountID = .primary,
        capability: ProviderCapabilityState? = nil,
        probeDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.snapshot = snapshot
        self.capability = capability
        self.probeDuration = probeDuration
    }

    /// The fixture itself, instantly: tests enumerate every scenario's providers this way.
    /// Only `fetchResult()`, the path the scheduler drives, pays the simulated probe cost.
    public func fetchSnapshot() async -> UsageSnapshot { snapshot }
    public func fetchResult() async -> UsageProviderFetchResult {
        if let probeDuration, probeDuration > 0 {
            try? await Task.sleep(for: .seconds(probeDuration))
        }
        return UsageProviderFetchResult(snapshot: snapshot, capability: capability)
    }
}

/// An `APISpendProvider` that returns a fixed spend snapshot — screenshot demo mode only.
public struct DemoSpendProvider: APISpendProvider {
    public let id: ProviderID
    public let displayName: String
    private let snapshot: APISpendSnapshot

    public init(id: ProviderID, displayName: String, snapshot: APISpendSnapshot) {
        self.id = id
        self.displayName = displayName
        self.snapshot = snapshot
    }

    public func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot { snapshot }
}
