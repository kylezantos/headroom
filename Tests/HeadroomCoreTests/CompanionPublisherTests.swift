import Foundation
import Testing

@testable import HeadroomCore

/// U5 / KTD7, KTD8, KTD22: the serial, coalesced publisher against a recording KVS and a
/// manual clock. `autoSchedule` is off, so every flush decision is driven by `tick()`.
@MainActor
@Suite
struct CompanionPublisherTests {
    typealias F = CompanionFixtures

    // MARK: Harness

    @MainActor
    final class Harness {
        let store: RecordingKeyValueStore
        let clock: ManualClock
        let lifecycle: RecordingLifecycle
        let diagnostics: CompanionPublishDiagnosticsStore
        let publisher: CompanionPublisher
        var generation: Int64 = 0
        /// What a heartbeat or forced republish captures: the latest state, re-stamped.
        var state: CompanionPublishCapture?

        init(autoSchedule: Bool = false, sleep: (@Sendable (TimeInterval) async -> Void)? = nil) {
            let suite = "headroom.publisher.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let store = RecordingKeyValueStore()
            let clock = ManualClock(F.date().date)
            let lifecycle = RecordingLifecycle()
            self.store = store
            self.clock = clock
            self.lifecycle = lifecycle
            diagnostics = CompanionPublishDiagnosticsStore(defaults: defaults)
            publisher = CompanionPublisher(
                store: store,
                configuration: .init(
                    sourceID: F.macA, macAppVersion: "1.5 (40)", flushSpacing: 60,
                    now: { clock.now }, autoSchedule: autoSchedule, sleep: sleep ?? { _ in }),
                diagnosticsStore: diagnostics, participants: [lifecycle])
        }

        func bindHeartbeat() async {
            await publisher.setCaptureProvider { [self] in
                guard var capture = self.state else { return nil }
                self.generation += 1
                capture.generation = self.generation
                return capture
            }
        }

        /// Stamps and submits like the facade does.
        @discardableResult
        func submit(_ capture: CompanionPublishCapture, forced: Bool = false) async -> Int64 {
            generation += 1
            var stamped = capture
            stamped.generation = generation
            state = capture
            await publisher.receive(stamped, forced: forced)
            return generation
        }

        func advance(_ seconds: TimeInterval) async {
            clock.advance(seconds)
            await publisher.tick()
        }

        func manifest() -> CompanionActiveManifest? {
            guard case .value(let manifest) = CompanionSyncCodec.decodeManifest(
                store.data(forKey: CompanionSyncKeys.manifest)) else { return nil }
            return manifest.active
        }

        func payload(_ id: String) -> CompanionProviderPayload? {
            guard case .value(let payload) = CompanionSyncCodec.decodeProviderPayload(
                store.data(forKey: CompanionSyncKeys.provider(id)!), providerID: id) else { return nil }
            return payload
        }

        func v3() -> SyncedWidgetSnapshotEnvelope? {
            SyncedWidgetSnapshotCodec.decode(store.data(forKey: iCloudSnapshotSync.snapshotKey)).envelope
        }
    }

    // MARK: Fixtures

    static func row(
        _ kind: CompanionWindowKind = .fiveHour, name: String? = nil, remaining: Double = 63,
        freshness: CompanionWindowFreshness = .live, observed: Int64? = nil, spark: Bool = false
    ) -> CompanionSlimWindow {
        F.window(
            kind, name: name, remaining: remaining, utilization: 100 - remaining,
            freshness: freshness, observed: observed.map { F.date($0) }, spark: spark)
    }

    static func account(
        _ id: String = "primary", title: String = "Main", captured: Int64 = 0,
        remaining: Double = 63, extraRows: [CompanionSlimWindow] = [], stale: Bool = false
    ) -> CompanionAccountSummary {
        try! CompanionAccountSummary(
            id: id, title: title, planName: "Max", freshness: stale ? .stale : .live,
            capturedAt: F.date(captured), attention: stale ? .retrying : nil,
            needsAttention: stale ? false : nil,
            windows: [row(.fiveHour, remaining: remaining), row(.weekly, remaining: 40)] + extraRows)
    }

    static func provider(
        _ id: String = "claude", main: CompanionAccountSummary = account(),
        extras: [CompanionAccountSummary] = [], spend: CompanionSpendSummary? = nil,
        mode: CompanionPayloadMode = .subscription, interval: Double = 120
    ) -> CompanionCapturedProvider {
        CompanionCapturedProvider(
            providerID: id, mode: mode, mainAccount: mode == .spendOnly ? nil : main,
            extraAccounts: extras, apiSpend: spend, effectiveIntervalSeconds: interval)
    }

    static func capture(
        at offset: Int64 = 0, providers: [CompanionCapturedProvider] = [provider()],
        interval: Int = 120, display: CompanionDisplayBlock = CompanionDisplayBlock(),
        selection: [String]? = nil
    ) -> CompanionPublishCapture {
        let stamp = F.date(offset)
        let subscription = providers.filter { $0.mode == .subscription }.map(\.providerID)
        return CompanionPublishCapture(
            generatedAt: stamp, status: .enabled, providers: providers,
            providerOrder: subscription,
            spendOrder: providers.filter { $0.apiSpend != nil }.map(\.providerID),
            chosenIntervalSeconds: interval, display: display,
            widgetProviderSelection: selection ?? Array(subscription.prefix(2)),
            v3: WidgetSnapshotEnvelope(generatedAt: stamp.date, status: .enabled, providers: []))
    }

    static func disabled(at offset: Int64 = 0) -> CompanionPublishCapture {
        .disabled(at: F.date(offset), chosenIntervalSeconds: 120)
    }

    static func spend(captured: Int64 = 0, amount: Double = 12.5) -> CompanionSpendSummary {
        try! CompanionSpendSummary(
            id: "claude", displayName: "Anthropic API", amount: amount, currency: "USD",
            periodLabel: "Oct 1 – Oct 31", capturedAt: F.date(captured))
    }

    // MARK: Coalescer

    @Test func firstPublishWritesEveryKeyThenIdenticalContentWithinTheSpacingWritesNothing() async throws {
        let h = Harness()
        await h.submit(Self.capture(providers: [Self.provider(), Self.provider("codex")]))
        #expect(h.store.operations == [
            .set(CompanionSyncKeys.provider("claude")!), .set(CompanionSyncKeys.provider("codex")!),
            .set(CompanionSyncKeys.manifest), .set(iCloudSnapshotSync.snapshotKey),
        ])
        let manifest = try #require(h.manifest())
        #expect(manifest.generation == 1 && manifest.generatedAt == F.date())
        // One shared generatedAt and the lineage pair on the v3 mirror (KTD5).
        let v3 = try #require(h.v3())
        #expect(v3.snapshot.generatedAt == F.date().date && v3.publishedAt == F.date().date)
        #expect(v3.companionLineage == CompanionV3Lineage(sourceID: F.macA, generation: 1))
        #expect(v3.sourceID == "Mac")

        h.store.clearLog()
        await h.advance(20)
        await h.submit(Self.capture(at: 20, providers: [Self.provider(), Self.provider("codex")]))
        await h.advance(60)
        #expect(h.store.operations.isEmpty)
    }

    @Test func aContentChangeInsideTheSpacingWritesOnceWhenTheSpacingElapses() async throws {
        let h = Harness()
        await h.submit(Self.capture(providers: [Self.provider(), Self.provider("codex")]))
        h.store.clearLog()

        await h.advance(10)
        await h.submit(Self.capture(at: 10, providers: [
            Self.provider(main: Self.account(captured: 10, remaining: 50)), Self.provider("codex"),
        ]))
        await h.advance(20)
        await h.submit(Self.capture(at: 30, providers: [
            Self.provider(main: Self.account(captured: 30, remaining: 45)), Self.provider("codex"),
        ]))
        #expect(h.store.operations.isEmpty)
        await h.advance(29)
        #expect(h.store.operations.isEmpty)
        await h.advance(1)
        // Only the changed provider, then the manifest and the v3 mirror together.
        #expect(h.store.operations == [
            .set(CompanionSyncKeys.provider("claude")!), .set(CompanionSyncKeys.manifest),
            .set(iCloudSnapshotSync.snapshotKey),
        ])
        #expect(h.payload("claude")?.mainAccount?.windows.first?.percentRemaining == 45)
        let manifest = try #require(h.manifest())
        #expect(manifest.providers["claude"]?.payloadGeneration == 3)
        // The unchanged key keeps the generation it was written in (KTD6.3).
        #expect(manifest.providers["codex"]?.payloadGeneration == 1)
        #expect(h.payload("codex")?.payloadGeneration == 1)
    }

    @Test func aHeartbeatRewritesTheManifestAndMirrorOncePerChosenInterval() async throws {
        let h = Harness()
        await h.bindHeartbeat()
        await h.submit(Self.capture())
        let first = try #require(h.manifest())
        h.store.clearLog()

        await h.advance(119)
        #expect(h.store.operations.isEmpty)
        // The heartbeat state keeps the same capture times, so the key itself stays.
        h.state = Self.capture(at: 120)
        await h.advance(1)
        #expect(h.store.operations == [.set(CompanionSyncKeys.manifest), .set(iCloudSnapshotSync.snapshotKey)])
        let beat = try #require(h.manifest())
        #expect(beat.generation > first.generation)
        #expect(beat.generatedAt == F.date(120))
        #expect(h.v3()?.snapshot.generatedAt == F.date(120).date)
        #expect(h.v3()?.companionGeneration == beat.generation)
        #expect(beat.providers["claude"]?.payloadGeneration == first.generation)

        h.store.clearLog()
        await h.advance(120)
        #expect(h.store.setCount == 2)
    }

    @Test func structuralChangesForceAnImmediateFlush() async throws {
        let h = Harness()
        await h.submit(Self.capture())
        h.store.clearLog()

        await h.advance(5)
        await h.submit(Self.capture(at: 5, providers: [
            Self.provider(extras: [Self.account("work", title: "Work", captured: 5)]),
        ]))
        #expect(h.store.setCount == 3)
        #expect(h.payload("claude")?.accounts.map(\.title) == ["Work"])

        h.store.clearLog()
        await h.advance(5)
        await h.submit(Self.capture(
            at: 10, providers: [Self.provider(extras: [Self.account("work", title: "Work", captured: 5)])],
            display: CompanionDisplayBlock(percentageMode: .used)))
        #expect(h.store.operations == [.set(CompanionSyncKeys.manifest), .set(iCloudSnapshotSync.snapshotKey)])
        #expect(h.manifest()?.display?.percentageMode == .used)

        h.store.clearLog()
        await h.advance(5)
        await h.submit(Self.capture(
            at: 15, providers: [Self.provider(extras: [Self.account("work", title: "Work", captured: 5)])],
            display: CompanionDisplayBlock(percentageMode: .used), selection: []))
        #expect(h.store.setCount == 2)
        #expect(h.manifest()?.widgetProviderSelection == [])
    }

    // MARK: Honest stamp (KTD8)

    @Test func anObservationAdvancingByOneIntervalRewritesTheKeyWithUnchangedNumbers() async throws {
        let h = Harness()
        await h.bindHeartbeat()
        let staleExtra = Self.account("old", title: "Old", captured: -3_600, stale: true)
        let retainedRow = Self.row(.other, name: "Weekly (Fable)", freshness: .stale, observed: -7_200)
        func state(_ captured: Int64, spendAt: Int64 = 0) -> CompanionPublishCapture {
            Self.capture(at: captured, providers: [
                Self.provider(
                    main: Self.account(captured: captured, extraRows: [retainedRow]),
                    extras: [staleExtra], spend: Self.spend(captured: spendAt)),
            ])
        }
        await h.submit(state(0))
        h.store.clearLog()

        // Advanced less than one interval: a coalesced flush finds nothing to write.
        h.clock.advance(70)
        await h.submit(state(70))
        #expect(h.store.operations.isEmpty)

        // At least one interval past the published observation: rewritten on the flush.
        h.clock.advance(60)
        await h.submit(state(130))
        #expect(h.store.operations.first == .set(CompanionSyncKeys.provider("claude")!))
        let payload = try #require(h.payload("claude"))
        #expect(payload.mainAccount?.capturedAt == F.date(130))
        // Retained rows and a stale extra keep their original observation times.
        #expect(payload.mainAccount?.windows.last?.observedAtOverride == F.date(-7_200))
        #expect(payload.accounts.first?.capturedAt == F.date(-3_600))

        // A heartbeat applies the same rule.
        h.store.clearLog()
        h.state = state(250)
        await h.advance(120)
        #expect(h.store.operations.first == .set(CompanionSyncKeys.provider("claude")!))
        #expect(h.payload("claude")?.mainAccount?.capturedAt == F.date(250))

        // A spend capture advancing by an interval rewrites the key with the same amount.
        h.store.clearLog()
        h.clock.advance(60)
        await h.submit(state(250, spendAt: 300))
        #expect(h.store.operations.first == .set(CompanionSyncKeys.provider("claude")!))
        #expect(h.payload("claude")?.apiSpend?.capturedAt == F.date(300))
        #expect(h.payload("claude")?.apiSpend?.amount == 12.5)
    }

    // MARK: Serial order and iCloud state

    @Test func aLowerGenerationNeverFollowsAHigherOne() async throws {
        let h = Harness()
        var newer = Self.capture(providers: [Self.provider(main: Self.account(remaining: 10))])
        newer.generation = 9
        var older = Self.capture(providers: [Self.provider(main: Self.account(remaining: 90))])
        older.generation = 8
        await h.publisher.receive(newer)
        await h.publisher.receive(older, forced: true)
        await h.advance(120)
        #expect(h.manifest()?.generation == 9)
        #expect(h.payload("claude")?.mainAccount?.windows.first?.percentRemaining == 10)
        // Overlapping submissions land in decision (generation) order.
        var later = older
        later.generation = 10
        await h.publisher.receive(later, forced: true)
        #expect(h.manifest()?.generation == 10)
        #expect(h.payload("claude")?.mainAccount?.windows.first?.percentRemaining == 90)
    }

    @Test func aKeyRewrittenFromOutsideIsRestoredOnTheNextPublish() async throws {
        let h = Harness()
        await h.bindHeartbeat()
        await h.submit(Self.capture(providers: [Self.provider(), Self.provider("codex")]))
        let written = try #require(h.store.data(forKey: CompanionSyncKeys.provider("codex")!))
        h.store.seed(CompanionSyncKeys.provider("codex")!, Data("{}".utf8))
        h.store.seed(CompanionSyncKeys.provider("claude")!, nil)
        h.store.clearLog()

        await h.advance(120)
        #expect(Set(h.store.operations) == [
            .set(CompanionSyncKeys.provider("claude")!), .set(CompanionSyncKeys.provider("codex")!),
            .set(CompanionSyncKeys.manifest), .set(iCloudSnapshotSync.snapshotKey),
        ])
        #expect(h.payload("codex") != nil)
        #expect(h.store.data(forKey: CompanionSyncKeys.provider("codex")!) != written)
    }

    @Test func pendingWritesFlushOnSleepAndQuit() async throws {
        let h = Harness()
        await h.submit(Self.capture())
        h.store.clearLog()
        await h.advance(10)
        await h.submit(Self.capture(at: 10, providers: [Self.provider(main: Self.account(captured: 10, remaining: 20))]))
        #expect(h.store.operations.isEmpty)
        await h.publisher.flushPending()
        #expect(h.store.setCount == 3)
        #expect(h.payload("claude")?.mainAccount?.windows.first?.percentRemaining == 20)
        h.store.clearLog()
        await h.publisher.flushPending()
        #expect(h.store.operations.isEmpty)
    }

    @Test func anAccountChangeRewritesEveryKey() async throws {
        let h = Harness()
        await h.bindHeartbeat()
        await h.submit(Self.capture(providers: [Self.provider(), Self.provider("codex")]))
        h.store.clearLog()
        await h.advance(5)
        await h.publisher.accountDidChange()
        #expect(h.store.setCount == 4)
        await h.publisher.participantsIdle()
        #expect(await h.lifecycle.events == ["enable", "account"])
    }

    // MARK: Sync off (KTD22, V7, AE4)

    @Test func syncOffWritesDisabledV3ThenTheTombstoneThenRemovesEveryOtherKey() async throws {
        let h = Harness()
        await h.submit(Self.capture(providers: [Self.provider(), Self.provider("codex")]))
        let request = CompanionSyncKeys.request(deviceUUID: UUID().uuidString)!
        h.store.seed(request, Data("{}".utf8))
        h.store.seed(CompanionSyncKeys.receipt, Data("{}".utf8))
        h.store.clearLog()

        await h.advance(3)
        await h.submit(Self.disabled(at: 3))
        #expect(h.store.operations == [
            .set(iCloudSnapshotSync.snapshotKey), .set(CompanionSyncKeys.manifest),
            .remove(CompanionSyncKeys.provider("claude")!), .remove(CompanionSyncKeys.provider("codex")!),
            .remove(CompanionSyncKeys.receipt), .remove(request),
        ])
        #expect(h.store.keys(withPrefix: CompanionSyncKeys.namespace) == [CompanionSyncKeys.manifest])
        #expect(CompanionSyncCodec.decodeManifest(h.store.data(forKey: CompanionSyncKeys.manifest))
            == .value(.disabled(sourceID: F.macA)))
        let v3 = try #require(h.v3())
        #expect(v3.snapshot.status == .disabled && v3.snapshot.providers.isEmpty)
        #expect(v3.companionSourceID == F.macA)
        await h.publisher.participantsIdle()
        #expect(await h.lifecycle.events == ["enable", "purge"])
        // The phone resolves the paused state from these keys (AE4).
        let resolved = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: h.store.data(forKey: CompanionSyncKeys.manifest),
                v3: h.store.data(forKey: iCloudSnapshotSync.snapshotKey), now: F.date(4).date))
        #expect(resolved.snapshot.state == .paused)

        // Further disabled captures in the same launch write nothing more.
        h.store.clearLog()
        await h.advance(60)
        await h.submit(Self.disabled(at: 63))
        #expect(h.store.operations.isEmpty)
    }

    /// Contract Decision 3 / AE4: sync off clears the whole v4 namespace, keys a newer build
    /// wrote included, but never the account-scope marker that lives outside it.
    @Test func syncOffSweepsUnknownNamespaceKeysButKeepsTheScopeMarker() async throws {
        let h = Harness()
        await h.submit(Self.capture())
        let future = CompanionSyncKeys.namespace + "future"
        h.store.seed(future, Data("{}".utf8))
        h.store.seed(CompanionSyncKeys.scopeMarker, Data("marker".utf8))

        await h.advance(3)
        await h.submit(Self.disabled(at: 3))
        #expect(h.store.operations.contains(.remove(future)))
        #expect(h.store.keys(withPrefix: CompanionSyncKeys.namespace) == [CompanionSyncKeys.manifest])
        #expect(h.store.data(forKey: CompanionSyncKeys.scopeMarker) == Data("marker".utf8))
        #expect(!h.store.operations.contains(.remove(CompanionSyncKeys.scopeMarker)))
    }

    @Test func everyLaunchWhileOffRepeatsTheSweep() async throws {
        let h = Harness()
        // Leftovers from a lost deletion, or a downgraded Mac that could not delete v4.
        h.store.seed(CompanionSyncKeys.provider("grok")!, Data("{}".utf8))
        h.store.seed(CompanionSyncKeys.manifest, Data("{}".utf8))
        await h.submit(Self.disabled())
        #expect(h.store.keys(withPrefix: CompanionSyncKeys.namespace) == [CompanionSyncKeys.manifest])
        await h.publisher.participantsIdle()
        #expect(await h.lifecycle.events == ["purge"])

        // A second launch (a new publisher) sweeps again.
        let relaunch = Harness()
        relaunch.store.seed(CompanionSyncKeys.provider("claude")!, Data("{}".utf8))
        await relaunch.submit(Self.disabled())
        #expect(relaunch.store.keys(withPrefix: CompanionSyncKeys.providerPrefix).isEmpty)
    }

    @Test func syncBackOnWritesEveryKeyImmediately() async throws {
        let h = Harness()
        await h.submit(Self.capture())
        await h.advance(1)
        await h.submit(Self.disabled(at: 1))
        h.store.clearLog()
        await h.advance(1)
        await h.submit(Self.capture(at: 2))
        #expect(h.store.setCount == 3)
        #expect(h.manifest() != nil && h.payload("claude") != nil)
    }

    @Test func turningAProviderOffRemovesItsKeyInTheSamePublish() async throws {
        let h = Harness()
        await h.submit(Self.capture(providers: [Self.provider(), Self.provider("grok")]))
        h.store.clearLog()
        await h.advance(1)
        await h.submit(Self.capture(at: 1, providers: [Self.provider()]))
        #expect(h.store.operations == [
            .set(CompanionSyncKeys.manifest), .set(iCloudSnapshotSync.snapshotKey),
            .remove(CompanionSyncKeys.provider("grok")!),
        ])
        #expect(h.manifest()?.providers.keys.sorted() == ["claude"])
    }

    @Test func aSpendOnlyKeyStaysWhileSpendIsOnAndGoesWithBoth() async throws {
        let h = Harness()
        let spendOnly = Self.provider(spend: Self.spend(), mode: .spendOnly)
        await h.submit(Self.capture(providers: [spendOnly]))
        let payload = try #require(h.payload("claude"))
        #expect(payload.mode == .spendOnly && payload.mainAccount == nil && payload.apiSpend != nil)
        #expect(h.manifest()?.providerOrder == [] && h.manifest()?.spendOrder == ["claude"])

        await h.advance(1)
        await h.submit(Self.capture(at: 1, providers: []))
        #expect(h.store.keys(withPrefix: CompanionSyncKeys.providerPrefix).isEmpty)
    }

    // MARK: Budget and quota (KTD7)

    static func heavyProvider(_ id: String, accounts: Int, captured: Int64 = 0) -> CompanionCapturedProvider {
        let models = (0..<6).map { Self.row(.other, name: "Weekly (Model \($0) with a long name)", remaining: Double($0) + 0.5) }
        let all = (0..<accounts).map { i in
            Self.account(
                i == 0 ? "primary" : String(format: "%08x-4f2b-4c1d-9a7e-%012x", i, i * 7_919),
                title: "Client account \(i + 1) — long label", captured: captured - Int64(i),
                remaining: Double(i % 90) + 0.25, extraRows: models)
        }
        return Self.provider(id, main: all[0], extras: Array(all.dropFirst()))
    }

    @Test func anOversizedKeyStepsTheLadderBeforeWritingAndStepsBackWhenAccountsGo() async throws {
        let h = Harness()
        await h.submit(Self.capture(providers: [Self.heavyProvider("claude", accounts: 20)]))
        let level1 = try #require(h.manifest())
        #expect(level1.dropLadderLevel == 1)
        let payload = try #require(h.payload("claude"))
        #expect(payload.allAccounts.count == 20 && payload.omittedAccountCount == 0)
        #expect(payload.accounts.allSatisfy { $0.windows.allSatisfy { $0.kind != .other } })
        #expect(payload.mainAccount?.windows.count == 8)
        #expect(try #require(h.store.data(forKey: CompanionSyncKeys.provider("claude")!)).count <= 15_000)
        #expect((await h.publisher.currentDiagnostics).ladderLevel == 1)

        await h.advance(1)
        await h.submit(Self.capture(at: 1, providers: [Self.heavyProvider("claude", accounts: 4, captured: 1)]))
        #expect(h.manifest()?.dropLadderLevel == 0)
        #expect(h.payload("claude")?.accounts.first?.windows.count == 8)
        #expect(h.diagnostics.load().ladderLevel == 0)
    }

    @Test func eachQuotaViolationUnderBudgetStepsTheLadderOnceAndIsRecorded() async throws {
        let h = Harness()
        await h.bindHeartbeat()
        let state = Self.capture(providers: [Self.heavyProvider("claude", accounts: 3)])
        await h.submit(state)
        #expect(h.manifest()?.dropLadderLevel == 0)

        await h.advance(2)
        await h.publisher.recordQuotaEvent(iCloudKeyValueQuotaEvent(observedAt: F.date(2).date))
        #expect(h.manifest()?.dropLadderLevel == 1)
        let recorded = h.diagnostics.load()
        #expect(recorded.lastQuotaEventAt == F.date(2).date && recorded.ladderLevel == 1)

        await h.advance(2)
        await h.publisher.recordQuotaEvent(iCloudKeyValueQuotaEvent(observedAt: F.date(4).date))
        #expect(h.manifest()?.dropLadderLevel == 2)
        await h.advance(2)
        await h.publisher.recordQuotaEvent(iCloudKeyValueQuotaEvent(observedAt: F.date(6).date))
        #expect(h.manifest()?.dropLadderLevel == 2)
        // At or below the envelope the cap step never trims an account.
        #expect(h.payload("claude")?.allAccounts.count == 3)
    }

    @Test func protocolOverflowStopsTheWriteAndKeepsTheLastValidContent() async throws {
        let h = Harness()
        await h.submit(Self.capture())
        let held = h.store.data(forKey: CompanionSyncKeys.manifest)
        h.store.seed(CompanionSyncKeys.request(deviceUUID: UUID().uuidString)!, Data(count: 63_900))
        h.store.clearLog()
        await h.advance(1)
        await h.submit(Self.capture(at: 1, providers: [Self.provider(extras: [Self.account("w", title: "W")])]))
        #expect(h.store.operations.isEmpty)
        #expect(h.store.data(forKey: CompanionSyncKeys.manifest) == held)
        #expect(h.diagnostics.load().lastFailure == "overBudget")
    }

    /// Contract Decision 3: an unknown key under the v4 namespace (a newer build's) counts
    /// toward the 64 KB image like every known key.
    @Test func unknownNamespaceKeysCountTowardTheBudget() async throws {
        let h = Harness()
        await h.submit(Self.capture())
        let held = h.store.data(forKey: CompanionSyncKeys.manifest)
        h.store.seed(CompanionSyncKeys.namespace + "future", Data(count: 63_900))
        h.store.clearLog()
        await h.advance(1)
        await h.submit(Self.capture(at: 1, providers: [Self.provider(extras: [Self.account("w", title: "W")])]))
        #expect(h.store.operations.isEmpty)
        #expect(h.store.data(forKey: CompanionSyncKeys.manifest) == held)
        #expect(h.diagnostics.load().lastFailure == "overBudget")
    }

    /// A failed heartbeat backs off one chosen interval instead of re-capturing and
    /// re-encoding every second until the content shrinks (review #6).
    @Test func anOverBudgetHeartbeatWaitsAWholeIntervalBeforeTryingAgain() async throws {
        let sleep = RecordingSleep()
        let h = Harness(autoSchedule: true, sleep: sleep.sleep)
        await h.bindHeartbeat()
        await h.submit(Self.capture())
        #expect(await sleep.next() == 120)
        let request = CompanionSyncKeys.request(deviceUUID: UUID().uuidString)!
        h.store.seed(request, Data(count: 63_900))
        let held = h.store.data(forKey: CompanionSyncKeys.manifest)

        await h.advance(120)
        #expect(h.diagnostics.load().lastFailure == "overBudget")
        let captured = h.generation
        #expect(await sleep.next() == 120)

        // Each second of the following interval: no new capture, no new write, and the
        // timer still aims at one interval after the failed attempt.
        for second in 1...119 {
            await h.advance(1)
            #expect(await sleep.next() == TimeInterval(120 - second))
        }
        #expect(h.generation == captured)
        #expect(h.store.data(forKey: CompanionSyncKeys.manifest) == held)

        // One interval after the failed attempt it tries again, and recovers once room returns.
        h.store.seed(request, nil)
        await h.advance(1)
        #expect(h.generation == captured + 1)
        #expect(h.store.data(forKey: CompanionSyncKeys.manifest) != held)
        #expect(h.diagnostics.load().lastFailure == nil)
        #expect(await sleep.next() == 120)
    }

    // MARK: Write rate (KTD8 steady state)

    /// The multi-20 envelope with a 2-minute interval: 61 accounts, one merge every two
    /// seconds, numbers changing on most merges, for 30 simulated minutes.
    @Test func multiTwentyAtATwoMinuteIntervalStaysAtOrUnderSixWritesPerMinute() async throws {
        let h = Harness()
        await h.bindHeartbeat()
        var captured: [String: [Int64]] = [:]
        var remaining: [String: [Double]] = [:]
        let ids = ["claude", "codex", "grok"]
        for id in ids {
            captured[id] = Array(repeating: 0, count: 20)
            remaining[id] = (0..<20).map { Double($0) + 10 }
        }
        func state(at t: Int64) -> CompanionPublishCapture {
            var providers = ids.map { id in
                let accounts = (0..<20).map { i in
                    Self.account(
                        i == 0 ? "primary" : "\(id)-\(i)", title: "Account \(i + 1)",
                        captured: captured[id]![i], remaining: remaining[id]![i],
                        extraRows: id == "codex"
                            ? [Self.row(.other, name: "GPT-5.3-Codex-Spark 5h", spark: true)] : [])
                }
                return Self.provider(id, main: accounts[0], extras: Array(accounts.dropFirst()))
            }
            providers.append(Self.provider("cursor", main: Self.account(captured: t)))
            return Self.capture(at: t, providers: providers)
        }
        await h.submit(state(at: 0))
        h.store.clearLog()

        var setsPerMinute: [Int] = []
        var lastCount = 0
        var flushSizes: [Int] = []
        var before = 0
        var merges = 0
        for second in 1...1_800 {
            let t = Int64(second)
            if second % 2 == 0 {
                let slot = merges % 61
                merges += 1
                if slot < 60 {
                    let id = ids[slot / 20]
                    let index = slot % 20
                    captured[id]![index] = t
                    if merges % 3 != 0 { remaining[id]![index] = Double((merges * 7) % 100) }
                }
                h.state = state(at: t)
                await h.advance(1)
                await h.submit(state(at: t))
            } else {
                await h.advance(1)
            }
            let count = h.store.setCount
            if count > before { flushSizes.append(count - before) }
            before = count
            if second % 60 == 0 {
                setsPerMinute.append(count - lastCount)
                lastCount = count
            }
        }
        let average = Double(h.store.setCount) / 30
        print("U5-WRITE-RATE total=\(h.store.setCount) average=\(average) max=\(setsPerMinute.max() ?? 0) maxFlush=\(flushSizes.max() ?? 0)")
        #expect(flushSizes.allSatisfy { $0 <= 6 })
        #expect(average <= 6)
        #expect((setsPerMinute.max() ?? 0) <= 6)
    }
}

/// KTD22 / R35: the what-syncs footnote and the Mac status line.
@Suite
struct CompanionPrivacyCopyTests {
    @Test func whatSyncsNamesEveryWireCategoryAndClaimsNoEncryption() {
        let copy = CompanionPrivacyCopy.whatSyncs
        for phrase in [
            "account names you chose", "plan names", "usage", "reset times", "API spend",
            "display choices", "check-now requests", "random ID for this Mac",
            "each iPhone or iPad", "Sign-ins, emails and API keys never sync",
            "isn’t end-to-end encrypted",
        ] {
            #expect(copy.contains(phrase), "\(phrase)")
        }
        // R2C6: curly apostrophes only, no "connect".
        #expect(!copy.contains("'") && !copy.localizedCaseInsensitiveContains("connect"))
    }

    @Test func statusLineReportsThePublishAndTheLadderPlainly() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(CompanionPrivacyCopy.macStatus(lastPublishAt: nil, formattedTime: nil, ladderLevel: 0, lastFailure: nil)
            == "Nothing sent to iCloud yet.")
        #expect(CompanionPrivacyCopy.macStatus(lastPublishAt: at, formattedTime: "at 2:41 PM", ladderLevel: 0, lastFailure: nil)
            == "Last sent to iCloud at 2:41 PM.")
        #expect(CompanionPrivacyCopy.macStatus(lastPublishAt: at, formattedTime: "at 2:41 PM", ladderLevel: 1, lastFailure: nil)
            == "Last sent to iCloud at 2:41 PM. Model rows for extra accounts stay on this Mac so everything fits in iCloud.")
        #expect(CompanionPrivacyCopy.macStatus(lastPublishAt: at, formattedTime: "at 2:41 PM", ladderLevel: 0, lastFailure: "overBudget")
            .hasSuffix("The latest update didn’t fit in iCloud, so your iPhone keeps the one before."))
    }
}
