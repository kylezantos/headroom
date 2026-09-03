import SwiftUI
import HeadroomCore

/// Global popover meter controls. Shape and fill choices are deliberately rendered
/// by `MeterGauge` itself, so the controls stay truthful as the renderer evolves.
struct MeterStyleTile: View {
    let meterStyle: MeterStyle
    let formatPickerMaxWidth: CGFloat
    let onChange: (MeterStyle) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let rowLabelWidth: CGFloat = 46
    private let rowSpacing: CGFloat = 12
    private let swatchSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: rowSpacing) {
                rowLabel("Format")
                Spacer(minLength: rowSpacing)
                formatPicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Format")
                formatPicker
            }
        }
    }

    private var formatPicker: some View {
        Picker("Format", selection: formatBinding) {
            ForEach(GaugeFormat.allCases) { format in
                Text(format.label).tag(format)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: formatPickerMaxWidth)
    }

    private var shapeRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: rowSpacing) {
                rowLabel("Shape")
                LazyVGrid(columns: shapeColumns, alignment: .leading, spacing: swatchSpacing) {
                    ForEach(GaugeShape.allCases) { shape in
                        shapeSwatch(shape)
                    }
                }
            }

            if meterStyle.format == .full {
                SettingsHelpText(text: "Tube is available only with Micro format.")
                    .padding(.leading, rowLabelWidth + rowSpacing)
            }
        }
    }

    private var fillRow: some View {
        HStack(alignment: .top, spacing: rowSpacing) {
            rowLabel("Fill")
            LazyVGrid(columns: fillColumns, alignment: .leading, spacing: swatchSpacing) {
                ForEach(GaugeFill.allCases) { fill in
                    fillSwatch(fill)
                }
            }
        }
    }

    private var shapeColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 64, maximum: 80), spacing: swatchSpacing)]
    }

    private var fillColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 78, maximum: 88), spacing: swatchSpacing)]
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: rowLabelWidth, alignment: .leading)
    }

    private var formatBinding: Binding<GaugeFormat> {
        Binding(
            get: { meterStyle.format },
            set: { format in
                onChange(MeterStyle(format: format, shape: meterStyle.shape, fill: meterStyle.fill))
            }
        )
    }

    private func shapeSwatch(_ shape: GaugeShape) -> some View {
        let isSelected = meterStyle.shape == shape
        let isAvailable = shape.resolved(for: meterStyle.format) == shape

        return Button {
            onChange(MeterStyle(format: meterStyle.format, shape: shape, fill: meterStyle.fill))
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ClaudeSetupStyle.wellBackground(dark: colorScheme == .dark))
                    MeterGauge(
                        style: MeterStyle(format: .micro, shape: shape, fill: .glass),
                        fraction: 0.62,
                        severity: .healthy,
                        freshness: .live
                    )
                }
                .frame(height: 26)

                Text(shape.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isAvailable ? 1 : 0.45)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .meterStyleSelectionBorder(isSelected: isSelected, colorScheme: colorScheme)
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
            VStack(spacing: 5) {
                VStack(spacing: 4) {
                    referenceGauge(fill: fill, fraction: 0.62, severity: .healthy)
                    referenceGauge(fill: fill, fraction: 0.38, severity: .low)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    ClaudeSetupStyle.wellBackground(dark: colorScheme == .dark),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

                Text(fill.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 28, alignment: .top)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .meterStyleSelectionBorder(isSelected: isSelected, colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .help(fill.label)
        .accessibilityLabel("\(fill.label) fill")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
    func meterStyleSelectionBorder(
        isSelected: Bool,
        colorScheme: ColorScheme
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor
                        : ClaudeSetupStyle.hairline(dark: colorScheme == .dark),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }
}
