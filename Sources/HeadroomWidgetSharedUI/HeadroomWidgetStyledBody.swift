#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

// The widget-style dispatcher (2026-10-02 widget-styles plan, U4). Every caller — both widget
// hosts, Settings' gallery and preview strip, and the render harness — draws a style through
// these two views: the content (padded by the caller's margins) and the full-bleed layer
// beneath it (KTD9). Non-host callers take both at once through `HeadroomWidgetStyledTile`. The brand mark is injected because the Mac app has no brand-icon asset
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
    private let freshness: WidgetFreshnessTreatment
    private let mark: (String, CGFloat) -> Mark

    /// `freshness`: U13's KTD15 treatment for this entry. Hosts pass the widget treatment;
    /// other callers get the past-reset rule at `now` and never dim.
    public init(
        style: WidgetLayoutStyle,
        family: WidgetFamily,
        envelope: WidgetSnapshotEnvelope,
        colorMode: WidgetColorMode,
        now: Date,
        footerPrefix: String,
        freshness: WidgetFreshnessTreatment? = nil,
        @ViewBuilder mark: @escaping (String, CGFloat) -> Mark
    ) {
        self.style = style
        self.family = family
        self.envelope = envelope
        self.colorMode = colorMode
        self.now = now
        self.footerPrefix = footerPrefix
        self.freshness = freshness ?? WidgetFreshnessTreatment(now: now)
        self.mark = mark
    }

    public var body: some View {
        let context = HeadroomWidgetStyleContext(
            recipe: WidgetStyleRecipe(style: style, family: family, envelope: envelope, freshness: freshness),
            envelope: envelope,
            colorMode: colorMode,
            now: now,
            footerPrefix: footerPrefix
        )
        // U13: the freshness notes and the dimmed sentence wrap every style the same way.
        HeadroomWidgetFreshnessFrame(recipe: context.recipe) { notes in
            let context = context.placing(notes)
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
    init(style: WidgetLayoutStyle, family: WidgetFamily, envelope: WidgetSnapshotEnvelope, colorMode: WidgetColorMode, now: Date, footerPrefix: String,
         freshness: WidgetFreshnessTreatment? = nil) {
        self.init(style: style, family: family, envelope: envelope, colorMode: colorMode, now: now, footerPrefix: footerPrefix,
                  freshness: freshness) { id, size in
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

    /// `freshness`: the same treatment the body draws with, so a past-reset or dimmed primary
    /// loses or desaturates its wash exactly as its numeral does (U13).
    public init(style: WidgetLayoutStyle, family: WidgetFamily, envelope: WidgetSnapshotEnvelope, colorMode: WidgetColorMode,
                freshness: WidgetFreshnessTreatment = .none) {
        recipe = style == .liquidLevel ? WidgetStyleRecipe(style: style, family: family, envelope: envelope, freshness: freshness) : nil
        self.colorMode = colorMode
    }

    public var body: some View {
        if let recipe, !recipe.washSegments.isEmpty {
            HeadroomWidgetLiquidWash(segments: recipe.washSegments, colorMode: colorMode, showsDivider: recipe.showsWashDivider)
        }
    }
}

/// The pair every non-host caller draws — Settings' preview strip and gallery, and the render
/// harness: the style's full-bleed layer (KTD9) under the body padded by the tile's content
/// margin. The caller still owns the container fill (`.background`), frame and clip. The widget
/// hosts don't use this: their wash goes in `containerBackground` and WidgetKit owns the margin.
public struct HeadroomWidgetStyledTile<Mark: View>: View {
    private let style: WidgetLayoutStyle
    private let family: WidgetFamily
    private let envelope: WidgetSnapshotEnvelope
    private let colorMode: WidgetColorMode
    private let now: Date
    private let footerPrefix: String
    private let contentMargin: CGFloat
    private let freshness: WidgetFreshnessTreatment
    private let mark: (String, CGFloat) -> Mark

    public init(
        style: WidgetLayoutStyle,
        family: WidgetFamily,
        envelope: WidgetSnapshotEnvelope,
        colorMode: WidgetColorMode,
        now: Date,
        footerPrefix: String,
        contentMargin: CGFloat,
        freshness: WidgetFreshnessTreatment? = nil,
        @ViewBuilder mark: @escaping (String, CGFloat) -> Mark
    ) {
        self.style = style
        self.family = family
        self.envelope = envelope
        self.colorMode = colorMode
        self.now = now
        self.footerPrefix = footerPrefix
        self.contentMargin = contentMargin
        self.freshness = freshness ?? WidgetFreshnessTreatment(now: now)
        self.mark = mark
    }

    public var body: some View {
        ZStack {
            HeadroomWidgetStyledBackground(style: style, family: family, envelope: envelope, colorMode: colorMode, freshness: freshness)
            HeadroomWidgetStyledBody(
                style: style, family: family, envelope: envelope, colorMode: colorMode,
                now: now, footerPrefix: footerPrefix, freshness: freshness, mark: mark
            )
            .padding(contentMargin)
        }
    }
}

public extension HeadroomWidgetStyledTile where Mark == HeadroomWidgetProviderIcon {
    init(style: WidgetLayoutStyle, family: WidgetFamily, envelope: WidgetSnapshotEnvelope, colorMode: WidgetColorMode, now: Date, footerPrefix: String, contentMargin: CGFloat,
         freshness: WidgetFreshnessTreatment? = nil) {
        self.init(style: style, family: family, envelope: envelope, colorMode: colorMode, now: now, footerPrefix: footerPrefix, contentMargin: contentMargin,
                  freshness: freshness) { id, size in
            HeadroomWidgetProviderIcon(providerID: id, size: size)
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
    /// U13: the "Reset at <time>" notes large prints in its tail, above the footer; the
    /// freshness frame picks the rung that fits (`HeadroomWidgetFreshnessFrame`).
    var pastResetNotes: [WidgetPastResetNote] = []

    var family: WidgetFamily { recipe.family }

    func placing(_ notes: [WidgetPastResetNote]) -> HeadroomWidgetStyleContext {
        var copy = self
        copy.pastResetNotes = notes
        return copy
    }
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
        if !context.pastResetNotes.isEmpty {
            HeadroomWidgetPastResetNotes(notes: context.pastResetNotes, family: context.family)
                .padding(.bottom, 6)
        }
        if context.recipe.showsSpend {
            HeadroomWidgetAPISpendStrip(
                summaries: envelope.apiSpendProviders,
                now: context.now,
                scale: context.scale,
                footerText: HeadroomWidgetCopy.footerText(prefix: context.footerPrefix, capturedAt: envelope.generatedAt, now: context.now),
                footerShortText: Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: context.now),
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
    let provider: WidgetStyleProviderRecipe
    let size: Double
    var body: some View {
        HStack(spacing: 5) {
            if let pill = provider.waitingPill {
                // KTD15: the caption's small mark has one 3×6 ghost; the line keeps its type size.
                HalftoneVesselView(state: pill, width: 8, height: 13, columns: 3, rows: 6)
            }
            HeadroomWidgetCaption(WidgetStyleCopy.waiting, size: size, ink: .secondary)
        }
        .headroomWidgetProbe()
    }
}
