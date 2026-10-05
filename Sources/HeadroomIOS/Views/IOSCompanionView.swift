import SwiftUI
import WidgetKit

struct IOSCompanionView: View {
    @Binding var appearance: AppearanceSetting
    @State private var state: IOSWidgetSnapshotState = .waitingForMac
    @State private var syncInfo: IOSCompanionSyncInfo?
    @State private var diagnostics: IOSSyncDiagnostics?
    @State private var showSettings = false
    @State private var sessionDemoEnabled = false
    @State private var demoWidgetUnavailable = false
    @State private var didApplyUITestReset = false
    @State private var suppressPersistedDemoForUITest = false
    @Environment(\.scenePhase) private var scenePhase

    private let demoModeStore = CompanionDemoModeStore.appGroup()

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("headroom.settings")
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsSheetView(
                        envelope: currentEnvelope,
                        syncInfo: syncInfo,
                        diagnostics: diagnostics,
                        isDemoMode: isDemoMode,
                        canExitDemo: canExitDemo,
                        demoWidgetUnavailable: demoWidgetUnavailable,
                        appearance: $appearance,
                        onEnterDemo: enterDemo,
                        onExitDemo: exitDemo,
                        forcesLargeDetent: opensSettingsForCapture
                    )
                }
        }
        .onAppear {
            Task {
                await refresh()
                // Capture harness only: present Settings once content has settled so the
                // sheet can be screenshotted headlessly. Always false in Release.
                if opensSettingsForCapture { showSettings = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onOpenURL { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            Task { await refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .demo(let envelope):
            MirrorView(
                envelope: envelope,
                syncInfo: nil,
                diagnostics: diagnostics,
                isDemoMode: true,
                canExitDemo: canExitDemo,
                demoWidgetUnavailable: demoWidgetUnavailable,
                onExitDemo: exitDemo,
                appearance: $appearance,
                onRefresh: refresh
            )
        case .content(let envelope):
            MirrorView(
                envelope: envelope,
                syncInfo: syncInfo,
                diagnostics: diagnostics,
                isDemoMode: false,
                canExitDemo: false,
                demoWidgetUnavailable: false,
                onExitDemo: exitDemo,
                appearance: $appearance,
                onRefresh: refresh
            )
        case .disabled:
            StatusScreen(
                title: "Companion Sync Paused",
                message: "Turn Sync snapshot to iPhone back on in Headroom Settings on your Mac.",
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .setupNeeded:
            StatusScreen(
                title: "iCloud Not Available",
                message: "Make sure iCloud is enabled for Headroom on this device and your Mac.",
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .waitingForMac:
            StatusScreen(
                title: "Waiting for Mac",
                message: "Open Headroom on your Mac to start syncing your usage to this device.",
                isWaiting: true,
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .corrupt:
            StatusScreen(
                title: "Snapshot Unreadable",
                message: "Open Headroom on your Mac to publish a fresh snapshot.",
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .incompatibleSchema:
            StatusScreen(
                title: "Update Needed",
                message: "Update Headroom on your Mac and iPhone so their snapshot formats match.",
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        }
    }

    private var currentEnvelope: WidgetSnapshotEnvelope? {
        switch state {
        case .content(let envelope), .demo(let envelope): envelope
        default: nil
        }
    }

    private var isDemoMode: Bool {
        if case .demo = state { true } else { false }
    }

    private var canExitDemo: Bool {
        isDemoMode && !DemoScreenshotData.isEnabled
    }

    /// DEBUG-only: lets the case-study capture script open Settings on launch and shoot it
    /// headlessly, with no UI automation. Compiled out of Release.
    private var opensSettingsForCapture: Bool {
        #if DEBUG
        CompanionPreviewSeed.previewScreen == .settings
        #else
        false
        #endif
    }

    private func refresh() async {
        let floor = Task {
            try? await Task.sleep(for: .milliseconds(550))
        }
        #if DEBUG
        if CompanionPreviewSeed.shouldResetDemoForUITest && !didApplyUITestReset {
            sessionDemoEnabled = false
            demoWidgetUnavailable = false
            suppressPersistedDemoForUITest = true
            demoModeStore.setEnabled(false)
            didApplyUITestReset = true
        }
        #endif
        if DemoScreenshotData.isEnabled
            || sessionDemoEnabled
            || (!suppressPersistedDemoForUITest && demoModeStore.isEnabled) {
            // Demo state is resolved before cache/iCloud and never enters either persistence path.
            state = .demo(DemoScreenshotData.envelope)
            syncInfo = nil
            diagnostics = IOSSyncDiagnostics(cacheGeneratedAt: nil, syncRead: .missing, origin: .demo)
            await floor.value
            return
        }
        #if DEBUG
        if let uiTestState = CompanionPreviewSeed.uiTestState {
            if let envelope = CompanionPreviewSeed.envelope(for: uiTestState, now: Date()) {
                state = .content(envelope)
                syncInfo = IOSCompanionSyncInfo(publishedAt: envelope.generatedAt, sourceID: "UI Test", sourcePlatform: .macOS)
            } else {
                state = .waitingForMac
                syncInfo = nil
            }
            diagnostics = IOSSyncDiagnostics(cacheGeneratedAt: nil, syncRead: .missing, origin: nil)
            await floor.value
            return
        }
        if CompanionPreviewSeed.isEnabled {
            let envelope = CompanionPreviewSeed.envelope(now: Date())
            state = .content(envelope)
            // Also seed the widget's app-group cache and reload timelines so the widget
            // gallery renders the same sample content in the Simulator (iOS visual gate).
            try? WidgetSnapshotCache.appGroup().write(envelope)
            WidgetCenter.shared.reloadAllTimelines()
            await floor.value
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
        await floor.value
    }

    private func enterDemo() {
        sessionDemoEnabled = true
        let result = demoModeStore.setEnabled(true)
        demoWidgetUnavailable = result == .unavailable
        if result == .changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task { await refresh() }
    }

    private func exitDemo() {
        sessionDemoEnabled = false
        demoWidgetUnavailable = false
        let result = demoModeStore.setEnabled(false)
        if result == .changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task { await refresh() }
    }

    /// A remote snapshot is worth writing to the local cache when the cache holds nothing,
    /// or when the remote is strictly newer than (or a different payload from) what's cached.
    private func adoptable(remote: WidgetSnapshotEnvelope, into cacheRead: WidgetSnapshotCacheRead) -> Bool {
        guard let cached = cacheRead.envelope else { return true }
        if remote.generatedAt > cached.generatedAt { return true }
        return remote.generatedAt == cached.generatedAt && remote != cached
    }
}
