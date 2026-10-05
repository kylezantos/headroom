import Foundation
import HeadroomCore
import os
import WidgetKit

private let widgetTimelineLogger = Logger(subsystem: "com.kylezantos.headroom.widgets", category: "timeline")

/// KTD1 (2026-10-02 widget-styles plan): an App Intent provider so each placed widget carries
/// its own Style and Color from Edit Widget. The kind string is unchanged, so widgets placed
/// before the update keep their identity and pick up the parameter defaults.
struct HeadroomTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HeadroomWidgetEntry {
        HeadroomWidgetEntry(date: .now, state: .content(DemoScreenshotData.envelope))
    }

    func snapshot(for configuration: HeadroomWidgetConfigurationIntent, in context: Context) async -> HeadroomWidgetEntry {
        // WCW4: the widget gallery is the product's first impression, and a machine that has
        // not run Headroom yet would otherwise show it a status card. The iOS provider has
        // always had this branch; the Mac one did not.
        if context.isPreview {
            // Demo data carries no Mac clock: the gallery never dims.
            return entry(date: .now, state: .content(DemoScreenshotData.envelope), configuration: configuration, freshness: nil)
        }
        let state = resolvedState()
        return entry(date: .now, state: state, configuration: configuration, freshness: state.freshness)
    }

    func timeline(for configuration: HeadroomWidgetConfigurationIntent, in context: Context) async -> Timeline<HeadroomWidgetEntry> {
        let now = Date.now
        let state = resolvedState()
        let envelope: WidgetSnapshotEnvelope?
        if case .content(let content) = state { envelope = content } else { envelope = nil }
        // U13: entries also land at the dim moment and ten minutes after each reset, so the
        // widget dims and hides a past-reset number without waiting for the app (KTD15).
        let timeline = CompanionTimelineSchedule.timeline(for: envelope, freshness: state.freshness, now: now)
        let entries = timeline.entryDates.map { date in
            entry(date: date, state: state, configuration: configuration, freshness: state.freshness)
        }
        return Timeline(entries: entries, policy: .after(timeline.reloadDate))
    }

    private func entry(
        date: Date,
        state: HeadroomWidgetState,
        configuration: HeadroomWidgetConfigurationIntent,
        freshness: CompanionFreshnessInputs?
    ) -> HeadroomWidgetEntry {
        HeadroomWidgetEntry(
            date: date,
            state: state,
            style: configuration.layoutStyle,
            colorMode: configuration.colorMode,
            freshness: freshness
        )
    }

    private func resolvedState() -> HeadroomWidgetState {
        let read = WidgetSnapshotCache.appGroup().read()
        log(read)
        return .from(read)
    }

    private func log(_ read: WidgetSnapshotCacheRead) {
        switch read {
        case .unavailable:
            widgetTimelineLogger.info("Widget cache read unavailable")
        case .empty:
            widgetTimelineLogger.info("Widget cache read empty")
        case .corrupt:
            widgetTimelineLogger.info("Widget cache read corrupt")
        case .incompatibleSchema:
            widgetTimelineLogger.info("Widget cache schema incompatible")
        case .snapshot(let envelope):
            widgetTimelineLogger.info(
                "Widget cache read snapshot status=\(envelope.status.rawValue, privacy: .public) providers=\(envelope.providers.count, privacy: .public)"
            )
        }
    }
}
