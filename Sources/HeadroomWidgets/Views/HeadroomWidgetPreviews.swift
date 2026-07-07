import HeadroomCore
import SwiftUI
import WidgetKit

#if DEBUG
private enum HeadroomWidgetPreviewData {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let resetSoon = Date(timeIntervalSince1970: 1_800_900_000)
    private static let resetLater = Date(timeIntervalSince1970: 1_820_000_000)

    static let entry = HeadroomWidgetEntry(
        date: now,
        state: .content(WidgetSnapshotEnvelope(
            generatedAt: now.addingTimeInterval(-124),
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: ProviderID.claude.raw,
                    displayName: "Claude",
                    planLabel: "Max",
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(kind: .weekly, label: "weekly", percentRemaining: 48, resetsAt: resetLater, resetLabel: "Resets Monday", severity: .healthy),
                        WidgetWindowSummary(kind: .fiveHour, label: "5h", percentRemaining: 9, resetsAt: resetSoon, resetLabel: "Resets 12:08 AM", severity: .critical),
                    ],
                    renewalDate: now.addingTimeInterval(9 * 24 * 60 * 60)
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "Pro",
                    freshness: .stale(message: "Run `codex`", needsAttention: true),
                    windows: [
                        WidgetWindowSummary(kind: .weekly, label: "weekly", percentRemaining: 100, resetsAt: resetLater, resetLabel: nil, severity: .healthy),
                        WidgetWindowSummary(kind: .fiveHour, label: "5h", percentRemaining: 18, resetsAt: resetSoon, resetLabel: nil, severity: .low),
                        WidgetWindowSummary(kind: .other("GPT-5.3-Codex-Spark weekly"), label: "GPT-5.3-Codex-Spark weekly", percentRemaining: 7, resetsAt: resetLater, resetLabel: nil, severity: .critical),
                    ],
                    renewalDate: now.addingTimeInterval(2 * 24 * 60 * 60)
                ),
            ]
        ))
    )
}

#Preview("Small", as: .systemSmall) {
    HeadroomUsageWidget()
} timeline: {
    HeadroomWidgetPreviewData.entry
}

#Preview("Medium", as: .systemMedium) {
    HeadroomUsageWidget()
} timeline: {
    HeadroomWidgetPreviewData.entry
}

#Preview("Large", as: .systemLarge) {
    HeadroomUsageWidget()
} timeline: {
    HeadroomWidgetPreviewData.entry
}
#endif
