import Foundation
import HeadroomCore
import WidgetKit

struct HeadroomWidgetEntry: TimelineEntry {
    let date: Date
    let state: HeadroomWidgetState
    /// R7: the style and color mode this widget instance chose in Edit Widget.
    var style: WidgetLayoutStyle = .default
    var colorMode: WidgetColorMode = .default
}

enum HeadroomWidgetState: Equatable {
    case setupNeeded
    case incompatibleSchema
    case disabled
    case pending
    case content(WidgetSnapshotEnvelope)

    static func from(_ read: WidgetSnapshotCacheRead) -> HeadroomWidgetState {
        switch read {
        case .unavailable, .corrupt:
            .setupNeeded
        case .incompatibleSchema:
            .incompatibleSchema
        case .empty:
            .pending
        case .snapshot(let envelope):
            envelope.status == .disabled ? .disabled : .content(envelope)
        }
    }
}
