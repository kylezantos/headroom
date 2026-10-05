import Foundation
import HeadroomCore
import WidgetKit

struct HeadroomWidgetEntry: TimelineEntry {
    let date: Date
    let state: HeadroomWidgetState
    /// R7: the style and color mode this widget instance chose in Edit Widget.
    var style: WidgetLayoutStyle = .default
    var colorMode: WidgetColorMode = .default
    /// U13 (KTD15): the Mac's own export time as freshness inputs; nil for the gallery's demo.
    var freshness: CompanionFreshnessInputs?

    /// The past-reset and dimming rules at this entry's date (R10, R11).
    var freshnessTreatment: WidgetFreshnessTreatment {
        .widget(inputs: freshness, now: date, host: .mac)
    }
}

enum HeadroomWidgetState: Equatable {
    case setupNeeded
    case incompatibleSchema
    case disabled
    case pending
    case content(WidgetSnapshotEnvelope)

    /// U13: the Mac widget reads a local file with no cadence in it, so it dims on the
    /// 120-minute v3-only threshold against the Mac's own last export time, where generatedAt
    /// and first-seen are one clock (KTD15).
    var freshness: CompanionFreshnessInputs? {
        guard case .content(let envelope) = self else { return nil }
        return CompanionFreshnessInputs(
            generatedAt: envelope.generatedAt, firstSeen: envelope.generatedAt,
            largestEffectiveIntervalSeconds: nil, isV3Only: true)
    }

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
