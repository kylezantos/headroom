import AppKit
import HeadroomCore
#if SWIFT_PACKAGE
import HeadroomWidgetSharedUI
#endif
import SwiftUI

/// Hidden diagnostic (`--render-widgets <dir>`, 2026-10-02 widget-styles plan KTD12): renders
/// the real shared widget-style bodies with `ImageRenderer` — every style × family × fixture ×
/// appearance × geometry — into PNGs plus a contact sheet, and flags any probed element that
/// leaves its tile's content box (WCF7, R10).
///
/// What it cannot prove: `ImageRenderer` ignores `.dynamicTypeSize` and lays iPhone text out
/// with macOS metrics, so the 6.1″ renders are geometry evidence only. The `shrunk` pass
/// narrows each tile as a stand-in for xxLarge labels; the device check remains the gate.
///
/// Filters: `--widget-style <id>`, `--widget-fixture <name>`, `--widget-geometry mac|ios61|ios67`,
/// `--widget-quick` (Claude + Codex only, both appearances, macOS and 6.1″),
/// `--widget-family lock|home` (Lock Screen bodies only, or the unchanged home sweep),
/// `--widget-transparent` (no harness backdrops, 4× scale).
@MainActor
enum WidgetRenderHarness {
    struct Geometry {
        let name: String
        let sizes: [WidgetFamily: CGSize]
        let radius: CGFloat
        let margins: [WidgetFamily: CGFloat]
        let footerPrefix: String
    }

    static let geometries: [Geometry] = [
        Geometry(name: "mac",
                 sizes: [.small: CGSize(width: 170, height: 170), .medium: CGSize(width: 364, height: 170), .large: CGSize(width: 364, height: 382)],
                 radius: 22, margins: [.small: 16, .medium: 16, .large: 16], footerPrefix: HeadroomWidgetCopy.macFooterPrefix),
        Geometry(name: "ios61",
                 sizes: [.small: CGSize(width: 158, height: 158), .medium: CGSize(width: 338, height: 158), .large: CGSize(width: 338, height: 354)],
                 radius: 22, margins: [.small: 12, .medium: 14, .large: 12], footerPrefix: HeadroomWidgetCopy.iosFooterPrefix),
        Geometry(name: "ios67",
                 sizes: [.small: CGSize(width: 170, height: 170), .medium: CGSize(width: 364, height: 170), .large: CGSize(width: 364, height: 382)],
                 radius: 23, margins: [.small: 12, .medium: 14, .large: 12], footerPrefix: HeadroomWidgetCopy.iosFooterPrefix),
    ]

    /// Fixed so every countdown is reproducible.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    struct Job {
        let style: WidgetLayoutStyle
        let fixture: String
        let family: WidgetFamily
        let dark: Bool
        let geometry: Geometry
        var colorMode: WidgetColorMode = .solid
        var rendering: HeadroomWidgetRenderingContext = .fullColor
        var shrink: CGFloat = 1
        var status: WidgetStatusState?

        var fileName: String {
            var parts = [status == nil ? style.rawValue : "status", fixture, "\(family)", geometry.name, dark ? "dark" : "light"]
            if colorMode != .solid { parts.append(colorMode.rawValue) }
            if rendering != .fullColor { parts.append("\(rendering)") }
            if shrink != 1 { parts.append("shrunk") }
            return parts.joined(separator: "-") + ".png"
        }
    }

    static func run(outputDirectory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let outDir = URL(fileURLWithPath: (outputDirectory as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let jobs = buildJobs()
        let lockJobs = buildLockJobs()
        guard !jobs.isEmpty || !lockJobs.isEmpty else {
            print("✗ No tiles to render for these filters")
            exit(2)
        }
        var overflows: [String] = []
        var stress: [String] = []
        var rendered: [(Job, String)] = []
        for job in jobs {
            let (image, problems) = render(job)
            let url = outDir.appendingPathComponent(job.fileName)
            if let image, write(image, to: url) {
                rendered.append((job, job.fileName))
            } else {
                overflows.append("\(job.fileName): render failed")
            }
            // The shrunk pass is a stress stand-in for xxLarge text, not a real tile size, so
            // its findings are warnings to review by eye rather than failures.
            if job.shrink != 1 {
                stress += problems.map { "\(job.fileName): \($0)" }
            } else {
                overflows += problems.map { "\(job.fileName): \($0)" }
            }
        }
        var lockRendered: [(LockJob, String)] = []
        for job in lockJobs {
            let (image, problems) = renderLock(job)
            if let image, write(image, to: outDir.appendingPathComponent(job.fileName)) {
                lockRendered.append((job, job.fileName))
            } else {
                overflows.append("\(job.fileName): render failed")
            }
            overflows += problems.map { "\(job.fileName): \($0)" }
        }
        writeContactSheet(rendered, lockRendered: lockRendered, overflows: overflows + stress, to: outDir.appendingPathComponent("index.html"))
        let report = overflows.isEmpty ? "No overflow.\n" : overflows.joined(separator: "\n") + "\n"
        try? report.write(to: outDir.appendingPathComponent("overflow.txt"), atomically: true, encoding: .utf8)
        try? (stress.joined(separator: "\n") + "\n").write(to: outDir.appendingPathComponent("overflow-shrunk.txt"), atomically: true, encoding: .utf8)
        print("Rendered \(rendered.count) home tiles and \(lockRendered.count) Lock Screen tiles to \(outDir.path)")
        print(overflows.isEmpty ? "✓ No overflow" : "✗ \(overflows.count) overflow finding(s) — see overflow.txt")
        if !stress.isEmpty { print("△ \(stress.count) finding(s) in the shrunk xxLarge stand-in — see overflow-shrunk.txt") }
        exit(overflows.isEmpty ? 0 : 1)
    }

    // MARK: Jobs

    /// Compositing renders for video and marketing: the harness's own backdrops (export padding,
    /// Lock Screen wallpaper) go transparent and tiles render at 4×; widget designs are untouched.
    static let transparent = CommandLine.arguments.contains("--widget-transparent")
    static var renderScale: CGFloat { transparent ? 4 : 2 }

    private static func argument(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    static func buildJobs() -> [Job] {
        if let family = argument("--widget-family"), !["lock", "home"].contains(family) {
            print("Unknown family \(family). Families: lock, home")
            exit(2)
        }
        if argument("--widget-family") == "lock" { return [] }
        let quick = CommandLine.arguments.contains("--widget-quick")
        // A mistyped filter must fail loudly: an unknown id silently became the default style
        // (or no geometry at all) and the sweep passed green on work it never rendered.
        if let requested = argument("--widget-style"), WidgetLayoutStyle(rawValue: requested) == nil {
            print("Unknown style \(requested). Styles: \(WidgetLayoutStyle.allCases.map(\.rawValue).joined(separator: ", "))")
            exit(2)
        }
        let styles = argument("--widget-style").flatMap { WidgetLayoutStyle(rawValue: $0) }.map { [$0] } ?? WidgetLayoutStyle.allCases
        let statusFixtures = Dictionary(uniqueKeysWithValues: WidgetStatusState.allCases.map { ("status-\($0)", $0) })
        let styleFixtureNames = DemoScreenshotData.styleFixtureNames + freshnessFixtureNames
        if let requested = argument("--widget-fixture"), !styleFixtureNames.contains(requested), statusFixtures[requested] == nil {
            print("Unknown fixture \(requested). Fixtures: \((styleFixtureNames + statusFixtures.keys.sorted()).joined(separator: ", "))")
            exit(2)
        }
        let fixtures = argument("--widget-fixture").map { styleFixtureNames.contains($0) ? [$0] : [] }
            ?? (quick ? ["claudeCodex"] : styleFixtureNames)
        let geometryNames = argument("--widget-geometry").map { [$0] } ?? ["mac", "ios61"]
        let chosen = geometries.filter { geometryNames.contains($0.name) }
        if chosen.isEmpty {
            print("Unknown geometry \(geometryNames.joined(separator: ", ")). Geometries: \(geometries.map(\.name).joined(separator: ", "))")
            exit(2)
        }

        var jobs: [Job] = []
        for style in styles {
            for fixture in fixtures {
                for geometry in chosen {
                    for family in WidgetFamily.allCases {
                        for dark in [true, false] {
                            jobs.append(Job(style: style, fixture: fixture, family: family, dark: dark, geometry: geometry))
                        }
                    }
                }
            }
            guard !quick else { continue }
            // Color mode, the monochrome and stripped branches (KTD14), and the xxLarge
            // stand-in, on the fixtures where they matter.
            for fixture in ["claudeCodex", "tightClaudeCursor", "staleUnavailable", "dimmed", "pastReset"] where fixtures.contains(fixture) {
                for family in WidgetFamily.allCases {
                    let mac = geometries[0]
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: mac, colorMode: .event))
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: false, geometry: mac, colorMode: .event))
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: mac, rendering: .monochrome))
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: mac, rendering: .stripped))
                }
            }
            // U9/KTD15: pose the pending paths in both geometries and rendering modes.
            for fixture in ["pending", "firstPending", "pendingAll", "pendingPools", "pendingCodex", "pendingCursor"] where fixtures.contains(fixture) {
                for geometry in chosen {
                    for family in WidgetFamily.allCases {
                        for dark in [true, false] {
                            for rendering in [HeadroomWidgetRenderingContext.monochrome, .stripped] {
                                jobs.append(Job(style: style, fixture: fixture, family: family, dark: dark,
                                                geometry: geometry, rendering: rendering))
                            }
                        }
                    }
                }
            }
            for fixture in fixtures {
                for family in WidgetFamily.allCases {
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: geometries[1], shrink: 0.85))
                }
            }
        }
        if !quick {
            // Render the actual status card, not an enabled envelope with no provider rows.
            for fixture in statusFixtures.keys.sorted() where argument("--widget-fixture").map({ $0 == fixture }) ?? true {
                for geometry in chosen {
                    for family in WidgetFamily.allCases {
                        for dark in [true, false] {
                            for rendering in [HeadroomWidgetRenderingContext.fullColor, .monochrome, .stripped] {
                                jobs.append(Job(style: .nestedMeter, fixture: fixture, family: family, dark: dark,
                                                geometry: geometry, rendering: rendering, status: statusFixtures[fixture]))
                            }
                        }
                    }
                }
            }
        }
        return jobs
    }

    // MARK: Render

    private final class ProbeCollector {
        var problems: [String] = []
        func add(_ problem: String) { if !problems.contains(problem) { problems.append(problem) } }
    }

    static func render(_ job: Job) -> (CGImage?, [String]) {
        let envelope = freshnessFixture(job.fixture) ?? DemoScreenshotData.styleFixture(job.fixture, now: now)
        guard job.status != nil || envelope != nil,
              let base = job.geometry.sizes[job.family],
              let margin = job.geometry.margins[job.family]
        else { return (nil, ["missing fixture or geometry"]) }
        let size = CGSize(width: (base.width * job.shrink).rounded(), height: (base.height * job.shrink).rounded())
        let collector = ProbeCollector()
        let tile = tileView(job: job, envelope: envelope, size: size, margin: margin, collector: collector)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = renderScale
        return (renderer.cgImage, collector.problems)
    }

    private static func tileView(job: Job, envelope: WidgetSnapshotEnvelope?, size: CGSize, margin: CGFloat, collector: ProbeCollector) -> some View {
        let shape = RoundedRectangle(cornerRadius: job.geometry.radius, style: .continuous)
        return Group {
            if let status = job.status {
                HeadroomWidgetStatusCard(state: status, family: job.family, scale: .scale(for: job.family))
                    .padding(margin + WidgetMetrics.residualMargin)
            } else if let envelope {
                HeadroomWidgetStyledTile(
                    style: job.style, family: job.family, envelope: envelope, colorMode: job.colorMode,
                    now: now, footerPrefix: job.geometry.footerPrefix, contentMargin: margin,
                    freshness: freshnessTreatment(job)
                ) { id, markSize in
                    ProviderLogoView(providerID: ProviderID(id), size: markSize)
                }
            }
        }
        .background { background(job) }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlayPreferenceValue(HeadroomWidgetProbeKey.self) { anchors in
            GeometryReader { geo in
                let box = CGRect(origin: .zero, size: geo.size).insetBy(dx: margin - 1, dy: margin - 1)
                let _ = anchors.forEach { anchor in
                    let rect = geo[anchor]
                    if rect.width > 0, rect.height > 0, !box.contains(rect.integral.insetBy(dx: 1, dy: 1)) {
                        collector.add("element \(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)) outside content box")
                    }
                }
                Color.clear
            }
        }
        .environment(\.colorScheme, job.dark || job.rendering == .monochrome ? .dark : .light)
        .environment(\.headroomWidgetRenderingOverride, job.rendering)
        .environment(\.headroomWidgetProbesEnabled, true)
        .environment(\.loadingDate, now)
        .padding(12)
        .background(transparent ? Color.clear : job.dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.86, green: 0.89, blue: 0.93))
    }

    // MARK: Freshness fixtures (U13, iOS parity plan KTD15)

    /// The dimmed and past-reset states, posed on the shared style fixtures. They live here,
    /// not in `DemoScreenshotData`, because they are a treatment plus an envelope: the same
    /// envelope renders dimmed only when the host's freshness rule says so.
    static let freshnessFixtureNames = ["dimmed", "dimmedSpend", "pastReset", "pastResetPrimary", "dimmedPastReset"]

    /// When the Mac was last heard from in the dimmed fixtures: past the 60-minute widget floor.
    static let dimmedSince = now.addingTimeInterval(-95 * 60)

    static func freshnessFixture(_ name: String) -> WidgetSnapshotEnvelope? {
        switch name {
        case "dimmed": return DemoScreenshotData.styleFixture("claudeCodex", now: now)
        case "dimmedSpend": return DemoScreenshotData.styleFixture("spend", now: now)
        case "pastReset", "dimmedPastReset":
            // Both providers' 5-hour windows reset while the Mac slept: two notes, the tightest
            // pressure on small.
            return DemoScreenshotData.styleFixture("claudeCodex", now: now).map {
                resetting($0, ago: [ProviderID.claude.raw: ["fiveHour": 20 * 60], ProviderID.codex.raw: ["fiveHour": 14 * 60]])
            }
        case "pastResetPrimary":
            // The hero itself reset: Grok's only pool and one of Cursor's two.
            return DemoScreenshotData.styleFixture("grokCursor", now: now).map {
                resetting($0, ago: [ProviderID.grok.raw: ["other:Weekly": 25 * 60],
                                    ProviderID.cursor.raw: ["other:Other Models": 3 * 3_600]])
            }
        default: return nil
        }
    }

    static func freshnessTreatment(_ job: Job) -> WidgetFreshnessTreatment {
        let host: WidgetFreshnessTreatment.Host = job.geometry.name == "mac" ? .mac : .phone
        let dimmed = ["dimmed", "dimmedSpend", "dimmedPastReset"].contains(job.fixture)
        // A fixed zone keeps the clock copy, and so the overflow findings, the same on every machine.
        return WidgetFreshnessTreatment(now: now, dimmedSince: dimmed ? dimmedSince : nil, host: host,
                                        timeZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_US"))
    }

    /// Moves the named windows' resets (provider ID → window ID → seconds ago) into the past,
    /// with no reading taken since.
    private static func resetting(_ envelope: WidgetSnapshotEnvelope, ago: [String: [String: TimeInterval]]) -> WidgetSnapshotEnvelope {
        let providers = envelope.providers.map { provider in
            var copy = provider
            copy.windows = provider.windows.map { window in
                guard let seconds = ago[provider.id]?[window.id] else { return window }
                return WidgetWindowSummary(
                    kind: window.kind, label: window.label, percentRemaining: window.percentRemaining,
                    utilization: window.utilization, resetSchedule: .scheduled(now.addingTimeInterval(-seconds)),
                    resetLabel: window.resetLabel, observedAt: now.addingTimeInterval(-seconds - 60), severity: window.severity,
                    freshness: window.freshness, billingPeriodDuration: window.billingPeriodDuration)
            }
            return copy
        }
        return WidgetSnapshotEnvelope(generatedAt: envelope.generatedAt, status: envelope.status, providers: providers,
                                      apiSpendProviders: envelope.apiSpendProviders,
                                      widgetProviderSelection: envelope.widgetProviderSelection)
    }

    @ViewBuilder
    private static func background(_ job: Job) -> some View {
        switch job.rendering {
        case .fullColor:
            WidgetPreviewStrip.tileBackground(dark: job.dark)
        case .monochrome:
            // An approximation of a tinted glass tile; the real accented look needs a device.
            LinearGradient(colors: [Color(red: 0.24, green: 0.30, blue: 0.40), Color(red: 0.16, green: 0.21, blue: 0.30)],
                           startPoint: .top, endPoint: .bottom)
        case .stripped:
            Color.black
        }
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    // MARK: Contact sheet

    private static func writeContactSheet(_ rendered: [(Job, String)], lockRendered: [(LockJob, String)], overflows: [String], to url: URL) {
        var html = """
        <!doctype html><meta charset="utf-8"><title>Widget styles — render sweep</title>
        <style>body{background:#0b0d11;color:#ddd;font:13px -apple-system,system-ui;margin:24px}
        h2{margin:28px 0 8px;font-size:16px}h3{margin:16px 0 6px;font-size:12px;color:#999;font-weight:600}
        .row{display:flex;gap:10px;align-items:flex-start;flex-wrap:wrap}img{display:block}
        .bad{color:#ff8a80;white-space:pre-wrap;font:12px ui-monospace,monospace}</style>
        <h1>Widget styles — render sweep</h1>
        """
        html += overflows.isEmpty ? "<p>✓ No overflow.</p>" : "<pre class=bad>\(overflows.joined(separator: "\n"))</pre>"
        let groups = Dictionary(grouping: rendered, by: { "\($0.0.status == nil ? $0.0.style.displayName : "Status card") — \($0.0.fixture)" })
        for key in groups.keys.sorted() {
            html += "<h2>\(key)</h2>"
            let byVariant = Dictionary(grouping: groups[key]!, by: { job, _ in
                "\(job.geometry.name) · \(job.dark ? "dark" : "light") · \(job.colorMode.displayName) · \(job.rendering)\(job.shrink != 1 ? " · shrunk" : "")"
            })
            for variant in byVariant.keys.sorted() {
                html += "<h3>\(variant)</h3><div class=row>"
                for (_, file) in byVariant[variant]!.sorted(by: { "\($0.0.family)" > "\($1.0.family)" }) {
                    html += "<img src=\"\(file)\" style=\"zoom:\(transparent ? "0.25" : "0.5")\">"
                }
                html += "</div>"
            }
        }
        for family in LockScreenWidgetFamily.allCases {
            let items = lockRendered.filter { $0.0.family == family }
            guard !items.isEmpty else { continue }
            html += "<h2>Lock Screen \(family.rawValue)</h2>"
            let sections = Dictionary(grouping: items, by: { "\($0.0.style.rawValue) · \($0.0.geometry.name) · \($0.0.mode.rawValue)" })
            for section in sections.keys.sorted() {
                html += "<h3>\(section)</h3><div class=row>"
                for (job, file) in sections[section]!.sorted(by: { $0.0.fileName < $1.0.fileName }) {
                    html += "<figure style=\"margin:0\"><img src=\"\(file)\" style=\"zoom:\(transparent ? "0.25" : "0.5")\"><figcaption>\(job.source.name) · \(job.providerChoice.rawValue)</figcaption></figure>"
                }
                html += "</div>"
            }
        }
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }
}

// U7 (2026-10-04 Lock Screen plan): the real Lock Screen bodies, every style × size ×
// provider choice × fixture × geometry, normal and Always On, plus privacy, status and demo passes.
private extension WidgetRenderHarness {
    struct LockGeometry {
        let name: String
        let sizes: [LockScreenWidgetFamily: CGSize]
    }

    static var lockGeometries: [LockGeometry] {
        // KTD12: published smallest, 6.1-inch and Pro Max accessory content bounds.
        [
            LockGeometry(name: "iosSE", sizes: [.circle: CGSize(width: 68, height: 68), .rectangle: CGSize(width: 153, height: 68), .inline: CGSize(width: 225, height: 26)]),
            LockGeometry(name: "ios61", sizes: [.circle: CGSize(width: 72, height: 72), .rectangle: CGSize(width: 160, height: 72), .inline: CGSize(width: 234, height: 26)]),
            LockGeometry(name: "ios67", sizes: [.circle: CGSize(width: 76, height: 76), .rectangle: CGSize(width: 172, height: 76), .inline: CGSize(width: 257, height: 26)]),
        ]
    }

    enum LockMode: String, CaseIterable {
        case normal, alwaysOn, privacy

        var redaction: RedactionReasons { self == .privacy ? .privacy : [] }
    }

    /// The source a job renders: a Lock Screen fixture, demo data, or a status state.
    enum LockSource: Equatable {
        case fixture(String)
        case demo
        case status(String)

        var name: String {
            switch self {
            case .fixture(let name): name
            case .demo: "demo"
            case .status(let name): "status_\(name)"
            }
        }

        func state(now: Date) -> IOSWidgetSnapshotState? {
            switch self {
            case .fixture(let name):
                DemoScreenshotData.lockScreenFixture(name, now: now).map(IOSWidgetSnapshotState.content)
            case .demo:
                // KTD10: Lock Screen demo always reads the every-provider envelope.
                .demo(DemoScreenshotData.envelope(for: "fiveProviders"))
            case .status(let name):
                switch name {
                case "disabled": .disabled
                case "setupNeeded": .setupNeeded
                case "waitingForMac": .waitingForMac
                case "corrupt": .corrupt
                case "incompatibleSchema": .incompatibleSchema
                default: nil
                }
            }
        }

        static let statusNames = ["disabled", "setupNeeded", "waitingForMac", "corrupt", "incompatibleSchema"]
    }

    struct LockJob {
        let style: WidgetLayoutStyle
        let family: LockScreenWidgetFamily
        let source: LockSource
        let providerChoice: LockScreenProviderChoice
        let geometry: LockGeometry
        let mode: LockMode

        var fileName: String {
            ["lock", family.rawValue, style.rawValue, source.name, providerChoice.rawValue, geometry.name, mode.rawValue]
                .joined(separator: "-") + ".png"
        }
    }

    static func buildLockJobs() -> [LockJob] {
        if argument("--widget-family") == "home" { return [] }
        if let style = argument("--widget-style"), WidgetLayoutStyle(rawValue: style) == nil {
            print("Unknown style \(style)")
            exit(2)
        }
        let knownSources = DemoScreenshotData.lockScreenFixtureNames + ["demo"] + LockSource.statusNames.map { "status_\($0)" }
        if let fixture = argument("--widget-fixture"), !knownSources.contains(fixture) {
            print("Unknown Lock Screen fixture \(fixture). Fixtures: \(knownSources.joined(separator: ", "))")
            exit(2)
        }
        // Home-only geometry filters add no Lock Screen jobs; lock-only sweeps fail loudly.
        let geometries = argument("--widget-geometry").map { requested in
            lockGeometries.filter { $0.name == requested }
        } ?? lockGeometries
        if geometries.isEmpty {
            if argument("--widget-family") == "lock" {
                print("Unknown Lock Screen geometry. Geometries: \(lockGeometries.map(\.name).joined(separator: ", "))")
                exit(2)
            }
            return []
        }
        let quick = CommandLine.arguments.contains("--widget-quick")
        var sources: [LockSource] = (quick ? ["claudeCodex", "thirdProviderTightest", "staleUnavailable", "grokCursor"]
                                     : DemoScreenshotData.lockScreenFixtureNames).map(LockSource.fixture)
        sources += [.demo] + LockSource.statusNames.map(LockSource.status)
        if let filter = argument("--widget-fixture") { sources = sources.filter { $0.name == filter } }
        let styles = argument("--widget-style").flatMap(WidgetLayoutStyle.init(rawValue:)).map { [$0] } ?? WidgetLayoutStyle.allCases
        // R16: privacy runs on two fixtures; normal and Always On run everywhere.
        let privacySources: [LockSource] = [.fixture("tightClaudeCursor"), .demo]
        var jobs: [LockJob] = []
        for geometry in geometries {
            for family in LockScreenWidgetFamily.allCases {
                for style in styles {
                    for source in sources {
                        // A status form ignores the provider choice; render it once per style.
                        let choices: [LockScreenProviderChoice] = if case .status = source { [.automatic] } else {
                            quick ? [.automatic, .cursor] : LockScreenProviderChoice.allCases
                        }
                        for choice in choices {
                            for mode in LockMode.allCases where mode != .privacy || privacySources.contains(source) {
                                jobs.append(LockJob(style: style, family: family, source: source,
                                                    providerChoice: choice, geometry: geometry, mode: mode))
                            }
                        }
                    }
                }
            }
        }
        return jobs
    }

    static func renderLock(_ job: LockJob) -> (CGImage?, [String]) {
        guard let size = job.geometry.sizes[job.family], let state = job.source.state(now: now)
        else { return (nil, ["missing Lock Screen fixture or geometry"]) }
        let recipe = LockScreenWidgetRecipe(style: job.style, family: job.family,
                                           providerChoice: job.providerChoice, state: state, now: now)
        let collector = ProbeCollector()
        let tile = lockBody(recipe)
            .frame(width: size.width, height: size.height)
            .overlayPreferenceValue(HeadroomLockScreenReadableBounds.self) { anchors in
                GeometryReader { geometry in
                    let _ = anchors.forEach { anchor in
                        if job.family == .circle,
                           !HeadroomLockScreenReadableBounds.fits(geometry[anchor], in: geometry.size) {
                            collector.add("readable content crosses circular clipping boundary")
                        }
                    }
                    Color.clear
                }
            }
            // KTD5: vibrant rendering lightens the wallpaper by each gray's lightness;
            // plus-lighter is the design doc's stand-in for that material mapping.
            .compositingGroup()
            .blendMode(.plusLighter)
            .background { lockWallpaper(size: size) }
            .overlayPreferenceValue(HeadroomWidgetProbeKey.self) { anchors in
                GeometryReader { geometry in
                    let box = CGRect(origin: .zero, size: geometry.size)
                    let _ = anchors.forEach { anchor in
                        let bounds = geometry[anchor]
                        if bounds.width > 0, bounds.height > 0,
                           !box.contains(bounds.integral.insetBy(dx: 1, dy: 1)) {
                            collector.add("element \(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))×\(Int(bounds.height)) outside Lock Screen content box")
                        }
                    }
                    Color.clear
                }
            }
            .environment(\.colorScheme, .dark)
            .environment(\.headroomWidgetProbesEnabled, true)
            .environment(\.isLuminanceReduced, job.mode == .alwaysOn)
            .redacted(reason: job.mode.redaction)
            // KTD12: export padding is outside the probed accessory content box.
            .padding(12)
            .background(transparent ? Color.clear : Color(white: 0.08))
        let renderer = ImageRenderer(content: tile)
        renderer.scale = renderScale
        return (renderer.cgImage, collector.problems)
    }

    /// KTD6/KTD7: the Mac has no asset catalog or `AccessoryWidgetBackground`, so marks are
    /// `ProviderLogoView` silhouettes and the backdrop is a same-weight translucent fill.
    static let lockArt = HeadroomWidgetLockScreenArt(
        // KTD7: the brand-mark primitive masks this original Mac image into one ink.
        mark: { id, size in AnyView(ProviderLogoView(providerID: ProviderID(id), size: size)) },
        accessoryBackground: { AnyView(Color(white: 0.15)) }
    )

    @ViewBuilder
    static func lockBody(_ recipe: LockScreenWidgetRecipe) -> some View {
        let body = HeadroomWidgetLockScreenBody(recipe: recipe, art: lockArt) { image in
            // KTD9: the iOS stepped assets, drawn here from the same Core geometry.
            switch image {
            case .warning:
                Image(systemName: "exclamationmark.circle")
            case .vessel(let level):
                HeadroomWidgetLockScreenVessel(
                    fraction: Double(level) / Double(LockScreenInlineVesselArt.levels.upperBound),
                    geometry: LockScreenInlineVesselArt.geometry)
            }
        }
        if recipe.family == .inline {
            // The system styles inline text; this stands in for its 17 pt semibold line.
            body.font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(white: LockScreenWidgetTokens.fullInk))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            body
        }
    }

    static func lockWallpaper(size: CGSize) -> some View {
        // KTD8/U4: opaque alternating diagonal bands make a real numeral cut-out observable.
        // Skipped inside the Canvas so the default view tree, and its pixels, stay identical.
        let skip = transparent
        return Canvas { context, canvas in
            guard !skip else { return }
            context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(Color(white: 0.12)))
            let band: CGFloat = 8 // Diagnostic pattern crosses every digit, including at 17 pt.
            for offset in stride(from: -canvas.height, through: canvas.width, by: band * 2) {
                var stripe = Path()
                stripe.move(to: CGPoint(x: offset, y: 0))
                stripe.addLine(to: CGPoint(x: offset + band, y: 0))
                stripe.addLine(to: CGPoint(x: offset + band + canvas.height, y: canvas.height))
                stripe.addLine(to: CGPoint(x: offset + canvas.height, y: canvas.height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(Color(white: 0.38)))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// KTD9: `--generate-lock-screen-vessels <LockScreenAssets.xcassets>` writes the eleven inline
/// template imagesets from Core geometry, so the asset art cannot drift from the vessel.
enum LockScreenVesselAssetGenerator {
    static func run(assetCatalog: String) {
        let catalog = URL(fileURLWithPath: (assetCatalog as NSString).expandingTildeInPath, isDirectory: true)
        let manager = FileManager.default
        do {
            for level in LockScreenInlineVesselArt.levels {
                let set = catalog.appendingPathComponent(LockScreenInlineVesselArt.assetName(level: level) + ".imageset", isDirectory: true)
                try manager.createDirectory(at: set, withIntermediateDirectories: true)
                try LockScreenInlineVesselArt.svg(level: level)
                    .write(to: set.appendingPathComponent("vessel.svg"), atomically: true, encoding: .utf8)
                try LockScreenInlineVesselArt.imagesetContents
                    .write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
            }
            print("Wrote \(LockScreenInlineVesselArt.levels.count) vessel imagesets to \(catalog.path)")
        } catch {
            print("✗ Could not write the vessel imagesets")
            exit(1)
        }
    }
}
