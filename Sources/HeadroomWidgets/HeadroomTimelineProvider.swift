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
            return entry(date: .now, state: .content(DemoScreenshotData.envelope), configuration: configuration)
        }
        return entry(date: .now, state: resolvedState(), configuration: configuration)
    }

    func timeline(for configuration: HeadroomWidgetConfigurationIntent, in context: Context) async -> Timeline<HeadroomWidgetEntry> {
        let now = Date.now
        let state = resolvedState()
        let envelope: WidgetSnapshotEnvelope?
        if case .content(let content) = state { envelope = content } else { envelope = nil }
        let entries = WidgetTimelineSchedule.entryDates(for: envelope, now: now).map { date in
            entry(date: date, state: state, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .after(WidgetTimelineSchedule.refreshDate(after: now)))
    }

    private func entry(
        date: Date,
        state: HeadroomWidgetState,
        configuration: HeadroomWidgetConfigurationIntent
    ) -> HeadroomWidgetEntry {
        HeadroomWidgetEntry(
            date: date,
            state: state,
            style: configuration.layoutStyle,
            colorMode: configuration.colorMode
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
