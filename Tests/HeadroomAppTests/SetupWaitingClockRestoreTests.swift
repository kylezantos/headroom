import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// R2M12: the app boundary half of the durable waiting clock. `AccountStorage` owns the
/// stamp; this is the seam that puts it back into the observable session state on relaunch,
/// and it must stay fail-safe — a start Headroom never wrote is no clock, not "Waiting 3s".
@MainActor
@Suite(.sharedAppState)
struct SetupWaitingClockRestoreTests {
    private func makeMarker() throws -> (SetupCompletionMarker, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-restore-clock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            SetupCompletionMarker(
                pendingPath: directory.appendingPathComponent("pending").path,
                completedPath: directory.appendingPathComponent("complete").path
            ),
            directory
        )
    }

    private func freshKey() -> AccountKey {
        AccountKey(providerID: .codex, accountID: AccountID("restore-\(UUID().uuidString)"))
    }

    @Test func aRestoredHandoffKeepsCountingFromItsPersistedStart() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = freshKey()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: startedAt)

        SetupSessions.restoreWaitingStart(
            for: key,
            marker: marker,
            now: startedAt.addingTimeInterval(3_600)
        )

        #expect(SetupSessionActivity.shared.waitingSince(for: key) == startedAt)
        SetupSessionActivity.shared.endWaiting(for: key)
    }

    @Test func aHandoffWithNoPersistedStartSeedsNoClock() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = freshKey()

        // Nothing staged at all, then a "Stop waiting" tombstone over a staged handoff:
        // both leave the header on the card-derived line.
        SetupSessions.restoreWaitingStart(for: key, marker: marker)
        #expect(SetupSessionActivity.shared.waitingSince(for: key) == nil)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: startedAt)
        AccountStorage.clearSetupCompletionMarkers(marker)
        SetupSessions.restoreWaitingStart(
            for: key,
            marker: marker,
            now: startedAt.addingTimeInterval(60)
        )
        #expect(SetupSessionActivity.shared.waitingSince(for: key) == nil)
    }

    @Test func aStartInTheFutureIsRefusedRatherThanClockedBackwards() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = freshKey()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: startedAt)

        SetupSessions.restoreWaitingStart(
            for: key,
            marker: marker,
            now: startedAt.addingTimeInterval(-60)
        )

        #expect(SetupSessionActivity.shared.waitingSince(for: key) == nil)
    }
}
