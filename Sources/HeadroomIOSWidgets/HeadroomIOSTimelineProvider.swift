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
        return entry(date: .now, load: load(), configuration: configuration)
    }

    func timeline(for configuration: HeadroomWidgetConfigurationIntent, in context: Context) async -> Timeline<HeadroomIOSWidgetEntry> {
        let now = Date.now
        let load = load()
        let envelope: WidgetSnapshotEnvelope?
        switch load.state {
        case .demo(let content), .content(let content): envelope = content
        default: envelope = nil
        }
        // U13: entries also land at the dim moment (the 60-minute widget floor) and ten minutes
        // after each reset, and the reload comes no later than the dim moment (KTD15).
        let timeline = CompanionTimelineSchedule.timeline(for: envelope, freshness: load.freshness, now: now)
        let entries = timeline.entryDates.map { date in
            entry(date: date, load: load, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .after(timeline.reloadDate))
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

    private func entry(date: Date, load: Load, configuration: HeadroomWidgetConfigurationIntent) -> HeadroomIOSWidgetEntry {
        var entry = entry(date: date, state: load.state, configuration: configuration)
        entry.freshness = load.freshness
        entry.showsDemoBadge = load.showsDemoBadge
        return entry
    }

    private struct Load {
        let state: IOSWidgetSnapshotState
        let freshness: CompanionFreshnessInputs?
        let showsDemoBadge: Bool
    }

    /// U13 (KTD13): the widget loads through the shared phone source — never its own iCloud
    /// or cache reads — and shows the resolver's primary-only projection. Demo is decided
    /// once, before iCloud is touched, and its bundled snapshot short-circuits the source (KTD21).
    private func load() -> Load {
        let demoStore = CompanionDemoModeStore.appGroup()
        let demoSnapshot = demoStore.loaderSeam(launch: .current)()
        let snapshot = CompanionPhoneSnapshotSource.production(demo: { demoSnapshot }).load()
        let load = CompanionWidgetLoad.from(snapshot, isDemo: demoSnapshot != nil)
        return Load(state: load.state, freshness: load.freshness, showsDemoBadge: !demoStore.isScreenshotPresentation)
    }
}
