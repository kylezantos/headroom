import SwiftUI
import AppKit
import WidgetKit
import HeadroomCore

/// Entry point. Supports hidden diagnostics: `--probe-claude` / `--probe-codex` /
/// `--probe-grok` / `--probe-cursor` run the real provider capture once and print parsed
/// windows; `--probe-spend <openai|anthropic|xai> [--key-file <path>]` verifies a key-based
/// API-spend path; `--dump-phone-sync` decodes the iCloud KVS payload the Mac published for
/// the iPhone; `--bench-ui` measures the popover and Settings offscreen (`UIBenchHarness`).
/// All run without launching the menu bar UI.
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
        if CommandLine.arguments.contains("--probe-grok") {
            runGrokProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-cursor") {
            runCursorProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-spend") {
            runSpendProbe()
            return
        }
        if CommandLine.arguments.contains("--dump-phone-sync") {
            runPhoneSyncDump()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-widgets") {
            // KTD12 (widget-styles plan): headless renders of every widget style.
            let outDir = CommandLine.arguments.indices.contains(index + 1)
                ? CommandLine.arguments[index + 1] : "widget-shots"
            MainActor.assumeIsolated { WidgetRenderHarness.run(outputDirectory: outDir) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-popover") {
            let outDir = CommandLine.arguments.indices.contains(index + 1)
                ? CommandLine.arguments[index + 1] : "popover-shots"
            MainActor.assumeIsolated { PopoverRenderHarness.run(outputDirectory: outDir) }
            return
        }
        if CommandLine.arguments.contains("--bench-ui") {
            // Offscreen perf bench: timings, frame-by-frame probes, and (with -DHEADROOM_BENCH)
            // view-body counts for the popover and Settings.
            MainActor.assumeIsolated { UIBenchHarness.run() }
            return
        }
        // `--demo <scenario>` (demo mode, Jul 2026): reject an unrecognized scenario before the
        // menu bar launches, mirroring the probe/render diagnostics above — a bare `--demo`
        // (single-account screenshot fixtures) still launches normally.
        if case .invalid(let token) = DemoFixture.scenarioRequest() {
            let valid = DemoFixture.MultiAccountScenario.allCases.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(Data("Unknown --demo scenario '\(token)'. Valid scenarios: \(valid)\n".utf8))
            exit(1)
        }
        if DemoFixture.isEnabled,
           let index = CommandLine.arguments.firstIndex(of: "--meter-style"),
           (!CommandLine.arguments.indices.contains(index + 1)
               || MeterStyle(launchToken: CommandLine.arguments[index + 1]) == nil) {
            FileHandle.standardError.write(Data(
                "Invalid --meter-style. Expected <format>.<shape>.<fill>, for example micro.chip.event.\n".utf8
            ))
            exit(1)
        }
        // `--account-title-ink <neutral|brand>`: the visual-review seam Brand had no path to.
        // The demo prefs suite cannot be preset by hand and the `MenuBarExtra` popover is not
        // an accessibility window, so the ink was accepted on code and tests alone (round-3
        // residual). Same validation shape as `--meter-style` above.
        if DemoFixture.isEnabled,
           let index = CommandLine.arguments.firstIndex(of: "--account-title-ink"),
           (!CommandLine.arguments.indices.contains(index + 1)
               || AccountTitleInk(rawValue: CommandLine.arguments[index + 1]) == nil) {
            let valid = AccountTitleInk.allCases.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(Data(
                "Invalid --account-title-ink. Expected one of: \(valid).\n".utf8
            ))
            exit(1)
        }
        if !DemoFixture.isEnabled, let running = SingleInstance.otherRunningCopy() {
            let path = running.bundleURL?.path ?? "another location"
            FileHandle.standardError.write(Data(
                "Headroom is already running (pid \(running.processIdentifier), \(path)). Quit it first.\n".utf8
            ))
            exit(0)
        }
        HeadroomApp.main()
    }

    private static func runClaudeProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            // `--claude-config <dir>`: probe an alternate account home (multi-account
            // diagnostic) — exercises the same CLAUDE_CONFIG_DIR override the extra
            // accounts use in production.
            var overrides: [String: String] = [:]
            let accountCategory: ClaudeCapabilityDiagnosticAccount
            if let flagIndex = CommandLine.arguments.firstIndex(of: "--claude-config"),
               CommandLine.arguments.indices.contains(flagIndex + 1) {
                overrides["CLAUDE_CONFIG_DIR"] = CommandLine.arguments[flagIndex + 1]
                accountCategory = .extra
            } else {
                accountCategory = .builtIn
            }
            let location = await AppComposition.claudeExecutableLocator.locate()
            let versionBand = if let path = location.path {
                await ClaudeUsageCLIProbe.versionBand(
                    executablePath: path,
                    environmentOverrides: overrides
                )
            } else {
                ClaudeCLIVersionBand.unknown
            }
            let result = await ClaudeUsageCLIProbe(
                locator: AppComposition.claudeExecutableLocator,
                workingDirectory: claudeWorkingDirectory(),
                environmentOverrides: overrides
            ).capturePanel()
            let events = await AppComposition.claudeExecutableLocator.recentDiagnosticEvents()
            ClaudeCapabilityDiagnostic.lines(
                account: accountCategory,
                versionBand: versionBand,
                outcome: diagnosticOutcome(for: result),
                events: events,
                signOutEvents: AppComposition.signOutRecord.events
            ).forEach { print($0) }

            switch result {
            case .cliNotFound:
                print("RESULT: CLI not found")
            case .cliInconclusive:
                print("RESULT: CLI discovery inconclusive")
            case .transientCapture:
                print("RESULT: capture failed (no panel text)")
            case .loginRequired:
                print("RESULT: login required (first-run screen — no account signed into this config home)")
            case .workspaceTrustRequired:
                print("RESULT: workspace trust required")
            case .unknownUI:
                print("RESULT: unrecognized Claude surface (no input sent)")
            case .panel(let text, let planHint):
                let capturedAt = Date()
                let windows = ClaudeUsageParser.parse(text)
                let plan = ClaudeUsageParser.plan(in: text) ?? planHint
                print("RESULT: parsed \(windows.count) window(s) plan=\(plan == nil ? "absent" : "present")")
                for w in windows {
                    let schedule = ClaudeResetNormalizer.schedule(
                        label: w.resetLabel,
                        timeZoneIdentifier: w.resetTimeZoneIdentifier,
                        kind: w.kind,
                        now: capturedAt
                    )
                    print("  • category=\(diagnosticWindowCategory(w.kind))  \(Int(w.percentUsed))% used  \(ResetDiagnostic.line(for: schedule, observedAt: capturedAt, now: capturedAt))")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func diagnosticOutcome(
        for result: ClaudePanelResult
    ) -> ClaudeCapabilityDiagnosticOutcome {
        switch result {
        case .panel: .available
        case .loginRequired: .loginRequired
        case .workspaceTrustRequired: .trustRequired
        case .cliNotFound: .confirmedAbsent
        case .cliInconclusive: .discoveryInconclusive
        case .transientCapture: .captureFailed
        case .unknownUI: .unknownSurface
        }
    }

    private static func diagnosticWindowCategory(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: "five-hour"
        case .weekly: "weekly"
        case .billingPeriod: "billing-period"
        case .other: "other"
        }
    }

    fileprivate static func claudeWorkingDirectory() -> String {
        do {
            return try ClaudeUsageWorkspace.ensureDefaultDirectory().path
        } catch {
            return ClaudeUsageWorkspace.defaultDirectoryURL.path
        }
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
                print("  \(snapshot.codexBankedResetProbeLine)")
                for window in snapshot.windows {
                    print("  • \(window.kind)  \(Int(window.utilization.rounded()))% used  \(ResetDiagnostic.line(for: window.resetSchedule, observedAt: window.observedAt ?? snapshot.capturedAt, now: Date()))  (remaining \(Int(window.percentRemaining.rounded()))%)")
                }
            case .stale(let reason):
                print("RESULT: stale Codex snapshot: \(reason.message)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func runGrokProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            var overrides: [String: String] = [:]
            var authPath: URL?
            if let index = CommandLine.arguments.firstIndex(of: "--grok-home"),
               CommandLine.arguments.indices.contains(index + 1) {
                let home = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
                overrides["GROK_HOME"] = home.path
                authPath = home.appendingPathComponent("auth.json")
                print("account home: isolated")
            } else {
                print("account home: built-in")
            }

            let source = GrokFallbackUsageSource(
                primary: GrokACPUsageSource(environmentOverrides: overrides),
                fallback: GrokHTTPUsageSource(authReader: GrokAuthFileReader(path: authPath))
            )
            let result = await source.fetchUsage()
            switch result {
            case .payload(let data, let transport):
                let snapshot = await GrokProvider(
                    source: CapturedGrokUsageSource(data: data, transport: transport),
                    // Identity from the same isolated auth.json the billing call used —
                    // never the built-in home when --grok-home targets another account.
                    emailSource: GrokCredentialEmailReader(
                        authReader: GrokAuthFileReader(path: authPath)
                    )
                ).fetchSnapshot()
                guard snapshot.freshness == .live else {
                    print("RESULT: Grok payload could not be parsed")
                    semaphore.signal()
                    return
                }
                print("RESULT: live Grok snapshot via \(transport.rawValue), parsed \(snapshot.windows.count) window(s):")
                if let plan = snapshot.planLabel { print("  plan: \(plan)") }
                for window in snapshot.windows {
                    print("  • \(window.kind.shortLabel)  \(Int(window.percentUsed.rounded()))% used  \(ResetDiagnostic.line(for: window.resetSchedule, observedAt: window.observedAt ?? snapshot.capturedAt, now: Date()))")
                }
            case .methodUnavailable:
                print("RESULT: Grok billing method unavailable and fallback was not attempted")
            case .cliNotFound:
                print("RESULT: Grok Build CLI not found")
            case .authAbsent:
                print("RESULT: login required")
            case .authPermissionDenied, .authUnsafePermissions, .authMalformed, .authIOFailure:
                print("RESULT: Grok sign-in file is unavailable")
            case .rejectedAuth:
                print("RESULT: Grok sign-in expired")
            case .failure(let reason):
                print("RESULT: Grok probe failed: \(reason.message)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func runCursorProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        print("cursor-agent CLI: \(CursorUsageCLIProbe.resolveCursorPath() == nil ? "missing" : "available")")
        Task {
            switch await CursorUsageCLIProbe().capturePanel() {
            case .panel(let text):
                guard let parsed = CursorUsageParser.parse(text) else {
                    print("RESULT: Cursor usage panel could not be parsed")
                    semaphore.signal()
                    return
                }
                switch parsed.subscription {
                case .namedPools(let pools):
                    print("RESULT: live Cursor snapshot via official /usage panel")
                    print("  plan: \(parsed.planName)")
                    for pool in pools {
                        print("  • \(pool.label)  \(Int(pool.percentUsed.rounded()))% used  reset-evidence=scheduled")
                    }
                case .includedFallback(let percentUsed):
                    print("RESULT: live Cursor snapshot via official /usage panel")
                    print("  plan: \(parsed.planName)")
                    print("  • Included (compatibility fallback)  \(Int(percentUsed.rounded()))% used  reset-evidence=scheduled")
                case .incomplete:
                    print("RESULT: Cursor subscription table was incomplete")
                }
                print("  on-demand: \(parsed.onDemand.isEnabled ? "enabled" : "disabled")")
            case .loginRequired:
                print("RESULT: login required")
            case .workspaceTrustRequired:
                print("RESULT: Cursor workspace trust required (no input sent)")
            case .mcpApprovalRequired:
                print("RESULT: Cursor MCP server approval required (no input sent)")
            case .cliNotFound:
                print("RESULT: Cursor Agent CLI not found")
            case .unknownUI:
                print("RESULT: unrecognized Cursor Agent surface (no input sent)")
            case .transientCapture:
                print("RESULT: Cursor usage capture failed")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// `--probe-spend <openai|anthropic|xai>` verifies a real key-based API-spend path (U8
    /// acceptance): the three admin/management-key providers share one shape (key → vendor
    /// billing/cost API → typed spend or balance row), so one probe covers all of them. It
    /// prints only the typed, redacted outcome. The key read is off any leak-prone channel:
    /// pass `--key-file <path>` and the key is read from that file (never an argument or env
    /// var, so it can't surface in `ps`/shell history), never echoed, and never persisted.
    /// With no file flag it reads the app-saved Keychain key instead. The API calls are
    /// read-only status fetches. For xAI, compare the printed balance against console.x.ai to
    /// confirm the documented negative-liability sign convention holds against a real response.
    private static func runSpendProbe() {
        let valid = ["openai", "anthropic", "xai"]
        guard let index = CommandLine.arguments.firstIndex(of: "--probe-spend"),
              CommandLine.arguments.indices.contains(index + 1),
              case let token = CommandLine.arguments[index + 1].lowercased(),
              valid.contains(token) else {
            print("Usage: --probe-spend <\(valid.joined(separator: "|"))> [--key-file <path>]")
            return
        }
        let keyProvider: APIKeyProvider
        let label: String
        switch token {
        case "openai": (keyProvider, label) = (.openAI, "OpenAI")
        case "anthropic": (keyProvider, label) = (.anthropic, "Anthropic")
        default: (keyProvider, label) = (.xAI, "xAI")
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let credentials: CredentialStore
            if let fileIndex = CommandLine.arguments.firstIndex(of: "--key-file"),
               CommandLine.arguments.indices.contains(fileIndex + 1) {
                let path = CommandLine.arguments[fileIndex + 1]
                guard let raw = try? String(contentsOfFile: path, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                    print("RESULT: could not read a non-empty key from \(path)")
                    semaphore.signal()
                    return
                }
                print("key source: file (\(raw.count) chars — value not shown)")
                credentials = CredentialStore(apiKeyStore: SingleAPIKeyStore(key: raw, provider: keyProvider))
            } else {
                print("key source: Keychain (app-saved; pass --key-file <path> to test a raw key)")
                credentials = CredentialStore()
            }

            let provider: any APISpendProvider
            switch keyProvider {
            case .openAI: provider = OpenAIAPISpendProvider(credentials: credentials)
            case .anthropic: provider = AnthropicAPISpendProvider(credentials: credentials)
            case .xAI: provider = XAIAPISpendProvider(credentials: credentials)
            }

            let snapshot = await provider.fetchSpend(period: .currentMonth)
            print("provider: \(label)")
            switch snapshot.freshness {
            case .pending:
                print("RESULT: pending")
            case .live:
                let amount = snapshot.amount.map { String(format: "%.2f", $0) } ?? "(none)"
                print("RESULT: live \(label) \(snapshot.kind == .balance ? "balance" : "period spend")")
                print("  label:  \(snapshot.periodLabel)")
                print("  amount: \(amount) \(snapshot.currency ?? "")")
            case .stale(let reason):
                print("RESULT: stale — \(reason.message)")
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
    /// Live mirror of the OS light/dark setting, so `.system` resolves to a concrete scheme
    /// (see `resolvedScheme`). Updated by the interface-theme observer on the menu bar label.
    @State private var systemIsDark: Bool
    @StateObject private var softwareUpdates = SoftwareUpdateController()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let preferences: Preferences

    @MainActor
    init() {
        let preferences = AppComposition.launchPreferences
        let store = AppComposition.store(preferences: preferences)
        if !DemoFixture.isEnabled {
            SetupSessions.configure(
                store: store,
                claudeExecutableLocator: AppComposition.claudeExecutableLocator
            )
        }
        self.preferences = preferences
        _store = State(initialValue: store)
        _appearancePreference = State(initialValue: preferences.appearancePreference)
        _systemIsDark = State(initialValue: SystemAppearance.isDark())
        AppDelegate.startUsageStore = { Task { await store.start() } }
        // SwiftUI's `preferredColorScheme` doesn't reach the `MenuBarExtra(.window)`
        // popover panel or the Settings window's AppKit chrome — both are NSWindows whose
        // appearance follows the process. Drive `NSApp.appearance` so the theme toggle
        // actually repaints every surface (popover + settings), not just SwiftUI content.
        // Applied at `applicationDidFinishLaunching` (below), not here: `NSApp` is still nil
        // during `App.init()`, so touching it now traps.
        AppDelegate.startupAppearance = preferences.appearancePreference.nsAppearance
    }

    /// Concrete color scheme for the SwiftUI content. Deliberately never nil for `.system`:
    /// `preferredColorScheme(nil)` does NOT revert the content scheme after it was pinned to
    /// an explicit value, so a Light→System flip left the cards stuck light even though the
    /// window chrome (driven by `applyToProcess`) went dark. Resolving `.system` to the live
    /// OS scheme sidesteps that; `systemIsDark` is kept current by the interface-theme
    /// observer below so System mode still tracks the OS.
    private var resolvedScheme: ColorScheme {
        switch appearancePreference {
        case .light: .light
        case .dark: .dark
        case .system: systemIsDark ? .dark : .light
        }
    }

    // ML1: `--bench-ui scene` measures `BenchSceneStandIn` (UIBenchHarness.swift), not this body.
    // Mirror a change to what this body reads or builds into the stand-in before measuring it.
    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store) {
                openSettings()
            }
                // PC1 (Kyle, 2026-09-23): on Tahoe the MenuBarExtra window draws its own
                // Liquid Glass background behind the popover at the system's smaller corner
                // radius, so a second corner and rim showed outside the r22 shell. The shell
                // owns the whole surface (`PopoverSurfaceModifier`); the scene's default
                // container background goes. Verified in the bundled app — an unbundled
                // `swift run` gets a different host background, handled in `PopoverView`.
                .containerBackground(.clear, for: .window)
                .preferredColorScheme(resolvedScheme)
                .onChange(of: appearancePreference) { _, newValue in
                    newValue.applyToProcess()
                }
                .task {
                    await store.start()
                    // R2M2: `start()` is idempotent and early-returns once the loop
                    // exists, so this is the only place the popover can freshen on open.
                    // The store decides whether it's worth a poll (oldest live capture
                    // older than one interval) and re-phases the cadence if it is.
                    store.refreshOnPopoverOpen()
                }
        } label: {
            MenuBarStatusLabel(store: store)
                .preferredColorScheme(resolvedScheme)
                .task { await store.start() }
                // Attach to the status item's own window once the scene exists (L1A). The menu
                // bar's appearance is not the process appearance: a light system appearance over
                // a dark wallpaper still gets a dark menu bar, which is exactly the case the old
                // dark pin got right by accident and a system-appearance check would get wrong.
                .task { MenuBarAppearanceMonitor.shared.start() }
                // Track OS light/dark flips so `.system` content re-resolves live (chrome
                // follows the OS on its own via `NSApp.appearance == nil`). Attached to the
                // always-present label, not the on-demand popover, so it never misses a change.
                .onReceive(DistributedNotificationCenter.default().publisher(
                    for: Notification.Name("AppleInterfaceThemeChangedNotification")
                )) { _ in
                    systemIsDark = SystemAppearance.isDark()
                    // An OS theme flip repaints the menu bar backplate; re-read it in case the
                    // status window was replaced and the KVO has nothing to fire from (L1A).
                    MenuBarAppearanceMonitor.shared.refresh()
                }
                // Re-read the OS truth on any theme switch so a Light→System flip resolves
                // against the live setting, not a possibly-stale mirror.
                .onChange(of: appearancePreference) { _, _ in
                    systemIsDark = SystemAppearance.isDark()
                    MenuBarAppearanceMonitor.shared.refresh()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Headroom Settings", id: "settings") {
            SettingsView(
                store: store,
                appearancePreference: $appearancePreference,
                softwareUpdates: softwareUpdates,
                preferences: preferences,
                credentialStore: AppComposition.settingsCredentialStore,
                // U6: the one client per launch; inert under `--demo` and unbundled runs (KTD9).
                notificationClient: AppComposition.notificationClient
            )
            .preferredColorScheme(resolvedScheme)
            // L9A (revising KTD2): the window opens at 800 × 700 and is resizable on
            // both axes down to 720 × 600, with no ceiling. It no longer changes size
            // with the selected pane — every pane body is a `ScrollView`, so the room
            // scrolls inside whatever frame the user left the window at. Only minimizing
            // is withdrawn, since a settings sheet in the Dock is a dead end;
            // `windowResizeBehavior` is deliberately *not* disabled.
            .windowMinimizeBehavior(.disabled)
        }
        // Hidden title bar: the settings window draws its own identity block (icon, name,
        // version) at the top of the sidebar, so traffic lights float on a transparent
        // strip. Avoids Tahoe wrapping a toolbar item in a Liquid Glass container.
        // (Standard modern-macOS utility pattern.)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: SettingsView.windowWidth, height: SettingsView.windowHeight)
        .defaultPosition(.center)
    }

    /// Open (or re-focus) the Settings window. An accessory / `LSUIElement` app is not
    /// activated by `openWindow` alone, so the window would open *behind* the frontmost
    /// app or never take keyboard focus — and clicking the gear a second time would look
    /// like a no-op because the already-open window stays buried. Activating brings it
    /// forward and makes it key on both first open and re-open. (`Done`/⌘W close it via
    /// the view's `dismiss`; this method reopens cleanly afterward.)
    private func openSettings() {
        // SW1: a window that is already showing is only brought forward. One that is arriving
        // is shown at zero opacity, placed, then revealed, so the placement never shows.
        // `openWindow` orders the window front synchronously (measured, macOS 26), but nothing
        // reaches the screen before this runloop turn ends, so zeroing the alpha right after
        // it hides the first frame too. A reused window drops its close animation first so
        // AppKit adds nothing of its own to the order-in. KB1: from ⌘, the reveal is instant;
        // only a click fades.
        let existing = Self.settingsWindow
        let isArriving = existing?.isVisible != true
        let fades = isArriving && !HeadroomMotion.isKeyboardInitiated
        if isArriving, let existing {
            existing.animationBehavior = .none
            existing.alphaValue = 0
        }
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        if isArriving { Self.settingsWindow?.alphaValue = 0 }
        // `.defaultPosition(.center)` (and SwiftUI's persisted frame) can land the window on
        // whichever display it was last on — often the wrong one on a multi-monitor setup.
        // A menu-bar app is invoked from wherever the user is looking, so re-home it onto the
        // screen under the cursor. Deferred a runloop tick so SwiftUI has sized the window to
        // its content; while arriving it is still invisible, so the move never shows.
        DispatchQueue.main.async {
            Self.placeSettingsWindowOnActiveScreen()
            guard isArriving, let window = Self.settingsWindow else { return }
            Self.reveal(window, fading: fades)
        }
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Headroom Settings" }
    }

    /// SW1: the entrance, then AppKit's utility-window fade for whichever way the user closes
    /// it (red button, ⌘W). The behavior only governs order-in and order-out, so setting it on
    /// a window that is already ordered in changes nothing about this entrance.
    private static func reveal(_ window: NSWindow, fading: Bool) {
        window.animationBehavior = .utilityWindow
        guard fading else {
            window.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = HeadroomMotion.windowInDuration
            context.timingFunction = HeadroomMotion.windowCurve
            window.animator().alphaValue = 1
        }
    }

    /// Center the Settings window on the active screen (the one under the cursor). If the
    /// window is already showing on that screen, its current position is respected so a
    /// user's manual placement isn't yanked back to center on every re-open.
    private static func placeSettingsWindowOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let activeScreen, let window = settingsWindow else { return }

        if window.isVisible, activeScreen.frame.intersects(window.frame) { return }

        // Force the layout pass so SwiftUI has applied the Settings content's preferred size
        // before we read it. At open the window is briefly wider than its content, and reading
        // that transient frame centers ~50px off.
        window.layoutIfNeeded()
        let visible = activeScreen.visibleFrame
        let size = window.frame.size
        // Horizontally centered; nudged slightly above the vertical midpoint, matching the
        // weighting AppKit's own `NSWindow.center()` uses.
        let preferred = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + size.height * 0.05
        )
        // The window is fixed-width and only shrinks to 600pt tall, so on a short or narrow
        // screen the centered origin can push the title bar under the menu bar (or the edge
        // off-screen); clamping into `visibleFrame` is what keeps the traffic lights
        // reachable. The 5% upward weighting survives whenever it still fits.
        let origin = NSPoint(
            x: min(max(preferred.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
            y: min(max(preferred.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        )
        window.setFrameOrigin(origin)
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// `nil` on `.system` lets `NSApp` fall back to the OS appearance (and keep tracking
    /// system light/dark changes); the explicit cases pin every window to one appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Apply this theme to the process AND every open window. Setting only
    /// `NSApp.appearance` isn't enough: SwiftUI's `preferredColorScheme` pins each open
    /// window's own `appearance`, and switching to `.system` (nil) does NOT release that
    /// pin. A Light→System flip then leaves the popover/settings windows stuck on the
    /// light appearance even though the OS is dark. Writing `appearance` on each window
    /// (nil for System) clears the pin so they follow the process/OS again.
    @MainActor
    func applyToProcess() {
        NSApp.appearance = nsAppearance
        for window in NSApp.windows {
            window.appearance = nsAppearance
        }
    }
}

/// Two copies of the bundle (the installed app plus a dev build, or a stray copy left in
/// Downloads) share one bundle ID, but LaunchServices treats them as different apps: tapping
/// a reminder launched `/Applications/Headroom.app` while a workspace build was already
/// running (2026-09-30). Both copies then poll every CLI and post the same reminders, so the
/// copy already running keeps the menu bar and a later launch exits. `swift run` has no
/// bundle ID and is never blocked.
enum SingleInstance {
    static func otherRunningCopy() -> NSRunningApplication? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }
    }
}

enum SystemAppearance {
    /// The OS light/dark setting, read from the global preference so it stays correct even
    /// while the app pins `NSApp.appearance` to an explicit theme (a pinned `effectiveAppearance`
    /// would report the override, not the OS). `AppleInterfaceStyle` is "Dark" in dark mode and
    /// absent in light — including under the auto/scheduled setting, which toggles this key.
    @MainActor static func isDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
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
    /// Set from `HeadroomApp.init()`; applied here once `NSApp` exists (`.some(nil)` means
    /// "System" — leave `NSApp.appearance` at its default so it tracks the OS).
    static var startupAppearance: NSAppearance??

    /// KTD10: the presentation delegate must be in place before launch completes, so a
    /// banner posted during the first refresh already presents while Settings is frontmost.
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppComposition.notificationClient.installPresentationDelegate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if case let .some(appearance) = Self.startupAppearance {
            NSApp.appearance = appearance
        }
        Self.startUsageStore?()
    }
}

/// Composition root (R13): the one place concrete providers are wired to the engine.
/// Adding a third provider is a one-line append here plus a card — no engine change.
enum AppComposition {
    private struct SubscriptionProviderRegistration {
        let id: ProviderID
        /// KTD10 (2026-09-19 polling plan): the registry is read before any provider instance
        /// exists, so the capacity that truncates it lives here and must match the provider's.
        let accountCapacity: Int
        let factory: @MainActor (ProviderAccount, CredentialStore, URL) -> any UsageProvider
    }

    private static let cursorUsageSource = CursorUsageCaptureCache(source: CursorUsageCLIProbe())
    static let claudeExecutableLocator = CLIExecutableLocator.claude()

    /// The one UserDefaults domain a launch may read or write. `.standard` in the shipping
    /// app; an isolated suite under `--demo`, because the App shell and the store have to
    /// agree on it. They did not: `HeadroomApp.init` built `Preferences()` on `.standard`
    /// while the store took the demo suite, so a demo run wrote `appearancePreference`,
    /// `settingsPane`, `showMenuBarPercentage`, and `menuBarFillSource` into the user's real
    /// domain, and read its theme from whatever a previous `swift run` had left there
    /// (2026-09-03 / round-3 residual).
    nonisolated(unsafe) static let launchDefaults: UserDefaults = resolveLaunchDefaults()

    /// Preferences over `launchDefaults`. `Preferences` is a value wrapper around the
    /// defaults object, so every call site shares one domain regardless of instance.
    static var launchPreferences: Preferences { Preferences(defaults: launchDefaults) }

    /// KTD14 (2026-09-19 sign-in plan): the sign-out record over that same one domain,
    /// so the running app and `--probe-claude` read and write the same entries. An
    /// unbundled `swift run Headroom` resolves `.standard` to a different domain than
    /// the app bundle, so the record is read from the built app's binary.
    static var signOutRecord: SignOutRecord { SignOutRecord(defaults: launchDefaults) }
    static var bankedResetAcknowledgements: BankedResetAcknowledgements {
        BankedResetAcknowledgements(defaults: launchDefaults)
    }

    /// `arguments` is injected so the demo isolation can be tested from a process that was
    /// not itself launched with `--demo`.
    static func resolveLaunchDefaults(arguments: [String] = CommandLine.arguments) -> UserDefaults {
        let request = DemoFixture.scenarioRequest(arguments: arguments)
        guard request != .notRequested else { return .standard }
        // `--demo <scenario>` gets a fresh per-launch suite (the live multi-account preview
        // must not inherit a previous run); a bare `--demo` keeps the stable screenshot
        // suite the marketing pipeline's repeated captures rely on.
        if case .multiAccount = request {
            let suite = "co.zantos.headroom.demo.multi.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Unable to create isolated multi-account demo preferences")
            }
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }
        guard let defaults = UserDefaults(suiteName: "co.zantos.headroom.demo") else {
            preconditionFailure("Unable to create isolated demo preferences")
        }
        return defaults
    }

    /// Ordered composition registry. Adding a provider extends this table; Settings,
    /// account management, polling, and presentation discover the resulting order from
    /// the store instead of maintaining parallel provider literals.
    @MainActor
    private static var subscriptionProviderRegistry: [SubscriptionProviderRegistration] {
        [
            SubscriptionProviderRegistration(id: .claude, accountCapacity: AccountRegistry.testedEnvelope, factory: makeClaudeProvider),
            SubscriptionProviderRegistration(id: .codex, accountCapacity: AccountRegistry.testedEnvelope, factory: makeCodexProvider),
            SubscriptionProviderRegistration(id: .grok, accountCapacity: AccountRegistry.testedEnvelope, factory: makeGrokProvider),
            // Cursor has no config-home isolation, so it stays single-account (matches `CursorProvider.accountCapacity`).
            SubscriptionProviderRegistration(id: .cursor, accountCapacity: 1, factory: makeCursorProvider),
        ]
    }

    @MainActor
    static func store(preferences: Preferences = launchPreferences) -> UsageStore {
        if DemoFixture.isEnabled {
            // `--demo <scenario>` opts into the isolated multi-account preview; a bare `--demo`
            // keeps the single-account screenshot fixtures the marketing pipeline relies on.
            if case .multiAccount(let scenario) = DemoFixture.scenarioRequest() {
                return demoMultiAccountStore(scenario: scenario)
            }
            return demoStore()
        }
        let credentials = CredentialStore()
        let registry = AccountRegistry()
        return UsageStore(
            providers: providers(credentials: credentials, registry: registry),
            apiSpendProviders: apiSpendProviders(credentials: credentials),
            preferences: preferences,
            accountRegistry: registry,
            providerFactory: { account in provider(for: account, credentials: credentials) },
            continuityCache: UsageContinuityCache(),
            signOutRecord: signOutRecord,
            bankedResetAcknowledgements: bankedResetAcknowledgements,
            notificationCoordinator: NotificationCoordinator(
                poster: notificationClient,
                useItUpLedger: UseItUpLedger(defaults: launchDefaults),
                bankedResetBaseline: BankedResetNotificationBaseline(defaults: launchDefaults)
            ),
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
        let prefs = launchPreferences
        let meterStyle = demoMeterStyle()
        prefs.meterStyle = meterStyle
        prefs.accountTitleInk = demoAccountTitleInk()
        prefs.showMenuBarPercentage = true
        prefs.menuBarFillSource = .both            // show both Claude + Codex pills side by side in the menu bar
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

    /// Live multi-account preview (`--demo <scenario>`, demo mode Jul 2026): the real menu
    /// bar app + popover + Liquid Glass shell, backed entirely by the shared multi-account
    /// fixtures (`DemoFixture.multiFixture`) so the multi-account UI can be posed without a
    /// second real login, and the genuine glass popover can be screenshotted over a desktop
    /// (the render harness forces a solid shell — this mode is the complement).
    ///
    /// Isolation is a hard requirement: both the preferences and the account registry live in
    /// their own per-launch UserDefaults suites (never `.standard`), so nothing here reads or
    /// mutates the user's real settings or account catalog. The providers are fixtures that
    /// return their snapshots instantly (Refresh re-serves them at no cost — no CLI, no
    /// network), and the widget/iCloud exporters are omitted so no App Group or KVS write
    /// happens. The `providerFactory` returns fixtures too, so even "Add account" in Settings
    /// never spawns the claude/codex CLIs.
    @MainActor
    private static func demoMultiAccountStore(scenario: DemoFixture.MultiAccountScenario) -> UsageStore {
        let prefsDefaults = launchDefaults
        let prefs = launchPreferences
        let meterStyle = demoMeterStyle()
        prefs.meterStyle = meterStyle
        prefs.accountTitleInk = demoAccountTitleInk()
        prefs.showMenuBarPercentage = true
        prefs.menuBarFillSource = .both            // show both Claude + Codex pills in the menu bar
        // API spend surfaces are off by default, so enable exactly the ones this scenario
        // wires — derived from the providers rather than a hardcoded Claude/Codex pair, so
        // `spend-states`' xAI balance row is not silently filtered out of the card.
        let spendProviders = demoSpendProviders(for: scenario)
        for provider in spendProviders {
            if let surface = UsageSurface.api(for: provider.id) {
                prefs.setSurfaceEnabled(true, for: surface)
            }
        }
        // widgetsEnabled / syncToIPhoneEnabled deliberately left off (with nil exporters
        // below) so the preview never publishes to the widget App Group or iCloud KVS.

        let fixture = DemoFixture.multiFixture(for: scenario)
        let continuityCache = UsageContinuityCache(defaults: prefsDefaults)
        for (key, snapshot) in fixture.continuitySnapshots {
            continuityCache.save(snapshot, for: key)
        }
        // Enable the subscription surface for every provider present in the scenario. Grok and
        // Cursor default OFF (upgrade-safety), so the four-provider scenario would otherwise
        // render only the Claude/Codex cards even though all four fixtures are wired.
        for providerID in Set(fixture.accounts.map(\.providerID)) {
            if let surface = UsageSurface.subscription(for: providerID) {
                prefs.setSurfaceEnabled(true, for: surface)
            }
        }
        // A live registry + factory so account management renders enabled (the real app always
        // has both), seeded with the fixture accounts — but in its OWN suite, never `.standard`,
        // so seeding can't clobber the user's real account catalog.
        let registry = UserDefaults(suiteName: "co.zantos.headroom.demo.accounts.\(UUID().uuidString)")
            .map { AccountRegistry(defaults: $0) }
        registry?.seed(fixture.accounts)
        // Split assignment (not `registry.map { … }`): a nested `@MainActor` closure inside
        // `Optional.map` trips a Swift 6.3 type-checker crash — mirror the harness's pattern.
        var factory: (@MainActor (ProviderAccount) -> any UsageProvider)?
        if registry != nil {
            factory = { account in
                DemoUsageProvider(
                    id: account.providerID,
                    displayName: account.providerID.displayName,
                    snapshot: .pending(for: account.providerID),
                    accountID: account.id
                )
            }
        }
        return UsageStore(
            providers: fixture.providers,
            apiSpendProviders: spendProviders,
            preferences: prefs,
            accounts: fixture.accounts,
            accountRegistry: registry,
            providerFactory: factory,
            continuityCache: continuityCache,
            bankedResetAcknowledgements: BankedResetAcknowledgements(defaults: prefsDefaults)
        )
    }

    /// The spend rows a live preview scenario poses. Every other scenario keeps the two
    /// `.live` period-spend rows the demo has always shown; `spend-states` (S5A) is the one
    /// that exercises the card's other states, because nothing else in the tree ever renders
    /// a stale spend row or a `.balance` row. Cursor rides along last because it is the only
    /// spend provider with no `addCreditsURL`: its row is what proves the reserved-empty
    /// top-up slot keeps all four amounts on one right edge.
    private static func demoSpendProviders(
        for scenario: DemoFixture.MultiAccountScenario
    ) -> [any APISpendProvider] {
        switch scenario {
        case .spendStates:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpendKeyRejected),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                DemoSpendProvider(id: .grok, displayName: "xAI API", snapshot: DemoFixture.xaiBalanceSpend),
                DemoSpendProvider(id: .cursor, displayName: "Cursor on-demand", snapshot: DemoFixture.cursorOnDemandSpend),
            ]
        // X5: the retained-figure counterpart — a rejected key that still shows its last
        // total (so the column and the glyph-less top-up slot hold) beside a retryable stale
        // row. `spend-states` poses the nil-amount collapse; one row cannot show both.
        case .spendRetained:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpendKeyRejectedRetained),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpendStaleRetained),
                DemoSpendProvider(id: .grok, displayName: "xAI API", snapshot: DemoFixture.xaiBalanceSpend),
                DemoSpendProvider(id: .cursor, displayName: "Cursor on-demand", snapshot: DemoFixture.cursorOnDemandSpend),
            ]
        default:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ]
        }
    }

    /// Demo-only launch override. An absent flag always reseeds the landed default so a
    /// previous demo run cannot change a later capture; Entry rejects malformed tokens.
    static func demoMeterStyle(arguments: [String] = CommandLine.arguments) -> MeterStyle {
        guard let index = arguments.firstIndex(of: "--meter-style"),
              arguments.indices.contains(index + 1),
              let style = MeterStyle(launchToken: arguments[index + 1])
        else { return .default }
        return style
    }

    /// `--widget-style <id>` (widget-styles plan, KTD13): which style Settings › Widgets &
    /// iPhone previews, for the `--render-popover --widgets-only` harness. An absent or
    /// unknown id previews the default style.
    static func demoWidgetStyle(arguments: [String] = CommandLine.arguments) -> WidgetLayoutStyle {
        guard let index = arguments.firstIndex(of: "--widget-style"),
              arguments.indices.contains(index + 1)
        else { return .default }
        return WidgetLayoutStyle(storedValue: arguments[index + 1])
    }

    /// `--account-title-ink <neutral|brand>`, the review seam for `AccountTitleInk.brand`.
    /// Reseeds the landed default when absent for the same reason `demoMeterStyle` does.
    static func demoAccountTitleInk(arguments: [String] = CommandLine.arguments) -> AccountTitleInk {
        guard let index = arguments.firstIndex(of: "--account-title-ink"),
              arguments.indices.contains(index + 1),
              let ink = AccountTitleInk(rawValue: arguments[index + 1])
        else { return .neutral }
        return ink
    }

    /// One provider instance per configured account, in registry order (built-in first).
    @MainActor
    private static func providers(credentials: CredentialStore, registry: AccountRegistry) -> [any UsageProvider] {
        subscriptionProviderRegistry.flatMap { registration in
            registry.accounts(for: registration.id, capacity: registration.accountCapacity)
                .map { provider(for: $0, credentials: credentials) }
        }
    }

    /// The concrete provider for one account. Built-in accounts read the CLI's default
    /// config (`~/.claude` / `~/.codex` / `~/.grok`) exactly as before; extra accounts
    /// route the same paths at their Headroom-owned config home (`CLAUDE_CONFIG_DIR` /
    /// `CODEX_HOME` / `GROK_HOME`) that the user signed into via the official CLI.
    @MainActor
    static func provider(
        for account: ProviderAccount,
        credentials: CredentialStore,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL
    ) -> any UsageProvider {
        guard let registration = subscriptionProviderRegistry.first(where: { $0.id == account.providerID }) else {
            return UnavailableAccountProvider(account: account)
        }
        return registration.factory(account, credentials, builtInClaudeWorkspace)
    }

    @MainActor
    private static func makeCodexProvider(
        account: ProviderAccount,
        credentials: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        guard !account.isBuiltIn else {
            return CodexProvider(credentials: credentials) // reads ~/.codex/auth.json + wham/usage
        }
        let configuration = ProviderAccountConfiguration.make(for: account)
        let reader = CodexAuthFileReader(path: configuration.codexAuthFile)
        return CodexProvider(credentials: CredentialStore(codexReader: reader), accountID: account.id)
    }

    @MainActor
    private static func makeClaudeProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace: URL
    ) -> any UsageProvider {
        let configuration = ProviderAccountConfiguration.make(
            for: account,
            builtInClaudeWorkspace: builtInClaudeWorkspace
        )
        guard let workspace = configuration.claudeWorkspaceDirectory else {
            return UnavailableAccountProvider(account: account)
        }
        // Provider configuration describes the path but deliberately has no file-system
        // side effects. Provision it before the PTY receives it as its working directory.
        guard (try? ClaudeUsageWorkspace.ensureDirectory(at: workspace)) != nil else {
            return UnavailableAccountProvider(account: account)
        }
        guard !account.isBuiltIn else {
            return ClaudeProvider(source: ClaudeUsageCLIProbe(
                locator: claudeExecutableLocator,
                workingDirectory: workspace.path
            ))
        }
        guard let configDirectory = configuration.claudeConfigDirectory else {
            return UnavailableAccountProvider(account: account)
        }
        return ClaudeProvider(
            source: ClaudeUsageCLIProbe(
                locator: claudeExecutableLocator,
                workingDirectory: workspace.path,
                environmentOverrides: ["CLAUDE_CONFIG_DIR": configDirectory.path]
            ),
            accountID: account.id
        )
    }

    @MainActor
    private static func makeGrokProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        let configuration = ProviderAccountConfiguration.make(for: account)
        guard let authFile = configuration.grokAuthFile else {
            return UnavailableAccountProvider(account: account)
        }
        let overrides = configuration.grokHomeDirectory.map { ["GROK_HOME": $0.path] } ?? [:]
        // One reader for this account's `auth.json`: the billing fallback takes the token
        // from it, the email source takes the identity from the same record. No second
        // path resolution.
        let authReader = GrokAuthFileReader(path: authFile)
        return GrokProvider(
            source: GrokFallbackUsageSource(
                primary: GrokACPUsageSource(environmentOverrides: overrides),
                fallback: GrokHTTPUsageSource(authReader: authReader)
            ),
            accountID: account.id,
            emailSource: GrokCredentialEmailReader(authReader: authReader)
        )
    }

    @MainActor
    private static func makeCursorProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        guard account.isBuiltIn else { return UnavailableAccountProvider(account: account) }
        return CursorProvider(source: cursorUsageSource, emailSource: CursorStatusEmailProbe())
    }

    private static func apiSpendProviders(credentials: CredentialStore) -> [any APISpendProvider] {
        [
            AnthropicAPISpendProvider(credentials: credentials),
            OpenAIAPISpendProvider(credentials: credentials),
            XAIAPISpendProvider(credentials: credentials),
            CursorOnDemandSpendProvider(source: cursorUsageSource),
        ]
    }

    /// `HeadroomAppTests` runs inside this app as its XCTest host, so every run launches the
    /// real app: `UsageStore.start()` → `refreshAll` → `exportWidgetSnapshot` reaches for the
    /// App Group container, and macOS answers the first reach with the "would like to access
    /// data from other apps" consent alert. That alert blocks the container call on the main
    /// thread until a human dismisses it, which stalls the whole test run — on every rebuild.
    /// Nothing under test observes the export, so the test host gets an exporter that writes
    /// nothing. The environment is a parameter so the decision is provable without a launch.
    static func usesNoOpWidgetExporter(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    /// The Settings window's key store, one per launch rather than one per scene-body pass.
    /// Demo runs stay off the real Keychain: the unsigned debug binary would otherwise raise
    /// one prompt per API-key provider every time Settings opens.
    static let settingsCredentialStore: CredentialStore = DemoFixture.isEnabled
        ? CredentialStore(apiKeyStore: DemoAPIKeyStore())
        : CredentialStore()

    /// U5: the one notification client per launch. The store's coordinator posts through
    /// it and `SettingsView` reads and requests permission through it (U6).
    @MainActor static let notificationClient: any NotificationClient = makeNotificationClient()

    /// KTD9: every process that must not reach `UNUserNotificationCenter` composes the inert
    /// client — demo runs (their stores are fixtures), the render harness, the XCTest host
    /// (the bundle guard alone passes there, and a real prompt would stall the run, as the
    /// widget exporter's consent alert did), and any unbundled `swift run`.
    static func usesInertNotificationClient(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: NotificationBundleDescriptor = .main
    ) -> Bool {
        arguments.contains("--demo")
            || arguments.contains("--render-popover")
            || arguments.contains("--render-widgets")
            || arguments.contains("--bench-ui")
            || usesNoOpWidgetExporter(environment: environment)
            || !bundle.supportsUserNotifications
    }

    static func makeNotificationClient(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: NotificationBundleDescriptor = .main
    ) -> any NotificationClient {
        guard !usesInertNotificationClient(arguments: arguments, environment: environment, bundle: bundle) else {
            return InertNotificationClient()
        }
        return UserNotificationClient.make(bundle: bundle)
    }

    static func widgetExporter(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any WidgetSnapshotExporting {
        guard !usesNoOpWidgetExporter(environment: environment) else {
            return NoOpWidgetSnapshotExporter()
        }
        return WidgetSnapshotExporter(cache: .appGroup()) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func phoneSyncExporter() -> any WidgetSnapshotExporting {
        iCloudSnapshotPublisher(sync: iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore()))
    }
}

/// The exporter the XCTest host composes in place of the App Group one. See
/// `AppComposition.usesNoOpWidgetExporter`.
struct NoOpWidgetSnapshotExporter: WidgetSnapshotExporting {
    func export(_ envelope: WidgetSnapshotEnvelope) {}
}

private struct UnavailableAccountProvider: UsageProvider {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String

    init(account: ProviderAccount) {
        id = account.providerID
        accountID = account.id
        displayName = account.providerID.raw.capitalized
    }

    func fetchSnapshot() async -> UsageSnapshot {
        .stale(for: id, reason: .transient("This provider is not available in this Headroom build"))
    }
}

private struct CapturedGrokUsageSource: GrokUsageSource {
    let data: Data
    let transport: GrokUsageTransport

    func fetchUsage() async -> GrokUsageSourceResult {
        .payload(data, transport: transport)
    }
}

/// Diagnostic-only key store: serves one in-memory key for one provider so `--probe-xai`
/// can validate a raw management key without persisting it to the Keychain. Save/delete are
/// intentionally unsupported — the probe never writes.
private struct SingleAPIKeyStore: APIKeyStoring {
    let key: String
    let provider: APIKeyProvider

    func readAPIKey(for provider: APIKeyProvider) throws -> String {
        guard provider == self.provider else { throw CredentialError.notLoggedIn }
        return key
    }

    func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        throw CredentialError.notLoggedIn
    }

    func deleteAPIKey(for provider: APIKeyProvider) throws {
        throw CredentialError.notLoggedIn
    }
}
