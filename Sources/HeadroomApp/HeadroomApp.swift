import SwiftUI
import AppKit
import WidgetKit
import HeadroomCore

/// Entry point. Supports hidden diagnostics: `--probe-claude` / `--probe-codex` run the real
/// provider capture once and print parsed windows; `--dump-phone-sync` decodes the iCloud KVS
/// payload the Mac published for the iPhone. All run without launching the menu bar UI.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--probe-claude") {
            runClaudeProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-codex") {
            runCodexProbe()
            return
        }
        if CommandLine.arguments.contains("--dump-phone-sync") {
            runPhoneSyncDump()
            return
        }
        HeadroomApp.main()
    }

    private static func runClaudeProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let path = ClaudeUsageCLIProbe.resolveClaudePath() ?? "(not found)"
            print("claude path: \(path)")
            switch await ClaudeUsageCLIProbe(workingDirectory: claudeWorkingDirectory()).capturePanel() {
            case .cliNotFound:
                print("RESULT: CLI not found")
            case .failed:
                print("RESULT: capture failed (no panel text)")
            case .panel(let text):
                let windows = ClaudeUsageParser.parse(text)
                print("RESULT: captured panel (\(text.count) chars), parsed \(windows.count) window(s):")
                for w in windows {
                    print("  • \(w.kind)  \(Int(w.percentUsed))% used  →  \(w.resetLabel ?? "no reset")  (remaining \(Int(100 - w.percentUsed))%)")
                }
                // Always dump the raw panel so we can see fields the parser doesn't yet
                // extract (e.g. the subscription tier for the plan pill).
                print("--- RAW PANEL (first 1500 chars) ---")
                print(String(text.prefix(1500)))
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    fileprivate static func claudeWorkingDirectory() -> String {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingLastPathComponent().path
        }
        return FileManager.default.currentDirectoryPath
    }

    private static func runCodexProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let snapshot = await CodexProvider(credentials: CredentialStore()).fetchSnapshot()
            switch snapshot.freshness {
            case .pending:
                print("RESULT: pending")
            case .live:
                print("RESULT: live Codex snapshot, parsed \(snapshot.windows.count) window(s):")
                if let plan = snapshot.planLabel {
                    print("  plan: \(plan)")
                }
                for window in snapshot.windows {
                    print("  • \(window.kind)  \(Int(window.utilization.rounded()))% used  →  \(window.resetsAt)  (remaining \(Int(window.percentRemaining.rounded()))%)")
                }
            case .stale(let reason):
                print("RESULT: stale Codex snapshot: \(reason.message)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// Decode and print the widget-safe snapshot the Mac last published to iCloud KVS for the
    /// iPhone. Answers the stale-sync question directly: is the "Sync snapshot to iPhone"
    /// toggle on, and is a *fresh* payload actually sitting in the key-value store. The
    /// snapshot model is redaction-safe (display-ready usage only — no credentials/paths).
    private static func runPhoneSyncDump() {
        // The reading is only meaningful from the signed .app bundle: `swift run` has no bundle
        // identifier (so UserDefaults resolves a different domain) and no iCloud-KVS entitlement
        // (so the store is inert). Surface the bundle id so an empty result from a bare CLI run
        // is never mistaken for the real app's state.
        print("bundle id: \(Bundle.main.bundleIdentifier ?? "(none — running outside an .app; readings are not the installed app's state)")")

        let preferences = Preferences()
        print("syncToIPhoneEnabled: \(preferences.syncToIPhoneEnabled)")

        let store = UbiquitousKeyValueSyncStore()
        _ = store.synchronize()
        let data = store.data(forKey: iCloudSnapshotSync.snapshotKey)
        print("KVS key:   \(iCloudSnapshotSync.snapshotKey)")
        print("KVS bytes: \(data?.count ?? 0)")

        switch SyncedWidgetSnapshotCodec.decode(data) {
        case .missing:
            print("RESULT: no payload in iCloud KVS (missing) — the Mac has not published, or the store is empty on this account.")
        case .corrupt:
            print("RESULT: payload present but undecodable (corrupt).")
        case .incompatibleSchema:
            print("RESULT: payload schema incompatible with this build.")
        case .snapshot(let envelope):
            let formatter = ISO8601DateFormatter()
            print("RESULT: snapshot present")
            print("  publishedAt:          \(formatter.string(from: envelope.publishedAt))")
            print("  snapshot.generatedAt: \(formatter.string(from: envelope.snapshot.generatedAt))")
            print("  sourceID:             \(envelope.sourceID)")
            print("  sourcePlatform:       \(envelope.sourcePlatform.rawValue)")
            print("  status:               \(envelope.snapshot.status.rawValue)")
            print("  envelope.schema:      \(envelope.schemaVersion)")
            print("  snapshot.schema:      \(envelope.snapshot.schemaVersion)")
            let providers = envelope.snapshot.providers.map(\.id).joined(separator: ", ")
            print("  providers:            \(providers.isEmpty ? "(none)" : providers)")
            let apiSpend = envelope.snapshot.apiSpendProviders.map(\.id).joined(separator: ", ")
            print("  apiSpendProviders:    \(apiSpend.isEmpty ? "(none)" : apiSpend)")
        }
    }
}

/// Menu bar app (U1). `MenuBarExtra(.window)` gives a custom Liquid Glass popover
/// (KTD9). No Dock icon in the shipped app — `LSUIElement = YES` is stamped into the
/// Xcode app target's Info.plist when finalizing the bundle (U1/KTD8).
struct HeadroomApp: App {
    @State private var store: UsageStore
    @State private var appearancePreference: AppearancePreference
    @StateObject private var softwareUpdates = SoftwareUpdateController()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let preferences: Preferences

    @MainActor
    init() {
        let preferences = Preferences()
        let store = AppComposition.store(preferences: preferences)
        self.preferences = preferences
        _store = State(initialValue: store)
        _appearancePreference = State(initialValue: preferences.appearancePreference)
        AppDelegate.startUsageStore = { Task { await store.start() } }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store) {
                openSettings()
            }
                .preferredColorScheme(appearancePreference.colorScheme)
                .task { await store.start() }
        } label: {
            MenuBarLabel(
                meters: store.menuBarMeters,
                showsPercentage: store.showMenuBarPercentage
            )
            .preferredColorScheme(appearancePreference.colorScheme)
            .task { await store.start() }
        }
        .menuBarExtraStyle(.window)

        Window("Headroom Settings", id: "settings") {
            SettingsView(
                store: store,
                appearancePreference: $appearancePreference,
                softwareUpdates: softwareUpdates,
                preferences: preferences
            )
            .preferredColorScheme(appearancePreference.colorScheme)
        }
        // Hidden title bar: the settings window draws its own header (logo + title) in
        // content, so traffic lights float on a transparent strip. Avoids Tahoe wrapping a
        // toolbar item in a Liquid Glass container. (Standard modern-macOS utility pattern.)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 460, height: 700)
        .defaultPosition(.center)
    }

    /// Open (or re-focus) the Settings window. An accessory / `LSUIElement` app is not
    /// activated by `openWindow` alone, so the window would open *behind* the frontmost
    /// app or never take keyboard focus — and clicking the gear a second time would look
    /// like a no-op because the already-open window stays buried. Activating brings it
    /// forward and makes it key on both first open and re-open. (`Done`/⌘W close it via
    /// the view's `dismiss`; this method reopens cleanly afterward.)
    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        // `.defaultPosition(.center)` (and SwiftUI's persisted frame) can land the window on
        // whichever display it was last on — often the wrong one on a multi-monitor setup.
        // A menu-bar app is invoked from wherever the user is looking, so re-home it onto the
        // screen under the cursor. Deferred a runloop tick so the NSWindow exists.
        DispatchQueue.main.async { Self.placeSettingsWindowOnActiveScreen() }
    }

    /// Center the Settings window on the active screen (the one under the cursor). If the
    /// window is already showing on that screen, its current position is respected so a
    /// user's manual placement isn't yanked back to center on every re-open.
    private static func placeSettingsWindowOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let activeScreen,
              let window = NSApp.windows.first(where: { $0.title == "Headroom Settings" })
        else { return }

        if window.isVisible, activeScreen.frame.intersects(window.frame) { return }

        // Force the layout pass so SwiftUI has applied the Settings content's preferred size
        // before we read it. At open the window is briefly wider than its content, and reading
        // that transient frame centers ~50px off.
        window.layoutIfNeeded()
        let visible = activeScreen.visibleFrame
        let size = window.frame.size
        // Horizontally centered; nudged slightly above the vertical midpoint, matching the
        // weighting AppKit's own `NSWindow.center()` uses.
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + size.height * 0.05
        )
        window.setFrameOrigin(origin)
    }
}

private extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Pins the process to `.accessory` at launch so it behaves as a pure menu-bar app —
/// no Dock icon, no app-switcher entry — even when run via `swift run` (which has no
/// `LSUIElement` Info.plist). This also makes the Settings-window activation path
/// identical in development and in the shipped bundle, so "does the window open and
/// close properly" can be verified with `swift run Headroom`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var startUsageStore: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.startUsageStore?()
    }
}

/// Composition root (R13): the one place concrete providers are wired to the engine.
/// Adding a third provider is a one-line append here plus a card — no engine change.
enum AppComposition {
    @MainActor
    static func store(preferences: Preferences = Preferences()) -> UsageStore {
        if DemoFixture.isEnabled { return demoStore() }
        let credentials = CredentialStore()
        return UsageStore(
            providers: providers(credentials: credentials),
            apiSpendProviders: apiSpendProviders(credentials: credentials),
            preferences: preferences,
            widgetExporter: widgetExporter(),
            phoneSyncExporter: phoneSyncExporter()
        )
    }

    /// Screenshot demo mode (`--demo`): fixed sample data wired into the real UI across
    /// every surface. Preferences live in a private UserDefaults suite so demo runs never
    /// touch the user's real settings. Keeps the real widget + iCloud exporters, so the
    /// macOS widgets and the iPhone mirror pick up the same fixed numbers.
    @MainActor
    private static func demoStore() -> UsageStore {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "co.zantos.headroom.demo") ?? .standard)
        prefs.showMenuBarPercentage = true
        prefs.menuBarFillSource = .claude          // Claude weekly (38%) drives the menu-bar number
        prefs.widgetsEnabled = true
        prefs.syncToIPhoneEnabled = true
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)   // API spend surfaces are off by default
        prefs.setSurfaceEnabled(true, for: .openAIAPI)
        prefs.setRenewalDate(DemoFixture.renewalDate(for: .claude), for: .claude)
        prefs.setRenewalDate(DemoFixture.renewalDate(for: .codex), for: .codex)
        return UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            apiSpendProviders: [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ],
            preferences: prefs,
            widgetExporter: widgetExporter(),
            phoneSyncExporter: phoneSyncExporter()
        )
    }

    static func providers() -> [any UsageProvider] {
        providers(credentials: CredentialStore())
    }

    private static func providers(credentials: CredentialStore) -> [any UsageProvider] {
        return [
            ClaudeProvider(source: ClaudeUsageCLIProbe(workingDirectory: Entry.claudeWorkingDirectory())),
            CodexProvider(credentials: credentials), // reads ~/.codex/auth.json + wham/usage
        ]
    }

    private static func apiSpendProviders(credentials: CredentialStore) -> [any APISpendProvider] {
        [
            AnthropicAPISpendProvider(credentials: credentials),
            OpenAIAPISpendProvider(credentials: credentials),
        ]
    }

    static func widgetExporter() -> any WidgetSnapshotExporting {
        WidgetSnapshotExporter(cache: .appGroup()) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func phoneSyncExporter() -> any WidgetSnapshotExporting {
        iCloudSnapshotPublisher(sync: iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore()))
    }
}
