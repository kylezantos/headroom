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
            content
                .padding(contentMargins)
        }
        .containerBackground(for: .widget) {
            HeadroomWidgetContainerBackground()
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .setupNeeded:
            WidgetStatusView(title: "Widget Data Unavailable", message: "Open Headroom to refresh the widget cache.")
        case .disabled:
            WidgetStatusView(title: "Widgets Paused", message: "Enable widget data in Headroom Settings.")
        case .pending:
            WidgetStatusView(title: "Waiting for Data", message: "Open Headroom to fetch usage.")
        case .content(let envelope):
            switch family {
            case .systemSmall:
                HeadroomSmallWidgetView(envelope: envelope)
            case .systemMedium:
                HeadroomMediumWidgetView(envelope: envelope, now: entry.date)
            default:
                HeadroomLargeWidgetView(envelope: envelope, now: entry.date)
            }
        }
    }
}
