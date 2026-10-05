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
/// `--widget-family lock|home` (Lock Screen primitive gallery or unchanged home sweep).
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

        var fileName: String {
            var parts = [style.rawValue, fixture, "\(family)", geometry.name, dark ? "dark" : "light"]
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
        print("Rendered \(rendered.count) home tiles and \(lockRendered.count) Lock Screen primitive tiles to \(outDir.path)")
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
        if let requested = argument("--widget-fixture"), !DemoScreenshotData.styleFixtureNames.contains(requested) {
            print("Unknown fixture \(requested). Fixtures: \(DemoScreenshotData.styleFixtureNames.joined(separator: ", "))")
            exit(2)
        }
        let fixtures = argument("--widget-fixture").map { [$0] } ?? (quick ? ["claudeCodex"] : DemoScreenshotData.styleFixtureNames)
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
            for fixture in ["claudeCodex", "tightClaudeCursor", "staleUnavailable"] where fixtures.contains(fixture) {
                for family in WidgetFamily.allCases {
                    let mac = geometries[0]
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: mac, colorMode: .event))
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: false, geometry: mac, colorMode: .event))
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: mac, rendering: .monochrome))
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: mac, rendering: .stripped))
                }
            }
            for fixture in fixtures {
                for family in WidgetFamily.allCases {
                    jobs.append(Job(style: style, fixture: fixture, family: family, dark: true, geometry: geometries[1], shrink: 0.85))
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
        guard let envelope = DemoScreenshotData.styleFixture(job.fixture, now: now),
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

    private static func tileView(job: Job, envelope: WidgetSnapshotEnvelope, size: CGSize, margin: CGFloat, collector: ProbeCollector) -> some View {
        let shape = RoundedRectangle(cornerRadius: job.geometry.radius, style: .continuous)
        return HeadroomWidgetStyledTile(
            style: job.style, family: job.family, envelope: envelope, colorMode: job.colorMode,
            now: now, footerPrefix: job.geometry.footerPrefix, contentMargin: margin
        ) { id, markSize in
            ProviderLogoView(providerID: ProviderID(id), size: markSize)
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
        .padding(12)
        .background(job.dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.86, green: 0.89, blue: 0.93))
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
        let groups = Dictionary(grouping: rendered, by: { "\($0.0.style.displayName) — \($0.0.fixture)" })
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
        for family in LockScreenWidgetFamily.allCases {
            let items = lockRendered.filter { $0.0.primitive.family == family }
            guard !items.isEmpty else { continue }
            html += "<h2>Lock Screen \(family.rawValue) — primitive gallery</h2>"
            let sections = Dictionary(grouping: items, by: { "\($0.0.fixture) · \($0.0.geometry.name) · \($0.0.mode.rawValue)" })
            for section in sections.keys.sorted() {
                html += "<h3>\(section)</h3><div class=row>"
                for (job, file) in sections[section]!.sorted(by: { $0.0.fileName < $1.0.fileName }) {
                    html += "<figure style=\"margin:0\"><img src=\"\(file)\" style=\"zoom:0.5\"><figcaption>\(job.primitive.rawValue) · \(job.providerID ?? job.providerChoice.rawValue)</figcaption></figure>"
                }
                html += "</div>"
            }
        }
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }
}

// U7 scaffold: these are isolated primitive rigs, replaced by real body jobs after U2.
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

    enum LockPrimitive: String, CaseIterable {
        case mark, numeral, caption, arc, bars, wash, vessel

        var defaultStyle: WidgetLayoutStyle {
            switch self {
            case .bars: .nestedMeter
            case .wash: .liquidLevel
            case .vessel: .vesselHero
            case .mark, .numeral, .caption, .arc: .tightestFirst
            }
        }

        var family: LockScreenWidgetFamily {
            switch self {
            case .mark, .numeral, .arc: .circle
            case .bars, .wash: .rectangle
            case .caption, .vessel: .inline
            }
        }
    }

    enum LockMode: String, CaseIterable {
        case normal, alwaysOn, privacy, placeholder

        var redaction: RedactionReasons {
            switch self {
            case .normal, .alwaysOn: []
            case .privacy: .privacy
            case .placeholder: .placeholder
            }
        }
    }

    struct LockJob {
        let primitive: LockPrimitive
        let fixture: String
        let geometry: LockGeometry
        let mode: LockMode
        var providerID: String?
        var providerChoice: LockScreenProviderChoice = .automatic
        var style: WidgetLayoutStyle = .tightestFirst

        var fileName: String {
            ["lock", primitive.family.rawValue, primitive.rawValue, fixture,
             providerID ?? providerChoice.rawValue, style.rawValue, geometry.name, mode.rawValue]
                .joined(separator: "-") + ".png"
        }
    }

    static func buildLockJobs() -> [LockJob] {
        if argument("--widget-family") == "home" { return [] }
        if let style = argument("--widget-style"), WidgetLayoutStyle(rawValue: style) == nil {
            print("Unknown style \(style)")
            exit(2)
        }
        if let fixture = argument("--widget-fixture"), !DemoScreenshotData.lockScreenFixtureNames.contains(fixture) {
            print("Unknown Lock Screen fixture \(fixture). Fixtures: \(DemoScreenshotData.lockScreenFixtureNames.joined(separator: ", "))")
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
        let fixtures = argument("--widget-fixture").map { [$0] }
            ?? (CommandLine.arguments.contains("--widget-quick")
                ? ["thirdProviderTightest", "staleUnavailable"] : DemoScreenshotData.lockScreenFixtureNames)
        let selectedStyle = argument("--widget-style").flatMap(WidgetLayoutStyle.init(rawValue:))
        var jobs: [LockJob] = []
        for geometry in geometries {
            for mode in LockMode.allCases {
                for id in LockScreenProviderChoice.allCases.compactMap(\.providerID) {
                    jobs.append(LockJob(primitive: .mark, fixture: "marks", geometry: geometry,
                                        mode: mode, providerID: id.raw, style: selectedStyle ?? .tightestFirst))
                }
                for fixture in fixtures {
                    for choice in LockScreenProviderChoice.allCases {
                        for primitive in LockPrimitive.allCases where primitive != .mark {
                            jobs.append(LockJob(primitive: primitive, fixture: fixture, geometry: geometry,
                                                mode: mode, providerChoice: choice,
                                                style: selectedStyle ?? primitive.defaultStyle))
                        }
                    }
                }
            }
        }
        return jobs
    }

    static func renderLock(_ job: LockJob) -> (CGImage?, [String]) {
        guard let size = job.geometry.sizes[job.primitive.family],
              let envelope = DemoScreenshotData.lockScreenFixture(job.fixture == "marks" ? "claudeCodex" : job.fixture, now: now)
        else { return (nil, ["missing Lock Screen fixture or geometry"]) }
        let recipe = LockScreenWidgetRecipe(style: job.style, family: job.primitive.family,
                                           providerChoice: job.providerChoice, state: .content(envelope), now: now)
        let collector = ProbeCollector()
        let tile = lockPrimitive(job, recipe: recipe)
            .frame(width: size.width, height: size.height)
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
            .background(Color(white: 0.08))
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 2
        return (renderer.cgImage, collector.problems)
    }

    @ViewBuilder
    static func lockPrimitive(_ job: LockJob, recipe: LockScreenWidgetRecipe) -> some View {
        if job.primitive == .mark, let id = job.providerID {
            HeadroomWidgetLockScreenBrandMark(providerID: id, size: LockScreenWidgetTokens.liquidMark) { id, size in
                // KTD7: mask the original Mac image; its private Image cannot be templated here.
                ProviderLogoView(providerID: ProviderID(id), size: size)
            }
        } else if let slot = recipe.slots.first {
            switch job.primitive {
            case .mark: EmptyView()
            case .numeral:
                HeadroomWidgetLockScreenNumeral(slot.primary, size: LockScreenWidgetTokens.liquidNumeral)
            case .caption:
                HeadroomWidgetLockScreenCaption(slot.primary)
            case .arc:
                HeadroomWidgetLockScreenArc(slot.primary)
            case .bars:
                HeadroomWidgetLockScreenNestedBars(slot)
            case .wash:
                HeadroomWidgetLockScreenWash(slot.primary)
            case .vessel:
                let size = LockScreenWidgetTokens.vesselNumeral
                let descent = HeadroomWidgetFontMetrics.digitInk(size: size, weight: .semibold).descent
                HStack(alignment: .firstTextBaseline, spacing: (size * LockScreenWidgetTokens.vesselNumeralGapRatio).rounded()) {
                    HeadroomWidgetLockScreenVessel(slot.primary, geometry: HeadroomWidgetLockScreenVessel.geometry(numeralSize: size))
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - descent }
                    HeadroomWidgetLockScreenNumeral(slot.primary, size: size)
                }
                .headroomWidgetProbe()
            }
        } else if let status = recipe.status {
            Text(status.title).font(.system(size: LockScreenWidgetTokens.captionSize))
                .foregroundStyle(Color(white: LockScreenWidgetTokens.secondaryInk))
                .privacySensitive()
                .headroomWidgetProbe()
        }
    }

    static func lockWallpaper(size: CGSize) -> some View {
        // KTD8/U4: opaque alternating diagonal bands make a real numeral cut-out observable.
        Canvas { context, canvas in
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
