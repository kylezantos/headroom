import Foundation
import Testing
@testable import HeadroomCore

/// U3: the Codex banked-reset notice and its per-account baseline (R14–R16, KTD7).
struct BankedResetNotificationTests {
    private let builtIn = AccountKey(providerID: .codex, accountID: .primary)
    private let work = AccountKey(providerID: .codex, accountID: AccountID("work"))
    private let now = Date(timeIntervalSince1970: 1_790_355_600)

    private func freshBaseline() -> BankedResetNotificationBaseline {
        let suite = "headroom.banked-notice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return BankedResetNotificationBaseline(defaults: defaults)
    }

    private func codex(_ count: Int?, freshness: Freshness = .live, provider: ProviderID = .codex) -> UsageSnapshot {
        UsageSnapshot(
            providerID: provider,
            windows: [UsageWindow(kind: .weekly, utilization: 40, resetsAt: now.addingTimeInterval(86_400))],
            planLabel: "plus",
            bankedResets: count,
            capturedAt: now,
            freshness: freshness
        )
    }

    /// What the U4 coordinator does: record immediately, or post and then record.
    @discardableResult
    private func observe(
        _ baseline: BankedResetNotificationBaseline,
        _ count: Int?,
        account: AccountKey? = nil,
        enabled: Bool = true,
        freshness: Freshness = .live,
        postSucceeds: Bool = true
    ) -> BankedResetProposal? {
        let key = account ?? builtIn
        switch baseline.decide(snapshot: codex(count, freshness: freshness), account: key, isEnabled: enabled) {
        case .ignore:
            return nil
        case .record(let count):
            baseline.record(count: count, for: key)
            return nil
        case .notify(let proposal):
            if postSucceeds { baseline.record(count: proposal.count, for: key) }
            return proposal
        }
    }

    @Test func ae5FirstCountSeedsSilentlyThenARiseNotifies() {
        let baseline = freshBaseline()
        #expect(observe(baseline, 1) == nil)
        #expect(baseline.baselineCount(for: builtIn) == 1)

        let proposal = observe(baseline, 2)
        #expect(proposal == BankedResetProposal(account: builtIn, count: 2, previousCount: 1))
        #expect(baseline.baselineCount(for: builtIn) == 2)

        #expect(observe(baseline, 2) == nil)
    }

    @Test func ae6RiseWhileOffRecordsSoTurningOnDoesNotReplayIt() {
        let baseline = freshBaseline()
        observe(baseline, 1, enabled: false)
        #expect(observe(baseline, 2, enabled: false) == nil)
        #expect(baseline.baselineCount(for: builtIn) == 2)

        #expect(observe(baseline, 2, enabled: true) == nil)
        #expect(observe(baseline, 3, enabled: true)?.count == 3)
    }

    @Test func aDropRecordsQuietlyAndTheNextRiseNotifies() {
        let baseline = freshBaseline()
        observe(baseline, 2)
        #expect(observe(baseline, 1) == nil)
        #expect(baseline.baselineCount(for: builtIn) == 1)
        #expect(observe(baseline, 2)?.count == 2)
    }

    @Test func aNilCountChangesNothing() {
        let baseline = freshBaseline()
        #expect(baseline.decide(snapshot: codex(nil), account: builtIn, isEnabled: true) == BankedResetNotificationDecision.ignore)
        #expect(baseline.baselineCount(for: builtIn) == nil)

        observe(baseline, 1)
        #expect(observe(baseline, nil) == nil)
        #expect(baseline.baselineCount(for: builtIn) == 1)
        #expect(observe(baseline, 1) == nil)
    }

    /// A key-present `null` is reported zero, so 0 then 1 is a real rise.
    @Test func nullAsZeroThenOneNotifies() {
        let baseline = freshBaseline()
        #expect(observe(baseline, 0) == nil)
        #expect(baseline.baselineCount(for: builtIn) == 0)
        #expect(observe(baseline, 1)?.count == 1)
    }

    @Test func staleSnapshotsWithARetainedCountChangeNothing() {
        let baseline = freshBaseline()
        observe(baseline, 1)
        #expect(observe(baseline, 3, freshness: .stale(.transient("offline"))) == nil)
        #expect(observe(baseline, 3, freshness: .pending) == nil)
        #expect(baseline.baselineCount(for: builtIn) == 1)
    }

    /// First-seen on a stale snapshot must not seed either: the count may be days old.
    @Test func staleSnapshotsDoNotSeed() {
        let baseline = freshBaseline()
        observe(baseline, 3, freshness: .stale(.transient("offline")))
        #expect(baseline.baselineCount(for: builtIn) == nil)
    }

    @Test func onlyCodexSnapshotsCount() {
        let baseline = freshBaseline()
        let claude = AccountKey(providerID: .claude, accountID: .primary)
        #expect(baseline.decide(snapshot: codex(2, provider: .claude), account: claude, isEnabled: true) == BankedResetNotificationDecision.ignore)
    }

    /// KTD6: a failed post records nothing, so the next fresh poll retries.
    @Test func aFailedPostLeavesTheBaselineForARetry() {
        let baseline = freshBaseline()
        observe(baseline, 1)
        #expect(observe(baseline, 2, postSucceeds: false)?.count == 2)
        #expect(baseline.baselineCount(for: builtIn) == 1)
        #expect(observe(baseline, 2)?.count == 2)
        #expect(observe(baseline, 2) == nil)
    }

    @Test func accountsHaveIndependentBaselines() {
        let baseline = freshBaseline()
        observe(baseline, 1, account: builtIn)
        #expect(observe(baseline, 2, account: work) == nil)
        #expect(baseline.baselineCount(for: work) == 2)
        #expect(baseline.baselineCount(for: builtIn) == 1)
    }

    @Test func purgeRemovesTheEntrySoTheNextCountSeedsSilently() {
        let baseline = freshBaseline()
        observe(baseline, 1, account: builtIn)
        observe(baseline, 1, account: work)
        baseline.purge(for: builtIn)
        #expect(baseline.baselineCount(for: builtIn) == nil)
        #expect(baseline.baselineCount(for: work) == 1)
        #expect(observe(baseline, 4, account: builtIn) == nil)
        #expect(baseline.baselineCount(for: builtIn) == 4)
    }

    /// KTD7: its own store, independent of the capsule's acknowledgement record.
    @Test func baselineIsSeparateFromCapsuleAcknowledgements() {
        let suite = "headroom.banked-notice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let baseline = BankedResetNotificationBaseline(defaults: defaults)
        let acknowledgements = BankedResetAcknowledgements(defaults: defaults)
        baseline.record(count: 3, for: builtIn)
        #expect(acknowledgements.acknowledgedCount(for: builtIn) == nil)
        #expect(acknowledgements.claimReveal(for: builtIn, currentCount: 5))
        #expect(baseline.baselineCount(for: builtIn) == 3)
        #expect(BankedResetNotificationBaseline(defaults: defaults).baselineCount(for: builtIn) == 3)
    }

    @Test func corruptBaselineReadsAsEmpty() {
        let suite = "headroom.banked-notice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(Data("nope".utf8), forKey: "bankedResetNotificationBaseline.v1")
        #expect(BankedResetNotificationBaseline(defaults: defaults).baselineCount(for: builtIn) == nil)
    }

    // MARK: - Copy (R16, KTD12)

    @Test func singleAccountCopy() {
        let one = NotificationContent.bankedReset(BankedResetProposal(account: builtIn, count: 1, previousCount: 0), accountLabel: nil)
        #expect(one.title == "Codex banked a reset")
        #expect(one.body == "You now have 1 banked reset.")
        #expect(one.identifier == "codex-banked.primary.1")
        #expect(one.threadIdentifier == "codex.primary")

        let two = NotificationContent.bankedReset(BankedResetProposal(account: builtIn, count: 2, previousCount: 1), accountLabel: nil)
        #expect(two.body == "You now have 2 banked resets.")
    }

    @Test func multiAccountCopyNamesTheAccount() {
        let banner = NotificationContent.bankedReset(BankedResetProposal(account: work, count: 2, previousCount: 1), accountLabel: "Work")
        #expect(banner.title == "Codex banked a reset")
        #expect(banner.body == "Work now has 2 banked resets.")
        #expect(banner.identifier == "codex-banked.work.2")
        #expect(banner.threadIdentifier == "codex.work")

        let single = NotificationContent.bankedReset(BankedResetProposal(account: work, count: 1, previousCount: 0), accountLabel: "Work")
        #expect(single.body == "Work now has 1 banked reset.")
    }
}
