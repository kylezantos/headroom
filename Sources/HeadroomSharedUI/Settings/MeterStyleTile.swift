import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif

/// The geometry a host gives `MeterStyleTile`. The Mac's values are the ones the tile has
/// always drawn (L12B); the phone sets its own to fit a native list row (U12).
public struct MeterStyleTileMetrics: Sendable {
    /// Between the Format, Shape and Fill rows.
    public var rowSpacing: CGFloat
    /// A row's caption to its swatch grid.
    public var captionSpacing: CGFloat
    public var swatchWidth: CGFloat
    public var swatchSpacing: CGFloat
    /// The swatch's own inset around its well and label.
    public var swatchPadding: CGFloat
    public var wellHeight: CGFloat
    public var wellCornerRadius: CGFloat
    /// The well to the swatch label.
    public var labelSpacing: CGFloat
    public var labelFont: Font
    /// The reserved height of a two-line swatch label (the Fill row).
    public var twoLineLabelHeight: CGFloat
    public var labelMinimumScaleFactor: CGFloat
    /// The width of the mini card fragment inside a Format swatch (the Mac's 60; AP2 reads it
    /// too, so the swatch's segment pitch follows the same number).
    public var fragmentWidth: CGFloat

    public init(
        rowSpacing: CGFloat, captionSpacing: CGFloat, swatchWidth: CGFloat, swatchSpacing: CGFloat,
        swatchPadding: CGFloat, wellHeight: CGFloat, wellCornerRadius: CGFloat, labelSpacing: CGFloat,
        labelFont: Font, twoLineLabelHeight: CGFloat, labelMinimumScaleFactor: CGFloat,
        fragmentWidth: CGFloat
    ) {
        self.rowSpacing = rowSpacing
        self.captionSpacing = captionSpacing
        self.swatchWidth = swatchWidth
        self.swatchSpacing = swatchSpacing
        self.swatchPadding = swatchPadding
        self.wellHeight = wellHeight
        self.wellCornerRadius = wellCornerRadius
        self.labelSpacing = labelSpacing
        self.labelFont = labelFont
        self.twoLineLabelHeight = twoLineLabelHeight
        self.labelMinimumScaleFactor = labelMinimumScaleFactor
        self.fragmentWidth = fragmentWidth
    }
}

/// The host's Settings vocabulary: its captions, help lines, swatch press style and selection
/// chrome. The Mac passes its `SettingsTile` family (PB13, SM1, R2M6); the phone passes a
/// neutral list chrome. The tile itself owns only the swatches and what they draw.
@MainActor public protocol MeterStyleTileChrome {
    associatedtype Caption: View
    associatedtype Help: View
    associatedtype Selection: ViewModifier
    associatedtype SelectionGroup: ViewModifier
    associatedtype SwatchStyle: ButtonStyle
    associatedtype Container: ViewModifier

    var metrics: MeterStyleTileMetrics { get }
    @ViewBuilder func caption(_ text: String) -> Caption
    @ViewBuilder func help(_ text: String) -> Help
    /// A swatch's selected/unselected chrome.
    func selection(isSelected: Bool) -> Selection
    /// One row of swatches, so a selection plate can travel within it (SM1).
    func selectionGroup(value: AnyHashable) -> SelectionGroup
    var swatchStyle: SwatchStyle { get }
    /// What the three rows sit in: the Mac's titled `SettingsTile`, or nothing on the phone,
    /// whose list section is the container.
    func container() -> Container
    /// CA-S11: the caption under a Fill swatch. Defaults to the Core label the phone prints;
    /// the Mac passes a shorter form that fits one line at its compact swatch width.
    func fillLabel(_ fill: GaugeFill) -> String
    /// The Fill row's help line, which names the options by the labels shown.
    var fillHelp: String { get }
    /// Lines a Fill caption may take (and reserves): two for the Core labels.
    var fillLabelLines: Int { get }
}

public extension MeterStyleTileChrome {
    func fillLabel(_ fill: GaugeFill) -> String { fill.label }

    var fillLabelLines: Int { 2 }

    var fillHelp: String {
        "Only when low keeps meters neutral until usage runs low. "
            + "Glass and Ghost add a bright\u{00A0}end\u{00A0}cap."
    }
}

/// Global meter controls. Every choice is deliberately rendered by `MeterGauge`
/// itself, so the controls stay truthful as the renderer evolves.
///
/// U12 (iOS parity): moved here from the Mac app so the phone's Appearance section draws the
/// same swatches. The host's chrome comes in through `MeterStyleTileChrome`; the Mac's chrome
/// still wraps the rows in its `SettingsTile`, exactly as before.
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
public struct MeterStyleTile<Chrome: MeterStyleTileChrome>: View {
    public let meterStyle: MeterStyle
    public let chrome: Chrome
    public let onChange: (MeterStyle) -> Void

    public init(
        meterStyle: MeterStyle,
        chrome: Chrome,
        onChange: @escaping (MeterStyle) -> Void
    ) {
        self.meterStyle = meterStyle
        self.chrome = chrome
        self.onChange = onChange
    }

    @Environment(\.colorScheme) private var colorScheme

    /// L12B: one fixed column rhythm across all three rows. On the Mac, five 76pt columns on
    /// 8pt gaps need 412pt; at the 720pt minimum window the detail column is 504pt, so the tile
    /// is 464pt wide and its 438pt interior clears that without wrapping or shrinking.
    private let columnCount = 5
    private var metrics: MeterStyleTileMetrics { chrome.metrics }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            formatRow
            shapeRow
            fillRow
        }
        .modifier(chrome.container())
    }

    private var formatRow: some View {
        swatchRow("Format", selection: meterStyle.format) {
            ForEach(GaugeFormat.allCases) { format in
                formatSwatch(format)
            }
        }
    }

    private var shapeRow: some View {
        swatchRow("Shape", selection: meterStyle.shape) {
            ForEach(GaugeShape.allCases) { shape in
                shapeSwatch(shape)
            }
        } footer: {
            if meterStyle.format == .full {
                chrome.help("Tube is available only with Micro format.")
            }
        }
    }

    private var fillRow: some View {
        swatchRow("Fill", selection: meterStyle.fill) {
            ForEach(GaugeFill.allCases) { fill in
                fillSwatch(fill)
            }
        } footer: {
            // PB7: the Fill row shipped five renderer names and no help line while every
            // other row in the window had one. R2C12 cuts it to the two options whose names
            // can't carry themselves — the swatch labels say the rest — and settles the
            // spelling: "coloured" and "Color" appeared in one pair of sentences, in an app
            // that is American everywhere else.
            chrome.help(chrome.fillHelp)
        }
    }

    /// L12B: a fixed five-column grid, not an adaptive one, so Format (2), Shape (4), and
    /// Fill (5) all sit on the same column centers.
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(metrics.swatchWidth), spacing: metrics.swatchSpacing, alignment: .leading),
            count: columnCount
        )
    }

    private func swatchRow<Selection: Hashable, Swatches: View, Footer: View>(
        _ caption: String,
        selection: Selection,
        @ViewBuilder swatches: () -> Swatches,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.captionSpacing) {
            chrome.caption(caption)

            LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.swatchSpacing) {
                swatches()
            }
            // SM1: the row's selection plate slides between its swatches.
            .modifier(chrome.selectionGroup(value: AnyHashable(selection)))

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
                            fragmentCaption(shrinksToFit: false)
                            fragmentGauge(format: .full)
                        }
                    case .micro:
                        // CA-I8 fix pass: the chip's width is fixed and the caption takes what
                        // is left, shrinking rather than overflowing. "Weekly" (21.8pt) + 4 + a
                        // 38pt Segmented row is 63.8, wider than the 60pt fragment on the Mac
                        // and than the phone's narrower one.
                        HStack(spacing: 4) {
                            fragmentCaption(shrinksToFit: true)
                            fragmentGauge(format: .micro)
                        }
                    }
                }
                .frame(width: metrics.fragmentWidth, alignment: .leading)
            }
            .modifier(chrome.selection(isSelected: isSelected))
        }
        .buttonStyle(chrome.swatchStyle)
        .help(format.label)
        .accessibilityLabel("\(format.label) format")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder private func fragmentCaption(shrinksToFit: Bool) -> some View {
        let caption = Text("Weekly")
            .font(.system(size: 6))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        if shrinksToFit {
            caption.minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
        } else {
            caption.fixedSize()
        }
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
                    fittingWidth: Double(metrics.fragmentWidth),
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
            .modifier(chrome.selection(isSelected: isSelected))
        }
        .buttonStyle(chrome.swatchStyle)
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
            swatchBody(label: chrome.fillLabel(fill), labelLines: chrome.fillLabelLines) {
                // The healthy/low pair is the subject of this row, so the two fractions and
                // severities stay literal (PA5) — only the shape they are drawn on follows
                // the live selection. Tube is vertical, so the pair sits side by side there;
                // stacked it would need 36pt inside a 26pt well.
                referencePair {
                    referenceGauge(fill: fill, fraction: 0.62, severity: .healthy)
                    referenceGauge(fill: fill, fraction: 0.38, severity: .low)
                }
            }
            .modifier(chrome.selection(isSelected: isSelected))
        }
        .buttonStyle(chrome.swatchStyle)
        // The full Core name, whatever caption the host prints (CA-S11).
        .help(fill.label)
        .accessibilityLabel("\(fill.label) fill")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    /// The one swatch shell every row shares: a well over a swatch label (on the Mac a 26pt
    /// well over an 11pt label, 5pt apart, inside 5pt of padding).
    private func swatchBody<Content: View>(
        label: String,
        labelLines: Int = 1,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: metrics.labelSpacing) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: metrics.wellHeight)
                .background(
                    ProviderStyle.recessedWell(dark: colorScheme == .dark),
                    in: RoundedRectangle(cornerRadius: metrics.wellCornerRadius, style: .continuous)
                )

            Text(label)
                .font(metrics.labelFont)
                .multilineTextAlignment(.center)
                .lineLimit(labelLines, reservesSpace: labelLines > 1)
                .minimumScaleFactor(metrics.labelMinimumScaleFactor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: labelLines > 1 ? metrics.twoLineLabelHeight : nil, alignment: .top)
        }
        .padding(metrics.swatchPadding)
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
