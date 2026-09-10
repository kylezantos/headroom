import Foundation

/// Which limit window a `UsageWindow` describes. Billing periods preserve their
/// source-declared label and duration; `.other` keeps unrecognized windows honest.
public enum WindowKind: Sendable, Equatable, Hashable {
    case fiveHour
    case weekly
    case billingPeriod(label: String, duration: TimeInterval)
    case other(String)

    /// Short human label rendered verbatim on widget surfaces (via
    /// `WidgetSnapshotProjector.windowSummary`, its sole consumer).
    public var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "Weekly"
        case .billingPeriod(let label, _): return label
        case .other(let label): return label
        }
    }

    /// Codex reports model-specific allowances as additional windows, currently labeled
    /// with Spark. Keep the check narrow to Codex presentation paths so generic unknown
    /// windows are not hidden by accident.
    public var isCodexSparkCounter: Bool {
        guard case .other(let label) = self else { return false }
        return label.localizedCaseInsensitiveContains("spark")
    }
}

/// Classifies provider-declared billing periods without inferring identity from row
/// position or presentation copy. Unknown durations stay honest `.other` windows.
public enum BillingPeriodWindowClassifier {
    private static let day: TimeInterval = 24 * 60 * 60

    public static func kind(periodType: String?, durationSeconds: TimeInterval?) -> WindowKind {
        let declaredDuration = durationSeconds.flatMap { duration in
            duration.isFinite && duration > 0 ? duration : nil
        }
        switch periodType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "weekly", "week":
            return .billingPeriod(label: "Weekly", duration: declaredDuration ?? 7 * day)
        case "monthly", "month":
            return .billingPeriod(label: "Monthly", duration: declaredDuration ?? 30 * day)
        default:
            break
        }

        guard let declaredDuration else {
            let label = periodType?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .other(label.flatMap { $0.isEmpty ? nil : $0 } ?? "Billing period")
        }
        if declaredDuration == 7 * day {
            return .billingPeriod(label: "Weekly", duration: declaredDuration)
        }
        if (28 * day...31 * day).contains(declaredDuration) {
            return .billingPeriod(label: "Monthly", duration: declaredDuration)
        }
        return .other(durationLabel(seconds: declaredDuration))
    }

    private static func durationLabel(seconds: TimeInterval) -> String {
        let hours = (seconds / 3_600).rounded()
        if hours < 48 { return "\(Int(hours))h" }
        return "\(Int((seconds / day).rounded()))d"
    }
}

/// How subscription percentages are presented to the user. Provider snapshots keep
/// canonical utilization; this mode derives the complementary display without mutating
/// fetched data or the remaining-based severity thresholds.
public enum UsagePercentageMode: String, CaseIterable, Identifiable, Sendable {
    case remaining
    case used

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .remaining: return "Left"
        case .used: return "Used"
        }
    }

    public var term: String { label.lowercased() }

    public func percentage(for window: UsageWindow) -> Double {
        switch self {
        case .remaining: return window.percentRemaining
        case .used: return window.percentUsed
        }
    }

    public func roundedPercentage(for window: UsageWindow) -> Int {
        Int(percentage(for: window).rounded())
    }

    public func fraction(for window: UsageWindow) -> Double {
        percentage(for: window) / 100
    }
}

/// How account names are inked in the macOS popover. `.neutral` is the G1A grey — the
/// title labels its meters instead of competing with them; `.brand` restores the
/// pre-round-2 per-provider tint (`HeadroomWidgetColorValues.textAccent`) for people who
/// want the popover colored the way they are used to (G1A, Sep 2026).
///
/// Popover-only, exactly like `MeterStyle`: the widgets, the iPhone mirror, and the menu
/// bar carry no title ink, so no projection reads this preference.
public enum AccountTitleInk: String, CaseIterable, Identifiable, Sendable {
    case neutral
    case brand

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .neutral: return "Neutral"
        case .brand: return "Brand"
        }
    }
}

/// Per-window provenance for snapshots that mix a fresh provider capture with a
/// retained model-specific sub-limit. A last-known percentage remains displayable but
/// must never inherit a newer snapshot timestamp; once its validity window expires it
/// becomes unavailable and consumers must hide the old percentage.
public enum UsageWindowFreshness: Sendable, Equatable {
    case live
    case stale(observedAt: Date)
    case unavailable(since: Date)

    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    public var observedAt: Date? {
        guard case .stale(let observedAt) = self else { return nil }
        return observedAt
    }

}

/// One usage window: how much has been consumed and the source evidence for its reset.
public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let utilization: Double
    public let resetSchedule: ResetSchedule
    /// The provider's own reset text when present (e.g. Claude's "Resets Jul 2 at
    /// 10am"). Preserved for diagnostics and snapshot consumers; the macOS app derives
    /// its compact relative presentation from `resetSchedule`. Nil for providers that give
    /// only a machine reset timestamp (Codex).
    public let resetLabel: String?
    public let resetTimeZoneIdentifier: String?
    public let freshness: UsageWindowFreshness
    /// Original source observation anchor. It survives stale/unavailable transitions;
    /// publication and migration timestamps never replace it.
    public let observedAt: Date?

    public init(
        kind: WindowKind,
        utilization: Double,
        resetSchedule: ResetSchedule,
        resetLabel: String? = nil,
        resetTimeZoneIdentifier: String? = nil,
        freshness: UsageWindowFreshness = .live,
        observedAt: Date? = nil
    ) {
        self.kind = kind
        self.utilization = utilization
        self.resetSchedule = resetSchedule
        self.resetLabel = resetLabel
        self.resetTimeZoneIdentifier = resetTimeZoneIdentifier
        self.freshness = freshness
        self.observedAt = observedAt ?? freshness.observedAt
    }

    /// Convenience for providers that receive an exact machine deadline.
    public init(
        kind: WindowKind,
        utilization: Double,
        resetsAt: Date,
        resetLabel: String? = nil,
        freshness: UsageWindowFreshness = .live,
        observedAt: Date? = nil
    ) {
        self.init(
            kind: kind,
            utilization: utilization,
            resetSchedule: .scheduled(resetsAt),
            resetLabel: resetLabel,
            freshness: freshness,
            observedAt: observedAt
        )
    }

    /// Percentage of the window still available (R1/R2). Clamped to 0…100 so an
    /// over-limit `utilization > 100` reads as 0 remaining rather than negative.
    public var percentRemaining: Double {
        min(100, max(0, 100 - utilization))
    }

    /// Percentage consumed, clamped independently because provider payloads can report
    /// transient under/over-limit values outside the normal 0...100 range.
    public var percentUsed: Double {
        min(100, max(0, utilization))
    }

    /// Static health band for this window (UI-01). A pure threshold on
    /// `percentRemaining` — never animated — so the bar and menu-bar glyph can encode
    /// urgency at a glance without violating the standing "no pulsing indicators" rule.
    public var severity: UsageSeverity { UsageSeverity(percentRemaining: percentRemaining) }

    public func withFreshness(_ freshness: UsageWindowFreshness) -> UsageWindow {
        UsageWindow(
            kind: kind,
            utilization: utilization,
            resetSchedule: resetSchedule,
            resetLabel: resetLabel,
            resetTimeZoneIdentifier: resetTimeZoneIdentifier,
            freshness: freshness,
            observedAt: observedAt
        )
    }
}

/// How close a window is to running out. Drives the semantic color ramp
/// (healthy → low → critical) on the usage bar and the menu-bar glyph. Thresholds are
/// fixed here — the single source of truth — so views never reinvent them.
public enum UsageSeverity: Sendable, Equatable, Comparable {
    case healthy
    case low
    case critical

    /// Bands by percent *remaining*: ≤15% critical, ≤50% low, otherwise healthy.
    /// Green means "you genuinely have plenty" — reserved for more than half left — so a
    /// third of the way down reads as amber, not a false all-clear.
    public init(percentRemaining: Double) {
        switch percentRemaining {
        case ..<0:      self = .critical   // defensive; percentRemaining is clamped ≥0
        case ...15:     self = .critical
        case ...50:     self = .low
        default:        self = .healthy
        }
    }

    /// Anything a user should notice — used for the "Low" chip and menu-bar tint.
    public var needsAttention: Bool { self != .healthy }
}

/// Typed failure reason (KTD7). Failures are always one of these cases — never a
/// free-form string built from a caught `Error`, `URLRequest`, or `HTTPURLResponse`,
/// which is how tokens leak into logs/UI (R10). Each case carries a short,
/// already-redacted message safe to display.
public enum FailureReason: Sendable, Equatable, Error {
    /// Retry on the next cycle (network error, 429, expired-but-refreshable token).
    case transient(String)
    /// Permanent until the user re-authenticates in the source CLI.
    case needsReauth(String)
    /// The token cannot call the endpoint at all (missing `user:profile` scope, KTD1).
    case scopeDenied(String)
    /// Response body could not be parsed; treated as transient-style stale.
    case decode(String)
    /// No credential is present yet (Keychain item / auth.json absent).
    case notLoggedIn(String)
    /// A typed provider/setup condition. Its redaction-safe copy is derived from the
    /// outcome; UI recovery behavior must use the outcome, never compare the copy.
    case providerSetup(ProviderSetupOutcome)

    /// User-facing message for the stale card (already redaction-safe).
    public var message: String {
        switch self {
        case .transient(let m), .needsReauth(let m), .scopeDenied(let m),
             .decode(let m), .notLoggedIn(let m):
            return m
        case .providerSetup(let outcome):
            return outcome.message
        }
    }

    /// Whether the poller should keep retrying, or stop and wait for the user.
    public var isPermanent: Bool {
        switch self {
        case .transient: return false
        case .needsReauth, .scopeDenied, .notLoggedIn: return true
        case .decode: return false
        case .providerSetup(let outcome): return outcome.isPermanent
        }
    }

    public var providerSetupOutcome: ProviderSetupOutcome? {
        guard case .providerSetup(let outcome) = self else { return nil }
        return outcome
    }
}

/// Snapshot freshness. `.pending` is the genuine first-run state before any
/// successful fetch — distinct from `.stale`, so the UI never fabricates a
/// nonsensical "updated 0 min ago" on launch (design review P0).
public enum Freshness: Sendable, Equatable {
    case pending
    case live
    case stale(FailureReason)
}

/// A provider's usage at a point in time. `capturedAt` is nil while `.pending`.
public struct UsageSnapshot: Sendable, Equatable {
    public let providerID: ProviderID
    public let windows: [UsageWindow]
    /// Lenient plan label — any string passes through (KTD6); nil when absent.
    public let planLabel: String?
    /// Which email this account is signed in as, read from the account file the official
    /// CLI itself wrote (`.claude.json` / `auth.json`). Lenient like `planLabel`: nil
    /// whenever the source is absent or unreadable — identity is display context, so a
    /// missing email must never turn a good usage capture into a failure. Defaulted in
    /// the initializer so snapshot *transforms* opt in explicitly to carrying it forward.
    public let accountEmail: String?
    public let capturedAt: Date?
    public let freshness: Freshness

    public init(
        providerID: ProviderID,
        windows: [UsageWindow],
        planLabel: String?,
        accountEmail: String? = nil,
        capturedAt: Date?,
        freshness: Freshness
    ) {
        self.providerID = providerID
        self.windows = windows
        self.planLabel = planLabel
        self.accountEmail = accountEmail
        self.capturedAt = capturedAt
        self.freshness = freshness
    }

    /// The first-run snapshot for a provider: no data, no timestamp.
    public static func pending(for providerID: ProviderID) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [],
            planLabel: nil,
            accountEmail: nil,
            capturedAt: nil,
            freshness: .pending
        )
    }

    /// A failed fetch with no fresh data. The store merges prior windows back in for
    /// continuity (KTD7) — including the last-known plan label and account email — so
    /// this carries none of its own.
    public static func stale(for providerID: ProviderID, reason: FailureReason) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [],
            planLabel: nil,
            accountEmail: nil,
            capturedAt: nil,
            freshness: .stale(reason)
        )
    }

    /// Re-mark an existing snapshot as stale, preserving its last-known windows so
    /// the UI keeps showing prior data dimmed rather than blanking (KTD7). If there
    /// is no prior data yet, the result stays `.pending`-shaped but carries the reason.
    public func markedStale(_ reason: FailureReason) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: planLabel,
            accountEmail: accountEmail,
            capturedAt: capturedAt,
            freshness: .stale(reason)
        )
    }
}

public extension UsageSnapshot {
    /// The popover's row order: weekly (or billing-period) leads, 5-hour second, unknown
    /// windows keep the provider's order after. Providers and the parser emit 5-hour first
    /// (`ClaudeUsageParser.displayRank`); the widgets re-rank the same way at display time
    /// (`WidgetProviderSummary.displaySubscriptionWindows`, PR #35). Every macOS surface that
    /// stands in for the popover — the Settings Appearance specimen included — must apply
    /// this rather than render the raw fixture order.
    func weeklyFirst() -> UsageSnapshot {
        func rank(_ kind: WindowKind) -> Int {
            switch kind {
            case .weekly, .billingPeriod: return 0
            case .fiveHour: return 1
            case .other: return 2
            }
        }
        let ordered = windows.enumerated()
            .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
        guard ordered != windows else { return self }
        return UsageSnapshot(
            providerID: providerID,
            windows: ordered,
            planLabel: planLabel,
            accountEmail: accountEmail,
            capturedAt: capturedAt,
            freshness: freshness
        )
    }
}

/// Which usage surface a user can opt into. This static catalog keeps Settings able
/// to show disabled surfaces, while polling still fetches only enabled providers.
public enum UsageSurface: String, CaseIterable, Sendable, Codable, Equatable {
    case claudeSubscription
    case codexSubscription
    case grokSubscription
    case cursorSubscription
    case anthropicAPI
    case openAIAPI
    case xaiAPI
    case cursorAPI

    public var providerID: ProviderID {
        switch self {
        case .claudeSubscription, .anthropicAPI: return .claude
        case .codexSubscription, .openAIAPI: return .codex
        case .grokSubscription, .xaiAPI: return .grok
        case .cursorSubscription, .cursorAPI: return .cursor
        }
    }

    public var displayName: String {
        switch self {
        case .claudeSubscription: return "Claude subscription"
        case .codexSubscription: return "Codex subscription"
        case .grokSubscription: return "Grok subscription"
        case .cursorSubscription: return "Cursor subscription"
        case .anthropicAPI: return "Anthropic API spend"
        case .openAIAPI: return "OpenAI API spend"
        case .xaiAPI: return "xAI API spend"
        case .cursorAPI: return "Cursor on-demand spend"
        }
    }

    public var isSubscription: Bool {
        switch self {
        case .claudeSubscription, .codexSubscription, .grokSubscription, .cursorSubscription:
            return true
        case .anthropicAPI, .openAIAPI, .xaiAPI, .cursorAPI:
            return false
        }
    }

    public var isEnabledByDefault: Bool {
        switch self {
        case .claudeSubscription, .codexSubscription:
            return true
        case .grokSubscription, .cursorSubscription, .anthropicAPI, .openAIAPI, .xaiAPI, .cursorAPI:
            return false
        }
    }

    public static func subscription(for providerID: ProviderID) -> UsageSurface? {
        allCases.first { $0.providerID == providerID && $0.isSubscription }
    }

    public static func api(for providerID: ProviderID) -> UsageSurface? {
        allCases.first { $0.providerID == providerID && !$0.isSubscription }
    }
}

/// Which providers get menu-bar meters. Automatic mode preserves the shipped default:
/// one summary for the tightest enabled window with the decorative static vessel fill.
/// Explicit selection renders one meter per selected provider in registry order.
public enum MenuBarFillSource: Sendable, Equatable, Hashable {
    case auto
    case providers(Set<ProviderID>)

    /// Source-compatible spellings for older call sites and persisted-fixture setup.
    /// These are migration aliases, not additional runtime states.
    public static let none: Self = .auto
    public static let claude: Self = .providers([.claude])
    public static let codex: Self = .providers([.codex])
    public static let both: Self = .providers([.claude, .codex])

    public var providerIDs: Set<ProviderID>? {
        guard case .providers(let ids) = self else { return nil }
        return ids
    }

    /// Stable identity for animation and diagnostics; never depends on Set iteration.
    public var sortedIdentifier: String {
        switch self {
        case .auto:
            return "auto"
        case .providers(let ids):
            return "providers:" + ids.map(\.raw).sorted().joined(separator: ",")
        }
    }

    public func filtered(to availableProviders: [ProviderID]) -> Self {
        guard case .providers(let selected) = self else { return .auto }
        let available = Set(availableProviders)
        let filtered = selected.intersection(available)
        return filtered.isEmpty ? .auto : .providers(filtered)
    }
}

/// A provider's preferred menu-bar limit window. Percentage text, vessel fill, and
/// severity tint resolve together so each glyph always means one thing.
public enum MenuBarWindowSource: String, CaseIterable, Sendable, Codable, Equatable {
    case weekly
    case fiveHour

    public var kind: WindowKind {
        switch self {
        case .weekly: return .weekly
        case .fiveHour: return .fiveHour
        }
    }

    public var label: String {
        switch self {
        case .weekly: return "Weekly"
        case .fiveHour: return "5-hour"
        }
    }

    /// Short form used in tooltips/accessibility ("Claude weekly", "Claude 5h").
    public var shortLabel: String {
        switch self {
        case .weekly: return "weekly"
        case .fiveHour: return "5h"
        }
    }
}

/// User-selectable period for API cost reports. The provider converts this into the
/// endpoint's query shape at fetch time so later periods do not change UI state.
public enum APISpendPeriod: String, CaseIterable, Sendable, Codable, Equatable {
    case currentMonth
    case rolling30Days

    public var label: String {
        switch self {
        case .currentMonth: return "Current month"
        case .rolling30Days: return "Last 30 days"
        }
    }

    /// Compact period label for the popover spend row — distinct from `label`, which the
    /// Settings picker owns. Current-month renders the actual month name ("July") so the
    /// row reads like the design mock; rolling keeps the descriptive phrase.
    public func displayLabel(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        switch self {
        case .currentMonth:
            var calendar = calendar
            calendar.timeZone = .current
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .current
            // CMM5 (Kyle, 2026-09-10): the three-letter month — "Sep", not "September" —
            // reads as a period tag beside the amount rather than a second title.
            formatter.setLocalizedDateFormatFromTemplate("MMM")
            return formatter.string(from: now)
        case .rolling30Days:
            return label
        }
    }

    public func range(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> APISpendRange {
        var calendar = calendar
        calendar.timeZone = .current
        switch self {
        case .currentMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: components) ?? now
            return APISpendRange(start: start, end: now, label: label)
        case .rolling30Days:
            return APISpendRange(start: now.addingTimeInterval(-30 * 24 * 60 * 60), end: now, label: label)
        }
    }
}

public struct APISpendRange: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let label: String

    public init(start: Date, end: Date, label: String) {
        self.start = start
        self.end = end
        self.label = label
    }
}

public enum APISpendKind: String, Codable, Sendable, Equatable {
    case periodSpend
    case balance
}

/// Money-based API spend or remaining credit balance for one provider.
public struct APISpendSnapshot: Sendable, Equatable {
    public let providerID: ProviderID
    public let displayName: String
    public let amount: Double?
    public let currency: String?
    public let periodLabel: String
    public let kind: APISpendKind
    public let capturedAt: Date?
    public let freshness: Freshness

    public init(
        providerID: ProviderID,
        displayName: String,
        amount: Double?,
        currency: String?,
        periodLabel: String,
        kind: APISpendKind = .periodSpend,
        capturedAt: Date?,
        freshness: Freshness
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.amount = amount
        self.currency = currency
        self.periodLabel = periodLabel
        self.kind = kind
        self.capturedAt = capturedAt
        self.freshness = freshness
    }

    public static func pending(providerID: ProviderID, displayName: String, periodLabel: String) -> APISpendSnapshot {
        APISpendSnapshot(
            providerID: providerID,
            displayName: displayName,
            amount: nil,
            currency: nil,
            periodLabel: periodLabel,
            kind: .periodSpend,
            capturedAt: nil,
            freshness: .pending
        )
    }

    public static func stale(providerID: ProviderID, displayName: String, periodLabel: String, reason: FailureReason) -> APISpendSnapshot {
        APISpendSnapshot(
            providerID: providerID,
            displayName: displayName,
            amount: nil,
            currency: nil,
            periodLabel: periodLabel,
            kind: .periodSpend,
            capturedAt: nil,
            freshness: .stale(reason)
        )
    }

    public func markedStale(_ reason: FailureReason) -> APISpendSnapshot {
        APISpendSnapshot(
            providerID: providerID,
            displayName: displayName,
            amount: amount,
            currency: currency,
            periodLabel: periodLabel,
            kind: kind,
            capturedAt: capturedAt,
            freshness: .stale(reason)
        )
    }
}
