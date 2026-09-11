#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI
import WidgetKit

public enum HeadroomWidgetStyle {
    public static func assetName(for id: String) -> String? {
        switch id {
        case ProviderID.claude.raw: "ClaudeBrandIcon"
        case ProviderID.codex.raw: "CodexBrandIcon"
        // Grok/Cursor imagesets carry a luminosity dark appearance, so `Image(assetName)`
        // adapts per scheme natively — no separate light/dark lookup needed here.
        case ProviderID.grok.raw: "GrokBrandIcon"
        case ProviderID.cursor.raw: "CursorBrandIcon"
        default: nil
        }
    }

    public static func accent(for id: String) -> Color {
        switch id {
        case ProviderID.claude.raw: return Color(HeadroomBrandColorValues.claude)
        case ProviderID.codex.raw: return Color(HeadroomBrandColorValues.codex)
        case ProviderID.grok.raw: return Color(HeadroomBrandColorValues.grok)
        case ProviderID.cursor.raw: return Color(HeadroomBrandColorValues.cursor)
        default: return .secondary
        }
    }

    // R2: wraps the shared HeadroomWidgetColorValues so macOS and iOS cannot drift.
    public static func textAccent(for id: String, scheme: ColorScheme) -> Color {
        guard let rgb = HeadroomWidgetColorValues.textAccent(for: id, dark: scheme == .dark) else { return .secondary }
        return Color(rgb)
    }

    public static func symbol(for id: String) -> String {
        switch id {
        case ProviderID.claude.raw: "sparkle"
        case ProviderID.codex.raw: "chevron.left.forwardslash.chevron.right"
        case ProviderID.grok.raw: "atom"
        case ProviderID.cursor.raw: "cursorarrow"
        default: "circle.dashed"
        }
    }

    public static func severityColor(for severity: WidgetUsageSeverity, scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    /// Bar-fill tier, mirroring the popover (`ProviderStyle.severityFill`): vivid in the
    /// default light appearance, reverting to the 3:1-passing text-tier values under
    /// Increase Contrast. Text and the attention glyphs keep `severityColor`. See
    /// `HeadroomSeverityColorValues` for why the tiers differ.
    public static func severityFill(
        for severity: WidgetUsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(HeadroomSeverityColorValues.fill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }

    /// WCM1: what a *healthy live* bar paints. Green as the resting state carries no
    /// information; the popover's shipped default (`MeterStyle.default.fill ==
    /// .colorAsEvent`) already paints healthy neutral, and it is the precondition for WCM2
    /// and WCD1 — a red bar is only an alarm on a tile where nothing else is coloured.
    public static func neutralFill(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.neutralFill(dark: scheme == .dark))
    }

    /// WCM3: what a bar paints when its window (or its provider) is no longer live. The
    /// row keeps its own severity hue at 0.35 chroma, so a stale critical is still faintly
    /// red and a stale healthy is the neutral stale tone — the old `secondaryText` fill made
    /// a retired bar the loudest bar on the tile.
    public static func staleFill(
        for severity: WidgetUsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(HeadroomMeterColorValues.staleFill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }


    public static func criticalText(scheme: ColorScheme) -> Color {
        Color(HeadroomSeverityColorValues.criticalText(dark: scheme == .dark))
    }

    /// WCM2: at critical the track takes the critical hue at constant lightness, so the
    /// alarm survives the few points of fill left at 3%.
    public static func criticalBarTrack(scheme: ColorScheme) -> Color {
        Color(HeadroomMeterColorValues.criticalBarTrack(dark: scheme == .dark))
    }

    public static func secondaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark))
    }

    public static func tertiaryText(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark))
    }

    /// WCD1: provider and account names are neutral on widgets. Colour lives in the brand
    /// mark and in severity events; Claude's dark text accent and the low amber are
    /// near-neighbours in hue at glance distance, and the mark already separates providers.
    public static func accountTitle(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.accountTitle(dark: scheme == .dark))
    }

    /// WCW9: the large family's plan pill ink.
    public static func planLabel(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.planLabel(dark: scheme == .dark))
    }

    public static func barTrack(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.barTrack(dark: scheme == .dark))
    }

    /// WCL4: the lifted widget-only rule ink. The shared `hairline` token was tuned for the
    /// popover's card fills and measures 1.28:1 on the widget container; a rule that is a
    /// true device pixel has to be a little stronger to read at all.
    public static func widgetHairline(scheme: ColorScheme) -> Color {
        Color(HeadroomWidgetColorValues.widgetHairline(dark: scheme == .dark))
    }

    /// WCL4: one device pixel, not one point. Every rule in the widgets is drawn at this
    /// width so a 2× and a 3× tile carry the same hairline rather than a 2pt slab.
    public static func hairlineWidth(displayScale: CGFloat) -> CGFloat {
        CGFloat(WidgetMetrics.hairline) / max(1, displayScale)
    }
}

public struct HeadroomWidgetProviderIcon: View {
    private let providerID: String
    private let size: CGFloat

    public init(providerID: String, size: CGFloat) {
        self.providerID = providerID
        self.size = size
    }

    // OA2: same measured rule and leading alignment as the popover and the iOS app — the
    // imageset artwork is trimmed to its ink, the larger ink dimension is 13/15 of the slot
    // with the aspect preserved, and the leftover slot falls on the trailing side so every
    // provider's mark hangs on one axis.
    //
    // WCM7: `.desaturated` in the accented/vibrant families. The brand mark is the one
    // channel that separates Claude from Codex, and a tinted mark loses it; desaturated
    // keeps the silhouette's own value structure under the user's tint.
    public var body: some View {
        let mark = HeadroomBrandMark.markSize(for: providerID, slot: Double(size))
        let markWidth = CGFloat(mark.width)
        let markHeight = CGFloat(mark.height)
        if let assetName = HeadroomWidgetStyle.assetName(for: providerID) {
            Image(assetName)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .frame(width: size, height: size, alignment: .leading)
                .accessibilityHidden(true)
        } else {
            Image(systemName: HeadroomWidgetStyle.symbol(for: providerID))
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .frame(width: size, height: size, alignment: .leading)
                .foregroundStyle(HeadroomWidgetStyle.accent(for: providerID))
                .accessibilityHidden(true)
        }
    }
}

/// WCM5: the one attention glyph pair. Provider-level attention is an account-lifecycle
/// fact, not a usage severity, so per R2C5 it comes off the severity ramp entirely and
/// prints in neutral `secondaryText` — the old amber triangle was the *same* amber as a low
/// bar, three meanings on one glyph. The circle marks a provider, the triangle a spend row.
public struct HeadroomWidgetAttentionGlyph: View {
    public enum Kind: Sendable, Equatable {
        case provider
        case spend

        var symbol: String {
            switch self {
            case .provider: "exclamationmark.circle.fill"
            case .spend: "exclamationmark.triangle.fill"
            }
        }
    }

    private let kind: Kind
    private let size: Double

    @Environment(\.colorScheme) private var scheme
    // WCF1: callers hand over the *ladder* size and the glyph takes the Dynamic Type factor
    // itself, so a glyph beside a name never stays put while the name grows — and the spend
    // strip, whose own sizes are already `@ScaledMetric`, passes its raw token rather than
    // scaling twice.
    @HeadroomWidgetTypeUnit private var typeUnit

    public init(kind: Kind, size: Double) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        let scaled = size * typeUnit
        return Image(systemName: kind.symbol)
            .font(HeadroomWidgetType.font(size: scaled, weight: .semibold))
            .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
            // WCL6/WCM5-iv: the glyph sits beside a name of another size, so it lands on the
            // row's cap-height axis rather than on its own line box.
            .widgetCapHeightCentered(size: scaled, weight: .semibold)
            .accessibilityHidden(true)
    }
}

/// One usage row: `[label · state · countdown]` on the left, a reserved numeral column and
/// suffix on the right, the bar underneath. The same view draws medium and large rows and —
/// in `glance` mode — the small family's provider line (WCF5), so there is one implementation
/// of the ladder, the columns, and the freshness rules rather than three.
public struct HeadroomWidgetUsageMeter: View {
    private let window: WidgetWindowSummary?
    private let fallbackLabel: String
    private let now: Date
    private let scale: WidgetTypeScale
    private let family: HeadroomWidgetFamily
    private let providerIsLive: Bool
    private let showsResetInline: Bool
    private let glance: Bool
    private let glanceName: String?
    private let explicitBarHeight: CGFloat?

    @Environment(\.colorScheme) private var scheme

    // WCF1: the ladder is in points, read through `@ScaledMetric` so iPhone keeps Dynamic
    // Type (the root cap at `xxLarge` still applies; on macOS this is inert). Every step
    // scales relative to the *same* text style so the ladder's internal ratios hold —
    // relating the numeral to `.title3` and the label to `.caption` would pull them apart
    // at the accessibility sizes.
    @ScaledMetric private var nameSize: Double
    @ScaledMetric private var labelSize: Double
    @ScaledMetric private var countdownSize: Double
    @ScaledMetric private var numeralSize: Double
    @ScaledMetric private var suffixSize: Double

    public init(
        window: WidgetWindowSummary?,
        fallbackLabel: String,
        now: Date,
        scale: WidgetTypeScale,
        family: HeadroomWidgetFamily,
        providerIsLive: Bool = true,
        showsResetInline: Bool = false,
        glance: Bool = false,
        glanceName: String? = nil,
        barHeight: CGFloat? = nil
    ) {
        self.window = window
        self.fallbackLabel = fallbackLabel
        self.now = now
        self.scale = scale
        self.family = family
        self.providerIsLive = providerIsLive
        self.showsResetInline = showsResetInline
        self.glance = glance
        self.glanceName = glanceName
        self.explicitBarHeight = barHeight
        _nameSize = ScaledMetric(wrappedValue: scale.name, relativeTo: .body)
        _labelSize = ScaledMetric(wrappedValue: scale.label, relativeTo: .body)
        _countdownSize = ScaledMetric(wrappedValue: scale.countdown, relativeTo: .body)
        _numeralSize = ScaledMetric(wrappedValue: scale.numeral, relativeTo: .body)
        _suffixSize = ScaledMetric(wrappedValue: scale.suffix, relativeTo: .body)
    }

    public var body: some View {
        // WCL5: the glance row (small) sits its bar 6 under the name; every stacked meter
        // keeps WCL2's 7.
        VStack(alignment: .leading, spacing: glance ? 6 : CGFloat(WidgetMetrics.labelToBar)) {
            if glance {
                glanceRow
            } else {
                // WCF2/WCF7: one degradation ladder, three rungs — drop the countdown
                // whole, then drop the state word whole, then let the label truncate. The
                // countdown is never ellipsised ("· Reset info unavaila…") and the numeral
                // column never gives.
                ViewThatFits(in: .horizontal) {
                    meterRow(showsCountdown: true, showsState: true, truncatesLabel: false)
                    meterRow(showsCountdown: false, showsState: true, truncatesLabel: false)
                    meterRow(showsCountdown: false, showsState: false, truncatesLabel: true)
                }
            }
            bar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Rows


    /// WCF5/WCD1: the small family's provider line is this meter with the account name in
    /// the label slot — no window label, no state word, no suffix. The numeral column is
    /// still reserved, which is what keeps two provider rows sharing one right edge.
    /// WCL6: the 18pt numeral against a 14pt name is exactly the mixed-size row cap-height
    /// centring exists for.
    private var glanceRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(glanceName ?? labelText)
                .font(HeadroomWidgetType.font(size: nameSize, weight: .semibold))
                .kerning(CGFloat(scale.nameKerning))
                .foregroundStyle(HeadroomWidgetStyle.accountTitle(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .widgetOpticalLeading(glanceName ?? labelText, size: nameSize, weight: .semibold)
                .widgetCapHeightCentered(size: nameSize, weight: .semibold)
            Spacer(minLength: 6)
            numeral(capCentred: true)
        }
    }

    private func meterRow(showsCountdown: Bool, showsState: Bool, truncatesLabel: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            metadataCluster(
                showsCountdown: showsCountdown,
                showsState: showsState,
                truncatesLabel: truncatesLabel
            )
            Spacer(minLength: 6)
            numeralCluster
        }
    }

    /// WCF7: `fixedSize` pins the cluster to its ideal width on the rungs that must fit
    /// whole — that is what makes `ViewThatFits` reject them rather than squeeze them. On
    /// the last rung the label is the only flexible element in the row, so it is the one
    /// that gives.
    private func metadataCluster(
        showsCountdown: Bool,
        showsState: Bool,
        truncatesLabel: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(labelText)
                .font(HeadroomWidgetType.font(size: labelSize, weight: .medium))
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                // WCL6: "Weekly" (a diagonal) over "5-hour" (a flat stem) is the widest
                // stagger in a provider's label column.
                .widgetOpticalLeading(labelText, size: labelSize, weight: .medium)
            if showsState, let stateText {
                Text("· \(stateText)")
                    .font(HeadroomWidgetType.font(size: countdownSize, weight: .medium, mono: true))
                    .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .fixedSize()
            }
            if showsCountdown, let countdownText {
                Text("· \(countdownText)")
                    .font(HeadroomWidgetType.font(size: countdownSize, mono: true))
                    .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: !truncatesLabel, vertical: false)
    }

    /// WCF2: the numeral sits in a column wide enough for "100%" at its own size, and the
    /// suffix is laid out whether or not there is a value to print. Without both, an
    /// `.unavailable` row's "—" and the row above it stop sharing a right edge.
    private var numeralCluster: some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(WidgetMetrics.suffixGap)) {
            numeral(capCentred: false)
            Text("left")
                .font(HeadroomWidgetType.font(size: suffixSize))
                .foregroundStyle(
                    hasValue ? HeadroomWidgetStyle.tertiaryText(scheme: scheme) : Color.clear
                )
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .fixedSize()
        .layoutPriority(1)
    }

    private func numeral(capCentred: Bool) -> some View {
        Text(percentText)
            .font(HeadroomWidgetType.font(size: numeralSize, weight: .semibold, mono: true))
            .foregroundStyle(numeralInk)
            .lineLimit(1)
            // WCD3: the only motion a widget carries — a reload rolls the digits rather
            // than cutting them. An odometer has nothing to roll to once the value goes
            // away, so "—" crossfades instead. Nothing here loops or pulses.
            .contentTransition(hasValue ? .numericText() : .opacity)
            .frame(
                minWidth: CGFloat(WidgetTypeScale.numeralColumnWidth(forNumeralSize: numeralSize)),
                alignment: .trailing
            )
            .modifier(CapCentred(enabled: capCentred, size: numeralSize))
            // WCF7: the numeral never shrinks, truncates, or gives ground — it is the
            // payload, and a flexible sibling (the label, the glance name) always yields
            // first.
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .widgetAccentable()
    }

    private var bar: some View {
        HeadroomWidgetUsageBar(
            percentRemaining: window?.displayPercentRemaining,
            severity: window?.severity ?? .healthy,
            freshness: window?.freshness ?? .unavailable(since: now),
            providerIsLive: providerIsLive,
            height: barHeight
        )
    }

    // MARK: - Values

    private var barHeight: CGFloat {
        if let explicitBarHeight { return explicitBarHeight }
        switch family {
        case .small: return CGFloat(WidgetMetrics.smallBarHeight)
        case .medium: return CGFloat(WidgetMetrics.mediumBarHeight)
        // WCL1: large passes its tier's height explicitly; this is the regular tier's value.
        case .large: return CGFloat(LargeWidgetDensity.regular.barHeight)
        }
    }

    private var isLive: Bool {
        providerIsLive && window?.freshness.isLive == true
    }

    private var hasValue: Bool { window?.displayPercentRemaining != nil }

    private var percentText: String {
        // WCW8: an em dash, never "--".
        guard let value = window?.displayPercentRemaining else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    /// WCW2: one Core accessor decides what a window is called, so "Weekly (Fable)" reads
    /// as "Fable" here and as "Fable" on the phone.
    private var labelText: String {
        window?.widgetDisplayLabel ?? fallbackLabel
    }

    /// WCW5: the state word wherever the family has room. Large also carries the row's own
    /// age, because "· Last known" beside a footer that says "9 min ago" is two clocks with
    /// no stated relationship.
    private var stateText: String? {
        guard let window, let base = MirrorPresentation.windowStateText(for: window) else { return nil }
        guard family == .large, window.freshness.isStale else { return base }
        guard let age = Countdown.updatedLabel(capturedAt: window.observedAt, now: now) else { return base }
        return "\(base) \(age)"
    }

    /// WCW1: the countdown, not the tooltip — "6d 4h", not "Resets in 6d 4h" — and nothing
    /// at all when the schedule is unresolved (`meterResetLine` returns nil, exactly where
    /// the popover prints nothing). WCL9: medium opts in; large always has the room.
    private var countdownText: String? {
        guard showsResetInline || family == .large else { return nil }
        guard let window, !window.freshness.isUnavailable else { return nil }
        return window.resetSchedule.meterResetLine(now: now)?.countdown
    }

    /// WCD3: at the reset itself the countdown holds "now" (R2M3); for that one entry the
    /// numeral steps back to secondary while the bar keeps its fill, and the next capture
    /// restores it.
    private var isAtReset: Bool {
        guard let window, !window.freshness.isUnavailable else { return false }
        return window.resetSchedule.meterResetLine(now: now)?.countdown == "now"
    }

    /// WCM2/WCM3: red only when the reading is one we still stand behind; secondary the
    /// moment the window or its provider stops being live.
    private var numeralInk: Color {
        if !isLive || isAtReset {
            return HeadroomWidgetStyle.secondaryText(scheme: scheme)
        }
        if window?.severity == .critical {
            return HeadroomWidgetStyle.criticalText(scheme: scheme)
        }
        return .primary
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        glance ? "\(glanceName ?? labelText) usage" : "\(labelText) usage"
    }

    /// WCM2: "Low" left the tile but not the audio description — a critical row still says
    /// so, and a retired one still says it is not current.
    private var accessibilityValue: String {
        var parts: [String] = []
        if let value = window?.displayPercentRemaining {
            parts.append("\(Int(value.rounded())) percent left")
        }
        if window?.freshness.isStale == true {
            parts.append("last known")
        }
        if window?.freshness.isUnavailable == true {
            parts.append("unavailable")
        }
        if !providerIsLive {
            parts.append("provider needs attention")
        }
        if window?.severity == .critical, isLive {
            parts.append("low")
        }
        if let window, !window.freshness.isUnavailable {
            parts.append(Countdown.resetText(
                schedule: window.resetSchedule,
                utilization: window.utilization,
                isLive: window.freshness.isLive,
                now: now
            ))
        }
        return parts.joined(separator: ", ")
    }
}

/// WCL6: `alignmentGuide` has to be applied conditionally without changing the view's type,
/// and a glance row is `.center`-aligned while a stacked meter row is `.firstTextBaseline`.
private struct CapCentred: ViewModifier {
    let enabled: Bool
    let size: Double

    func body(content: Content) -> some View {
        if enabled {
            content.widgetCapHeightCentered(size: size, weight: .semibold, mono: true)
        } else {
            content
        }
    }
}

public struct HeadroomWidgetUsageBar: View {
    private let percentRemaining: Double?
    private let severity: WidgetUsageSeverity
    private let freshness: WidgetWindowFreshness
    private let providerIsLive: Bool
    private let height: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground

    public init(
        percentRemaining: Double?,
        severity: WidgetUsageSeverity,
        freshness: WidgetWindowFreshness,
        providerIsLive: Bool,
        height: CGFloat
    ) {
        self.percentRemaining = percentRemaining
        self.severity = severity
        self.freshness = freshness
        self.providerIsLive = providerIsLive
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                track
                if let fillLength = fillLength(in: geo.size.width), fillLength > 0 {
                    Capsule()
                        .fill(fillColor)
                        .frame(width: fillLength)
                        // WCM7: the *quantity* is what an accented family should tint, so
                        // the fill is accentable and the track is not.
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// WCF6: the widgets stay flat — the tile already is the card, and a tile inside a tile
    /// is the lazy container. The depth goes here instead: at 6pt and up the track reads as
    /// a shallow well, a dark top edge and a light bottom edge one device pixel wide. Below
    /// 6pt the stroke would eat the track, so it is dropped rather than scaled.
    private var track: some View {
        Capsule()
            .fill(trackColor)
            .overlay {
                if height >= 6, usesFullColorTokens {
                    Capsule()
                        .strokeBorder(wellGradient, lineWidth: HeadroomWidgetStyle.hairlineWidth(displayScale: displayScale))
                }
            }
    }

    private var wellGradient: LinearGradient {
        let dark = scheme == .dark
        return LinearGradient(
            colors: dark
                ? [Color.black.opacity(0.18), Color.white.opacity(0.05)]
                : [Color.black.opacity(0.07), Color.white.opacity(0.30)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// WCM7/WCM8: accented and vibrant families get one neutral pair, and so does a
    /// stripped background (StandBy, the Lock Screen): the tokens below were tuned against
    /// the container gradient, and on pure black the 0.14 track is invisible.
    private var usesFullColorTokens: Bool {
        renderingMode == .fullColor && showsContainerBackground
    }

    private var isLive: Bool {
        providerIsLive && freshness.isLive
    }

    /// WCM6: one constant floor, from the popover's own geometry, so 1% is the same visible
    /// stub on a roomy tile and a dense one. `.full` at 6pt and up, `.micro` below.
    private func fillLength(in available: CGFloat) -> CGFloat? {
        guard let percentRemaining, !freshness.isUnavailable else { return nil }
        let fraction = min(1, max(0, percentRemaining / 100))
        return CGFloat(MeterGeometry.continuousFillLength(
            available: Double(available),
            fraction: fraction,
            format: height >= 6 ? .full : .micro
        ))
    }

    private var fillColor: Color {
        guard usesFullColorTokens else { return .primary }
        if !isLive {
            return HeadroomWidgetStyle.staleFill(
                for: severity,
                scheme: scheme,
                increasedContrast: contrast == .increased
            )
        }
        // WCM1: colour arrives as an event.
        guard severity != .healthy else { return HeadroomWidgetStyle.neutralFill(scheme: scheme) }
        return HeadroomWidgetStyle.severityFill(
            for: severity,
            scheme: scheme,
            increasedContrast: contrast == .increased
        )
    }

    private var trackColor: Color {
        if renderingMode != .fullColor { return Color.primary.opacity(0.20) }
        if !showsContainerBackground { return Color.primary.opacity(0.22) }
        // WCM2: `.unavailable` opts out — a red track under no value at all would be
        // asserting a reading the tile does not have.
        guard severity == .critical, isLive, !freshness.isUnavailable else {
            return HeadroomWidgetStyle.barTrack(scheme: scheme)
        }
        return HeadroomWidgetStyle.criticalBarTrack(scheme: scheme)
    }
}

/// WCW6: the API-spend strip. No eyebrow — the craft floor bans them, and a 10pt tracked
/// "API" was the same size as the amounts it labelled. The rule stays on large (spend is a
/// different *tile* in the popover; here the rule does that separating job), while medium
/// separates with air instead (WCL4). Each item is mark · amount · direction term, because
/// "$58.90" alone means money gone on a period row and money left on a balance row, and the
/// two render identically.
public struct HeadroomWidgetAPISpendStrip: View {
    private let summaries: [WidgetAPISpendSummary]
    private let now: Date
    private let family: HeadroomWidgetFamily
    private let scale: WidgetTypeScale
    private let footerText: String?
    private let showsRule: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    @ScaledMetric private var amountSize: Double
    @ScaledMetric private var termSize: Double
    @ScaledMetric private var footerSize: Double

    public init(
        summaries: [WidgetAPISpendSummary],
        now: Date,
        family: HeadroomWidgetFamily,
        scale: WidgetTypeScale,
        footerText: String?,
        showsRule: Bool
    ) {
        self.summaries = summaries
        self.now = now
        self.family = family
        self.scale = scale
        self.footerText = footerText
        self.showsRule = showsRule
        _amountSize = ScaledMetric(wrappedValue: scale.spendAmount, relativeTo: .body)
        _termSize = ScaledMetric(wrappedValue: scale.spendSuffix, relativeTo: .body)
        _footerSize = ScaledMetric(wrappedValue: scale.footer, relativeTo: .body)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsRule {
                Rectangle()
                    .fill(HeadroomWidgetStyle.widgetHairline(scheme: scheme))
                    .frame(height: HeadroomWidgetStyle.hairlineWidth(displayScale: displayScale))
                    .padding(.bottom, CGFloat(WidgetMetrics.spendRuleToRow))
                    .accessibilityHidden(true)
            }
            // WCF7: the stamp is the element that gives — dropped whole when the amounts
            // and it cannot share the run. The amounts never truncate; they are the payload.
            ViewThatFits(in: .horizontal) {
                row(showsFooter: true)
                row(showsFooter: false)
            }
        }
    }

    private func row(showsFooter: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: CGFloat(WidgetMetrics.spendItemGap)) {
                ForEach(summaries) { summary in
                    item(summary)
                }
            }
            .fixedSize()
            Spacer(minLength: 8)
            if showsFooter, let footerText {
                Text(footerText)
                    .font(HeadroomWidgetType.font(size: footerSize, weight: .medium, mono: true))
                    .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .widgetCapHeightCentered(size: footerSize, weight: .medium, mono: true)
            }
        }
    }

    private func item(_ summary: WidgetAPISpendSummary) -> some View {
        let status = rowStatus(summary)
        return HStack(alignment: .center, spacing: 5) {
            HeadroomWidgetProviderIcon(providerID: summary.id, size: 13)
            Text(amountText(summary))
                .font(HeadroomWidgetType.font(size: amountSize, weight: .semibold, mono: true))
                .foregroundStyle(amountColor(summary))
                .privacySensitive()
                .lineLimit(1)
                .widgetCapHeightCentered(size: amountSize, weight: .semibold, mono: true)
                .widgetAccentable()
            Text(APISpendPresentation.directionTerm(kind: summary.semanticKind))
                .font(HeadroomWidgetType.font(size: termSize))
                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .widgetCapHeightCentered(size: termSize, weight: .regular)
            attention(status)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(summary, status: status))
    }

    /// WCW6: large has the width to name the state — "Setup", "Rejected", "Denied",
    /// "Stale" — and those strings were written for this surface and never printed. Medium
    /// keeps the glyph and moves the word into the accessibility label; the glyph is
    /// neutral per R2C5, since a spend key problem is not a usage severity.
    @ViewBuilder
    private func attention(_ status: APISpendRowStatus) -> some View {
        if let badge = status.shortBadge {
            if family == .large {
                Text(badge)
                    .font(HeadroomWidgetType.font(size: termSize, weight: .medium))
                    .foregroundStyle(badgeInk(status.tone))
                    .lineLimit(1)
                    .widgetCapHeightCentered(size: termSize, weight: .medium)
            } else {
                // WCF1: the glyph scales the ladder token itself, so it gets the raw
                // `spendSuffix` rather than this view's already-scaled `termSize`.
                HeadroomWidgetAttentionGlyph(kind: .spend, size: scale.spendSuffix)
            }
        }
    }

    private func badgeInk(_ tone: APISpendRowStatus.Tone) -> Color {
        switch tone {
        case .critical: HeadroomWidgetStyle.criticalText(scheme: scheme)
        case .warning: HeadroomWidgetStyle.secondaryText(scheme: scheme)
        case .neutral, .quiet: HeadroomWidgetStyle.tertiaryText(scheme: scheme)
        }
    }

    private func rowStatus(_ summary: WidgetAPISpendSummary) -> APISpendRowStatus {
        APISpendPresentation.rowStatus(
            freshness: summary.freshness,
            attention: summary.attention,
            providerID: ProviderID(summary.id),
            displayName: summary.displayName,
            kind: summary.semanticKind
        )
    }

    /// The bare figure: the direction term is printed as its own element here, so the
    /// widget/phone form of `amountText` (which bakes "left" into balance rows) would
    /// double it.
    private func amountText(_ summary: WidgetAPISpendSummary) -> String {
        APISpendPresentation.amountText(amount: summary.amount, currency: summary.currency) ?? "—"
    }

    private func amountColor(_ summary: WidgetAPISpendSummary) -> Color {
        summary.amount == nil || summary.freshness != .live
            ? HeadroomWidgetStyle.secondaryText(scheme: scheme)
            : .primary
    }

    private func accessibilityText(_ summary: WidgetAPISpendSummary, status: APISpendRowStatus) -> String {
        var parts = [
            summary.displayName,
            APISpendPresentation.amountText(summary) ?? "no amount",
        ]
        if summary.amount != nil {
            parts.append(APISpendPresentation.directionTerm(kind: summary.semanticKind))
        }
        if let badge = status.badge {
            parts.append(badge)
        }
        return parts.joined(separator: ", ")
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    init(_ tint: HeadroomTint) {
        self = Color(tint.color).opacity(tint.opacity)
    }
}
