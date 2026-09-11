import Foundation
import HeadroomCore
import os
import WidgetKit

private let widgetTimelineLogger = Logger(subsystem: "com.kylezantos.headroom.widgets", category: "timeline")

struct HeadroomTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadroomWidgetEntry {
        HeadroomWidgetEntry(date: .now, state: .content(DemoScreenshotData.envelope))
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadroomWidgetEntry) -> Void) {
        // WCW4: the widget gallery is the product's first impression, and a machine that has
        // not run Headroom yet would otherwise show it a status card. The iOS provider has
        // always had this branch; the Mac one did not.
        if context.isPreview {
            completion(HeadroomWidgetEntry(date: .now, state: .content(DemoScreenshotData.envelope)))
        } else {
            completion(entry(date: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadroomWidgetEntry>) -> Void) {
        let now = Date.now
        let state = resolvedState()
        let envelope: WidgetSnapshotEnvelope?
        if case .content(let content) = state { envelope = content } else { envelope = nil }
        let entries = WidgetTimelineSchedule.entryDates(for: envelope, now: now).map { date in
            HeadroomWidgetEntry(date: date, state: state)
        }
        completion(Timeline(entries: entries, policy: .after(WidgetTimelineSchedule.refreshDate(after: now))))
    }

    private func entry(date: Date) -> HeadroomWidgetEntry {
        HeadroomWidgetEntry(date: date, state: resolvedState())
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
