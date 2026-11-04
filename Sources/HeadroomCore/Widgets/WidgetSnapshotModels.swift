import Foundation

/// A redaction-safe snapshot built for WidgetKit. It contains only display-ready usage
/// values, never provider credentials, request metadata, raw CLI output, or paths.
public struct WidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 3
    public static let oldestSupportedSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let status: WidgetExportStatus
    public let providers: [WidgetProviderSummary]
    public let apiSpendProviders: [WidgetAPISpendSummary]
    public let widgetProviderSelection: [String]?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        generatedAt: Date,
        status: WidgetExportStatus,
        providers: [WidgetProviderSummary],
        apiSpendProviders: [WidgetAPISpendSummary] = [],
        widgetProviderSelection: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.status = status
        self.providers = providers
        self.apiSpendProviders = apiSpendProviders
        self.widgetProviderSelection = widgetProviderSelection
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case status
        case providers
        case apiSpendProviders
        case widgetProviderSelection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let decodedGeneratedAt = try container.decode(Date.self, forKey: .generatedAt)
        generatedAt = decodedGeneratedAt
        status = try container.decode(WidgetExportStatus.self, forKey: .status)
        guard Self.supports(schemaVersion: schemaVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported widget snapshot schema"
            )
        }
        if schemaVersion >= 3 {
            providers = try container.decode([WidgetProviderSummary].self, forKey: .providers)
        } else {
            providers = try container.decode([LegacyWidgetProviderSummary].self, forKey: .providers)
                .map { WidgetProviderSummary(legacy: $0, generatedAt: decodedGeneratedAt) }
        }
        apiSpendProviders = try container.decodeIfPresent([WidgetAPISpendSummary].self, forKey: .apiSpendProviders) ?? []
        widgetProviderSelection = try container.decodeIfPresent([String].self, forKey: .widgetProviderSelection)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(status, forKey: .status)
        try container.encode(providers, forKey: .providers)
        try container.encode(apiSpendProviders, forKey: .apiSpendProviders)
        try container.encodeIfPresent(widgetProviderSelection, forKey: .widgetProviderSelection)
    }

    public static func disabled(generatedAt: Date) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(generatedAt: generatedAt, status: .disabled, providers: [], apiSpendProviders: [])
    }

    public static func supports(schemaVersion: Int) -> Bool {
        (oldestSupportedSchemaVersion...Self.schemaVersion).contains(schemaVersion)
    }

    /// Weekly provider-by-provider values for the smallest widget. This never creates
    /// a cross-provider aggregate because Claude and Codex have independent limits.
    public var weeklyProviders: [WidgetProviderSummary] {
        providers.map { provider in
            var copy = provider
            copy.windows = provider.primarySubscriptionWindow.map { [$0] } ?? []
            return copy
        }
    }

    /// The ordered, bounded provider list shared by every widget family. The full
    /// `providers` list stays intact for the iOS companion app.
    public var widgetProviders: [WidgetProviderSummary] {
        guard let widgetProviderSelection, !widgetProviderSelection.isEmpty else {
            return Array(providers.prefix(2))
        }
        var included = Set<String>()
        var result: [WidgetProviderSummary] = []
        for id in widgetProviderSelection where result.count < 2 {
            guard included.insert(id).inserted,
                  let provider = providers.first(where: { $0.id == id })
            else { continue }
            result.append(provider)
        }
        return result.isEmpty ? Array(providers.prefix(2)) : result
    }
}

public enum WidgetExportStatus: String, Codable, Sendable {
    case enabled
    case disabled
}

public struct WidgetProviderSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let planLabel: String?
    public let freshness: WidgetProviderFreshness
    public var windows: [WidgetWindowSummary]
    public let renewalDate: Date?

    public init(
        id: String,
        displayName: String,
        planLabel: String?,
        freshness: WidgetProviderFreshness,
        windows: [WidgetWindowSummary],
        renewalDate: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.planLabel = planLabel
        self.freshness = freshness
        self.windows = windows
        self.renewalDate = renewalDate
    }

    public var weeklyWindow: WidgetWindowSummary? {
        subscriptionWindows.first { $0.kind == .weekly }
    }

    /// The one period-level meter used by constrained widget families. Existing
    /// providers keep preferring weekly; providers with multiple billing pools use
    /// the tightest pool by displayed value (KTD4, 2026-10-02 widget-styles plan) — an
    /// unavailable pool ranks last, so it never wins while a pool with a number exists —
    /// and preserve source order as the equality tie-break.
    public var primarySubscriptionWindow: WidgetWindowSummary? {
        if let weeklyWindow { return weeklyWindow }
        let billingPeriods = subscriptionWindows.filter(\.isBillingPeriod)
        return WidgetWindowRanking.tightest(billingPeriods) ?? subscriptionWindows.first
    }

    public var subscriptionWindows: [WidgetWindowSummary] {
        windows.filter(\.isSubscriptionWindow)
    }

    public var displaySubscriptionWindows: [WidgetWindowSummary] {
        subscriptionWindows.enumerated().sorted { lhs, rhs in
            func rank(_ window: WidgetWindowSummary) -> Int {
                if window.kind == .weekly || window.isBillingPeriod { return 0 }
                if window.kind == .fiveHour { return 1 }
                return 2
            }
            return (rank(lhs.element), lhs.offset) < (rank(rhs.element), rhs.offset)
        }.map(\.element)
    }

    public var extraCounterWindows: [WidgetWindowSummary] {
        windows.filter { !$0.isSubscriptionWindow }
    }

    public var weeklyDisplayWindows: [WidgetWindowSummary] {
        windows.filter { window in
            switch window.kind {
            case .weekly:
                return true
            case .fiveHour:
                return false
            case .other:
                return window.isBillingPeriod
                    || window.label.localizedCaseInsensitiveContains("weekly")
            }
        }
    }

    /// Model-specific weekly sub-limits retained for compact large-widget context,
    /// including Claude's "Weekly (Fable)" and Codex's optional Spark weekly counter.
    /// Excludes the primary weekly and 5-hour windows; the projector has already decided
    /// which `.other` windows survive to the widget.
    public var extraWeeklyWindows: [WidgetWindowSummary] {
        windows.filter { window in
            guard case .other = window.kind, !window.isBillingPeriod else { return false }
            return window.label.localizedCaseInsensitiveContains("weekly")
        }
    }

    /// The most restrictive model-specific weekly limit, when it communicates a
    /// different whole-number value than the provider's primary weekly limit.
    /// Large widgets use this as compact header context instead of adding another meter.
    public var limitingExtraWeeklyWindow: WidgetWindowSummary? {
        guard let extraWindow = extraWeeklyWindows.lazy.filter({
            $0.displayPercentRemaining != nil
        }).min(by: {
            $0.percentRemaining < $1.percentRemaining
        }) else {
            return nil
        }
        guard let weeklyWindow else { return extraWindow }
        return extraWindow.roundedPercentRemaining < weeklyWindow.roundedPercentRemaining
            ? extraWindow
            : nil
    }
}

public struct WidgetAPISpendSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let amount: Double?
    public let currency: String?
    public let periodLabel: String
    /// Additive v2 field. Missing values from older writers mean period spend.
    public let kind: APISpendKind?
    public let capturedAt: Date?
    public let freshness: WidgetProviderFreshness
    /// Additive field: why a stale row needs attention, kept alongside the freshness so
    /// the companion can show the same badge/CTA the Mac card does. Payloads from older
    /// writers omit it and fall back to the permanent/transient split in `freshness`.
    public let attention: APISpendAttention?

    public init(
        id: String,
        displayName: String,
        amount: Double?,
        currency: String?,
        periodLabel: String,
        kind: APISpendKind? = nil,
        capturedAt: Date?,
        freshness: WidgetProviderFreshness,
        attention: APISpendAttention? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.amount = amount
        self.currency = currency
        self.periodLabel = periodLabel
        self.kind = kind
        self.capturedAt = capturedAt
        self.freshness = freshness
        self.attention = attention
    }

    public var semanticKind: APISpendKind { kind ?? .periodSpend }
}

public enum WidgetProviderFreshness: Codable, Equatable, Sendable {
    case pending
    case live
    case stale(message: String, needsAttention: Bool)

    public var needsAttention: Bool {
        switch self {
        case .pending, .live: false
        case .stale(_, let needsAttention): needsAttention
        }
    }
}

public struct WidgetWindowSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: WidgetWindowKind
    public let label: String
    public let percentRemaining: Double
    /// Exact canonical utilization when written by v3. Nil for migrated v1/v2 rows,
    /// which makes them ineligible for the live-zero “Available” inference.
    public let utilization: Double?
    public let resetSchedule: ResetSchedule
    public let resetLabel: String?
    public let resetTimeZoneIdentifier: String?
    public let observedAt: Date?
    public let severity: WidgetUsageSeverity
    public let freshness: WidgetWindowFreshness
    /// Additive v2 wire discriminator. Older readers ignore it and see an honest
    /// labeled `.other` window; current readers recover subscription semantics.
    public let billingPeriodDuration: TimeInterval?

    public init(
        kind: WidgetWindowKind,
        label: String,
        percentRemaining: Double,
        utilization: Double? = nil,
        resetSchedule: ResetSchedule,
        resetLabel: String?,
        resetTimeZoneIdentifier: String? = nil,
        observedAt: Date? = nil,
        severity: WidgetUsageSeverity,
        freshness: WidgetWindowFreshness = .live,
        billingPeriodDuration: TimeInterval? = nil
    ) {
        self.id = kind.id
        self.kind = kind
        self.label = label
        self.percentRemaining = percentRemaining
        self.utilization = utilization
        self.resetSchedule = resetSchedule
        self.resetLabel = resetLabel
        self.resetTimeZoneIdentifier = resetTimeZoneIdentifier
        self.observedAt = observedAt ?? freshness.observedAt
        self.severity = severity
        self.freshness = freshness
        self.billingPeriodDuration = billingPeriodDuration
    }

    public init(
        kind: WidgetWindowKind,
        label: String,
        percentRemaining: Double,
        resetsAt: Date,
        resetLabel: String?,
        severity: WidgetUsageSeverity,
        freshness: WidgetWindowFreshness = .live,
        billingPeriodDuration: TimeInterval? = nil
    ) {
        self.init(
            kind: kind,
            label: label,
            percentRemaining: percentRemaining,
            utilization: nil,
            resetSchedule: .scheduled(resetsAt),
            resetLabel: resetLabel,
            severity: severity,
            freshness: freshness,
            billingPeriodDuration: billingPeriodDuration
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case percentRemaining
        case utilization
        case resetKind
        case resetDeadline
        case resetReason
        case resetLabel
        case resetTimeZoneIdentifier
        case observedAt
        case severity
        case freshness
        case billingPeriodDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(WidgetWindowKind.self, forKey: .kind)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? kind.id
        label = try container.decode(String.self, forKey: .label)
        percentRemaining = try container.decode(Double.self, forKey: .percentRemaining)
        utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)
        let resetKind = try container.decode(ResetKind.self, forKey: .resetKind)
        let resetDeadline = try container.decodeIfPresent(Date.self, forKey: .resetDeadline)
        let resetReason = try container.decodeIfPresent(String.self, forKey: .resetReason)
        switch resetKind {
        case .scheduled:
            guard let resetDeadline, resetReason == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .resetKind,
                    in: container,
                    debugDescription: "Scheduled reset requires only a deadline"
                )
            }
            resetSchedule = .scheduled(resetDeadline)
        case .unresolved:
            guard resetDeadline == nil,
                  let resetReason,
                  let reason = ResetUnresolvedReason(rawValue: resetReason)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .resetKind,
                    in: container,
                    debugDescription: "Unresolved reset requires only a known reason"
                )
            }
            resetSchedule = .unresolved(reason)
        }
        resetLabel = try container.decodeIfPresent(String.self, forKey: .resetLabel)
        resetTimeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .resetTimeZoneIdentifier)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        severity = try container.decode(WidgetUsageSeverity.self, forKey: .severity)
        freshness = try container.decodeIfPresent(WidgetWindowFreshness.self, forKey: .freshness) ?? .live
        billingPeriodDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .billingPeriodDuration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(label, forKey: .label)
        try container.encode(percentRemaining, forKey: .percentRemaining)
        try container.encodeIfPresent(utilization, forKey: .utilization)
        switch resetSchedule {
        case .scheduled(let deadline):
            try container.encode(ResetKind.scheduled, forKey: .resetKind)
            try container.encode(deadline, forKey: .resetDeadline)
        case .unresolved(let reason):
            try container.encode(ResetKind.unresolved, forKey: .resetKind)
            try container.encode(reason.rawValue, forKey: .resetReason)
        }
        try container.encodeIfPresent(resetLabel, forKey: .resetLabel)
        try container.encodeIfPresent(resetTimeZoneIdentifier, forKey: .resetTimeZoneIdentifier)
        try container.encodeIfPresent(observedAt, forKey: .observedAt)
        try container.encode(severity, forKey: .severity)
        try container.encode(freshness, forKey: .freshness)
        try container.encodeIfPresent(billingPeriodDuration, forKey: .billingPeriodDuration)
    }

    private enum ResetKind: String, Codable {
        case scheduled
        case unresolved
    }

    public var roundedPercentRemaining: Int {
        Int(percentRemaining.rounded())
    }

    public var displayPercentRemaining: Double? {
        freshness.isUnavailable ? nil : percentRemaining
    }

    public var isBillingPeriod: Bool {
        guard let billingPeriodDuration else { return false }
        return billingPeriodDuration.isFinite && billingPeriodDuration > 0
    }

    public var isSubscriptionWindow: Bool {
        kind.isSubscriptionWindow || isBillingPeriod
    }

    /// Shortens model-specific labels for constrained widget headers. For example,
    /// "Weekly (Fable)" becomes "Fable" and Codex Spark weekly labels become "Spark".
    public var compactLabel: String {
        if label.localizedCaseInsensitiveContains("spark"),
           label.localizedCaseInsensitiveContains("weekly") {
            return "Spark"
        }
        return WindowKind.weeklyModelName(in: label) ?? label
    }
}

// MARK: - Widget display accessors (WCW2 / WCW7)
//
// Display-only derivations. Nothing here touches the wire format: the envelope's
// `schemaVersion` stays at 3 and no `CodingKeys` change.

public extension WidgetWindowSummary {
    /// WCW7: the label every widget surface falls back to when a window has no usable name.
    static let fallbackLabel = "Usage"

    /// WCW2: the one accessor every widget surface uses to name a window.
    ///
    /// The four families had four rules — one passed `window.label`, one hard-coded "Weekly",
    /// one used `compactLabel`, one used the kind — so the same Claude sub-limit could read
    /// "Weekly (Fable)" on one tile and "Fable" on another. A widget column is narrow enough
    /// that the short form is the only one that fits; this is that form, everywhere.
    var widgetDisplayLabel: String {
        // Billing-period windows ride on `.other`, but their label is already the noun the
        // provider bills by ("Weekly", "Monthly") — check them before the `.other` shortener.
        if isBillingPeriod {
            return label.isEmpty ? Self.fallbackLabel : label
        }
        switch kind {
        case .weekly:
            return "Weekly"
        case .fiveHour:
            return "5-hour"
        case .other:
            let compact = compactLabel
            return compact.isEmpty ? Self.fallbackLabel : compact
        }
    }
}

private struct LegacyWidgetProviderSummary: Codable {
    let id: String
    let displayName: String
    let planLabel: String?
    let freshness: WidgetProviderFreshness
    let windows: [LegacyWidgetWindowSummary]
    let renewalDate: Date?
}

private struct LegacyWidgetWindowSummary: Codable {
    let kind: WidgetWindowKind
    let label: String
    let percentRemaining: Double
    let resetsAt: Date
    let resetLabel: String?
    let severity: WidgetUsageSeverity
    let freshness: WidgetWindowFreshness?
    let billingPeriodDuration: TimeInterval?
}

private extension WidgetProviderSummary {
    init(legacy: LegacyWidgetProviderSummary, generatedAt: Date) {
        self.init(
            id: legacy.id,
            displayName: legacy.displayName,
            planLabel: legacy.planLabel,
            freshness: legacy.freshness,
            windows: legacy.windows.map {
                WidgetWindowSummary(
                    kind: $0.kind,
                    label: $0.label,
                    percentRemaining: $0.percentRemaining,
                    utilization: nil,
                    resetSchedule: LegacyResetClassifier.schedule(
                        providerID: ProviderID(legacy.id),
                        resetsAt: $0.resetsAt,
                        capturedAt: generatedAt
                    ),
                    resetLabel: $0.resetLabel,
                    observedAt: $0.freshness?.observedAt ?? generatedAt,
                    severity: $0.severity,
                    freshness: $0.freshness ?? .live,
                    billingPeriodDuration: $0.billingPeriodDuration
                )
            },
            renewalDate: legacy.renewalDate
        )
    }
}

public enum WidgetWindowFreshness: Codable, Equatable, Sendable {
    case live
    case stale(observedAt: Date)
    case unavailable(since: Date)

    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    public var isStale: Bool {
        if case .stale = self { return true }
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

public enum WidgetWindowKind: Codable, Equatable, Sendable {
    case fiveHour
    case weekly
    case other(String)

    public var isSubscriptionWindow: Bool {
        switch self {
        case .fiveHour, .weekly: true
        case .other: false
        }
    }

    public var id: String {
        switch self {
        case .fiveHour: "fiveHour"
        case .weekly: "weekly"
        case .other(let label): "other:\(label)"
        }
    }
}

public enum WidgetUsageSeverity: String, Codable, Sendable {
    case healthy
    case low
    case critical

    /// The wire form of `UsageSeverity`, whose bands stay the single source of truth — the
    /// projector and the demo fixtures both map through here rather than re-deriving them.
    public init(_ severity: UsageSeverity) {
        switch severity {
        case .healthy: self = .healthy
        case .low: self = .low
        case .critical: self = .critical
        }
    }
}

/// Builds the short WidgetKit timeline used to keep relative reset copy accurate between
/// host-app exports. Minute cadence handles ordinary countdown changes; exact entries
/// cover the approved immediate-reset boundary and the source deadline itself.
public enum WidgetTimelineSchedule {
    private static let cadence: TimeInterval = 60
    private static let entryCount = 15

    public static func entryDates(
        for envelope: WidgetSnapshotEnvelope?,
        now: Date
    ) -> [Date] {
        let horizon = now.addingTimeInterval(Double(entryCount) * cadence)
        var dates = Set((0..<entryCount).map {
            now.addingTimeInterval(Double($0) * cadence)
        })

        for deadline in envelope?.providers
            .flatMap(\.windows)
            .compactMap(\.resetSchedule.deadline) ?? [] {
            for transition in [
                deadline.addingTimeInterval(-60),
                deadline,
                deadline.addingTimeInterval(61),
            ] where !(transition < now) && transition < horizon {
                dates.insert(transition)
            }
        }
        return dates.sorted()
    }

    public static func refreshDate(after now: Date) -> Date {
        now.addingTimeInterval(Double(entryCount) * cadence)
    }
}
