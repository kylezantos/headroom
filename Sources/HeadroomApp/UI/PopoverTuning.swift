import AppKit
import Combine
import HeadroomCore
import SwiftUI
#if HEADROOM_DIALKIT
import DialkitmacOS
import DialkitmacOSAgent
#endif

#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif

/// Local tuning seam for DialKit (https://github.com/mikelikesdesign/dialkit-macos).
/// Defaults equal the shipped literals (`HeadroomTuning`), so without `HEADROOM_DIALKIT`
/// nothing changes. Build with `HEADROOM_DIALKIT=1 swift run Headroom --demo …`.
/// Live app state the dials can drive (meter style, percentage mode), so springs have
/// something to animate.
struct PopoverLiveState: Codable, Equatable {
    var format = MeterStyle.default.format.rawValue
    var shape = MeterStyle.default.shape.rawValue
    var fill = MeterStyle.default.fill.rawValue
    var percentageMode = UsagePercentageMode.remaining.rawValue
}

@MainActor
final class PopoverTuningModel: ObservableObject {
    static let shared = PopoverTuningModel()

    @Published private(set) var values = HeadroomTuning()
    /// PC2: which surface the popover draws, and its glass tint. Always `.shipping` without DialKit.
    @Published private(set) var surface = PopoverSurfaceSettings.shipping

    #if HEADROOM_DIALKIT
    private weak var store: UsageStore?

    private let panel = DialPanelState(
        id: UUID(uuidString: "6E0C2A51-6E1B-4C0B-9E4B-5A1D3C7F2B10")!,
        name: "Popover",
        initial: HeadroomTuning(),
        controls: PopoverTuningModel.controls
    )

    private let livePanel = DialPanelState(
        id: UUID(uuidString: "0B7E4C2D-9A13-4F58-8B61-2C4E7D9A1F35")!,
        name: "Meter style",
        initial: PopoverLiveState(),
        controls: [
            .select("format", keyPath: \.format, options: GaugeFormat.allCases.map { DialOption($0.rawValue, label: $0.label) }),
            .select("shape", keyPath: \.shape, options: GaugeShape.allCases.map { DialOption($0.rawValue, label: $0.label) }),
            .select("fill", keyPath: \.fill, options: GaugeFill.allCases.map { DialOption($0.rawValue, label: $0.rawValue) }),
            .select("percentageMode", keyPath: \.percentageMode, label: "Show", options: [
                DialOption("remaining", label: "Remaining"), DialOption("used", label: "Used"),
            ]),
        ]
    )

    private let surfacePanel = DialPanelState(
        id: UUID(uuidString: "6F0B7C1E-4E52-4C61-9C1D-2B8F3A0D5E11")!,
        name: "Surface",
        initial: PopoverSurfaceState(),
        controls: [
            .select("surface", keyPath: \.surface, options: [
                DialOption("headroom", label: "Headroom shell"),
                DialOption("system", label: "System glass"),
            ]),
            .group("tint", label: "Tint (both surfaces)", children: [
                .color("lightTint", keyPath: \.lightTint),
                .slider("lightTintOpacity", keyPath: \.lightTintOpacity, range: 0...1, step: 0.01),
                .color("darkTint", keyPath: \.darkTint),
                .slider("darkTintOpacity", keyPath: \.darkTintOpacity, range: 0...1, step: 0.01),
            ]),
            .group("headroomShell", label: "Headroom Shell", children: [
                .select("glass", keyPath: \.glass, options: [
                    DialOption("regular", label: "Regular"),
                    DialOption("clear", label: "Clear"),
                ]),
                .toggle("reshapeHostChrome", keyPath: \.reshapeHostChrome, label: "Reshape Host Chrome (PC2)"),
                .toggle("windowShadow", keyPath: \.windowShadow, label: "Window Shadow"),
            ]),
            .group("customShadow", label: "Custom Shadow (PS1)", children: [
                .toggle("customShadow", keyPath: \.customShadow, label: "Custom Shadow"),
                .slider("customShadowOpacity", keyPath: \.customShadowOpacity, label: "Darkness", range: 0...1, step: 0.01),
                .slider("customShadowRadius", keyPath: \.customShadowRadius, label: "Softness", range: 0...40, step: 0.5, unit: "pt"),
                .slider("customShadowY", keyPath: \.customShadowY, label: "Offset Y", range: -10...30, step: 0.5, unit: "pt"),
            ]),
        ]
    )

    private static var controls: [DialControl<HeadroomTuning>] {
        let weights = HeadroomTuning.weightOptions
        return [
            .group("shell", children: [
                .slider("shellWidth", keyPath: \.shellWidth, range: 300...480, step: 1, unit: "pt"),
                .slider("shellMargin", keyPath: \.shellMargin, range: 0...40, step: 0.5, unit: "pt"),
                .slider("shellCornerRadius", keyPath: \.shellCornerRadius, range: 0...40, step: 0.5, unit: "pt"),
                .slider("cardGap", keyPath: \.cardGap, range: 0...48, step: 1, unit: "pt"),
                .slider("headerGap", keyPath: \.headerGap, range: 0...40, step: 1, unit: "pt"),
            ]),
            .group("card", children: [
                .slider("cardPadding", keyPath: \.cardPadding, range: 0...32, step: 0.5, unit: "pt"),
                .slider("cardCornerRadius", keyPath: \.cardCornerRadius, range: 0...28, step: 0.5, unit: "pt"),
                .slider("accountGap", keyPath: \.accountGap, range: 0...48, step: 1, unit: "pt"),
                .slider("identityToMetersGap", keyPath: \.identityToMetersGap, label: "Title → Meters", range: 0...20, step: 0.5, unit: "pt"),
                .slider("microRowGap", keyPath: \.microRowGap, label: "Micro Row Gap", range: 0...30, step: 0.5, unit: "pt"),
                .slider("fullRowGap", keyPath: \.fullRowGap, label: "Full Row Gap", range: 0...30, step: 0.5, unit: "pt"),
            ]),
            .group("identity", label: "Account Title", children: [
                .slider("titleSize", keyPath: \.titleSize, range: 10...24, step: 0.5, unit: "pt"),
                .slider("titleKerning", keyPath: \.titleKerning, range: -1...1, step: 0.05),
                .select("titleWeight", keyPath: \.titleWeight, options: weights),
                .slider("markSlotWidth", keyPath: \.markSlotWidth, label: "Logo Slot", range: 8...28, step: 0.5, unit: "pt"),
                .slider("markGap", keyPath: \.markGap, label: "Logo Gap", range: 0...16, step: 0.5, unit: "pt"),
            ]),
            .group("meter", label: "Meter Row", children: [
                .slider("labelSize", keyPath: \.labelSize, range: 9...18, step: 0.5, unit: "pt"),
                .select("labelWeight", keyPath: \.labelWeight, options: weights),
                .slider("resetSize", keyPath: \.resetSize, range: 8...16, step: 0.5, unit: "pt"),
                .slider("percentSize", keyPath: \.percentSize, range: 10...30, step: 0.5, unit: "pt"),
                .select("percentWeight", keyPath: \.percentWeight, options: weights),
                .slider("meterGap", keyPath: \.meterGap, label: "Inline Gap", range: 0...16, step: 0.5, unit: "pt"),
                .slider("fullLabelToGauge", keyPath: \.fullLabelToGauge, label: "Full Label → Gauge", range: 0...20, step: 0.5, unit: "pt"),
                .slider("gaugeLengthScale", keyPath: \.gaugeLengthScale, label: "Micro Gauge Length", range: 0.5...2, step: 0.05, unit: "×"),
                .slider("gaugeHeightScale", keyPath: \.gaugeHeightScale, label: "Gauge Height", range: 0.5...3, step: 0.05, unit: "×"),
            ]),
            .group("tileDark", label: "Tile · Dark", collapsed: true, children: [
                .slider("darkFillTop", keyPath: \.darkFillTop, range: 0...0.3, step: 0.005),
                .slider("darkFillBottom", keyPath: \.darkFillBottom, range: 0...0.3, step: 0.005),
                // CA-P2: the sliders stop at rule 8's 0.15 ceiling, so a tuning pass cannot
                // dial the bright rim back in.
                .slider("darkRing", keyPath: \.darkRing, label: "Ring", range: 0...HeadroomTileEdgeValues.darkRimCeiling, step: 0.005),
                .slider("darkRimTop", keyPath: \.darkRimTop, label: "Top Lip", range: 0...HeadroomTileEdgeValues.darkRimCeiling, step: 0.005),
                .slider("darkShadowOpacity", keyPath: \.darkShadowOpacity, label: "Contact Shadow", range: 0...1, step: 0.01),
                .slider("darkShadowRadius", keyPath: \.darkShadowRadius, label: "Contact Radius", range: 0...10, step: 0.5, unit: "pt"),
                .slider("darkShadowY", keyPath: \.darkShadowY, label: "Contact Y", range: -10...20, step: 0.5, unit: "pt"),
                .slider("darkAmbientShadowOpacity", keyPath: \.darkAmbientShadowOpacity, label: "Ambient Shadow", range: 0...1, step: 0.01),
                .slider("darkAmbientShadowRadius", keyPath: \.darkAmbientShadowRadius, label: "Ambient Radius", range: 0...30, step: 0.5, unit: "pt"),
                .slider("darkAmbientShadowY", keyPath: \.darkAmbientShadowY, label: "Ambient Y", range: -10...20, step: 0.5, unit: "pt"),
            ]),
            .group("tileLight", label: "Tile · Light", collapsed: true, children: [
                .slider("lightFillTop", keyPath: \.lightFillTop, range: 0...1, step: 0.01),
                .slider("lightFillBottom", keyPath: \.lightFillBottom, range: 0...1, step: 0.01),
                .slider("lightRimTop", keyPath: \.lightRimTop, range: 0...1, step: 0.01),
                .slider("lightRimBottom", keyPath: \.lightRimBottom, range: 0...0.4, step: 0.01),
                .slider("lightShadowOpacity", keyPath: \.lightShadowOpacity, range: 0...0.6, step: 0.01),
                .slider("lightShadowRadius", keyPath: \.lightShadowRadius, range: 0...30, step: 0.5, unit: "pt"),
                .slider("lightShadowY", keyPath: \.lightShadowY, range: -10...20, step: 0.5, unit: "pt"),
            ]),
            .group("motion", children: [
                .slider("valueSpringResponse", keyPath: \.valueSpringResponse, label: "Meter Spring Response", range: 0.05...2, step: 0.01, unit: "s"),
                .slider("valueSpringDamping", keyPath: \.valueSpringDamping, label: "Meter Spring Damping", range: 0.1...1.5, step: 0.01),
                .slider("settleDuration", keyPath: \.settleDuration, label: "Settle Duration", range: 0.02...1, step: 0.01, unit: "s"),
            ]),
        ]
    }
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        panel.$values
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.values = $0 }
            .store(in: &cancellables)
        surfacePanel.$values
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.surface = $0.settings }
            .store(in: &cancellables)
        livePanel.$values
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.apply($0) }
            .store(in: &cancellables)
    }

    private func apply(_ live: PopoverLiveState) {
        guard let store else { return }
        if let format = GaugeFormat(rawValue: live.format),
           let shape = GaugeShape(rawValue: live.shape),
           let fill = GaugeFill(rawValue: live.fill) {
            let style = MeterStyle(format: format, shape: shape, fill: fill)
            if style != store.meterStyle { store.setMeterStyle(style) }
        }
        if let mode = UsagePercentageMode(rawValue: live.percentageMode), mode != store.usagePercentageMode {
            store.setUsagePercentageMode(mode)
        }
    }

    static func startAgent() {
        _ = shared
        DialKitAgent.shared.start(appName: "Headroom")
    }

    /// The `MenuBarExtra` window closes as soon as focus moves to the inspector, so tuning
    /// gets a pinned copy of the popover in a floating panel that never hides.
    private var pinnedPanel: NSPanel?

    func showPinnedPopover(store: UsageStore) {
        guard pinnedPanel == nil else { return }
        self.store = store
        livePanel.values = PopoverLiveState(
            format: store.meterStyle.format.rawValue,
            shape: store.meterStyle.shape.rawValue,
            fill: store.meterStyle.fill.rawValue,
            percentageMode: store.usagePercentageMode.rawValue
        )
        // The pinned copy has no MenuBarExtra host, so it always draws the Headroom shell;
        // judge "System glass" in the real menu-bar popover.
        let host = NSHostingController(rootView: PopoverView(store: store, onOpenSettings: {}, isPinnedTuningCopy: true))
        host.sizingOptions = [.preferredContentSize]
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // Follows the user to whichever Space (and full-screen app) they are tuning from.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - panel.frame.width - 40, y: screen.maxY - 12))
        }
        panel.orderFrontRegardless()
        pinnedPanel = panel
    }
    #else
    private init() {}
    static func startAgent() {}
    func showPinnedPopover(store: UsageStore) {}
    #endif
}

/// PC2: how the popover draws its surface — Headroom's own r22 glass shell, or the glass the
/// MenuBarExtra host draws itself. Defaults are the shipped values.
struct PopoverSurfaceSettings: Equatable {
    enum Surface: String { case headroom, system }
    enum GlassVariant: String { case regular, clear }

    var surface: Surface = .headroom
    var glass: GlassVariant = .regular
    /// Light and dark tints: the shell's glass tint, or the wash over the system glass.
    var lightTint: Color = .white
    var lightTintOpacity: Double = 0.55
    var darkTint: Color = .black
    var darkTintOpacity: Double = 0
    /// PC2's host-chrome reshape; off shows what the OS draws under the shell.
    var reshapeHostChrome = true
    /// PC3: the system window shadow draws a rim at the window's tighter corner, so it is off.
    var windowShadow = false
    /// PS1: a replacement shadow at the shell's corner, drawn from a child window.
    var customShadow = true
    var customShadowOpacity = 0.3
    var customShadowRadius = 16.0
    var customShadowY = 6.0

    static let shipping = PopoverSurfaceSettings()

    var usesHeadroomShell: Bool { surface == .headroom }
}

extension View {
    /// The popover window's container background: cleared for the Headroom shell (PC1), left
    /// to the host when a DialKit build switches to the system surface.
    @ViewBuilder
    func popoverSurfaceHost() -> some View {
        #if HEADROOM_DIALKIT
        modifier(PopoverSurfaceHost(tuning: PopoverTuningModel.shared))
        #else
        containerBackground(.clear, for: .window)
        #endif
    }
}

#if HEADROOM_DIALKIT
private struct PopoverSurfaceHost: ViewModifier {
    @ObservedObject var tuning: PopoverTuningModel

    func body(content: Content) -> some View {
        if tuning.surface.usesHeadroomShell {
            content.containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}

/// The DialKit-side copy of `PopoverSurfaceSettings`: Codable, colors as hex.
struct PopoverSurfaceState: Codable, Equatable {
    var surface = "headroom"
    var glass = "regular"
    var lightTint = "#FFFFFF"
    var lightTintOpacity = 0.55
    var darkTint = "#000000"
    var darkTintOpacity = 0.0
    var reshapeHostChrome = true
    var windowShadow = false
    var customShadow = true
    var customShadowOpacity = 0.3
    var customShadowRadius = 16.0
    var customShadowY = 6.0

    var settings: PopoverSurfaceSettings {
        PopoverSurfaceSettings(
            surface: .init(rawValue: surface) ?? .headroom,
            glass: .init(rawValue: glass) ?? .regular,
            lightTint: Self.color(lightTint),
            lightTintOpacity: lightTintOpacity,
            darkTint: Self.color(darkTint),
            darkTintOpacity: darkTintOpacity,
            reshapeHostChrome: reshapeHostChrome,
            windowShadow: windowShadow,
            customShadow: customShadow,
            customShadowOpacity: customShadowOpacity,
            customShadowRadius: customShadowRadius,
            customShadowY: customShadowY
        )
    }

    private static func color(_ hex: String) -> Color {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return .white }
        let hasAlpha = digits.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        return Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }
}
#endif
