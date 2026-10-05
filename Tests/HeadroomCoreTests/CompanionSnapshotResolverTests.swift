import Foundation
import Testing

@testable import HeadroomCore

/// KTD6 rules 1–8 and contract Decisions 1–4, exercised through the pure resolver.
@Suite
struct CompanionSnapshotResolverTests {
    typealias F = CompanionFixtures
    private let now = F.date(60).date

    private func resolve(
        manifest: CompanionManifest?, keys: [String: Data] = [:], v3: SyncedWidgetSnapshotEnvelope? = nil,
        cache: CompanionCacheContents = .empty, at now: Date? = nil
    ) -> CompanionResolution {
        CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: manifest.map(F.bytes), providerKeys: keys, v3: v3.map(F.v3Bytes),
                cache: cache, now: now ?? self.now))
    }

    private func content(_ resolution: CompanionResolution) throws -> CompanionResolvedContent {
        try #require(resolution.snapshot.content)
    }

    private func provider(_ resolution: CompanionResolution, _ id: String) throws -> CompanionResolvedProvider {
        try #require(try content(resolution).providers.first { $0.id == id })
    }

    // MARK: Happy path and lineage (rules 2–4)

    @Test func equalGenerationKeyWithMatchingDigestResolvesEveryAccount() throws {
        let claude = F.bytes(F.payload(generation: 4, extras: [F.account("x1", title: "Work")]))
        let manifest = F.manifest(generation: 9, entries: ["claude": F.entry(claude, generation: 4)])
        let resolution = resolve(manifest: manifest, keys: ["claude": claude])
        let content = try content(resolution)
        #expect(content.origin == .v4 && content.notice == nil && content.sourceID == F.macA)
        let provider = try provider(resolution, "claude")
        #expect(provider.source == .v4(.manifestDigestMatched) && provider.lag == .current)
        #expect(provider.accounts.map(\.title) == ["Personal", "Work"])
        #expect(provider.mainAccount?.isMain == true && provider.extraAccounts.first?.isMain == false)
        #expect(resolution.cache.providers["claude"]?.evidence == .manifestDigestMatched)
        #expect(resolution.cache.manifest?.generation == 9)
        #expect(content.freshness == CompanionFreshnessInputs(
            generatedAt: F.date().date, firstSeen: now, largestEffectiveIntervalSeconds: 300,
            isV3Only: false))
    }

    /// V4: manifest 12 with Claude key 11 keeps Claude's last complete copy, never mixing.
    @Test func laggingKeyShowsItsCompleteCopyThenTurnsLastKnownAfterGrace() throws {
        let old = F.bytes(F.payload(generation: 11, extras: [F.account("x1", title: "Work")]))
        let expected = F.bytes(F.payload(generation: 12, extras: [F.account("x2", title: "Studio")]))
        let manifest = F.manifest(generation: 12, entries: ["claude": F.entry(expected, generation: 12)])
        let first = resolve(manifest: manifest, keys: ["claude": old])
        let lagging = try provider(first, "claude")
        #expect(lagging.accounts.map(\.accountID) == ["primary", "x1"])
        #expect(lagging.lag == .lagging(since: now) && lagging.source == .v4(.structural))
        #expect(first.cache.providers["claude"]?.evidence == .structural)

        // Grace is max(120 s, the 300 s heartbeat); first-seen is shared, never restarted.
        let later = resolve(manifest: manifest, keys: ["claude": old], cache: first.cache, at: now + 299)
        #expect(try provider(later, "claude").lag == .lagging(since: now))
        let expired = resolve(manifest: manifest, keys: ["claude": old], cache: later.cache, at: now + 300)
        #expect(try provider(expired, "claude").lag == .lastKnown(since: now))
        #expect(try provider(expired, "claude").lag.showsLastKnown)

        // The key catches up: verified, current, and the lag first-seen is pruned.
        let caught = resolve(manifest: manifest, keys: ["claude": expected], cache: expired.cache, at: now + 400)
        #expect(try provider(caught, "claude").lag == .current)
        #expect(try provider(caught, "claude").accounts.map(\.accountID) == ["primary", "x2"])
        #expect(!caught.cache.firstSeen.keys.contains { $0.hasPrefix("lag|") })
    }

    @Test func heartbeatsThatKeepTheExpectedGenerationDoNotRestartLagGrace() throws {
        let old = F.bytes(F.payload(generation: 3))
        let expected = F.bytes(F.payload(generation: 4, extras: [F.account("x1")]))
        var cache = CompanionCacheContents.empty
        var lags: [CompanionProviderLag] = []
        for (step, generation) in (20...24).enumerated() {
            let manifest = F.manifest(
                generation: Int64(generation), generatedAt: Int64(step * 60),
                entries: ["claude": F.entry(expected, generation: 4)])
            let resolution = resolve(manifest: manifest, keys: ["claude": old], cache: cache, at: now + Double(step * 100))
            cache = resolution.cache
            lags.append(try provider(resolution, "claude").lag)
        }
        #expect(lags.prefix(3).allSatisfy { $0 == .lagging(since: now) })
        #expect(lags.suffix(2).allSatisfy { $0 == .lastKnown(since: now) })
    }

    @Test func unchangedKeyStaysVerifiedAcrossFiveManifestGenerations() throws {
        let claude = F.bytes(F.payload(generation: 3))
        var cache = CompanionCacheContents.empty
        for generation in 3...7 {
            let manifest = F.manifest(
                generation: Int64(generation), generatedAt: Int64(generation * 300),
                entries: ["claude": F.entry(claude, generation: 3)])
            let resolution = resolve(manifest: manifest, keys: ["claude": claude], cache: cache)
            cache = resolution.cache
            let provider = try provider(resolution, "claude")
            #expect(provider.lag == .current && provider.source == .v4(.manifestDigestMatched))
            #expect(try content(resolution).generation == Int64(generation))
        }
    }

    @Test func aheadKeyIsStructuralUntilTheManifestCatchesUpAndThenExactlyVerified() throws {
        let ahead = F.bytes(F.payload(generation: 13))
        let current = F.bytes(F.payload(generation: 12))
        let m12 = F.manifest(generation: 12, entries: ["claude": F.entry(current, generation: 12)])
        let first = resolve(manifest: m12, keys: ["claude": ahead])
        #expect(try provider(first, "claude").source == .v4(.structural))
        #expect(try provider(first, "claude").lag == .current)
        let m13 = F.manifest(generation: 13, entries: ["claude": F.entry(ahead, generation: 13)])
        // The key read is now missing; the cached ahead bytes verify against the new manifest.
        let caught = resolve(manifest: m13, cache: first.cache)
        #expect(try provider(caught, "claude").source == .v4(.manifestDigestMatched))
        #expect(caught.cache.providers["claude"]?.evidence == .manifestDigestMatched)
    }

    @Test func equalGenerationDigestMismatchRejectsAndFallsBackWithoutMixing() throws {
        let published = F.bytes(F.payload(generation: 5))
        let tampered = F.bytes(F.payload(generation: 5, extras: [F.account("x9", title: "Intruder")]))
        let manifest = F.manifest(generation: 5, entries: ["claude": F.entry(published, generation: 5)])
        let rejected = resolve(manifest: manifest, keys: ["claude": tampered])
        #expect(try provider(rejected, "claude").source == .skeleton)
        #expect(rejected.snapshot.diagnostics.contains(.providerDigestMismatch("claude")))
        // With that Mac's v3 mirror present, the provider shows its v3 main account instead.
        let mirror = F.v3(lineage: (F.macA, 5))
        let fallback = resolve(manifest: manifest, keys: ["claude": tampered], v3: mirror)
        let lifted = try provider(fallback, "claude")
        #expect(lifted.source == .v3Main && lifted.accounts.count == 1)
        #expect(lifted.mainAccount?.accountID == nil)
    }

    @Test func sameGenerationMutationCannotReplacePreviouslyVerifiedBytes() throws {
        let original = F.bytes(F.payload(generation: 5))
        let manifest = F.manifest(generation: 5, entries: ["claude": F.entry(original, generation: 5)])
        let first = resolve(manifest: manifest, keys: ["claude": original])
        let mutated = F.bytes(F.payload(generation: 5, extras: [F.account("x1")]))
        // Even a manifest rewritten for the mutated bytes cannot displace the verified copy.
        let rewritten = F.manifest(generation: 6, entries: ["claude": F.entry(mutated, generation: 5)])
        let second = resolve(manifest: rewritten, keys: ["claude": mutated], cache: first.cache)
        #expect(try provider(second, "claude").accounts.count == 1)
        #expect(second.cache.providers["claude"]?.raw == original)
        #expect(second.snapshot.diagnostics.contains(.providerImmutableGenerationViolation("claude")))
    }

    @Test func higherCachedCopyWinsOverALowerRemoteRead() throws {
        let newer = F.bytes(F.payload(generation: 8, extras: [F.account("x1")]))
        let older = F.bytes(F.payload(generation: 7))
        let manifest = F.manifest(generation: 8, entries: ["claude": F.entry(newer, generation: 8)])
        let first = resolve(manifest: manifest, keys: ["claude": newer])
        let reread = resolve(manifest: manifest, keys: ["claude": older], cache: first.cache)
        #expect(try provider(reread, "claude").payloadGeneration == 8)
        #expect(try provider(reread, "claude").accounts.count == 2)
    }

    @Test func unknownRawFieldsSurviveDigestVerification() throws {
        var json = try #require(
            JSONSerialization.jsonObject(with: F.bytes(F.payload(generation: 2))) as? [String: Any])
        json["futureBlock"] = ["kept": true]
        let raw = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        let manifest = F.manifest(generation: 2, entries: ["claude": F.entry(raw, generation: 2)])
        let resolution = resolve(manifest: manifest, keys: ["claude": raw])
        #expect(try provider(resolution, "claude").source == .v4(.manifestDigestMatched))
        #expect(resolution.cache.providers["claude"]?.raw == raw)
    }

    // MARK: Missing, foreign and malformed keys (rules 3, 6; KTD12)

    @Test func missingKeyIsSkeletonAbsentProviderIgnoredAndSpendOnlyHasNoCard() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let codex = F.bytes(F.payload("codex", generation: 1))
        let spend = try CompanionSpendSummary(
            id: "grok", displayName: "xAI", amount: 4, currency: "USD", capturedAt: F.date())
        let grokSpend = F.bytes(F.payload("grok", generation: 1, spend: spend, mode: .spendOnly))
        let cursor = F.bytes(F.payload("cursor", generation: 1))
        let manifest = F.manifest(
            order: ["claude", "codex", "grok"],
            entries: [
                "claude": F.entry(claude, generation: 1), "codex": F.entry(codex, generation: 1),
                "grok": F.entry(grokSpend, generation: 1),
            ],
            spendOrder: ["grok"])
        // Cursor's key exists in KVS but the manifest never names it.
        let resolution = resolve(
            manifest: manifest, keys: ["claude": claude, "grok": grokSpend, "cursor": cursor])
        let content = try content(resolution)
        #expect(content.providers.map(\.id) == ["claude", "codex"])
        #expect(try provider(resolution, "codex").source == .skeleton)
        #expect(content.apiSpend.map(\.id) == ["grok"])
        #expect(resolution.cache.providers.keys.sorted() == ["claude", "grok"])
        let projection = try #require(resolution.snapshot.primaryProjection())
        #expect(projection.providers.map(\.id) == ["claude", "codex"])
        #expect(projection.providers[1].freshness == .pending && projection.providers[1].windows.isEmpty)
    }

    @Test func keysFromAnotherMacAreNeverAssembled() throws {
        let foreign = F.bytes(F.payload(source: F.macB, generation: 1, extras: [F.account("b1")]))
        let manifest = F.manifest(entries: ["claude": F.entry(foreign, generation: 1)])
        let resolution = resolve(manifest: manifest, keys: ["claude": foreign])
        #expect(try provider(resolution, "claude").source == .skeleton)
        #expect(resolution.snapshot.diagnostics.contains(.providerForeignSource("claude")))
        #expect(resolution.cache.providers.isEmpty)
    }

    @Test func oneMalformedProviderIsIsolated() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let manifest = F.manifest(
            order: ["claude", "codex", "grok"],
            entries: [
                "claude": F.entry(claude, generation: 1),
                "codex": F.entry(Data("{".utf8), generation: 1),
                "grok": F.entry(Data(), generation: 1),
            ])
        var future = try #require(
            JSONSerialization.jsonObject(with: F.bytes(F.payload("grok", generation: 1))) as? [String: Any])
        future["r"] = 2
        let resolution = resolve(
            manifest: manifest,
            keys: ["claude": claude, "codex": Data("{".utf8),
                   "grok": try JSONSerialization.data(withJSONObject: future)])
        #expect(try provider(resolution, "claude").source == .v4(.manifestDigestMatched))
        #expect(try provider(resolution, "codex").source == .skeleton)
        #expect(try provider(resolution, "grok").source == .skeleton)
        #expect(resolution.snapshot.diagnostics.contains(.providerUnreadable("codex")))
        #expect(resolution.snapshot.diagnostics.contains(.providerNeedsNewerReader("grok")))
    }

    // MARK: v3 versus v4 (rules 5–7)

    /// V3: a manifest older than a lineage-less v3 picks v3; a newer manifest returns to v4.
    @Test func lineagelessV3NewerThanManifestWinsWithTheUpdateMacLine() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let manifest = F.manifest(generatedAt: 0, entries: ["claude": F.entry(claude, generation: 1)])
        let downgraded = F.v3(generatedAt: 30)
        let first = resolve(manifest: manifest, keys: ["claude": claude], v3: downgraded)
        let firstContent = try content(first)
        #expect(firstContent.origin == .v3 && firstContent.notice == .updateMac)
        #expect(CompanionCompatibilityNotice.updateMac.message
            == "Update Headroom on your Mac to see every account")
        let newer = F.manifest(generation: 2, generatedAt: 45, entries: ["claude": F.entry(claude, generation: 1)])
        let back = resolve(manifest: newer, keys: ["claude": claude], v3: downgraded, cache: first.cache)
        let backContent = try content(back)
        #expect(backContent.origin == .v4 && backContent.notice == nil)
        // A tie goes to v4.
        let tie = F.manifest(generation: 3, generatedAt: 30, entries: ["claude": F.entry(claude, generation: 1)])
        #expect(try content(resolve(manifest: tie, keys: ["claude": claude], v3: downgraded)).origin == .v4)
    }

    @Test func sameLineageMirrorNeverWinsUnlessTheV4ChannelLooksStuck() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let manifest = F.manifest(generation: 10, entries: ["claude": F.entry(claude, generation: 1)])
        let seconds = resolve(manifest: manifest, keys: ["claude": claude], v3: F.v3(generatedAt: 5, lineage: (F.macA, 11)))
        #expect(try content(seconds).origin == .v4)
        // Ahead by more than max(15 min, 2 × 300 s) = 15 min.
        let stuck = resolve(manifest: manifest, keys: ["claude": claude], v3: F.v3(generatedAt: 901, lineage: (F.macA, 40)))
        let stuckContent = try content(stuck)
        #expect(stuckContent.origin == .v3 && stuckContent.notice == nil)
        #expect(stuck.snapshot.diagnostics.contains(.v4ChannelStuck))
        let edge = resolve(manifest: manifest, keys: ["claude": claude], v3: F.v3(generatedAt: 900, lineage: (F.macA, 40)))
        #expect(try content(edge).origin == .v4)
    }

    @Test func mirrorAloneShowsMainAccountsWithoutTheUpdateLine() throws {
        let resolution = resolve(manifest: nil, v3: F.v3(lineage: (F.macA, 3)))
        let content = try content(resolution)
        #expect(content.origin == .v3 && content.notice == nil && content.sourceID == F.macA)
        #expect(content.display == nil && content.freshness.isV3Only)
    }

    /// V2/AE1: only v3 lifts to one account per provider, with no display block.
    @Test func v3OnlyLiftsOneAccountPerProviderWithTheUpdateMacLine() throws {
        let v3 = F.v3(providers: [F.v3Provider("claude"), F.v3Provider("codex", remaining: 15.04)])
        let resolution = resolve(manifest: nil, v3: v3)
        let content = try content(resolution)
        #expect(content.origin == .v3 && content.notice == .updateMac)
        #expect(content.display == nil && !content.widgetSparkEnabled && content.ladder == .full)
        #expect(content.providers.map { $0.accounts.count } == [1, 1])
        #expect(content.providers.allSatisfy { $0.source == .v3Main })
        let codex = try #require(content.providers.last?.mainAccount?.windows.first?.summary)
        // KTD6.2: lifted rows are normalized idempotently, severity from the normalized value.
        #expect(codex.percentRemaining == 15 && codex.severity == .critical)
        #expect(content.freshness.firstSeen == now && content.freshness.isV3Only)
        #expect(resolution.cache.v3?.envelope == v3)
    }

    /// V5: a future v4 schema with readable v3 shows v3 plus "Update Headroom on this iPhone".
    @Test func readerMinimumAboveThisPhoneFallsBackToV3WithTheUpdatePhoneLine() throws {
        let claude = F.bytes(F.payload(generation: 1))
        var json = try #require(
            JSONSerialization.jsonObject(
                with: F.bytes(F.manifest(entries: ["claude": F.entry(claude, generation: 1)]))) as? [String: Any])
        json["r"] = 2
        json["p"] = "a future shape"
        let future = try JSONSerialization.data(withJSONObject: json)
        let v3 = F.v3(lineage: (F.macA, 1))
        let withV3 = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(manifest: future, providerKeys: ["claude": claude], v3: F.v3Bytes(v3), now: now))
        #expect(withV3.snapshot.content?.origin == .v3 && withV3.snapshot.content?.notice == .updatePhone)
        let alone = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(manifest: future, v3: nil, now: now))
        #expect(alone.snapshot.state == .waiting(.updatePhone))
        #expect(CompanionCompatibilityNotice.updatePhone.message == "Update Headroom on this iPhone")
    }

    @Test func compatibleFutureManifestWithUnknownFieldsResolvesNormally() throws {
        let claude = F.bytes(F.payload(generation: 1))
        var json = try #require(
            JSONSerialization.jsonObject(
                with: F.bytes(F.manifest(entries: ["claude": F.entry(claude, generation: 1)]))) as? [String: Any])
        json["v"] = 7
        json["futureBlock"] = ["x": [1, 2]]
        let resolution = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: try JSONSerialization.data(withJSONObject: json),
                providerKeys: ["claude": claude], v3: nil, now: now))
        #expect(resolution.snapshot.content?.origin == .v4)
    }

    @Test func incompatibleOrCorruptV3NeverHidesReadableV4() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let manifest = F.manifest(entries: ["claude": F.entry(claude, generation: 1)])
        var json = try #require(JSONSerialization.jsonObject(with: F.v3Bytes(F.v3(generatedAt: 99))) as? [String: Any])
        json["schemaVersion"] = 9
        for v3 in [try JSONSerialization.data(withJSONObject: json), Data("{".utf8)] {
            let resolution = CompanionSnapshotResolver.resolve(
                CompanionResolverInput(
                    manifest: F.bytes(manifest), providerKeys: ["claude": claude], v3: v3, now: now))
            #expect(resolution.snapshot.content?.origin == .v4)
        }
    }

    // MARK: Status and lineage changes (rule 5, KTD22)

    @Test func disabledTombstoneWinsFirstAndClearsAccountCaches() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let active = F.manifest(entries: ["claude": F.entry(claude, generation: 1)])
        let first = resolve(manifest: active, keys: ["claude": claude], v3: F.v3(lineage: (F.macA, 1)))
        let tombstone = try CompanionManifest.disabledTombstone(sourceID: F.macA)
        // Readable v3 (even newer) and checked caches cannot outrank the tombstone.
        let paused = resolve(manifest: tombstone, keys: ["claude": claude], v3: F.v3(generatedAt: 50), cache: first.cache)
        #expect(paused.snapshot.state == .paused)
        #expect(paused.cache == CompanionCacheContents(paused: true))
        // Missing keys afterwards cannot revive old accounts from the cache.
        #expect(resolve(manifest: nil, cache: paused.cache).snapshot.state == .paused)
        // Re-enabling with an active manifest resumes.
        let resumed = resolve(manifest: active, keys: ["claude": claude], cache: paused.cache)
        #expect(resumed.snapshot.content?.origin == .v4 && !resumed.cache.paused)
    }

    @Test func disabledV3PausesUnlessANewerActiveManifestExists() throws {
        let disabled = F.v3(generatedAt: 20, status: .disabled)
        let alone = resolve(manifest: nil, v3: disabled)
        #expect(alone.snapshot.state == .paused)
        #expect(alone.cache.v3?.envelope.snapshot.status == .disabled)
        let claude = F.bytes(F.payload(generation: 1))
        let older = F.manifest(generatedAt: 10, entries: ["claude": F.entry(claude, generation: 1)])
        #expect(resolve(manifest: older, keys: ["claude": claude], v3: disabled).snapshot.state == .paused)
        let newer = F.manifest(generatedAt: 30, entries: ["claude": F.entry(claude, generation: 1)])
        let resumed = resolve(manifest: newer, keys: ["claude": claude], v3: disabled)
        #expect(resumed.snapshot.content?.origin == .v4)
        #expect(resumed.snapshot.diagnostics.contains(.v3DisabledOverriddenByNewerManifest))
    }

    @Test func newLineageDropsOtherLineagesAndWaitsForItsProviders() throws {
        let a = F.bytes(F.payload(generation: 4, extras: [F.account("a1")]))
        let fromA = resolve(
            manifest: F.manifest(generation: 4, generatedAt: 0, entries: ["claude": F.entry(a, generation: 4)]),
            keys: ["claude": a])
        let b = F.bytes(F.payload(source: F.macB, generation: 1))
        let manifestB = F.manifest(
            source: F.macB, generation: 1, generatedAt: 30, entries: ["claude": F.entry(b, generation: 1)])
        // B's key has not arrived; A's key is still in KVS and must not be used.
        let switched = resolve(manifest: manifestB, keys: ["claude": a], cache: fromA.cache)
        #expect(try provider(switched, "claude").source == .skeleton)
        #expect(switched.cache.providers.isEmpty && switched.cache.manifest?.sourceID == F.macB)
        #expect(!switched.cache.firstSeen.keys.contains { $0.contains(F.macA) })
        // An older manifest from A arriving later does not flip back.
        let stale = resolve(
            manifest: F.manifest(generation: 5, generatedAt: 10, entries: ["claude": F.entry(a, generation: 4)]),
            keys: ["claude": a], cache: switched.cache)
        #expect(try content(stale).sourceID == F.macB)
        #expect(stale.snapshot.diagnostics.contains(.olderManifestIgnored))
    }

    @Test func generationResetUnderOneLineageDoesNotDim() throws {
        let key = F.bytes(F.payload(generation: 90))
        let high = resolve(
            manifest: F.manifest(generation: 90, generatedAt: 0, entries: ["claude": F.entry(key, generation: 90)]),
            keys: ["claude": key], at: F.date(0).date)
        let resetKey = F.bytes(F.payload(generation: 1, extras: [F.account("x1")]))
        let reset = resolve(
            manifest: F.manifest(generation: 2, generatedAt: 7_200, entries: ["claude": F.entry(resetKey, generation: 1)]),
            keys: ["claude": resetKey], cache: high.cache, at: F.date(7_205).date)
        let content = try content(reset)
        #expect(content.generation == 2 && reset.snapshot.diagnostics.contains(.manifestGenerationReset))
        #expect(try provider(reset, "claude").accounts.count == 2)
        #expect(!CompanionFreshnessRule.isDimmed(content.freshness, surface: .app, at: F.date(7_210).date))
        // An older generation that is also older in time is a stale delivery and ignored.
        let late = resolve(
            manifest: F.manifest(generation: 89, generatedAt: -60, entries: ["claude": F.entry(key, generation: 90)]),
            keys: ["claude": key], cache: high.cache)
        #expect(try #require(late.snapshot.content).generation == 90)
    }

    @Test func corruptManifestFallsBackToTheCheckedCacheThenV3ThenWaiting() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let first = resolve(manifest: F.manifest(entries: ["claude": F.entry(claude, generation: 1)]), keys: ["claude": claude])
        let corrupt = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(manifest: Data("{".utf8), providerKeys: [:], v3: nil, cache: first.cache, now: now))
        #expect(corrupt.snapshot.content?.origin == .v4)
        #expect(corrupt.snapshot.content?.providers.first?.source == .v4(.manifestDigestMatched))
        #expect(corrupt.snapshot.diagnostics.contains(.manifestUnreadableUsedCache))
        #expect(resolve(manifest: nil).snapshot.state == .waiting(nil))
    }

    // MARK: V14, first-seen and projection

    /// V14: Claude grows from 1 to 2 accounts while Codex's key lags; rows switch once.
    @Test func providerGrowthWhileOthersLagSwitchesAccountRowsExactlyOnce() throws {
        let claude1 = F.bytes(F.payload(generation: 1))
        let claude2 = F.bytes(F.payload(generation: 2, extras: [F.account("x1", title: "Work")]))
        let codex1 = F.bytes(F.payload("codex", generation: 1))
        let codex2 = F.bytes(F.payload("codex", generation: 2, main: F.account(plan: "Pro")))
        let order = ["claude", "codex"]
        let m1 = F.manifest(generation: 1, order: order, entries: [
            "claude": F.entry(claude1, generation: 1), "codex": F.entry(codex1, generation: 1)])
        let m2 = F.manifest(generation: 2, generatedAt: 60, order: order, entries: [
            "claude": F.entry(claude2, generation: 2), "codex": F.entry(codex2, generation: 2)])
        var cache = CompanionCacheContents.empty
        var claudeRows: [[String]] = []
        for (manifest, keys) in [
            (m1, ["claude": claude1, "codex": codex1]),
            (m2, ["claude": claude1, "codex": codex1]),
            (m2, ["claude": claude2, "codex": codex1]),
            (m2, ["claude": claude2, "codex": codex1]),
            (m2, ["claude": claude2, "codex": codex2]),
        ] {
            let resolution = resolve(manifest: manifest, keys: keys, cache: cache)
            cache = resolution.cache
            claudeRows.append(try provider(resolution, "claude").accounts.map(\.id))
        }
        let changes = zip(claudeRows, claudeRows.dropFirst()).filter { $0 != $1 }.count
        #expect(changes == 1 && claudeRows.last == ["primary", "x1"])
    }

    @Test func firstSeenIsCreatedOnceAndReusedByLaterReads() throws {
        let claude = F.bytes(F.payload(generation: 1))
        let manifest = F.manifest(entries: ["claude": F.entry(claude, generation: 1)])
        let first = resolve(manifest: manifest, keys: ["claude": claude], at: now)
        let second = resolve(manifest: manifest, keys: ["claude": claude], cache: first.cache, at: now + 500)
        #expect(try content(second).freshness.firstSeen == now)
        #expect(second.cache.firstSeen == first.cache.firstSeen)
    }

    @Test func primaryProjectionFiltersSparkByTheMacWidgetSwitchAndKeepsSelection() throws {
        let rows = [
            F.window(.fiveHour), F.window(.weekly, resetAt: 86_400),
            F.window(.other, name: "GPT-5.3-Codex-Spark 5h", spark: true),
        ]
        let codex = F.bytes(F.payload("codex", main: F.account(windows: rows), extras: [F.account("x1")]))
        for widgetSpark in [false, true] {
            let manifest = F.manifest(
                order: ["codex", "claude"], entries: ["codex": F.entry(codex, generation: 1)],
                selection: ["claude", "unknown", "claude"], widgetSpark: widgetSpark)
            let resolution = resolve(manifest: manifest, keys: ["codex": codex])
            let projection = try #require(resolution.snapshot.primaryProjection())
            #expect(projection.providers.first?.windows.count == (widgetSpark ? 3 : 2))
            #expect(projection.widgetProviderSelection == ["claude"])
            #expect(projection.providers.first?.renewalDate == nil)
            // The app keeps every row and flags Spark for its own switch.
            #expect(try provider(resolution, "codex").mainAccount?.windows.filter(\.isSpark).count == 1)
        }
    }

    /// KTD13: a lifted v3 projects back to the identical envelope for every demo variant.
    @Test func liftedV3ProjectsBackToTheSameEnvelopeForEveryDemoVariant() throws {
        for variant in ["full", "noSpend", "claudeOnly", "claudeOnlyNoSpend", "codexFiveHourReturns", "attention", "fourProviders"] {
            let inner = DemoScreenshotData.envelope(for: variant)
            // The contract drops renewal dates: a 1.5 Mac emits nil in v3 too.
            let providers = inner.providers.map {
                WidgetProviderSummary(
                    id: $0.id, displayName: $0.displayName, planLabel: $0.planLabel,
                    freshness: $0.freshness, windows: $0.windows, renewalDate: nil)
            }
            let canonical = WidgetSnapshotEnvelope(
                generatedAt: CompanionWireDate.canonicalize(inner.generatedAt)!, status: inner.status,
                providers: providers, apiSpendProviders: inner.apiSpendProviders,
                widgetProviderSelection: inner.widgetProviderSelection)
            let v3 = SyncedWidgetSnapshotEnvelope(
                publishedAt: canonical.generatedAt, sourceID: "Mac", sourcePlatform: .macOS,
                snapshot: canonical)
            let resolution = CompanionSnapshotResolver.resolve(
                CompanionResolverInput(manifest: nil, v3: F.v3Bytes(v3), now: now))
            let decoded = try #require(SyncedWidgetSnapshotCodec.decode(F.v3Bytes(v3)).envelope)
            #expect(resolution.snapshot.primaryProjection() == decoded.snapshot, "variant \(variant)")
        }
    }

    /// The resolver exposes these inputs; skeletons become "Waiting for your Mac" at the
    /// same dim moment, and widget surfaces use main accounts only.
    @Test func resolvedSnapshotExposesSharedInputsPerSurface() throws {
        let claude = F.bytes(F.payload(extras: [F.account("x1", captured: -600)]))
        let manifest = F.manifest(
            order: ["claude", "codex"], entries: ["claude": F.entry(claude, generation: 1)])
        let resolution = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: F.bytes(manifest), providerKeys: ["claude": claude], v3: nil,
                now: F.date(5).date))
        let content = try #require(resolution.snapshot.content)
        #expect(CompanionFreshnessRule.updatedAt(resolution.snapshot.shownWindows(for: .app)) == F.date(-600).date)
        #expect(CompanionFreshnessRule.updatedAt(resolution.snapshot.shownWindows(for: .widget)) == F.date().date)
        #expect(content.providers.last?.source == .skeleton)
        #expect(CompanionFreshnessRule.dimsAt(content.freshness, surface: .app) == F.date(5 + 900).date)
    }
}
