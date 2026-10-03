#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// Tightest First (widget-styles plan). Whichever window is lowest is what limits you, so
/// each provider shows its binding window big and named; large is a list from tightest to
/// roomiest that sheds from the loose end (R3, KTD10).
struct HeadroomWidgetTightestFirst<Mark: View>: View {
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

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeadroomWidgetCaption(WidgetStyleCopy.tightestSmallHeading, size: context.scale.header)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(context.recipe.providers) { provider in
                    let live = context.isLive(provider)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: CGFloat(WidgetMetrics.markGap)) {
                            mark(provider.id, CGFloat(context.slot)).frame(width: CGFloat(context.slot), height: CGFloat(context.slot))
                            HeadroomWidgetName(provider.summary.displayName, size: 13)
                            Spacer(minLength: 4)
                            if !provider.isWaiting {
                                HeadroomWidgetNumeral(provider.tightest, size: context.hero(), providerIsLive: live, now: context.now)
                                    .widgetCapHeightCentered(size: context.hero(), weight: .semibold, mono: true)
                            }
                        }
                        if provider.isWaiting {
                            HeadroomWidgetWaitingLine(size: 10.5)
                        } else {
                            HStack(alignment: .center, spacing: 7) {
                                HeadroomWidgetStyleBar(provider.tightest, colorMode: context.colorMode, providerIsLive: live,
                                                       height: CGFloat(WidgetStyleMetrics.tightestRowBar))
                                HeadroomWidgetCaption(provider.tightest?.widgetDisplayLabel ?? "", size: 10.5, ink: .countdown)
                                    .frame(maxWidth: 62, alignment: .trailing)
                                    .fixedSize()
                            }
                        }
                    }
                    .headroomWidgetProviderAccessibility(provider, now: context.now)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(Array(context.recipe.providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 { HeadroomWidgetRule(.vertical) }
                mediumColumn(provider)
            }
        }
    }

    private func mediumColumn(_ provider: WidgetStyleProviderRecipe) -> some View {
        let live = context.isLive(provider)
        return VStack(alignment: .leading, spacing: 0) {
            HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name, showsPlan: true, mark: mark)
            Spacer(minLength: 4)
            if provider.isWaiting {
                HeadroomWidgetWaitingLine(size: context.scale.countdown)
            } else if let tightest = provider.tightest {
                HeadroomWidgetNumeral(tightest, size: context.hero(), providerIsLive: live, now: context.now)
                HeadroomWidgetCaption(Self.captionLine(tightest, now: context.now), size: context.scale.countdown, ink: .label)
                    .padding(.top, 4)
                HeadroomWidgetStyleBar(tightest, colorMode: context.colorMode, providerIsLive: live, height: 6)
                    .padding(.top, 8)
                let rest = provider.windows.filter { $0 != tightest }
                if !rest.isEmpty {
                    HeadroomWidgetCaption(rest.map { "\($0.widgetDisplayLabel) \(HeadroomWidgetWindowText.percent($0))" }.joined(separator: " · "),
                                          size: context.scale.countdown, ink: .countdown)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .headroomWidgetProviderAccessibility(provider, now: context.now)
    }

    // MARK: Large

    private var large: some View {
        let ladder = context.recipe.rankedRowsLadder
        return VStack(alignment: .leading, spacing: 0) {
            HeadroomWidgetCaption(WidgetStyleCopy.tightestLargeHeading, size: context.scale.header)
            if let headline = context.recipe.rankedRows.first {
                headlineView(headline).padding(.top, 10)
                ViewThatFits(in: .vertical) {
                    ForEach(0..<ladder.count, id: \.self) { rung in
                        rows(Array(ladder[rung].dropFirst()))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ForEach(context.recipe.providers) { provider in
                    HeadroomWidgetIdentityRow(provider: provider, slot: context.slot, nameSize: context.scale.name, showsPlan: false, mark: mark)
                        .padding(.top, 10)
                    HeadroomWidgetWaitingLine(size: context.scale.countdown).padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            HeadroomWidgetStyleTail(context: context, mark: mark)
                .padding(.top, 6)
        }
    }

    private func headlineView(_ row: WidgetRankedRow) -> some View {
        let live = isLive(row)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                mark(row.providerID, CGFloat(context.slot)).frame(width: CGFloat(context.slot), height: CGFloat(context.slot))
                HeadroomWidgetCaption("\(row.providerName) · \(row.window.widgetDisplayLabel)", size: 14, ink: .label, weight: .semibold)
                Spacer(minLength: 4)
                HeadroomWidgetNumeral(row.window, size: context.hero(), providerIsLive: live, now: context.now)
                    .widgetCapHeightCentered(size: context.hero(), weight: .semibold, mono: true)
            }
            if let countdown = HeadroomWidgetWindowText.countdown(row.window, now: context.now) {
                HeadroomWidgetCaption(WidgetStyleCopy.resetsIn(countdown), size: context.scale.countdown, ink: .countdown, mono: true)
                    .padding(.top, 3)
            }
            HeadroomWidgetStyleBar(row.window, colorMode: context.colorMode, providerIsLive: live,
                                   height: CGFloat(WidgetStyleMetrics.tightestHeadlineBar))
                .padding(.top, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tightest limit: \(row.providerName) \(row.window.widgetDisplayLabel)")
        .accessibilityValue(HeadroomWidgetWindowText.accessibilityValue(row.window, providerIsLive: live, now: context.now))
    }

    @ViewBuilder
    private func rows(_ rows: [WidgetRankedRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !rows.isEmpty {
                HeadroomWidgetRule().padding(.top, 16).padding(.bottom, 2)
            }
            ForEach(rows) { row in
                let live = isLive(row)
                HStack(alignment: .center, spacing: 9) {
                    mark(row.providerID, 15).frame(width: 15, height: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        HeadroomWidgetCaption("\(row.providerName) · \(row.window.widgetDisplayLabel)", size: 12.5, ink: .label)
                        if let countdown = HeadroomWidgetWindowText.countdown(row.window, now: context.now) {
                            HeadroomWidgetCaption(countdown, size: 10.5, ink: .countdown, mono: true)
                        }
                    }
                    .frame(width: 118, alignment: .leading)
                    HeadroomWidgetStyleBar(row.window, colorMode: context.colorMode, providerIsLive: live,
                                           height: CGFloat(WidgetStyleMetrics.tightestRowBar))
                    HeadroomWidgetNumeral(row.window, size: context.rowNumeral, providerIsLive: live, now: context.now)
                        .frame(minWidth: 42, alignment: .trailing)
                }
                .frame(minHeight: 26, maxHeight: 46)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.providerName) \(row.window.widgetDisplayLabel)")
                .accessibilityValue(HeadroomWidgetWindowText.accessibilityValue(row.window, providerIsLive: live, now: context.now))
            }
        }
    }

    private func isLive(_ row: WidgetRankedRow) -> Bool {
        context.recipe.providers.first { $0.id == row.providerID }.map(context.isLive) ?? true
    }

    static func captionLine(_ window: WidgetWindowSummary, now: Date) -> String {
        guard let countdown = HeadroomWidgetWindowText.countdown(window, now: now) else { return "\(window.widgetDisplayLabel) left" }
        return "\(window.widgetDisplayLabel) left · \(countdown)"
    }
}
