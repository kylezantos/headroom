import SwiftUI
import WidgetKit

struct HeadroomWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeadroomWidgetEntry

    var body: some View {
        Group {
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
        .containerBackground(for: .widget) {
            HeadroomWidgetContainerBackground()
        }
    }
}
