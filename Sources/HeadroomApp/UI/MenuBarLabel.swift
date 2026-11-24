import SwiftUI
import AppKit
import HeadroomCore
#if canImport(HeadroomWidgetSharedUI)
import HeadroomWidgetSharedUI
#endif

/// The always-visible menu bar content (R5, UI-03): the compact vessel glyph, with the
/// selected weekly percentage optionally shown beside it. The glyph is tinted by weekly
/// *severity* (healthy → amber → red), not by brand color, so the menu bar means "how
/// close is my weekly allotment to running out" at a glance; a small warning dot appears
/// when a provider needs re-auth, so a dead provider isn't silently invisible. Never a
/// pulse (user's standing rule).
///
/// M10A (Sep 2026): the numeral hard-cuts on every poll, and that is a decision, not a gap.
/// The label is one rasterized `NSImage` swapped whole, so `contentTransition` has nothing to
/// attach to; faking a digit roll would mean re-rasterizing frames on a timer.
///
/// KTD13 (Oct 2026): slosh while a main account is probed, plus a four-frame print on its
/// first live reading. The level stays fixed and the numeral still hard-cuts (M10A).
struct MenuBarLabel: View {
    /// Which appearance the label paints for (L1A).
    enum Appearance {
        /// Follow the live menu bar. Only the real status item should use this.
        case menuBar
        /// Always the dark palette. The Settings specimens sit on a fixed dark plate, so
        /// they must not follow a light menu bar into black ink on that plate.
        case pinnedDark
    }

    let meters: [MenuBarMeter]
    let showsPercentage: Bool
    var appearance: Appearance = .pinnedDark
    /// Providers whose pill sloshes (`UsageStore.menuBarUpdatingProviders`). Only the real
    /// status item passes any; the Settings specimens stay still.
    var updatingProviders: Set<ProviderID> = []
    var automatic = false
    /// Appearance is independent: Settings follows the live palette but always stays still.
    var motionEnabled = false
    var sourceAccounts: [ProviderID: AccountKey] = [:]
    var probeEndTimes: [ProviderID: Date] = [:]
    /// The status item always draws `.standard`; a narrow Settings pill card passes `.compact`.
    var metrics: MenuBarPillMetrics = .standard
    /// CA-MB1 (KTD7): whether explicit pills carry their provider's mark
    /// (`UsageStore.menuBarShowsMarks`). The automatic summary is marked regardless
    /// (`MenuBarMeter.showsMark`). Off by default. The mark is drawn into the same image as
    /// the vessel and numeral, so it hard-cuts with them on the same poll (M10A).
    var showsMarks = false

    @State private var slosh = MenuBarSlosh()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadingDate) private var pinnedDate

    var body: some View {
        // L1A: the palette is chosen from the *menu bar's* effective appearance, not the
        // system's — a light system appearance over a dark wallpaper still gets a dark menu
        // bar, and a light wallpaper turns the bar light while the system stays dark. Every
        // color in `MenuBarPalette` is an explicit constant, so the render never depends on
        // which appearance SwiftUI happens to rasterize `Image(nsImage:)` against.
        let palette = MenuBarPalette(isDarkMenuBar: isDarkMenuBar)
        let presentations = Dictionary(meters.map { meter in
            (MenuBarSlosh.key(for: meter, automatic: automatic), motionEnabled
                ? slosh.presentation(for: meter, automatic: automatic, at: pinnedDate ?? slosh.frameDate)
                : MenuBarSlosh.staticPresentation(for: meter))
        }, uniquingKeysWith: { _, latest in latest })
        let result = MenuBarLabelRenderer.render(meters: meters, showsPercentage: showsPercentage,
            palette: palette, automatic: automatic, presentations: presentations, metrics: metrics,
            showsMarks: showsMarks)
        Image(nsImage: result.image)
            .accessibilityLabel(result.accessibilityLabel)
            .help(result.tooltip)
            .onChange(of: motionInput, initial: true) { _, input in
                guard input.enabled else { slosh.suspend(); return }
                slosh.update(meters: input.meters, automatic: input.automatic, updating: input.updating,
                             reduceMotion: input.reduceMotion, sourceAccounts: input.sources,
                             probeEndTimes: input.ends, clockEnabled: input.pinnedDate == nil, at: input.pinnedDate ?? Date())
            }
            .onDisappear { slosh.suspend() }
    }

    private struct MotionInput: Equatable {
        let meters: [MenuBarMeter]
        let automatic: Bool
        let enabled: Bool
        let updating: Set<ProviderID>
        let reduceMotion: Bool
        let sources: [ProviderID: AccountKey]
        let ends: [ProviderID: Date]
        let pinnedDate: Date?
    }
    private var motionInput: MotionInput {
        MotionInput(meters: meters, automatic: automatic, enabled: motionEnabled,
                    updating: updatingProviders, reduceMotion: reduceMotion, sources: sourceAccounts, ends: probeEndTimes, pinnedDate: pinnedDate)
    }

    /// Read inside `body` so SwiftUI's observation tracking re-renders the image the moment
    /// the menu bar flips appearance.
    private var isDarkMenuBar: Bool {
        switch appearance {
        case .pinnedDark: true
        case .menuBar: MenuBarAppearanceMonitor.shared.isDarkMenuBar
        }
    }
}

/// The real status item's label, reading the store from its own body (ML1, 2026-10-03 perf
/// bench). `MenuBarExtra`'s label closure runs inside `App.body`, so reading the meters there
/// made every probe start, probe end and merge re-run the whole scene — rebuilding the
/// popover and re-rendering whichever Settings pane was open (~50–124ms at 20 accounts).
struct MenuBarStatusLabel: View {
    let store: UsageStore

    var body: some View {
        let _ = BenchCounters.hit("MenuBarStatusLabel")
        let sources = Dictionary(uniqueKeysWithValues: store.providerOrder.map {
            ($0, store.displayPrimaryKey(for: $0) ?? AccountKey(providerID: $0, accountID: .primary))
        })
        let ends = store.lastProbeEndTimes
        MenuBarLabel(
            meters: store.menuBarMeters,
            showsPercentage: store.showMenuBarPercentage,
            // L1A: only the real status item follows the live menu bar. The Settings
            // specimens follow that same palette with their motion explicitly disabled.
            appearance: .menuBar,
            updatingProviders: store.menuBarUpdatingProviders,
            automatic: store.menuBarFillSource.providerIDs == nil,
            motionEnabled: true,
            sourceAccounts: sources,
            probeEndTimes: Dictionary(uniqueKeysWithValues: sources.compactMap { provider, key in
                ends[key].map { (provider, $0) }
            }),
            showsMarks: store.menuBarShowsMarks
        )
    }
}

/// The live appearance of the menu bar itself (L1A).
///
/// `MenuBarExtra` hands out no `NSStatusItem`, so there is no supported handle on the status
/// item's button. The status item does live in an `NSStatusBarWindow` inside this process,
/// though, and that window's appearance is the very thing the old dark pin was working
/// around: the system sets it from the menu bar's backplate, so it reports dark over a dark
/// wallpaper even when the system appearance is light. We find that window by class name and
/// KVO its `effectiveAppearance`.
///
/// `NSApp.effectiveAppearance` is deliberately **not** the source: it is the process
/// appearance (which Headroom's own theme switch pins), and it would answer "light" for the
/// light-system / dark-menu-bar case that this decision exists to fix. It is used only as a
/// first-paint fallback before the status window exists.
@MainActor
@Observable
final class MenuBarAppearanceMonitor {
    static let shared = MenuBarAppearanceMonitor()

    /// Defaults to dark: that is what the menu bar is in most of the day, and it is the
    /// palette that shipped, so the pre-attach frame is never a regression.
    private(set) var isDarkMenuBar = true

    @ObservationIgnored private weak var observedWindow: NSWindow?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var attachTask: Task<Void, Never>?

    private init() {}

    /// Begin (or re-begin) tracking. Safe to call repeatedly — the status item's window is
    /// created after the scene's first paint, and can be torn down and rebuilt, so a lost
    /// window simply restarts the search.
    func start() {
        guard observedWindow == nil else { return }
        attachTask?.cancel()
        attachTask = Task { [weak self] in
            // The status window shows up a runloop turn or two after the scene appears.
            // Poll briefly, then back off; give up rather than spin forever, leaving the
            // process-appearance fallback in place.
            for attempt in 0..<40 {
                guard let self, !Task.isCancelled else { return }
                if self.bind() { return }
                try? await Task.sleep(for: .milliseconds(attempt < 10 ? 100 : 500))
            }
        }
    }

    /// Re-read the current appearance, re-attaching if the status window was replaced.
    /// Called on OS theme flips, which can swap the menu bar backplate without the KVO
    /// having a window to fire from yet.
    func refresh() {
        if observedWindow == nil {
            start()
        } else {
            readCurrentAppearance()
        }
    }

    private func bind() -> Bool {
        guard let window = Self.statusBarWindow() else {
            readCurrentAppearance()
            return false
        }
        observedWindow = window
        // `.initial` gives us the first value synchronously; later fires cover wallpaper
        // changes, display moves, and OS theme flips.
        observation = window.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.readCurrentAppearance() }
        }
        return true
    }

    private func readCurrentAppearance() {
        guard let window = observedWindow else {
            isDarkMenuBar = Self.isDark(NSApplication.shared.effectiveAppearance)
            return
        }
        // Measured on macOS 26 (2026-09-04): the status window carries no explicit
        // `appearance`, and its `effectiveAppearance` is NOT the inherited process one — it
        // reported `NSAppearanceNameVibrantLight` and then `VibrantDark` while
        // `NSApp.appearance` sat pinned at `NSAppearanceNameDarkAqua` throughout. So this is
        // genuinely the menu bar's backplate and Headroom's own theme pin does not taint it.
        // `window.appearance` is still preferred if the system ever starts setting one.
        // The light→dark settle took ~45ms at launch, before the item is drawn.
        isDarkMenuBar = Self.isDark(window.appearance ?? window.effectiveAppearance)
    }

    private static func statusBarWindow() -> NSWindow? {
        NSApplication.shared.windows.first { String(describing: type(of: $0)) == "NSStatusBarWindow" }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

/// The type and spacing a menu-bar pill is drawn with. The status item always uses
/// `standard`; only a Settings pill card narrower than the standard pill takes `compact`,
/// chosen by `PillShelfModel.cardGeometry` (KTD14 follow-up: six cards share one row).
struct MenuBarPillMetrics: Equatable, Sendable {
    /// The percentage's point size (monospaced digits, medium).
    let numeralSize: CGFloat
    /// The gap between the vessel and its percentage.
    let vesselTextGap: CGFloat
    /// The preview plate's inset on each side of the label.
    let plateHorizontalPadding: CGFloat
    /// "100%", the widest value a pill shows, at `numeralSize`, rounded up the way the
    /// renderer rounds it. `MenuBarPillMetricsTests` measures the real font against it.
    let widestNumeralWidth: CGFloat

    static let standard = MenuBarPillMetrics(
        numeralSize: 13.5,
        vesselTextGap: CGFloat(MenuBarLabelGeometry.vesselTextGap),
        plateHorizontalPadding: 7,
        widestNumeralWidth: 39
    )

    /// One deliberate step down: about 80% type, with the plate and gap tightened to match,
    /// so "100%" fits a 62pt card with room to spare.
    static let compact = MenuBarPillMetrics(
        numeralSize: 11,
        vesselTextGap: 4,
        plateHorizontalPadding: 4,
        widestNumeralWidth: 33
    )

    /// The widest plate this pill can draw: a single meter showing "100%", or the bare vessel,
    /// plus its provider mark's box and gap when it carries one (CA-MB1).
    func widestPillWidth(showsPercentage: Bool, showsMark: Bool = false) -> CGFloat {
        let vessel = CGFloat(MenuBarLabelGeometry.vesselWidth)
        let text = showsPercentage ? vesselTextGap + widestNumeralWidth : 0
        let mark = showsMark ? CGFloat(MenuBarLabelGeometry.markBoxSize + MenuBarLabelGeometry.markVesselGap) : 0
        return 2 * plateHorizontalPadding + mark + vessel + text
    }
}

@MainActor
struct MenuBarLabelRenderResult {
    let image: NSImage
    let accessibilityLabel: String
    let tooltip: String
}

@MainActor
enum MenuBarLabelRenderer {
    // PB5: the numbers and the layout pass both live in `MenuBarLabelGeometry` now, so the
    // measured image width and the drawn positions cannot disagree (they did: the attention
    // dot's 3pt overhang was drawn but never measured, clipping it on the trailing mark).
    private static let height = CGFloat(MenuBarLabelGeometry.height)
    private static let vesselWidth = CGFloat(MenuBarLabelGeometry.vesselWidth)
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: MenuBarPillMetrics.standard.numeralSize, weight: .medium)
    private static let compactFont = NSFont.monospacedDigitSystemFont(ofSize: MenuBarPillMetrics.compact.numeralSize, weight: .medium)

    private static func font(for metrics: MenuBarPillMetrics) -> NSFont {
        switch metrics.numeralSize {
        case MenuBarPillMetrics.standard.numeralSize: font
        case MenuBarPillMetrics.compact.numeralSize: compactFont
        default: NSFont.monospacedDigitSystemFont(ofSize: metrics.numeralSize, weight: .medium)
        }
    }

    static func render(
        meters: [MenuBarMeter],
        showsPercentage: Bool,
        palette: MenuBarPalette,
        automatic: Bool = false,
        presentations: [MenuBarSlosh.MeterKey: MenuBarSlosh.Presentation] = [:],
        metrics: MenuBarPillMetrics = .standard,
        showsMarks: Bool = false
    ) -> MenuBarLabelRenderResult {
        let numeralFont = font(for: metrics)
        let visibleMeters = meters.isEmpty ? [MenuBarMeter(summary: .neutral, fill: nil)] : meters
        let measured = visibleMeters.map { meter -> (meter: MenuBarMeter, textSize: NSSize?, mark: NSImage?) in
            // CA-MB1/CA-MB2 (KTD7): the automatic summary is marked whatever `showsMarks`
            // says; a provider with no artwork reserves no box.
            let mark = meter.showsMark(explicitPillsMarked: showsMarks)
                ? meter.providerID.flatMap { BrandIconImage.vector(for: $0, isDark: palette.isDarkMenuBar) }
                : nil
            guard showsPercentage, !meter.summary.isNeutral else { return (meter, nil, mark) }
            return (meter, (meter.summary.text as NSString).size(withAttributes: [.font: numeralFont]), mark)
        }
        let layout = MenuBarLabelGeometry.layout(
            items: measured.map {
                MenuBarLabelGeometry.Item(
                    textWidth: $0.textSize.map { Double(ceil($0.width)) },
                    needsAttention: $0.meter.summary.needsAttention,
                    hasMark: $0.mark != nil
                )
            },
            showsPercentage: showsPercentage,
            vesselTextGap: Double(metrics.vesselTextGap)
        )
        let image = NSImage(
            size: NSSize(width: layout.imageWidth, height: height),
            flipped: false
        ) { bounds in
            for (item, placement) in zip(measured, layout.placements) {
                if let mark = item.mark, let markX = placement.markX, let provider = item.meter.providerID {
                    drawMark(mark, providerID: provider, boxX: bounds.minX + CGFloat(markX), palette: palette)
                }
                let x = bounds.minX + CGFloat(placement.vesselX)
                let vessel = VesselGlyph.menuBarImage(
                    fill: item.meter.fill,
                    severity: item.meter.summary.severity,
                    isNeutral: item.meter.summary.isNeutral,
                    palette: palette,
                    wavePhase: presentations[MenuBarSlosh.key(for: item.meter, automatic: automatic)]?.wavePhase,
                    ink: presentations[MenuBarSlosh.key(for: item.meter, automatic: automatic)]?.ink
                        ?? MenuBarSlosh.staticPresentation(for: item.meter).ink
                )
                vessel.draw(in: NSRect(x: x, y: 0, width: vesselWidth, height: height))
                if item.meter.summary.needsAttention {
                    // The dot is a graphic mark, not ink, so it stays on the severity fill
                    // tier — critical red in whichever appearance the menu bar is (L1A).
                    let diameter = CGFloat(MenuBarLabelGeometry.attentionDotDiameter)
                    palette.liquid(for: .critical).menuBarColor.setFill()
                    NSBezierPath(ovalIn: NSRect(
                        x: x + vesselWidth - CGFloat(MenuBarLabelGeometry.attentionDotInset),
                        y: height - diameter,
                        width: diameter,
                        height: diameter
                    )).fill()
                }
                if let textSize = item.textSize, let textX = placement.textX {
                    let textHeight = ceil(textSize.height)
                    let rect = NSRect(
                        x: bounds.minX + CGFloat(textX),
                        y: (height - textHeight) / 2,
                        width: ceil(textSize.width),
                        height: textHeight
                    )
                    item.meter.summary.text.draw(in: rect, withAttributes: [
                        .font: numeralFont,
                        .foregroundColor: textColor(for: item.meter.summary, palette: palette)
                    ])
                }
            }
            return true
        }
        image.isTemplate = false
        let accessibilityLabel = accessibilityLabel(for: visibleMeters)
        return MenuBarLabelRenderResult(
            image: image,
            accessibilityLabel: accessibilityLabel,
            tooltip: accessibilityLabel
        )
    }

    /// CA-MB1 (KTD7): one provider mark, drawn as single ink. The artwork only supplies
    /// coverage; `sourceIn` replaces its colours (Claude's orange, Codex's gradient, the
    /// monochrome greys) with `markInk`, so severity stays the only colour in the bar. Drawn
    /// from the vector at the bar's backing scale, so 1× and 2× each rasterize it natively.
    /// The ink takes the menu bar's own per-provider metrics
    /// (`MenuBarLabelGeometry.markMetrics`, never the popover's `HeadroomBrandMark` size), is
    /// centred on the vessel's middle (the image's vertical middle) plus the metrics' nudge,
    /// and has its edges snapped to the pixel grid of the scale being drawn, so OpenCode's
    /// block and Cursor's cube land crisp at 1× and the ink never leaves its box. It reads no
    /// slosh or print state, so it never moves.
    private static func drawMark(_ mark: NSImage, providerID: ProviderID, boxX: CGFloat, palette: MenuBarPalette) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let box = CGFloat(MenuBarLabelGeometry.markBoxSize)
        let metrics = MenuBarLabelGeometry.markMetrics(for: providerID.raw)
        let ink = metrics.inkSize(aspect: HeadroomBrandMark.inkAspect(for: providerID.raw))
        let scale = max(1, abs(context.userSpaceToDeviceSpaceTransform.a))
        // CA-MB1: the outline is Retina-only; on a 1× bar it closed Grok's ring.
        let reach = scale >= 1.5 ? CGFloat(metrics.thickening) / 2 : 0
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let centredX = boxX + (box - CGFloat(ink.width)) / 2
        let centredY = (height - CGFloat(ink.height)) / 2 + CGFloat(metrics.verticalNudge)
        var minX = snap(centredX), maxX = snap(centredX + CGFloat(ink.width))
        // Rounding may push an ink that fills its box past an edge (the outline included):
        // slide it back inside, off the grid, rather than squash it.
        let low = boxX + reach, high = boxX + box - reach
        if maxX > high { minX -= maxX - high; maxX = high }
        if minX < low { maxX = min(high, maxX + low - minX); minX = low }
        let minY = snap(centredY), maxY = snap(centredY + CGFloat(ink.height))
        let rect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        context.saveGState()
        // The resampled outline's filter tail would otherwise reach a pixel past the box.
        context.clip(to: CGRect(x: boxX, y: 0, width: box, height: height))
        context.beginTransparencyLayer(in: rect.insetBy(dx: -1, dy: -1), auxiliaryInfo: nil)
        if reach > 0, let outline = outline(of: mark, providerID: providerID, isDark: palette.isDarkMenuBar,
                                            size: rect.size, reach: reach) {
            context.interpolationQuality = .high
            context.draw(outline.image, in: rect.insetBy(dx: -outline.pad, dy: -outline.pad))
        } else {
            mark.draw(in: rect)
        }
        if providerID == .codex, scale < 1.5 {
            openCodexPrompt(in: rect, context: context)
        }
        context.setBlendMode(.sourceIn)
        context.setFillColor(palette.markInk.menuBarColor.cgColor)
        context.fill(rect.insetBy(dx: -1, dy: -1))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Pixels per point the outline is built at before it is drawn down to the bar's scale.
    private static let outlineSupersample: CGFloat = 8

    /// The label is re-rasterized on every slosh frame, so each outline is built once per
    /// provider, bar appearance and size.
    private struct OutlineKey: Hashable {
        let providerID: String
        let isDark: Bool
        let width: CGFloat
        let height: CGFloat
        let reach: CGFloat
    }
    private static var outlines: [OutlineKey: (image: CGImage, pad: CGFloat)] = [:]

    private static func outline(of mark: NSImage, providerID: ProviderID, isDark: Bool, size: NSSize,
                                reach: CGFloat) -> (image: CGImage, pad: CGFloat)? {
        let key = OutlineKey(providerID: providerID.raw, isDark: isDark, width: size.width, height: size.height, reach: reach)
        if let cached = outlines[key] { return cached }
        let built = dilatedCoverage(of: mark, size: size, reach: reach)
        outlines[key] = built
        return built
    }

    /// CA-MB1: the artwork's coverage grown by `reach` points on every side, a same-ink
    /// outline of `2 × reach`. Built as a true dilation (the maximum coverage within a disc)
    /// on an 8× alpha mask and drawn down, because stacking offset copies of the artwork
    /// compounds its antialiased edges into solid ink and thickens far more than `reach`.
    /// `pad` is how far the returned image extends past the artwork's rect, in points.
    private static func dilatedCoverage(of mark: NSImage, size: NSSize, reach: CGFloat) -> (image: CGImage, pad: CGFloat)? {
        let ss = outlineSupersample
        let radius = Int((reach * ss).rounded())
        guard radius > 0 else { return nil }
        let pad = radius + 1
        let width = Int((size.width * ss).rounded()) + 2 * pad
        let height = Int((size.height * ss).rounded()) + 2 * pad
        // RGBA because AppKit draws nothing into an alpha-only context; only alpha is read.
        let rgb = CGColorSpaceCreateDeviceRGB(), info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let source = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: rgb, bitmapInfo: info)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: source, flipped: false)
        mark.draw(in: NSRect(x: CGFloat(pad), y: CGFloat(pad), width: CGFloat(width - 2 * pad), height: CGFloat(height - 2 * pad)))
        NSGraphicsContext.restoreGraphicsState()
        guard let input = source.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var offsets: [(Int, Int)] = []
        for dy in -radius...radius {
            for dx in -radius...radius where dx * dx + dy * dy <= radius * radius { offsets.append((dx, dy)) }
        }
        var output = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var peak: UInt8 = 0
                for (dx, dy) in offsets {
                    let sx = x + dx, sy = y + dy
                    guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                    peak = max(peak, input[(sy * width + sx) * 4 + 3])
                }
                for channel in 0..<4 { output[(y * width + x) * 4 + channel] = peak }
            }
        }
        let image = output.withUnsafeMutableBytes { bytes -> CGImage? in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: rgb, bitmapInfo: info)?.makeImage()
        }
        return image.map { ($0, CGFloat(pad) / ss) }
    }

    /// CA-MB1: Codex's `>_` cut-out is 0.6 artwork units wide, about 0.7pt in the 13pt slot,
    /// so on a 1× bar it rasterizes to grey speckles and the mark reads as a plain blob. On
    /// 1× only, the chevron and underscore are knocked out again at `codexPromptStroke`
    /// points, the chevron opened a little wider than the artwork's (its 0.8pt depth
    /// collapsed into a vertical bar), which keeps the prompt open as whole pixels. 2× draws
    /// the artwork untouched. Points are the artwork's own coordinates (its viewBox is
    /// 0.498…9.502 on both axes, y down).
    private static let codexPromptStroke: CGFloat = 1.15

    private static func openCodexPrompt(in rect: NSRect, context: CGContext) {
        let origin = 0.498, span = 9.0039
        func point(_ u: Double, _ v: Double) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat((u - origin) / span) * rect.width,
                    y: rect.maxY - CGFloat((v - origin) / span) * rect.height)
        }
        let prompt = CGMutablePath()
        prompt.move(to: point(2.70, 3.80))
        prompt.addLine(to: point(3.85, 5.05))
        prompt.addLine(to: point(2.70, 6.30))
        prompt.move(to: point(5.27, 6.27))
        prompt.addLine(to: point(7.09, 6.27))
        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineWidth(codexPromptStroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(prompt)
        context.strokePath()
        context.restoreGState()
    }

    private static func accessibilityLabel(for meters: [MenuBarMeter]) -> String {
        if meters.count == 1, let summary = meters.first?.summary, summary.needsAttention, summary.isNeutral {
            return "AI usage — a provider needs sign-in"
        }
        let parts = meters.compactMap { meter -> String? in
            guard meter.summary.detail != nil else { return nil }
            return tooltip(for: meter.summary)
        }
        return parts.isEmpty ? "AI usage" : parts.joined(separator: "; ")
    }

    private static func tooltip(for summary: MenuBarSummary) -> String {
        guard let detail = summary.detail else {
            return summary.needsAttention ? "AI usage — a provider needs sign-in" : "AI usage"
        }
        let term = (summary.percentageMode ?? .remaining).term
        let base = summary.isNeutral ? detail : "\(detail), \(summary.text) \(term)"
        return summary.needsAttention ? "\(base), needs sign-in" : base
    }

    /// Percentage ink (L1A): the menu bar's own label color, except where the numeral is
    /// itself the warning — then it takes the severity *text* tier for this appearance.
    private static func textColor(for summary: MenuBarSummary, palette: MenuBarPalette) -> NSColor {
        if !summary.isNeutral, summary.severity != .healthy {
            return palette.severityInk(for: summary.severity).menuBarColor
        }
        if summary.needsAttention {
            return palette.severityInk(for: .critical).menuBarColor
        }
        return palette.ink.menuBarColor
    }
}

// Explicit sRGB conversions for the menu bar render. Deliberately *not* dynamic
// `NSColor`s (L1A): the label is rasterized into an `NSImage`, and a dynamic color would
// resolve against whichever appearance the rasterizer is in rather than the menu bar's.
extension HeadroomRGBColor {
    var menuBarColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }
}

extension HeadroomTint {
    var menuBarColor: NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: opacity)
    }
}
