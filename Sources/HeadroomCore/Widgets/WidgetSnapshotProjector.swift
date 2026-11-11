import Foundation

/// Which consumer a schema-3 projection is for. Mac-only by path (KTD4): this file may
/// read Engine types because the iOS targets exclude it.
public enum WidgetProjectionContext: Sendable, Equatable {
    /// The Mac's own App Group widget export: source copy and provenance, unchanged.
    case localWidget
    /// The schema-3 phone export paired with v4 in one publish (KTD5, KTD13, contract
    /// "Additional narrow projection-parity findings"). Whole-second dates, normalized
    /// percentages, typed attention copy, no reset labels, time zones or renewal dates,
    /// so `primaryProjection()` of the paired v4 publish reproduces it exactly.
    /// `attention` is each provider's main-account attention after any session overlay.
    case phoneSync(attention: [ProviderID: CompanionAttention])
}

/// Converts the app's richer provider snapshots into the small, safe contract consumed
/// by WidgetKit. Keeping this in core makes widget rendering deterministic and testable.
public enum WidgetSnapshotProjector {
    public static func project(
        snapshots: [ProviderID: UsageSnapshot],
        providerOrder: [ProviderID],
        displayNames: [ProviderID: String],
        renewalDate: (ProviderID) -> Date?,
        widgetsEnabled: Bool,
        widgetProviderSelection: [ProviderID]? = nil,
        showsCodexSparkCounters: Bool = false,
        apiSpendSnapshots: [ProviderID: APISpendSnapshot] = [:],
        apiSpendProviderOrder: [ProviderID] = [],
        generatedAt: Date = .now,
        context: WidgetProjectionContext = .localWidget
    ) -> WidgetSnapshotEnvelope {
        let stamp = context == .localWidget
            ? generatedAt : (CompanionWireDate.canonicalize(generatedAt) ?? generatedAt)
        guard widgetsEnabled else { return .disabled(generatedAt: stamp) }
        let providers = providerOrder.map { id in
            providerSummary(
                id: id,
                snapshot: snapshots[id] ?? .pending(for: id),
                displayName: displayNames[id] ?? id.raw,
                renewalDate: renewalDate(id),
                showsCodexSparkCounters: showsCodexSparkCounters,
                context: context
            )
        }
        let apiSpendProviders = apiSpendProviderOrder.compactMap { id in
            apiSpendSnapshots[id].flatMap { apiSpendSummary($0, context: context) }
        }
        let availableProviders = Set(providerOrder)
        let normalizedSelection: [String]? = widgetProviderSelection.map { selection in
            var included = Set<ProviderID>()
            var result: [String] = []
            for id in selection where result.count < 2 {
                guard availableProviders.contains(id), included.insert(id).inserted else { continue }
                result.append(id.raw)
            }
            return result
        }
        return WidgetSnapshotEnvelope(
            generatedAt: stamp,
            status: .enabled,
            providers: providers,
            apiSpendProviders: apiSpendProviders,
            widgetProviderSelection: normalizedSelection
        )
    }

    private static func providerSummary(
        id: ProviderID,
        snapshot: UsageSnapshot,
        displayName: String,
        renewalDate: Date?,
        showsCodexSparkCounters: Bool,
        context: WidgetProjectionContext
    ) -> WidgetProviderSummary {
        guard case .phoneSync(let attention) = context else {
            return WidgetProviderSummary(
                id: id.raw,
                displayName: displayName,
                planLabel: snapshot.planLabel,
                freshness: freshness(snapshot.freshness),
                windows: snapshot.windows.compactMap {
                    windowSummary(
                        $0,
                        providerID: id,
                        capturedAt: snapshot.capturedAt,
                        showsCodexSparkCounters: showsCodexSparkCounters
                    )
                },
                renewalDate: renewalDate
            )
        }
        // The phone lift names providers by ID (the resolver has no Mac display table).
        // A pending account carries no rows on the wire, whatever the snapshot holds.
        let canonical = snapshot.freshness == .pending ? [] : CompanionPhoneProjection.windows(of: snapshot)
        let windows = canonical.compactMap { row in
            row.isSpark && !showsCodexSparkCounters ? nil : row.widgetSummary
        }
        let projectedFreshness: WidgetProviderFreshness
        switch snapshot.freshness {
        case .pending: projectedFreshness = .pending
        case .live: projectedFreshness = .live
        case .stale(let reason):
            let typed = attention[id] ?? CompanionAttentionMapping.attention(for: reason)
            projectedFreshness = .stale(
                message: CompanionAttentionCopy.account(typed), needsAttention: reason.isPermanent)
        }
        return WidgetProviderSummary(
            id: id.raw, displayName: id.displayName, planLabel: snapshot.planLabel,
            freshness: projectedFreshness, windows: windows, renewalDate: nil)
    }

    private static func freshness(_ freshness: Freshness) -> WidgetProviderFreshness {
        switch freshness {
        case .pending:
            .pending
        case .live:
            .live
        case .stale(let reason):
            .stale(message: reason.message, needsAttention: reason.isPermanent)
        }
    }

    private static func apiSpendSummary(
        _ snapshot: APISpendSnapshot, context: WidgetProjectionContext
    ) -> WidgetAPISpendSummary? {
        guard context != .localWidget else {
            return WidgetAPISpendSummary(
                id: snapshot.providerID.raw,
                displayName: snapshot.displayName,
                amount: snapshot.amount,
                currency: snapshot.currency,
                periodLabel: snapshot.periodLabel,
                kind: snapshot.kind,
                capturedAt: snapshot.capturedAt,
                freshness: freshness(snapshot.freshness),
                attention: spendAttention(snapshot.freshness)
            )
        }
        // The same canonical record v4 carries, lifted the way the phone lifts it.
        return CompanionPhoneProjection.spend(snapshot)?.widgetSummary
    }

    /// Carries the typed reason across the wire, which the widget `freshness` case
    /// (message + permanence flag only) cannot express.
    private static func spendAttention(_ freshness: Freshness) -> APISpendAttention? {
        guard case .stale(let reason) = freshness else { return nil }
        return APISpendAttention(reason: reason)
    }

    private static func windowSummary(
        _ window: UsageWindow,
        providerID: ProviderID,
        capturedAt: Date?,
        showsCodexSparkCounters: Bool
    ) -> WidgetWindowSummary? {
        guard let kind = widgetKind(window.kind, providerID: providerID, showsCodexSparkCounters: showsCodexSparkCounters) else { return nil }
        // KTD6.2: the canonical display value (decimal source utilization, then one decimal),
        // so an exported 84.95 reads 15.1 here exactly as it does on the phone.
        let display = UsageDisplayValue(window: window)
        let remaining = display?.percentRemaining ?? window.percentRemaining
        return WidgetWindowSummary(
            kind: kind,
            label: window.kind.shortLabel,
            percentRemaining: remaining,
            utilization: window.utilization,
            resetSchedule: window.resetSchedule,
            resetLabel: window.resetLabel,
            resetTimeZoneIdentifier: window.resetTimeZoneIdentifier,
            observedAt: window.observedAt ?? window.freshness.observedAt ?? capturedAt,
            severity: WidgetUsageSeverity(display?.severity ?? window.severity),
            freshness: widgetFreshness(window.freshness),
            billingPeriodDuration: billingPeriodDuration(window.kind)
        )
    }

    private static func billingPeriodDuration(_ kind: WindowKind) -> TimeInterval? {
        guard case .billingPeriod(_, let duration) = kind else { return nil }
        return duration
    }

    private static func widgetFreshness(_ freshness: UsageWindowFreshness) -> WidgetWindowFreshness {
        switch freshness {
        case .live:
            .live
        case .stale(let observedAt):
            .stale(observedAt: observedAt)
        case .unavailable(let since):
            .unavailable(since: since)
        }
    }

    static func widgetKind(
        _ kind: WindowKind,
        providerID: ProviderID,
        showsCodexSparkCounters: Bool
    ) -> WidgetWindowKind? {
        switch kind {
        case .fiveHour:
            return .fiveHour
        case .weekly:
            return .weekly
        case .billingPeriod(let label, _):
            return .other(label)
        case .other(let label):
            if providerID == .codex {
                return (showsCodexSparkCounters && kind.isCodexSparkCounter) ? .other(label) : nil
            }
            // Claude reports model-specific weekly sub-limits (e.g. "Weekly (Fable)") as
            // extra `.other` windows. Retain them so a more restrictive sub-limit can
            // appear as compact context in the large-widget header.
            if providerID == .claude {
                return label.localizedCaseInsensitiveContains("weekly") ? .other(label) : nil
            }
            return .other(label)
        }
    }
}

// MARK: - Phone sync projection (KTD5, KTD7, KTD9, KTD13)

/// The one canonical conversion from a Mac snapshot to what the phone receives. Both the
/// paired schema-3 phone export and every v4 account read it, so the two can never
/// disagree about which rows exist, their rounded values or their whole-second dates.
public enum CompanionPhoneProjection {
    /// One exportable row: the v4 slim window plus the schema-3 lift of the same values.
    public struct CanonicalWindow: Equatable, Sendable {
        public let slim: CompanionSlimWindow
        public let widgetSummary: WidgetWindowSummary
        public var isSpark: Bool { slim.isSpark }
    }

    /// The rows the phone carries for one account, in source order. The row set is the
    /// widget row set with Codex Spark counters always present and flagged (KTD13): the
    /// projection filters them by the Mac's widget switch and the app by the phone's.
    /// Rows the widgets never carried (a Codex window with an unrecognized duration, a
    /// Claude model row that is not weekly) stay Mac-only, which keeps the KTD13 parity.
    /// A row with a non-finite value or an unrepresentable date is dropped on both sides.
    public static func windows(of snapshot: UsageSnapshot) -> [CanonicalWindow] {
        let captured = snapshot.capturedAt.flatMap(CompanionWireDate.init(date:))
        return snapshot.windows.compactMap { window in
            canonicalWindow(window, providerID: snapshot.providerID, capturedAt: captured)
        }
    }

    static func canonicalWindow(
        _ window: UsageWindow, providerID: ProviderID, capturedAt: CompanionWireDate?
    ) -> CanonicalWindow? {
        guard WidgetSnapshotProjector.widgetKind(
            window.kind, providerID: providerID, showsCodexSparkCounters: true) != nil,
            let display = UsageDisplayValue(window: window), window.utilization.isFinite
        else { return nil }

        let kind: CompanionWindowKind
        var kindName: String?
        var duration: Double?
        switch window.kind {
        case .fiveHour: kind = .fiveHour
        case .weekly: kind = .weekly
        case .other(let label):
            kind = .other
            kindName = label
        case .billingPeriod(let label, let seconds):
            // A non-positive or non-finite period lifts to an unknown row the phone
            // drops; drop it here too so both exports agree.
            guard seconds.isFinite, seconds > 0 else { return nil }
            kind = .billingPeriod
            kindName = label
            duration = seconds
        }

        let resetKind: CompanionResetKind
        var deadline: CompanionWireDate?
        var reason: ResetUnresolvedReason?
        switch window.resetSchedule {
        case .scheduled(let date):
            guard let wire = CompanionWireDate(date: date) else { return nil }
            resetKind = .scheduled
            deadline = wire
        case .unresolved(let unresolved):
            resetKind = .unresolved
            reason = unresolved
        }

        // One observation per row on both sides: the row's own anchor, else the capture.
        guard let observedSource = window.observedAt ?? window.freshness.observedAt
                ?? capturedAt?.date,
            let observed = CompanionWireDate(date: observedSource)
        else { return nil }

        let freshness: CompanionWindowFreshness
        var override: CompanionWireDate?
        var since: CompanionWireDate?
        let widgetFreshness: WidgetWindowFreshness
        switch window.freshness {
        case .live:
            freshness = .live
            override = observed == capturedAt ? nil : observed
            widgetFreshness = .live
        case .stale:
            freshness = .stale
            override = observed
            widgetFreshness = .stale(observedAt: observed.date)
        case .unavailable(let unavailableSince):
            guard let wire = CompanionWireDate(date: unavailableSince) else { return nil }
            freshness = .unavailable
            override = observed
            since = wire
            widgetFreshness = .unavailable(since: wire.date)
        }

        let isSpark = providerID == .codex && window.kind.isCodexSparkCounter
        guard let slim = try? CompanionSlimWindow(
            kind: kind, kindName: kindName, billingPeriodDuration: duration,
            percentRemaining: display.percentRemaining, utilization: window.utilization,
            resetKind: resetKind, resetDeadline: deadline, resetReason: reason,
            freshness: freshness, observedAtOverride: override, unavailableSince: since,
            isSpark: isSpark)
        else { return nil }

        let summary = WidgetWindowSummary(
            kind: kind == .fiveHour ? .fiveHour : kind == .weekly ? .weekly : .other(kindName ?? ""),
            label: window.kind.shortLabel,
            percentRemaining: slim.percentRemaining,
            utilization: window.utilization,
            resetSchedule: deadline.map { .scheduled($0.date) } ?? .unresolved(reason ?? .legacyUnknown),
            resetLabel: nil,
            resetTimeZoneIdentifier: nil,
            observedAt: observed.date,
            severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: slim.percentRemaining)),
            freshness: widgetFreshness,
            billingPeriodDuration: duration)
        return CanonicalWindow(slim: slim, widgetSummary: summary)
    }

    /// One v4 account. `title` is already KTD9-resolved; `attention` already carries any
    /// session overlay. Nil when the snapshot cannot form a structurally valid account
    /// (for example a live reading with no capture time); the provider key is then left
    /// out and the phone shows that Mac's schema-3 main account instead (KTD6.3).
    /// `isRemembered` marks a last-known row the default login left (default-login KTD14);
    /// the caller passes it only for an extra.
    public static func account(
        id: AccountID, title: String, snapshot: UsageSnapshot, attention: CompanionAttention?,
        isRemembered: Bool = false
    ) -> CompanionAccountSummary? {
        let freshness: CompanionContentFreshness
        var needsAttention: Bool?
        switch snapshot.freshness {
        case .pending: freshness = .pending
        case .live: freshness = .live
        case .stale(let reason):
            freshness = .stale
            needsAttention = reason.isPermanent
        }
        let windows = freshness == .pending ? [] : self.windows(of: snapshot).map(\.slim)
        let captured = snapshot.capturedAt.flatMap(CompanionWireDate.init(date:))
        return try? CompanionAccountSummary(
            id: id.raw, title: title, planName: snapshot.planLabel, freshness: freshness,
            capturedAt: freshness == .pending ? nil : captured,
            attention: attention,
            needsAttention: needsAttention, bankedResets: snapshot.bankedResets,
            windows: windows, isRemembered: isRemembered)
    }

    /// The canonical spend record, or nil when it cannot be carried honestly (a
    /// non-finite amount, or an amount with no capture time). Both exports drop it then.
    public static func spend(_ snapshot: APISpendSnapshot) -> CompanionSpendSummary? {
        let freshness: CompanionContentFreshness
        var attention: CompanionSpendAttention?
        var needsAttention: Bool?
        switch snapshot.freshness {
        case .pending: freshness = .pending
        case .live: freshness = .live
        case .stale(let reason):
            freshness = .stale
            attention = CompanionSpendAttention(APISpendAttention(reason: reason))
            needsAttention = reason.isPermanent
        }
        let kind: CompanionSpendKind
        switch snapshot.kind {
        case .periodSpend: kind = .periodSpend
        case .balance: kind = .balance
        }
        return try? CompanionSpendSummary(
            id: snapshot.providerID.raw, displayName: snapshot.displayName,
            amount: snapshot.amount, currency: snapshot.currency,
            periodLabel: snapshot.periodLabel, kind: kind,
            capturedAt: snapshot.capturedAt.flatMap(CompanionWireDate.init(date:)),
            freshness: freshness, attention: attention, needsAttention: needsAttention)
    }

    /// KTD9, amended Nov 2026: the phone shows the name the Mac shows, so people who
    /// tell accounts apart by email see the same name on both. With "Use email as account
    /// name" on, an account with a captured email is titled with that email
    /// (`DesktopAccountIdentity`, the Mac's own rule); otherwise the title is the user's
    /// label or the default name. An email reaches the phone only as this displayed title,
    /// never as its own field or an ID, and never when the setting is off. Copilot captures
    /// no email, so its titles are always labels. Duplicates compare case-insensitively and
    /// take " · N" in stored registry order, so Make Main never moves a suffix, and a
    /// generated suffix skips any title already taken, including a user's literal "Work · 2".
    public static func titles(
        storedOrder accounts: [ProviderAccount],
        emails: [AccountID: String],
        usesEmailAsName: Bool
    ) -> [AccountID: String] {
        func fold(_ title: String) -> String { title.folding(options: [.caseInsensitive], locale: nil) }
        let bases = accounts.map { account -> String in
            let identity = DesktopAccountIdentity(
                title: account.label, email: emails[account.id],
                showsPersistentEmail: false, usesEmailAsName: usesEmailAsName)
            if identity.isEmailTitle { return identity.title }
            let trimmed = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty else { return trimmed }
            return account.isBuiltIn ? ProviderAccount.builtInDefaultLabel : "Account"
        }
        var taken = Set(bases.map(fold))
        var seen: Set<String> = []
        var result: [AccountID: String] = [:]
        for (account, base) in zip(accounts, bases) {
            if seen.insert(fold(base)).inserted {
                result[account.id] = base
                continue
            }
            var n = 2
            while taken.contains(fold("\(base) · \(n)")) { n += 1 }
            let title = "\(base) · \(n)"
            taken.insert(fold(title))
            result[account.id] = title
        }
        return result
    }
}
