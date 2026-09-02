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
    let scheme: ColorScheme

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
            let inset = shape == .machined
                ? CGFloat(style.format == .micro ? MeterGeometry.microMachinedInset : MeterGeometry.fullTrackInset)
                : 0
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

                if fillLength > 0, MeterRecipe.fillRecipe(
                    fill: style.fill,
                    severity: severity,
                    freshness: freshness
                ) != .none {
                    continuousFill(shape: shape)
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

    private func continuousFill(shape: GaugeShape) -> some View {
        let radius = shape == .machined ? max(1, (gaugeHeight - 2 * continuousInset) / 2) : gaugeHeight / 2
        return ZStack(alignment: shape == .tube ? .top : .trailing) {
            continuousFillBody(shape: shape)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

            if drawsCap {
                RoundedRectangle(cornerRadius: capThickness / 2, style: .continuous)
                    .fill(ProviderStyle.severityColor(for: severity, scheme: scheme))
                    .frame(
                        width: shape == .tube ? nil : capThickness,
                        height: shape == .tube ? capThickness : nil
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder
    private func continuousFillBody(shape: GaugeShape) -> some View {
        switch MeterRecipe.fillRecipe(
            fill: style.fill,
            severity: severity,
            freshness: freshness
        ) {
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
            ProviderStyle.meterGhostBody(for: severity, scheme: scheme)
        case .ramp:
            LinearGradient(
                colors: [
                    ProviderStyle.meterRampStart(
                        for: severity,
                        surface: shape == .machined ? .well : .flat,
                        scheme: scheme
                    ),
                    ProviderStyle.severityColor(for: severity, scheme: scheme),
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

        return HStack(spacing: gap) {
            ForEach(0..<cells, id: \.self) { index in
                RoundedRectangle(cornerRadius: style.format == .micro ? 1.5 : 2, style: .continuous)
                    .fill(segmentedCellColor(index: index, lit: lit))
                    .frame(
                        width: style.format == .micro ? CGFloat(MeterGeometry.microCellWidth) : nil,
                        height: gaugeHeight
                    )
                    .frame(maxWidth: style.format == .full ? .infinity : nil)
            }
        }
    }

    private func segmentedCellColor(index: Int, lit: Int) -> Color {
        guard index < lit else { return ProviderStyle.meterTickOff(scheme: scheme) }
        if case .staleGrey = MeterRecipe.fillRecipe(
            fill: style.fill,
            severity: severity,
            freshness: freshness
        ) {
            return staleColor
        }

        switch MeterRecipe.cellRecipe(
            index: index,
            lit: lit,
            fill: style.fill,
            severity: severity
        ) {
        case .off:
            return ProviderStyle.meterTickOff(scheme: scheme)
        case .body(let fill):
            return cellColor(fill, isTip: false)
        case .tip(let fill):
            return cellColor(fill, isTip: true)
        }
    }

    private func cellColor(_ fill: MeterCellFill, isTip: Bool) -> Color {
        switch fill {
        case .severity:
            return flatSeverityColor
        case .glass:
            return isTip
                ? ProviderStyle.meterTickGlassCap(scheme: scheme)
                : ProviderStyle.meterTickGlass(scheme: scheme)
        case .ghost:
            return isTip
                ? ProviderStyle.severityColor(for: severity, scheme: scheme)
                : ProviderStyle.meterGhostBody(for: severity, scheme: scheme)
        case .neutral:
            return isTip
                ? ProviderStyle.meterTickGlassCap(scheme: scheme)
                : ProviderStyle.meterTickGlass(scheme: scheme)
        case .ramp(let progress):
            let stops = MeterRecipe.rampStops(
                severity: severity,
                scheme: scheme == .dark ? .dark : .light,
                surface: .well
            )
            let t = min(1, max(0, progress))
            return Color(
                red: stops.start.red + (stops.end.red - stops.start.red) * t,
                green: stops.start.green + (stops.end.green - stops.start.green) * t,
                blue: stops.start.blue + (stops.end.blue - stops.start.blue) * t
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

    private var drawsCap: Bool {
        guard freshness.isLive else { return false }
        return style.fill == .glass || style.fill == .ghost
    }

    private var flatSeverityColor: Color {
        let opacity = scheme == .dark ? (severity == .critical ? 0.95 : 0.85) : 1
        return ProviderStyle.severityColor(for: severity, scheme: scheme).opacity(opacity)
    }

    private var staleColor: Color { Color.secondary.opacity(0.55) }

    private func continuousFillLength(available: CGFloat) -> CGFloat {
        guard clampedFraction > 0, !freshness.isUnavailable else { return 0 }
        let minimum: CGFloat = style.format == .micro ? 3 : 6
        return min(available, max(minimum, available * clampedFraction))
    }
}
