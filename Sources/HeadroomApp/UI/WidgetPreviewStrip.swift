import SwiftUI
import HeadroomCore
#if SWIFT_PACKAGE
import HeadroomWidgetSharedUI
#endif

/// L9P: the specimen at the top of Settings › Widgets & iPhone. Like the Appearance
/// specimen it is not a mock — it renders the *real* `HeadroomSmallWidgetView` and
/// `HeadroomMediumWidgetView` bodies (moved into `HeadroomWidgetSharedUI` for exactly
/// this) at WidgetKit's macOS tile sizes, over the widgets' own container gradient. The
/// three switches below it stop being abstract: you can see what "share data with
/// widgets" produces before you decide.
///
/// Inert the same three ways as `AppearanceSpecimen`: no hit testing, one collapsed
/// accessibility element, and frozen fixture data (`DemoScreenshotData.settingsPreview…`)
/// rather than the live store — Settings is not a live-data surface.
struct WidgetPreviewStrip: View {
    /// Dims the tiles when widget export is off, which is what the widgets themselves do
    /// (they fall back to the "Widgets Paused" status card once the snapshot stops).
    let widgetsEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// WidgetKit's macOS tile sizes. Anything else would make the preview a drawing of a
    /// widget rather than a widget.
    private static let smallSize = CGSize(width: 170, height: 170)
    private static let mediumSize = CGSize(width: 364, height: 170)
    private static let tileGap: CGFloat = 12
    private static let captionHeight: CGFloat = 15

    private static var intrinsicWidth: CGFloat {
        smallSize.width + tileGap + mediumSize.width
    }

    var body: some View {
        // The two tiles at true size are 546pt wide — more than the settings detail column
        // gives at any supported window width — so the strip shrinks uniformly rather than
        // clipping a tile or restacking. `ViewThatFits` picks the largest step that fits,
        // so on a wide window the tiles are pixel-for-pixel the real thing.
        ViewThatFits(in: .horizontal) {
            strip(scale: 1)
            strip(scale: 0.92)
            strip(scale: 0.84)
            strip(scale: 0.76)
            strip(scale: 0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // R2C9: r20 around r20 widget tiles at 9/10pt of padding. A fixed r7 well held tiles
        // three times its own roundness.
        .settingsPreviewWell(dark: colorScheme == .dark, verticalPadding: 10, cornerRadius: 20)
        .opacity(widgetsEnabled ? 1 : 0.55)
        // R2M7/S2A: the dim is opacity only, so it keeps its 200ms under Reduce Motion rather
        // than snapping — `reduceMotion ? nil :` killed both kinds indiscriminately.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: widgetsEnabled
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the small and medium macOS widgets")
    }

    private func strip(scale: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Self.tileGap) {
            tile(label: "Small", size: Self.smallSize) {
                HeadroomSmallWidgetView(
                    envelope: DemoScreenshotData.settingsPreviewEnvelope,
                    now: DemoScreenshotData.settingsPreviewNow,
                    mark: { providerID, size in brandMark(providerID, size) }
                )
            }
            tile(label: "Medium", size: Self.mediumSize) {
                HeadroomMediumWidgetView(
                    envelope: DemoScreenshotData.settingsPreviewEnvelope,
                    now: DemoScreenshotData.settingsPreviewNow,
                    mark: { providerID, size in brandMark(providerID, size) }
                )
            }
        }
        .frame(width: Self.intrinsicWidth, alignment: .leading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(
            width: Self.intrinsicWidth * scale,
            height: (Self.smallSize.height + Self.captionHeight) * scale,
            alignment: .topLeading
        )
    }

    /// The app has no `BrandIcons.xcassets` — its marks are the bundled SVGs the popover
    /// draws — so the shared widget bodies get the app's own renderer injected. Same
    /// artwork, same measured mark rule (`HeadroomBrandMark`), different loader.
    private func brandMark(_ providerID: String, _ size: CGFloat) -> some View {
        ProviderLogoView(providerID: ProviderID(providerID), size: size)
    }

    private func tile<Content: View>(
        label: String,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
                // WidgetKit's default macOS content margins; the widget bodies deliberately
                // add only a small residual on top of them (KTD1).
                .padding(16)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // A tile on the desktop is lifted, not outlined; the shadow is what keeps
                // it legible against the well in light appearance.
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 4, y: 1)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    /// The widgets' own three-stop falloff. Redrawn here rather than shared because the
    /// two widget extensions each keep their own `HeadroomWidgetContainerBackground` copy;
    /// the colors come from the one Core token set, so the surfaces cannot drift.
    private var tileBackground: some View {
        let dark = colorScheme == .dark
        return LinearGradient(
            colors: [
                Color(HeadroomWidgetColorValues.containerBackgroundTop(dark: dark)),
                Color(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: dark)),
                Color(HeadroomWidgetColorValues.containerBackgroundBottom(dark: dark)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
