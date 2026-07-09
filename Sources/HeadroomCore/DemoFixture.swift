import Foundation

/// Deterministic sample data for producing clean, repeatable product screenshots
/// (the marketing site at headroom.zantos.co). Activated by the `--demo` launch
/// argument. These numbers are the single source of truth for the mock, so the
/// menu-bar popover, the macOS widgets, and the iPhone mirror all agree at one moment.
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
                UsageWindow(kind: .fiveHour, utilization: 28, resetsAt: soon(hours: 5), resetLabel: "Resets 2:15pm"),
                UsageWindow(kind: .weekly, utilization: 62, resetsAt: soon(days: 3), resetLabel: "Resets Jul 9"),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 62, resetsAt: soon(days: 3), resetLabel: "Resets Jul 9"),
            ],
            planLabel: "Max",
            capturedAt: Date(),
            freshness: .live
        )
    }

    public static var codexSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(kind: .fiveHour, utilization: 9, resetsAt: soon(hours: 3), resetLabel: "Resets in 3h 12m"),
                UsageWindow(kind: .weekly, utilization: 36, resetsAt: soon(days: 6), resetLabel: "Resets in 6d 4h"),
            ],
            planLabel: "Prolite",
            capturedAt: Date(),
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
        default: return nil
        }
    }

    // MARK: Helpers

    private static func soon(hours: Int = 0, days: Int = 0) -> Date {
        Date().addingTimeInterval(TimeInterval(days * 86_400 + hours * 3_600))
    }

    private static func day(month: Int, day: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year], from: Date())
        comps.month = month
        comps.day = day
        comps.hour = 10
        return Calendar.current.date(from: comps) ?? Date()
    }
}

/// A `UsageProvider` that returns a fixed snapshot — screenshot demo mode only.
public struct DemoUsageProvider: UsageProvider {
    public let id: ProviderID
    public let displayName: String
    private let snapshot: UsageSnapshot

    public init(id: ProviderID, displayName: String, snapshot: UsageSnapshot) {
        self.id = id
        self.displayName = displayName
        self.snapshot = snapshot
    }

    public func fetchSnapshot() async -> UsageSnapshot { snapshot }
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
