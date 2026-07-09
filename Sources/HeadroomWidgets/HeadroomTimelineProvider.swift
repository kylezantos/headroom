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
        completion(entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadroomWidgetEntry>) -> Void) {
        let now = Date.now
        let state = resolvedState()
        let entries = (0..<15).map { offset in
            HeadroomWidgetEntry(date: now.addingTimeInterval(Double(offset) * 60), state: state)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
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
        case .snapshot(let envelope):
            widgetTimelineLogger.info(
                "Widget cache read snapshot status=\(envelope.status.rawValue, privacy: .public) providers=\(envelope.providers.count, privacy: .public)"
            )
        }
    }
}
