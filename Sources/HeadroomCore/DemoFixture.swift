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
        var email: String? = "\(label.lowercased())@example.com"
        switch freshness {
        case .stale(let reason) where reason.isPermanent:
            windows = []
            email = nil
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
            accountEmail: email,
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
        snapshot: UsageSnapshot
    ) -> (account: ProviderAccount, provider: any UsageProvider) {
        let account = ProviderAccount(id: .primary, providerID: providerID, label: providerID.displayName, isBuiltIn: true)
        return (account, DemoUsageProvider(id: providerID, displayName: providerID.displayName, snapshot: snapshot, accountID: .primary))
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
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                demoAccount(provider: .codex, id: "codex-work", label: "Work", plan: "Pro", fiveHour: 54, weekly: 79,
                            freshness: .stale(.transient("Couldn't reach Codex — will retry"))),
            ]
        case .capabilityFailure:
            pairs = [
                demoAccount(
                    provider: .claude,
                    id: "personal",
                    label: "Personal",
                    plan: "Max",
                    fiveHour: 28,
                    weekly: 62,
                    // The provider verdict drives the dimming on this deterministic pose;
                    // a live-shaped fixture ensures the store has values to retain on its
                    // first and only demo refresh (there is no continuity cache in demo mode).
                    freshness: .live,
                    builtIn: true,
                    capability: .confirmedAbsent
                ),
                demoAccount(
                    provider: .claude,
                    id: "work",
                    label: "Work",
                    plan: "Pro",
                    fiveHour: 0,
                    weekly: 0,
                    freshness: .stale(.notLoggedIn(UsageStore.finishSignInMessage)),
                    capability: .confirmedAbsent
                ),
            ]
        case .multiProviders:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                builtInProviderPair(provider: .grok, snapshot: grokSnapshot),
                builtInProviderPair(provider: .cursor, snapshot: cursorSnapshot),
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
