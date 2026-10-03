#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// 02 Vessel Hero (widget-styles plan). The Headroom vessel beside each provider's primary
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
                HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name, showsPlan: false, mark: mark)
                Spacer(minLength: 4)
                hero(provider, size: context.hero(1), extra: nil)
                Spacer(minLength: 4)
                secondLine(provider)
            }
            .providerAccessibility(provider, now: context.now)
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
                        HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name, showsPlan: true, mark: mark)
                        Spacer(minLength: 4)
                        hero(provider, size: context.hero(), extra: nil)
                        Spacer(minLength: 4)
                        secondLine(provider)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .providerAccessibility(provider, now: context.now)
                }
            }
        }
    }

    private func mediumSingle(_ provider: WidgetStyleProviderRecipe) -> some View {
        let live = context.isLive(provider)
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name, showsPlan: true, mark: mark)
                Spacer(minLength: 4)
                hero(provider, size: context.hero(1), extra: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                ForEach(provider.secondary) { window in
                    HStack(alignment: .center, spacing: 8) {
                        HeadroomWidgetVessel(window, colorMode: context.colorMode, providerIsLive: live,
                                             geometry: WidgetVesselGeometry(width: 10, height: 18, stroke: WidgetStyleMetrics.rowVesselStroke))
                        HeadroomWidgetCaption(window.widgetDisplayLabel, size: context.scale.label, ink: .label)
                        Spacer(minLength: 4)
                        HeadroomWidgetNumeral(window, size: 16, providerIsLive: live, now: context.now)
                    }
                }
                if let countdown = HeadroomWidgetWindowText.countdown(provider.primary, now: context.now) {
                    HeadroomWidgetCaption("Resets in \(countdown)", size: context.scale.countdown, ink: .countdown, mono: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .providerAccessibility(provider, now: context.now)
    }

    // MARK: Large

    private var large: some View {
        let providers = context.recipe.providers
        let rungCount = providers.map(\.secondaryLadder.count).max() ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { HeadroomWidgetRule(.vertical) }
                    VStack(alignment: .leading, spacing: 16) {
                        HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name, showsPlan: true, mark: mark)
                        hero(provider, size: context.hero(), extra: HeadroomWidgetWindowText.countdown(provider.primary, now: context.now))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .providerAccessibility(provider, now: context.now)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .vertical) {
                ForEach(0..<rungCount, id: \.self) { rung in
                    largeRows(rung: rung)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            HeadroomWidgetStyleTail(context: context, mark: mark)
                .padding(.top, 8)
        }
    }

    @ViewBuilder private func largeRows(rung: Int) -> some View {
        let rows = context.recipe.providers.flatMap { provider in
            provider.secondaryLadder[min(rung, provider.secondaryLadder.count - 1)].map {
                HeadroomWidgetProviderWindow(provider: provider, window: $0)
            }
        }
        if rows.isEmpty {
            Spacer(minLength: 0)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HeadroomWidgetRule().padding(.top, 18).padding(.bottom, 4)
                // Keyed by provider and window: two providers each have a "fiveHour" window.
                ForEach(rows, id: \.rowID) { row in
                    let provider = row.provider, window = row.window
                    let live = context.isLive(provider)
                    HStack(alignment: .center, spacing: 9) {
                        mark(provider.id, 15).frame(width: 15, height: 15)
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
            HeadroomWidgetWaitingLine(size: context.scale.countdown)
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
        if let other = provider.secondary.first(where: { $0.widgetRole == .fiveHour }) ?? provider.secondary.first {
            // WCF7: the countdown drops whole, then the label truncates; the value never gives.
            ViewThatFits(in: .horizontal) {
                if let countdown = HeadroomWidgetWindowText.countdown(other, now: context.now) {
                    secondLineRow(other, live: live, countdown: countdown, labelFixed: true)
                }
                secondLineRow(other, live: live, countdown: nil, labelFixed: false)
            }
        } else if let countdown = HeadroomWidgetWindowText.countdown(provider.primary, now: context.now) {
            HeadroomWidgetCaption("Resets in \(countdown)", size: context.scale.countdown, ink: .countdown, mono: true)
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

extension View {
    /// R15: one VoiceOver element per provider — its name, then its windows in visual order.
    func providerAccessibility(_ provider: WidgetStyleProviderRecipe, now: Date) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(provider.summary.displayName)
            .accessibilityValue(HeadroomWidgetWindowText.providerAccessibility(provider, windows: provider.windows, now: now))
    }
}

/// A provider's window, keyed so rows from two providers never share an identity.
struct HeadroomWidgetProviderWindow {
    let provider: WidgetStyleProviderRecipe
    let window: WidgetWindowSummary
    var rowID: String { "\(provider.id)|\(window.id)" }
}
