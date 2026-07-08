import Foundation

/// Where the content the iPhone is showing actually came from. Surfaced in the
/// companion Settings diagnostics so a stale display is never silently blamed on
/// rendering when the real problem is which snapshot won resolution.
public enum IOSWidgetContentOrigin: String, Equatable, Sendable {
    case cache
    case sync
}

/// The resolved display state plus where its content came from. `from(...)` keeps
/// returning just the state for the widget entry; `resolve(...)` exposes the origin
/// for diagnostics.
public struct IOSWidgetResolution: Equatable, Sendable {
    public let state: IOSWidgetSnapshotState
    public let origin: IOSWidgetContentOrigin?

    public init(state: IOSWidgetSnapshotState, origin: IOSWidgetContentOrigin?) {
        self.state = state
        self.origin = origin
    }
}

public enum IOSWidgetSnapshotState: Equatable, Sendable {
    case setupNeeded
    case waitingForMac
    case disabled
    case corrupt
    case incompatibleSchema
    case content(WidgetSnapshotEnvelope)

    public static func from(
        cacheRead: WidgetSnapshotCacheRead,
        syncRead: iCloudSnapshotSyncRead? = nil
    ) -> IOSWidgetSnapshotState {
        resolve(cacheRead: cacheRead, syncRead: syncRead).state
    }

    /// Newest-valid-snapshot wins. When both the local cache and the iCloud read carry
    /// a snapshot, the one with the newer `generatedAt` is shown (ties go to iCloud, the
    /// published source of truth) so a stale local cache can never mask a fresher sync —
    /// or vice-versa. When only one side has a snapshot it is used, so a missing/corrupt
    /// iCloud read never hides usable cached content. Only when neither side has a
    /// snapshot do we surface the most actionable setup/wait state.
    public static func resolve(
        cacheRead: WidgetSnapshotCacheRead,
        syncRead: iCloudSnapshotSyncRead? = nil
    ) -> IOSWidgetResolution {
        let cacheSnapshot = cacheRead.envelope
        let syncSnapshot = syncRead?.envelope?.snapshot

        if let cacheSnapshot, let syncSnapshot {
            let syncWins = syncSnapshot.generatedAt >= cacheSnapshot.generatedAt
            let winner = syncWins ? syncSnapshot : cacheSnapshot
            return IOSWidgetResolution(state: contentState(for: winner), origin: syncWins ? .sync : .cache)
        }
        if let cacheSnapshot {
            return IOSWidgetResolution(state: contentState(for: cacheSnapshot), origin: .cache)
        }
        if let syncSnapshot {
            return IOSWidgetResolution(state: contentState(for: syncSnapshot), origin: .sync)
        }
        return IOSWidgetResolution(state: nonContentState(cacheRead: cacheRead, syncRead: syncRead), origin: nil)
    }

    private static func contentState(for envelope: WidgetSnapshotEnvelope) -> IOSWidgetSnapshotState {
        envelope.status == .disabled ? .disabled : .content(envelope)
    }

    private static func nonContentState(
        cacheRead: WidgetSnapshotCacheRead,
        syncRead: iCloudSnapshotSyncRead?
    ) -> IOSWidgetSnapshotState {
        switch cacheRead {
        case .unavailable:
            return .setupNeeded
        case .corrupt:
            return .corrupt
        case .empty, .snapshot:
            break
        }
        guard let syncRead else { return .waitingForMac }
        switch syncRead {
        case .unavailable:
            return .setupNeeded
        case .missing:
            return .waitingForMac
        case .corrupt:
            return .corrupt
        case .incompatibleSchema:
            return .incompatibleSchema
        case .snapshot:
            return .waitingForMac
        }
    }
}
