import Foundation
import WidgetKit

struct HeadroomIOSTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadroomIOSWidgetEntry {
        HeadroomIOSWidgetEntry(date: .now, state: .content(DemoScreenshotData.envelope))
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadroomIOSWidgetEntry) -> Void) {
        completion(entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadroomIOSWidgetEntry>) -> Void) {
        let now = Date.now
        let state = resolvedState()
        let entries = (0..<15).map { offset in
            HeadroomIOSWidgetEntry(date: now.addingTimeInterval(Double(offset) * 60), state: state)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func entry(date: Date) -> HeadroomIOSWidgetEntry {
        HeadroomIOSWidgetEntry(date: date, state: resolvedState())
    }

    private func resolvedState() -> IOSWidgetSnapshotState {
        let cache = WidgetSnapshotCache.appGroup()
        let sync = iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore())
        let syncRead = sync.read()
        let cacheRead = cache.read()
        // Adopt the remote snapshot only when it's newer than (or absent from) the cache, so
        // an older iCloud payload never overwrites fresher cached content. Resolution below is
        // newest-wins regardless, but this keeps the on-disk cache honest for the next read.
        if case .snapshot(let envelope) = syncRead,
           adoptable(remote: envelope.snapshot, into: cacheRead) {
            try? cache.write(envelope.snapshot)
        }
        return .from(cacheRead: cache.read(), syncRead: syncRead)
    }

    private func adoptable(remote: WidgetSnapshotEnvelope, into cacheRead: WidgetSnapshotCacheRead) -> Bool {
        guard let cached = cacheRead.envelope else { return true }
        if remote.generatedAt > cached.generatedAt { return true }
        return remote.generatedAt == cached.generatedAt && remote != cached
    }
}
