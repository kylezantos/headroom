import Foundation

/// U13 (iOS parity plan, KTD13): what the iPhone Home Screen widget shows, taken from the
/// shared phone source's resolved snapshot. The envelope is always `primaryProjection()` — main
/// accounts only, never a pass-through of the v3 key — and the freshness inputs ride along so
/// each timeline entry applies the KTD15 widget rule. Pure, so the host stays a thin adapter.
public struct CompanionWidgetLoad: Equatable, Sendable {
    public let state: IOSWidgetSnapshotState
    /// The resolver's freshness inputs; nil for every state without content.
    public let freshness: CompanionFreshnessInputs?

    public init(state: IOSWidgetSnapshotState, freshness: CompanionFreshnessInputs?) {
        self.state = state
        self.freshness = freshness
    }

    /// `isDemo`: the snapshot came from the bundled demo seam (KTD21), so the entry wears the
    /// DEMO capsule. Demo keeps its freshness inputs, so the dimmed and past-reset demo
    /// variants pose those states on the widget too (R30).
    public static func from(_ snapshot: CompanionResolvedSnapshot, isDemo: Bool) -> CompanionWidgetLoad {
        switch snapshot.state {
        case .content(let content):
            guard let envelope = snapshot.primaryProjection() else {
                return CompanionWidgetLoad(state: .waitingForMac, freshness: nil)
            }
            return CompanionWidgetLoad(state: isDemo ? .demo(envelope) : .content(envelope), freshness: content.freshness)
        case .paused:
            return CompanionWidgetLoad(state: .disabled, freshness: nil)
        case .accountScopeUnavailable:
            // Build 33's "iCloud Not Available" card: nothing scoped can be shown.
            return CompanionWidgetLoad(state: .setupNeeded, freshness: nil)
        case .waiting(.updatePhone):
            return CompanionWidgetLoad(state: .incompatibleSchema, freshness: nil)
        case .waiting:
            return CompanionWidgetLoad(state: .waitingForMac, freshness: nil)
        }
    }
}
