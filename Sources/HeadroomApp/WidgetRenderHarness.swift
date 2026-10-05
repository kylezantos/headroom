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
/// `--widget-quick` (Claude + Codex only, both appearances, macOS and 6.1″).
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
        guard !jobs.isEmpty else {
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
        writeContactSheet(rendered, overflows: overflows + stress, to: outDir.appendingPathComponent("index.html"))
        let report = overflows.isEmpty ? "No overflow.\n" : overflows.joined(separator: "\n") + "\n"
        try? report.write(to: outDir.appendingPathComponent("overflow.txt"), atomically: true, encoding: .utf8)
        try? (stress.joined(separator: "\n") + "\n").write(to: outDir.appendingPathComponent("overflow-shrunk.txt"), atomically: true, encoding: .utf8)
        print("Rendered \(rendered.count) tiles to \(outDir.path)")
        print(overflows.isEmpty ? "✓ No overflow" : "✗ \(overflows.count) overflow finding(s) — see overflow.txt")
        if !stress.isEmpty { print("△ \(stress.count) finding(s) in the shrunk xxLarge stand-in — see overflow-shrunk.txt") }
        exit(overflows.isEmpty ? 0 : 1)
    }

    // MARK: Jobs

    private static func argument(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    static func buildJobs() -> [Job] {
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
        renderer.scale = 2
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
        .background(job.dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.86, green: 0.89, blue: 0.93))
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

    private static func writeContactSheet(_ rendered: [(Job, String)], overflows: [String], to url: URL) {
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
                    html += "<img src=\"\(file)\" style=\"zoom:0.5\">"
                }
                html += "</div>"
            }
        }
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }
}
