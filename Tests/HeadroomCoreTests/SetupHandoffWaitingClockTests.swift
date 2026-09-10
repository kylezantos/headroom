import Foundation
import Testing
@testable import HeadroomCore

/// R2M12: the popover header clocks an open Terminal handoff. Before this, the start lived
/// only in memory, so a handoff that outlived a relaunch had no trustworthy start and the
/// header fell back to the card's own line. These pin the durable half: the start is written
/// beside the marker's generation, read back against an injected `now`, cleared everywhere a
/// handoff ends, and never guessed.
@Suite struct SetupHandoffWaitingClockTests {
    private func makeMarker() throws -> (SetupCompletionMarker, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-waiting-clock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            SetupCompletionMarker(
                pendingPath: directory.appendingPathComponent("pending").path,
                completedPath: directory.appendingPathComponent("complete").path
            ),
            directory
        )
    }

    @Test func preparedHandoffPersistsItsStartForARelaunchToReadBack() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let generation = try AccountStorage.prepareSetupCompletionMarker(
            marker,
            mode: .deviceCode,
            purpose: .reset,
            startedAt: startedAt
        )

        let now = startedAt.addingTimeInterval(3_600)
        let restored = try #require(AccountStorage.setupHandoffStartedAt(marker: marker, now: now))
        #expect(restored == startedAt)
        #expect(now.timeIntervalSince(restored) == 3_600)
        // The start rides beside the generation, so the rest of the handoff protocol is
        // untouched by it.
        #expect(AccountStorage.setupHandoffGeneration(marker: marker) == generation)
        #expect(AccountStorage.setupHandoffMode(marker: marker) == .deviceCode)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .reset)
    }

    /// The wrapper replaces the opening pending marker with its own PID as soon as Terminal
    /// is up — which is exactly the state a relaunch finds. The clock has to survive that.
    @Test func startSurvivesTheWrapperReplacingThePendingMarkerWithItsPID() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let generation = try AccountStorage.prepareSetupCompletionMarker(
            marker,
            startedAt: startedAt
        )
        try Data("setup:standard:\(generation):\(getpid())\n".utf8).write(
            to: URL(fileURLWithPath: AccountStorage.generatedPendingPath(
                marker,
                generation: generation
            ))
        )

        let now = startedAt.addingTimeInterval(900)
        #expect(AccountStorage.setupHandoffIsActive(marker: marker, now: now))
        #expect(AccountStorage.setupHandoffStartedAt(marker: marker, now: now) == startedAt)
    }

    /// "Stop waiting" tombstones the generation; a tombstoned wait is over, so it clocks
    /// nothing even though the state file it wrote is still on disk.
    @Test func forceCancelClearsTheStart() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: startedAt)

        AccountStorage.clearSetupCompletionMarkers(marker)

        #expect(AccountStorage.setupHandoffStartedAt(
            marker: marker,
            now: startedAt.addingTimeInterval(60)
        ) == nil)
        #expect(!AccountStorage.setupHandoffIsActive(marker: marker))
    }

    @Test func discardingAPreparedHandoffClearsTheStart() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: startedAt)

        AccountStorage.clearPreparedSetupCompletionMarker(marker)

        #expect(AccountStorage.setupHandoffStartedAt(
            marker: marker,
            now: startedAt.addingTimeInterval(60)
        ) == nil)
    }

    @Test func consumingAFinishedHandoffClearsTheStart() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: startedAt)

        AccountStorage.clearFinishedSetupCompletionMarkers(marker)

        #expect(AccountStorage.setupHandoffStartedAt(
            marker: marker,
            now: startedAt.addingTimeInterval(60)
        ) == nil)
    }

    /// A successor generation clocks its own wait, not the abandoned one's.
    @Test func aNewGenerationReplacesTheOlderStart() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(7_200)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: first)
        try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: second)

        #expect(AccountStorage.setupHandoffStartedAt(
            marker: marker,
            now: second.addingTimeInterval(30)
        ) == second)
    }

    /// Fail safe, three ways: a state file staged by a build that predates the start, an
    /// unparseable timestamp, and a start in the future all mean "no clock".
    @Test func anUntrustworthyStartYieldsNoClockRatherThanAFabricatedOne() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let generation = try AccountStorage.prepareSetupCompletionMarker(marker, startedAt: startedAt)
        let statePath = URL(fileURLWithPath: AccountStorage.generationStatePath(marker))
        let now = startedAt.addingTimeInterval(600)

        try Data("active:\(generation)\n".utf8).write(to: statePath)
        #expect(AccountStorage.setupHandoffStartedAt(marker: marker, now: now) == nil)
        // The two-field form is still a valid active generation; only the clock is absent.
        #expect(AccountStorage.setupHandoffGeneration(marker: marker) == generation)

        try Data("active:\(generation):not-a-number\n".utf8).write(to: statePath)
        #expect(AccountStorage.setupHandoffStartedAt(marker: marker, now: now) == nil)

        try Data("active:\(generation):\(now.addingTimeInterval(60).timeIntervalSince1970)\n".utf8)
            .write(to: statePath)
        #expect(AccountStorage.setupHandoffStartedAt(marker: marker, now: now) == nil)
    }

    /// The wrapper reads the same generation state, so the start had to be added without
    /// loosening the guard that makes "Stop waiting" stick: a wrapper whose generation was
    /// tombstoned while it ran must still record no completion.
    @Test func aGenerationTombstonedMidRunStillRecordsNoCompletion() throws {
        let (marker, directory) = try makeMarker()
        defer { try? FileManager.default.removeItem(at: directory) }
        let generation = try AccountStorage.prepareSetupCompletionMarker(
            marker,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let statePath = AccountStorage.generationStatePath(marker)
        let scriptURL = directory.appendingPathComponent("setup.command")
        try SetupCompletionCommand.wrap(
            "print -r -- 'cancelled:\(generation)' > '\(statePath)'",
            marker: marker,
            mode: .standard
        ).write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.environment = ["TERM": "xterm-256color"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
        #expect(!FileManager.default.fileExists(
            atPath: AccountStorage.generatedCompletedPath(marker, generation: generation)
        ))
    }
}
