import SwiftUI

/// R22 / S3 (approved): a read-only gallery of the four widget styles, drawn by the widgets'
/// own shared bodies (`HeadroomWidgetStyledTile`), plus how to choose one and which providers
/// the Mac sends to widgets. Nothing here changes a widget: each widget picks its style in
/// Edit Widget.
struct WidgetsGallerySection: View {
    let manifestRows: PhoneSettingsManifestRows

    var body: some View {
        Section {
            LazyVGrid(columns: Self.columns, alignment: .center, spacing: 16) {
                ForEach(WidgetLayoutStyle.allCases, id: \.self) { style in
                    WidgetStyleThumbnail(style: style)
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("headroom.settings.widgetGallery")
        } header: {
            Text("Widget styles")
        } footer: {
            // KTD11 / V25: whatever Percentages says, widgets show what's left.
            Text(PhoneSettingsCopy.widgetsFooter + " " + PhoneDisplayCopy.widgetsAlwaysLeft)
        }

        // Rule 7: the Mac's widget provider selection is a manifest field.
        switch manifestRows {
        case .hidden:
            EmptyView()
        case .updateMac:
            Section("Shown in widgets") {
                Text(PhoneSettingsCopy.updateMac)
                    .foregroundStyle(.secondary)
            }
        case .available(let widgetProviders, _):
            Section {
                LabeledContent("Providers", value: ListFormatter.localizedString(byJoining: widgetProviders))
                    .accessibilityIdentifier("headroom.settings.widgetProviders")
            } header: {
                Text("Shown in widgets")
            } footer: {
                Text(PhoneSettingsCopy.widgetProvidersFooter)
            }
        }
    }

    /// Two small widgets per row, as on the Home Screen.
    private static let columns = [
        GridItem(.flexible(), spacing: 14, alignment: .top),
        GridItem(.flexible(), spacing: 14, alignment: .top),
    ]
}

/// One style as a small widget, scaled down from the iPhone's real small-widget size so its
/// type and shedding are the widget's own (WCF7), over the widgets' container gradient.
private struct WidgetStyleThumbnail: View {
    let style: WidgetLayoutStyle

    @Environment(\.colorScheme) private var scheme

    /// The 6.1″ iPhone small widget and its system content margin.
    private static let tileSize: CGFloat = 170
    private static let contentMargin: CGFloat = 16
    /// The approved S3 mock's 150pt thumbnails, two to a row.
    private static let artSize: CGFloat = 150

    var body: some View {
        VStack(spacing: 7) {
            art
            Text(style.displayName)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.displayName) widget style")
    }

    private var art: some View {
        // WCW3: the gallery draws a fixture, so it takes the demo tiles' "Updated" footer;
        // "From Mac" would be a claim about data the Mac never sent.
        HeadroomWidgetStyledTile(
            style: style, family: .small, envelope: DemoScreenshotData.settingsPreviewEnvelope,
            colorMode: .default, now: DemoScreenshotData.settingsPreviewNow,
            footerPrefix: HeadroomWidgetCopy.macFooterPrefix, contentMargin: Self.contentMargin
        ) { providerID, size in
            ProviderLogoView(providerID: providerID, size: size / 1.35)
        }
        .background { containerBackground }
        .frame(width: Self.tileSize, height: Self.tileSize)
        // The widget's own corner, which iOS draws for a small widget.
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .scaleEffect(Self.artSize / Self.tileSize)
        .frame(width: Self.artSize, height: Self.artSize)
        .allowsHitTesting(false)
    }

    /// The iPhone widget's container gradient (`HeadroomWidgetContainerBackground`), from the
    /// same Core values.
    private var containerBackground: some View {
        let dark = scheme == .dark
        return LinearGradient(
            colors: [
                color(HeadroomWidgetColorValues.containerBackgroundTop(dark: dark)),
                color(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: dark)),
                color(HeadroomWidgetColorValues.containerBackgroundBottom(dark: dark)),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private func color(_ rgb: HeadroomRGBColor) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
