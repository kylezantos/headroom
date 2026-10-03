import Foundation
import WidgetKit

struct HeadroomIOSWidgetEntry: TimelineEntry {
    let date: Date
    let state: IOSWidgetSnapshotState
    /// R7: the style and color mode this widget instance chose in Edit Widget.
    var style: WidgetLayoutStyle = .default
    var colorMode: WidgetColorMode = .default
}
