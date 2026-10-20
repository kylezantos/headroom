import Foundation
import Testing
@testable import HeadroomCore

@MainActor
struct SessionReliabilityRecordTests {
    private let claude = AccountKey(providerID: .claude, accountID: .primary)
    private let codex = AccountKey(providerID: .codex, accountID: .primary)

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "headroom.session-reliability.tests.\(UUID().uuidString)")!
    }

    private func live(_ provider: ProviderID) -> UsageSnapshot {
        .live(provider, windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: Date().addingTimeInterval(3600))])
    }

    @Test func rejectedAuthIsNotAConfirmedSignOutAndEdgesPersistAcrossRestart() {
        let preferences = defaults()
        let record = SessionReliabilityRecord(defaults: preferences)
        record.note(live(.claude), for: claude, expectedInterval: 300)
        record.note(live(.codex), for: codex, expectedInterval: 300)
        let restarted = SessionReliabilityRecord(defaults: preferences)
        restarted.note(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)), for: claude, expectedInterval: 300)
        restarted.note(.stale(for: .codex, reason: .providerSetup(.codexRejectedAuth)), for: codex, expectedInterval: 300)
        restarted.note(.stale(for: .codex, reason: .providerSetup(.codexRejectedAuth)), for: codex, expectedInterval: 300)

        #expect(restarted.days.first { $0.provider == .claude }?.signOutTransitions == 1)
        #expect(restarted.days.first { $0.provider == .codex }?.signOutTransitions == 0)
        #expect(restarted.days.first { $0.provider == .codex }?.rejectedAuthTransitions == 1)
    }

    @Test func unverifiedCodex401CountsRejectedRequestsWithoutClaimingASignOut() {
        let record = SessionReliabilityRecord(defaults: defaults())
        record.note(live(.codex), for: codex, expectedInterval: 300)
        for _ in 0..<3 {
            record.note(.stale(for: .codex, reason: .providerSetup(.codexSessionUnverified)),
                        for: codex, expectedInterval: 300)
        }
        #expect(record.days.first?.rejectedAuthTransitions == 1)
        #expect(record.days.first?.signOutTransitions == 0)
        record.note(live(.codex), for: codex, expectedInterval: 300)
        record.note(.stale(for: .codex, reason: .providerSetup(.codexSessionUnverified)),
                    for: codex, expectedInterval: 300)
        #expect(record.days.first?.rejectedAuthTransitions == 2)
    }

    @Test func coverageSplitsAtUTCMidnightAndDoesNotCountDowntimeOrFirstSamples() {
        let midnight = Date(timeIntervalSince1970: 1_728_000_000) // UTC midnight
        let clock = MutableDateSource(midnight.addingTimeInterval(-100))
        let record = SessionReliabilityRecord(defaults: defaults(), now: clock.now)
        record.note(live(.claude), for: claude, expectedInterval: 300)
        #expect(record.days.reduce(0) { $0 + $1.sampledAccountSeconds } == 0)
        clock.set(midnight.addingTimeInterval(200))
        record.note(live(.claude), for: claude, expectedInterval: 300)
        #expect(record.days.map(\.sampledAccountSeconds) == [100, 200])
        clock.set(midnight.addingTimeInterval(4000))
        record.note(live(.claude), for: claude, expectedInterval: 300)
        #expect(record.days.reduce(0) { $0 + $1.sampledAccountSeconds } == 300)
    }

    @Test func intentionalResetAndRemovalDoNotCreateSignOutTransitionsOrCoverage() {
        let clock = MutableDateSource(Date(timeIntervalSince1970: 1_728_000_000))
        let record = SessionReliabilityRecord(defaults: defaults(), now: clock.now)
        record.note(live(.claude), for: claude, expectedInterval: 300)
        record.endObservation(for: claude)
        clock.set(clock.now().addingTimeInterval(300))
        record.note(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)), for: claude, expectedInterval: 300)
        #expect(record.days.first?.signOutTransitions == 0)
        #expect(record.days.first?.sampledAccountSeconds == 0)
    }

    @Test func transientFailuresNeverCreateAuthEventsAndDiagnosticOutputOmitsIdentity() {
        let preferences = defaults()
        let record = SessionReliabilityRecord(defaults: preferences)
        let extra = AccountKey(providerID: .claude, accountID: AccountID("local-extra-id"))
        record.note(live(.claude), for: extra, expectedInterval: 300)
        record.note(.stale(for: .claude, reason: .transient("secret-sentinel@example.invalid")), for: extra, expectedInterval: 300)
        let text = record.diagnosticLines().joined(separator: "\n")
        let stored = preferences.dictionaryRepresentation().values.compactMap { $0 as? Data }
            .map { String(decoding: $0, as: UTF8.self) }.joined()
        #expect(record.days.first?.signOutTransitions == 0)
        #expect(record.days.first?.observedAccounts == 1)
        #expect(!text.contains("local-extra-id"))
        #expect(!text.contains("secret-sentinel"))
        #expect(!stored.contains("secret-sentinel"))
        #expect(!stored.contains("utilization"))
    }

    @Test func retentionIsBoundedAndClockReversalAddsNoCoverage() {
        let clock = MutableDateSource(Date(timeIntervalSince1970: 1_728_000_000))
        let record = SessionReliabilityRecord(defaults: defaults(), now: clock.now)
        for _ in 0..<30 {
            record.note(live(.claude), for: claude, expectedInterval: 300)
            clock.set(clock.now().addingTimeInterval(86_400))
        }
        #expect(record.days.count <= SessionReliabilityRecord.retentionDays)
        #expect(record.days.allSatisfy { $0.sampledAccountSeconds == 0 })
        clock.set(clock.now().addingTimeInterval(-86_500))
        record.note(live(.claude), for: claude, expectedInterval: 300)
        #expect(record.days.allSatisfy { $0.sampledAccountSeconds == 0 })
    }

    @Test func observedAccountsDoNotStandInForTheTrackedCatalogSize() {
        let record = SessionReliabilityRecord(defaults: defaults())
        let extras = (0..<3).map { AccountKey(providerID: .codex, accountID: AccountID("extra-\($0)")) }
        record.note(live(.codex), for: extras[0], expectedInterval: 300, trackedAccounts: extras + [codex, claude])
        #expect(record.days.first?.observedAccounts == 1)
        #expect(record.days.first?.peakTrackedAccounts == 3)
        record.note(live(.codex), for: extras[1], expectedInterval: 300, trackedAccounts: [extras[1]])
        #expect(record.days.first?.observedAccounts == 2)
        #expect(record.days.first?.peakTrackedAccounts == 3)
    }

    @Test func acceptedStoreResultsReachTheCollectorAndResetClearsTheEdge() async {
        let preferences = Preferences(defaults: defaults())
        let record = SessionReliabilityRecord(defaults: defaults())
        let source = MutableStubProvider(id: .claude, displayName: "Claude", snapshot: live(.claude))
        let store = UsageStore(providers: [source], preferences: preferences, sessionReliabilityRecord: record)
        await store.refreshAll()
        source.set(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)))
        await store.refreshAll()
        #expect(record.days.first?.signOutTransitions == 1)
        source.set(live(.claude))
        await store.refreshAll()
        let oldGeneration = store.schedulerAttachmentGeneration(for: claude)
        store.invalidateUsageForAccountReset(claude)
        let beforeLateResult = record.days
        let accepted = store.schedulerMerge(
            key: claude,
            result: UsageProviderFetchResult(snapshot: .stale(
                for: .claude, reason: .providerSetup(.claudeLoginRequired)
            )),
            attachmentGeneration: oldGeneration
        )
        #expect(!accepted)
        #expect(record.days == beforeLateResult)
        source.set(.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)))
        await store.refreshAll()
        #expect(record.days.first?.signOutTransitions == 1)
        #expect(record.days.first?.observations == 4)
    }
}
