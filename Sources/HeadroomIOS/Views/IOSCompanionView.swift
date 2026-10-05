import SwiftUI
import WidgetKit

/// The app's one loading path (KTD6, U8): everything the phone shows comes from
/// `CompanionPhoneSnapshotSource` as a `CompanionResolvedSnapshot`. With
/// `CompanionLoaderAdoption.isEnabled` off, the source runs build 33's path lifted through the
/// resolver; no view reads iCloud or a cache itself.
enum PhoneSnapshotLoading {
    /// KTD21: `--demo`, `--demo-variant` and `--demo-screen`, parsed once.
    static let launch = CompanionDemoLaunchOptions.current
    static let demoStore = CompanionDemoModeStore.appGroup()
    /// KTD21: while demo is active the source returns bundled data and never reads iCloud or
    /// any cache.
    static let source = CompanionPhoneSnapshotSource.production(demo: demoStore.loaderSeam(launch: launch))
}

struct IOSCompanionView: View {
    @Binding var appearance: AppearanceSetting
    /// nil until the first load lands, so a launch never flashes the waiting screen.
    @State private var snapshot: CompanionResolvedSnapshot?
    @State private var isDemoMode = false
    @State private var diagnostics: IOSSyncDiagnostics?
    @State private var showSettings = false
    @State private var sessionDemoEnabled = false
    @State private var demoWidgetUnavailable = false
    @State private var didApplyLaunchSetup = false
    /// What the Home Screen widgets would show from the last non-demo load. A change reloads
    /// their timelines (replaces build 33's adopt-then-reload).
    @State private var lastWidgetReloadKey: WidgetReloadKey?
    @Environment(\.scenePhase) private var scenePhase

    private var launch: CompanionDemoLaunchOptions { PhoneSnapshotLoading.launch }
    private var demoModeStore: CompanionDemoModeStore { PhoneSnapshotLoading.demoStore }
    private var source: CompanionPhoneSnapshotSource { PhoneSnapshotLoading.source }

    var body: some View {
        NavigationStack {
            content
                .environment(
                    \.phoneDisplayResolver,
                    PhoneDisplayResolver.demoLaunchOverride(base: inheritedDisplayResolver) ?? inheritedDisplayResolver)
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
                        envelope: snapshot?.primaryProjection(),
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
            ensureScopeMarkerIfAdopted()
            Task {
                await refresh()
                // Capture harness only: present Settings once content has settled so the
                // sheet can be screenshotted headlessly.
                if opensSettingsForCapture { showSettings = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            ensureScopeMarkerIfAdopted()
            Task { await refresh() }
        }
        .onOpenURL { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { note in
            // KTD22: the typed change goes to the source first; with adoption on, an account
            // change clears every cache before the reload below reads anything.
            let change = iCloudKeyValueChange(userInfo: note.userInfo)
            source.handle(change)
            recordScopeMarkerChangeIfAdopted(change)
            Task { await refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot?.state {
        case nil:
            HeadroomTheme.backgroundView(scheme).ignoresSafeArea()
        case .content(let content):
            MirrorView(
                content: content,
                isDemoMode: isDemoMode,
                showsDemoBanner: isDemoMode && !launch.isDemoLaunch,
                canExitDemo: canExitDemo,
                demoWidgetUnavailable: demoWidgetUnavailable,
                onExitDemo: exitDemo,
                onRefresh: refresh
            )
        case .paused:
            StatusScreen(
                title: "Companion Sync Paused",
                message: "Turn Sync snapshot to iPhone back on in Headroom Settings on your Mac.",
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .accountScopeUnavailable:
            StatusScreen(
                title: "iCloud Not Available",
                message: "Make sure iCloud is enabled for Headroom on this device and your Mac.",
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .waiting(.some(.updatePhone)):
            StatusScreen(
                title: "Update Needed",
                message: "Update Headroom on your Mac and iPhone so their snapshot formats match.",
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        case .waiting:
            StatusScreen(
                title: "Waiting for Mac",
                message: "Open Headroom on your Mac to start syncing your usage to this device.",
                isWaiting: true,
                onExploreDemo: enterDemo,
                onRefresh: refresh
            )
            .navigationTitle("Headroom")
        }
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.phoneDisplayResolver) private var inheritedDisplayResolver

    /// The Settings sheet's sync rows. The Mac's source ID is a random lineage UUID, never a
    /// name to show, so the sheet reads "Headroom on Mac".
    private var syncInfo: IOSCompanionSyncInfo? {
        guard !isDemoMode, let content = snapshot?.content else { return nil }
        return IOSCompanionSyncInfo(publishedAt: content.generatedAt, sourceID: nil, sourcePlatform: .macOS)
    }

    /// KTD21: a `--demo` screenshot launch has no exit; Explore Demo does.
    private var canExitDemo: Bool {
        isDemoMode && !launch.isDemoLaunch
    }

    /// DEBUG-only: lets a capture script open Settings on launch (`HEADROOM_PREVIEW_SCREEN`)
    /// and `--demo-screen settings` does the same for a screenshot launch (KTD21).
    private var opensSettingsForCapture: Bool {
        if launch.isDemoLaunch && launch.screen == .settings { return true }
        #if DEBUG
        return CompanionPreviewSeed.previewScreen == .settings
        #else
        return false
        #endif
    }

    private func refresh() async {
        let floor = Task {
            try? await Task.sleep(for: .milliseconds(550))
        }
        applyLaunchSetupOnce()
        let resolved = await load()
        snapshot = resolved.snapshot
        isDemoMode = resolved.isDemo
        if !resolved.isDemo { reloadWidgetsIfChanged(resolved.snapshot) }
        diagnostics = await Self.diagnostics(for: resolved)
        await floor.value
    }

    /// Launch-time switches, applied before the first load reads anything.
    private func applyLaunchSetupOnce() {
        guard !didApplyLaunchSetup else { return }
        didApplyLaunchSetup = true
        // KTD21: a `--demo` launch is a screenshot launch, so the widget extension (which
        // cannot see launch arguments) hides its DEMO badge too; any other launch clears it.
        demoModeStore.setScreenshotPresentation(launch.isDemoLaunch)
        #if DEBUG
        if CompanionPreviewSeed.shouldResetDemoForUITest {
            sessionDemoEnabled = false
            demoWidgetUnavailable = false
            demoModeStore.setEnabled(false)
        }
        if CompanionPreviewSeed.isEnabled {
            // KTD21: the preview seed writes only the demo store, never a real cache, and
            // the widget gallery renders the same moment from it.
            CompanionPreviewSeed.seedDemoCache(demoModeStore)
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    private struct Loaded: Sendable {
        let snapshot: CompanionResolvedSnapshot
        let isDemo: Bool
    }

    private func load() async -> Loaded {
        #if DEBUG
        if CompanionPreviewSeed.isEnabled {
            // Renders as ordinary synced content (no banner): the case-study pair illustrates
            // the Mac→iPhone mirror.
            return Loaded(snapshot: CompanionPreviewSeed.snapshot(), isDemo: false)
        }
        #endif
        if sessionDemoEnabled {
            // Explore Demo when the App Group switch could not be written: still bundled data.
            return Loaded(snapshot: demoModeStore.snapshot(demoModeStore.variant(launch: launch)), isDemo: true)
        }
        if demoModeStore.isActive(launch: launch) {
            return Loaded(snapshot: await loadFromSource(), isDemo: true)
        }
        #if DEBUG
        if let uiTestState = CompanionPreviewSeed.uiTestState {
            return Loaded(snapshot: Self.lifted(CompanionPreviewSeed.envelope(for: uiTestState)), isDemo: false)
        }
        #endif
        return Loaded(snapshot: await loadFromSource(), isDemo: false)
    }

    /// `load()` reads KVS and the App Group files, so it runs off the main actor.
    private func loadFromSource() async -> CompanionResolvedSnapshot {
        let source = source
        return await Task.detached { source.load() }.value
    }

    private func enterDemo() {
        let result = demoModeStore.setEnabled(true)
        sessionDemoEnabled = result == .unavailable
        demoWidgetUnavailable = result == .unavailable
        if result == .changed {
            WidgetCenter.shared.reloadTimelines(ofKind: HeadroomIOSWidgetConfiguration.kind)
        }
        Task { await refresh() }
    }

    private func exitDemo() {
        sessionDemoEnabled = false
        demoWidgetUnavailable = false
        let result = demoModeStore.setEnabled(false)
        if result == .changed {
            WidgetCenter.shared.reloadTimelines(ofKind: HeadroomIOSWidgetConfiguration.kind)
        }
        Task { await refresh() }
    }

    // MARK: Widgets

    /// What the Home Screen widgets render: the state and the main-account projection
    /// (KTD13). Resolved first-seen times are left out, so an unchanged Mac publish never
    /// reloads timelines.
    struct WidgetReloadKey: Equatable {
        let state: String
        let projection: WidgetSnapshotEnvelope?
    }

    private func reloadWidgetsIfChanged(_ snapshot: CompanionResolvedSnapshot) {
        let key = WidgetReloadKey(state: Self.stateName(snapshot.state), projection: snapshot.primaryProjection())
        guard key != lastWidgetReloadKey else { return }
        lastWidgetReloadKey = key
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func stateName(_ state: CompanionResolvedState) -> String {
        switch state {
        case .accountScopeUnavailable: "scope"
        case .paused: "paused"
        case .waiting(let notice): "waiting.\(notice.map { "\($0)" } ?? "none")"
        case .content: "content"
        }
    }

    // MARK: KTD22 scope-marker hook (prepared, not enabled)

    /// KTD22: the app is the KVS scope marker's only writer. This hook runs on launch and
    /// foreground, and only once `CompanionLoaderAdoption.isEnabled` turns on (after the P5
    /// device gate passes); today it never constructs the writer.
    private func ensureScopeMarkerIfAdopted() {
        guard CompanionLoaderAdoption.isEnabled, !demoModeStore.isActive(launch: launch) else { return }
        Task.detached { _ = ScopeMarkerHook.writer.ensureMarker() }
    }

    private func recordScopeMarkerChangeIfAdopted(_ change: iCloudKeyValueChange) {
        guard CompanionLoaderAdoption.isEnabled else { return }
        ScopeMarkerHook.writer.record(change)
    }

    private enum ScopeMarkerHook {
        /// Lazily created: never touched while adoption is off.
        static let writer = CompanionKVSScopeMarkerWriter(store: UbiquitousKeyValueSyncStore())
    }

    // MARK: DEBUG diagnostics

    /// The DEBUG Sync Diagnostics rows. Read-only, DEBUG-only and separate from loading: they
    /// report what the v3 key and the compatibility cache hold right now.
    private static func diagnostics(for loaded: Loaded) async -> IOSSyncDiagnostics? {
        if loaded.isDemo {
            return IOSSyncDiagnostics(cacheGeneratedAt: nil, syncRead: .missing, origin: .demo)
        }
        #if DEBUG
        return await Task.detached {
            let read = iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore()).read()
            let cache = WidgetSnapshotCache.appGroup().read()
            let origin: IOSWidgetContentOrigin? = switch loaded.snapshot.content?.origin {
            case .v3: IOSWidgetSnapshotState.resolve(cacheRead: cache, syncRead: read).origin
            case .v4: .sync
            case nil: nil
            }
            return IOSSyncDiagnostics(cacheGeneratedAt: cache.envelope?.generatedAt, syncRead: read, origin: origin)
        }.value
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// UI-test states arrive as build-33 envelopes; lift them through the resolver's v3 rules
    /// like any other old-format content (KTD6.7).
    private static func lifted(_ envelope: WidgetSnapshotEnvelope?) -> CompanionResolvedSnapshot {
        guard let envelope,
              let bytes = try? SyncedWidgetSnapshotCodec.encode(
                SyncedWidgetSnapshotEnvelope(
                    publishedAt: envelope.generatedAt, sourceID: "UI Test", sourcePlatform: .macOS,
                    snapshot: envelope))
        else { return CompanionResolvedSnapshot(state: .waiting(nil)) }
        return CompanionSnapshotResolver.resolve(
            CompanionResolverInput(manifest: nil, v3: bytes, cache: .empty, now: Date())
        ).snapshot
    }
    #endif
}
