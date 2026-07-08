import SwiftUI
import WidgetKit

struct IOSCompanionView: View {
    @Binding var appearance: AppearanceSetting
    @State private var state: IOSWidgetSnapshotState = .waitingForMac
    @State private var syncInfo: IOSCompanionSyncInfo?
    @State private var diagnostics: IOSSyncDiagnostics?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onOpenURL { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .content(let envelope):
            MirrorView(
                envelope: envelope,
                syncInfo: syncInfo,
                diagnostics: diagnostics,
                appearance: $appearance,
                onRefresh: refresh
            )
        case .disabled:
            StatusScreen(
                title: "iPhone Sync Paused",
                message: "Turn Sync snapshot to iPhone back on in Headroom Settings on your Mac.",
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .setupNeeded:
            StatusScreen(
                title: "iCloud Not Available",
                message: "Make sure iCloud is enabled for Headroom on this iPhone and your Mac.",
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .waitingForMac:
            StatusScreen(
                title: "Waiting for Mac",
                message: "Open Headroom on your Mac to start syncing your usage to this iPhone.",
                isWaiting: true,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .corrupt:
            StatusScreen(
                title: "Snapshot Unreadable",
                message: "Open Headroom on your Mac to publish a fresh snapshot.",
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .incompatibleSchema:
            StatusScreen(
                title: "Update Needed",
                message: "Update Headroom on your Mac and iPhone so their snapshot formats match.",
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        }
    }

    private func refresh() {
        #if DEBUG
        if CompanionPreviewSeed.isEnabled {
            let envelope = CompanionPreviewSeed.envelope(now: Date())
            state = .content(envelope)
            // Also seed the widget's app-group cache and reload timelines so the widget
            // gallery renders the same sample content in the Simulator (iOS visual gate).
            try? WidgetSnapshotCache.appGroup().write(envelope)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        #endif
        let cache = WidgetSnapshotCache.appGroup()
        let sync = iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore())
        let read = sync.read()
        let cacheRead = cache.read()
        var resolvedCacheRead = cacheRead
        if case .snapshot(let envelope) = read {
            // Adopt the remote snapshot into the shared cache so the widget process reads the
            // same content — but only when it is genuinely newer (or the cache lacks it), so a
            // newer local cache is never clobbered by an older remote and WidgetKit isn't
            // reloaded needlessly.
            if adoptable(remote: envelope.snapshot, into: cacheRead) {
                try? cache.write(envelope.snapshot)
                WidgetCenter.shared.reloadAllTimelines()
                resolvedCacheRead = cache.read()
            }
            syncInfo = IOSCompanionSyncInfo(
                publishedAt: envelope.publishedAt,
                sourceID: envelope.sourceID,
                sourcePlatform: envelope.sourcePlatform
            )
        } else {
            syncInfo = nil
        }
        let resolution = IOSWidgetSnapshotState.resolve(cacheRead: resolvedCacheRead, syncRead: read)
        state = resolution.state
        diagnostics = IOSSyncDiagnostics(
            cacheGeneratedAt: resolvedCacheRead.envelope?.generatedAt,
            syncRead: read,
            origin: resolution.origin
        )
    }

    /// A remote snapshot is worth writing to the local cache when the cache holds nothing,
    /// or when the remote is strictly newer than (or a different payload from) what's cached.
    private func adoptable(remote: WidgetSnapshotEnvelope, into cacheRead: WidgetSnapshotCacheRead) -> Bool {
        guard let cached = cacheRead.envelope else { return true }
        if remote.generatedAt > cached.generatedAt { return true }
        return remote.generatedAt == cached.generatedAt && remote != cached
    }
}
