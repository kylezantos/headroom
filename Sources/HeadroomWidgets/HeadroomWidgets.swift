import SwiftUI
import WidgetKit

@main
struct HeadroomWidgets: WidgetBundle {
    var body: some Widget {
        HeadroomUsageWidget()
    }
}

struct HeadroomUsageWidget: Widget {
    private let kind = "HeadroomUsageWidget"

    var body: some WidgetConfiguration {
        // KTD1: same kind string as the shipped StaticConfiguration, so placed widgets keep
        // their identity and take the intent's defaults (Nested Meter, Always colored).
        AppIntentConfiguration(
            kind: kind,
            intent: HeadroomWidgetConfigurationIntent.self,
            provider: HeadroomTimelineProvider()
        ) { entry in
            HeadroomWidgetView(entry: entry)
        }
        .configurationDisplayName("Headroom")
        .description("AI subscription usage headroom at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // Content draws its own edge-to-edge background to dodge the Liquid Glass sheen on
        // the containerBackground layer; the system margins are re-applied in the view.
        .contentMarginsDisabled()
    }
}
