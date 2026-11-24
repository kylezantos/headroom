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

    /// Stable identity for persisted choices. Billing periods key on their label, not their
    /// duration, because a monthly pool's declared length changes month to month.
    public var persistentID: String {
        switch self {
        case .fiveHour: return "fiveHour"
        case .weekly: return "weekly"
        case .billingPeriod(let label, _): return "billing:\(label)"
        case .other(let label): return "other:\(label)"
        }
    }

    public init?(persistentID id: String) {
        switch id {
        case "fiveHour": self = .fiveHour
        case "weekly": self = .weekly
        default:
            if id.hasPrefix("billing:"), id.count > "billing:".count {
                self = .billingPeriod(label: String(id.dropFirst("billing:".count)), duration: 0)
            } else if id.hasPrefix("other:"), id.count > "other:".count {
                self = .other(String(id.dropFirst("other:".count)))
            } else {
                return nil
            }
        }
    }

    /// The window's name on every surface except the compact widget header
    /// (`WidgetWindowSummary.compactLabel`). Claude's model rows read as the model alone —
    /// "Weekly (Fable)" is "Fable" — since the reset time already says the period. Codex's
    /// model rows keep their period: one model can carry both a 5-hour and a weekly window,
    /// so dropping it would print two rows with the same name.
    public var displayName: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .billingPeriod(let label, _): return label
        case .other(let raw):
            if let model = Self.weeklyModelName(in: raw) { return model }
            if let (model, period) = Self.modelAndPeriod(in: raw) { return "\(model) · \(period)" }
            return raw
        }
    }

    /// `displayName` in the compact form the Accounts retained-usage line uses ("5h 72%").
    public var compactName: String {
        switch self {
        case .fiveHour: return "5h"
        default: return displayName
        }
    }

    /// `displayName` with the period spoken, for tooltips and VoiceOver, where "Fable" alone
    /// would not say what kind of limit it is.
    public var spokenName: String {
        if case .other(let raw) = self {
            if let model = Self.weeklyModelName(in: raw) { return "\(model) weekly" }
            if let (model, period) = Self.modelAndPeriod(in: raw) { return "\(model) \(period.lowercased())" }
        }
        return displayName
    }

    /// The menu-bar tooltip's phrase after the provider name ("Claude weekly", "Codex 5h").
    public var menuBarTerm: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "weekly"
        case .billingPeriod(let label, _): return label.lowercased()
        case .other: return spokenName
        }
    }

    /// "Fable" from Claude's "Weekly (Fable)" model row; nil for any other label. The widget
    /// header's `compactLabel` uses the same rule, so the two surfaces cannot drift apart.
    static func weeklyModelName(in label: String) -> String? {
        let prefix = "Weekly ("
        guard label.hasPrefix(prefix), label.hasSuffix(")"), label.count > prefix.count + 1 else { return nil }
        return String(label.dropFirst(prefix.count).dropLast())
    }

    /// Codex model rows are "<model> <period>", built from `WindowKind.shortLabel`, so the
    /// weekly one ends in "Weekly" and the 5-hour one in "5h". Matched case-insensitively.
    private static func modelAndPeriod(in label: String) -> (model: String, period: String)? {
        for (suffix, period) in [(" weekly", "Weekly"), (" 5h", "5-hour")] {
            guard label.count > suffix.count,
                  label.lowercased().hasSuffix(suffix) else { continue }
            return (String(label.dropLast(suffix.count)), period)
        }
        return nil
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

    /// The raw source integer. Display surfaces print `displayedPercentage(for:)` (or a
    /// `UsageMeterReading`), which rounds the one normalized tenth every surface shares (KTD6.2).
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
/// The widgets and the menu bar carry no title ink; the phone's display block does
/// (iPhone parity KTD11), so the phone can follow it under "Match my Mac".
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

/// How the macOS popover lays out accounts (popover account layout plan, R1). `.standard`
/// keeps the provider cards; `.compact` draws one dense row per account. Both flow into a
/// second column past the cards-height cap (KTD1, KTD2).
///
/// Mac-only (KTD8): it sizes the popover's window, which has no phone equivalent, so neither
/// the phone's display block nor any widget or menu-bar projection carries it.
public enum AccountLayout: String, CaseIterable, Identifiable, Sendable {
    case standard
    case compact

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: return "Standard"
        case .compact: return "Compact"
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
    /// The source itself said this window is at its limit (OpenCode's `limited`, KTD6/D3 of
    /// the OpenCode plan), which is the authority for the card's limited sentence; a window
    /// that merely reads 100% is not. False for every other provider. Mac-local: never
    /// persisted or synced, because the sentence shows only on a live window.
    public let isLimited: Bool

    public init(
        kind: WindowKind,
        utilization: Double,
        resetSchedule: ResetSchedule,
        resetLabel: String? = nil,
        resetTimeZoneIdentifier: String? = nil,
        freshness: UsageWindowFreshness = .live,
        observedAt: Date? = nil,
        isLimited: Bool = false
    ) {
        self.kind = kind
        self.utilization = utilization
        self.resetSchedule = resetSchedule
        self.resetLabel = resetLabel
        self.resetTimeZoneIdentifier = resetTimeZoneIdentifier
        self.freshness = freshness
        self.observedAt = observedAt ?? freshness.observedAt
        self.isLimited = isLimited
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
        withFreshness(freshness, observedAt: nil)
    }

    /// CA-P4 review fix: an aging path that resolved this window's observation anchor (its
    /// own, else the capture that held it) passes it here, so a window that once held a
    /// number keeps one after it turns unavailable and reads "No current reading". A live
    /// window carries no anchor of its own; the window's own anchor always wins.
    public func withFreshness(_ freshness: UsageWindowFreshness, observedAt anchor: Date?) -> UsageWindow {
        UsageWindow(
            kind: kind,
            utilization: utilization,
            resetSchedule: resetSchedule,
            resetLabel: resetLabel,
            resetTimeZoneIdentifier: resetTimeZoneIdentifier,
            freshness: freshness,
            observedAt: observedAt ?? anchor,
            isLimited: isLimited
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

/// How `rate_limit_reset_credits` arrived on a Codex capture. Nil on every other
/// provider. The card reads `bankedResets`; `--probe-codex` reads this so a
/// key-present `null` stays distinguishable from a missing key and from
/// `available_count: 0` (R2).
public enum CodexResetCreditsField: Sendable, Equatable {
    /// The key was not in the body.
    case absent
    /// The key was present and JSON `null` — reported zero.
    case nullObject
    /// A non-negative integral `available_count`, including 0.
    case count(Int)
    /// The key was present but carried no usable count (missing, negative,
    /// fractional, or a non-object). Not reported.
    case notReported

    /// Snapshot count for this shape. `null` and a literal `0` are both reported
    /// zero; a missing or unusable value is not reported.
    public var bankedResets: Int? {
        switch self {
        case .nullObject: return 0
        case .count(let count): return count
        case .absent, .notReported: return nil
        }
    }
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
    /// Banked rate-limit resets held by this account. Nil means not reported;
    /// 0 means reported zero (a key-present `null` or `available_count: 0`).
    /// Only Codex populates it (KTD1, KTD11).
    public let bankedResets: Int?
    /// Codex field shape behind `bankedResets`. Not persisted; continuity
    /// restores the count alone. Nil except on a Codex decode.
    public let codexResetCreditsField: CodexResetCreditsField?
    public let capturedAt: Date?
    public let freshness: Freshness
    /// Whose reading this is, from the identity reads around it (default-login plan,
    /// KTD2). Nil when the provider reports no identity evidence, which keeps the row's
    /// behavior as it was before identities existed. Mac-local: it never reaches the
    /// widget envelope or the phone.
    public let identity: AccountIdentityOutcome?
    /// What the source said about the account's plan when it isn't a usage number: today
    /// only OpenCode's signed-in workspace without Go (KTD7, OpenCode plan). Nil on every
    /// other reading.
    public let planStatus: PlanStatus?

    /// KTD7 (OpenCode plan): a stored value, so its raw value is permanent once shipped.
    public enum PlanStatus: String, Sendable, Equatable, Codable {
        /// Signed in, but the workspace has no plan with usage limits to read.
        case noActivePlan
    }

    /// KTD16 (OpenCode plan): the plan text every widget and phone export carries. A plan
    /// status with a name of its own wins over the source label, so a no-Go account reads
    /// "No Go plan" on the phone and its widgets with no sync field added. Only while the
    /// status can still be true: after a permanent failure (signed out, sign-in expired, CLI
    /// missing, update required) the home may hold another login or none, so the retained
    /// status names no plan there.
    public var exportedPlanLabel: String? {
        if case .stale(let reason) = freshness, reason.isPermanent { return planLabel }
        return planStatus?.syncedPlanName(for: providerID) ?? planLabel
    }

    public init(
        providerID: ProviderID,
        windows: [UsageWindow],
        planLabel: String?,
        accountEmail: String? = nil,
        bankedResets: Int? = nil,
        codexResetCreditsField: CodexResetCreditsField? = nil,
        capturedAt: Date?,
        freshness: Freshness,
        identity: AccountIdentityOutcome? = nil,
        planStatus: PlanStatus? = nil
    ) {
        self.providerID = providerID
        self.windows = windows
        self.planLabel = planLabel
        self.accountEmail = accountEmail
        self.bankedResets = bankedResets
        self.codexResetCreditsField = codexResetCreditsField
        self.capturedAt = capturedAt
        self.freshness = freshness
        self.identity = identity
        self.planStatus = planStatus
    }

    /// `--probe-codex` line. Three live states stay distinguishable: an integer
    /// (including reported `0`), a key-present `null`, and a missing key.
    public var codexBankedResetProbeLine: String {
        switch codexResetCreditsField {
        case .absent, nil:
            return "banked resets: absent (field not present)"
        case .nullObject:
            return "banked resets: null (reported zero)"
        case .count(let count):
            return "banked resets: \(count)"
        case .notReported:
            return "banked resets: not reported"
        }
    }

    /// The first-run snapshot for a provider: no data, no timestamp.
    public static func pending(for providerID: ProviderID) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [],
            planLabel: nil,
            accountEmail: nil,
            bankedResets: nil,
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
            bankedResets: nil,
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
            bankedResets: bankedResets,
            codexResetCreditsField: codexResetCreditsField,
            capturedAt: capturedAt,
            freshness: .stale(reason),
            identity: identity,
            planStatus: planStatus
        )
    }

    /// The same reading, stamped with what the identity reads around it found (KTD2).
    public func withIdentity(_ identity: AccountIdentityOutcome?) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: planLabel,
            accountEmail: accountEmail,
            bankedResets: bankedResets,
            codexResetCreditsField: codexResetCreditsField,
            capturedAt: capturedAt,
            freshness: freshness,
            identity: identity,
            planStatus: planStatus
        )
    }

    public func withAccountEmail(_ accountEmail: String?) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: planLabel,
            accountEmail: accountEmail,
            bankedResets: bankedResets,
            codexResetCreditsField: codexResetCreditsField,
            capturedAt: capturedAt,
            freshness: freshness,
            identity: identity,
            planStatus: planStatus
        )
    }

    /// The same reading with different windows; every other field, identity included,
    /// carries over.
    public func replacingWindows(_ windows: [UsageWindow], freshness: Freshness? = nil) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: planLabel,
            accountEmail: accountEmail,
            bankedResets: bankedResets,
            codexResetCreditsField: codexResetCreditsField,
            capturedAt: capturedAt,
            freshness: freshness ?? self.freshness,
            identity: identity,
            planStatus: planStatus
        )
    }
}

public extension UsageSnapshot {
    /// The popover's row order: 5-hour leads, weekly (or billing-period) second, model rows
    /// such as Claude's Fable keep the provider's order after (Kyle, Sep 2026 — the popover
    /// used to lead with weekly to match the widgets, which still do via
    /// `WidgetProviderSummary.displaySubscriptionWindows`). Every macOS surface that stands
    /// in for the popover — the Settings Appearance specimen included — must apply this
    /// rather than render the raw fixture order.
    func fiveHourFirst() -> UsageSnapshot {
        func rank(_ kind: WindowKind) -> Int {
            switch kind {
            case .fiveHour: return 0
            case .weekly, .billingPeriod: return 1
            case .other: return 2
            }
        }
        let ordered = windows.enumerated()
            .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
        guard ordered != windows else { return self }
        return replacingWindows(ordered)
    }
}

/// Which usage surface a user can opt into. This static catalog keeps Settings able
/// to show disabled surfaces, while polling still fetches only enabled providers.
public enum UsageSurface: String, CaseIterable, Sendable, Codable, Equatable {
    case claudeSubscription
    case codexSubscription
    case grokSubscription
    case cursorSubscription
    case copilotSubscription
    case anthropicAPI
    case openAIAPI
    case xaiAPI
    case cursorAPI
    /// KTD13 (OpenCode plan): appended after the API surfaces, not beside the other
    /// subscriptions, so no stored raw value or `allCases` position moves.
    case opencodeSubscription
    case antigravitySubscription

    public var providerID: ProviderID {
        switch self {
        case .claudeSubscription, .anthropicAPI: return .claude
        case .codexSubscription, .openAIAPI: return .codex
        case .grokSubscription, .xaiAPI: return .grok
        case .cursorSubscription, .cursorAPI: return .cursor
        case .copilotSubscription: return .copilot
        case .opencodeSubscription: return .opencode
        case .antigravitySubscription: return .antigravity
        }
    }

    public var displayName: String {
        switch self {
        case .claudeSubscription: return "Claude subscription"
        case .codexSubscription: return "Codex subscription"
        case .grokSubscription: return "Grok subscription"
        case .cursorSubscription: return "Cursor subscription"
        case .copilotSubscription: return "Copilot subscription"
        case .anthropicAPI: return "Anthropic API spend"
        case .openAIAPI: return "OpenAI API spend"
        case .xaiAPI: return "xAI API spend"
        case .cursorAPI: return "Cursor on-demand spend"
        case .opencodeSubscription: return "OpenCode subscription"
        case .antigravitySubscription: return "Antigravity subscription"
        }
    }

    public var isSubscription: Bool {
        switch self {
        case .claudeSubscription, .codexSubscription, .grokSubscription, .cursorSubscription, .copilotSubscription,
             .opencodeSubscription, .antigravitySubscription:
            return true
        case .anthropicAPI, .openAIAPI, .xaiAPI, .cursorAPI:
            return false
        }
    }

    public var isEnabledByDefault: Bool {
        switch self {
        case .claudeSubscription, .codexSubscription:
            return true
        // R11: OpenCode is off for fresh installs and upgrades alike, like Grok, Cursor and
        // Copilot before it, and Antigravity after it.
        case .grokSubscription, .cursorSubscription, .copilotSubscription, .opencodeSubscription,
             .antigravitySubscription, .anthropicAPI, .openAIAPI, .xaiAPI, .cursorAPI:
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

/// A provider's chosen menu-bar limit. Percentage text, vessel fill, and severity tint
/// resolve together so each glyph always means one thing.
///
/// Persisted as a string. A window choice stores `WindowKind.persistentID`, so the two
/// pre-Sep-2026 values ("weekly", "fiveHour") load unchanged and any limit the provider
/// reports — Claude's model rows, Cursor's named pools — can be chosen. A choice the
/// latest data does not carry is kept, and the pill follows `closest` until it returns.
public enum MenuBarWindowChoice: Hashable, Sendable {
    /// Follows whichever of the provider's limits has the least remaining right now.
    case closest
    case window(id: String)

    public static let weekly = MenuBarWindowChoice.window(id: WindowKind.weekly.persistentID)
    public static let fiveHour = MenuBarWindowChoice.window(id: WindowKind.fiveHour.persistentID)

    private static let closestRawValue = "closest"

    /// Nil for anything that is neither "closest" nor a readable window ID, so a malformed
    /// stored value falls back to the default instead of listing a nameless choice.
    public init?(rawValue: String) {
        if rawValue == Self.closestRawValue {
            self = .closest
        } else if WindowKind(persistentID: rawValue) != nil {
            self = .window(id: rawValue)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .closest: return Self.closestRawValue
        case .window(let id): return id
        }
    }

    public func matches(_ kind: WindowKind) -> Bool {
        guard case .window(let id) = self else { return false }
        return kind.persistentID == id
    }

    /// The kind this choice names, rebuilt from its stored ID so Settings can title a
    /// choice the latest data does not carry. Billing durations are not stored; naming
    /// never reads them.
    public var kind: WindowKind? {
        guard case .window(let id) = self else { return nil }
        return WindowKind(persistentID: id)
    }

    public var title: String {
        kind?.displayName ?? "Closest to limit"
    }

    /// Lower-case phrase for the menu-bar tooltip and VoiceOver ("Claude weekly").
    public var menuBarTerm: String {
        kind?.menuBarTerm ?? "closest to limit"
    }
}

/// One entry in a provider's menu-bar limit picker. `window` is the provider's current
/// row for that limit, or nil when the choice is saved but not in the latest data.
public struct MenuBarWindowOption: Identifiable, Equatable, Sendable {
    public let choice: MenuBarWindowChoice
    public let window: UsageWindow?

    public init(choice: MenuBarWindowChoice, window: UsageWindow?) {
        self.choice = choice
        self.window = window
    }

    public var id: String { choice.rawValue }
    public var title: String { choice.title }
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
            // CMM5 (Kyle, 2026-09-10): the three-letter month — "Sep", not "September" —
            // reads as a period tag beside the amount rather than a second title.
            // A format style, not a `DateFormatter` built per call: the spend card asks for
            // this label on every row of every popover pass, and the per-call formatter was
            // the app's own largest hot spot in the 2026-10-03 perf bench.
            let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: .current, calendar: calendar, timeZone: .current)
                .month(.abbreviated)
            return now.formatted(style)
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

extension UsageSnapshot.PlanStatus {
    /// KTD16 (OpenCode plan): the plan name exported for this status. The Mac card says it
    /// in its own action row (KTD7) and draws no plan capsule; the phone has no such row, so
    /// it prints the status as the plan name. Nil for a provider that has no name for it.
    public func syncedPlanName(for provider: ProviderID) -> String? {
        switch (self, provider) {
        case (.noActivePlan, .opencode): "No Go plan"
        default: nil
        }
    }
}
