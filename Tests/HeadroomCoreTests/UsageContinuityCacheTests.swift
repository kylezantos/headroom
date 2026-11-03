import Foundation
import Testing
@testable import HeadroomCore

struct UsageContinuityCacheTests {
    @Test func roundTripPreservesDisplaySafeWindowsPerAccount() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let primary = AccountKey(providerID: .claude, accountID: .primary)
        let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
        let reset = Date(timeIntervalSince1970: 3_000_000)
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)

        cache.save(
            .live(.claude, windows: [
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 39,
                    resetsAt: reset,
                    resetLabel: "Resets Jul 23 at 9:59am",
                    freshness: .stale(observedAt: capturedAt)
                ),
            ], plan: "Max", at: capturedAt),
            for: primary
        )
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 12, resetsAt: reset),
            ], at: capturedAt),
            for: work
        )

        let restored = UsageContinuityCache(defaults: defaults).load()

        #expect(restored[primary]?.windows.map(\.kind) == [.other("Weekly (Fable)")])
        #expect(restored[primary]?.windows.first?.resetLabel == "Resets Jul 23 at 9:59am")
        #expect(restored[primary]?.planLabel == "Max")
        #expect(restored[primary]?.capturedAt == capturedAt)
        #expect(restored[primary]?.windows.first?.freshness == .stale(observedAt: capturedAt))
        #expect(restored[work]?.windows.map(\.kind) == [.weekly])
        if case .stale = restored[primary]?.freshness {} else {
            Issue.record("restored continuity data must never claim to be live")
        }
    }

    @Test func removeDeletesOnlyTheRequestedAccount() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let primary = AccountKey(providerID: .claude, accountID: .primary)
        let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
        let snapshot = UsageSnapshot.live(
            .claude,
            windows: [UsageWindow(kind: .weekly, utilization: 12, resetsAt: .distantFuture)]
        )
        cache.save(snapshot, for: primary)
        cache.save(snapshot, for: work)

        cache.remove(for: work)

        #expect(cache.load()[primary] != nil)
        #expect(cache.load()[work] == nil)
    }

    @Test func billingPeriodRestoresWithFutureResetAndOriginalObservation() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let key = AccountKey(providerID: .grok, accountID: .primary)
        let observedAt = Date(timeIntervalSince1970: 2_000_000)
        let duration: TimeInterval = 30 * 24 * 60 * 60
        let resetsAt = observedAt.addingTimeInterval(duration)
        let kind = WindowKind.billingPeriod(label: "Monthly", duration: duration)
        cache.save(
            .live(.grok, windows: [
                UsageWindow(kind: kind, utilization: 25, resetsAt: resetsAt),
            ], at: observedAt),
            for: key
        )

        let cached = UsageContinuityCache(defaults: defaults).load()[key]
        let restored = UsageContinuityPolicy.restoredSnapshot(
            cached,
            for: .grok,
            at: observedAt.addingTimeInterval(2 * 24 * 60 * 60)
        )

        #expect(restored.windows.first?.kind == kind)
        #expect(restored.windows.first?.freshness == .stale(observedAt: observedAt))
        #expect(restored.windows.first?.resetSchedule == .scheduled(resetsAt))
    }

    @Test func corruptPersistenceFailsSafe() {
        let defaults = freshDefaults()
        defaults.set(Data("not-json".utf8), forKey: "usageContinuitySnapshots.v1")

        #expect(UsageContinuityCache(defaults: defaults).load().isEmpty)
    }

    @Test func mismatchedProviderKeyIsRejected() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let claudeKey = AccountKey(providerID: .claude, accountID: .primary)
        cache.save(
            .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 12, resetsAt: .distantFuture),
            ]),
            for: claudeKey
        )

        #expect(cache.load().isEmpty)
    }

    @Test func failureDetailsAreNeverPersisted() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let secret = "SECRET_PROVIDER_FAILURE_DETAIL"
        cache.save(
            UsageSnapshot(
                providerID: .claude,
                windows: [UsageWindow(kind: .weekly, utilization: 12, resetsAt: .distantFuture)],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .stale(.transient(secret))
            ),
            for: AccountKey(providerID: .claude, accountID: .primary)
        )

        let encoded = defaults.data(forKey: "usageContinuitySnapshots.v2") ?? Data()
        #expect(!String(decoding: encoded, as: UTF8.self).contains(secret))
    }

    @Test func unresolvedResetRoundTripsWithoutADeadline() throws {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let observedAt = Date(timeIntervalSince1970: 2_000_000)
        cache.save(
            .live(.claude, windows: [
                UsageWindow(
                    kind: .fiveHour,
                    utilization: 0,
                    resetSchedule: .unresolved(.absent),
                    observedAt: observedAt
                ),
            ], at: observedAt),
            for: key
        )

        let restored = try #require(cache.load()[key]?.windows.first)
        let encoded = try #require(defaults.data(forKey: "usageContinuitySnapshots.v2"))

        #expect(restored.resetSchedule == .unresolved(.absent))
        #expect(restored.observedAt == observedAt)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("resetDeadline"))
    }

    @Test func everyUnresolvedReasonPreservesObservationAcrossLifecycle() throws {
        let observedAt = Date(timeIntervalSince1970: 2_000_000)
        let kind = WindowKind.other("Weekly (Fable)")

        for reason in ResetUnresolvedReason.allCases {
            let window = UsageWindow(
                kind: kind,
                utilization: 39,
                resetSchedule: .unresolved(reason),
                observedAt: observedAt
            )
            let source = UsageSnapshot.live(.claude, windows: [window], at: observedAt)

            let stale = UsageContinuityPolicy.restoredSnapshot(
                source,
                for: .claude,
                at: observedAt.addingTimeInterval(6 * 24 * 60 * 60)
            )
            let staleWindow = try #require(stale.windows.first)
            #expect(staleWindow.resetSchedule == .unresolved(reason))
            #expect(staleWindow.observedAt == observedAt)
            #expect(staleWindow.freshness == .stale(observedAt: observedAt))

            let unavailableAt = observedAt.addingTimeInterval(7 * 24 * 60 * 60)
            let unavailable = UsageContinuityPolicy.restoredSnapshot(
                stale,
                for: .claude,
                at: unavailableAt.addingTimeInterval(1)
            )
            let unavailableWindow = try #require(unavailable.windows.first)
            #expect(unavailableWindow.resetSchedule == .unresolved(reason))
            #expect(unavailableWindow.observedAt == observedAt)
            #expect(unavailableWindow.freshness == .unavailable(since: unavailableAt))

            let removed = UsageContinuityPolicy.restoredSnapshot(
                unavailable,
                for: .claude,
                at: unavailableAt.addingTimeInterval(7 * 24 * 60 * 60)
            )
            #expect(removed.windows.isEmpty)
        }
    }

    @Test func legacyFutureAndPastDeadlinesMigrateWithoutSentinels() throws {
        let defaults = freshDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)
        let future = capturedAt.addingTimeInterval(3_600)
        let past = capturedAt.addingTimeInterval(-3_600)
        let legacy = [LegacySnapshotFixture(
            key: key,
            windows: [
                LegacyWindowFixture(
                    kind: "weekly",
                    otherLabel: nil,
                    billingPeriodDuration: nil,
                    utilization: 30,
                    resetsAt: future,
                    resetLabel: nil,
                    staleObservedAt: nil,
                    unavailableSince: nil
                ),
                LegacyWindowFixture(
                    kind: "other",
                    otherLabel: "Weekly (Fable)",
                    billingPeriodDuration: nil,
                    utilization: 40,
                    resetsAt: past,
                    resetLabel: nil,
                    staleObservedAt: nil,
                    unavailableSince: nil
                ),
            ],
            planLabel: nil,
            accountEmail: nil,
            capturedAt: capturedAt
        )]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "usageContinuitySnapshots.v1")

        let windows = try #require(UsageContinuityCache(defaults: defaults).load()[key]?.windows)

        #expect(windows.first { $0.kind == .weekly }?.resetSchedule == .scheduled(future))
        #expect(windows.first { $0.kind == .other("Weekly (Fable)") }?.resetSchedule == .unresolved(.elapsed))
    }

    @Test func legacySentinelMigratesReadOnlyToVersionedUnknownEvidence() throws {
        let defaults = freshDefaults()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)
        let legacy = [LegacySnapshotFixture(
            key: key,
            windows: [LegacyWindowFixture(
                kind: "fiveHour",
                otherLabel: nil,
                billingPeriodDuration: nil,
                utilization: 0,
                resetsAt: capturedAt,
                resetLabel: nil,
                staleObservedAt: nil,
                unavailableSince: nil
            )],
            planLabel: "Max",
            accountEmail: nil,
            capturedAt: capturedAt
        )]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "usageContinuitySnapshots.v1")

        let restored = try #require(UsageContinuityCache(defaults: defaults).load()[key]?.windows.first)

        #expect(restored.resetSchedule == .unresolved(.legacyUnknown))
        #expect(restored.freshness == .stale(observedAt: capturedAt))
        #expect(restored.observedAt == capturedAt)
        #expect(defaults.data(forKey: "usageContinuitySnapshots.v2") != nil)
        #expect(defaults.data(forKey: "usageContinuitySnapshots.v1") != nil)
        #expect(Countdown.resetText(for: restored, now: capturedAt) == "Reset info unavailable")
    }

    @Test func futureVersionedPayloadIsNotOverwrittenBySaveOrRemove() throws {
        let defaults = freshDefaults()
        let future = Data(#"{"schemaVersion":999,"records":[]}"#.utf8)
        defaults.set(future, forKey: "usageContinuitySnapshots.v2")
        let cache = UsageContinuityCache(defaults: defaults)
        let key = AccountKey(providerID: .claude, accountID: .primary)

        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 12, resetsAt: .distantFuture),
            ]),
            for: key
        )
        cache.remove(for: key)

        #expect(defaults.data(forKey: "usageContinuitySnapshots.v2") == future)
        #expect(cache.load().isEmpty)
    }

    @Test func staleMergeKeepsLastKnownBankedResets() {
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)
        let prior = UsageSnapshot(
            providerID: .codex,
            windows: [UsageWindow(kind: .weekly, utilization: 20, resetsAt: .distantFuture)],
            planLabel: "plus",
            bankedResets: 2,
            capturedAt: capturedAt,
            freshness: .live
        )
        let merged = UsageContinuityPolicy.mergedSnapshot(
            .stale(for: .codex, reason: .transient("down")),
            with: prior,
            at: capturedAt.addingTimeInterval(60)
        )
        #expect(merged.bankedResets == 2)
        if case .stale = merged.freshness {} else { Issue.record("merged failure must be stale") }
    }

    @Test func liveCaptureReplacesBankedResets() {
        let prior = UsageSnapshot(
            providerID: .codex,
            windows: [UsageWindow(kind: .weekly, utilization: 20, resetsAt: .distantFuture)],
            planLabel: "plus",
            bankedResets: 2,
            capturedAt: Date(timeIntervalSince1970: 2_000_000),
            freshness: .live
        )
        let raised = UsageSnapshot(
            providerID: .codex,
            windows: prior.windows,
            planLabel: "plus",
            bankedResets: 3,
            capturedAt: Date(timeIntervalSince1970: 2_000_300),
            freshness: .live
        )
        let cleared = UsageSnapshot(
            providerID: .codex,
            windows: prior.windows,
            planLabel: "plus",
            bankedResets: nil,
            capturedAt: Date(timeIntervalSince1970: 2_000_300),
            freshness: .live
        )
        #expect(UsageContinuityPolicy.mergedSnapshot(raised, with: prior, at: raised.capturedAt!).bankedResets == 3)
        #expect(UsageContinuityPolicy.mergedSnapshot(cleared, with: prior, at: cleared.capturedAt!).bankedResets == nil)
    }

    @Test func diskRoundTripRestoresBankedResetsAsStale() {
        let defaults = freshDefaults()
        let key = AccountKey(providerID: .codex, accountID: .primary)
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)
        UsageContinuityCache(defaults: defaults).save(
            UsageSnapshot(
                providerID: .codex,
                windows: [UsageWindow(kind: .weekly, utilization: 20, resetsAt: .distantFuture)],
                planLabel: "plus",
                bankedResets: 2,
                capturedAt: capturedAt,
                freshness: .live
            ),
            for: key
        )
        let restored = UsageContinuityCache(defaults: defaults).load()[key]
        #expect(restored?.bankedResets == 2)
        #expect(restored?.planLabel == "plus")
        if case .stale(let reason) = restored?.freshness {
            #expect(reason.message.contains("Last known usage"))
        } else {
            Issue.record("restored count must ride a stale snapshot")
        }
    }

    @Test func versionTwoEnvelopeWithoutBankedResetsDecodesNil() throws {
        let defaults = freshDefaults()
        defaults.set(try envelope(bankedResets: nil, extra: ""), forKey: "usageContinuitySnapshots.v2")
        let key = AccountKey(providerID: .codex, accountID: .primary)
        let restored = try #require(UsageContinuityCache(defaults: defaults).load()[key])
        #expect(restored.bankedResets == nil)
        #expect(restored.planLabel == "plus")
    }

    @Test func versionTwoEnvelopeIgnoresUnknownKeys() throws {
        let defaults = freshDefaults()
        defaults.set(
            try envelope(bankedResets: 2, extra: #", "futurePerk": "keep""#),
            forKey: "usageContinuitySnapshots.v2"
        )
        let key = AccountKey(providerID: .codex, accountID: .primary)
        let restored = try #require(UsageContinuityCache(defaults: defaults).load()[key])
        #expect(restored.bankedResets == 2)
    }

    private func envelope(bankedResets: Int?, extra: String) throws -> Data {
        let deadline = Date().addingTimeInterval(86_400).timeIntervalSinceReferenceDate
        let captured = Date().timeIntervalSinceReferenceDate
        let count = bankedResets.map { #", "bankedResets": \#($0)"# } ?? ""
        let json = """
        {"schemaVersion":2,"records":[{
          "key":{"providerID":{"raw":"codex"},"accountID":{"raw":"primary"}},
          "windows":[{"kind":"weekly","utilization":10,"reset":{"kind":"scheduled","deadline":\(deadline)}}],
          "planLabel":"plus",
          "capturedAt":\(captured)\(count)\(extra)
        }]}
        """
        return Data(json.utf8)
    }

    @Test func aFailedCopilotPollHidesLastMonthsReadingInTheNewMonth() throws {
        let observedAt = try #require(DateParsing.iso8601("2026-10-31T23:00:00Z"))
        let monthEnd = try #require(DateParsing.iso8601("2026-11-01T00:00:00Z"))
        let prior = UsageSnapshot.live(.copilot, windows: [copilotOctoberWindow], at: observedAt)
        let failed = UsageSnapshot.stale(for: .copilot, reason: .transient("Couldn’t read Copilot status"))

        let sameMonth = UsageContinuityPolicy.mergedSnapshot(failed, with: prior, at: observedAt.addingTimeInterval(30 * 60))
        let nextMonth = UsageContinuityPolicy.mergedSnapshot(failed, with: prior, at: monthEnd.addingTimeInterval(30 * 60))

        #expect(sameMonth.windows.first?.freshness == .stale(observedAt: observedAt))
        #expect(nextMonth.windows.first?.freshness == .unavailable(since: monthEnd))
    }

    @Test func aCopilotLaunchRestoreHidesLastMonthsReadingInTheNewMonth() throws {
        let defaults = freshDefaults()
        let key = AccountKey(providerID: .copilot, accountID: .primary)
        let observedAt = try #require(DateParsing.iso8601("2026-10-31T23:00:00Z"))
        let monthEnd = try #require(DateParsing.iso8601("2026-11-01T00:00:00Z"))
        UsageContinuityCache(defaults: defaults).save(
            .live(.copilot, windows: [copilotOctoberWindow], at: observedAt),
            for: key
        )

        let restored = UsageContinuityPolicy.restoredSnapshot(
            UsageContinuityCache(defaults: defaults).load()[key],
            for: .copilot,
            at: monthEnd.addingTimeInterval(24 * 60 * 60)
        )

        let window = try #require(restored.windows.first)
        #expect(window.freshness == .unavailable(since: monthEnd))
        #expect(UsagePercentageMode.remaining.displayedPercentage(for: window) == nil)
    }

    private var copilotOctoberWindow: UsageWindow {
        UsageWindow(
            kind: .billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60),
            utilization: 40,
            resetSchedule: .unresolved(.absent)
        )
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.continuity-cache.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private struct LegacySnapshotFixture: Codable {
    let key: AccountKey
    let windows: [LegacyWindowFixture]
    let planLabel: String?
    let accountEmail: String?
    let capturedAt: Date?
}

private struct LegacyWindowFixture: Codable {
    let kind: String
    let otherLabel: String?
    let billingPeriodDuration: TimeInterval?
    let utilization: Double
    let resetsAt: Date
    let resetLabel: String?
    let staleObservedAt: Date?
    let unavailableSince: Date?
}
