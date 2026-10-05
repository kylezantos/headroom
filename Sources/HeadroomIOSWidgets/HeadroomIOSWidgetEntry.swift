import Foundation
import WidgetKit

struct HeadroomIOSWidgetEntry: TimelineEntry {
    let date: Date
    let state: IOSWidgetSnapshotState
    /// R7: the style and color mode this widget instance chose in Edit Widget.
    var style: WidgetLayoutStyle = .default
    var colorMode: WidgetColorMode = .default
    /// U13 (KTD15): the resolver's freshness inputs; nil for the gallery preview and status cards.
    var freshness: CompanionFreshnessInputs?
    /// WCW8: demo tiles wear the DEMO capsule, except in the host's `--demo` screenshot
    /// presentation (an App Group flag), where the capture must look like real use.
    var showsDemoBadge = true

    /// The past-reset and dimming rules at this entry's date, on the widget floor (R10, R11).
    var freshnessTreatment: WidgetFreshnessTreatment {
        .widget(inputs: freshness, now: date, host: .phone)
    }
}
