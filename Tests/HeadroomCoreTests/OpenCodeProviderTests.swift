import Foundation
import Testing
@testable import HeadroomCore

/// U3 of the OpenCode plan: a capture becomes an honest snapshot (KTD6, KTD7) and the card's
/// limited sentence (D3, KTD21). Every source is a fixed double (KTD17).
private actor FixedOpenCodeSource: OpenCodeUsageSource {
    private var captures: [OpenCodeCapture]
    private(set) var homes: [OpenCodeAccountHome] = []

    init(_ captures: [OpenCodeCapture]) { self.captures = captures }

    func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        homes.append(home)
        return captures.count > 1 ? captures.removeFirst() : captures[0]
    }
}

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

struct OpenCodeProviderTests {
    /// Thu 12 Nov 2026 17:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_502_800)
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400
    private let utc = TimeZone(identifier: "UTC")!
    private let locale = Locale(identifier: "en_US_POSIX")

    private func go(_ percent: Double, limited: Bool = false, resetIn: TimeInterval) -> OpenCodeGoWindow {
        OpenCodeGoWindow(percentUsed: limited ? 100 : percent, isLimited: limited, resetsAt: now.addingTimeInterval(resetIn))
    }

    private func usage(
        rolling: OpenCodeGoWindow? = nil, weekly: OpenCodeGoWindow? = nil, monthly: OpenCodeGoWindow? = nil
    ) -> OpenCodeCapture {
        .goUsage(OpenCodeGoUsage(
            rolling: rolling ?? go(12, resetIn: 3 * hour),
            weekly: weekly ?? go(40, resetIn: 4 * day),
            monthly: monthly ?? go(25, resetIn: 18 * day)
        ))
    }

    private func provider(
        _ captures: [OpenCodeCapture],
        home: OpenCodeAccountHome = .builtIn,
        accountID: AccountID = .primary,
        clock: Clock? = nil
    ) -> (OpenCodeProvider, FixedOpenCodeSource) {
        let source = FixedOpenCodeSource(captures)
        let clock = clock ?? Clock(now)
        return (OpenCodeProvider(source: source, accountID: accountID, home: home, now: { clock.now }), source)
    }

    private func fetch(_ capture: OpenCodeCapture) async -> UsageSnapshot {
        await provider([capture]).0.fetchSnapshot()
    }

    // MARK: - KTD6

    @Test func windowsMapByNameInOrderWithTheirResets() async {
        let snapshot = await fetch(usage())
        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.map(\.kind) == [
            .fiveHour, .weekly, .billingPeriod(label: "Monthly", duration: 2_592_000),
        ])
        #expect(snapshot.windows.map(\.utilization) == [12, 40, 25])
        #expect(snapshot.windows.map(\.resetSchedule) == [
            .scheduled(now.addingTimeInterval(3 * hour)),
            .scheduled(now.addingTimeInterval(4 * day)),
            .scheduled(now.addingTimeInterval(18 * day)),
        ])
        #expect(snapshot.windows.allSatisfy { $0.freshness == .live && !$0.isLimited })
        // KTD19: no plan label, workspace or email; a Go reading carries no plan status.
        #expect(snapshot.planLabel == nil)
        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.planStatus == nil)
        #expect(snapshot.capturedAt == now)
    }

    @Test func resetsComeFromTheClientsMillisecondsDividedByAThousand() throws {
        // U2's DTO divides; pinned here end to end so the provider never re-scales.
        let json = #"{"percent":12,"limited":false,"resetsAt":1794513600000}"#
        let dto = try JSONDecoder().decode(OpenCodeGoWindowDTO.self, from: Data(json.utf8))
        #expect(dto.window?.resetsAt == Date(timeIntervalSince1970: 1_794_513_600))
    }

    /// Settings › Accounts' retained-usage line draws `snapshot.windows.prefix(2)` with each
    /// kind's own `compactName`: source order puts monthly third, so it drops without any
    /// window being relabelled, and the popover's `fiveHourFirst()` leaves the order alone.
    @Test func theRetainedUsageLineShowsTwoWindowsAndDropsMonthly() async {
        let snapshot = await fetch(usage())
        #expect(snapshot.windows.prefix(2).map(\.kind) == [.fiveHour, .weekly])
        #expect(snapshot.windows.prefix(2).map(\.kind.compactName) == [WindowKind.fiveHour.compactName, WindowKind.weekly.compactName])
        #expect(snapshot.fiveHourFirst().windows == snapshot.windows)
    }

    @Test func zeroAndOneHundredKeepTheirValues() async {
        let snapshot = await fetch(usage(rolling: go(0, resetIn: hour), weekly: go(100, resetIn: day)))
        #expect(snapshot.windows.map(\.utilization) == [0, 100, 25])
        #expect(!snapshot.windows[1].isLimited)
    }

    /// Covers AE1: 92% with `limited: true` reads 100% used and the sentence names it.
    @Test func aLimitedWindowReadsFullyUsedAndTheSentenceNamesIt() async throws {
        let limitedMonthly = OpenCodeGoWindow(percentUsed: 100, isLimited: true, resetsAt: now.addingTimeInterval(18 * day))
        let snapshot = await fetch(usage(monthly: limitedMonthly))
        #expect(snapshot.windows[2].utilization == 100)
        #expect(snapshot.windows[2].percentRemaining == 0)
        #expect(snapshot.windows[2].isLimited)
        let sentence = try #require(UsageLimitSentence(snapshot: snapshot, now: now, timeZone: utc, locale: locale))
        #expect(sentence.window.kind == OpenCodeProvider.monthlyKind)
        #expect(sentence.text == "Go’s monthly limit is reached until Nov 30")
    }

    @Test func aLimitedWindowFromTheRealDTOReadsOneHundred() throws {
        let json = #"{"percent":92,"limited":true,"resetsAt":1796000000000}"#
        let window = try #require(try JSONDecoder().decode(OpenCodeGoWindowDTO.self, from: Data(json.utf8)).window)
        #expect(window.percentUsed == 100)
        #expect(window.isLimited)
    }

    // MARK: - The limited sentence (D3, KTD21)

    @Test func severalLimitedWindowsNameTheOneThatResetsLast() async throws {
        let snapshot = await fetch(usage(
            weekly: go(0, limited: true, resetIn: 4 * day),
            monthly: go(0, limited: true, resetIn: 2 * day)
        ))
        let sentence = try #require(UsageLimitSentence(snapshot: snapshot, now: now, timeZone: utc, locale: locale))
        #expect(sentence.window.kind == .weekly)
        // The shared formatter's own spacing (a narrow no-break space before PM) is kept.
        #expect(sentence.text.replacingOccurrences(of: "\u{202F}", with: " ")
            == "Go’s weekly limit is reached until Monday at 5:00 PM")
        #expect(sentence.text == "Go’s weekly limit is reached until "
            + ResetClockFormatter.phrase(for: now.addingTimeInterval(4 * day), now: now, timeZone: utc, locale: locale))
    }

    @Test func allThreeLimitedNameTheLatestReset() async throws {
        let snapshot = await fetch(usage(
            rolling: go(0, limited: true, resetIn: 2 * hour),
            weekly: go(0, limited: true, resetIn: 4 * day),
            monthly: go(0, limited: true, resetIn: 18 * day)
        ))
        let sentence = try #require(UsageLimitSentence(snapshot: snapshot, now: now, timeZone: utc, locale: locale))
        #expect(sentence.window.kind == OpenCodeProvider.monthlyKind)
    }

    @Test func aFiveHourLimitReadsTodayOrTomorrow() async throws {
        let snapshot = await fetch(usage(rolling: go(0, limited: true, resetIn: 2 * hour)))
        let sentence = try #require(UsageLimitSentence(snapshot: snapshot, now: now, timeZone: utc, locale: locale))
        #expect(sentence.text.replacingOccurrences(of: "\u{202F}", with: " ")
            == "Go’s 5-hour limit is reached until today at 7:00 PM")
        #expect(!sentence.text.localizedCaseInsensitiveContains("refus"))
        #expect(!sentence.text.localizedCaseInsensitiveContains("fall"))
    }

    @Test func oneHundredWithoutTheLimitedFlagHasNoSentence() async {
        let snapshot = await fetch(usage(monthly: go(100, resetIn: 18 * day)))
        #expect(UsageLimitSentence(snapshot: snapshot, now: now) == nil)
    }

    @Test func theSentenceNeedsALiveWindowWithAFutureReset() async {
        let limited = await fetch(usage(monthly: go(0, limited: true, resetIn: 18 * day)))
        let observed = now.addingTimeInterval(-600)

        let stale = limited.replacingWindows(limited.windows.map { $0.withFreshness(.stale(observedAt: observed)) })
        #expect(UsageLimitSentence(snapshot: stale, now: now) == nil)

        let unavailable = limited.replacingWindows(limited.windows.map { $0.withFreshness(.unavailable(since: observed)) })
        #expect(UsageLimitSentence(snapshot: unavailable, now: now) == nil)

        let resetAt = now.addingTimeInterval(18 * day)
        #expect(UsageLimitSentence(snapshot: limited, now: resetAt) == nil, "reset exactly now")
        #expect(UsageLimitSentence(snapshot: limited, now: resetAt.addingTimeInterval(1)) == nil)
        #expect(UsageLimitSentence(snapshot: limited, now: resetAt.addingTimeInterval(-1)) != nil)
    }

    @Test func aFailedPollAfterALimitDropsTheSentence() async {
        let limited = await fetch(usage(monthly: go(0, limited: true, resetIn: 18 * day)))
        let merged = UsageContinuityPolicy.mergedSnapshot(
            .stale(for: .opencode, reason: .providerSetup(.opencodeTransientCapture)),
            with: limited, at: now.addingTimeInterval(300)
        )
        #expect(merged.windows.count == 3)
        #expect(UsageLimitSentence(snapshot: merged, now: now.addingTimeInterval(300)) == nil)
    }

    @Test func onlyAProviderThatReportsLimitsHasASentence() {
        let window = UsageWindow(kind: .weekly, utilization: 100, resetSchedule: .scheduled(now.addingTimeInterval(day)),
                                 isLimited: true)
        let claude = UsageSnapshot.live(.claude, windows: [window], at: now)
        #expect(UsageLimitSentence(snapshot: claude, now: now) == nil)
    }

    // MARK: - KTD7: no Go plan

    /// Covers AE2: live, one unavailable Monthly row, the no-plan status, a stable `since`.
    @Test func noGoPlanIsALiveReadingWithOneUnavailableRow() async throws {
        let clock = Clock(now)
        let (provider, _) = provider([.noGoPlan], clock: clock)
        let first = await provider.fetchSnapshot()
        #expect(first.freshness == .live)
        #expect(first.planStatus == .noActivePlan)
        #expect(first.planLabel == nil)
        #expect(first.windows.count == 1)
        let row = try #require(first.windows.first)
        #expect(row.kind == OpenCodeProvider.monthlyKind)
        #expect(row.resetSchedule == .unresolved(.absent))
        let monthStart = try #require(DateParsing.iso8601("2026-11-01T00:00:00Z"))
        #expect(row.freshness == .unavailable(since: monthStart))
        #expect(UsagePercentageMode.remaining.displayedPercentage(for: row) == nil)
        #expect(first.planStatusRecovery?.status == "No Go plan on this workspace")
        #expect(UsageLimitSentence(snapshot: first, now: now) == nil)

        clock.now = now.addingTimeInterval(5 * 60)
        let second = await provider.fetchSnapshot()
        #expect(second.windows == first.windows, "the row is identical between polls")

        clock.now = try #require(DateParsing.iso8601("2026-12-02T00:00:00Z"))
        let nextMonth = await provider.fetchSnapshot()
        #expect(nextMonth.windows.first?.freshness == .unavailable(since: try #require(DateParsing.iso8601("2026-12-01T00:00:00Z"))))
    }

    @Test func noGoToGoClearsTheStatusAndBack() async {
        let (provider, _) = provider([.noGoPlan, usage(), .noGoPlan])
        #expect(await provider.fetchSnapshot().planStatus == .noActivePlan)
        let go = await provider.fetchSnapshot()
        #expect(go.planStatus == nil)
        #expect(go.windows.count == 3)
        #expect(await provider.fetchSnapshot().planStatus == .noActivePlan)
    }

    @Test func aPermanentFailureWinsOverARetainedNoPlanStatus() async {
        let noGo = await fetch(.noGoPlan)
        let signedOut = UsageContinuityPolicy.mergedSnapshot(
            .stale(for: .opencode, reason: .providerSetup(.opencodeSignedOut)), with: noGo, at: now)
        #expect(signedOut.planStatus == .noActivePlan)
        #expect(signedOut.planStatusRecovery == nil)
        let transient = UsageContinuityPolicy.mergedSnapshot(
            .stale(for: .opencode, reason: .providerSetup(.opencodeTransientCapture)), with: noGo, at: now)
        #expect(transient.planStatusRecovery?.primaryAction == .seeOpenCodeGoPlans)
    }

    // MARK: - Failures

    @Test func everyFailureIsTheMatchingStaleSnapshot() async {
        let failures: [OpenCodeCaptureFailure] = [
            .cliMissing, .updateRequired, .signedOut, .consoleSignInRequired, .signInExpired,
            .formatChanged(.usageValues), .formatChanged(.clientDecode), .transient(.deadline),
        ]
        for failure in failures {
            let snapshot = await fetch(.failed(failure))
            #expect(snapshot.freshness == .stale(.providerSetup(failure.outcome)), "\(failure)")
            #expect(snapshot.windows.isEmpty)
            #expect(snapshot.planStatus == nil)
        }
    }

    /// The schema makes all three windows required, so a missing monthly window is a contract
    /// change: U2 fails it as format changed, and the provider passes that through.
    @Test func aReadingMissingTheMonthlyWindowIsFormatChanged() throws {
        let json = #"{"rolling":{"percent":1,"limited":false,"resetsAt":1794513600000},"weekly":{"percent":1,"limited":false,"resetsAt":1794513600000}}"#
        #expect((try? JSONDecoder().decode(OpenCodeGoDTO.self, from: Data(json.utf8))) == nil)
        #expect(OpenCodeCaptureFailure.formatChanged(.clientDecode).outcome == .opencodeFormatChanged)
        #expect(!OpenCodeCaptureFailure.formatChanged(.clientDecode).failureReason.isPermanent)
    }

    @Test func anEarlierLiveWindowGoesStaleThenUnavailable() async throws {
        let live = await fetch(usage(rolling: go(30, resetIn: hour)))
        let failed = UsageSnapshot.stale(for: .opencode, reason: .providerSetup(.opencodeTransientCapture))

        let soon = UsageContinuityPolicy.mergedSnapshot(failed, with: live, at: now.addingTimeInterval(600))
        #expect(soon.windows.first?.freshness == .stale(observedAt: now))
        #expect(soon.freshness == failed.freshness)

        // Past the 5-hour reset the window drops out; the billing period turns unavailable.
        let later = UsageContinuityPolicy.mergedSnapshot(failed, with: live, at: now.addingTimeInterval(19 * day))
        #expect(!later.windows.contains { $0.kind == .fiveHour })
        #expect(later.windows.first { $0.kind == OpenCodeProvider.monthlyKind }?.freshness
            == .unavailable(since: now.addingTimeInterval(18 * day)))
    }

    @Test func signedOutAndNeedsReauthAreSignInStates() async {
        #expect((await fetch(.failed(.signedOut))).freshness == .stale(.providerSetup(.opencodeSignedOut)))
        #expect((await fetch(.failed(.signInExpired))).freshness == .stale(.providerSetup(.opencodeSignInExpired)))
        #expect(OpenCodeCaptureFailure.signInExpired.failureReason.isPermanent)
        #expect(!OpenCodeCaptureFailure.transient(.consoleUnavailable).failureReason.isPermanent)
    }

    // MARK: - Identity and lane

    @Test func identityLaneAndHome() async {
        let (provider, source) = provider([usage()], home: .isolated(root: "/tmp/acct"), accountID: AccountID("work"))
        #expect(provider.id == .opencode)
        #expect(provider.displayName == "OpenCode")
        #expect(provider.accountKey == AccountKey(providerID: .opencode, accountID: AccountID("work")))
        #expect(provider.pollingLane == .serial("opencode-cli"))
        #expect(provider.accountCapacity == AccountRegistry.testedEnvelope)
        _ = await provider.fetchSnapshot()
        #expect(await source.homes == [.isolated(root: "/tmp/acct")])
    }
}
