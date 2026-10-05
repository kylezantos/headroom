import SwiftUI
import WidgetKit

/// KTD1/KTD6 (2026-10-04 Lock Screen plan): the host maps WidgetKit's accessory sizes to
/// Core, builds the recipe and injects the iOS-only art. Every drawing decision lives in
/// `LockScreenWidgetRecipe` and the shared `HeadroomWidgetLockScreenBody`.
struct HeadroomLockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeadroomLockScreenWidgetEntry

    var body: some View {
        Group {
            if let lockScreenFamily {
                content(for: lockScreenFamily)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "headroom://usage"))
        .privacySensitive()
        .dynamicTypeSize(...labelDynamicTypeCap)
    }

    private var labelDynamicTypeCap: DynamicTypeSize {
        switch LockScreenWidgetTokens.labelDynamicTypeCap {
        case .xLarge: .xLarge
        }
    }

    /// KTD2: unknown WidgetKit sizes stay empty, never route into a home family.
    private var lockScreenFamily: LockScreenWidgetFamily? {
        switch family {
        case .accessoryCircular: .circle
        case .accessoryRectangular: .rectangle
        case .accessoryInline: .inline
        default: nil
        }
    }

    @ViewBuilder
    private func content(for family: LockScreenWidgetFamily) -> some View {
        if entry.isPlaceholder {
            placeholder(for: family)
        } else {
            HeadroomWidgetLockScreenBody(
                recipe: LockScreenWidgetRecipe(style: entry.style, family: family,
                                               providerChoice: entry.providerChoice,
                                               state: entry.state, now: entry.date,
                                               freshness: entry.freshnessTreatment),
                art: Self.art
            ) { image in
                // KTD9: inline renders only text and one image, so the icon stays a bare Image.
                switch image {
                case .warning: Image(systemName: "exclamationmark.circle")
                case .vessel(let level):
                    Image(LockScreenInlineVesselArt.assetName(level: level)).renderingMode(.template)
                }
            }
        }
    }

    /// KTD10/R16: the neutral placeholder carries no provider, number or filled shape.
    @ViewBuilder
    private func placeholder(for family: LockScreenWidgetFamily) -> some View {
        switch family {
        case .inline:
            Text("Headroom · —")
        case .circle:
            ZStack {
                AccessoryWidgetBackground()
                Text("—").font(.system(size: LockScreenWidgetTokens.liquidNumeral, weight: .semibold))
            }
        case .rectangle:
            Text("Headroom")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// KTD7: the existing brand assets as template silhouettes; `AccessoryWidgetBackground`
    /// is the system's own backdrop for circles and the Liquid Strip.
    private static let art = HeadroomWidgetLockScreenArt(
        mark: { id, slot in
            let dimensions = HeadroomBrandMark.markSize(for: id, slot: Double(slot))
            let image = HeadroomWidgetStyle.assetName(for: id).map { Image($0) }
                ?? Image(systemName: HeadroomWidgetStyle.symbol(for: id))
            return AnyView(image.resizable().renderingMode(.template).scaledToFit()
                .frame(width: dimensions.width, height: dimensions.height)
                .frame(width: slot, height: slot))
        },
        accessoryBackground: { AnyView(AccessoryWidgetBackground()) }
    )
}
