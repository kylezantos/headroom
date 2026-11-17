import Foundation
import Testing
@testable import HeadroomCore

// A capture becomes an honest snapshot: four labelled rows from the source's buckets, the
// credits badge only above zero, and every failure a stale snapshot with its setup reason.
// Every source here is a fixed double.

private actor FixedAntigravitySource: AntigravityUsageSource {
    private var captures: [AntigravityCapture]
    private(set) var calls = 0

    init(_ captures: [AntigravityCapture]) { self.captures = captures }

    func capture() async -> AntigravityCapture {
        calls += 1
        return captures.count > 1 ? captures.removeFirst() : captures[0]
    }
}

struct AntigravityProviderTests {
    /// Mon 16 Nov 2026 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_795_348_800)
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400
    private let enUS = Locale(identifier: "en_US")

    private func bucket(
        _ pool: AntigravityPool, _ window: AntigravityWindow, remaining: Double, resetIn: TimeInterval?
    ) -> AntigravityBucket {
        AntigravityBucket(
            pool: pool, window: window, remainingFraction: remaining,
            resetsAt: resetIn.map { now.addingTimeInterval($0) }
        )
    }

    /// The live capture's values in its order: Gemini weekly, Gemini 5h, 3p weekly, 3p 5h.
    private var liveBuckets: [AntigravityBucket] {
        [
            bucket(.gemini, .weekly, remaining: 0.9946, resetIn: 7 * day),
            bucket(.gemini, .fiveHour, remaining: 0.9894, resetIn: 5 * hour),
            bucket(.claudeAndGPT, .weekly, remaining: 1, resetIn: 7 * day + 600),
            bucket(.claudeAndGPT, .fiveHour, remaining: 1, resetIn: 5 * hour + 600),
        ]
    }

    private func fetch(_ capture: AntigravityCapture, locale: Locale? = nil) async -> UsageSnapshot {
        let clock = now
        return await AntigravityProvider(
            source: FixedAntigravitySource([capture]), locale: locale ?? enUS, now: { clock }
        ).fetchSnapshot()
    }

    private func labels(_ snapshot: UsageSnapshot) -> [String] {
        snapshot.windows.map(\.kind.shortLabel)
    }

    private func window(_ snapshot: UsageSnapshot, _ label: String) -> UsageWindow? {
        snapshot.windows.first { $0.kind == .other(label) }
    }

    // MARK: - Rows

    @Test func fourBucketsBecomeFourLabelledOtherRowsWithTheirResets() async throws {
        let snapshot = await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: 0)))
        #expect(snapshot.providerID == .antigravity)
        #expect(snapshot.freshness == .live)
        #expect(snapshot.capturedAt == now)
        #expect(Set(labels(snapshot)) == ["Gemini 5h", "Gemini weekly", "Other 5h", "Other weekly"])
        let gemini5h = try #require(window(snapshot, "Gemini 5h"))
        let geminiWeekly = try #require(window(snapshot, "Gemini weekly"))
        let other5h = try #require(window(snapshot, "Other 5h"))
        let otherWeekly = try #require(window(snapshot, "Other weekly"))
        #expect(abs(gemini5h.utilization - 1.06) < 0.0001)
        #expect(abs(geminiWeekly.utilization - 0.54) < 0.0001)
        #expect(other5h.utilization == 0)
        #expect(otherWeekly.utilization == 0)
        #expect(gemini5h.resetSchedule == .scheduled(now.addingTimeInterval(5 * hour)))
        #expect(geminiWeekly.resetSchedule == .scheduled(now.addingTimeInterval(7 * day)))
        #expect(other5h.resetSchedule == .scheduled(now.addingTimeInterval(5 * hour + 600)))
        #expect(otherWeekly.resetSchedule == .scheduled(now.addingTimeInterval(7 * day + 600)))
    }

    /// These labels are stored window IDs, so they are pinned exactly.
    @Test func theRowLabelsAreStablePersistentIDs() async {
        let snapshot = await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: nil)))
        #expect(Set(snapshot.windows.map(\.kind.persistentID)) == [
            "other:Gemini 5h", "other:Gemini weekly", "other:Other 5h", "other:Other weekly",
        ])
        #expect(AntigravityProvider.windowKind(.gemini, .fiveHour) == .other("Gemini 5h"))
        #expect(AntigravityProvider.windowKind(.gemini, .weekly) == .other("Gemini weekly"))
        #expect(AntigravityProvider.windowKind(.claudeAndGPT, .fiveHour) == .other("Other 5h"))
        #expect(AntigravityProvider.windowKind(.claudeAndGPT, .weekly) == .other("Other weekly"))
    }

    @Test func eachPoolLeadsWithItsLowerRemainingRow() async {
        let live = await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: nil)))
        // Gemini's 5h has less left than its weekly; the tied pool keeps the source's order.
        #expect(labels(live) == ["Gemini 5h", "Gemini weekly", "Other weekly", "Other 5h"])

        let flipped = await fetch(.usage(AntigravityUsage(buckets: [
            bucket(.claudeAndGPT, .fiveHour, remaining: 0.7, resetIn: hour),
            bucket(.claudeAndGPT, .weekly, remaining: 0.2, resetIn: day),
            bucket(.gemini, .fiveHour, remaining: 0.9, resetIn: hour),
            bucket(.gemini, .weekly, remaining: 0.4, resetIn: day),
        ], credits: nil)))
        #expect(labels(flipped) == ["Other weekly", "Other 5h", "Gemini weekly", "Gemini 5h"])
    }

    @Test func utilizationIsUsedPercentClampedToTheMeter() async throws {
        let snapshot = await fetch(.usage(AntigravityUsage(buckets: [
            bucket(.gemini, .fiveHour, remaining: 0, resetIn: hour),
            bucket(.gemini, .weekly, remaining: 0.25, resetIn: day),
        ], credits: nil)))
        #expect(try #require(window(snapshot, "Gemini 5h")).utilization == 100)
        #expect(try #require(window(snapshot, "Gemini weekly")).utilization == 75)
    }

    @Test func anOmittedBucketIsAbsentNotZeroOrFull() async {
        let snapshot = await fetch(.usage(AntigravityUsage(buckets: Array(liveBuckets.prefix(3)), credits: nil)))
        #expect(snapshot.windows.count == 3)
        #expect(window(snapshot, "Other 5h") == nil)
    }

    @Test func aMissingResetIsNeverInvented() async throws {
        let snapshot = await fetch(.usage(AntigravityUsage(buckets: [
            bucket(.gemini, .fiveHour, remaining: 0.5, resetIn: nil),
        ], credits: nil)))
        let row = try #require(window(snapshot, "Gemini 5h"))
        #expect(row.resetSchedule == .unresolved(.absent))
    }

    // MARK: - Credits badge

    @Test func creditsAboveZeroAreALocaleFormattedBalanceBadge() async {
        #expect(await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: 1200))).planLabel == "1,200 credits")
        #expect(await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: 1))).planLabel == "1 credit")
        #expect(await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: 12.5))).planLabel == "12.5 credits")
        let german = await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: 1200)), locale: Locale(identifier: "de_DE"))
        #expect(german.planLabel == "1.200 credits")
    }

    @Test func zeroOrUnavailableCreditsShowNoBadge() async {
        #expect(await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: 0))).planLabel == nil)
        #expect(await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: nil))).planLabel == nil)
    }

    // MARK: - Failures

    @Test func everyFailureIsTheMatchingStaleSnapshot() async {
        let cases: [(AntigravityCaptureFailure, ProviderSetupOutcome)] = [
            (.cliMissing, .antigravityCLIMissing),
            (.updateRequired, .antigravityUpdateRequired),
            (.unsupportedClient, .antigravityUnsupportedClient),
            (.signedOut, .antigravitySignedOut),
            (.formatChanged(.usageData), .antigravityFormatChanged),
            (.transient(.deadline), .antigravityTransientCapture),
            (.transient(.authenticationFailed), .antigravityTransientCapture),
        ]
        for (failure, outcome) in cases {
            #expect(failure.outcome == outcome, "\(failure)")
            let snapshot = await fetch(.failed(failure))
            #expect(snapshot.providerID == .antigravity)
            #expect(snapshot.freshness == .stale(.providerSetup(outcome)), "\(failure)")
            #expect(snapshot.windows.isEmpty)
            #expect(snapshot.planLabel == nil)
        }
    }

    /// A timeout, unknown output or a sign-in wait that ended without the prompt is never
    /// reported as signed out or missing.
    @Test func onlyPositiveEvidenceIsPermanent() {
        #expect(!AntigravityCaptureFailure.transient(.authenticationFailed).failureReason.isPermanent)
        #expect(!AntigravityCaptureFailure.transient(.deadline).failureReason.isPermanent)
        #expect(!AntigravityCaptureFailure.formatChanged(.output).failureReason.isPermanent)
        #expect(AntigravityCaptureFailure.signedOut.failureReason.isPermanent)
        #expect(AntigravityCaptureFailure.cliMissing.failureReason.isPermanent)
        #expect(AntigravityCaptureFailure.updateRequired.failureReason.isPermanent)
        #expect(AntigravityCaptureFailure.unsupportedClient.failureReason.isPermanent)
    }

    @Test func aTransientFailureKeepsTheLastReadingDimmed() async throws {
        let live = await fetch(.usage(AntigravityUsage(buckets: liveBuckets, credits: 1200)))
        let failed = await fetch(.failed(.transient(.deadline)))
        let merged = UsageContinuityPolicy.mergedSnapshot(failed, with: live, at: now.addingTimeInterval(600))
        #expect(merged.freshness == failed.freshness)
        #expect(merged.windows.count == 4)
        #expect(merged.windows.allSatisfy { $0.freshness == .stale(observedAt: now) })
        #expect(merged.planLabel == "1,200 credits")
    }

    @Test func recoveryActionsFollowTheOutcome() {
        #expect(ProviderSetupOutcome.antigravitySignedOut.recoveryPresentation.primaryAction == .connectAntigravity)
        #expect(ProviderSetupOutcome.antigravitySignedOut.recoveryPresentation.primaryLabel == ProviderSignInCopy.button)
        #expect(ProviderSetupOutcome.antigravitySignedOut.isNeverSignedIn)
        #expect(ProviderSetupOutcome.antigravitySignedOut.message == "Sign in with the official Antigravity CLI")
        #expect(ProviderSetupOutcome.antigravityCLIMissing.message == "Antigravity CLI isn’t installed on this Mac")
        #expect(ProviderSetupOutcome.antigravityCLIMissing.recoveryPresentation.primaryAction == .installAntigravityCLI)
        #expect(ProviderSetupOutcome.antigravityUpdateRequired.recoveryPresentation.primaryAction == .installAntigravityCLI)
        #expect(ProviderSetupOutcome.antigravityUnsupportedClient.recoveryPresentation.primaryAction == .contactSupport)
        #expect(ProviderSetupOutcome.antigravityFormatChanged.recoveryPresentation.primaryAction == .contactSupport)
        #expect(ProviderSetupOutcome.antigravityTransientCapture.recoveryPresentation.primaryAction == .checkNow)
        #expect(CompanionAttentionMapping.attention(for: .antigravitySignedOut) == .signInRequired)
        #expect(CompanionAttentionMapping.attention(for: .antigravityCLIMissing) == .cliMissing)
        #expect(CompanionAttentionMapping.attention(for: .antigravityUpdateRequired) == .cliUpdateRequired)
        #expect(CompanionAttentionMapping.attention(for: .antigravityTransientCapture) == .retrying)
    }

    /// A check while the Terminal sign-in is open would run a signed-out read, which opens
    /// another browser sign-in, so the handoff waits for the sign-in to exit.
    @Test func theSignInHandoffCompletesOnExitWithNoChecksWhileOpen() {
        for purpose in [SetupHandoffPurpose.setup, .reset] {
            #expect(SetupWaitingPolicy.staged(providerID: .antigravity, purpose: purpose, claudeScriptKind: nil) == .exitSignalled)
            #expect(SetupWaitingPolicy.restored(providerID: .antigravity, purpose: purpose) == .exitSignalled)
        }
    }

    // MARK: - Identity and lane

    @Test func identityLaneAndCapacity() async {
        let source = FixedAntigravitySource([.usage(AntigravityUsage(buckets: liveBuckets, credits: nil))])
        let provider = AntigravityProvider(source: source)
        #expect(provider.id == .antigravity)
        #expect(provider.displayName == "Antigravity")
        #expect(ProviderID.antigravity.raw == "antigravity")
        #expect(provider.accountKey == AccountKey(providerID: .antigravity, accountID: .primary))
        #expect(provider.pollingLane == .serial("antigravity-cli"))
        #expect(provider.accountCapacity == 1)
        _ = await provider.fetchSnapshot()
        #expect(await source.calls == 1)
    }
}
