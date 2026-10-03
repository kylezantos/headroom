#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI
import WidgetKit

// Shared pieces for the four widget styles (2026-10-02 widget-styles plan, U3). Every type is
// `HeadroomWidget`-prefixed: the macOS app compiles this module into its own, so a bare name
// here could collide with an app symbol.

// MARK: - Rendering context (KTD14)

/// How the widget is being drawn. WidgetKit's `widgetRenderingMode` and
/// `showsWidgetContainerBackground` are read-only outside a widget, so `ImageRenderer` would
/// only ever see full color; reading this one value lets the render harness pose the tinted
/// and StandBy branches too.
public enum HeadroomWidgetRenderingContext: Sendable, Equatable {
    /// Full color with the container background shown — the designed look.
    case fullColor
    /// Accented or vibrant (iOS Tinted/Clear, macOS desktop widgets behind windows): one ink.
    case monochrome
    /// Full color with the background stripped (StandBy, the Lock Screen).
    case stripped

    public var usesFullColorTokens: Bool { self == .fullColor }
}

private struct HeadroomWidgetRenderingOverrideKey: EnvironmentKey {
    static let defaultValue: HeadroomWidgetRenderingContext? = nil
}

private struct HeadroomWidgetProbesEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Set by the render harness only. Widgets leave it nil and resolve from WidgetKit.
    var headroomWidgetRenderingOverride: HeadroomWidgetRenderingContext? {
        get { self[HeadroomWidgetRenderingOverrideKey.self] }
        set { self[HeadroomWidgetRenderingOverrideKey.self] = newValue }
    }

    /// KTD12: turns on the overflow probes. Off in every widget and in Settings.
    var headroomWidgetProbesEnabled: Bool {
        get { self[HeadroomWidgetProbesEnabledKey.self] }
        set { self[HeadroomWidgetProbesEnabledKey.self] = newValue }
    }
}

@propertyWrapper
public struct HeadroomWidgetRendering: DynamicProperty {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.headroomWidgetRenderingOverride) private var override

    public init() {}

    public var wrappedValue: HeadroomWidgetRenderingContext {
        if let override { return override }
        guard mode == .fullColor else { return .monochrome }
        return showsBackground ? .fullColor : .stripped
    }
}

// MARK: - Overflow probe (KTD12)

/// One probed element's bounds. The harness reads these to prove nothing leaves the tile.
public struct HeadroomWidgetProbeKey: PreferenceKey {
    public static let defaultValue: [Anchor<CGRect>] = []
    public static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}

private struct HeadroomWidgetProbe: ViewModifier {
    @Environment(\.headroomWidgetProbesEnabled) private var enabled

    func body(content: Content) -> some View {
        if enabled {
            content.anchorPreference(key: HeadroomWidgetProbeKey.self, value: .bounds) { [$0] }
        } else {
            content
        }
    }
}

public extension View {
    /// Marks a payload element (numeral, meter, row, strip, footer) for the overflow sweep.
    func headroomWidgetProbe() -> some View { modifier(HeadroomWidgetProbe()) }
}

// MARK: - Inks the styles add

public extension HeadroomWidgetStyle {
    /// The popover's meter-label ink (`HeadroomMeterColorValues.labelInk`).
    static func labelInk(scheme: ColorScheme) -> Color {
        Color(styleTint: HeadroomMeterColorValues.labelInk(dark: scheme == .dark))
    }

    /// The popover's countdown ink (`HeadroomMeterColorValues.countdownInk`, PA13).
    static func countdownInk(scheme: ColorScheme) -> Color {
        Color(styleTint: HeadroomMeterColorValues.countdownInk(dark: scheme == .dark))
    }

    /// KTD5: one fill for bars, rails, vessel liquid and the wash. Nil means draw nothing.
    static func styleFill(
        for window: WidgetWindowSummary?,
        colorMode: WidgetColorMode,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color? {
        guard let window,
              let tint = WidgetStyleColors.fill(for: window, colorMode: colorMode, dark: scheme == .dark, increasedContrast: increasedContrast)
        else { return nil }
        return Color(styleTint: tint)
    }
}

extension Color {
    init(styleTint tint: HeadroomTint) {
        self = Color(red: tint.color.red, green: tint.color.green, blue: tint.color.blue).opacity(tint.opacity)
    }
}

// MARK: - Countdown and accessibility

/// The window strings live in Core (`WidgetWindowText`) so their branches are unit-tested; this
/// alias keeps the style views' spelling.
public typealias HeadroomWidgetWindowText = WidgetWindowText

// MARK: - Numeral (R5)

/// A usage numeral: `.system(size, .semibold).monospacedDigit()`, no kerning, "%" in the same
/// run at full size. Ink follows WCM2/WCM3/WCD3.
public struct HeadroomWidgetNumeral: View {
    private let window: WidgetWindowSummary?
    private let size: Double
    private let providerIsLive: Bool
    private let now: Date

    @Environment(\.colorScheme) private var scheme

    public init(_ window: WidgetWindowSummary?, size: Double, providerIsLive: Bool = true, now: Date) {
        self.window = window
        self.size = size
        self.providerIsLive = providerIsLive
        self.now = now
    }

    public var body: some View {
        Text(HeadroomWidgetWindowText.percent(window))
            .font(HeadroomWidgetType.font(size: size, weight: .semibold, mono: true))
            .foregroundStyle(ink)
            .lineLimit(1)
            .contentTransition(window?.displayPercentRemaining != nil ? .numericText() : .opacity)
            .fixedSize()
            .layoutPriority(2)
            .widgetAccentable()
            .headroomWidgetProbe()
    }

    private var ink: Color {
        guard let window, providerIsLive, window.freshness.isLive else {
            return HeadroomWidgetStyle.secondaryText(scheme: scheme)
        }
        if HeadroomWidgetWindowText.countdown(window, now: now) == "now" {
            return HeadroomWidgetStyle.secondaryText(scheme: scheme)
        }
        return window.severity == .critical ? HeadroomWidgetStyle.criticalText(scheme: scheme) : .primary
    }
}

// MARK: - Identity row

/// Mark · name · plan capsule · attention glyph · stale reason. The plan capsule is the first
/// thing to go when the row is short (KTD10), then the name truncates; the mark never shrinks.
public struct HeadroomWidgetIdentityRow<Mark: View>: View {
    private let provider: WidgetStyleProviderRecipe
    private let slot: Double
    private let scale: WidgetTypeScale
    private let showsPlan: Bool
    private let showsStaleReason: Bool
    private let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme
    @HeadroomWidgetTypeUnit private var typeUnit

    /// `showsStaleReason`: WCM5-v — large is the one family with room to print the provider's
    /// on-wire stale reason after the glyph.
    public init(
        provider: WidgetStyleProviderRecipe,
        slot: Double,
        scale: WidgetTypeScale,
        showsPlan: Bool,
        showsStaleReason: Bool = false,
        @ViewBuilder mark: @escaping (String, CGFloat) -> Mark
    ) {
        self.provider = provider
        self.slot = slot
        self.scale = scale
        self.showsPlan = showsPlan
        self.showsStaleReason = showsStaleReason
        self.mark = mark
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            if showsPlan, provider.summary.planLabel != nil {
                row(plan: true)
            }
            row(plan: false)
        }
    }

    private func row(plan: Bool) -> some View {
        let size = scale.name * typeUnit
        return HStack(spacing: CGFloat(WidgetMetrics.markGap)) {
            mark(provider.id, CGFloat(slot))
                .frame(width: CGFloat(slot), height: CGFloat(slot))
            Text(provider.summary.displayName)
                .font(.system(size: size, weight: .semibold))
                .kerning(scale.nameKerning)
                .foregroundStyle(HeadroomWidgetStyle.accountTitle(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: plan, vertical: false)
                .widgetCapHeightCentered(size: size, weight: .semibold)
            if plan, let label = provider.summary.planLabel {
                HeadroomWidgetPlanCapsule(label: label)
                    .widgetCapHeightCentered(size: size, weight: .semibold)
            }
            if provider.summary.freshness.isStale {
                HeadroomWidgetAttentionGlyph(kind: .provider, size: 10)
                    .fixedSize()
                    .widgetCapHeightCentered(size: size, weight: .semibold)
            }
            if showsStaleReason, let message = provider.staleMessage {
                reason(message)
            }
            Spacer(minLength: 0)
        }
    }

    /// WCM5-v: the reason in tertiary ink, one line. WCF7: it is the row's last flexible element
    /// and gives first — negative priority, and no ideal width, so it never costs the plan
    /// capsule its rung or pushes the name out; it takes only what the row has left, and drops
    /// whole rather than print a one-letter fragment.
    private func reason(_ message: String) -> some View {
        let reasonSize = scale.countdown * typeUnit
        // Four ems is roughly "Sign…": below that the reason is a fragment, not a phrase.
        let fragmentWidth = CGFloat(reasonSize * 4)
        return ViewThatFits(in: .horizontal) {
            Text(message)
                .font(HeadroomWidgetType.font(size: reasonSize))
                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .widgetCapHeightCentered(size: reasonSize, weight: .regular)
                .frame(minWidth: fragmentWidth, idealWidth: fragmentWidth, maxWidth: .infinity, alignment: .leading)
                .headroomWidgetProbe()
            Color.clear.frame(width: 0, height: 0)
        }
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
        .layoutPriority(-1)
    }
}

public extension HeadroomWidgetIdentityRow where Mark == HeadroomWidgetProviderIcon {
    init(provider: WidgetStyleProviderRecipe, slot: Double, scale: WidgetTypeScale, showsPlan: Bool, showsStaleReason: Bool = false) {
        self.init(provider: provider, slot: slot, scale: scale, showsPlan: showsPlan, showsStaleReason: showsStaleReason) { id, size in
            HeadroomWidgetProviderIcon(providerID: id, size: size)
        }
    }
}

/// WCW9: capsule 15 high, label 9.5 medium +0.2, `secondary @ 0.12`, `planLabel` ink.
public struct HeadroomWidgetPlanCapsule: View {
    private let label: String
    @Environment(\.colorScheme) private var scheme
    @HeadroomWidgetTypeUnit private var typeUnit

    public init(label: String) { self.label = label }

    public var body: some View {
        let scale = WidgetTypeScale.scale(for: .large)
        Text(label)
            .font(.system(size: scale.pillLabel * typeUnit, weight: .medium))
            .kerning(0.2)
            .foregroundStyle(HeadroomWidgetStyle.planLabel(scheme: scheme))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: scale.pillHeight * typeUnit)
            .background(Capsule().fill(HeadroomWidgetStyle.secondaryText(scheme: scheme).opacity(0.12)))
    }
}

// MARK: - Bar (bars and rails)

/// A style bar or rail: track, fill from the color mode (KTD5), shallow well at 6pt and up
/// (WCF6), critical track (WCM2), constant minimum fill (WCM6). Outside full color the fill
/// is `.primary` and the track `.primary @ 0.20` (WCM7/WCM8).
public struct HeadroomWidgetStyleBar: View {
    private let window: WidgetWindowSummary?
    private let colorMode: WidgetColorMode
    private let providerIsLive: Bool
    private let height: CGFloat
    private let showsWell: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @HeadroomWidgetRendering private var rendering

    public init(_ window: WidgetWindowSummary?, colorMode: WidgetColorMode, providerIsLive: Bool = true, height: CGFloat, showsWell: Bool = true) {
        self.window = window
        self.colorMode = colorMode
        self.providerIsLive = providerIsLive
        self.height = height
        self.showsWell = showsWell
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .overlay {
                        if showsWell, height >= 6, rendering.usesFullColorTokens {
                            Capsule().strokeBorder(wellGradient, lineWidth: HeadroomWidgetStyle.hairlineWidth(displayScale: displayScale))
                        }
                    }
                if let length = fillLength(geo.size.width), length > 0, let fill = fillColor {
                    Capsule()
                        .fill(fill)
                        .frame(width: length)
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .headroomWidgetProbe()
    }

    /// WCM5: a stale provider's rows take the stale treatment.
    private var effectiveWindow: WidgetWindowSummary? {
        providerIsLive ? window : window?.demotedToStale()
    }

    private func fillLength(_ available: CGFloat) -> CGFloat? {
        guard let value = window?.displayPercentRemaining else { return nil }
        return CGFloat(MeterGeometry.continuousFillLength(
            available: Double(available),
            fraction: min(1, max(0, value / 100)),
            format: height >= 6 ? .full : .micro
        ))
    }

    private var fillColor: Color? {
        guard rendering.usesFullColorTokens else { return .primary }
        return HeadroomWidgetStyle.styleFill(for: effectiveWindow, colorMode: colorMode, scheme: scheme, increasedContrast: contrast == .increased)
    }

    private var trackColor: Color {
        switch rendering {
        case .monochrome: return Color.primary.opacity(0.20)
        case .stripped: return Color.primary.opacity(0.22)
        case .fullColor:
            guard let window, window.severity == .critical, providerIsLive, window.freshness.isLive else {
                return HeadroomWidgetStyle.barTrack(scheme: scheme)
            }
            return HeadroomWidgetStyle.criticalBarTrack(scheme: scheme)
        }
    }

    private var wellGradient: LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color.black.opacity(0.18), Color.white.opacity(0.05)]
                : [Color.black.opacity(0.07), Color.white.opacity(0.30)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Vessel (KTD6)

/// The Headroom vessel: capsule wall, inset capsule clip, flat liquid top. Liquid takes the
/// color-mode fill; the wall is tertiary ink, critical only for a live critical window; a
/// window with no displayed value is an empty outline.
public struct HeadroomWidgetVessel: View {
    private let window: WidgetWindowSummary?
    private let colorMode: WidgetColorMode
    private let providerIsLive: Bool
    private let geometry: WidgetVesselGeometry

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @HeadroomWidgetRendering private var rendering

    public init(_ window: WidgetWindowSummary?, colorMode: WidgetColorMode, providerIsLive: Bool = true, geometry: WidgetVesselGeometry) {
        self.window = window
        self.colorMode = colorMode
        self.providerIsLive = providerIsLive
        self.geometry = geometry
    }

    public var body: some View {
        let width = CGFloat(geometry.width)
        let height = CGFloat(geometry.height)
        let inset = CGFloat(geometry.inset)
        let liquid = CGFloat(geometry.liquidHeight(fraction: window?.displayPercentRemaining.map { $0 / 100 }))
        ZStack {
            Capsule()
                .inset(by: CGFloat(geometry.stroke) / 2)
                .stroke(wallColor, lineWidth: CGFloat(geometry.stroke))
            if liquid > 0, let fill = liquidColor {
                // VesselGlyph.render: clip to the inset capsule, then fill the lower part —
                // the clip supplies the rounded base, the rectangle the flat liquid top.
                Rectangle()
                    .fill(fill)
                    .frame(height: liquid)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .frame(width: width - 2 * inset, height: height - 2 * inset)
                    .clipShape(Capsule())
                    .widgetAccentable()
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
        .headroomWidgetProbe()
    }

    private var wallColor: Color {
        if rendering.usesFullColorTokens, providerIsLive, WidgetVesselGeometry.wallIsCritical(window) {
            return HeadroomWidgetStyle.styleFill(for: window, colorMode: colorMode, scheme: scheme, increasedContrast: contrast == .increased)
                ?? HeadroomWidgetStyle.tertiaryText(scheme: scheme)
        }
        return rendering.usesFullColorTokens
            ? HeadroomWidgetStyle.tertiaryText(scheme: scheme)
            : Color.primary.opacity(0.55)
    }

    private var liquidColor: Color? {
        guard rendering.usesFullColorTokens else { return .primary }
        return HeadroomWidgetStyle.styleFill(
            for: providerIsLive ? window : window?.demotedToStale(),
            colorMode: colorMode, scheme: scheme, increasedContrast: contrast == .increased
        )
    }
}

/// R4/KTD7: a vessel exactly as tall as the numeral's digit ink, sitting on its baseline, with
/// the numeral beside it. Callers put this in a first-text-baseline row; the vessel's own
/// baseline guide is its bottom raised by the digits' overshoot, so vessel and digits share a
/// top line and a bottom line.
public struct HeadroomWidgetVesselNumeral: View {
    private let window: WidgetWindowSummary?
    private let colorMode: WidgetColorMode
    private let providerIsLive: Bool
    private let numeralSize: Double
    private let now: Date

    public init(_ window: WidgetWindowSummary?, colorMode: WidgetColorMode, providerIsLive: Bool, numeralSize: Double, now: Date) {
        self.window = window
        self.colorMode = colorMode
        self.providerIsLive = providerIsLive
        self.numeralSize = numeralSize
        self.now = now
    }

    public var body: some View {
        let descent = HeadroomWidgetFontMetrics.digitInk(size: CGFloat(numeralSize), weight: .semibold).descent
        HStack(alignment: .firstTextBaseline, spacing: Self.gap(numeralSize: numeralSize)) {
            HeadroomWidgetVessel(window, colorMode: colorMode, providerIsLive: providerIsLive, geometry: Self.geometry(numeralSize: numeralSize))
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - descent }
            HeadroomWidgetNumeral(window, size: numeralSize, providerIsLive: providerIsLive, now: now)
        }
    }

    /// The numeral's leading offset from the vessel's left edge, so a caption can hang under
    /// the numeral rather than under the vessel.
    public static func captionIndent(numeralSize: Double) -> CGFloat {
        CGFloat(geometry(numeralSize: numeralSize).width) + gap(numeralSize: numeralSize)
    }

    /// The vessel's height is the digits' ink span, rounded to the half point.
    private static func geometry(numeralSize: Double) -> WidgetVesselGeometry {
        let ink = HeadroomWidgetFontMetrics.digitInk(size: CGFloat(numeralSize), weight: .semibold)
        return WidgetVesselGeometry(height: Double(((ink.ascent + ink.descent) * 2).rounded() / 2))
    }

    private static func gap(numeralSize: Double) -> CGFloat {
        CGFloat((numeralSize * WidgetStyleMetrics.heroVesselGapRatio).rounded())
    }
}

// MARK: - Liquid wash (KTD9)

/// Liquid Level's full-bleed layer: one column per wash segment, filled from the bottom to
/// its level, with a bright top edge. Drawn by every caller beneath the padded content.
public struct HeadroomWidgetLiquidWash: View {
    private let segments: [WidgetWashSegment]
    private let colorMode: WidgetColorMode
    private let showsDivider: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @HeadroomWidgetRendering private var rendering

    public init(segments: [WidgetWashSegment], colorMode: WidgetColorMode, showsDivider: Bool) {
        self.segments = segments
        self.colorMode = colorMode
        self.showsDivider = showsDivider
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                if index > 0, showsDivider {
                    Rectangle()
                        .fill(HeadroomWidgetStyle.widgetHairline(scheme: scheme))
                        .frame(width: HeadroomWidgetStyle.hairlineWidth(displayScale: displayScale))
                }
                column(segment)
            }
        }
        .accessibilityHidden(true)
    }

    private func column(_ segment: WidgetWashSegment) -> some View {
        GeometryReader { geo in
            if let fraction = segment.fraction, fraction > 0, let ink = ink(segment) {
                let height = max(CGFloat(WidgetStyleMetrics.washEdgeWidth), geo.size.height * CGFloat(fraction))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .top) {
                        Rectangle().fill(body(ink))
                        Rectangle()
                            .fill(edge(ink))
                            .frame(height: CGFloat(WidgetStyleMetrics.washEdgeWidth))
                            .widgetAccentable()
                    }
                    .frame(height: height)
                }
            }
        }
    }

    private func ink(_ segment: WidgetWashSegment) -> Color? {
        guard rendering.usesFullColorTokens else { return .primary }
        return HeadroomWidgetStyle.styleFill(for: segment.window, colorMode: colorMode, scheme: scheme, increasedContrast: contrast == .increased)
    }

    private func body(_ ink: Color) -> AnyShapeStyle {
        guard rendering.usesFullColorTokens else {
            return AnyShapeStyle(ink.opacity(WidgetStyleMetrics.washMonochromeOpacity))
        }
        return AnyShapeStyle(LinearGradient(
            colors: [ink.opacity(WidgetStyleMetrics.washTopOpacity), ink.opacity(WidgetStyleMetrics.washBottomOpacity)],
            startPoint: .top,
            endPoint: .bottom
        ))
    }

    private func edge(_ ink: Color) -> Color {
        rendering.usesFullColorTokens ? ink.opacity(WidgetStyleMetrics.washEdgeOpacity) : ink
    }
}

// MARK: - Shared text pieces

public struct HeadroomWidgetCaption: View {
    private let text: String
    private let size: Double
    private let ink: Ink
    private let weight: Font.Weight
    private let mono: Bool

    public enum Ink { case secondary, label, countdown }

    @Environment(\.colorScheme) private var scheme
    @HeadroomWidgetTypeUnit private var typeUnit

    public init(_ text: String, size: Double, ink: Ink = .secondary, weight: Font.Weight = .medium, mono: Bool = false) {
        self.text = text
        self.size = size
        self.ink = ink
        self.weight = weight
        self.mono = mono
    }

    public var body: some View {
        Text(text)
            .font(HeadroomWidgetType.font(size: size * typeUnit, weight: weight, mono: mono))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .headroomWidgetProbe()
    }

    private var color: Color {
        switch ink {
        case .secondary: HeadroomWidgetStyle.secondaryText(scheme: scheme)
        case .label: HeadroomWidgetStyle.labelInk(scheme: scheme)
        case .countdown: HeadroomWidgetStyle.countdownInk(scheme: scheme)
        }
    }
}

/// A one-pixel rule in the widget hairline ink (WCL4).
public struct HeadroomWidgetRule: View {
    private let axis: Axis
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    public init(_ axis: Axis = .horizontal) { self.axis = axis }

    public var body: some View {
        let width = HeadroomWidgetStyle.hairlineWidth(displayScale: displayScale)
        Rectangle()
            .fill(HeadroomWidgetStyle.widgetHairline(scheme: scheme))
            .frame(width: axis == .vertical ? width : nil, height: axis == .horizontal ? width : nil)
            .accessibilityHidden(true)
    }
}

/// WCF7: a caption with fallbacks. Each option is tried whole, longest first; only the last
/// one may truncate. Used where a countdown or a secondary value should drop whole rather
/// than end in "2…".
public struct HeadroomWidgetFittingCaption: View {
    private let options: [String]
    private let size: Double
    private let ink: HeadroomWidgetCaption.Ink
    private let mono: Bool

    public init(_ options: [String], size: Double, ink: HeadroomWidgetCaption.Ink = .secondary, mono: Bool = false) {
        self.options = options.isEmpty ? [""] : options
        self.size = size
        self.ink = ink
        self.mono = mono
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(options.dropLast().enumerated()), id: \.offset) { _, option in
                HeadroomWidgetCaption(option, size: size, ink: ink, mono: mono).fixedSize()
            }
            HeadroomWidgetCaption(options[options.count - 1], size: size, ink: ink, mono: mono)
        }
    }
}

extension View {
    /// R15: one VoiceOver element per provider — its name, then its windows in visual order.
    func headroomWidgetProviderAccessibility(_ provider: WidgetStyleProviderRecipe, windows: [WidgetWindowSummary]? = nil, now: Date) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(provider.summary.displayName)
            .accessibilityValue(HeadroomWidgetWindowText.providerAccessibility(provider, windows: windows, now: now))
    }
}
