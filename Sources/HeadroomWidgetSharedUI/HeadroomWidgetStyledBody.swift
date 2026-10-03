#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

// The widget-style dispatcher (2026-10-02 widget-styles plan, U4). Every caller — both widget
// hosts, Settings' gallery and preview strip, and the render harness — draws a style through
// these two views: the content (padded by the caller's margins) and the full-bleed layer
// beneath it (KTD9). The brand mark is injected because the Mac app has no brand-icon asset
// catalog; the widget extensions use the `HeadroomWidgetProviderIcon` convenience inits.
//
// This file does not import WidgetKit, so `WidgetFamily` is Core's (WC-merge).

public struct HeadroomWidgetStyledBody<Mark: View>: View {
    private let style: WidgetLayoutStyle
    private let family: WidgetFamily
    private let envelope: WidgetSnapshotEnvelope
    private let colorMode: WidgetColorMode
    private let now: Date
    private let footerPrefix: String
    private let mark: (String, CGFloat) -> Mark

    public init(
        style: WidgetLayoutStyle,
        family: WidgetFamily,
        envelope: WidgetSnapshotEnvelope,
        colorMode: WidgetColorMode,
        now: Date,
        footerPrefix: String,
        @ViewBuilder mark: @escaping (String, CGFloat) -> Mark
    ) {
        self.style = style
        self.family = family
        self.envelope = envelope
        self.colorMode = colorMode
        self.now = now
        self.footerPrefix = footerPrefix
        self.mark = mark
    }

    public var body: some View {
        let context = HeadroomWidgetStyleContext(
            recipe: WidgetStyleRecipe(style: style, family: family, envelope: envelope),
            envelope: envelope,
            colorMode: colorMode,
            now: now,
            footerPrefix: footerPrefix
        )
        Group {
            switch style {
            case .nestedMeter: HeadroomWidgetNestedMeter(context: context, mark: mark)
            case .vesselHero: HeadroomWidgetVesselHero(context: context, mark: mark)
            case .tightestFirst: HeadroomWidgetTightestFirst(context: context, mark: mark)
            case .liquidLevel: HeadroomWidgetLiquidLevel(context: context, mark: mark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // WCF4: the caller supplies the system content margin; this is the 2pt residual.
        .padding(WidgetMetrics.residualMargin)
    }
}

public extension HeadroomWidgetStyledBody where Mark == HeadroomWidgetProviderIcon {
    init(style: WidgetLayoutStyle, family: WidgetFamily, envelope: WidgetSnapshotEnvelope, colorMode: WidgetColorMode, now: Date, footerPrefix: String) {
        self.init(style: style, family: family, envelope: envelope, colorMode: colorMode, now: now, footerPrefix: footerPrefix) { id, size in
            HeadroomWidgetProviderIcon(providerID: id, size: size)
        }
    }
}

/// KTD9: the layer a style paints behind the margins. Only Liquid Level has one; every caller
/// draws it under the padded content, inside the tile's clip.
public struct HeadroomWidgetStyledBackground: View {
    /// Only Liquid Level has a layer, so the other styles skip building a recipe at all.
    private let recipe: WidgetStyleRecipe?
    private let colorMode: WidgetColorMode

    public init(style: WidgetLayoutStyle, family: WidgetFamily, envelope: WidgetSnapshotEnvelope, colorMode: WidgetColorMode) {
        recipe = style == .liquidLevel ? WidgetStyleRecipe(style: style, family: family, envelope: envelope) : nil
        self.colorMode = colorMode
    }

    public var body: some View {
        if let recipe, !recipe.washSegments.isEmpty {
            HeadroomWidgetLiquidWash(segments: recipe.washSegments, colorMode: colorMode, showsDivider: recipe.showsWashDivider)
        }
    }
}

/// What every style view reads.
struct HeadroomWidgetStyleContext {
    let recipe: WidgetStyleRecipe
    let envelope: WidgetSnapshotEnvelope
    let colorMode: WidgetColorMode
    let now: Date
    let footerPrefix: String

    var family: WidgetFamily { recipe.family }
    var scale: WidgetTypeScale { WidgetTypeScale.scale(for: family) }
    var slot: Double { WidgetMetrics.markSlot(for: family) }

    func hero(_ providerCount: Int? = nil) -> Double {
        WidgetStyleType.heroNumeral(style: recipe.style, family: family, providerCount: providerCount ?? recipe.providers.count)
    }

    var rowNumeral: Double { WidgetStyleType.rowNumeral(style: recipe.style, family: family) }

    func isLive(_ provider: WidgetStyleProviderRecipe) -> Bool {
        provider.summary.freshness == .live
    }
}

/// R14: large's tail — the spend strip (which carries the footer stamp in its run) or the
/// footer alone.
struct HeadroomWidgetStyleTail<Mark: View>: View {
    let context: HeadroomWidgetStyleContext
    let mark: (String, CGFloat) -> Mark

    var body: some View {
        let envelope = context.envelope
        if context.recipe.showsSpend {
            HeadroomWidgetAPISpendStrip(
                summaries: envelope.apiSpendProviders,
                now: context.now,
                family: .large,
                scale: context.scale,
                footerText: HeadroomWidgetCopy.footerText(prefix: context.footerPrefix, capturedAt: envelope.generatedAt, now: context.now),
                footerShortText: Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: context.now),
                showsRule: true,
                mark: { id, size in AnyView(mark(id, size)) }
            )
            .headroomWidgetProbe()
        } else if context.recipe.showsFooter,
                  HeadroomWidgetCopy.footerText(prefix: context.footerPrefix, capturedAt: envelope.generatedAt, now: context.now) != nil {
            HeadroomWidgetFooterStamp(text: context.footerPrefix, capturedAt: envelope.generatedAt, now: context.now, size: context.scale.footer)
                .headroomWidgetProbe()
        }
    }
}

/// R11: the line a provider shows before Headroom has read it.
struct HeadroomWidgetWaitingLine: View {
    let size: Double
    var body: some View {
        HeadroomWidgetCaption(WidgetStyleCopy.waiting, size: size, ink: .secondary)
    }
}
