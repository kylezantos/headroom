import Foundation
import WidgetKit

/// KTD1 (2026-10-02 widget-styles plan): an App Intent provider so each placed widget carries
/// its own Style and Color from Edit Widget. The kind string is unchanged, so widgets placed
/// before the update keep their identity and pick up the parameter defaults.
struct HeadroomIOSTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HeadroomIOSWidgetEntry {
        HeadroomIOSWidgetEntry(date: .now, state: .demo(DemoScreenshotData.envelope))
    }

    func snapshot(for configuration: HeadroomWidgetConfigurationIntent, in context: Context) async -> HeadroomIOSWidgetEntry {
        if context.isPreview {
            return entry(date: .now, state: .demo(DemoScreenshotData.envelope), configuration: configuration)
        }
        return entry(date: .now, state: HeadroomIOSWidgetStateResolver.resolvedState(demoEnvelope: DemoScreenshotData.envelope), configuration: configuration)
    }

    func timeline(for configuration: HeadroomWidgetConfigurationIntent, in context: Context) async -> Timeline<HeadroomIOSWidgetEntry> {
        let now = Date.now
        let state = HeadroomIOSWidgetStateResolver.resolvedState(demoEnvelope: DemoScreenshotData.envelope)
        let envelope: WidgetSnapshotEnvelope?
        switch state {
        case .demo(let content), .content(let content): envelope = content
        default: envelope = nil
        }
        let entries = WidgetTimelineSchedule.entryDates(for: envelope, now: now).map { date in
            entry(date: date, state: state, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .after(WidgetTimelineSchedule.refreshDate(after: now)))
    }

    private func entry(
        date: Date,
        state: IOSWidgetSnapshotState,
        configuration: HeadroomWidgetConfigurationIntent
    ) -> HeadroomIOSWidgetEntry {
        HeadroomIOSWidgetEntry(
            date: date,
            state: state,
            style: configuration.layoutStyle,
            colorMode: configuration.colorMode
        )
    }

}

/// KTD10 (2026-10-04 Lock Screen plan): both iOS kinds share newest-valid cache/iCloud
/// resolution; their demo envelopes stay independent and never enter persistence.
enum HeadroomIOSWidgetStateResolver {
    static func resolvedState(demoEnvelope: @autoclosure () -> WidgetSnapshotEnvelope) -> IOSWidgetSnapshotState {
        if CompanionDemoModeStore.appGroup().isEnabled {
            return .demo(demoEnvelope())
        }
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
        return .from(cacheRead: cacheRead, syncRead: syncRead)
    }

    private static func adoptable(remote: WidgetSnapshotEnvelope, into cacheRead: WidgetSnapshotCacheRead) -> Bool {
        guard let cached = cacheRead.envelope else { return true }
        return remote.generatedAt > cached.generatedAt
    }
}
