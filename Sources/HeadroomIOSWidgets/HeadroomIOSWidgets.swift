import SwiftUI
import WidgetKit

@main
struct HeadroomIOSWidgets: WidgetBundle {
    var body: some Widget {
        HeadroomIOSUsageWidget()
        HeadroomLockScreenWidget()
    }
}

struct HeadroomIOSUsageWidget: Widget {
    var body: some WidgetConfiguration {
        // KTD1: same kind string as the shipped StaticConfiguration, so placed widgets keep
        // their identity and take the intent's defaults (Nested Meter, Always colored).
        AppIntentConfiguration(
            kind: HeadroomIOSWidgetConfiguration.kind,
            intent: HeadroomWidgetConfigurationIntent.self,
            provider: HeadroomIOSTimelineProvider()
        ) { entry in
            HeadroomIOSWidgetView(entry: entry)
        }
        .configurationDisplayName("Headroom")
        .description("AI subscription usage headroom at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .disfavoredLocations([.iPhoneWidgetsOnMac], for: [.systemSmall, .systemMedium, .systemLarge])
        // Content draws its own edge-to-edge background to dodge the Liquid Glass sheen on
        // the containerBackground layer; the system margins are re-applied in the view.
        .contentMarginsDisabled()
    }
}
