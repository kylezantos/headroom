import Foundation
import WidgetKit

struct HeadroomLockScreenWidgetEntry: TimelineEntry {
    let date: Date
    let state: IOSWidgetSnapshotState
    var style: WidgetLayoutStyle = LockScreenWidgetChoices.defaultStyle
    var providerChoice: LockScreenProviderChoice = .automatic
    var isPlaceholder = false
    /// U13 (iOS parity, KTD15): the same dimming and past-reset inputs the home widgets take.
    var freshness: CompanionFreshnessInputs?

    var freshnessTreatment: WidgetFreshnessTreatment {
        .widget(inputs: freshness, now: date, host: .phone)
    }
}

struct HeadroomLockScreenTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HeadroomLockScreenWidgetEntry {
        // KTD10/R16: a redacted placeholder must never carry a demo number or filled level.
        HeadroomLockScreenWidgetEntry(date: .now, state: .waitingForMac, isPlaceholder: true)
    }

    func snapshot(for configuration: HeadroomLockScreenConfigurationIntent, in context: Context) async -> HeadroomLockScreenWidgetEntry {
        if context.isPreview {
            return entry(date: .now, load: Load(state: .demo(Self.demoEnvelope), freshness: nil), configuration: configuration)
        }
        return entry(date: .now, load: load(), configuration: configuration)
    }

    func timeline(for configuration: HeadroomLockScreenConfigurationIntent, in context: Context) async -> Timeline<HeadroomLockScreenWidgetEntry> {
        let now = Date.now
        let load = load()
        let envelope: WidgetSnapshotEnvelope?
        switch load.state {
        case .demo(let content), .content(let content): envelope = content
        default: envelope = nil
        }
        // U13: entries at the dim moment and ten minutes after each reset, as on the home widgets.
        let timeline = CompanionTimelineSchedule.timeline(for: envelope, freshness: load.freshness, now: now)
        let entries = timeline.entryDates.map { date in
            entry(date: date, load: load, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .after(timeline.reloadDate))
    }

    /// KTD10: Lock Screen demo always shows the four-provider envelope, so every pinned
    /// provider has data, whichever demo variant the Home Screen widgets show.
    private static var demoEnvelope: WidgetSnapshotEnvelope { DemoScreenshotData.envelope(for: "fourProviders") }

    private struct Load {
        let state: IOSWidgetSnapshotState
        let freshness: CompanionFreshnessInputs?
    }

    /// U13 (KTD13, iOS parity): the same shared phone source as the home widgets. Demo is
    /// decided before iCloud is touched; only its envelope differs (KTD10 above).
    private func load() -> Load {
        let demoStore = CompanionDemoModeStore.appGroup()
        let demoSnapshot = demoStore.loaderSeam(launch: .current)()
        let snapshot = CompanionPhoneSnapshotSource.production(demo: { demoSnapshot }).load()
        let load = CompanionWidgetLoad.from(snapshot, isDemo: demoSnapshot != nil)
        if case .demo = load.state {
            return Load(state: .demo(Self.demoEnvelope), freshness: nil)
        }
        return Load(state: load.state, freshness: load.freshness)
    }

    private func entry(date: Date, load: Load, configuration: HeadroomLockScreenConfigurationIntent) -> HeadroomLockScreenWidgetEntry {
        HeadroomLockScreenWidgetEntry(
            date: date, state: load.state,
            style: configuration.layoutStyle, providerChoice: configuration.providerChoice,
            freshness: load.freshness
        )
    }
}
