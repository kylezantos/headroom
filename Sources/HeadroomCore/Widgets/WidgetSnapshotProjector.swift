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
        showsCodexSparkCounters: Bool = false,
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
        return WidgetSnapshotEnvelope(generatedAt: generatedAt, status: .enabled, providers: providers)
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
            windows: snapshot.windows.compactMap { windowSummary($0, providerID: id, showsCodexSparkCounters: showsCodexSparkCounters) },
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

    private static func windowSummary(
        _ window: UsageWindow,
        providerID: ProviderID,
        showsCodexSparkCounters: Bool
    ) -> WidgetWindowSummary? {
        guard let kind = widgetKind(window.kind, providerID: providerID, showsCodexSparkCounters: showsCodexSparkCounters) else { return nil }
        return WidgetWindowSummary(
            kind: kind,
            label: window.kind.shortLabel,
            percentRemaining: window.percentRemaining,
            resetsAt: window.resetsAt,
            resetLabel: window.resetLabel,
            severity: widgetSeverity(window.severity)
        )
    }

    private static func widgetKind(
        _ kind: WindowKind,
        providerID: ProviderID,
        showsCodexSparkCounters: Bool
    ) -> WidgetWindowKind? {
        switch kind {
        case .fiveHour: .fiveHour
        case .weekly: .weekly
        case .other(let label):
            providerID == .codex && showsCodexSparkCounters && kind.isCodexSparkCounter ? .other(label) : nil
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
