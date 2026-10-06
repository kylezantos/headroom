import SwiftUI
import WidgetKit

struct PhoneSettingsButton: View {
    let action: () -> Void
    var usesHeaderStyle = false

    var body: some View {
        Button(action: action) {
            if usesHeaderStyle {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular, in: .circle)
            } else {
                Image(systemName: "gearshape")
            }
        }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("headroom.settings")
    }
}

/// The app's one loading path (KTD6, U8): everything the phone shows comes from
/// `CompanionPhoneSnapshotSource` as a `CompanionResolvedSnapshot` (the scoped loader since
/// `CompanionLoaderAdoption` turned on); no view reads iCloud or a cache itself.
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
    /// U9: pull to check now, its status line and Settings' last round trip.
    @State private var checkNow = PhoneCheckNow()
    /// Review #10: only the latest-started load may publish (`CompanionLatestLoad`).
    @State private var loads = CompanionLatestLoad<Refreshed>()
    @Environment(\.scenePhase) private var scenePhase

    private var launch: CompanionDemoLaunchOptions { PhoneSnapshotLoading.launch }
    private var demoModeStore: CompanionDemoModeStore { PhoneSnapshotLoading.demoStore }
    private var source: CompanionPhoneSnapshotSource { PhoneSnapshotLoading.source }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    if !hasUsageContent {
                        ToolbarItem(placement: .topBarTrailing) {
                            PhoneSettingsButton { showSettings = true }
                        }
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
                        forcesLargeDetent: opensSettingsForCapture,
                        snapshot: snapshot,
                        lastCheckNow: checkNow.lastRoundTrip,
                        // U12: Settings › Demo switched the variant; re-read the demo data.
                        onDemoVariantChange: {
                            checkNow.reset()
                            Task { await refresh() }
                        }
                    )
                }
        }
        .onAppear {
            Task {
                await refresh()
                // Capture harness only: present Settings once content has settled so the
                // sheet can be screenshotted headlessly.
                if opensSettingsForCapture { showSettings = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
        .onOpenURL { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { note in
            // KTD22: the typed change goes to the source first. An account change clears every
            // cache, and an initial-sync or account change defers the marker write, before the
            // reload below reads anything.
            source.handle(iCloudKeyValueChange(userInfo: note.userInfo))
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
                checkNow: checkNow,
                onExitDemo: exitDemo,
                onCheckNow: pullToCheckNow,
                onSettings: { showSettings = true }
            )
        case .some(let state):
            // U10: one Core row per non-content state (iCloud unavailable, paused, waiting,
            // unreadable, update needed), copy and actions included.
            if let screen = statusScreen(for: state) {
                StatusScreen(screen: screen, onExploreDemo: enterDemo, onRefresh: refresh)
                    .navigationTitle("Headroom")
            }
        }
    }

    /// The usage screen owns both toolbar items so their order is stable.
    private var hasUsageContent: Bool {
        if case .content = snapshot?.state { true } else { false }
    }

    /// U10: the status screen for a non-content state. DEBUG captures and UI tests can pose
    /// the screens no fixture reaches (`HEADROOM_UI_TEST_STATUS`) over a non-content state.
    private func statusScreen(for state: CompanionResolvedState) -> CompanionStatusScreen? {
        guard let screen = CompanionStatusScreen(state) else { return nil }
        #if DEBUG
        if let posed = CompanionPreviewSeed.uiTestStatus { return posed }
        #endif
        return screen
    }

    @Environment(\.colorScheme) private var scheme

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
        // Review #10: launch, foreground, URL opens, every KVS change and pulls each start a
        // load. One that finishes after a newer one started publishes nothing, so stale data
        // never replaces newer numbers or reloads widgets back to them.
        if let refreshed = await loads.run({
            let loaded = await load()
            return Refreshed(loaded: loaded, diagnostics: await Self.diagnostics(for: loaded))
        }) {
            let resolved = refreshed.loaded
            snapshot = resolved.snapshot
            isDemoMode = resolved.isDemo
            if !resolved.isDemo {
                reloadWidgetsIfChanged(resolved.snapshot)
                // KTD14.7: every reload folds the receipt and the snapshot into the request.
                checkNow.update(snapshot: resolved.snapshot)
            }
            diagnostics = refreshed.diagnostics
        }
        await floor.value
    }

    /// U9 (R18, KTD14): pull to refresh and ⌘R. A v4 Mac gets a request and the call returns
    /// at once; Explore Demo replays the bundled receipt and writes nothing (AE8); an older
    /// Mac, a paused or waiting state, or a phone without its App Group re-reads (AE1).
    private func pullToCheckNow() async {
        guard let current = snapshot else { return await refresh() }
        let started = isDemoMode
            ? checkNow.pullDemo(
                snapshot: current, store: demoModeStore,
                variant: demoModeStore.variant(launch: launch),
                adopt: adoptCheckedSnapshot)
            : checkNow.pull(snapshot: current)
        guard !started else { return }
        await refresh()
        #if DEBUG
        checkNow.recordRereadPull()
        #endif
    }

    /// KTD14.7: a demo check's finished snapshot is newer than any load still in flight.
    private func adoptCheckedSnapshot(_ checked: CompanionResolvedSnapshot) {
        loads.supersede()
        snapshot = checked
    }

    private struct Refreshed {
        let loaded: Loaded
        let diagnostics: IOSSyncDiagnostics?
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
            // U12: a UI test that picked a variant in Settings › Demo leaves the App Group
            // back on the unset default ("full"), so suites that read it start clean.
            demoModeStore.setVariant("full")
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
        if CompanionPreviewSeed.uiTestState == .unreadable {
            return Loaded(snapshot: CompanionPreviewSeed.unreadableSnapshot(), isDemo: false)
        }
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
        checkNow.reset()
        let result = demoModeStore.setEnabled(true)
        sessionDemoEnabled = result == .unavailable
        demoWidgetUnavailable = result == .unavailable
        if result == .changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task { await refresh() }
    }

    private func exitDemo() {
        checkNow.reset()
        sessionDemoEnabled = false
        demoWidgetUnavailable = false
        let result = demoModeStore.setEnabled(false)
        if result == .changed {
            WidgetCenter.shared.reloadAllTimelines()
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
        case .unreadable: "unreadable"
        case .content: "content"
        }
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
