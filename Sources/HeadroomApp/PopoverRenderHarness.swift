#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import HeadroomCore

/// Hidden diagnostic (`--render-popover <dir>`): renders the real `PopoverView` — demo
/// fixture data, the current OS surface, real appearance — to PNGs for every onboarding state ×
/// appearance, headlessly. Exists so popover design changes can be visually reviewed
/// and diffed against the HTML design mockups without posing the live menu bar
/// (`Scripts/capture-demo-screenshots.sh` still covers the marketing hero shots).
@MainActor
enum PopoverRenderHarness {
    static func run(outputDirectory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let outDir = URL(fileURLWithPath: (outputDirectory as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        Task { @MainActor in
            var failedPaths: [String] = []
            if CommandLine.arguments.contains("--general-only") {
                for dark in [false, true] {
                    for availability in SoftwareUpdatePresentation.Availability.allCases {
                        for compact in [false, true] {
                            let name = "settings-general-\(availability.rawValue)-\(compact ? "compact" : "regular")-\(dark ? "dark" : "light").png"
                            let url = outDir.appendingPathComponent(name)
                            if await renderSettings(
                                pane: .general, percentageMode: .remaining, dark: dark,
                                height: compact ? SettingsView.minimumWindowHeight : nil,
                                width: compact ? SettingsView.minimumWindowWidth : nil,
                                softwareUpdates: RenderSoftwareUpdateController(availability: availability),
                                to: url
                            ) {
                                print("✓ \(url.path)")
                            } else { failedPaths.append(url.path) }
                        }
                    }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--loading-only") {
                do {
                    try await PopoverLoadingRenderHarness.run(to: outDir)
                    exit(0)
                } catch {
                    print("✗ Loading capture checkpoint failed: \(error)")
                    exit(1)
                }
            }
            // Focused, offscreen acceptance for the arranger at the normal and minimum
            // window sizes, including both width treatments and the automatic entry state.
            if CommandLine.arguments.contains("--menu-bar-only") {
                for dark in [false, true] {
                    for showsPercentage in [false, true] {
                        for compactWindow in [false, true] {
                            let name = "settings-menuBar-\(showsPercentage ? "percentages" : "pills")-\(compactWindow ? "compact" : "regular")-\(dark ? "dark" : "light").png"
                            let url = outDir.appendingPathComponent(name)
                            if await renderSettings(
                                pane: .menuBar, percentageMode: .remaining, dark: dark,
                                height: compactWindow ? 632 : nil,
                                width: compactWindow ? 720 : nil,
                                menuBarPercentages: showsPercentage, to: url
                            ) {
                                print("✓ \(url.path)")
                            } else { failedPaths.append(url.path) }
                        }
                    }
                    let url = outDir.appendingPathComponent("settings-menuBar-auto-\(dark ? "dark" : "light").png")
                    if await renderSettings(pane: .menuBar, percentageMode: .remaining, dark: dark, to: url) {
                        print("✓ \(url.path)")
                    } else { failedPaths.append(url.path) }
                    // PS1: the shelf with a switched-on provider and a switched-off one.
                    let shelfURL = outDir.appendingPathComponent("settings-menuBar-shelf-\(dark ? "dark" : "light").png")
                    if await renderSettings(
                        pane: .menuBar, percentageMode: .remaining, dark: dark,
                        menuBarPercentages: true, menuBarShelf: true, to: shelfURL
                    ) {
                        print("✓ \(shelfURL.path)")
                    } else { failedPaths.append(shelfURL.path) }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            // Focused, offscreen acceptance for the widget preview at the default and minimum
            // window widths, plus a wide window where the tiles reach true size.
            if CommandLine.arguments.contains("--widgets-only") {
                for dark in [false, true] {
                    for (suffix, width) in [("regular", nil), ("compact", 720), ("wide", 1100)] as [(String, CGFloat?)] {
                        let url = outDir.appendingPathComponent("settings-widgets-\(suffix)-\(dark ? "dark" : "light").png")
                        if await renderSettings(
                            pane: .widgets, percentageMode: .remaining, dark: dark,
                            height: 900, width: width, to: url
                        ) {
                            print("✓ \(url.path)")
                        } else { failedPaths.append(url.path) }
                    }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            // U8 (popover account layout plan): one popover scenario in both appearances, so a
            // multi-20 or multi-7 check doesn't wait on every other capture.
            if let name = renderScenarioArgument() {
                let scenario = MultiAccountScenario(rawValue: name)
                let state = State(rawValue: name)
                if scenario == nil, state == nil {
                    let valid = State.allCases.map(\.rawValue) + MultiAccountScenario.allCases.map(\.rawValue)
                    FileHandle.standardError.write(Data("✗ Unknown --render-scenario '\(name)'. Valid: \(valid.joined(separator: ", "))\n".utf8))
                    exit(2)
                }
                for dark in [false, true] {
                    let url = outDir.appendingPathComponent("popover-\(name)-\(dark ? "dark" : "light").png")
                    let ok = if let scenario {
                        await renderMulti(scenario: scenario, dark: dark, to: url)
                    } else {
                        await render(state: state ?? .connected, percentageMode: .remaining, dark: dark, to: url)
                    }
                    if ok { print("✓ \(url.path)") } else { failedPaths.append(url.path) }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            for state in State.allCases {
                let modes: [UsagePercentageMode] = state == .connected ? UsagePercentageMode.allCases : [.remaining]
                for mode in modes {
                    for dark in [false, true] {
                        let modeSuffix = mode == .used ? "-used" : ""
                        let name = "popover-\(state.rawValue)\(modeSuffix)-\(dark ? "dark" : "light").png"
                        let url = outDir.appendingPathComponent(name)
                        if await render(state: state, percentageMode: mode, dark: dark, to: url) {
                            print("✓ \(url.path)")
                        } else {
                            failedPaths.append(url.path)
                        }
                    }
                }
            }
            for scenario in MultiAccountScenario.allCases {
                for dark in [false, true] {
                    let name = "popover-\(scenario.rawValue)-\(dark ? "dark" : "light").png"
                    let url = outDir.appendingPathComponent(name)
                    if await renderMulti(scenario: scenario, dark: dark, to: url) {
                        print("✓ \(url.path)")
                    } else {
                        failedPaths.append(url.path)
                    }
                }
            }
            // KTD10: one capture per sidebar pane and appearance at the fixed frame. The
            // Used variant only matters where Percentages lives now (Appearance).
            for pane in SettingsPane.allCases {
                let modes: [UsagePercentageMode] = pane == .appearance ? UsagePercentageMode.allCases : [.remaining]
                for mode in modes {
                    for dark in [false, true] {
                        let modeSuffix = mode == .used ? "-used" : ""
                        let name = "settings-\(pane.rawValue)\(modeSuffix)-\(dark ? "dark" : "light").png"
                        let url = outDir.appendingPathComponent(name)
                        if await renderSettings(pane: pane, percentageMode: mode, dark: dark, to: url) {
                            print("✓ \(url.path)")
                        } else {
                            failedPaths.append(url.path)
                        }
                    }
                }
            }
            // U6: the Notifications pane's other states beside the default capture above —
            // permission denied (R18), and switched on with custom rules (R4–R9), also at
            // the 720pt minimum width so a wrapping rule row shows up.
            let notificationStates: [(suffix: String, state: NotificationsRenderState, width: CGFloat?)] = [
                ("denied", .denied, nil),
                ("custom", .custom, nil),
                ("custom-compact", .custom, SettingsView.minimumWindowWidth),
            ]
            for (suffix, state, width) in notificationStates {
                for dark in [false, true] {
                    let url = outDir.appendingPathComponent("settings-notifications-\(suffix)-\(dark ? "dark" : "light").png")
                    if await renderSettings(
                        pane: .notifications, percentageMode: .remaining, dark: dark,
                        width: width, notifications: state, to: url
                    ) {
                        print("✓ \(url.path)")
                    } else {
                        failedPaths.append(url.path)
                    }
                }
            }
            for dark in [false, true] {
                let name = "settings-accounts-multi-\(dark ? "dark" : "light").png"
                let url = outDir.appendingPathComponent(name)
                if await renderSettings(
                    pane: .accounts,
                    percentageMode: .remaining,
                    dark: dark,
                    multiAccount: true,
                    // Taller than the shipping window so the whole multi-account list lands
                    // in the capture instead of being cropped at `windowHeight`.
                    height: 1500,
                    to: url
                ) {
                    print("✓ \(url.path)")
                } else {
                    failedPaths.append(url.path)
                }
            }
            let heroURL = outDir.appendingPathComponent("hero-popover-dark.png")
            if await renderHero(to: heroURL) {
                print("✓ \(heroURL.path)")
            } else {
                failedPaths.append(heroURL.path)
            }
            for path in failedPaths {
                FileHandle.standardError.write(Data("✗ Failed to render \(path)\n".utf8))
            }
            exit(failedPaths.isEmpty ? 0 : 1)
        }
        app.run()
    }

    /// U6: which Notifications pane state a Settings capture shows. Scripted, never the
    /// real client (KTD9): the default is undecided permission, the first-open state.
    enum NotificationsRenderState {
        case firstOpen
        case denied
        case custom

        var client: ScriptedNotificationClient {
            switch self {
            case .firstOpen: ScriptedNotificationClient(status: .notDetermined)
            case .denied: ScriptedNotificationClient(status: .denied)
            case .custom: ScriptedNotificationClient(status: .authorized)
            }
        }
    }

    /// `--render-scenario <name>`: a `MultiAccountScenario` or onboarding `State` raw value.
    private static func renderScenarioArgument(arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: "--render-scenario"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    enum State: String, CaseIterable {
        case connect, waiting, connected
        case codexConnect, codexReconnect, codexWaiting, codexConnected
        case dualWaiting
    }

    /// Scenario set + fixture builders now live on `DemoFixture` (demo mode, Jul 2026) so the
    /// live `--demo <scenario>` launch mode and this offscreen harness share one source of
    /// truth. These aliases keep the harness call sites (and its byte-identical output) intact.
    typealias MultiAccountScenario = DemoFixture.MultiAccountScenario

    private static func multiFixture(for scenario: MultiAccountScenario) -> DemoFixture.MultiAccountFixture {
        DemoFixture.multiFixture(for: scenario)
    }

    /// The fixture's accounts and providers for a popover capture. `multi-20`'s Claude and
    /// Grok rows simulate a 4s probe for the live duty-cycle gate (R15); a user refresh
    /// drains each lane one probe at a time, so 20 × 4s would keep cards as placeholders
    /// for over a minute. The capture shows the settled envelope instead, built the way
    /// `UIBenchHarness.makeStore` builds its `multi20`.
    private static func popoverPairs(for scenario: MultiAccountScenario) -> [(account: ProviderAccount, provider: any UsageProvider)] {
        guard scenario == .envelope else {
            let fixture = multiFixture(for: scenario)
            return Array(zip(fixture.accounts, fixture.providers))
        }
        return DemoFixture.settledEnvelopePairs()
    }

    /// U8: waits for the refresh `refreshNow()` started to finish and its "Refreshing…" hold
    /// to clear, bounded so a scenario that never settles still captures.
    private static func awaitSettledRefresh(_ store: UsageStore, timeout: Duration = .seconds(20)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while store.lastFullRefreshCompletedAt == nil || store.isRefreshing {
            guard clock.now < deadline else {
                FileHandle.standardError.write(Data("! refresh did not settle within \(timeout); capturing anyway\n".utf8))
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func renderMulti(scenario: MultiAccountScenario, dark: Bool, to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        ClaudeSetupSession.openedSetupAt = nil
        CodexSetupSession.openedSetupAt = nil
        let pairs = popoverPairs(for: scenario)
        let preferences = renderPreferences(mode: .remaining)
        let store = UsageStore(
            providers: pairs.map(\.provider),
            apiSpendProviders: [],
            preferences: preferences,
            accounts: pairs.map(\.account)
        )
        store.refreshNow()
        try? await Task.sleep(for: .milliseconds(700))
        await awaitSettledRefresh(store)
        return await snapshotPopover(store: store, dark: dark, to: url)
    }

    private static func render(state: State, percentageMode: UsagePercentageMode, dark: Bool, to url: URL) async -> Bool {
        // App-wide appearance, not just window-level: SwiftUI's semantic styles
        // (.primary/.secondary/.quaternary) resolve against the app's effective
        // appearance in this offscreen path, so a window-only override leaves
        // light-mode ink in dark renders.
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Provider-scoped flags drive each Connect → Waiting → Connected flow.
        ClaudeSetupSession.openedSetupAt = switch state {
        case .waiting, .connected, .dualWaiting: Date()
        default: nil
        }
        CodexSetupSession.openedSetupAt = switch state {
        case .codexWaiting, .codexConnected, .dualWaiting: Date()
        default: nil
        }

        let preferences = renderPreferences(mode: percentageMode)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: claudeSnapshot(for: state)),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: codexSnapshot(for: state)),
            ],
            apiSpendProviders: spendProviders(for: state),
            preferences: preferences
        )
        store.refreshNow()
        // Demo providers resolve instantly; give the cycle + entrance animation a beat.
        try? await Task.sleep(for: .milliseconds(700))
        return await snapshotPopover(store: store, dark: dark, to: url)
    }

    /// Shared popover capture: hosts the real `PopoverView` over the desk backdrop,
    /// sizes to fit, and snapshots the compositor output.
    ///
    /// U8 (popover account layout plan): the canvas is the popover's own width plus the 24pt
    /// desk margin — 432 for one column, 798 for two — not a fixed 432. The column plan is
    /// made from measured heights and lands a main-queue turn after the first layout, so the
    /// window is refitted once it has.
    private static func snapshotPopover(store: UsageStore, dark: Bool, to url: URL) async -> Bool {
        let root = PopoverView(store: store, onOpenSettings: {})
            .padding(24)
            .background {
                // Desk backdrop so the system surface has something to sample (mirrors the mockup).
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.137, green: 0.137, blue: 0.169), Color(red: 0.078, green: 0.078, blue: 0.102)]
                        : [Color(red: 0.843, green: 0.827, blue: 0.800), Color(red: 0.725, green: 0.702, blue: 0.663)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // Direct environment override (not the scene-level `preferredColorScheme`
            // preference) so semantic styles resolve for the right scheme in this
            // offscreen hosting context.
            .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 432, height: 10)
        hosting.frame = NSRect(origin: .zero, size: canvasSize(hosting.fittingSize))

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.isOpaque = true
        // Kyle (2026-09-10): the harness must never show on screen. A borderless window at
        // the origin flashed in the bottom-left corner of the desktop on every render.
        // Parking it off-screen is not an option — `screencapture -l` returns a fully
        // transparent image for a window outside every display — so it stays on screen but
        // *below the wallpaper*: the window server composites and captures it, nobody sees
        // it, and Mission Control / Spaces leave it alone.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.orderFrontRegardless()
        window.displayIfNeeded()
        await settle(hosting, in: window)
        if refit(hosting, in: window) { await settle(hosting, in: window) }
        // Let the staged meter arrival (M9A beat, then `arrivalSpring`) land before
        // snapshotting, or numerals are caught mid-roll. AR1 lengthened both; 650ms covers the
        // critically damped spring's visible settle.
        try? await Task.sleep(for: HeadroomMotion.arrivalDelay + .milliseconds(650))
        if refit(hosting, in: window) { await settle(hosting, in: window) }

        // Capture the compositor's actual output (correct dynamic-color resolution and
        // the real OS-selected surface) via `screencapture -l`. The offscreen `cacheDisplay` path
        // resolves semantic text colors against the wrong appearance, so it's only the
        // fallback when screen capture is unavailable (no Screen Recording permission).
        let captured = capture(window: window, to: url)
        window.orderOut(nil)
        return captured
    }

    /// The capture canvas for a fitted popover: its own width, and at least 200pt tall as before.
    private static func canvasSize(_ fitting: NSSize) -> NSSize {
        NSSize(width: max(fitting.width, 1), height: max(fitting.height, 200))
    }

    /// A few main-queue turns, laid out and drawn each time, so height reports and the column
    /// replan they complete (`PopoverPlanModel`, next main turn) can land.
    private static func settle(_ hosting: NSView, in window: NSWindow, turns: Int = 12) async {
        for _ in 0..<turns {
            try? await Task.sleep(for: .milliseconds(10))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
    }

    /// Resizes window and hosting view to the popover's current fitting size, as
    /// `MenuBarExtra` grows its window when the shell widens to two columns. False when the
    /// size already matched.
    private static func refit(_ hosting: NSView, in window: NSWindow) -> Bool {
        let size = canvasSize(hosting.fittingSize)
        guard size != hosting.frame.size else { return false }
        window.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return true
    }

    /// Marketing hero for headroom.zantos.co (U4): the connected, dark popover with the
    /// API Spend section, rendered via `ImageRenderer` at 3× with a transparent
    /// background (rounded corners live in the PNG alpha) — no Screen Recording
    /// permission needed, unlike the compositor `screencapture` path above. Forces the
    /// solid surface branch (reduce-transparency), because `ImageRenderer` can't
    /// rasterize the live Liquid Glass material; the resulting flat shell + tiles match
    /// the design artboard (OQ1 resolved to the solid shell — see the plan).
    @MainActor
    private static func renderHero(to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Steady connected state: clear any setup-session flags the diagnostic render loop
        // left set, so the transient "✓ Connected" payoff chip doesn't appear (the design
        // artboard shows plain provider headers).
        ClaudeSetupSession.openedSetupAt = nil
        CodexSetupSession.openedSetupAt = nil
        let preferences = renderPreferences(mode: .remaining)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            apiSpendProviders: [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ],
            preferences: preferences
        )
        store.refreshNow()
        try? await Task.sleep(for: .milliseconds(400))

        let root = PopoverView(
            store: store,
            onOpenSettings: {},
            forceSolidSurface: true,
            // Must fit the whole locked scenario: Claude (3 windows) + Codex (2 windows)
            // + both API Spend rows. At 410 the second spend row clipped under the footer
            // once Codex's restored 5-hour window pushed the stack down.
            // Sized to the locked scenario: Claude (3 windows) + Codex (2 windows) + both
            // API Spend rows. 410 clipped the second spend row once Codex's 5-hour window
            // was restored, and 444 left it fading under the scroll mask. 482 reproduces
            // the approved v3 geometry exactly (384x609pt). Retune if the scenario changes.
            forcedCardsHeight: 482
        )
            .environment(\.colorScheme, .dark)
            .focusEffectDisabled()
            // The popover's `WindowAccessor` background NSView renders as the system accent
            // under ImageRenderer, filling the rounded-corner cutouts with an opaque fringe.
            // Clip the whole export to the surface shape so those cutouts stay transparent.
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        // Host the view for one layout cycle. `ImageRenderer` does not mount ScrollView
        // content, so even a fixed height can produce a shell with no cards. A transparent
        // hosting view exercises the same mounted layout path as the 32 review captures
        // while retaining a permission-free bitmap export.
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 384, height: 760)
        let fitting = hosting.fittingSize
        hosting.frame.size.height = max(fitting.height, 200)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = hosting.appearance
        window.contentView = hosting
        // Kyle (2026-09-10): the harness must never show on screen. A borderless window at
        // the origin flashed in the bottom-left corner of the desktop on every render.
        // Parking it off-screen is not an option — `screencapture -l` returns a fully
        // transparent image for a window outside every display — so it stays on screen but
        // *below the wallpaper*: the window server composites and captures it, nobody sees
        // it, and Mission Control / Spaces leave it alone.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        let pngData = representation.representation(using: .png, properties: [:])
        window.orderOut(nil)
        guard let data = pngData, data.count > 10_000 else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func captureWindow(number: Int, to url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-o", "-x", "-l", String(number), url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0,
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > 10_000 else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    /// One capture per sidebar pane, demo store, at the shipping
    /// `SettingsView.windowWidth` × `SettingsView.windowHeight` — verifies the
    /// shared type hierarchy (15pt tile heads / 13pt controls / 11pt fine print) and the
    /// all-tiles material system across both windows. `height` overrides the frame for the
    /// multi-account capture, which needs a taller canvas so the full account list is
    /// visible instead of cropped at the pane height.
    private static func renderSettings(
        pane: SettingsPane,
        percentageMode: UsagePercentageMode,
        dark: Bool,
        multiAccount: Bool = false,
        height heightOverride: CGFloat? = nil,
        width widthOverride: CGFloat? = nil,
        menuBarPercentages: Bool? = nil,
        menuBarShelf: Bool = false,
        notifications: NotificationsRenderState = .firstOpen,
        softwareUpdates: SoftwareUpdateControlling = DisabledSoftwareUpdateController(),
        to url: URL
    ) async -> Bool {
        // L9A retired the per-pane window heights; the harness captures every pane at
        // the shipping default frame unless a caller asks for a taller canvas.
        let height = heightOverride ?? SettingsView.windowHeight
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let preferences = renderPreferences(mode: percentageMode)
        // The window opens on the persisted pane (R4), so selecting it here is how the
        // harness chooses which detail column to capture without a view-side hook.
        preferences.settingsPane = pane
        if pane == .menuBar {
            preferences.setSurfaceEnabled(true, for: .grokSubscription)
            preferences.setSurfaceEnabled(true, for: .cursorSubscription)
            if let menuBarPercentages {
                preferences.showMenuBarPercentage = menuBarPercentages
                preferences.menuBarFillSource = .providers([.claude, .codex, .grok, .cursor])
            }
            if menuBarShelf {
                preferences.menuBarFillSource = .providers([.claude, .codex])
                preferences.setSurfaceEnabled(false, for: .grokSubscription)
            }
        }
        if notifications == .custom {
            // The mockup's "Customised" state: both switches on, three rules, 5-hour ticked.
            preferences.useItUpRemindersEnabled = true
            preferences.bankedResetNotificationsEnabled = true
            preferences.reminderRules = [
                ReminderRule(amount: 2, unit: .days, threshold: 70),
                ReminderRule(amount: 1, unit: .days, threshold: 50),
                // 100, not the mockup's 15, so the widest threshold proves the field fits it.
                ReminderRule(amount: 3, unit: .hours, threshold: 100),
            ]
            preferences.reminderScope = [.weekly, .billingPeriod, .fiveHour]
        }
        let store: UsageStore
        if multiAccount {
            let fixture = multiFixture(for: .multiMixed)
            // A live registry + factory so account management renders enabled (the real
            // app always has both); seeded with the fixture accounts. The registry MUST
            // live in its own suite — seeding .standard would clobber the user's real
            // account catalog (code-review finding) — so a nil suite skips seeding.
            let registry = UserDefaults(suiteName: "co.zantos.headroom.render.accounts.\(UUID().uuidString)")
                .map { AccountRegistry(defaults: $0) }
            registry?.seed(fixture.accounts)
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
            store = UsageStore(
                providers: fixture.providers,
                apiSpendProviders: [
                    DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                    DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                ],
                preferences: preferences,
                accounts: fixture.accounts,
                accountRegistry: registry,
                providerFactory: factory
            )
            store.refreshNow()
            try? await Task.sleep(for: .milliseconds(300))
        } else {
            store = UsageStore(
                providers: [
                    DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                    DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
                ] + (pane == .menuBar ? [
                    DemoUsageProvider(id: .grok, displayName: "Grok", snapshot: DemoFixture.grokSnapshot),
                    DemoUsageProvider(id: .cursor, displayName: "Cursor", snapshot: DemoFixture.cursorSnapshot),
                ] : []),
                apiSpendProviders: [
                    DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                    DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                ],
                preferences: preferences
            )
        }
        if pane == .menuBar { await store.refreshAll() }
        let width = widthOverride ?? SettingsView.windowWidth
        let root = SettingsView(
            store: store,
            appearancePreference: .constant(dark ? .dark : .light),
            softwareUpdates: softwareUpdates,
            preferences: preferences,
            // The unsigned debug binary's Keychain reads raise a SecurityAgent prompt that
            // blocks the whole run; the diagnostic never needs real keys.
            credentialStore: CredentialStore(apiKeyStore: DemoAPIKeyStore()),
            notificationClient: notifications.client,
            frameHeightOverride: height
        )
            .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        // Kyle (2026-09-10): the harness must never show on screen. A borderless window at
        // the origin flashed in the bottom-left corner of the desktop on every render.
        // Parking it off-screen is not an option — `screencapture -l` returns a fully
        // transparent image for a window outside every display — so it stays on screen but
        // *below the wallpaper*: the window server composites and captures it, nobody sees
        // it, and Mission Control / Spaces leave it alone.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        // The focused acceptance run must fail if WindowServer capture is unavailable;
        // cacheDisplay can save a nonempty but cropped/incorrect Settings bitmap.
        let isFocusedAcceptance = CommandLine.arguments.contains("--menu-bar-only")
            || CommandLine.arguments.contains("--widgets-only")
        let captured = isFocusedAcceptance
            ? captureWindow(number: window.windowNumber, to: url)
            : capture(window: window, to: url)
        window.orderOut(nil)
        return captured
    }

    private static func capture(window: NSWindow, to url: URL) -> Bool {
        if captureWindow(number: window.windowNumber, to: url) { return true }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return false }
        (window.appearance ?? NSAppearance(named: .aqua))?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]), data.count > 10_000 else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func renderPreferences(mode: UsagePercentageMode) -> Preferences {
        let suite = "co.zantos.headroom.render.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Unable to create isolated render preferences")
        }
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        preferences.usagePercentageMode = mode
        // Diagnostic seam: `--meter-style <format.shape.fill>` renders the Settings swatches and
        // the specimen in that style (the demo parser rejects malformed tokens → default).
        preferences.meterStyle = AppComposition.demoMeterStyle()
        // Same seam for `AccountTitleInk.brand`, which otherwise has no capture path.
        preferences.accountTitleInk = AppComposition.demoAccountTitleInk()
        // And for `--account-layout <standard|compact>` (popover account layout plan, U8).
        preferences.accountLayout = AppComposition.demoAccountLayout()
        // API spend surfaces are off by default (`isSurfaceEnabled` → `isSubscription`),
        // so the store's `apiSpendProviderOrder` is empty and the section renders nothing.
        // Enable both so the connected hero shows the API Spend section — wiring the
        // providers alone is not sufficient (mirrors AppComposition.demoStore()).
        preferences.setSurfaceEnabled(true, for: .anthropicAPI)
        preferences.setSurfaceEnabled(true, for: .openAIAPI)
        return preferences
    }

    /// Demo API-spend providers for a popover render. Only the connected hero carries
    /// spend — the setup/waiting states have no configured keys, so showing dollar
    /// totals there would be misleading. The surfaces themselves are enabled in
    /// `renderPreferences`.
    private static func spendProviders(for state: State) -> [any APISpendProvider] {
        guard state == .connected else { return [] }
        return [
            DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
            DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
        ]
    }

    private static func claudeSnapshot(for state: State) -> UsageSnapshot {
        switch state {
        case .connect, .waiting, .dualWaiting:
            return UsageSnapshot(
                providerID: .claude,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .stale(.providerSetup(.claudeTrustRequired))
            )
        case .connected, .codexConnect, .codexReconnect, .codexWaiting, .codexConnected:
            return DemoFixture.claudeSnapshot
        }
    }

    private static func codexSnapshot(for state: State) -> UsageSnapshot {
        switch state {
        case .codexConnect:
            return .stale(
                for: .codex,
                reason: .providerSetup(.codexAuthAbsent)
            )
        case .codexReconnect, .codexWaiting, .dualWaiting:
            return UsageSnapshot(
                providerID: .codex,
                windows: DemoFixture.codexSnapshot.windows,
                planLabel: DemoFixture.codexSnapshot.planLabel,
                accountEmail: DemoFixture.codexSnapshot.accountEmail,
                bankedResets: DemoFixture.codexSnapshot.bankedResets,
                capturedAt: DemoFixture.codexSnapshot.capturedAt,
                freshness: .stale(.providerSetup(.codexRejectedAuth))
            )
        case .codexConnected, .connect, .waiting, .connected:
            return DemoFixture.codexSnapshot
        }
    }
}

/// Inert update fixtures for offscreen Settings captures; never starts Sparkle.
@MainActor
private final class RenderSoftwareUpdateController: SoftwareUpdateControlling {
    let canCheckForUpdates = true
    let allowsAutomaticUpdates = true
    let presentation = SoftwareUpdatePresentation()
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = true
    let lastUpdateCheckDate: Date? = Date(timeIntervalSince1970: 1_791_478_920)

    init(availability: SoftwareUpdatePresentation.Availability) {
        presentation.availability = availability
        presentation.canCheckForUpdates = true
    }

    func checkForUpdates() {}
}
