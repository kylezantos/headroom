import SwiftUI
import AppKit
import HeadroomCore

/// Hidden diagnostic (`--render-popover <dir>`): renders the real `PopoverView` — demo
/// fixture data, real glass, real appearance — to PNGs for every onboarding state ×
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
            for state in State.allCases {
                for dark in [false, true] {
                    let name = "popover-\(state.rawValue)-\(dark ? "dark" : "light").png"
                    await render(state: state, dark: dark, to: outDir.appendingPathComponent(name))
                    print("✓ \(outDir.appendingPathComponent(name).path)")
                }
            }
            for dark in [false, true] {
                let name = "settings-\(dark ? "dark" : "light").png"
                await renderSettings(dark: dark, to: outDir.appendingPathComponent(name))
                print("✓ \(outDir.appendingPathComponent(name).path)")
            }
            exit(0)
        }
        app.run()
    }

    enum State: String, CaseIterable {
        case connect, waiting, connected
    }

    private static func render(state: State, dark: Bool, to url: URL) async {
        // App-wide appearance, not just window-level: SwiftUI's semantic styles
        // (.primary/.secondary/.quaternary) resolve against the app's effective
        // appearance in this offscreen path, so a window-only override leaves
        // light-mode ink in dark renders.
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Session flag drives the Connect → Waiting → Connected chip flow.
        ClaudeSetupSession.openedSetupAt = (state == .connect) ? nil : Date()

        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: claudeSnapshot(for: state)),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            preferences: Preferences(defaults: UserDefaults(suiteName: "co.zantos.headroom.render") ?? .standard)
        )
        store.refreshNow()
        // Demo providers resolve instantly; give the cycle + entrance animation a beat.
        try? await Task.sleep(for: .milliseconds(700))

        let root = ZStack {
            // Desk backdrop so the glass has something to sample (mirrors the mockup).
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.137, green: 0.137, blue: 0.169), Color(red: 0.078, green: 0.078, blue: 0.102)]
                    : [Color(red: 0.843, green: 0.827, blue: 0.800), Color(red: 0.725, green: 0.702, blue: 0.663)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            PopoverView(store: store, onOpenSettings: {})
                .padding(24)
        }
        .frame(width: 432)
        // Direct environment override (not the scene-level `preferredColorScheme`
        // preference) so semantic styles resolve for the right scheme in this
        // offscreen hosting context.
        .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 432, height: 10)
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: 432, height: max(fitting.height, 200))

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.isOpaque = true
        window.orderFrontRegardless()
        window.displayIfNeeded()
        // Let the popover's one-shot entrance settle (0.22s curve) before snapshotting.
        try? await Task.sleep(for: .milliseconds(600))

        // Capture the compositor's actual output (correct dynamic-color resolution and
        // real Liquid Glass) via `screencapture -l`. The offscreen `cacheDisplay` path
        // resolves semantic text colors against the wrong appearance, so it's only the
        // fallback when screen capture is unavailable (no Screen Recording permission).
        let captured = captureWindow(number: window.windowNumber, to: url)
        if !captured,
           let view = window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            (window.appearance ?? NSAppearance(named: .aqua))?.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: rep)
            }
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
        window.orderOut(nil)
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

    /// Settings window, demo store, fixed 460×760 — verifies the shared type hierarchy
    /// (20pt title / 13pt section heads / 11pt fine print) across both windows.
    private static func renderSettings(dark: Bool, to url: URL) async {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            preferences: Preferences(defaults: UserDefaults(suiteName: "co.zantos.headroom.render") ?? .standard)
        )
        let root = SettingsView(store: store, appearancePreference: .constant(dark ? .dark : .light))
            .frame(width: 460, height: 760)
            .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 760)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        _ = captureWindow(number: window.windowNumber, to: url)
        window.orderOut(nil)
    }

    private static func claudeSnapshot(for state: State) -> UsageSnapshot {
        switch state {
        case .connect, .waiting:
            return UsageSnapshot(
                providerID: .claude,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .stale(.needsReauth(ClaudeUsageWorkspace.trustRequiredMessage))
            )
        case .connected:
            return DemoFixture.claudeSnapshot
        }
    }
}
