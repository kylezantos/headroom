#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// KTD6 (2026-10-04 Lock Screen plan): platform art the shared views cannot name. iOS injects
/// its template asset marks and `AccessoryWidgetBackground`; the Mac harness injects
/// `ProviderLogoView` silhouettes and a stand-in backdrop, because WidgetKit's accessory
/// views and the iOS asset catalog do not exist there.
public struct HeadroomWidgetLockScreenArt {
    public let mark: (String, CGFloat) -> AnyView
    public let accessoryBackground: () -> AnyView

    public init(mark: @escaping (String, CGFloat) -> AnyView, accessoryBackground: @escaping () -> AnyView) {
        self.mark = mark
        self.accessoryBackground = accessoryBackground
    }
}

/// KTD3/KTD6: the one public entry. It lays out the recipe and makes no policy decisions;
/// the eight circle and rectangle designs and the inline readout live in sibling files.
public struct HeadroomWidgetLockScreenBody<InlineIcon: View>: View {
    private let recipe: LockScreenWidgetRecipe
    private let art: HeadroomWidgetLockScreenArt
    private let inlineIcon: (LockScreenInlineImage) -> InlineIcon

    public init(recipe: LockScreenWidgetRecipe, art: HeadroomWidgetLockScreenArt,
                @ViewBuilder inlineIcon: @escaping (LockScreenInlineImage) -> InlineIcon) {
        self.recipe = recipe
        self.art = art
        self.inlineIcon = inlineIcon
    }

    public var body: some View {
        switch recipe.family {
        case .inline:
            HeadroomWidgetLockScreenInline(recipe: recipe, icon: inlineIcon)
        case .circle:
            HeadroomWidgetLockScreenCircle(recipe: recipe, art: art)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recipe.accessibilityText)
        case .rectangle:
            HeadroomWidgetLockScreenRectangle(recipe: recipe, art: art)
        }
    }
}

/// KTD7: every body draws marks through this one path so ink follows the R7/R8 state.
struct HeadroomWidgetLockScreenSlotMark: View {
    let slot: LockScreenProviderSlot
    let size: Double
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        HeadroomWidgetLockScreenBrandMark(providerID: slot.providerID, size: size,
                                          ink: HeadroomWidgetLockScreenInk.mark(slot.primary.state),
                                          mark: art.mark)
    }
}

/// R8/R9: provider and detail labels in secondary ink, scaled up to the R15 cap.
struct HeadroomWidgetLockScreenLabel: View {
    let text: String
    var size: Double = 11.5
    var weight: Font.Weight = .medium
    var ink = HeadroomWidgetLockScreenInk.label
    @HeadroomWidgetTypeUnit private var typeUnit

    var body: some View {
        Text(text)
            .font(.system(size: size * typeUnit, weight: weight))
            .foregroundStyle(ink)
            .lineLimit(1)
            .truncationMode(.tail)
            // R16: labels can carry readings ("Weekly 42% · 4d"); names redact with them.
            .privacySensitive()
            .headroomWidgetProbe()
    }
}

/// R15: the first candidate that fits wins; the last one truncates instead of overflowing.
struct HeadroomWidgetLockScreenFittingLabel: View {
    let candidates: [String]
    var size: Double = 11.5
    var weight: Font.Weight = .medium
    var ink = HeadroomWidgetLockScreenInk.label

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, text in
                HeadroomWidgetLockScreenLabel(text: text, size: size, weight: weight, ink: ink)
                    .fixedSize(horizontal: index < candidates.count - 1, vertical: false)
            }
        }
    }
}

/// KTD6: digit-ink vessel on the numeral's baseline, the home hero's optical rule.
struct HeadroomWidgetLockScreenHero: View {
    let recipe: LockScreenWindowRecipe
    let numeralSize: Double

    static func indent(numeralSize: Double) -> Double {
        HeadroomWidgetLockScreenVessel.geometry(numeralSize: numeralSize).width + gap(numeralSize)
    }

    static func gap(_ numeralSize: Double) -> Double {
        (numeralSize * LockScreenWidgetTokens.vesselNumeralGapRatio).rounded()
    }

    var body: some View {
        let descent = HeadroomWidgetFontMetrics.digitInk(size: numeralSize, weight: .semibold).descent
        HStack(alignment: .firstTextBaseline, spacing: Self.gap(numeralSize)) {
            HeadroomWidgetLockScreenVessel(recipe, geometry: HeadroomWidgetLockScreenVessel.geometry(numeralSize: numeralSize))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - descent }
            HeadroomWidgetLockScreenNumeral(recipe, size: numeralSize)
        }
        .fixedSize()
        .headroomWidgetProbe()
    }
}
