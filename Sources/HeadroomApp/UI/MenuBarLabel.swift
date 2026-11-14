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
    /// (`MenuBarMeter.showsMark`). Off by default; nothing is drawn for it yet.
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

    /// The widest plate this pill can draw: a single meter showing "100%", or the bare vessel.
    func widestPillWidth(showsPercentage: Bool) -> CGFloat {
        let vessel = CGFloat(MenuBarLabelGeometry.vesselWidth)
        let text = showsPercentage ? vesselTextGap + widestNumeralWidth : 0
        return 2 * plateHorizontalPadding + vessel + text
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
        let measured = visibleMeters.map { meter -> (meter: MenuBarMeter, textSize: NSSize?) in
            guard showsPercentage, !meter.summary.isNeutral else { return (meter, nil) }
            return (meter, (meter.summary.text as NSString).size(withAttributes: [.font: numeralFont]))
        }
        let layout = MenuBarLabelGeometry.layout(
            items: measured.map {
                MenuBarLabelGeometry.Item(
                    textWidth: $0.textSize.map { Double(ceil($0.width)) },
                    needsAttention: $0.meter.summary.needsAttention
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
