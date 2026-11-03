import Foundation
import Testing
@testable import HeadroomCore

/// Each test writes synthetic session logs under a throwaway Copilot home, answers the
/// status call from a stub, and polls with a fixed clock.
@Suite struct CopilotProviderTests {
    private static let now = copilotMoment("2026-11-20T12:00:00.000Z")
    private static let monthStart = copilotMoment("2026-11-01T00:00:00.000Z")
    private static let monthly = WindowKind.billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60)

    // MARK: Reading and freshness

    @Test func freshEvidenceIsALiveWindowOfUsedOverEntitlement() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 1_500, at: Self.minutesBeforeNow(30)),
                copilotRecord(id: "b", credits: 500, at: Self.minutesBeforeNow(5)),
            ])

            let snapshot = await provider(home, status: .signedIn(account())).fetchSnapshot()

            #expect(snapshot.providerID == .copilot)
            #expect(snapshot.freshness == .live)
            #expect(snapshot.capturedAt == Self.now)
            let window = try #require(snapshot.windows.first)
            #expect(snapshot.windows.count == 1)
            #expect(window.kind == Self.monthly)
            #expect(window.utilization == 10)
            #expect(window.freshness == .live)
            #expect(window.observedAt == nil)
            #expect(window.resetSchedule == .unresolved(.absent))
        }
    }

    @Test func evidenceSixteenMinutesOldIsStaleWhileTheCaptureIsThePoll() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(16)),
            ])

            let snapshot = await provider(home, status: .signedIn(account())).fetchSnapshot()

            #expect(snapshot.freshness == .live)
            #expect(snapshot.capturedAt == Self.now)
            #expect(snapshot.windows.first?.freshness == .stale(observedAt: copilotMoment(Self.minutesBeforeNow(16))))
            #expect(snapshot.windows.first?.utilization == 10)
        }
    }

    @Test func evidenceExactlyFifteenMinutesOldStaysLive() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(15)),
            ])

            let snapshot = await provider(home, status: .signedIn(account())).fetchSnapshot()

            #expect(snapshot.windows.first?.freshness == .live)
            #expect(snapshot.windows.first?.observedAt == nil)
        }
    }

    @Test func aLiveWindowBehindItsEvidenceStillStampsThePollTime() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(14)),
            ])

            let snapshot = await provider(home, status: .signedIn(account())).fetchSnapshot()

            #expect(FreshnessStamp.Anchors(snapshots: [snapshot]).oldestLive == Self.now)
            #expect(FreshnessStamp.resolve(snapshots: [snapshot], now: Self.now).text == "Just now")
        }
    }

    @Test func usedAboveEntitlementClampsAtTheWindow() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 25_000, at: Self.minutesBeforeNow(1)),
            ])

            let window = try #require(await provider(home, status: .signedIn(account())).fetchSnapshot().windows.first)

            #expect(window.utilization == 125)
            #expect(window.percentRemaining == 0)
            #expect(window.percentUsed == 100)
        }
    }

    // MARK: No reading

    @Test func signedInWithNoEvidenceIsLiveWithOneUnavailableRow() async throws {
        try await withHome { home in
            let snapshot = await provider(home, status: .signedIn(account())).fetchSnapshot()

            expectUnavailableRow(snapshot)
        }
    }

    @Test func octoberEvidenceInNovemberIsTheUnavailableRow() async throws {
        try await withHome { home in
            try home.writeSession("october", lines: [
                quotaSnapshotLine(used: 5_000, resetDate: "2026-11-01T00:00:00.000Z", at: "2026-10-30T10:00:00.000Z"),
                copilotRecord(id: "a", credits: 300, at: "2026-10-31T23:00:00.000Z"),
            ])

            let snapshot = await provider(home, status: .signedIn(account())).fetchSnapshot()

            expectUnavailableRow(snapshot)
        }
    }

    @Test func noMeasurableAllowanceIsTheUnavailableRow() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(1)),
            ])

            for status in [
                account(entitlement: 0),
                account(entitlement: nil, isUnlimited: true),
            ] {
                expectUnavailableRow(await provider(home, status: .signedIn(status)).fetchSnapshot())
            }
        }
    }

    // MARK: Failures

    @Test func unreadableSessionLogIsARetryableOutcomeWithoutSignIn() async throws {
        try await withHome { home in
            let file = try home.writeSession("locked", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(1)),
            ])
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

            let snapshot = await provider(home, status: .signedIn(account())).fetchSnapshot()

            #expect(snapshot.freshness == .stale(.providerSetup(.copilotLogsUnreadable)))
            #expect(snapshot.windows.isEmpty)
            #expect(!FailureReason.providerSetup(.copilotLogsUnreadable).isPermanent)
            let recovery = ProviderSetupOutcome.copilotLogsUnreadable.recoveryPresentation
            #expect(recovery.primaryAction == .checkNow)
            #expect(recovery.secondaryAction == nil)
        }
    }

    @Test func statusFailuresWinOverLogsThatExist() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(1)),
            ])

            let expectations: [(CopilotStatusResult, FailureReason)] = [
                (.cliMissing, .providerSetup(.copilotCLIMissing)),
                (.signedOut, .providerSetup(.copilotSignedOut)),
                (.failure(.transient("Couldn’t read Copilot status")), .transient("Couldn’t read Copilot status")),
            ]
            for (status, reason) in expectations {
                let snapshot = await provider(home, status: status).fetchSnapshot()
                #expect(snapshot.freshness == .stale(reason))
                #expect(snapshot.windows.isEmpty)
            }
        }
    }

    // MARK: Server reading

    @Test func aServerReadingAboveTheLogsRaisesUsedByItsLeastProvenUse() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "before", credits: 50, at: "2026-11-02T01:00:00.000Z"),
                copilotRecord(id: "after", credits: 7, at: "2026-11-03T00:00:00.000Z"),
            ])
            // 300 rounds to the nearest 0.5% of 20,000, so at least 250 had been used.
            let status = account(reportedUsed: 300, reportedResetDate: copilotMoment("2026-11-02T02:14:00.000Z"))

            let window = try #require(await provider(home, status: .signedIn(status)).fetchSnapshot().windows.first)

            #expect(window.utilization == 257.0 / 20_000 * 100)
            #expect(window.resetSchedule == .unresolved(.absent))
        }
    }

    @Test func aServerReadingWithinRoundingOfTheLogsLeavesTheLogsFigure() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "before", credits: 280, at: "2026-11-02T01:00:00.000Z"),
                copilotRecord(id: "after", credits: 5, at: "2026-11-03T00:00:00.000Z"),
            ])
            let status = account(reportedUsed: 300, reportedResetDate: copilotMoment("2026-11-02T02:14:00.000Z"))

            let window = try #require(await provider(home, status: .signedIn(status)).fetchSnapshot().windows.first)

            #expect(window.utilization == 285.0 / 20_000 * 100)
        }
    }

    @Test func aServerReadingAloneShowsItsLeastProvenUseAsOfTheReading() async throws {
        try await withHome { home in
            let readAt = copilotMoment("2026-11-02T02:14:00.000Z")
            let status = account(reportedUsed: 300, reportedResetDate: readAt)

            let window = try #require(await provider(home, status: .signedIn(status)).fetchSnapshot().windows.first)

            #expect(window.utilization == 250.0 / 20_000 * 100)
            #expect(window.freshness == .stale(observedAt: readAt))
        }
    }

    @Test func aZeroServerReadingIsNotEvidence() async throws {
        try await withHome { home in
            let status = account(reportedUsed: 0, reportedResetDate: Self.now.addingTimeInterval(-5 * 60))

            expectUnavailableRow(await provider(home, status: .signedIn(status)).fetchSnapshot())
        }
    }

    @Test func aServerReadingFromLastMonthIsIgnored() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 7, at: "2026-11-03T00:00:00.000Z"),
            ])
            let status = account(reportedUsed: 300, reportedResetDate: copilotMoment("2026-10-31T22:00:00.000Z"))

            let window = try #require(await provider(home, status: .signedIn(status)).fetchSnapshot().windows.first)

            #expect(window.utilization == 7.0 / 20_000 * 100)
        }
    }

    @Test func aFutureReportedResetIsTheResetAndNotAnAnchor() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 7, at: "2026-11-03T00:00:00.000Z"),
            ])
            let reset = copilotMoment("2026-12-01T00:00:00.000Z")
            let status = account(reportedUsed: 300, reportedResetDate: reset)

            let window = try #require(await provider(home, status: .signedIn(status)).fetchSnapshot().windows.first)

            #expect(window.utilization == 7.0 / 20_000 * 100)
            #expect(window.resetSchedule == .scheduled(reset))
        }
    }

    // MARK: Login change

    @Test func theFirstLoginSeenChangesNothingAndIsStoredOnlyAsADigest() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(1)),
            ])
            let defaults = freshDefaults()
            let memory = UserDefaultsCopilotLoginMemory(defaults: defaults)

            let snapshot = await provider(home, status: .signedIn(account(login: "first-login")), memory: memory)
                .fetchSnapshot()

            #expect(snapshot.windows.first?.utilization == 10)
            let stored = defaults.dictionaryRepresentation().values.map { "\($0)" }.joined()
            #expect(!stored.contains("first-login"))
        }
    }

    @Test func aLoginChangeWithholdsUsedUntilALaterAnchor() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "old-account", credits: 2_000, at: Self.minutesBeforeNow(1)),
            ])
            let memory = UserDefaultsCopilotLoginMemory(defaults: freshDefaults())
            _ = await provider(home, status: .signedIn(account(login: "first-login")), memory: memory).fetchSnapshot()

            let changed = await provider(home, status: .signedIn(account(login: "second-login")), memory: memory)
                .fetchSnapshot()

            expectUnavailableRow(changed)

            let later = Self.now.addingTimeInterval(60 * 60)
            try home.writeSession("print", lines: [
                copilotRecord(id: "old-account", credits: 2_000, at: Self.minutesBeforeNow(1)),
                copilotRecord(id: "new-account", credits: 4, at: "2026-11-20T12:50:00.000Z"),
            ], modifiedAt: later)
            let anchored = account(
                login: "second-login",
                reportedUsed: 500,
                reportedResetDate: copilotMoment("2026-11-20T12:30:00.000Z")
            )

            let window = try #require(await provider(home, status: .signedIn(anchored), now: later, memory: memory)
                .fetchSnapshot().windows.first)

            // The reading of 500 proves at least 450, half a rounding step lower.
            #expect(window.utilization == 454.0 / 20_000 * 100)
            #expect(window.freshness == .live)
        }
    }

    @Test func aLoginChangeLastMonthNoLongerWithholds() async throws {
        try await withHome { home in
            try home.writeSession("print", lines: [
                copilotRecord(id: "a", credits: 2_000, at: Self.minutesBeforeNow(1)),
            ])
            let memory = UserDefaultsCopilotLoginMemory(defaults: freshDefaults())
            _ = memory.loginChangedAt(noting: "first-login", at: copilotMoment("2026-10-01T00:00:00.000Z"))
            _ = memory.loginChangedAt(noting: "second-login", at: copilotMoment("2026-10-15T00:00:00.000Z"))

            let snapshot = await provider(home, status: .signedIn(account(login: "second-login")), memory: memory)
                .fetchSnapshot()

            #expect(snapshot.windows.first?.utilization == 10)
        }
    }

    // MARK: Helpers

    private static func minutesBeforeNow(_ minutes: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(-minutes * 60))
    }

    private func expectUnavailableRow(_ snapshot: UsageSnapshot, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(snapshot.freshness == .live, sourceLocation: sourceLocation)
        #expect(snapshot.capturedAt == Self.now, sourceLocation: sourceLocation)
        #expect(snapshot.windows.count == 1, sourceLocation: sourceLocation)
        guard let window = snapshot.windows.first else { return }
        #expect(window.kind == Self.monthly, sourceLocation: sourceLocation)
        #expect(window.freshness == .unavailable(since: Self.monthStart), sourceLocation: sourceLocation)
        for mode in UsagePercentageMode.allCases {
            #expect(mode.displayedPercentage(for: window) == nil, sourceLocation: sourceLocation)
        }
    }

    private func account(
        login: String = "copilot-user",
        entitlement: Double? = 20_000,
        isUnlimited: Bool = false,
        reportedUsed: Double? = nil,
        reportedResetDate: Date? = nil
    ) -> CopilotAccountStatus {
        CopilotAccountStatus(
            login: login,
            entitlement: entitlement,
            isUnlimited: isUnlimited,
            tokenBasedBilling: true,
            reportedUsed: reportedUsed,
            reportedResetDate: reportedResetDate
        )
    }

    private func provider(
        _ home: CopilotTestHome,
        status: CopilotStatusResult,
        now: Date = Self.now,
        memory: (any CopilotLoginMemory)? = nil
    ) -> CopilotProvider {
        CopilotProvider(
            statusSource: StubCopilotStatus(result: status),
            ledger: CopilotUsageLedger(copilotHome: home.url, now: { now }),
            loginMemory: memory ?? UserDefaultsCopilotLoginMemory(defaults: freshDefaults()),
            now: { now }
        )
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.copilot-provider.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func withHome(_ body: (CopilotTestHome) async throws -> Void) async throws {
        let home = CopilotTestHome()
        defer { try? FileManager.default.removeItem(at: home.url) }
        try await body(home)
    }
}

private struct StubCopilotStatus: CopilotStatusSourcing {
    let result: CopilotStatusResult
    func status() async -> CopilotStatusResult { result }
}

private func copilotMoment(_ text: String) -> Date {
    guard let date = DateParsing.iso8601(text) else { preconditionFailure("Bad test date \(text)") }
    return date
}

private func copilotRecord(id: String, credits: Int, at timestamp: String) -> String {
    #"{"type":"session.usage_record","data":{"usage":{"copilotUsage":{"totalNanoAiu":\#(credits * 1_000_000_000)},"accounting":{"usageId":"\#(id)"}}},"id":"event-\#(id)","timestamp":"\#(timestamp)","parentId":null}"#
}

private func quotaSnapshotLine(used: Int, resetDate: String, at timestamp: String) -> String {
    #"{"type":"model.model_call_success","data":{"quotaSnapshots":{"premium_interactions":{"entitlementRequests":20000,"usedRequests":\#(used),"resetDate":"\#(resetDate)","isUnlimitedEntitlement":false}}},"id":"event-snapshot","timestamp":"\#(timestamp)","parentId":null}"#
}

private struct CopilotTestHome {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CopilotProviderTests-\(UUID().uuidString)", isDirectory: true)

    /// The default time sits inside the test clock's period, so results never depend on the
    /// real date these files happen to be written.
    @discardableResult
    func writeSession(
        _ name: String,
        lines: [String],
        modifiedAt: Date = copilotMoment("2026-11-20T11:59:00.000Z")
    ) throws -> URL {
        let directory = url
            .appendingPathComponent("session-state", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("events.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
        return file
    }
}
