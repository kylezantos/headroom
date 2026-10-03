#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// Liquid Level (widget-styles plan). The widget is the vessel: each provider's column fills
/// from the bottom to its primary window's level. The wash itself is the full-bleed layer
/// (`HeadroomWidgetStyledBackground`, KTD9); this view is the type over it.
struct HeadroomWidgetLiquidLevel<Mark: View>: View {
    let context: HeadroomWidgetStyleContext
    let mark: (String, CGFloat) -> Mark

    /// Keeps each column's text clear of the centre divider; the columns themselves split the
    /// content box at the same centre line the wash splits the tile.
    private let columnGutter: CGFloat = 14

    var body: some View {
        switch context.family {
        case .small: small
        case .medium: columns(large: false)
        case .large: largeBody
        }
    }

    // MARK: Small (R6: one provider)

    @ViewBuilder private var small: some View {
        if let provider = context.recipe.providers.first {
            VStack(alignment: .leading, spacing: 0) {
                HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, scale: context.scale, showsPlan: false, mark: mark)
                Spacer(minLength: 4)
                heroBlock(provider, size: context.hero(1), extra: nil)
            }
            .headroomWidgetProviderAccessibility(provider, now: context.now)
        }
    }

    // MARK: Medium and large

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            columns(large: true)
            HeadroomWidgetStyleTail(context: context, mark: mark)
                .padding(.top, 8)
        }
    }

    private func columns(large: Bool) -> some View {
        let providers = context.recipe.providers
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                column(provider, large: large)
                    .padding(.leading, index > 0 ? columnGutter : 0)
                    .padding(.trailing, index < providers.count - 1 ? columnGutter : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func column(_ provider: WidgetStyleProviderRecipe, large: Bool) -> some View {
        let single = context.recipe.providers.count == 1
        let live = context.isLive(provider)
        return VStack(alignment: .leading, spacing: 0) {
            HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, scale: context.scale, showsPlan: single,
                                      showsStaleReason: large, mark: mark)
            if large {
                heroBlock(provider, size: context.hero(), extra: HeadroomWidgetWindowText.countdown(provider.primary, now: context.now))
                    .padding(.top, 10)
                Spacer(minLength: 4)
                ViewThatFits(in: .vertical) {
                    ForEach(0..<provider.secondaryLadder.count, id: \.self) { rung in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(provider.secondary(atRung: rung)) { window in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    HeadroomWidgetCaption(window.widgetDisplayLabel, size: context.scale.label, ink: .label)
                                    Spacer(minLength: 4)
                                    HeadroomWidgetNumeral(window, size: context.rowNumeral, providerIsLive: live, now: context.now)
                                }
                                .frame(height: 26)
                            }
                        }
                    }
                }
            } else {
                Spacer(minLength: 4)
                heroBlock(provider, size: context.hero(), extra: nil, mediumDetail: true)
            }
        }
        .headroomWidgetProviderAccessibility(provider, now: context.now)
    }

    // MARK: Pieces

    @ViewBuilder
    private func heroBlock(_ provider: WidgetStyleProviderRecipe, size: Double, extra: String?, mediumDetail: Bool = false) -> some View {
        if provider.isWaiting {
            HeadroomWidgetWaitingLine(size: context.scale.countdown)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HeadroomWidgetNumeral(provider.primary, size: size, providerIsLive: context.isLive(provider), now: context.now)
                VStack(alignment: .leading, spacing: 2) {
                    HeadroomWidgetFittingCaption(captions(provider, mediumDetail: mediumDetail), size: context.scale.countdown, ink: .label)
                    if let extra {
                        HeadroomWidgetCaption(extra, size: context.scale.countdown, ink: .countdown, mono: true)
                    }
                }
            }
        }
    }

    /// Longest first; the detail after "·" drops whole before the caption truncates (WCF7).
    private func captions(_ provider: WidgetStyleProviderRecipe, mediumDetail: Bool) -> [String] {
        guard let primary = provider.primary else { return [""] }
        let base = WidgetStyleCopy.leftCaption(for: primary, in: provider)
        let isSmall = context.family == .small
        guard mediumDetail || isSmall else { return [base] }
        if let other = provider.companion {
            return ["\(base) · \(other.widgetDisplayLabel) \(HeadroomWidgetWindowText.percent(other))", base]
        }
        if let countdown = HeadroomWidgetWindowText.countdown(primary, now: context.now) {
            return ["\(base) · \(countdown)", base]
        }
        return [base]
    }
}
