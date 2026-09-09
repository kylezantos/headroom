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
    /// AP2 / FS2: swatch-only request for a *miniature* segmented gauge. `nil` — the default,
    /// and the only value any real meter uses — means the shipped cell count and the format's
    /// own cell metrics. Non-nil means "draw this many cells at Micro's cell height, gap, and
    /// radius, whatever the format is", still laid out full-width for Full.
    ///
    /// The Settings Format swatch is the one caller: it renders Full inside a 60pt fragment.
    /// FS2 made the Full cell 14.5pt tall, so overriding only the count would comb the swatch
    /// into micro-width × full-height slivers; the swatch's whole point is "the same little
    /// chips, just more of them, placed differently". Non-segmented shapes ignore it.
    var miniatureSegmentCount: Int? = nil

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
            let cells = CGFloat(resolvedCellCount)
            return cells * CGFloat(MeterGeometry.microCellWidth)
                + (cells - 1) * CGFloat(MeterGeometry.microCellGap)
        case .tube: return CGFloat(MeterGeometry.microTubeWidth)
        }
    }

    private var gaugeHeight: CGFloat {
        switch (style.format, resolvedShape) {
        // FS2: segmented rows size to the *cell* format, which the miniature override can
        // pull back to Micro — so the swatch's frame reserves 5pt, not Full's 14.5pt.
        case (_, .segmented): return CGFloat(MeterGeometry.cellHeight(for: segmentedCellFormat))
        case (.micro, .chip): return CGFloat(MeterGeometry.microChipHeight)
        case (.micro, .machined): return CGFloat(MeterGeometry.microMachinedHeight)
        case (.micro, .tube): return CGFloat(MeterGeometry.microTubeHeight)
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
                    continuousFillLayer(shape: shape, recipe: fillRecipe, fillLength: fillLength)
                }
            }
            // L7B: the cap is a separate marker, so it lives outside the fill's clip *and*
            // outside the ZStack's sizing. An overlay never feeds the parent's layout, which
            // is what keeps a 10pt cap from stretching an 8pt track.
            .overlay(alignment: isVertical ? .bottom : .leading) {
                if fillLength > 0, fillRecipe == .glass || fillRecipe == .ghost {
                    capMarker(shape: shape, fillLength: fillLength, available: availableLength)
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

    /// L8A: the menu bar vessel's recipe (`VesselGlyph.render`). The body is a plain rect of
    /// `fillLength` and the *track's own shape* clips the whole layer, so the base inherits the
    /// track's rounding while the trailing edge stays dead flat. The gradient fills still span
    /// the body, not the track, because the clip sits outside the body's frame.
    private func continuousFillLayer(
        shape: GaugeShape,
        recipe: MeterFillRecipe,
        fillLength: CGFloat
    ) -> some View {
        let isVertical = shape == .tube
        return continuousFillBody(shape: shape, recipe: recipe)
            .frame(
                width: isVertical ? nil : fillLength,
                height: isVertical ? fillLength : nil
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: isVertical ? .bottom : .leading
            )
            .clipShape(continuousFillClip(shape: shape))
            // Applied after the clip so the clip rect *is* the machined well's inner rect.
            .padding(continuousInset)
    }

    private func continuousFillClip(shape: GaugeShape) -> AnyShape {
        guard shape == .machined else { return AnyShape(Capsule(style: .continuous)) }
        let radius = max(1, (gaugeHeight - 2 * continuousInset) / 2)
        return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// L7B: a standalone marker in the severity FILL tier, centered on the fill's flat trailing
    /// edge and overlapping the track outline on both sides. The ZStack's leading/bottom
    /// alignment supplies the cross-axis centering, so the overhang is symmetric by
    /// construction; the offset only moves it along the travel axis.
    private func capMarker(shape: GaugeShape, fillLength: CGFloat, available: CGFloat) -> some View {
        let isVertical = shape == .tube
        let axis: MeterFillAxis = isVertical ? .vertical : .horizontal
        let cap = MeterGeometry.cap(for: style.format)
        let center = continuousInset + CGFloat(MeterGeometry.capCenterOffset(
            fillLength: Double(fillLength),
            available: Double(available),
            cap: cap
        ))
        let travel = center - CGFloat(cap.thickness) / 2
        return RoundedRectangle(cornerRadius: CGFloat(cap.cornerRadius), style: .continuous)
            .fill(severityFillColor)
            .frame(width: CGFloat(cap.width(on: axis)), height: CGFloat(cap.height(on: axis)))
            .offset(x: isVertical ? 0 : travel, y: isVertical ? -travel : 0)
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

    private var resolvedCellCount: Int {
        miniatureSegmentCount ?? MeterRecipe.cellCount(for: style.format)
    }

    /// FS2: which format's cell metrics (height, gap, radius) a segmented gauge draws with.
    /// It is the style's own format everywhere except a miniature swatch, which asks for
    /// Micro's cell at any format so it stays a strip of little chips.
    private var segmentedCellFormat: GaugeFormat {
        miniatureSegmentCount == nil ? style.format : .micro
    }

    private var segmentedGauge: some View {
        let cells = resolvedCellCount
        let cellFormat = segmentedCellFormat
        let lit = freshness.isUnavailable
            ? 0
            : MeterRecipe.litCellCount(fraction: clampedFraction, cells: cells)
        let gap = CGFloat(MeterGeometry.cellGap(for: cellFormat))
        let radius = CGFloat(MeterGeometry.cellRadius(for: cellFormat))
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
                RoundedRectangle(cornerRadius: radius, style: .continuous)
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
            // FS1 (Kyle, Sep 2026): the tip is the reading; the body is the trail behind it.
            // Body cells step back to `segmentBodyAttenuation` of their own colour so the tip
            // has something to read against. `.staleGrey` is exempt — it is already a dim, and
            // dimming a dim would blur the live/stale distinction.
            return fillRecipe == .staleGrey
                ? staleColor
                : cellColor(fill, isTip: false, rampStops: rampStops)
                    .opacity(HeadroomMeterColorValues.segmentBodyAttenuation)
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
                    .fill(ProviderStyle.meterQuarterMark(scheme: scheme))
                    .frame(width: 1, height: max(0, size.height - 4))
                    .position(x: size.width * fraction, y: size.height / 2)
            }
        }
    }

    private var continuousInset: CGFloat {
        guard resolvedShape == .machined else { return 0 }
        return CGFloat(style.format == .micro ? MeterGeometry.microMachinedInset : MeterGeometry.fullTrackInset)
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

    private var staleColor: Color { ProviderStyle.meterStaleFill }

    private func continuousFillLength(available: CGFloat) -> CGFloat {
        guard !freshness.isUnavailable else { return 0 }
        return CGFloat(MeterGeometry.continuousFillLength(
            available: Double(available),
            fraction: clampedFraction,
            format: style.format
        ))
    }
}
