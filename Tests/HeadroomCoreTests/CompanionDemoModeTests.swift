import Foundation
import Testing
@testable import HeadroomCore

struct CompanionDemoModeTests {
    @Test func defaultsToDisabledAndPersistsOnlyTheDemoFlag() throws {
        let suiteName = "CompanionDemoModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)
        let cache = WidgetSnapshotCache(defaults: defaults)
        let realEnvelope = WidgetSnapshotEnvelope.disabled(
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try cache.write(realEnvelope)

        #expect(!store.isEnabled)
        #expect(store.setEnabled(true) == .changed)
        #expect(store.isEnabled)
        #expect(defaults.dictionaryRepresentation().keys.contains(CompanionDemoModeStore.defaultsKey))
        #expect(store.setEnabled(true) == .unchanged)
        #expect(cache.read() == .snapshot(realEnvelope))

        #expect(store.setEnabled(false) == .changed)
        #expect(!store.isEnabled)
        #expect(defaults.object(forKey: CompanionDemoModeStore.defaultsKey) == nil)
        #expect(cache.read() == .snapshot(realEnvelope))
    }

    @Test func unavailableStoreSupportsSessionOnlyFallback() {
        let store = CompanionDemoModeStore(defaults: nil)

        #expect(!store.isEnabled)
        #expect(store.setEnabled(true) == .unavailable)
        #expect(!store.isEnabled)
    }

    @Test func variantDefaultsToFull() throws {
        let suiteName = "CompanionDemoModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)

        #expect(store.variant == "full")
    }

    @Test func variantPersistsAndRoundTrips() throws {
        let suiteName = "CompanionDemoModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)

        #expect(store.setVariant("heavy") == .changed)
        #expect(store.variant == "heavy")
        #expect(store.setVariant("heavy") == .unchanged)
        #expect(store.setVariant("singleProviderFull") == .changed)
        #expect(store.variant == "singleProviderFull")
    }

    @Test func variantUnavailableWhenDefaultsNil() {
        let store = CompanionDemoModeStore(defaults: nil)

        #expect(store.setVariant("heavy") == .unavailable)
        #expect(store.variant == "full") // Still defaults to "full"
    }

    // MARK: - v4 demo data and check-now replay (U7, KTD21, AE8)

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CompanionDemoModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func store(_ defaults: UserDefaults?, clock: DemoReplayClock) -> CompanionDemoModeStore {
        CompanionDemoModeStore(defaults: defaults, now: { clock.now }, sleep: { clock.sleep($0) })
    }

    @Test func selectedVariantParsesTheStoredTokenAndDefaultsToMultiAccount() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompanionDemoModeStore(defaults: defaults)
        #expect(store.selectedVariant == .multiAccount)
        defaults.set("full", forKey: CompanionDemoModeStore.variantKey)
        #expect(store.selectedVariant == .multiAccount)
        #expect(store.setVariant(.dimmed) == .changed)
        #expect(store.selectedVariant == .dimmed)
        #expect(store.variant == "dimmed")
        #expect(CompanionDemoModeStore(defaults: nil).selectedVariant == .multiAccount)
    }

    @Test func screenshotPresentationIsItsOwnFlag() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompanionDemoModeStore(defaults: defaults)
        #expect(!store.isScreenshotPresentation)
        #expect(store.setScreenshotPresentation(true) == .changed)
        #expect(store.isScreenshotPresentation && !store.isEnabled)
        #expect(store.setScreenshotPresentation(true) == .unchanged)
        #expect(store.setScreenshotPresentation(false) == .changed)
        #expect(defaults.object(forKey: CompanionDemoModeStore.screenshotPresentationKey) == nil)
        #expect(CompanionDemoModeStore(defaults: nil).setScreenshotPresentation(true) == .unavailable)
    }

    @Test func activationAndVariantFollowLaunchThenStore() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompanionDemoModeStore(defaults: defaults)
        let plain = CompanionDemoLaunchOptions.parse(["Headroom"])
        let screenshot = CompanionDemoLaunchOptions.parse(["Headroom", "--demo", "--demo-variant", "paused"])
        #expect(!store.isActive(launch: plain))
        #expect(store.isActive(launch: screenshot))
        store.setEnabled(true)
        store.setVariant(.bankedResets)
        #expect(store.isActive(launch: plain))
        #expect(store.variant(launch: plain) == .bankedResets)
        #expect(store.variant(launch: screenshot) == .paused)
    }

    /// R30/AE8 with a recording iCloud double: the production loader's demo seam returns
    /// bundled data, and a full demo pull replays the receipt sequence, without one KVS read
    /// or write, one cache file touched, one scope check, or one demo preference written.
    @Test func demoLoadAndPullNeverTouchICloudOrAnyCache() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = DemoReplayClock(Self.start)
        let demo = store(defaults, clock: clock)
        demo.setEnabled(true)
        let preferencesBefore = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("companion") }

        let spy = SpyKeyValueStore()
        let storage = MemoryCacheStorage()
        let scope = FakeAccountScope("apple-id-a")
        let loader = CompanionSnapshotLoader(
            store: spy,
            cache: CompanionSnapshotCache(storage: storage, coordinator: BarrierCoordinator(anchor: SharedAnchor()), scope: scope),
            now: { clock.now },
            demo: demo.loaderSeam(launch: .parse(["Headroom"])))

        #expect(loader.load() == CompanionDemoData.snapshot(.multiAccount, now: Self.start))
        let recorder = DemoStepRecorder()
        #expect(await demo.replayCheckNow(.multiAccount) { await recorder.record($0) })
        #expect(loader.load().content?.origin == .v4)

        #expect(await !recorder.steps.isEmpty)
        #expect(spy.reads == 0 && spy.mutations == 0)
        #expect(spy.keys(withPrefix: "").isEmpty)
        #expect(storage.writes.isEmpty && storage.removals.isEmpty && scope.checks == 0)
        #expect(defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("companion") }.keys.sorted()
            == preferencesBefore.keys.sorted())
    }

    @Test func loaderSeamIsInertWhenDemoIsOff() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let seam = CompanionDemoModeStore(defaults: defaults).loaderSeam(launch: .parse(["Headroom"]))
        #expect(seam() == nil)
        let launched = CompanionDemoModeStore(defaults: defaults, now: { Self.start })
            .loaderSeam(launch: .parse(["Headroom", "--demo", "--demo-variant", "waiting"]))
        #expect(launched() == CompanionResolvedSnapshot(state: .waiting(nil)))
    }

    /// KTD14 receipt states in order, own request only, progress forward, each landed
    /// account main-first in provider order, then finished with the snapshot at
    /// `finishedGeneration`, which also carries the matching answered request.
    @Test func checkNowReplaysAcceptedRunningFinishedOnTheInjectedClock() async throws {
        let clock = DemoReplayClock(Self.start)
        let demo = store(nil, clock: clock)
        let recorder = DemoStepRecorder()
        let replayed = await demo.replayCheckNow(.multiAccount) { await recorder.record($0) }
        #expect(replayed)
        let steps = await recorder.steps
        let receipts = steps.map(\.receipt)

        #expect(receipts.map(\.state) == [.accepted] + Array(repeating: .running, count: 5) + [.finished])
        #expect(receipts.allSatisfy { $0.requestIDs == [CompanionDemoData.requestID] && $0.sourceID == CompanionDemoData.sourceID })
        #expect(receipts.compactMap(\.completed) == [1, 2, 3, 4, 5, 5])
        #expect(receipts.compactMap(\.total).allSatisfy { $0 == 5 })
        #expect(receipts.compactMap(\.lastLanded).map { "\($0.providerID)/\($0.accountID)" } == [
            "claude/primary", "claude/work", "claude/studio", "codex/primary", "codex/codex-work", "codex/codex-work",
        ])
        #expect(receipts.allSatisfy { $0.startedAt == CompanionWireDate(date: Self.start) })

        // Paced by the injected sleep; display times follow the injected clock.
        #expect(clock.sleeps.count == steps.count)
        #expect(clock.sleeps.first == 0.8)
        let finished = try #require(receipts.last)
        #expect(finished.finishedAt == CompanionWireDate(date: clock.now))
        #expect(finished.finishedGeneration == CompanionDemoData.generation + 1)
        #expect(finished.answeredRequests.map(\.requestID) == [CompanionDemoData.requestID])

        // Only the finished step carries a snapshot, at or above finishedGeneration.
        #expect(steps.dropLast().allSatisfy { $0.snapshot == nil })
        let refreshed = try #require(steps.last?.snapshot?.content)
        #expect(refreshed.generation == finished.finishedGeneration)
        #expect(refreshed.answeredRequests.map(\.requestID) == [CompanionDemoData.requestID])
    }

    /// A pull on the dimmed demo lands a fresh reading, the way a real check would.
    @Test func checkNowOnTheDimmedDemoFinishesUndimmed() async throws {
        let clock = DemoReplayClock(Self.start)
        let recorder = DemoStepRecorder()
        #expect(await store(nil, clock: clock).replayCheckNow(.dimmed) { await recorder.record($0) })
        let refreshed = try #require(await recorder.steps.last?.snapshot?.content)
        #expect(!CompanionFreshnessRule.isDimmed(refreshed.freshness, surface: .app, at: clock.now))
    }

    /// The past-reset demo's stale Claude account lands live: the check produced a reading.
    @Test func checkNowOnThePastResetDemoLandsLiveReadings() async throws {
        let clock = DemoReplayClock(Self.start)
        let recorder = DemoStepRecorder()
        #expect(await store(nil, clock: clock).replayCheckNow(.pastReset) { await recorder.record($0) })
        let landed = await recorder.steps.compactMap(\.receipt.lastLanded)
        #expect(!landed.isEmpty && landed.allSatisfy(\.live))
        let refreshed = try #require(await recorder.steps.last?.snapshot?.content)
        let windows = refreshed.providers.flatMap(\.accounts).flatMap(\.widgetWindows)
        #expect(windows.allSatisfy { CompanionFreshnessRule.pastResetTime($0, at: clock.now) == nil })
    }

    /// KTD14.1: requests go out only when the winner is v4, so these replay nothing.
    @Test(arguments: [CompanionDemoVariant.oldMac, .paused, .waiting])
    func variantsWithoutAV4MacReplayNothing(_ variant: CompanionDemoVariant) async {
        let clock = DemoReplayClock(Self.start)
        let recorder = DemoStepRecorder()
        #expect(!variant.supportsCheckNow)
        #expect(await !store(nil, clock: clock).replayCheckNow(variant) { await recorder.record($0) })
        #expect(await recorder.steps.isEmpty)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func aCancelledPullStopsReplaying() async {
        let clock = DemoReplayClock(Self.start)
        let recorder = DemoStepRecorder()
        let demo = store(nil, clock: clock)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await demo.replayCheckNow(.multiAccount) { await recorder.record($0) }
        }
        #expect(await !task.value)
        #expect(await recorder.steps.isEmpty)
    }
}

