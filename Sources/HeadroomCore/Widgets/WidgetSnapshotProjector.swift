import Foundation

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
        generatedAt: Date = .now
    ) -> WidgetSnapshotEnvelope {
        guard widgetsEnabled else { return .disabled(generatedAt: generatedAt) }
        let providers = providerOrder.map { id in
            providerSummary(
                id: id,
                snapshot: snapshots[id] ?? .pending(for: id),
                displayName: displayNames[id] ?? id.raw,
                renewalDate: renewalDate(id),
                showsCodexSparkCounters: showsCodexSparkCounters
            )
        }
        let apiSpendProviders = apiSpendProviderOrder.compactMap { id in
            apiSpendSnapshots[id].map(apiSpendSummary)
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
            generatedAt: generatedAt,
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
        showsCodexSparkCounters: Bool
    ) -> WidgetProviderSummary {
        WidgetProviderSummary(
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

    private static func apiSpendSummary(_ snapshot: APISpendSnapshot) -> WidgetAPISpendSummary {
        WidgetAPISpendSummary(
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
        return WidgetWindowSummary(
            kind: kind,
            label: window.kind.shortLabel,
            percentRemaining: window.percentRemaining,
            utilization: window.utilization,
            resetSchedule: window.resetSchedule,
            resetLabel: window.resetLabel,
            resetTimeZoneIdentifier: window.resetTimeZoneIdentifier,
            observedAt: window.observedAt ?? window.freshness.observedAt ?? capturedAt,
            severity: WidgetUsageSeverity(window.severity),
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

    private static func widgetKind(
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
