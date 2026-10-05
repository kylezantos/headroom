import Foundation
import WidgetKit

struct HeadroomLockScreenWidgetEntry: TimelineEntry {
    let date: Date
    let state: IOSWidgetSnapshotState
    var style: WidgetLayoutStyle = LockScreenWidgetChoices.defaultStyle
    var providerChoice: LockScreenProviderChoice = .automatic
    var isPlaceholder = false
}

struct HeadroomLockScreenTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HeadroomLockScreenWidgetEntry {
        // KTD10/R16: a redacted placeholder must never carry a demo number or filled level.
        HeadroomLockScreenWidgetEntry(date: .now, state: .waitingForMac, isPlaceholder: true)
    }

    func snapshot(for configuration: HeadroomLockScreenConfigurationIntent, in context: Context) async -> HeadroomLockScreenWidgetEntry {
        let state = context.isPreview
            ? IOSWidgetSnapshotState.demo(DemoScreenshotData.envelope(for: "fourProviders"))
            : resolvedState()
        return entry(date: .now, state: state, configuration: configuration)
    }

    func timeline(for configuration: HeadroomLockScreenConfigurationIntent, in context: Context) async -> Timeline<HeadroomLockScreenWidgetEntry> {
        let now = Date.now
        let state = resolvedState()
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

    private func resolvedState() -> IOSWidgetSnapshotState {
        HeadroomIOSWidgetStateResolver.resolvedState(demoEnvelope: DemoScreenshotData.envelope(for: "fourProviders"))
    }

    private func entry(date: Date, state: IOSWidgetSnapshotState, configuration: HeadroomLockScreenConfigurationIntent) -> HeadroomLockScreenWidgetEntry {
        HeadroomLockScreenWidgetEntry(
            date: date, state: state,
            style: configuration.layoutStyle, providerChoice: configuration.providerChoice
        )
    }
}
