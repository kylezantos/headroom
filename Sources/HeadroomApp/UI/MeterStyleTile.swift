import SwiftUI
import HeadroomCore

/// Global popover meter controls. Every choice is deliberately rendered by `MeterGauge`
/// itself, so the controls stay truthful as the renderer evolves.
///
/// L12B: three homogeneous swatch rows. Format lost its segmented control — Full and Micro
/// are swatches showing a mini card fragment each — and the row names became captions above
/// their rows instead of a 46pt left label column, so the tile has one rhythm instead of three.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// L12B: one fixed column rhythm across all three rows. Five 76pt columns on 8pt gaps
    /// need 412pt; at the 720pt minimum window the detail column is 504pt, so the tile is
    /// 464pt wide and its 438pt interior clears that without wrapping or shrinking.
    private let swatchWidth: CGFloat = 76
    private let swatchSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 16
    private let captionSpacing: CGFloat = 6
    private let columnCount = 5

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
                .frame(width: 60, alignment: .leading)
            }
            .meterStyleSwatchChrome(isSelected: isSelected, colorScheme: colorScheme, reduceMotion: reduceMotion)
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

    private func fragmentGauge(format: GaugeFormat) -> some View {
        MeterGauge(
            style: MeterStyle(format: format, shape: .chip, fill: .solid),
            fraction: 0.62,
            severity: .healthy,
            freshness: .live
        )
    }

    private func shapeSwatch(_ shape: GaugeShape) -> some View {
        let isSelected = meterStyle.shape == shape
        let isAvailable = shape.resolved(for: meterStyle.format) == shape

        return Button {
            onChange(MeterStyle(format: meterStyle.format, shape: shape, fill: meterStyle.fill))
        } label: {
            swatchBody(label: shape.label) {
                MeterGauge(
                    style: MeterStyle(format: .micro, shape: shape, fill: .glass),
                    fraction: 0.62,
                    severity: .healthy,
                    freshness: .live
                )
            }
            .opacity(isAvailable ? 1 : 0.45)
            .meterStyleSwatchChrome(isSelected: isSelected, colorScheme: colorScheme, reduceMotion: reduceMotion)
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
                VStack(spacing: 4) {
                    referenceGauge(fill: fill, fraction: 0.62, severity: .healthy)
                    referenceGauge(fill: fill, fraction: 0.38, severity: .low)
                }
            }
            .meterStyleSwatchChrome(isSelected: isSelected, colorScheme: colorScheme, reduceMotion: reduceMotion)
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

    private func referenceGauge(
        fill: GaugeFill,
        fraction: Double,
        severity: UsageSeverity
    ) -> some View {
        MeterGauge(
            style: MeterStyle(format: .micro, shape: .chip, fill: fill),
            fraction: fraction,
            severity: severity,
            freshness: .live
        )
    }
}

private extension View {
    func meterStyleSwatchChrome(
        isSelected: Bool,
        colorScheme: ColorScheme,
        reduceMotion: Bool
    ) -> some View {
        frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor
                            : ClaudeSetupStyle.hairline(dark: colorScheme == .dark),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            // M5A: the swatch ring picked up no motion at all when the theme thumbnails
            // beside it already tinted and thickened on the press token. Same token, same
            // 100ms, so the two pickers in one pane answer a click identically.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.pressDown, .crossfade, reduceMotion: reduceMotion),
                value: isSelected
            )
    }
}
