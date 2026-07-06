import Foundation

/// Which limit window a `UsageWindow` describes. `.other` carries an unrecognized
/// window's label verbatim so a new server-side window never fails decoding (KTD6).
public enum WindowKind: Sendable, Equatable, Hashable {
    case fiveHour
    case weekly
    case other(String)

    /// Short human label rendered verbatim on widget surfaces (via
    /// `WidgetSnapshotProjector.windowSummary`, its sole consumer).
    public var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "Weekly"
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

/// One usage window: how much has been consumed and when it resets.
///
/// `resetsAt` is always the server-provided reset time — never a client-side guess
/// about window length (R3, KTD6). `utilization` is 0–100 percent consumed.
public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let utilization: Double
    public let resetsAt: Date
    /// The provider's own reset text shown verbatim when present (e.g. Claude's
    /// "Resets Jul 2 at 10am"). Preferred over a client-computed countdown because it
    /// can't drift from what the source displays. Nil for providers that give only a
    /// machine reset timestamp (Codex).
    public let resetLabel: String?

    public init(kind: WindowKind, utilization: Double, resetsAt: Date, resetLabel: String? = nil) {
        self.kind = kind
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.resetLabel = resetLabel
    }

    /// Percentage of the window still available (R1/R2). Clamped to 0…100 so an
    /// over-limit `utilization > 100` reads as 0 remaining rather than negative.
    public var percentRemaining: Double {
        min(100, max(0, 100 - utilization))
    }

    /// Static health band for this window (UI-01). A pure threshold on
    /// `percentRemaining` — never animated — so the bar and menu-bar glyph can encode
    /// urgency at a glance without violating the standing "no pulsing indicators" rule.
    public var severity: UsageSeverity { UsageSeverity(percentRemaining: percentRemaining) }
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

    /// User-facing message for the stale card (already redaction-safe).
    public var message: String {
        switch self {
        case .transient(let m), .needsReauth(let m), .scopeDenied(let m),
             .decode(let m), .notLoggedIn(let m):
            return m
        }
    }

    /// Whether the poller should keep retrying, or stop and wait for the user.
    public var isPermanent: Bool {
        switch self {
        case .transient: return false
        case .needsReauth, .scopeDenied, .notLoggedIn: return true
        case .decode: return false
        }
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
    public let capturedAt: Date?
    public let freshness: Freshness

    public init(
        providerID: ProviderID,
        windows: [UsageWindow],
        planLabel: String?,
        capturedAt: Date?,
        freshness: Freshness
    ) {
        self.providerID = providerID
        self.windows = windows
        self.planLabel = planLabel
        self.capturedAt = capturedAt
        self.freshness = freshness
    }

    /// The first-run snapshot for a provider: no data, no timestamp.
    public static func pending(for providerID: ProviderID) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [],
            planLabel: nil,
            capturedAt: nil,
            freshness: .pending
        )
    }

    /// A failed fetch with no fresh data. The store merges prior windows back in for
    /// continuity (KTD7), so this carries none of its own.
    public static func stale(for providerID: ProviderID, reason: FailureReason) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [],
            planLabel: nil,
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
            capturedAt: capturedAt,
            freshness: .stale(reason)
        )
    }
}

/// Which usage surface a user can opt into. This static catalog keeps Settings able
/// to show disabled surfaces, while polling still fetches only enabled providers.
public enum UsageSurface: String, CaseIterable, Sendable, Codable, Equatable {
    case claudeSubscription
    case codexSubscription
    case anthropicAPI
    case openAIAPI

    public var providerID: ProviderID {
        switch self {
        case .claudeSubscription, .anthropicAPI: return .claude
        case .codexSubscription, .openAIAPI: return .codex
        }
    }

    public var displayName: String {
        switch self {
        case .claudeSubscription: return "Claude subscription"
        case .codexSubscription: return "Codex subscription"
        case .anthropicAPI: return "Anthropic API spend"
        case .openAIAPI: return "OpenAI API spend"
        }
    }

    public var isSubscription: Bool {
        switch self {
        case .claudeSubscription, .codexSubscription: return true
        case .anthropicAPI, .openAIAPI: return false
        }
    }
}

/// Which provider's *weekly* usage drives how full the menu-bar vessel is drawn. The
/// glyph's fill drains as that provider's weekly allotment is consumed. `.none` keeps a
/// static decorative fill (the identity mark), decoupled from any single provider.
public enum MenuBarFillSource: String, CaseIterable, Sendable, Codable, Equatable {
    case none
    case claude
    case codex
    case both

    /// The provider whose weekly window sets the fill, or nil for the static glyph.
    public var providerID: ProviderID? {
        switch self {
        case .none, .both: return nil
        case .claude: return .claude
        case .codex: return .codex
        }
    }

    public var label: String {
        switch self {
        case .none: return "None"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .both: return "Both"
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

/// Money-based API spend for one provider over a selected reporting period.
public struct APISpendSnapshot: Sendable, Equatable {
    public let providerID: ProviderID
    public let displayName: String
    public let amount: Double?
    public let currency: String?
    public let periodLabel: String
    public let capturedAt: Date?
    public let freshness: Freshness

    public init(
        providerID: ProviderID,
        displayName: String,
        amount: Double?,
        currency: String?,
        periodLabel: String,
        capturedAt: Date?,
        freshness: Freshness
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.amount = amount
        self.currency = currency
        self.periodLabel = periodLabel
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
            capturedAt: capturedAt,
            freshness: .stale(reason)
        )
    }
}
