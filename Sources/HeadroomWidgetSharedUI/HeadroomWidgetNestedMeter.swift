#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// 19 Nested Meter (widget-styles plan; default style). The primary window is a thick bar; the
/// other windows hang beneath it as thin rails, the way the 5-hour window draws from the week.
/// Cursor's sibling pools are not nested, so they draw as equal bars (R2).
struct HeadroomWidgetNestedMeter<Mark: View>: View {
    let context: HeadroomWidgetStyleContext
    let mark: (String, CGFloat) -> Mark

    var body: some View {
        switch context.family {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    // MARK: Small

    /// KTD10: small sheds the model and Spark rails before anything overlaps.
    private var small: some View {
        let rungCount = context.recipe.providers.map(\.secondaryLadder.count).max() ?? 1
        return ViewThatFits(in: .vertical) {
            ForEach(0..<rungCount, id: \.self) { rung in
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(context.recipe.providers) { provider in
                            smallBlock(provider, rails: provider.secondaryLadder[min(rung, provider.secondaryLadder.count - 1)])
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func smallBlock(_ provider: WidgetStyleProviderRecipe, rails: [WidgetWindowSummary]) -> some View {
        let live = context.isLive(provider)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: CGFloat(WidgetMetrics.markGap)) {
                mark(provider.id, CGFloat(context.slot))
                    .frame(width: CGFloat(context.slot), height: CGFloat(context.slot))
                HeadroomWidgetName(provider.summary.displayName, size: 13)
                Spacer(minLength: 4)
                if !provider.isWaiting {
                    HeadroomWidgetNumeral(provider.primary, size: context.hero(), providerIsLive: live, now: context.now)
                        .widgetCapHeightCentered(size: context.hero(), weight: .semibold, mono: true)
                }
            }
            if provider.isWaiting {
                HeadroomWidgetWaitingLine(size: 10.5).padding(.top, 6)
            } else {
                HeadroomWidgetNestedBars(provider: provider, rails: rails, colorMode: context.colorMode, family: .small, live: live)
                    .padding(.top, 6)
                HeadroomWidgetDetailLine(window: provider.secondary.first ?? provider.primary, showsValue: !provider.secondary.isEmpty,
                                         live: live, now: context.now, size: 10.5)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.summary.displayName)
        .accessibilityValue(HeadroomWidgetWindowText.providerAccessibility(provider, windows: provider.windows, now: context.now))
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(context.recipe.providers) { provider in
                mediumColumn(provider)
            }
        }
    }

    private func mediumColumn(_ provider: WidgetStyleProviderRecipe) -> some View {
        let live = context.isLive(provider)
        return VStack(alignment: .leading, spacing: 0) {
            HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name,
                                      showsPlan: context.recipe.providers.count == 1, mark: mark)
            if provider.isWaiting {
                HeadroomWidgetWaitingLine(size: 11).padding(.top, 14)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    HeadroomWidgetNumeral(provider.primary, size: context.hero(), providerIsLive: live, now: context.now)
                    if let primary = provider.primary {
                        HeadroomWidgetCaption(WidgetStyleCopy.leftCaption(for: primary, in: provider), size: 11)
                    }
                }
                .padding(.top, 14)
                HeadroomWidgetNestedBars(provider: provider, rails: provider.secondary, colorMode: context.colorMode, family: .medium, live: live)
                    .padding(.top, 9)
                VStack(alignment: .leading, spacing: 2) {
                    if provider.secondary.isEmpty {
                        if let countdown = HeadroomWidgetWindowText.countdown(provider.primary, now: context.now) {
                            HeadroomWidgetCaption("Resets in \(countdown)", size: 10.5, ink: .countdown)
                        }
                    } else {
                        ForEach(provider.secondary) { window in
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                HeadroomWidgetFittingCaption([Self.labelAndCountdown(window, now: context.now), window.widgetDisplayLabel],
                                                             size: 10.5, ink: .countdown)
                                Spacer(minLength: 4)
                                HeadroomWidgetNumeral(window, size: context.rowNumeral, providerIsLive: live, now: context.now)
                            }
                        }
                    }
                }
                .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.summary.displayName)
        .accessibilityValue(HeadroomWidgetWindowText.providerAccessibility(provider, windows: provider.windows, now: context.now))
    }

    // MARK: Large

    private var large: some View {
        let providers = context.recipe.providers
        let rungCount = providers.map(\.secondaryLadder.count).max() ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .vertical) {
                ForEach(0..<rungCount, id: \.self) { rung in
                    largeBlocks(rung: rung)
                }
            }
            .frame(maxHeight: .infinity)
            HeadroomWidgetStyleTail(context: context, mark: mark)
                .padding(.top, 8)
        }
    }

    private func largeBlocks(rung: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 4)
            ForEach(Array(context.recipe.providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 { Spacer(minLength: 16) }
                largeBlock(provider, rows: provider.secondaryLadder[min(rung, provider.secondaryLadder.count - 1)])
            }
            Spacer(minLength: 4)
        }
    }

    private func largeBlock(_ provider: WidgetStyleProviderRecipe, rows: [WidgetWindowSummary]) -> some View {
        let live = context.isLive(provider)
        let sibling = provider.hasSiblingPools
        return VStack(alignment: .leading, spacing: 0) {
            HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name, showsPlan: true, mark: mark)
            if provider.isWaiting {
                HeadroomWidgetWaitingLine(size: 11).padding(.top, 10)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HeadroomWidgetNumeral(provider.primary, size: context.hero(), providerIsLive: live, now: context.now)
                    if let primary = provider.primary {
                        HeadroomWidgetCaption(WidgetStyleCopy.leftCaption(for: primary, in: provider), size: 12)
                    }
                    Spacer(minLength: 4)
                    if let countdown = HeadroomWidgetWindowText.countdown(provider.primary, now: context.now) {
                        HeadroomWidgetCaption(countdown, size: context.scale.countdown, ink: .countdown, mono: true)
                            .fixedSize()
                    }
                }
                .padding(.top, 12)
                HeadroomWidgetStyleBar(provider.primary, colorMode: context.colorMode, providerIsLive: live,
                                       height: CGFloat(WidgetStyleMetrics.nestedParentBar(.large)))
                    .padding(.top, 11)
                ForEach(rows) { window in
                    HStack(alignment: .center, spacing: 8) {
                        HeadroomWidgetCaption(window.widgetDisplayLabel, size: 11.5, ink: .label)
                            .frame(width: sibling ? 92 : 56, alignment: .leading)
                        HeadroomWidgetStyleBar(window, colorMode: context.colorMode, providerIsLive: live,
                                               height: CGFloat(sibling ? WidgetStyleMetrics.nestedParentBar(.large) - 2 : WidgetStyleMetrics.nestedRail(.large)),
                                               showsWell: sibling)
                        HeadroomWidgetNumeral(window, size: context.rowNumeral, providerIsLive: live, now: context.now)
                            .frame(minWidth: 36, alignment: .trailing)
                        if !sibling {
                            HeadroomWidgetCaption(HeadroomWidgetWindowText.countdown(window, now: context.now) ?? "",
                                                  size: 10.5, ink: .countdown, mono: true)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.summary.displayName)
        .accessibilityValue(HeadroomWidgetWindowText.providerAccessibility(provider, windows: [provider.primary].compactMap { $0 } + rows, now: context.now))
    }

    static func labelAndCountdown(_ window: WidgetWindowSummary, now: Date) -> String {
        guard let countdown = HeadroomWidgetWindowText.countdown(window, now: now) else { return window.widgetDisplayLabel }
        return "\(window.widgetDisplayLabel) · \(countdown)"
    }
}

/// The primary bar with the provider's other windows as rails beneath it — or, for sibling
/// pools, as equal bars.
struct HeadroomWidgetNestedBars: View {
    let provider: WidgetStyleProviderRecipe
    /// The rails to hang — `provider.secondary`, or a shed rung of it (KTD10).
    let rails: [WidgetWindowSummary]
    let colorMode: WidgetColorMode
    let family: WidgetFamily
    let live: Bool

    var body: some View {
        let parent = WidgetStyleMetrics.nestedParentBar(family)
        let sibling = provider.hasSiblingPools
        VStack(alignment: .leading, spacing: CGFloat(WidgetStyleMetrics.nestedRailGap(family) + (sibling ? 2 : 0))) {
            HeadroomWidgetStyleBar(provider.primary, colorMode: colorMode, providerIsLive: live, height: CGFloat(parent))
            ForEach(rails) { window in
                HeadroomWidgetStyleBar(window, colorMode: colorMode, providerIsLive: live,
                                       height: CGFloat(sibling ? parent : WidgetStyleMetrics.nestedRail(family)),
                                       showsWell: sibling)
            }
        }
    }
}

/// "5-hour 72% · 3h 15m" — a window's name, its value in numeral ink, and its countdown; or,
/// with `showsValue` off, "Weekly · 4d 6h".
struct HeadroomWidgetDetailLine: View {
    let window: WidgetWindowSummary?
    let showsValue: Bool
    let live: Bool
    let now: Date
    let size: Double

    @Environment(\.colorScheme) private var scheme
    @HeadroomWidgetTypeUnit private var typeUnit

    var body: some View {
        if let window {
            let countdown = HeadroomWidgetWindowText.countdown(window, now: now)
            let value = Text(HeadroomWidgetWindowText.percent(window))
                .foregroundStyle(valueInk(window))
                .fontWeight(.semibold)
            // WCF7: the countdown drops whole before the label truncates.
            ViewThatFits(in: .horizontal) {
                if let countdown {
                    line(window, value: value, tail: " · \(countdown)").fixedSize()
                }
                line(window, value: value, tail: "")
            }
            .headroomWidgetProbe()
        }
    }

    private func line(_ window: WidgetWindowSummary, value: Text, tail: String) -> some View {
        Group {
            if showsValue {
                Text("\(window.widgetDisplayLabel) \(value)\(tail)")
            } else {
                Text("\(window.widgetDisplayLabel)\(tail)")
            }
        }
        .font(HeadroomWidgetType.font(size: size * typeUnit, weight: .medium, mono: true))
        .foregroundStyle(HeadroomWidgetStyle.countdownInk(scheme: scheme))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func valueInk(_ window: WidgetWindowSummary) -> Color {
        guard live, window.freshness.isLive else { return HeadroomWidgetStyle.secondaryText(scheme: scheme) }
        return window.severity == .critical ? HeadroomWidgetStyle.criticalText(scheme: scheme) : HeadroomWidgetStyle.labelInk(scheme: scheme)
    }
}

/// A provider name on a row it shares with a numeral (WCD1 neutral ink, −0.15 kern).
struct HeadroomWidgetName: View {
    let text: String
    let size: Double
    @Environment(\.colorScheme) private var scheme
    @HeadroomWidgetTypeUnit private var typeUnit

    init(_ text: String, size: Double) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size * typeUnit, weight: .semibold))
            .kerning(-0.15)
            .foregroundStyle(HeadroomWidgetStyle.accountTitle(scheme: scheme))
            .lineLimit(1)
            .truncationMode(.tail)
            .widgetCapHeightCentered(size: size * typeUnit, weight: .semibold)
            .headroomWidgetProbe()
    }
}
