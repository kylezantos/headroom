import SwiftUI
import AppKit
import QuartzCore
import HeadroomCore
import os

/// Hidden diagnostic (`--bench-ui`, usage in `UIBenchOptions.usage`): hosts the real
/// `PopoverView` and `SettingsView` offscreen and measures what a still render cannot show —
/// main-thread CPU per open, scroll step, pane switch and store change, frame by frame after
/// an open, and (in `-DHEADROOM_BENCH` builds) how many view bodies each one re-ran. The recipe
/// and how to read the numbers are in
/// `docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md`.
///
/// Windows are parked below the wallpaper the way `PopoverRenderHarness` parks them: never
/// key, the app never activated, nothing on screen. Fixtures come from `DemoFixture`, keys from
/// in-memory stores (never the Keychain), and every run gets throwaway defaults suites that are
/// deleted, plist included, before exit.
@MainActor
enum UIBenchHarness {
    private static let clock = ContinuousClock()
    /// `.pointsOfInterest` is the category the Time Profiler template's Points of Interest
    /// instrument records, so a trace can be sliced per scenario (`Scripts/bench-trace-summary.py`).
    private static let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "co.zantos.headroom.bench", category: .pointsOfInterest)
    )
    private static let suitePrefix = "co.zantos.headroom.bench."
    private static let notificationClient = ScriptedNotificationClient(status: .notDetermined)
    private static var createdSuites: [String] = []
    private static var report: UIBenchReport?
    private static var framePassesDone = 0

    // MARK: - Entry

    static func run() {
        let options: UIBenchOptions
        do {
            options = try UIBenchOptions.parse(CommandLine.arguments)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n\(UIBenchOptions.usage)\n".utf8))
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        installCleanupOnSignals()

        Task { @MainActor in
            BenchCounters.enabled = true
            report = UIBenchReport(
                section: options.section.rawValue,
                arguments: Array(CommandLine.arguments.dropFirst()),
                bodyCountsAvailable: BenchCounters.isCompiledIn,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                startedAt: ISO8601DateFormatter().string(from: Date())
            )
            let runs = [.counts, .scene].contains(options.section) ? "" : " runs=\(options.resolvedRuns)"
            say("# bench-ui \(options.section.rawValue) scenario=\(options.resolvedScenario.rawValue)\(runs) pid=\(getpid())")
            say("# macOS \(ProcessInfo.processInfo.operatingSystemVersionString), scale \(NSScreen.main?.backingScaleFactor ?? 0)")
            if !BenchCounters.isCompiledIn {
                say("# body counts unavailable — build with -DHEADROOM_BENCH (swift build -c release -Xswiftc -DHEADROOM_BENCH)")
            }
            #if DEBUG
            say("# DEBUG build: timings are not comparable with release runs — use swift build -c release")
            #endif
            await runSection(options)
            removeCreatedSuites()
            var exitCode: Int32 = 0
            if let path = options.jsonPath, let report {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                do {
                    try report.encoded().write(to: url, options: .atomic)
                    say("\n# wrote \(url.path)")
                } catch {
                    FileHandle.standardError.write(Data("Could not write \(url.path)\n".utf8))
                    exitCode = 1
                }
            }
            exit(exitCode)
        }
        app.run()
    }

    private static func runSection(_ options: UIBenchOptions) async {
        let scenario = options.resolvedScenario
        let runs = options.resolvedRuns
        switch options.section {
        case .popover:
            await benchPopover(scenario: scenario, runs: runs)
        case .scroll:
            await benchScroll(scenario: scenario, sweeps: runs)
        case .settings:
            for pane in options.resolvedPanes {
                await benchSettings(pane: pane, scenario: scenario, runs: runs)
            }
        case .switch:
            await benchSwitch(scenario: scenario, passes: runs, animated: options.animatedSwitches)
        case .counts:
            await benchCounts(scenario: scenario)
        case .scene:
            await benchScene(scenario: scenario)
        case .all:
            for popoverScenario in [UIBenchOptions.Scenario.single, .multi5, .multi20] {
                await benchPopover(scenario: popoverScenario, runs: runs)
            }
            await benchScroll(scenario: .multi20, sweeps: 1)
            for pane in SettingsPane.allCases {
                await benchSettings(pane: pane, scenario: .multi5, runs: runs)
            }
            await benchSwitch(scenario: .multi5, passes: 1, animated: options.animatedSwitches)
            await benchSwitch(scenario: .multi20, passes: 1, animated: false)
            await benchCounts(scenario: .multi5)
            await benchScene(scenario: .multi20)
        }
    }

    // MARK: - Output

    private static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    private static func record(_ result: UIBenchResult) {
        report?.results.append(result)
    }

    private static func f(_ value: Double) -> String { String(format: "%.2f", value) }

    private static func sortedCounts(_ counts: [String: Int]) -> String {
        counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static func compressed(_ sequence: [String]) -> String {
        var out: [String] = []
        var last: String?
        var run = 0
        for item in sequence {
            if item == last { run += 1; continue }
            if let last { out.append(run > 1 ? "\(last)×\(run)" : last) }
            last = item
            run = 1
        }
        if let last { out.append(run > 1 ? "\(last)×\(run)" : last) }
        return out.joined(separator: " → ")
    }

    /// Nil without `HEADROOM_BENCH`, so the JSON says "not measured" rather than "zero".
    private static func bodies(_ phases: [String: [String: Int]]) -> [String: UIBenchBodyCount]? {
        guard BenchCounters.isCompiledIn else { return nil }
        return phases.mapValues(UIBenchBodyCount.init)
    }

    // MARK: - Timing and hosting

    private static func ms(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }

    /// CPU time of the main thread only: wall time includes sleeps, scheduling and other
    /// processes, which is why the audit compared CPU rather than wall clock.
    private static func cpuNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }
    private static func cpuMs(since start: UInt64) -> Double { Double(cpuNow() &- start) / 1e6 }

    /// One hosted root in a parked window.
    @MainActor
    private struct Host {
        let hosting: NSView
        let window: NSWindow

        var isDirty: Bool { hosting.needsLayout || window.viewsNeedDisplay || hosting.needsDisplay }

        func renderPass() {
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
        }

        /// A 60Hz frame that does work only when something is dirty, the way AppKit's display
        /// cycle treats a visible window. The parked window is occluded, so nothing else drives
        /// it; walking a clean multi-20 tree every frame would add ~4ms of harness-only cost.
        func framePass() {
            if isDirty {
                UIBenchHarness.framePassesDone += 1
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
            CATransaction.flush()
        }

        /// Runloop turns (1ms sleeps, so SwiftUI's and Core Animation's observers fire) until a
        /// turn is quiet and `until` holds. Quiet means no view bodies ran; without the counter
        /// it falls back to "nothing was dirty when the turn began".
        func settle(minTurns: Int = 1, maxTurns: Int = 40, until: () -> Bool = { true }) async -> Int {
            var turns = 0
            while turns < maxTurns {
                let bodiesBefore = BenchCounters.total
                try? await Task.sleep(for: .milliseconds(1))
                let wasDirty = isDirty
                renderPass()
                turns += 1
                let quiet = BenchCounters.isCompiledIn ? BenchCounters.total == bodiesBefore : !wasDirty
                if turns >= minTurns, quiet, until() { break }
            }
            return turns
        }

        func teardown() {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
    }

    private static func makeWindow(_ rect: NSRect, titled: Bool) -> NSWindow {
        let style: NSWindow.StyleMask = titled
            ? [.titled, .closable, .resizable, .fullSizeContentView]
            : [.borderless]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        if titled {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        } else {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        // PopoverRenderHarness's parking: on screen for the window server, below the
        // wallpaper so nobody sees it. Never key, and the app is never activated.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        return window
    }

    /// Hosts `root` at a fixed size (Settings, scene stand-in) and draws once.
    private static func makeHost(_ root: some View, size: NSSize, titled: Bool) -> Host {
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = makeWindow(hosting.frame, titled: titled)
        window.contentView = hosting
        window.orderFrontRegardless()
        let host = Host(hosting: hosting, window: window)
        host.renderPass()
        return host
    }

    /// Hosts the popover at its fitted size, resizing once if the first layout changes it.
    /// Also returns the fitted height before and after that first layout.
    private static func hostPopover(_ store: UsageStore) -> (Host, before: CGFloat, after: CGFloat) {
        let hosting = NSHostingView(rootView: popoverRoot(store))
        let fit = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: max(fit.width, 1), height: max(fit.height, 1)))
        let window = makeWindow(hosting.frame, titled: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        let host = Host(hosting: hosting, window: window)
        host.renderPass()
        let settled = hosting.fittingSize
        if settled != fit {
            window.setContentSize(settled)
            hosting.frame = NSRect(origin: .zero, size: settled)
            host.renderPass()
        }
        return (host, fit.height, settled.height)
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Fixtures

    private static func benchDefaults(_ kind: String) -> UserDefaults {
        let suite = "\(suitePrefix)\(kind)\(UUID().uuidString)"
        createdSuites.append(suite)
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("bench defaults suite") }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// `removePersistentDomain` empties a suite but leaves its plist in ~/Library/Preferences
    /// (eleven were left behind after the audit), so the exact files this run created go too.
    private static func removeCreatedSuites() {
        let preferencesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        for suite in createdSuites where suite.hasPrefix(suitePrefix) {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            CFPreferencesAppSynchronize(suite as CFString)
            flushPreferencesDaemon(suite)
            try? FileManager.default.removeItem(at: preferencesDirectory.appendingPathComponent("\(suite).plist"))
        }
        createdSuites = []
    }

    /// Ctrl-C, `kill`, and the `perl -e 'alarm N'` time limit the docs recommend still remove this
    /// run's own suites (code review, 2026-10-04): without this, an interrupted run left its
    /// plists behind and no later run would clean them up.
    private static var signalSources: [any DispatchSourceSignal] = []

    private static func installCleanupOnSignals() {
        for sig in [SIGINT, SIGTERM, SIGALRM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    removeCreatedSuites()
                    exit(128 + sig)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// cfprefsd writes an emptied domain lazily (about 10s later, or when this process exits),
    /// which re-creates a plist deleted before that write. A read of the domain from another
    /// process makes it write first, so the delete that follows is the last word. Measured
    /// 2026-10-04: 6 of 6 suites left nothing this way; deleting straight away left 6 of 6.
    /// A read-only `defaults read`, run to completion in the foreground.
    private static func flushPreferencesDaemon(_ suite: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", suite]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private static func makeStore(
        _ scenario: UIBenchOptions.Scenario,
        changingClaudePrimary: Bool = false
    ) async -> (UsageStore, Preferences) {
        let preferences = Preferences(defaults: benchDefaults(""))
        preferences.usagePercentageMode = .remaining
        preferences.setSurfaceEnabled(true, for: .anthropicAPI)
        preferences.setSurfaceEnabled(true, for: .openAIAPI)
        var providers: [any UsageProvider]
        var accounts: [ProviderAccount]?
        switch scenario {
        case .single:
            providers = [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ]
        case .multi3, .multi5:
            let fixture = DemoFixture.multiFixture(for: scenario == .multi3 ? .multiThree : .multiFive)
            providers = fixture.providers
            accounts = fixture.accounts
        case .multi20:
            // DemoFixture's `multi-20` account list without its simulated 4s probes, so
            // `refreshAll()` lands every row before timing starts.
            var pairs = DemoFixture.generatedAccounts(provider: .claude, count: 20)
                + DemoFixture.generatedAccounts(provider: .codex, count: 20)
                + DemoFixture.generatedAccounts(provider: .grok, count: 20)
            let cursor = ProviderAccount(id: .primary, providerID: .cursor, label: "Cursor", isBuiltIn: true)
            pairs.append((
                account: cursor,
                provider: DemoUsageProvider(
                    id: .cursor, displayName: ProviderID.cursor.displayName,
                    snapshot: DemoFixture.cursorSnapshot, accountID: .primary
                )
            ))
            providers = pairs.map(\.provider)
            accounts = pairs.map(\.account)
        }
        if changingClaudePrimary,
           let index = providers.firstIndex(where: { $0.id == .claude && $0.accountID == .primary }) {
            providers[index] = BenchChangingProvider(id: .claude, displayName: "Claude")
        }
        for id in Set(providers.map(\.id)) {
            if let surface = UsageSurface.subscription(for: id) {
                preferences.setSurfaceEnabled(true, for: surface)
            }
        }
        var registry: AccountRegistry?
        var factory: (@MainActor (ProviderAccount) -> any UsageProvider)?
        if let accounts {
            registry = AccountRegistry(defaults: benchDefaults("accounts."))
            registry?.seed(accounts)
            factory = { account in
                DemoUsageProvider(
                    id: account.providerID,
                    displayName: account.providerID.displayName,
                    snapshot: .pending(for: account.providerID),
                    accountID: account.id
                )
            }
        }
        let store = UsageStore(
            providers: providers,
            apiSpendProviders: [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ],
            preferences: preferences,
            accounts: accounts,
            accountRegistry: registry,
            providerFactory: factory
        )
        await store.refreshAll()
        // Let any trailing main-actor merges land.
        try? await Task.sleep(for: .milliseconds(50))
        let all = store.providerOrder.flatMap { store.accounts(for: $0) }
        let live = all.filter { store.snapshot(for: $0.key).freshness == .live }.count
        say("# store \(scenario.rawValue): providers \(store.providerOrder.map(\.raw)) accounts \(all.count) live \(live)")
        return (store, preferences)
    }

    private static func popoverRoot(_ store: UsageStore) -> some View {
        PopoverView(store: store, onOpenSettings: {})
            .environment(\.colorScheme, .light)
    }

    private static func settingsRoot(
        _ store: UsageStore,
        _ preferences: Preferences,
        keyStore: any APIKeyStoring = DemoAPIKeyStore()
    ) -> some View {
        SettingsView(
            store: store,
            appearancePreference: .constant(.light),
            preferences: preferences,
            credentialStore: CredentialStore(apiKeyStore: keyStore),
            // Never read the user's real `.claude.json` from the bench.
            duplicateDetector: ClaudeDuplicateLoginDetector(readAccountUUID: { _ in nil }),
            notificationClient: notificationClient
        )
        .environment(\.colorScheme, .light)
    }

    private static func paneStruct(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "GeneralSettingsPane"
        case .appearance: "AppearanceSettingsPane"
        case .menuBar: "MenuBarSettingsPane"
        case .widgets: "WidgetsSettingsPane"
        case .notifications: "NotificationsSettingsPane"
        case .accounts: "AccountsSettingsPane"
        case .apiSpend: "APISpendSettingsPane"
        case .about: "AboutSettingsPane"
        }
    }

    /// True once `pane`'s body has run in the current count, or always without the counter.
    private static func paneBuilt(_ pane: SettingsPane) -> Bool {
        !BenchCounters.isCompiledIn || (BenchCounters.counts[paneStruct(pane)] ?? 0) > 0
    }

    /// The status item renders at launch, so the real app has already paid its first-use costs
    /// (fonts, images, metadata) before anything opens.
    private static func primeMenuBarLabel(_ store: UsageStore) async {
        let primer = makeHost(MenuBarStatusLabel(store: store), size: NSSize(width: 160, height: 22), titled: false)
        _ = await primer.settle(maxTurns: 5)
        primer.teardown()
    }

    /// Selects a Settings pane through the `HEADROOM_BENCH` seam. False when it isn't compiled in.
    private static func requestPane(_ pane: SettingsPane, instant: Bool) -> Bool {
        #if HEADROOM_BENCH
        BenchSettingsSeam.request(pane, instant: instant)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Popover open

    private struct PopoverOpen {
        var construct = 0.0, fit0Ms = 0.0, window = 0.0, layout = 0.0, display = 0.0, flush = 0.0
        var fit1Ms = 0.0, resize = 0.0
        var syncWall = 0.0, syncCpu = 0.0, postOpenCpu = 0.0, totalCpu = 0.0
        var fit0 = 0.0, fit1 = 0.0, fitFinal = 0.0
        var postOpenBodies = 0, rootPassFrames = 0
        var counts: [String: Int] = [:]
    }

    /// One open, modelling an assumed version of what `MenuBarExtra(.window)` does: ask the
    /// content for its size, make the window, lay out, draw, commit, and resize once if the
    /// first layout changed the size. Then 600ms of 60Hz frames, which covers the 350ms M9A
    /// arrival beat and the start of its spring (run 0 only) plus any implicit animation the
    /// open starts.
    private static func measurePopoverOpen(_ store: UsageStore, label: String) async -> PopoverOpen {
        BenchCounters.reset()
        var sample = PopoverOpen()
        let interval = signposter.beginInterval("popover-open", id: signposter.makeSignpostID(), "\(label, privacy: .public)")
        let cpu0 = cpuNow()
        let t0 = clock.now
        let hosting = NSHostingView(rootView: popoverRoot(store))
        let t1 = clock.now
        // Before any window: 124pt here, because `cardsHeight` starts at 0.
        let fit0 = hosting.fittingSize
        let t2 = clock.now
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: max(fit0.width, 1), height: max(fit0.height, 1)))
        let window = makeWindow(hosting.frame, titled: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        let host = Host(hosting: hosting, window: window)
        let t3 = clock.now
        hosting.layoutSubtreeIfNeeded()
        let t4 = clock.now
        window.displayIfNeeded()
        let t5 = clock.now
        CATransaction.flush()
        let t6 = clock.now
        let fit1 = hosting.fittingSize
        let t7 = clock.now
        if fit1 != fit0 {
            window.setContentSize(fit1)
            hosting.frame = NSRect(origin: .zero, size: fit1)
            host.renderPass()
        }
        let t8 = clock.now
        let cpuSync = cpuNow()
        let bodiesBefore = BenchCounters.total
        let postStart = clock.now
        while ms(clock.now - postStart) < 600 {
            let rootBefore = rootPasses()
            try? await Task.sleep(for: .milliseconds(16))
            host.framePass()
            if rootPasses() > rootBefore { sample.rootPassFrames += 1 }
        }
        sample.postOpenCpu = cpuMs(since: cpuSync)
        sample.totalCpu = cpuMs(since: cpu0)
        signposter.endInterval("popover-open", interval)
        sample.construct = ms(t1 - t0)
        sample.fit0Ms = ms(t2 - t1)
        sample.window = ms(t3 - t2)
        sample.layout = ms(t4 - t3)
        sample.display = ms(t5 - t4)
        sample.flush = ms(t6 - t5)
        sample.fit1Ms = ms(t7 - t6)
        sample.resize = ms(t8 - t7)
        sample.syncWall = ms(t8 - t0)
        sample.syncCpu = Double(cpuSync &- cpu0) / 1e6
        sample.postOpenBodies = BenchCounters.total - bodiesBefore
        sample.counts = BenchCounters.counts
        sample.fit0 = fit0.height
        sample.fit1 = fit1.height
        sample.fitFinal = hosting.fittingSize.height
        host.teardown()
        return sample
    }

    private static func rootPasses() -> Int {
        (BenchCounters.counts["PopoverView"] ?? 0) + (BenchCounters.counts["PopoverView.timeline"] ?? 0)
    }

    private static func describe(_ s: PopoverOpen) -> String {
        let bodies = BenchCounters.isCompiledIn
            ? "bodies \(s.postOpenBodies) root-pass frames \(s.rootPassFrames) "
            : ""
        return "construct \(f(s.construct)) fit#0 \(f(s.fit0Ms)) window \(f(s.window)) layout \(f(s.layout)) "
            + "display \(f(s.display)) flush \(f(s.flush)) fit#1 \(f(s.fit1Ms)) resize \(f(s.resize)) "
            + "| sync \(f(s.syncWall)) cpu \(f(s.syncCpu)) | post-open cpu \(f(s.postOpenCpu)) \(bodies)"
            + "| h \(Int(s.fit0))→\(Int(s.fit1))→\(Int(s.fitFinal))"
    }

    private static func benchPopover(scenario: UIBenchOptions.Scenario, runs: Int) async {
        say("\n## popover-open scenario=\(scenario.rawValue)")
        let (store, _) = await makeStore(scenario)
        await primeMenuBarLabel(store)
        var samples: [PopoverOpen] = []
        for run in 0...runs {
            let sample = await measurePopoverOpen(store, label: "\(scenario.rawValue)#\(run)")
            say("  run \(run)\(run == 0 ? " (cold)" : ""): \(describe(sample))")
            samples.append(sample)
            try? await Task.sleep(for: .milliseconds(30))
        }
        let cold = samples[0]
        let warm = Array(samples.dropFirst())
        let title = "popover[\(scenario.rawValue)]"
        say("  \(title) cold: sync \(f(cold.syncWall)) cpu \(f(cold.syncCpu)) post-open cpu \(f(cold.postOpenCpu)) total cpu \(f(cold.totalCpu))")
        // (table label, JSON key, field)
        let phases: [(String, String, KeyPath<PopoverOpen, Double>)] = [
            ("sync wall", "syncWallMs", \.syncWall), ("sync cpu", "syncCpuMs", \.syncCpu),
            ("post-open cpu", "postOpenCpuMs", \.postOpenCpu), ("total cpu", "totalCpuMs", \.totalCpu),
            ("construct", "constructMs", \.construct), ("fit#0", "fit0Ms", \.fit0Ms),
            ("window", "windowMs", \.window), ("layout", "layoutMs", \.layout),
            ("display", "displayMs", \.display), ("flush", "flushMs", \.flush),
            ("fit#1", "fit1Ms", \.fit1Ms), ("resize", "resizeMs", \.resize),
        ]
        for (name, _, path) in phases {
            if let stats = UIBenchStats(warm.map { $0[keyPath: path] }) {
                say("  \(title) warm \(name.padding(toLength: 13, withPad: " ", startingAt: 0)) \(stats.text)")
            }
        }
        if BenchCounters.isCompiledIn {
            say("  \(title) post-open bodies cold=\(cold.postOpenBodies) warm=\(warm.map(\.postOpenBodies))")
            say("  \(title) root-pass frames cold=\(cold.rootPassFrames) warm=\(warm.map(\.rootPassFrames))")
            say("  cold counts: \(sortedCounts(cold.counts))")
            if let first = warm.first { say("  warm counts: \(sortedCounts(first.counts))") }
        }
        var result = UIBenchResult(
            id: "popover-open/\(scenario.rawValue)", kind: "popover-open", scenario: scenario.rawValue
        )
        for (_, key, path) in phases {
            result.metrics[key] = .coldWarm(samples.map { $0[keyPath: path] })
        }
        result.metrics["fittingHeightBeforeLayout"] = .single(cold.fit0)
        result.metrics["fittingHeightAfterLayout"] = .single(cold.fit1)
        result.metrics["fittingHeightFinal"] = .single(cold.fitFinal)
        if BenchCounters.isCompiledIn {
            result.metrics["postOpenBodies"] = .coldWarm(samples.map { Double($0.postOpenBodies) })
            result.metrics["rootPassFrames"] = .coldWarm(samples.map { Double($0.rootPassFrames) })
        }
        result.bodies = bodies(["cold": cold.counts, "warm": warm.first?.counts ?? [:]])
        result.frames = await probePopoverFrames(store)
        record(result)
    }

    /// Untimed open that prints every post-open frame: `fittingSize`, the scroll viewport
    /// height, and (with the counter) each geometry report and body count. A healthy open
    /// goes from 0 to its final viewport once; anything in between is motion nobody chose (FA1).
    private static func probePopoverFrames(_ store: UsageStore) async -> [UIBenchFrame] {
        say("  -- frame-by-frame probe (warm, not timed)")
        BenchCounters.reset()
        BenchCounters.recordSequence = true
        defer { BenchCounters.recordSequence = false }
        let (host, fitBefore, fitAfter) = hostPopover(store)
        let hosting = host.hosting
        say("    fittingSize before layout \(f(fitBefore)), after first layout \(f(fitAfter))")
        if BenchCounters.isCompiledIn {
            say("    open sequence: \(compressed(BenchCounters.drainSequence()))")
        }
        var frames: [UIBenchFrame] = []
        let start = clock.now
        var index = 0
        var lastViewport: Double?
        while ms(clock.now - start) < 600 {
            index += 1
            let bodiesBefore = BenchCounters.total
            let rootBefore = rootPasses()
            try? await Task.sleep(for: .milliseconds(16))
            host.framePass()
            let sequence = BenchCounters.drainSequence()
            let reports = sequence.compactMap { item -> Double? in
                guard let range = item.range(of: "viewport=") else { return nil }
                return Double(item[range.upperBound...].prefix { $0 != "," && $0 != ")" })
            }
            let bodies = BenchCounters.total - bodiesBefore
            let viewport = findScrollView(in: hosting).map { Double($0.contentView.bounds.height) }
            defer { lastViewport = viewport }
            guard index <= 3 || !reports.isEmpty || bodies > 0 || viewport != lastViewport else { continue }
            let frame = UIBenchFrame(
                frame: index,
                elapsedMs: Int(ms(clock.now - start).rounded()),
                fittingHeight: hosting.fittingSize.height,
                viewportHeight: viewport,
                geometryReports: BenchCounters.isCompiledIn ? reports : nil,
                bodies: BenchCounters.isCompiledIn ? bodies : nil,
                rootPasses: BenchCounters.isCompiledIn ? rootPasses() - rootBefore : nil
            )
            frames.append(frame)
            var line = "    frame \(index) (+\(frame.elapsedMs)ms): fittingSize \(f(frame.fittingHeight)) viewport \(viewport.map(f) ?? "-")"
            if BenchCounters.isCompiledIn {
                let reported = reports.isEmpty ? "-" : reports.map(f).joined(separator: ",")
                line += " geometry reports \(reported) bodies \(bodies) root passes \(rootPasses() - rootBefore)"
                let views = sequence.filter { !$0.hasPrefix("·") }
                if !views.isEmpty { line += " | \(compressed(views))" }
            }
            say(line)
        }
        say("    \(index) frames; listed: the first three and any that moved the viewport, reported geometry or ran a body")
        host.teardown()
        return frames
    }

    // MARK: - Scroll steps

    private static func benchScroll(scenario: UIBenchOptions.Scenario, sweeps: Int) async {
        say("\n## scroll scenario=\(scenario.rawValue) sweeps=\(sweeps)")
        let (store, _) = await makeStore(scenario)
        await primeMenuBarLabel(store)
        _ = await measurePopoverOpen(store, label: "scroll-primer")
        let host = hostPopover(store).0
        defer { host.teardown() }
        // Let the open and its 900ms indicator hold finish before the first step.
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(16))
            host.framePass()
        }
        try? await Task.sleep(for: .milliseconds(1200))
        host.renderPass()
        guard let scrollView = findScrollView(in: host.hosting) else {
            say("  no NSScrollView under the popover; cannot drive scroll")
            record(UIBenchResult(
                id: "scroll/\(scenario.rawValue)", kind: "scroll", scenario: scenario.rawValue, note: "no scroll view"
            ))
            return
        }
        let clip = scrollView.contentView
        let content = scrollView.documentView?.frame.height ?? 0
        say("  viewport \(f(clip.bounds.height)) content \(f(content))")
        if content <= clip.bounds.height {
            say("  content fits the viewport; nothing scrolls at \(scenario.rawValue)")
        }
        var stepCpu: [Double] = []
        var stepBodies: [Double] = []
        var allCounts: [String: Int] = [:]
        var idleCpu: [Double] = []
        var idleCounts: [String: Int] = [:]
        for sweep in 1...sweeps {
            for step in 1...10 {
                BenchCounters.reset()
                BenchCounters.recordSequence = true
                let interval = signposter.beginInterval("scroll-step", id: signposter.makeSignpostID(), "\(scenario.rawValue, privacy: .public)#\(sweep).\(step)")
                let cpu0 = cpuNow()
                var origin = clip.bounds.origin
                origin.y += clip.isFlipped ? 60 : -60
                clip.scroll(to: origin)
                scrollView.reflectScrolledClipView(clip)
                host.renderPass()
                _ = await host.settle(minTurns: 2, maxTurns: 20)
                let cpu = cpuMs(since: cpu0)
                signposter.endInterval("scroll-step", interval)
                let counts = BenchCounters.counts
                let reports = BenchCounters.drainSequence().filter { $0.hasPrefix("·scrollMetrics") }.count
                BenchCounters.recordSequence = false
                stepCpu.append(cpu)
                stepBodies.append(Double(BenchCounters.total))
                allCounts.merge(counts, uniquingKeysWith: +)
                var line = "  sweep \(sweep) step \(step): offset \(f(clip.bounds.origin.y)) cpu \(f(cpu))ms"
                if BenchCounters.isCompiledIn {
                    line += " geometry reports \(reports) bodies \(BenchCounters.total) | \(sortedCounts(counts))"
                }
                say(line)
                try? await Task.sleep(for: .milliseconds(30))
            }
            // The indicator's 900ms hold and 200ms fade after scrolling stops, at 60Hz dirty-only
            // frames: one leaf body (SC1), never the popover.
            BenchCounters.reset()
            let passesBefore = framePassesDone
            let cpu0 = cpuNow()
            let idleStart = clock.now
            while ms(clock.now - idleStart) < 1200 {
                try? await Task.sleep(for: .milliseconds(16))
                host.framePass()
            }
            idleCpu.append(cpuMs(since: cpu0))
            idleCounts.merge(BenchCounters.counts, uniquingKeysWith: +)
            var idleLine = "  sweep \(sweep) 1200ms after scrolling: cpu \(f(idleCpu.last ?? 0))ms dirty frames \(framePassesDone - passesBefore)"
            if BenchCounters.isCompiledIn { idleLine += " bodies \(BenchCounters.total) | \(sortedCounts(BenchCounters.counts))" }
            say(idleLine)
            clip.scroll(to: .zero)
            scrollView.reflectScrolledClipView(clip)
            host.renderPass()
            _ = await host.settle(maxTurns: 20)
            try? await Task.sleep(for: .milliseconds(1200))
            host.renderPass()
        }
        if let stats = UIBenchStats(stepCpu) { say("  scroll[\(scenario.rawValue)] step cpu    \(stats.text)") }
        if BenchCounters.isCompiledIn, let stats = UIBenchStats(stepBodies) {
            say("  scroll[\(scenario.rawValue)] step bodies \(stats.text)")
        }
        var result = UIBenchResult(id: "scroll/\(scenario.rawValue)", kind: "scroll", scenario: scenario.rawValue)
        result.metrics["stepCpuMs"] = .coldWarm(stepCpu)
        result.metrics["idleAfterScrollCpuMs"] = .warm(idleCpu)
        if BenchCounters.isCompiledIn { result.metrics["stepBodies"] = .coldWarm(stepBodies) }
        result.bodies = bodies(["allSteps": allCounts, "idleAfterScroll": idleCounts])
        record(result)
    }

    // MARK: - Settings open

    private struct SettingsOpen {
        var syncWall = 0.0, settledWall = 0.0, cpu = 0.0
        var turns = 0
        var counts: [String: Int] = [:]
    }

    /// Opens Settings on `pane` (stored, as a returning user would have it) in a titled window
    /// at the shipping size, then turns the runloop until the pane is built and SwiftUI is
    /// quiet. The caller tears the host down.
    private static func openSettings(
        _ store: UsageStore,
        _ preferences: Preferences,
        pane: SettingsPane,
        label: String,
        keyStore: any APIKeyStoring = DemoAPIKeyStore(),
        printSequence: Bool = false
    ) async -> (SettingsOpen, Host) {
        preferences.settingsPane = pane
        BenchCounters.reset()
        BenchCounters.recordSequence = printSequence
        defer { BenchCounters.recordSequence = false }
        var sample = SettingsOpen()
        let interval = signposter.beginInterval("settings-open", id: signposter.makeSignpostID(), "\(label, privacy: .public)")
        let cpu0 = cpuNow()
        let t0 = clock.now
        let host = makeHost(
            settingsRoot(store, preferences, keyStore: keyStore),
            size: NSSize(width: SettingsView.windowWidth, height: SettingsView.windowHeight),
            titled: true
        )
        let t1 = clock.now
        if printSequence, BenchCounters.isCompiledIn {
            say("    open sequence: \(compressed(BenchCounters.drainSequence()))")
        }
        sample.turns = await host.settle(minTurns: printSequence ? 3 : 1, until: { paneBuilt(pane) })
        sample.cpu = cpuMs(since: cpu0)
        signposter.endInterval("settings-open", interval)
        sample.syncWall = ms(t1 - t0)
        sample.settledWall = ms(clock.now - t0)
        sample.counts = BenchCounters.counts
        if printSequence, BenchCounters.isCompiledIn {
            say("    settle sequence: \(compressed(BenchCounters.drainSequence()))")
        }
        return (sample, host)
    }

    private static func benchSettings(pane: SettingsPane, scenario: UIBenchOptions.Scenario, runs: Int) async {
        say("\n## settings-open pane=\(pane.rawValue) scenario=\(scenario.rawValue)")
        let (store, preferences) = await makeStore(scenario)
        // Settings opens from the popover's gear, so the label and the popover drew first.
        await primeMenuBarLabel(store)
        _ = await measurePopoverOpen(store, label: "settings-primer")
        var samples: [SettingsOpen] = []
        for run in 0...runs {
            let (sample, host) = await openSettings(
                store, preferences, pane: pane, label: "\(scenario.rawValue) \(pane.rawValue)#\(run)"
            )
            host.teardown()
            var line = "  run \(run)\(run == 0 ? " (cold)" : ""): sync \(f(sample.syncWall)) "
                + "settled \(f(sample.settledWall)) cpu \(f(sample.cpu)) turns \(sample.turns)"
            if BenchCounters.isCompiledIn {
                line += " bodies \(sample.counts.values.reduce(0, +)) \(paneStruct(pane))=\(sample.counts[paneStruct(pane)] ?? 0)"
                if pane != .general { line += " GeneralSettingsPane=\(sample.counts["GeneralSettingsPane"] ?? 0)" }
            }
            say(line)
            samples.append(sample)
            try? await Task.sleep(for: .milliseconds(30))
        }
        let warm = Array(samples.dropFirst())
        let title = "settings[\(pane.rawValue)]"
        let rows: [(String, KeyPath<SettingsOpen, Double>)] = [
            ("sync wall", \.syncWall), ("settled wall", \.settledWall), ("cpu", \.cpu),
        ]
        for (name, path) in rows {
            if let stats = UIBenchStats(warm.map { $0[keyPath: path] }) {
                say("  \(title) warm \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(stats.text)")
            }
        }
        if BenchCounters.isCompiledIn {
            say("  cold counts: \(sortedCounts(samples[0].counts))")
            if let first = warm.first { say("  warm counts: \(sortedCounts(first.counts))") }
        }
        var result = UIBenchResult(
            id: "settings-open/\(scenario.rawValue)/\(pane.rawValue)",
            kind: "settings-open",
            scenario: scenario.rawValue,
            pane: pane.rawValue
        )
        result.metrics["syncWallMs"] = .coldWarm(samples.map(\.syncWall))
        result.metrics["settledWallMs"] = .coldWarm(samples.map(\.settledWall))
        result.metrics["cpuMs"] = .coldWarm(samples.map(\.cpu))
        if BenchCounters.isCompiledIn {
            result.metrics["bodies"] = .coldWarm(samples.map { Double($0.counts.values.reduce(0, +)) })
            // LP1: General is built only when General is the stored pane.
            result.metrics["generalPaneBodies"] = .coldWarm(samples.map { Double($0.counts["GeneralSettingsPane"] ?? 0) })
        }
        result.bodies = bodies(["cold": samples[0].counts, "warm": warm.first?.counts ?? [:]])
        record(result)
    }

    // MARK: - Pane switches

    private struct PaneSwitch {
        let from: SettingsPane
        let to: SettingsPane
        let instant: Bool
        let firstInto: Bool
        var sync = 0.0, settled = 0.0, cpu = 0.0
        var builtInSyncPass = false
        var counts: [String: Int] = [:]
    }

    /// Instant: the selection write and one render pass (the click's frame), then turns until
    /// quiet. Animated: SwiftUI drives the 80ms-out / 200ms-in transition on its own clock, so
    /// CPU covers 450ms of 60Hz frames.
    private static func switchPane(
        scenario: UIBenchOptions.Scenario,
        from: SettingsPane,
        to: SettingsPane,
        instant: Bool,
        firstInto: Bool,
        host: Host
    ) async -> PaneSwitch {
        BenchCounters.reset()
        var sample = PaneSwitch(from: from, to: to, instant: instant, firstInto: firstInto)
        let interval = signposter.beginInterval(
            "pane-switch", id: signposter.makeSignpostID(),
            "\(scenario.rawValue, privacy: .public) \(from.rawValue, privacy: .public)->\(to.rawValue, privacy: .public) instant=\(instant)"
        )
        let cpu0 = cpuNow()
        let t0 = clock.now
        _ = requestPane(to, instant: instant)
        host.renderPass()
        sample.sync = ms(clock.now - t0)
        sample.builtInSyncPass = paneBuilt(to)
        if instant {
            _ = await host.settle(until: { paneBuilt(to) })
            sample.settled = ms(clock.now - t0)
        } else {
            let start = clock.now
            while ms(clock.now - start) < 450 {
                try? await Task.sleep(for: .milliseconds(16))
                host.framePass()
            }
            sample.settled = ms(clock.now - t0)
        }
        sample.cpu = cpuMs(since: cpu0)
        signposter.endInterval("pane-switch", interval)
        sample.counts = BenchCounters.counts
        return sample
    }

    private static func benchSwitch(scenario: UIBenchOptions.Scenario, passes: Int, animated: Bool) async {
        say("\n## pane-switch scenario=\(scenario.rawValue) instant passes=\(passes) animated=\(animated)")
        guard BenchCounters.isCompiledIn else {
            say("  pane switches unavailable — the Settings pane seam needs -DHEADROOM_BENCH")
            record(UIBenchResult(
                id: "pane-switch/\(scenario.rawValue)", kind: "pane-switch",
                scenario: scenario.rawValue, note: "needs HEADROOM_BENCH"
            ))
            return
        }
        let (store, preferences) = await makeStore(scenario)
        await primeMenuBarLabel(store)
        _ = await measurePopoverOpen(store, label: "switch-primer")
        let (open, host) = await openSettings(store, preferences, pane: .general, label: "switch-host")
        defer { host.teardown() }
        say("  host opened on General: cpu \(f(open.cpu)) settled \(f(open.settledWall))")
        let panes = SettingsPane.allCases
        var current: SettingsPane = .general
        var visited: Set<SettingsPane> = [.general]
        var samples: [PaneSwitch] = []

        func go(_ to: SettingsPane, instant: Bool) async {
            let sample = await switchPane(
                scenario: scenario, from: current, to: to, instant: instant,
                firstInto: !visited.contains(to), host: host
            )
            visited.insert(to)
            samples.append(sample)
            current = to
            try? await Task.sleep(for: .milliseconds(5))
        }

        for pass in 1...passes {
            for from in panes {
                for to in panes where to != from {
                    if current != from { await go(from, instant: true) }
                    await go(to, instant: true)
                }
            }
            say("  instant pass \(pass) done, \(samples.count) switches so far")
        }
        if animated {
            // Animated cost is dominated by building the target, so each pane is visited from
            // General and back rather than over every pair.
            if current != .general { await go(.general, instant: true) }
            for to in panes where to != .general {
                await go(to, instant: false)
                await go(.general, instant: false)
            }
            say("  animated pass done")
        }

        say("  per target pane (instant; first-into = first visit this process, warm = the rest):")
        for pane in panes {
            let rows = samples.filter { $0.to == pane && $0.instant }
            let first = rows.first(where: \.firstInto)
            let warm = rows.filter { !$0.firstInto }
            let name = pane.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)
            let blank = "".padding(toLength: 13, withPad: " ", startingAt: 0)
            let firstBodies = first.map { "\($0.counts.values.reduce(0, +))" } ?? "-"
            say("  \(name) first-into sync \(first.map { f($0.sync) } ?? "-") cpu \(first.map { f($0.cpu) } ?? "-") bodies \(firstBodies)")
            if let stats = UIBenchStats(warm.map(\.cpu)) { say("  \(blank) warm cpu     \(stats.text)") }
            if let stats = UIBenchStats(warm.map(\.sync)) {
                say("  \(blank) warm sync    \(stats.text) built in the click's frame \(warm.filter(\.builtInSyncPass).count)/\(warm.count)")
            }
            let animatedRows = samples.filter { $0.to == pane && !$0.instant }
            if let stats = UIBenchStats(animatedRows.map(\.cpu)) { say("  \(blank) animated cpu \(stats.text) (450ms window)") }

            var result = UIBenchResult(
                id: "pane-switch/\(scenario.rawValue)/\(pane.rawValue)",
                kind: "pane-switch",
                scenario: scenario.rawValue,
                pane: pane.rawValue
            )
            result.metrics["instantCpuMs"] = .coldWarm(cold: first?.cpu, warm: warm.map(\.cpu))
            result.metrics["instantSyncMs"] = .coldWarm(cold: first?.sync, warm: warm.map(\.sync))
            result.metrics["instantSettledMs"] = .warm(warm.map(\.settled))
            result.metrics["instantBodies"] = .warm(warm.map { Double($0.counts.values.reduce(0, +)) })
            if !animatedRows.isEmpty {
                result.metrics["animatedCpuMs"] = .warm(animatedRows.map(\.cpu))
                result.metrics["animatedSyncMs"] = .warm(animatedRows.map(\.sync))
            }
            result.bodies = bodies(["firstInto": first?.counts ?? [:], "warm": warm.first?.counts ?? [:]])
            record(result)
        }
    }

    // MARK: - Body counts per interaction

    /// Mutates, then turns the runloop until the store is idle and SwiftUI is quiet (or, with
    /// `frames60Hz`, drives 600ms of dirty-only frames so springs and arrivals land).
    private static func observeChange(
        _ id: String,
        _ title: String,
        store: UsageStore,
        host: Host,
        frames60Hz: Bool = false,
        _ mutate: () -> Bool = { true }
    ) async {
        BenchCounters.reset()
        BenchCounters.recordSequence = true
        defer { BenchCounters.recordSequence = false }
        let passesBefore = framePassesDone
        let interval = signposter.beginInterval("store-change", id: signposter.makeSignpostID(), "\(id, privacy: .public)")
        let cpu0 = cpuNow()
        let t0 = clock.now
        guard mutate() else {
            signposter.endInterval("store-change", interval)
            say("  \(title): skipped — the Settings pane seam needs -DHEADROOM_BENCH")
            record(UIBenchResult(id: "counts/\(id)", kind: "store-change", note: "needs HEADROOM_BENCH"))
            return
        }
        host.renderPass()
        var turns = 0
        if frames60Hz {
            while ms(clock.now - t0) < 600 || store.isRefreshing || !store.probingAccounts.isEmpty {
                try? await Task.sleep(for: .milliseconds(16))
                host.framePass()
                turns += 1
                if turns > 200 { break }
            }
        } else {
            turns = await host.settle(
                minTurns: 5, maxTurns: 300,
                until: { !store.isRefreshing && store.probingAccounts.isEmpty }
            )
        }
        let wall = ms(clock.now - t0)
        let cpu = cpuMs(since: cpu0)
        signposter.endInterval("store-change", interval)
        var line = "  \(title): wall \(f(wall))ms cpu \(f(cpu))ms turns \(turns)"
        if frames60Hz { line += " dirty frames \(framePassesDone - passesBefore)" }
        if BenchCounters.isCompiledIn {
            line += " bodies \(BenchCounters.total)"
            say(line)
            if !BenchCounters.counts.isEmpty { say("     counts: \(sortedCounts(BenchCounters.counts))") }
            let sequence = BenchCounters.drainSequence()
            if !sequence.isEmpty { say("     sequence: \(compressed(sequence))") }
        } else {
            say(line)
        }
        var result = UIBenchResult(id: "counts/\(id)", kind: "store-change", note: title)
        result.metrics["cpuMs"] = .single(cpu)
        result.metrics["wallMs"] = .single(wall)
        if BenchCounters.isCompiledIn { result.metrics["bodies"] = .single(Double(BenchCounters.total)) }
        result.bodies = bodies(["change": BenchCounters.counts])
        record(result)
    }

    private static func idle(_ id: String, _ title: String, milliseconds: Int, host: Host) async {
        BenchCounters.reset()
        let cpu0 = cpuNow()
        try? await Task.sleep(for: .milliseconds(milliseconds))
        host.renderPass()
        let cpu = cpuMs(since: cpu0)
        var line = "  \(title): idle \(milliseconds)ms cpu \(f(cpu))ms"
        if BenchCounters.isCompiledIn { line += " bodies \(BenchCounters.total) \(sortedCounts(BenchCounters.counts))" }
        say(line)
        var result = UIBenchResult(id: "counts/\(id)", kind: "idle", note: title)
        result.metrics["cpuMs"] = .single(cpu)
        if BenchCounters.isCompiledIn { result.metrics["bodies"] = .single(Double(BenchCounters.total)) }
        result.bodies = bodies(["idle": BenchCounters.counts])
        record(result)
    }

    private static func recordOpen(_ id: String, _ title: String, cpu: Double, counts: [String: Int]) {
        var line = "  \(title): cpu \(f(cpu))ms"
        if BenchCounters.isCompiledIn { line += " bodies \(counts.values.reduce(0, +)) | \(sortedCounts(counts))" }
        say(line)
        var result = UIBenchResult(id: "counts/\(id)", kind: "open", note: title)
        result.metrics["cpuMs"] = .single(cpu)
        result.bodies = bodies(["open": counts])
        record(result)
    }

    private static func benchCounts(scenario: UIBenchOptions.Scenario) async {
        say("\n## body counts scenario=\(scenario.rawValue) (the Claude primary's snapshot changes on every fetch)")
        if !BenchCounters.isCompiledIn {
            say("  body counts unavailable — build with -DHEADROOM_BENCH; timings only")
        }
        let (store, preferences) = await makeStore(scenario, changingClaudePrimary: true)
        await primeMenuBarLabel(store)
        let claudeKey = store.accounts(for: .claude)[0].key
        let codexKey = store.accounts(for: .codex)[0].key

        say("\n### Settings opened on its stored pane (Appearance), no saved keys")
        let (open, host) = await openSettings(store, preferences, pane: .appearance, label: "counts-open", printSequence: true)
        recordOpen("settings-open-appearance", "open on Appearance", cpu: open.cpu, counts: open.counts)
        await idle("settings-idle-after-open", "after open", milliseconds: 400, host: host)

        say("\n### Store changes unrelated to the visible pane (General shown, Accounts never visited)")
        await observeChange("switch-appearance-general", "Appearance → General (instant)", store: store, host: host) {
            requestPane(.general, instant: true)
        }
        await observeChange("refresh-claude-changed", "refreshAccountNow(Claude primary, data changes)", store: store, host: host) {
            store.refreshAccountNow(claudeKey)
            return true
        }
        let showsPercentage = store.showMenuBarPercentage
        await observeChange("menu-bar-only-change", "setShowMenuBarPercentage (only the menu bar reads it)", store: store, host: host) {
            store.setShowMenuBarPercentage(!showsPercentage)
            return true
        }
        let style = store.meterStyle
        await observeChange("meter-style-same-value", "setMeterStyle(same value)", store: store, host: host) {
            store.setMeterStyle(style)
            return true
        }

        say("\n### Pane switches")
        await observeChange("switch-general-accounts", "General → Accounts (instant)", store: store, host: host) {
            requestPane(.accounts, instant: true)
        }
        await observeChange("switch-accounts-general", "Accounts → General (instant)", store: store, host: host) {
            requestPane(.general, instant: true)
        }
        await observeChange("switch-general-appearance-animated", "General → Appearance (animated)", store: store, host: host) {
            requestPane(.appearance, instant: false)
        }
        await observeChange("switch-appearance-general-2", "Appearance → General (instant)", store: store, host: host) {
            requestPane(.general, instant: true)
        }

        say("\n### After Accounts was visited (the duplicate-login scan is live), General shown")
        await observeChange("refresh-claude-changed-after-accounts", "refreshAccountNow(Claude primary, data changes)", store: store, host: host) {
            store.refreshAccountNow(claudeKey)
            return true
        }
        await observeChange("refresh-codex-unchanged-after-accounts", "refreshAccountNow(Codex primary, data unchanged)", store: store, host: host) {
            store.refreshAccountNow(codexKey)
            return true
        }
        host.teardown()

        say("\n### Settings opened with two saved API keys (Anthropic and OpenAI present, xAI absent)")
        let (keyedOpen, keyedHost) = await openSettings(
            store, preferences, pane: .general, label: "counts-saved-keys", keyStore: TwoKeyStore(), printSequence: true
        )
        recordOpen("settings-open-saved-keys", "open on General with saved keys", cpu: keyedOpen.cpu, counts: keyedOpen.counts)
        await idle("settings-idle-after-saved-keys", "after open", milliseconds: 400, host: keyedHost)
        keyedHost.teardown()

        let popoverScenarios = scenario == .multi20 ? [scenario] : [scenario, .multi20]
        for popoverScenario in popoverScenarios {
            say("\n### Popover \(popoverScenario.rawValue): open, refreshes, a change it never reads")
            let pStore: UsageStore
            if popoverScenario == scenario {
                pStore = store
            } else {
                pStore = await makeStore(popoverScenario, changingClaudePrimary: true).0
            }
            let id = popoverScenario.rawValue
            BenchCounters.reset()
            let cpu0 = cpuNow()
            let pHost = hostPopover(pStore).0
            _ = await pHost.settle(minTurns: 3)
            recordOpen("popover-\(id)-open", "[\(id)] popover open", cpu: cpuMs(since: cpu0), counts: BenchCounters.counts)
            await idle("popover-\(id)-arrival", "[\(id)] first-open arrival window (M9A lands here)", milliseconds: 900, host: pHost)
            await idle("popover-\(id)-idle", "[\(id)] idle after arrival", milliseconds: 600, host: pHost)
            await observeChange("popover-\(id)-baseline", "[\(id)] no change, 60Hz dirty-only frames", store: pStore, host: pHost, frames60Hz: true)
            let pCodex = pStore.accounts(for: .codex)[0].key
            await observeChange(
                "popover-\(id)-refresh-codex-unchanged", "[\(id)] refreshAccountNow(Codex primary, data unchanged)",
                store: pStore, host: pHost, frames60Hz: true
            ) {
                pStore.refreshAccountNow(pCodex)
                return true
            }
            try? await Task.sleep(for: .milliseconds(1500))
            let pClaude = pStore.accounts(for: .claude)[0].key
            await observeChange(
                "popover-\(id)-refresh-claude-changed", "[\(id)] refreshAccountNow(Claude primary, data changes)",
                store: pStore, host: pHost, frames60Hz: true
            ) {
                pStore.refreshAccountNow(pClaude)
                return true
            }
            // Let the meter-fill spring from that refresh finish before the next case.
            try? await Task.sleep(for: .milliseconds(1500))
            let pShows = pStore.showMenuBarPercentage
            await observeChange(
                "popover-\(id)-menu-bar-only-change", "[\(id)] setShowMenuBarPercentage (the popover never reads it)",
                store: pStore, host: pHost, frames60Hz: true
            ) {
                pStore.setShowMenuBarPercentage(!pShows)
                return true
            }
            pHost.teardown()
        }
    }

    // MARK: - Scene stand-in (ML1)

    /// `App.body` can't be hosted in a view, so this compares a direct Settings host with
    /// `BenchSceneStandIn`, which builds the label and Settings the way `HeadroomApp.body`
    /// does today. Expected: a change only the label reads re-runs `MenuBarStatusLabel` and
    /// nothing in Settings; an unchanged refresh re-runs nothing.
    private static func benchScene(scenario: UIBenchOptions.Scenario) async {
        say("\n## scene stand-in scenario=\(scenario.rawValue), Settings on Accounts (the Claude primary's snapshot changes on every fetch)")
        if !BenchCounters.isCompiledIn {
            say("  body counts unavailable — build with -DHEADROOM_BENCH; timings only")
        }
        let (store, preferences) = await makeStore(scenario, changingClaudePrimary: true)
        await primeMenuBarLabel(store)
        // One per launch, as `AppComposition.settingsCredentialStore` is.
        let credentialStore = CredentialStore(apiKeyStore: DemoAPIKeyStore())
        let claudeKey = store.accounts(for: .claude)[0].key
        let codexKey = store.accounts(for: .codex)[0].key
        for standIn in [false, true] {
            preferences.settingsPane = .accounts
            BenchCounters.reset()
            let size = NSSize(width: SettingsView.windowWidth, height: SettingsView.windowHeight)
            let host: Host = standIn
                ? makeHost(
                    BenchSceneStandIn(
                        store: store,
                        preferences: preferences,
                        credentialStore: credentialStore,
                        notificationClient: notificationClient
                    ),
                    size: size,
                    titled: true
                )
                : makeHost(settingsRoot(store, preferences), size: size, titled: true)
            _ = await host.settle(minTurns: 3)
            try? await Task.sleep(for: .milliseconds(300))
            host.renderPass()
            let tag = standIn ? "scene-stand-in" : "direct-settings"
            say("\n### \(standIn ? "Scene stand-in (label + Settings, built as HeadroomApp.body builds them)" : "Direct SettingsView host")")
            if BenchCounters.isCompiledIn { say("  open counts: \(sortedCounts(BenchCounters.counts))") }
            let showsPercentage = store.showMenuBarPercentage
            await observeChange("\(tag)-menu-bar-only-change", "setShowMenuBarPercentage (only the label reads it)", store: store, host: host) {
                store.setShowMenuBarPercentage(!showsPercentage)
                return true
            }
            await observeChange("\(tag)-refresh-codex-unchanged", "refreshAccountNow(Codex primary, data unchanged)", store: store, host: host) {
                store.refreshAccountNow(codexKey)
                return true
            }
            await observeChange("\(tag)-refresh-claude-changed", "refreshAccountNow(Claude primary, data changes)", store: store, host: host) {
                store.refreshAccountNow(claudeKey)
                return true
            }
            host.teardown()
        }
    }
}

/// Stand-in for `HeadroomApp.body` (ML1). `MenuBarExtra`'s label closure and `Window`'s content
/// closure run inside the scene body, so this view builds both the same way: the label gets
/// only the store reference (`MenuBarStatusLabel` reads it in its own body), Settings gets a
/// per-launch credential store and a binding to app-owned state, and the parent reads nothing
/// from the store. If `HeadroomApp.body` changes shape, change this to match.
private struct BenchSceneStandIn: View {
    let store: UsageStore
    let preferences: Preferences
    let credentialStore: CredentialStore
    let notificationClient: any NotificationAuthorizing
    @State private var appearancePreference: AppearancePreference = .light

    var body: some View {
        let _ = BenchCounters.hit("SceneStandIn")
        SettingsView(
            store: store,
            appearancePreference: $appearancePreference,
            preferences: preferences,
            credentialStore: credentialStore,
            duplicateDetector: ClaudeDuplicateLoginDetector(readAccountUUID: { _ in nil }),
            notificationClient: notificationClient
        )
        .overlay(alignment: .topLeading) {
            MenuBarStatusLabel(store: store)
                .fixedSize()
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .light)
    }
}

/// Two saved keys (Anthropic and OpenAI), for the saved-key presence sweep. Never the Keychain.
private struct TwoKeyStore: APIKeyStoring {
    func readAPIKey(for provider: APIKeyProvider) throws -> String {
        switch provider {
        case .anthropic, .openAI: return "bench-placeholder"
        default: throw CredentialError.notLoggedIn
        }
    }

    func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws { throw CredentialError.notLoggedIn }
    func deleteAPIKey(for provider: APIKeyProvider) throws { throw CredentialError.notLoggedIn }
}

/// A provider whose snapshot changes on every fetch, so a refresh lands new data.
private final class BenchTicker: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    func next() -> Int {
        count.withLock { value in
            value += 1
            return value
        }
    }
}

private struct BenchChangingProvider: UsageProvider {
    let id: ProviderID
    let displayName: String
    private let ticker = BenchTicker()

    init(id: ProviderID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func fetchSnapshot() async -> UsageSnapshot {
        let tick = ticker.next()
        return UsageSnapshot(
            providerID: id,
            windows: [
                UsageWindow(
                    kind: .fiveHour, utilization: Double(20 + tick % 50),
                    resetsAt: Date().addingTimeInterval(3.2 * 3600), resetLabel: "Resets 2:15pm"
                ),
                UsageWindow(
                    kind: .weekly, utilization: Double(40 + tick % 30),
                    resetsAt: Date().addingTimeInterval(4 * 86_400), resetLabel: "Resets Jul 20"
                ),
            ],
            planLabel: "Max",
            accountEmail: "personal@example.com",
            capturedAt: Date(),
            freshness: .live
        )
    }
}
