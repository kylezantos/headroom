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
    /// True when the app (macOS or iOS) was launched with `--demo`.
    public static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    // MARK: Subscription usage

    public static var claudeSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .claude,
            windows: [
                UsageWindow(kind: .weekly, utilization: 62, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
                UsageWindow(kind: .fiveHour, utilization: 28, resetsAt: soon(hours: 3, minutes: 15, seconds: 30), resetLabel: "Resets 2:15pm"),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 46, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
            ],
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

    /// Cursor bills a monthly included-usage pool (billing-period window) with a calendar
    /// reset day — the shape the official `/usage` panel exposes.
    public static var cursorSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .cursor,
            windows: [
                UsageWindow(
                    kind: BillingPeriodWindowClassifier.kind(periodType: "monthly", durationSeconds: nil),
                    utilization: 31,
                    resetsAt: soon(days: 12),
                    resetLabel: "Resets Sep 1"
                ),
            ],
            planLabel: "Pro+",
            accountEmail: "personal@example.com",  // placeholder (see claudeSnapshot)
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
            freshness: .stale(.transient("Couldn’t reach OpenAI — will retry"))
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
    /// (max cap + popover scroll — all render at the regular meter scale now), and a
    /// mixed-health stack (one live, one waiting on sign-in, one transiently stale).
    ///
    /// Shared between the offscreen `PopoverRenderHarness` (design-review PNGs) and the
    /// live `--demo <scenario>` launch mode (interactive multi-account preview + genuine
    /// Liquid-Glass screenshots), so both draw from one fixture source (demo mode, Jul 2026).
    public enum MultiAccountScenario: String, CaseIterable, Sendable {
        case multiTwo = "multi-2"
        case multiThree = "multi-3"
        case multiFive = "multi-5"
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
        /// X5: the same four rows, but with both retained-figure states posed — a rejected
        /// key still showing its last total (column and reserved top-up slot held), and a
        /// retryable stale row. `spend-states` can only pose one shape per row, and the
        /// nil-amount collapse is the shape it exists to show.
        case spendRetained = "spend-retained"
    }

    /// Canonical demo provider order, mirroring `AppComposition`'s subscription registry.
    /// Parity checks derive their expected provider list from this instead of hardcoding a
    /// Claude/Codex literal (KTD9 switch-site inventory).
    public static let registeredProviderOrder: [ProviderID] = [.claude, .codex, .grok, .cursor]

    /// One scenario resolved to its accounts + one fixture provider per account.
    public struct MultiAccountFixture: Sendable {
        public let accounts: [ProviderAccount]
        public let providers: [any UsageProvider]
        /// Optional last-known values posed before the first demo refresh. Capability
        /// failures intentionally withhold account snapshots, exactly like production.
        public let continuitySnapshots: [AccountKey: UsageSnapshot]
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
        freshness: Freshness = .live,
        builtIn: Bool = false,
        capability: ProviderCapabilityState? = nil
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
                capability: capability
            )
        )
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
                            freshness: .stale(.transient("Couldn’t reach Codex — will retry"))),
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
        return MultiAccountFixture(
            accounts: pairs.map(\.account),
            providers: pairs.map(\.provider),
            continuitySnapshots: continuitySnapshots
        )
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

public struct DemoUsageProvider: UsageProvider {
    public let id: ProviderID
    public let accountID: AccountID
    public let displayName: String
    private let snapshot: UsageSnapshot
    private let capability: ProviderCapabilityState?
    public var reportsProviderCapability: Bool { capability != nil }

    public init(
        id: ProviderID,
        displayName: String,
        snapshot: UsageSnapshot,
        accountID: AccountID = .primary,
        capability: ProviderCapabilityState? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.snapshot = snapshot
        self.capability = capability
    }

    public func fetchSnapshot() async -> UsageSnapshot { snapshot }
    public func fetchResult() async -> UsageProviderFetchResult {
        UsageProviderFetchResult(snapshot: snapshot, capability: capability)
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
