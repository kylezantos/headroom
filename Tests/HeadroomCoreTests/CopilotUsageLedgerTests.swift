import Foundation
import Testing
@testable import HeadroomCore

/// Every test writes synthetic session logs under a throwaway Copilot home and reads them
/// through the real entry point, with a fixed clock.
@Suite struct CopilotUsageLedgerTests {
    private static let now = moment("2026-11-20T12:00:00.000Z")
    private static let nextReset = "2026-12-01T00:00:00.000Z"

    // MARK: Ledger sum

    @Test func fifteenRecordsInAPrintSessionSumToUsed() async throws {
        try await withCopilotHome { home in
            let lines = (1...15).map { usageRecord(id: "call-\($0)", credits: 2, at: "2026-11-05T10:\(10 + $0):00.000Z") }
            try home.writeSession("print-session", lines: lines)

            let reading = try await read(home)

            #expect(reading.usedCredits == 30)
            #expect(reading.resetsAt == nil)
            #expect(reading.newestEvidenceAt == moment("2026-11-05T10:25:00.000Z"))
        }
    }

    @Test func eightyEightRecordFixtureReproducesItsTotal() async throws {
        try await withCopilotHome { home in
            let fixture = try #require(
                Bundle.module.url(forResource: "copilot-events-88-records", withExtension: "jsonl")
            )
            try home.writeSession("fixture", contents: Data(contentsOf: fixture))

            let reading = try await read(home)

            #expect(reading.usedCredits == 275.2)
            #expect(reading.newestEvidenceAt == moment("2026-11-02T11:16:27.368Z"))
        }
    }

    @Test func sameUsageIDCountsOnceWithinAFileAndAcrossFiles() async throws {
        try await withCopilotHome { home in
            try home.writeSession("first", lines: [
                usageRecord(id: "shared", credits: 5, at: "2026-11-05T10:00:00.000Z"),
                usageRecord(id: "shared", credits: 5, at: "2026-11-05T10:00:00.000Z"),
                usageRecord(id: "only-first", credits: 1, at: "2026-11-05T10:01:00.000Z"),
            ])
            try home.writeSession("second", lines: [
                usageRecord(id: "shared", credits: 5, at: "2026-11-05T10:00:00.000Z"),
                usageRecord(id: "only-second", credits: 2, at: "2026-11-05T10:02:00.000Z"),
            ])

            #expect(try await read(home).usedCredits == 8)
        }
    }

    @Test func recordsFromThePriorUTCMonthAreExcluded() async throws {
        try await withCopilotHome { home in
            try home.writeSession("spans-months", lines: [
                usageRecord(id: "october", credits: 40, at: "2026-10-31T23:59:59.999Z"),
                usageRecord(id: "november", credits: 3, at: "2026-11-01T00:00:00.000Z"),
            ])

            let reading = try await read(home)

            #expect(reading.usedCredits == 3)
            #expect(reading.newestEvidenceAt == moment("2026-11-01T00:00:00.000Z"))
        }
    }

    // MARK: Anchors

    @Test func snapshotPlusLaterRecordsGivesUsedAndEarlierRecordsDoNotAdd() async throws {
        try await withCopilotHome { home in
            try home.writeSession("interactive", lines: [
                usageRecord(id: "before", credits: 40, at: "2026-11-02T01:00:00.000Z"),
                quotaSnapshot(used: 100, resetDate: Self.nextReset, at: "2026-11-02T01:15:00.000Z"),
                usageRecord(id: "after-1", credits: 91, at: "2026-11-02T02:00:00.000Z"),
                usageRecord(id: "after-2", credits: 100, at: "2026-11-02T03:00:00.000Z"),
            ])

            let reading = try await read(home)

            #expect(reading.usedCredits == 291)
            #expect(reading.resetsAt == moment(Self.nextReset))
            #expect(reading.newestEvidenceAt == moment("2026-11-02T03:00:00.000Z"))
        }
    }

    @Test func snapshotWithPastResetIsNeitherResetEvidenceNorAnAnchor() async throws {
        try await withCopilotHome { home in
            try home.writeSession("old-reset", lines: [
                quotaSnapshot(used: 500, resetDate: "2026-11-15T00:00:00.000Z", at: "2026-11-02T01:00:00.000Z"),
                quotaSnapshot(used: 600, resetDate: "2026-11-20T12:00:00.000Z", at: "2026-11-03T01:00:00.000Z"),
                usageRecord(id: "call", credits: 10, at: "2026-11-04T01:00:00.000Z"),
            ])

            let reading = try await read(home)

            #expect(reading.usedCredits == 10)
            #expect(reading.resetsAt == nil)
        }
    }

    @Test func snapshotFromBeforeThePeriodIsNotAnAnchorButItsFutureResetCounts() async throws {
        try await withCopilotHome { home in
            try home.writeSession("spans-months", lines: [
                quotaSnapshot(used: 700, resetDate: "2026-12-15T00:00:00.000Z", at: "2026-10-31T20:00:00.000Z"),
                usageRecord(id: "call", credits: 4, at: "2026-11-04T01:00:00.000Z"),
            ])

            let reading = try await read(home)

            #expect(reading.usedCredits == 4)
            #expect(reading.resetsAt == moment("2026-12-15T00:00:00.000Z"))
        }
    }

    @Test func resetComesFromTheNewestSnapshotNotTheLatestDate() async throws {
        try await withCopilotHome { home in
            try home.writeSession("first", lines: [
                quotaSnapshot(used: 10, resetDate: "2027-01-01T00:00:00.000Z", at: "2026-11-02T01:00:00.000Z"),
            ])
            try home.writeSession("second", lines: [
                quotaSnapshot(used: 20, resetDate: Self.nextReset, at: "2026-11-03T01:00:00.000Z"),
            ])

            let reading = try await read(home)

            #expect(reading.resetsAt == moment(Self.nextReset))
            #expect(reading.usedCredits == 20)
        }
    }

    @Test func callerAnchorNewerThanTheLogSnapshotWins() async throws {
        try await withCopilotHome { home in
            try home.writeSession("interactive", lines: Self.snapshotBetweenRecords)
            let anchor = CopilotUsageAnchor(used: 150, observedAt: moment("2026-11-03T00:00:00.000Z"))

            let reading = try await read(home, anchor: anchor)

            #expect(reading.usedCredits == 161)
            #expect(reading.newestEvidenceAt == moment("2026-11-04T00:00:00.000Z"))
        }
    }

    @Test func callerAnchorOlderThanTheLogSnapshotDoesNotWin() async throws {
        try await withCopilotHome { home in
            try home.writeSession("interactive", lines: Self.snapshotBetweenRecords)
            let anchor = CopilotUsageAnchor(used: 90, observedAt: moment("2026-11-01T00:00:00.000Z"))

            #expect(try await read(home, anchor: anchor).usedCredits == 118)
        }
    }

    @Test func callerAnchorFromBeforeThePeriodIsIgnored() async throws {
        try await withCopilotHome { home in
            try home.writeSession("print", lines: [
                usageRecord(id: "call", credits: 6, at: "2026-11-04T00:00:00.000Z"),
            ])
            let anchor = CopilotUsageAnchor(used: 900, observedAt: moment("2026-10-31T00:00:00.000Z"))

            #expect(try await read(home, anchor: anchor).usedCredits == 6)
        }
    }

    @Test func recordedCreditsSumsThisMonthsRecordsWithoutAnySnapshot() async throws {
        try await withCopilotHome { home in
            try home.writeSession("interactive", lines: Self.snapshotBetweenRecords + [
                usageRecord(id: "between", credits: 7, at: "2026-11-02T12:00:00.000Z"),
                usageRecord(id: "october", credits: 40, at: "2026-10-31T23:00:00.000Z"),
            ])

            let ledger = CopilotUsageLedger(copilotHome: home.url, now: { Self.now })

            #expect(await ledger.recordedCredits() == 18)
        }
    }

    // MARK: Login change

    @Test func evidenceFloorWithholdsUsedUntilAnAnchorAfterIt() async throws {
        try await withCopilotHome { home in
            let floor = moment("2026-11-05T00:00:00.000Z")
            let before = [
                quotaSnapshot(used: 100, resetDate: Self.nextReset, at: "2026-11-02T00:00:00.000Z"),
                quotaSnapshot(used: 200, resetDate: Self.nextReset, at: "2026-11-05T00:00:00.000Z"),
                usageRecord(id: "old-login", credits: 30, at: "2026-11-03T00:00:00.000Z"),
                usageRecord(id: "after-floor", credits: 8, at: "2026-11-06T00:00:00.000Z"),
            ]
            try home.writeSession("session", lines: before)

            let withheld = try await read(home, evidenceNotBefore: floor)

            #expect(withheld == CopilotLedgerReading(usedCredits: nil, resetsAt: nil, newestEvidenceAt: nil))

            try home.writeSession("session", lines: before + [
                quotaSnapshot(used: 300, resetDate: Self.nextReset, at: "2026-11-07T00:00:00.000Z"),
                usageRecord(id: "new-login", credits: 4, at: "2026-11-08T00:00:00.000Z"),
            ], modifiedAt: moment("2026-11-08T00:00:00.000Z"))

            let anchored = try await read(home, evidenceNotBefore: floor)

            #expect(anchored.usedCredits == 304)
            #expect(anchored.resetsAt == moment(Self.nextReset))
            #expect(anchored.newestEvidenceAt == moment("2026-11-08T00:00:00.000Z"))
        }
    }

    @Test func callerAnchorAfterTheEvidenceFloorAlsoReleasesUsed() async throws {
        try await withCopilotHome { home in
            try home.writeSession("session", lines: [
                usageRecord(id: "before-anchor", credits: 8, at: "2026-11-06T00:00:00.000Z"),
                usageRecord(id: "after-anchor", credits: 2, at: "2026-11-08T00:00:00.000Z"),
            ])
            let reading = try await read(
                home,
                anchor: CopilotUsageAnchor(used: 50, observedAt: moment("2026-11-07T00:00:00.000Z")),
                evidenceNotBefore: moment("2026-11-05T00:00:00.000Z")
            )

            #expect(reading.usedCredits == 52)
        }
    }

    @Test func callerAnchorAtTheEvidenceFloorDoesNotCount() async throws {
        try await withCopilotHome { home in
            let floor = moment("2026-11-05T00:00:00.000Z")
            let reading = try await read(
                home,
                anchor: CopilotUsageAnchor(used: 50, observedAt: floor),
                evidenceNotBefore: floor
            )

            #expect(reading.usedCredits == nil)
        }
    }

    // MARK: Billing mode

    @Test func withoutTokenBillingRecordsAreIgnoredAndTheSnapshotIsUsed() async throws {
        try await withCopilotHome { home in
            try home.writeSession("interactive", lines: [
                quotaSnapshot(used: 120, resetDate: Self.nextReset, at: "2026-11-02T00:00:00.000Z"),
                usageRecord(id: "ignored", credits: 50, at: "2026-11-03T00:00:00.000Z"),
            ])

            let reading = try await read(home, tokenBasedBilling: false)

            #expect(reading.usedCredits == 120)
            #expect(reading.newestEvidenceAt == moment("2026-11-02T00:00:00.000Z"))
        }
    }

    @Test func withoutTokenBillingAndWithoutAnAnchorThereIsNoUsedValue() async throws {
        try await withCopilotHome { home in
            try home.writeSession("print", lines: [
                usageRecord(id: "ignored", credits: 50, at: "2026-11-03T00:00:00.000Z"),
            ])

            let reading = try await read(home, tokenBasedBilling: false)

            #expect(reading == CopilotLedgerReading(usedCredits: nil, resetsAt: nil, newestEvidenceAt: nil))
        }
    }

    // MARK: Reading the files

    @Test func truncatedFinalLineIsSkippedAndEarlierLinesCount() async throws {
        try await withCopilotHome { home in
            let complete = usageRecord(id: "complete", credits: 12, at: "2026-11-05T10:00:00.000Z")
            let partial = usageRecord(id: "partial", credits: 99, at: "2026-11-05T11:00:00.000Z")
            let contents = complete + "\n" + partial.prefix(partial.count - 20)
            try home.writeSession("running", contents: Data(contents.utf8))

            let reading = try await read(home)

            #expect(reading.usedCredits == 12)
            #expect(reading.newestEvidenceAt == moment("2026-11-05T10:00:00.000Z"))
        }
    }

    @Test func malformedLinesAreSkipped() async throws {
        try await withCopilotHome { home in
            try home.writeSession("damaged", lines: [
                #"{"type":"session.usage_record","data":{"usage":"not an object"},"timestamp":"2026-11-05T10:00:00.000Z"}"#,
                #"{"type":"session.usage_record","data":{"usage":{"copilotUsage":{"totalNanoAiu":1000000000},"accounting":{"usageId":"bad-time"}}},"timestamp":"yesterday"}"#,
                #"{"type":"model.model_call_success","data":{"requestMessages":[]},"timestamp":"2026-11-05T10:00:00.000Z"}"#,
                usageRecord(id: "good", credits: 7, at: "2026-11-05T10:00:00.000Z"),
            ])

            #expect(try await read(home).usedCredits == 7)
        }
    }

    @Test func filesLastChangedBeforeThePeriodAreNotRead() async throws {
        try await withCopilotHome { home in
            try home.writeSession(
                "untouched",
                lines: [usageRecord(id: "unseen", credits: 25, at: "2026-11-05T10:00:00.000Z")],
                modifiedAt: moment("2026-10-31T23:59:59.000Z")
            )
            try home.writeSession("changed", lines: [
                usageRecord(id: "seen", credits: 1, at: "2026-11-05T10:00:00.000Z"),
            ])

            #expect(try await read(home).usedCredits == 1)
        }
    }

    @Test func unchangedFileIsNotRereadUntilItsSizeOrTimeMoves() async throws {
        try await withCopilotHome { home in
            let ledger = CopilotUsageLedger(copilotHome: home.url, now: { Self.now })
            let stamp = moment("2026-11-10T00:00:00.000Z")
            let original = usageRecord(id: "memo", credits: 5, at: "2026-11-05T10:00:00.000Z")
            let sameSize = usageRecord(id: "memo", credits: 9, at: "2026-11-05T10:00:00.000Z")
            #expect(original.utf8.count == sameSize.utf8.count)

            try home.writeSession("session", lines: [original], modifiedAt: stamp)
            #expect(try await readValue(ledger).usedCredits == 5)

            try home.writeSession("session", lines: [sameSize], modifiedAt: stamp)
            #expect(try await readValue(ledger).usedCredits == 5)

            try home.writeSession("session", lines: [sameSize], modifiedAt: stamp.addingTimeInterval(1))
            #expect(try await readValue(ledger).usedCredits == 9)

            let grown = usageRecord(id: "more", credits: 1, at: "2026-11-05T11:00:00.000Z")
            try home.writeSession("session", lines: [sameSize, grown], modifiedAt: stamp.addingTimeInterval(1))
            #expect(try await readValue(ledger).usedCredits == 10)
        }
    }

    @Test func missingSessionStateIsNoEvidenceAndNoFailure() async throws {
        try await withCopilotHome { home in
            let outcome = await CopilotUsageLedger(copilotHome: home.url, now: { Self.now })
                .read(CopilotLedgerInput(tokenBasedBilling: true))

            #expect(outcome == .reading(CopilotLedgerReading(usedCredits: nil, resetsAt: nil, newestEvidenceAt: nil)))
        }
    }

    @Test func callerAnchorStillAppliesWithoutSessionState() async throws {
        try await withCopilotHome { home in
            let anchor = CopilotUsageAnchor(used: 75, observedAt: moment("2026-11-03T00:00:00.000Z"))

            let reading = try await read(home, anchor: anchor)

            #expect(reading.usedCredits == 75)
            #expect(reading.newestEvidenceAt == anchor.observedAt)
        }
    }

    @Test func unreadableSessionStateIsDistinctFromNoEvidence() async throws {
        try await withCopilotHome { home in
            try home.writeSession("session", lines: [
                usageRecord(id: "call", credits: 1, at: "2026-11-05T10:00:00.000Z"),
            ])
            try home.setPermissions(0o000, at: home.sessionState)
            defer { try? home.setPermissions(0o755, at: home.sessionState) }

            let outcome = await CopilotUsageLedger(copilotHome: home.url, now: { Self.now })
                .read(CopilotLedgerInput(tokenBasedBilling: true))

            #expect(outcome == .unreadable)
        }
    }

    @Test func unreadableSessionFileIsDistinctFromNoEvidence() async throws {
        try await withCopilotHome { home in
            try home.writeSession("readable", lines: [
                usageRecord(id: "call", credits: 1, at: "2026-11-05T10:00:00.000Z"),
            ])
            let locked = try home.writeSession("locked", lines: [
                usageRecord(id: "hidden", credits: 1, at: "2026-11-05T10:00:00.000Z"),
            ])
            try home.setPermissions(0o000, at: locked)

            let outcome = await CopilotUsageLedger(copilotHome: home.url, now: { Self.now })
                .read(CopilotLedgerInput(tokenBasedBilling: true))

            #expect(outcome == .unreadable)
        }
    }

    @Test func unreadableSessionDirectoryIsDistinctFromNoEvidence() async throws {
        try await withCopilotHome { home in
            let locked = try home.writeSession("locked", lines: [
                usageRecord(id: "hidden", credits: 1, at: "2026-11-05T10:00:00.000Z"),
            ]).deletingLastPathComponent()
            try home.setPermissions(0o000, at: locked)
            defer { try? home.setPermissions(0o755, at: locked) }

            let outcome = await CopilotUsageLedger(copilotHome: home.url, now: { Self.now })
                .read(CopilotLedgerInput(tokenBasedBilling: true))

            #expect(outcome == .unreadable)
        }
    }

    // MARK: Helpers

    /// A snapshot of 100 with 7 credits between it and a caller anchor, and 11 after both.
    private static let snapshotBetweenRecords = [
        quotaSnapshot(used: 100, resetDate: nextReset, at: "2026-11-02T01:15:00.000Z"),
        usageRecord(id: "between", credits: 7, at: "2026-11-02T12:00:00.000Z"),
        usageRecord(id: "after-both", credits: 11, at: "2026-11-04T00:00:00.000Z"),
    ]

    private func read(
        _ home: CopilotHome,
        tokenBasedBilling: Bool = true,
        anchor: CopilotUsageAnchor? = nil,
        evidenceNotBefore: Date? = nil
    ) async throws -> CopilotLedgerReading {
        try await readValue(
            CopilotUsageLedger(copilotHome: home.url, now: { Self.now }),
            CopilotLedgerInput(
                tokenBasedBilling: tokenBasedBilling,
                anchor: anchor,
                evidenceNotBefore: evidenceNotBefore
            )
        )
    }

    private func readValue(
        _ ledger: CopilotUsageLedger,
        _ input: CopilotLedgerInput = CopilotLedgerInput(tokenBasedBilling: true)
    ) async throws -> CopilotLedgerReading {
        guard case .reading(let reading) = await ledger.read(input) else {
            Issue.record("Expected a reading")
            throw CancellationError()
        }
        return reading
    }
}

private func moment(_ text: String) -> Date {
    guard let date = DateParsing.iso8601(text) else { preconditionFailure("Bad test date \(text)") }
    return date
}

private func usageRecord(id: String, credits: Int, at timestamp: String) -> String {
    #"{"type":"session.usage_record","data":{"usage":{"copilotUsage":{"totalNanoAiu":\#(credits * 1_000_000_000)},"accounting":{"usageId":"\#(id)"},"aiCreditsStatus":"included"}},"id":"event-\#(id)","timestamp":"\#(timestamp)","parentId":null}"#
}

private func quotaSnapshot(used: Int, resetDate: String, at timestamp: String) -> String {
    #"{"type":"model.model_call_success","data":{"requestMessages":[{"role":"user","content":"synthetic prompt"}],"quotaSnapshots":{"premium_interactions":{"entitlementRequests":20000,"usedRequests":\#(used),"resetDate":"\#(resetDate)","isUnlimitedEntitlement":false}}},"id":"event-snapshot","timestamp":"\#(timestamp)","parentId":null}"#
}

private func withCopilotHome(_ body: (CopilotHome) async throws -> Void) async throws {
    let home = CopilotHome()
    defer { try? FileManager.default.removeItem(at: home.url) }
    try await body(home)
}

private struct CopilotHome {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CopilotUsageLedgerTests-\(UUID().uuidString)", isDirectory: true)

    var sessionState: URL { url.appendingPathComponent("session-state", isDirectory: true) }

    /// The default time sits inside the test clock's period, so results never depend on
    /// the real date these files happen to be written.
    @discardableResult
    func writeSession(
        _ name: String,
        contents: Data,
        modifiedAt: Date = moment("2026-11-10T00:00:00.000Z")
    ) throws -> URL {
        let directory = sessionState.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("events.jsonl")
        try contents.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
        return file
    }

    @discardableResult
    func writeSession(
        _ name: String,
        lines: [String],
        modifiedAt: Date = moment("2026-11-10T00:00:00.000Z")
    ) throws -> URL {
        try writeSession(name, contents: Data((lines.joined(separator: "\n") + "\n").utf8), modifiedAt: modifiedAt)
    }

    func setPermissions(_ mode: Int, at target: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
    }
}
