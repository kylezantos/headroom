import SwiftUI
import HeadroomCore

/// The popover's one shape × fill renderer. All visual decisions that affect how much
/// is lit come from `MeterRecipe`; this view only turns those semantic recipes into
/// SwiftUI geometry.
struct MeterGauge: View {
    let style: MeterStyle
    let fraction: Double
    let severity: UsageSeverity
    let freshness: UsageWindowFreshness

    @Environment(\.colorScheme) private var scheme
    // Fill tier lookup: Increase Contrast swaps the vivid light bar fills back to the
    // darker text-tier values that clear WCAG 1.4.11's 3:1 floor. Read here at the SwiftUI
    // boundary so the Core tokens stay pure. See `HeadroomSeverityColorValues`.
    @Environment(\.colorSchemeContrast) private var contrast

    private var increasedContrast: Bool { contrast == .increased }

    private var resolvedShape: GaugeShape { style.resolvedShape }
    private var clampedFraction: Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    var body: some View {
        Group {
            switch resolvedShape {
            case .chip:
                continuousGauge(shape: .chip)
            case .machined:
                continuousGauge(shape: .machined)
            case .segmented:
                segmentedGauge
            case .tube:
                continuousGauge(shape: .tube)
            }
        }
        .frame(
            width: style.format == .micro ? microWidth : nil,
            height: gaugeHeight
        )
        .frame(maxWidth: style.format == .full ? .infinity : nil)
        .accessibilityHidden(true)
    }

    private var microWidth: CGFloat {
        switch resolvedShape {
        case .chip: return CGFloat(MeterGeometry.microChipWidth)
        case .machined: return CGFloat(MeterGeometry.microMachinedWidth)
        case .segmented:
            let cells = CGFloat(MeterRecipe.cellCount(for: .micro))
            return cells * CGFloat(MeterGeometry.microCellWidth)
                + (cells - 1) * CGFloat(MeterGeometry.microCellGap)
        case .tube: return CGFloat(MeterGeometry.microTubeWidth)
        }
    }

    private var gaugeHeight: CGFloat {
        switch (style.format, resolvedShape) {
        case (.micro, .chip): return CGFloat(MeterGeometry.microChipHeight)
        case (.micro, .machined): return CGFloat(MeterGeometry.microMachinedHeight)
        case (.micro, .segmented): return CGFloat(MeterGeometry.microCellHeight)
        case (.micro, .tube): return CGFloat(MeterGeometry.microTubeHeight)
        case (.full, .segmented): return CGFloat(MeterGeometry.fullCellHeight)
        case (.full, _): return CGFloat(MeterGeometry.fullTrackHeight)
        }
    }

    private func continuousGauge(shape: GaugeShape) -> some View {
        GeometryReader { geometry in
            let isVertical = shape == .tube
            let inset = continuousInset
            let fillRecipe = MeterRecipe.fillRecipe(
                fill: style.fill,
                severity: severity,
                freshness: freshness
            )
            let availableLength = max(
                0,
                (isVertical ? geometry.size.height : geometry.size.width) - inset * 2
            )
            let fillLength = continuousFillLength(available: availableLength)

            ZStack(alignment: isVertical ? .bottom : .leading) {
                continuousTrack(shape: shape)

                if style.drawsQuarterMarks {
                    quarterMarks(in: geometry.size)
                }

                if fillLength > 0, fillRecipe != .none {
                    continuousFill(shape: shape, recipe: fillRecipe)
                        .frame(
                            width: isVertical ? max(0, geometry.size.width - inset * 2) : fillLength,
                            height: isVertical ? fillLength : max(0, geometry.size.height - inset * 2)
                        )
                        .padding(isVertical ? .horizontal : .vertical, inset)
                        .padding(isVertical ? .bottom : .leading, inset)
                }
            }
        }
    }

    @ViewBuilder
    private func continuousTrack(shape: GaugeShape) -> some View {
        if shape == .machined {
            RoundedRectangle(cornerRadius: gaugeHeight / 2, style: .continuous)
                .fill(ProviderStyle.meterWellBackground(scheme: scheme))
                .overlay {
                    RoundedRectangle(cornerRadius: gaugeHeight / 2, style: .continuous)
                        .strokeBorder(ProviderStyle.meterWellShadow(scheme: scheme), lineWidth: 0.75)
                }
        } else {
            Capsule(style: .continuous)
                .fill(ProviderStyle.barTrack(scheme: scheme))
        }
    }

    private func continuousFill(shape: GaugeShape, recipe: MeterFillRecipe) -> some View {
        let radius = shape == .machined ? max(1, (gaugeHeight - 2 * continuousInset) / 2) : gaugeHeight / 2
        return ZStack(alignment: shape == .tube ? .top : .trailing) {
            continuousFillBody(shape: shape, recipe: recipe)

            if recipe == .glass || recipe == .ghost {
                RoundedRectangle(cornerRadius: capThickness / 2, style: .continuous)
                    .fill(severityFillColor)
                    .frame(
                        width: shape == .tube ? nil : capThickness,
                        height: shape == .tube ? capThickness : nil
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder
    private func continuousFillBody(shape: GaugeShape, recipe: MeterFillRecipe) -> some View {
        switch recipe {
        case .none:
            Color.clear
        case .staleGrey:
            staleColor
        case .solid:
            flatSeverityColor
        case .glass, .neutral:
            LinearGradient(
                colors: [
                    ProviderStyle.meterGlassA(scheme: scheme),
                    ProviderStyle.meterGlassB(scheme: scheme),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .ghost:
            ProviderStyle.meterGhostBody(
                for: severity,
                scheme: scheme,
                increasedContrast: increasedContrast
            )
        case .ramp:
            LinearGradient(
                colors: [
                    ProviderStyle.meterRampStart(
                        for: severity,
                        surface: shape == .machined ? .well : .flat,
                        scheme: scheme,
                        increasedContrast: increasedContrast
                    ),
                    severityFillColor,
                ],
                startPoint: shape == .tube ? .bottom : .leading,
                endPoint: shape == .tube ? .top : .trailing
            )
        }
    }

    private var segmentedGauge: some View {
        let cells = MeterRecipe.cellCount(for: style.format)
        let lit = freshness.isUnavailable
            ? 0
            : MeterRecipe.litCellCount(fraction: clampedFraction, cells: cells)
        let gap = CGFloat(style.format == .micro ? MeterGeometry.microCellGap : MeterGeometry.fullCellGap)
        let fillRecipe = MeterRecipe.fillRecipe(
            fill: style.fill,
            severity: severity,
            freshness: freshness
        )
        let rampStops = style.fill == .hueRamp
            ? MeterRecipe.rampStops(
                severity: severity,
                scheme: scheme == .dark ? .dark : .light,
                surface: .well,
                increasedContrast: increasedContrast
            )
            : nil

        return HStack(spacing: gap) {
            ForEach(0..<cells, id: \.self) { index in
                RoundedRectangle(cornerRadius: style.format == .micro ? 1.5 : 2, style: .continuous)
                    .fill(segmentedCellColor(
                        index: index,
                        lit: lit,
                        fillRecipe: fillRecipe,
                        rampStops: rampStops
                    ))
                    .frame(
                        width: style.format == .micro ? CGFloat(MeterGeometry.microCellWidth) : nil,
                        height: gaugeHeight
                    )
                    .frame(maxWidth: style.format == .full ? .infinity : nil)
            }
        }
    }

    private func segmentedCellColor(
        index: Int,
        lit: Int,
        fillRecipe: MeterFillRecipe,
        rampStops: MeterRampStops?
    ) -> Color {
        let cellRecipe = MeterRecipe.cellRecipe(
            index: index,
            lit: lit,
            fill: style.fill,
            severity: severity
        )
        switch cellRecipe {
        case .off:
            return ProviderStyle.meterTickOff(scheme: scheme)
        case .body(let fill):
            return fillRecipe == .staleGrey
                ? staleColor
                : cellColor(fill, isTip: false, rampStops: rampStops)
        case .tip(let fill):
            return fillRecipe == .staleGrey
                ? staleColor
                : cellColor(fill, isTip: true, rampStops: rampStops)
        }
    }

    private func cellColor(
        _ fill: MeterCellFill,
        isTip: Bool,
        rampStops: MeterRampStops?
    ) -> Color {
        switch fill {
        case .severity:
            return isTip ? severityFillColor : flatSeverityColor
        case .glass:
            return isTip
                ? ProviderStyle.meterTickGlassCap(scheme: scheme)
                : ProviderStyle.meterTickGlass(scheme: scheme)
        case .ghost:
            return isTip
                ? severityFillColor
                : ProviderStyle.meterGhostBody(
                    for: severity,
                    scheme: scheme,
                    increasedContrast: increasedContrast
                )
        case .neutral:
            return isTip
                ? ProviderStyle.meterTickGlassCap(scheme: scheme)
                : ProviderStyle.meterTickGlass(scheme: scheme)
        case .ramp(let progress):
            guard let stops = rampStops else { return flatSeverityColor }
            return Color(
                red: stops.start.red + (stops.end.red - stops.start.red) * progress,
                green: stops.start.green + (stops.end.green - stops.start.green) * progress,
                blue: stops.start.blue + (stops.end.blue - stops.start.blue) * progress
            )
        }
    }

    private func quarterMarks(in size: CGSize) -> some View {
        ZStack {
            ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                Rectangle()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.11 : 0.14))
                    .frame(width: 1, height: max(0, size.height - 4))
                    .position(x: size.width * fraction, y: size.height / 2)
            }
        }
    }

    private var continuousInset: CGFloat {
        guard resolvedShape == .machined else { return 0 }
        return CGFloat(style.format == .micro ? MeterGeometry.microMachinedInset : MeterGeometry.fullTrackInset)
    }

    private var capThickness: CGFloat {
        CGFloat(style.format == .micro ? MeterGeometry.microCapThickness : MeterGeometry.fullCapThickness)
    }

    private var severityFillColor: Color {
        ProviderStyle.severityFill(
            for: severity,
            scheme: scheme,
            increasedContrast: increasedContrast
        )
    }

    private var flatSeverityColor: Color {
        let opacity = scheme == .dark ? (severity == .critical ? 0.95 : 0.85) : 1
        return severityFillColor.opacity(opacity)
    }

    private var staleColor: Color { Color.secondary.opacity(0.55) }

    private func continuousFillLength(available: CGFloat) -> CGFloat {
        guard clampedFraction > 0, !freshness.isUnavailable else { return 0 }
        let minimum: CGFloat = style.format == .micro ? 3 : 6
        return min(available, max(minimum, available * clampedFraction))
    }
}
