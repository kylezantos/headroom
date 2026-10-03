import SwiftUI
import HeadroomCore
#if SWIFT_PACKAGE
import HeadroomWidgetSharedUI
#endif

/// R16/KTD13 (2026-10-02 widget-styles plan): the four widget styles as thumbnails, built the
/// way the Appearance pane's theme and meter swatches are — a `LazyVGrid` of plain buttons in
/// `selectionChrome`, with the container read to VoiceOver as one picker.
///
/// Preview only: the selection switches the specimen above it and nothing else. Each widget's
/// style is chosen on the widget itself, in Edit Widget, and the copy under the grid says so.
struct WidgetStyleGalleryPicker: View {
    @Binding var selection: WidgetLayoutStyle

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
            // Load-bearing grid, not an `HStack`: fixed-size thumbnails in an HStack crashed
            // AppKit's layout pass when a sibling tile resized (see ThemeThumbnailPicker).
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                ForEach(WidgetLayoutStyle.allCases, id: \.self) { style in
                    thumbnail(style)
                }
            }
            .settingsSelectionGroup(value: selection)
            .accessibilityRepresentation {
                Picker("Widget style preview", selection: $selection) {
                    ForEach(WidgetLayoutStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }
            SettingsHelpText(text: "Choose a style for each widget with Edit Widget.")
        }
    }

    private static let columns = [
        GridItem(.adaptive(minimum: artSize + 10, maximum: artSize + 36), spacing: SettingsMetrics.withinGroup)
    ]

    /// A small widget at 0.5 scale: big enough to read the style, small enough for four in a row.
    static let artSize: CGFloat = 85
    /// The preview strip's small tile, so the thumbnail is that widget at half size.
    private static let tileSize = WidgetPreviewStrip.smallSize

    private func thumbnail(_ style: WidgetLayoutStyle) -> some View {
        let isSelected = selection == style
        return Button {
            selection = style
        } label: {
            VStack(spacing: 5) {
                art(style)
                Text(style.displayName)
                    .font(SettingsType.swatchLabel)
                    .lineLimit(1)
            }
            .padding(5)
            .selectionChrome(isSelected: isSelected)
        }
        .buttonStyle(SettingsSwatchButtonStyle())
        .accessibilityLabel("\(style.displayName) widget style")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    /// The real small widget body over the widgets' own container gradient, scaled down.
    private func art(_ style: WidgetLayoutStyle) -> some View {
        let envelope = DemoScreenshotData.settingsPreviewEnvelope
        let scale = Self.artSize / Self.tileSize.width
        return HeadroomWidgetStyledTile(
            style: style, family: .small, envelope: envelope, colorMode: .default,
            now: DemoScreenshotData.settingsPreviewNow, footerPrefix: HeadroomWidgetCopy.macFooterPrefix,
            contentMargin: WidgetPreviewStrip.tileContentMargin
        ) { providerID, size in
            ProviderLogoView(providerID: ProviderID(providerID), size: size)
        }
        .background { WidgetPreviewStrip.tileBackground(dark: colorScheme == .dark) }
        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        .clipShape(RoundedRectangle(cornerRadius: WidgetPreviewStrip.tileRadius, style: .continuous))
        .scaleEffect(scale)
        .frame(width: Self.artSize, height: Self.artSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
