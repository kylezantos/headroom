#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// Vessel Hero (widget-styles plan). The Headroom vessel beside each provider's primary
/// number — the menu-bar pill at hero size, exactly as tall as the digits (R4).
struct HeadroomWidgetVesselHero<Mark: View>: View {
    let context: HeadroomWidgetStyleContext
    let mark: (String, CGFloat) -> Mark

    var body: some View {
        switch context.family {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    // MARK: Small (R6: one provider)

    @ViewBuilder private var small: some View {
        if let provider = context.recipe.providers.first {
            VStack(alignment: .leading, spacing: 0) {
                HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, scale: context.scale, showsPlan: false, mark: mark)
                Spacer(minLength: 4)
                hero(provider, size: context.hero(1), extra: nil)
                Spacer(minLength: 4)
                secondLine(provider)
            }
            .headroomWidgetProviderAccessibility(provider, now: context.now)
        }
    }

    // MARK: Medium

    @ViewBuilder private var medium: some View {
        let providers = context.recipe.providers
        if providers.count == 1, let provider = providers.first {
            mediumSingle(provider)
        } else {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        HeadroomWidgetRule(.vertical).padding(.vertical, 4)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, scale: context.scale, showsPlan: true, mark: mark)
                        Spacer(minLength: 4)
                        hero(provider, size: context.hero(), extra: nil)
                        Spacer(minLength: 4)
                        secondLine(provider)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .headroomWidgetProviderAccessibility(provider, now: context.now)
                }
            }
        }
    }

    private func mediumSingle(_ provider: WidgetStyleProviderRecipe) -> some View {
        let live = context.isLive(provider)
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, scale: context.scale, showsPlan: true, mark: mark)
                Spacer(minLength: 4)
                hero(provider, size: context.hero(1), extra: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                ForEach(provider.secondary) { window in
                    HStack(alignment: .center, spacing: 8) {
                        HeadroomWidgetVessel(window, colorMode: context.colorMode, providerIsLive: live,
                                             geometry: WidgetVesselGeometry(width: WidgetStyleMetrics.mediumRowVesselWidth,
                                                                            height: WidgetStyleMetrics.mediumRowVesselHeight,
                                                                            stroke: WidgetStyleMetrics.rowVesselStroke))
                        HeadroomWidgetCaption(window.widgetDisplayLabel, size: context.scale.label, ink: .label)
                        Spacer(minLength: 4)
                        HeadroomWidgetNumeral(window, size: WidgetStyleType.vesselHeroMediumRowNumeral, providerIsLive: live, now: context.now)
                    }
                }
                if let countdown = HeadroomWidgetWindowText.countdown(provider.primary, now: context.now) {
                    HeadroomWidgetCaption(WidgetStyleCopy.resetsIn(countdown), size: context.scale.countdown, ink: .countdown, mono: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .headroomWidgetProviderAccessibility(provider, now: context.now)
    }

    // MARK: Large

    /// CA-W3: the hero columns take the tile's spare height and the rows sit directly above
    /// the tail, so the open space falls between the vessels and their rows rather than above
    /// the footer. The vertical divider runs the columns' full height, from the header down to
    /// the rows' rule (or to the tail when there are no rows).
    private var large: some View {
        let providers = context.recipe.providers
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { HeadroomWidgetRule(.vertical) }
                    VStack(alignment: .leading, spacing: 16) {
                        HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, scale: context.scale, showsPlan: true,
                                                  showsStaleReason: true, mark: mark)
                        hero(provider, size: context.hero(), extra: HeadroomWidgetWindowText.countdown(provider.primary, now: context.now))
                    }
                    // The hero-to-rows gap the rows' rule used to carry, kept as the minimum.
                    .padding(.bottom, 18)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // R15: the column speaks its hero only; each row below is its own element.
                    .headroomWidgetProviderAccessibility(provider, windows: [provider.primary].compactMap { $0 }, now: context.now)
                }
            }
            // The rows are offered the room first, so they keep their fullest rung (KTD10) and
            // the hero columns stretch over whatever is left.
            ViewThatFits(in: .vertical) {
                ForEach(0..<context.recipe.ladderRungCount, id: \.self) { rung in
                    largeRows(rung: rung)
                }
            }
            .layoutPriority(1)
            HeadroomWidgetStyleTail(context: context, mark: mark)
                .padding(.top, 8)
        }
    }

    @ViewBuilder private func largeRows(rung: Int) -> some View {
        let rows = context.recipe.providers.flatMap { provider in
            provider.secondary(atRung: rung).map {
                HeadroomWidgetProviderWindow(provider: provider, window: $0)
            }
        }
        if rows.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HeadroomWidgetRule().padding(.bottom, 4)
                // Keyed by provider and window: two providers each have a "fiveHour" window.
                ForEach(rows, id: \.rowID) { row in
                    let provider = row.provider, window = row.window
                    let live = context.isLive(provider)
                    HStack(alignment: .center, spacing: 9) {
                        mark(provider.id, CGFloat(WidgetStyleMetrics.rowMark))
                            .frame(width: CGFloat(WidgetStyleMetrics.rowMark), height: CGFloat(WidgetStyleMetrics.rowMark))
                        HeadroomWidgetCaption(window.widgetDisplayLabel, size: context.scale.label, ink: .label)
                            .fixedSize()
                        if let countdown = HeadroomWidgetWindowText.countdown(window, now: context.now) {
                            HeadroomWidgetCaption(countdown, size: context.scale.countdown, ink: .countdown, mono: true)
                        }
                        Spacer(minLength: 4)
                        HeadroomWidgetVessel(window, colorMode: context.colorMode, providerIsLive: live,
                                             geometry: WidgetVesselGeometry(width: WidgetStyleMetrics.rowVesselWidth,
                                                                            height: WidgetStyleMetrics.rowVesselHeight,
                                                                            stroke: WidgetStyleMetrics.rowVesselStroke))
                        HeadroomWidgetNumeral(window, size: context.rowNumeral, providerIsLive: live, now: context.now)
                            .frame(minWidth: 46, alignment: .trailing)
                    }
                    .frame(minHeight: 24, maxHeight: 36)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(provider.summary.displayName) \(window.widgetDisplayLabel)")
                    .accessibilityValue(HeadroomWidgetWindowText.accessibilityValue(window, providerIsLive: live, now: context.now))
                }
            }
        }
    }

    // MARK: Pieces

    /// R4: the vessel and the numeral, with the caption hanging under the numeral.
    @ViewBuilder
    private func hero(_ provider: WidgetStyleProviderRecipe, size: Double, extra: String?) -> some View {
        if provider.isWaiting {
            HeadroomWidgetWaitingLine(provider: provider, size: context.scale.countdown)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HeadroomWidgetVesselNumeral(provider.primary, colorMode: context.colorMode, providerIsLive: context.isLive(provider),
                                            numeralSize: size, now: context.now)
                VStack(alignment: .leading, spacing: 2) {
                    if let primary = provider.primary {
                        HeadroomWidgetCaption(WidgetStyleCopy.leftCaption(for: primary, in: provider), size: context.scale.countdown)
                    }
                    if let extra {
                        HeadroomWidgetCaption(extra, size: context.scale.countdown, ink: .countdown, mono: true)
                    }
                }
                .padding(.leading, HeadroomWidgetVesselNumeral.captionIndent(numeralSize: size))
            }
        }
    }

    /// The line under the hero: the 5-hour (or other) window, else the reset countdown.
    @ViewBuilder
    private func secondLine(_ provider: WidgetStyleProviderRecipe) -> some View {
        let live = context.isLive(provider)
        if let other = provider.companion {
            // WCF7: the countdown drops whole, then the label truncates; the value never gives.
            ViewThatFits(in: .horizontal) {
                if let countdown = HeadroomWidgetWindowText.countdown(other, now: context.now) {
                    secondLineRow(other, live: live, countdown: countdown, labelFixed: true)
                }
                secondLineRow(other, live: live, countdown: nil, labelFixed: false)
            }
        } else if let countdown = HeadroomWidgetWindowText.countdown(provider.primary, now: context.now) {
            HeadroomWidgetCaption(WidgetStyleCopy.resetsIn(countdown), size: context.scale.countdown, ink: .countdown, mono: true)
        }
    }
}

extension HeadroomWidgetVesselHero {
    func secondLineRow(_ window: WidgetWindowSummary, live: Bool, countdown: String?, labelFixed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            HeadroomWidgetCaption(window.widgetDisplayLabel, size: context.scale.countdown, ink: .label)
                .fixedSize(horizontal: labelFixed, vertical: false)
            HeadroomWidgetNumeral(window, size: context.rowNumeral, providerIsLive: live, now: context.now)
            Spacer(minLength: 6)
            if let countdown {
                HeadroomWidgetCaption(countdown, size: context.scale.countdown, ink: .countdown, mono: true)
                    .fixedSize()
            }
        }
    }
}

/// A provider's window, keyed so rows from two providers never share an identity.
struct HeadroomWidgetProviderWindow {
    let provider: WidgetStyleProviderRecipe
    let window: WidgetWindowSummary
    var rowID: String { "\(provider.id)|\(window.id)" }
}
