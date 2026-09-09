import SwiftUI
import HeadroomCore

/// Global popover meter controls. Every choice is deliberately rendered by `MeterGauge`
/// itself, so the controls stay truthful as the renderer evolves.
///
/// L12B: three homogeneous swatch rows. Format lost its segmented control — Full and Micro
/// are swatches showing a mini card fragment each — and the row names became captions above
/// their rows instead of a 46pt left label column, so the tile has one rhythm instead of three.
///
/// PA5: a swatch previews against the **live** selection. Each row varies exactly one axis
/// and takes the other drawn axes from `meterStyle`, so nothing on screen is a style the
/// user's meters would never draw. (Before this, every Shape swatch wore a Glass end cap and
/// three rows painted healthy green while the specimen above them painted the same window
/// grey, because the swatches hard-coded chip/solid/glass.) Only the 0.62/0.38 fractions and
/// their severities stay literal — those are the *subject* of the comparison, not a setting.
///
/// The Shape and Fill rows still draw at `.micro`. That is a rendering scale, not a pinned
/// preview axis: a 66 × 26pt well cannot show a Full-format bar at anything near its real
/// cell pitch (Full segmented is 20 cells, which would comb down to ~3pt each), and Format is
/// previewed by the row that owns it.
struct MeterStyleTile: View {
    let meterStyle: MeterStyle
    let onChange: (MeterStyle) -> Void

    init(
        meterStyle: MeterStyle,
        onChange: @escaping (MeterStyle) -> Void
    ) {
        self.meterStyle = meterStyle
        self.onChange = onChange
    }

    @Environment(\.colorScheme) private var colorScheme

    /// L12B: one fixed column rhythm across all three rows. Five 76pt columns on 8pt gaps
    /// need 412pt; at the 720pt minimum window the detail column is 504pt, so the tile is
    /// 464pt wide and its 438pt interior clears that without wrapping or shrinking.
    private let swatchWidth: CGFloat = 76
    private let swatchSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 16
    private let captionSpacing: CGFloat = 6
    private let columnCount = 5
    /// The width of the mini card fragment inside a Format swatch. AP2 reads it too, so the
    /// swatch's segment pitch is derived from the same number that sizes the fragment.
    private let fragmentWidth: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text("Meter style")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.2)

            formatRow
            shapeRow
            fillRow
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10, surface: .opaque)
    }

    private var formatRow: some View {
        swatchRow("Format") {
            ForEach(GaugeFormat.allCases) { format in
                formatSwatch(format)
            }
        }
    }

    private var shapeRow: some View {
        swatchRow("Shape") {
            ForEach(GaugeShape.allCases) { shape in
                shapeSwatch(shape)
            }
        } footer: {
            if meterStyle.format == .full {
                SettingsHelpText(text: "Tube is available only with Micro format.")
            }
        }
    }

    private var fillRow: some View {
        swatchRow("Fill") {
            ForEach(GaugeFill.allCases) { fill in
                fillSwatch(fill)
            }
        } footer: {
            // PB7: the Fill row shipped five renderer names and no help line while every
            // other row in the window had one. Copy is the decided wording — Glass and
            // Ghost share a clause because they differ only in track weight.
            SettingsHelpText(
                text: "Solid is always coloured. Color as event stays neutral until usage runs low. "
                    + "Hue ramp shifts colour as it empties. Glass and Ghost add a bright end cap."
            )
        }
    }

    /// L12B: a fixed five-column grid, not an adaptive one, so Format (2), Shape (4), and
    /// Fill (5) all sit on the same column centers.
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(swatchWidth), spacing: swatchSpacing, alignment: .leading),
            count: columnCount
        )
    }

    private func swatchRow<Swatches: View, Footer: View>(
        _ caption: String,
        @ViewBuilder swatches: () -> Swatches,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: captionSpacing) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: swatchSpacing) {
                swatches()
            }

            footer()
        }
    }

    // MARK: - Swatches

    /// L12B: the two formats are mini card fragments — a "Weekly" caption over a full-width
    /// bar, or the same caption with the micro chip inline beside it — so the swatch shows
    /// the row layout the format produces rather than naming it.
    private func formatSwatch(_ format: GaugeFormat) -> some View {
        let isSelected = meterStyle.format == format

        return Button {
            onChange(MeterStyle(format: format, shape: meterStyle.shape, fill: meterStyle.fill))
        } label: {
            swatchBody(label: format.label) {
                Group {
                    switch format {
                    case .full:
                        VStack(alignment: .leading, spacing: 3) {
                            fragmentCaption
                            fragmentGauge(format: .full)
                        }
                    case .micro:
                        HStack(spacing: 4) {
                            fragmentCaption
                            fragmentGauge(format: .micro)
                        }
                    }
                }
                .frame(width: fragmentWidth, alignment: .leading)
            }
            .selectionChrome(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(format.label)
        .accessibilityLabel("\(format.label) format")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var fragmentCaption: some View {
        Text("Weekly")
            .font(.system(size: 6))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    /// PA5: shape and fill ride the live selection (`MeterGauge` resolves Tube to Chip for
    /// Full itself), so the Format row compares two *layouts* of the meter the user actually
    /// has rather than two drawings of a chip/solid meter they may never have chosen.
    ///
    /// AP2 (Kyle): "show the same little segment chips as in the micro version — there are
    /// just more of them and they're placed differently." Full's real 20 cells inside a 60pt
    /// fragment are 2pt ticks, so Segmented Full asks for however many *micro-sized* cells
    /// fit the fragment instead.
    ///
    /// FS2 (Kyle, Sep 2026): the Full cell is now 14.5pt tall, so a count override on its own
    /// would draw micro-width × full-height slivers inside a 26pt well. `miniatureSegmentCount`
    /// therefore carries the whole miniature cell — Micro's height, gap, and radius — while the
    /// row keeps Full's full-width spread under the caption, which is the layout difference the
    /// swatch is actually previewing.
    private func fragmentGauge(format: GaugeFormat) -> some View {
        MeterGauge(
            style: MeterStyle(format: format, shape: meterStyle.shape, fill: meterStyle.fill),
            fraction: 0.62,
            severity: .healthy,
            freshness: .live,
            // FS3: count as many *miniature Full* cells (the real cell scaled to Micro height)
            // as the fragment fits, so the swatch is the shipped row in small.
            miniatureSegmentCount: format == .full
                ? MeterGeometry.segmentCount(
                    fittingWidth: Double(fragmentWidth),
                    cellWidth: MeterGeometry.miniatureCell(for: .full).width,
                    gap: MeterGeometry.miniatureCell(for: .full).gap
                )
                : nil
        )
    }

    private func shapeSwatch(_ shape: GaugeShape) -> some View {
        let isSelected = meterStyle.shape == shape
        let isAvailable = shape.resolved(for: meterStyle.format) == shape

        return Button {
            onChange(MeterStyle(format: meterStyle.format, shape: shape, fill: meterStyle.fill))
        } label: {
            swatchBody(label: shape.label) {
                // PA5: fill follows the live selection. Pinned to Glass, all four shapes wore
                // an end cap the shipping default never draws.
                MeterGauge(
                    style: MeterStyle(format: .micro, shape: shape, fill: meterStyle.fill),
                    fraction: 0.62,
                    severity: .healthy,
                    freshness: .live
                )
            }
            .opacity(isAvailable ? 1 : 0.45)
            .selectionChrome(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(isAvailable ? shape.label : "Tube is available only with Micro format.")
        .accessibilityLabel("\(shape.label) shape")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func fillSwatch(_ fill: GaugeFill) -> some View {
        let isSelected = meterStyle.fill == fill

        return Button {
            onChange(MeterStyle(format: meterStyle.format, shape: meterStyle.shape, fill: fill))
        } label: {
            swatchBody(label: fill.label, labelLines: 2) {
                // The healthy/low pair is the subject of this row, so the two fractions and
                // severities stay literal (PA5) — only the shape they are drawn on follows
                // the live selection. Tube is vertical, so the pair sits side by side there;
                // stacked it would need 36pt inside a 26pt well.
                referencePair {
                    referenceGauge(fill: fill, fraction: 0.62, severity: .healthy)
                    referenceGauge(fill: fill, fraction: 0.38, severity: .low)
                }
            }
            .selectionChrome(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(fill.label)
        .accessibilityLabel("\(fill.label) fill")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    /// The one swatch shell every row shares: a 26pt well over a 10.5pt label, 5pt apart,
    /// inside 5pt of padding.
    private func swatchBody<Content: View>(
        label: String,
        labelLines: Int = 1,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 5) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    ClaudeSetupStyle.wellBackground(dark: colorScheme == .dark),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(labelLines, reservesSpace: labelLines > 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: labelLines > 1 ? 28 : nil, alignment: .top)
        }
        .padding(5)
    }

    /// The shape the user's meters are *drawing*, which is what the Fill row previews on:
    /// Tube stays stored while Full is selected but renders as Chip, so the raw `shape`
    /// would preview a tube nothing on the popover shows.
    private var drawnShape: GaugeShape { meterStyle.shape.resolved(for: meterStyle.format) }

    /// Stacks the healthy/low pair for the horizontal shapes and sets them abreast for Tube,
    /// which is drawn bottom-up.
    @ViewBuilder private func referencePair<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if drawnShape == .tube {
            HStack(spacing: 8) { content() }
        } else {
            VStack(spacing: 4) { content() }
        }
    }

    private func referenceGauge(
        fill: GaugeFill,
        fraction: Double,
        severity: UsageSeverity
    ) -> some View {
        MeterGauge(
            style: MeterStyle(format: .micro, shape: drawnShape, fill: fill),
            fraction: fraction,
            severity: severity,
            freshness: .live
        )
    }
}
