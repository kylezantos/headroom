import SwiftUI
import HeadroomCore
#if SWIFT_PACKAGE
import HeadroomWidgetSharedUI
#endif

/// L9P: the specimen at the top of Settings › Widgets & iPhone. Like the Appearance
/// specimen it is not a mock — it renders the *real* small, medium, and large widget
/// bodies (moved into `HeadroomWidgetSharedUI` for exactly this) at WidgetKit's macOS
/// tile sizes, over the widgets' own container gradient. The
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
    nonisolated private static let smallSize = CGSize(width: 170, height: 170)
    nonisolated private static let mediumSize = CGSize(width: 364, height: 170)
    nonisolated private static let largeSize = CGSize(width: 364, height: 382)
    /// WP1: the desktop's own gutter — a medium tile is two smalls plus 24 — so the mosaic
    /// reads as widgets placed on a desktop, not as tiles in a strip.
    nonisolated private static let tileGap: CGFloat = 24
    /// WP1: the well's inset, the same on all four sides. The old 9/10pt inset with the
    /// captions sitting on the bottom edge left the tiles crowded against the top and sides
    /// while a leftover gutter opened on the right.
    nonisolated private static let wellPadding: CGFloat = 14
    /// Captions keep one rendered size however far the tiles scale; these are rendered points.
    nonisolated private static let captionFontSize: CGFloat = 10
    nonisolated private static let captionSpacing: CGFloat = 5
    nonisolated private static let captionLineHeight: CGFloat = 13

    /// Large beside a column of Medium over Small, at their true sizes.
    nonisolated private static let intrinsicSize = CGSize(
        width: largeSize.width + tileGap + mediumSize.width,
        height: largeSize.height
    )

    var body: some View {
        // WP1: one continuous scale that fills the detail column, in place of the old
        // five-step ladder. A step always settled short of the width, and the tiles were
        // leading-aligned, so the slack pooled as a gutter on the right. The scale is read
        // from the proposed width inside the layout pass itself, so the first frame is
        // already the right size (a width measured after layout drew one frame wrong).
        FitWidthLayout(height: Self.renderedHeight(forWidth:)) {
            GeometryReader { proxy in
                let scale = Self.scale(forWidth: proxy.size.width)
                mosaic(scale: scale)
                    .frame(
                        width: Self.intrinsicSize.width,
                        height: Self.intrinsicHeight(scale: scale),
                        alignment: .topLeading
                    )
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: Self.intrinsicSize.width * scale, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        // R2C9 → WP1: concentric with the tiles' r20 at the scale they render at, which at a
        // typical Settings width is close to the 0.7 used here.
        .settingsPreviewWell(
            dark: colorScheme == .dark,
            verticalPadding: Self.wellPadding,
            horizontalPadding: Self.wellPadding,
            cornerRadius: Self.tileRadius * 0.7 + Self.wellPadding
        )
        .opacity(widgetsEnabled ? 1 : 0.55)
        // R2M7/S2A: the dim is opacity only, so it keeps its 200ms under Reduce Motion rather
        // than snapping — `reduceMotion ? nil :` killed both kinds indiscriminately.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: widgetsEnabled
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the small, medium, and large macOS widgets")
    }

    nonisolated private static let tileRadius: CGFloat = 20

    /// Never above true size: on a wide window the tiles are pixel-for-pixel real.
    nonisolated private static func scale(forWidth width: CGFloat) -> CGFloat {
        min(1, max(0.1, width / intrinsicSize.width))
    }

    /// A caption block in the mosaic's own (unscaled) coordinates, so it renders at a fixed
    /// size after the scale.
    nonisolated private static func captionBlock(scale: CGFloat) -> CGFloat {
        (captionSpacing + captionLineHeight) / scale
    }

    /// The Large tile plus its caption; the right column is fitted to the same height.
    nonisolated private static func intrinsicHeight(scale: CGFloat) -> CGFloat {
        largeSize.height + captionBlock(scale: scale)
    }

    nonisolated private static func renderedHeight(forWidth width: CGFloat) -> CGFloat {
        let scale = scale(forWidth: width)
        return intrinsicHeight(scale: scale) * scale
    }

    /// The gap between Medium's caption and the Small tile, chosen so Small's bottom edge
    /// lands on Large's — a large tile is two rows tall on the desktop grid.
    nonisolated private static func rowGap(scale: CGFloat) -> CGFloat {
        max(0, largeSize.height - mediumSize.height - smallSize.height - captionBlock(scale: scale))
    }

    private func mosaic(scale: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Self.tileGap) {
            tile(label: "Large", size: Self.largeSize, scale: scale) {
                HeadroomLargeWidgetView(
                    envelope: DemoScreenshotData.settingsPreviewEnvelope,
                    now: DemoScreenshotData.settingsPreviewNow,
                    mark: { providerID, size in brandMark(providerID, size) }
                )
            }
            VStack(alignment: .leading, spacing: Self.rowGap(scale: scale)) {
                tile(label: "Medium", size: Self.mediumSize, scale: scale) {
                    HeadroomMediumWidgetView(
                        envelope: DemoScreenshotData.settingsPreviewEnvelope,
                        now: DemoScreenshotData.settingsPreviewNow,
                        mark: { providerID, size in brandMark(providerID, size) }
                    )
                }
                tile(label: "Small", size: Self.smallSize, scale: scale) {
                    HeadroomSmallWidgetView(
                        envelope: DemoScreenshotData.settingsPreviewEnvelope,
                        now: DemoScreenshotData.settingsPreviewNow,
                        mark: { providerID, size in brandMark(providerID, size) }
                    )
                }
            }
        }
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
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.captionSpacing / scale) {
            content()
                // WidgetKit's default macOS content margins; the widget bodies deliberately
                // add only a small residual on top of them (KTD1).
                .padding(16)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous))
                // A tile on the desktop is lifted, not outlined; the shadow is what keeps
                // it legible against the well in light appearance.
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 4, y: 1)
            Text(label)
                .font(.system(size: Self.captionFontSize / scale))
                // T8: secondary, not tertiary — the faintest ink on a tinted well was the
                // lowest-contrast text in the window.
                .foregroundStyle(.secondary)
                .frame(height: Self.captionLineHeight / scale, alignment: .topLeading)
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

/// WP1: takes the width it is offered and asks `height` for the matching height, so the
/// preview's height follows its scale within one layout pass.
private struct FitWidthLayout: Layout {
    let height: @Sendable (CGFloat) -> CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 546
        return CGSize(width: width, height: height(width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

private extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
