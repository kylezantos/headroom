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
        generatedAt: Date = .now
    ) -> WidgetSnapshotEnvelope {
        guard widgetsEnabled else { return .disabled(generatedAt: generatedAt) }
        let providers = providerOrder.map { id in
            providerSummary(
                id: id,
                snapshot: snapshots[id] ?? .pending(for: id),
                displayName: displayNames[id] ?? id.raw,
                renewalDate: renewalDate(id)
            )
        }
        return WidgetSnapshotEnvelope(generatedAt: generatedAt, status: .enabled, providers: providers)
    }

    private static func providerSummary(
        id: ProviderID,
        snapshot: UsageSnapshot,
        displayName: String,
        renewalDate: Date?
    ) -> WidgetProviderSummary {
        WidgetProviderSummary(
            id: id.raw,
            displayName: displayName,
            planLabel: snapshot.planLabel,
            freshness: freshness(snapshot.freshness),
            windows: snapshot.windows.compactMap(windowSummary),
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

    private static func windowSummary(_ window: UsageWindow) -> WidgetWindowSummary? {
        guard let kind = widgetKind(window.kind) else { return nil }
        return WidgetWindowSummary(
            kind: kind,
            label: window.kind.shortLabel,
            percentRemaining: window.percentRemaining,
            resetsAt: window.resetsAt,
            resetLabel: window.resetLabel,
            severity: widgetSeverity(window.severity)
        )
    }

    private static func widgetKind(_ kind: WindowKind) -> WidgetWindowKind? {
        switch kind {
        case .fiveHour: .fiveHour
        case .weekly: .weekly
        case .other: nil
        }
    }

    private static func widgetSeverity(_ severity: UsageSeverity) -> WidgetUsageSeverity {
        switch severity {
        case .healthy: .healthy
        case .low: .low
        case .critical: .critical
        }
    }
}
