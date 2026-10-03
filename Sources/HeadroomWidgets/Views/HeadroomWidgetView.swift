import HeadroomCore
#if SWIFT_PACKAGE
import HeadroomWidgetSharedUI
#endif
import SwiftUI
import WidgetKit

struct HeadroomWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: HeadroomWidgetEntry

    var body: some View {
        ZStack {
            // The OS 26 Liquid Glass presentation composites a translucent sheen over the
            // `containerBackground` layer (bright at the widget's top edge, fading by
            // mid-tile — measured ~+28 RGB at top on both platforms), which made the top
            // provider card sit on a lighter surround than the bottom one. Content is not
            // veiled, so the background is drawn here in the content layer instead —
            // `contentMarginsDisabled` lets it bleed to the container edges, and the
            // system's own margins are re-applied around the actual content below. The
            // `containerBackground` copy remains for accented rendering and contexts that
            // strip backgrounds (StandBy / lock screen), where the system look should win.
            if showsContainerBackground && renderingMode == .fullColor {
                HeadroomWidgetContainerBackground()
            }
            // KTD9 (widget-styles plan): a style's full-bleed layer — Liquid Level's wash —
            // sits under the padded content. It reads the rendering mode itself, so it also
            // draws (as a translucent primary wash) in accented and StandBy.
            if case .content(let envelope) = entry.state {
                HeadroomWidgetStyledBackground(style: entry.style, family: coreFamily, envelope: envelope, colorMode: entry.colorMode)
            }
            // WCF4: the system content margin on every family, vertical included. The large
            // family used to zero its vertical margins so its equal spacers could own all
            // the slack; the style bodies now distribute their own slack inside a fixed
            // margin, which is the same rule the iPhone host has always followed.
            content
                .padding(contentMargins)
        }
        .containerBackground(for: .widget) {
            HeadroomWidgetContainerBackground()
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// WCF1's family token. Spelled through the shared alias because `WidgetKit` exports a
    /// `WidgetFamily` of its own and this file imports both.
    private var coreFamily: HeadroomWidgetFamily {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .setupNeeded:
            statusCard(.macSetupNeeded)
        case .incompatibleSchema:
            statusCard(.macIncompatibleSchema)
        case .disabled:
            statusCard(.macDisabled)
        case .pending:
            statusCard(.macPending)
        case .content(let envelope):
            // R7: the style and color this widget chose in Edit Widget.
            HeadroomWidgetStyledBody(
                style: entry.style,
                family: coreFamily,
                envelope: envelope,
                colorMode: entry.colorMode,
                now: entry.date,
                footerPrefix: HeadroomWidgetCopy.macFooterPrefix
            )
        }
    }

    /// WCW4: the status block takes the family residual, not its own 12pt inset, so the
    /// status axis is the content axis.
    private func statusCard(_ state: WidgetStatusState) -> some View {
        HeadroomWidgetStatusCard(
            state: state,
            family: coreFamily,
            scale: WidgetTypeScale.scale(for: coreFamily)
        )
        .padding(WidgetMetrics.residualMargin)
    }
}
