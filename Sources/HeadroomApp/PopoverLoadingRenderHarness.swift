import AppKit
import SwiftUI
import HeadroomCore
#if canImport(HeadroomWidgetSharedUI)
import HeadroomWidgetSharedUI
#endif

/// KTD16: every pose comes from a suspended real request or typed setup transition.
/// The host never orders a window or invokes the screen-capture fallback.
@MainActor
enum PopoverLoadingRenderHarness {
    private enum CaptureFailure: Error { case checkpoint(String), bitmap(String) }

    static func run(to directory: URL) async throws {
        let anchor = Date(timeIntervalSince1970: 2_000_000_000)
        let owner = LoadingDemoController(clock: LoadingDemoClock(pinned: anchor), automaticCompletion: false,
            preparationDelay: .zero, waitingDelay: .zero, probeDelay: .zero, spendDelay: .zero)
        guard let defaults = UserDefaults(suiteName: "co.zantos.headroom.loading-render.\(UUID().uuidString)") else {
            throw CaptureFailure.checkpoint("isolated preferences")
        }
        let store = AppComposition.demoMultiAccountStore(scenario: .loading, controller: owner, defaults: defaults)
        owner.configure(store: store)
        do {
            try await captureFlow(store: store, owner: owner, anchor: anchor, directory: directory)
            await owner.shutdown()
        } catch {
            await owner.shutdown()
            throw error
        }
    }

    private static func wait(_ label: String, until predicate: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw CaptureFailure.checkpoint(label)
    }

    private static func recipe(_ store: UsageStore, at date: Date) -> ReprintRecipe {
        let mains = Dictionary(uniqueKeysWithValues: store.providerOrder.compactMap { id in
            store.primaryAccount(for: id).map { (id, $0.key) }
        })
        return ReprintRecipe(meters: store.menuBarMeters, automatic: store.menuBarFillSource.providerIDs == nil,
            currentMains: mains, run: store.userRefreshRun, probingAccounts: store.probingAccounts,
            probeEndTimes: store.lastProbeEndTimes, spendInFlightProviders: store.apiSpendInFlightProviders,
            visibleWork: store.visibleRefreshWork, now: date)
    }

    private static func captureFlow(store: UsageStore, owner: LoadingDemoController, anchor: Date, directory: URL) async throws {
        let mains = store.providerOrder.compactMap { store.primaryAccount(for: $0) }
        guard let claude = mains.first(where: { $0.providerID == .claude }),
              let codex = mains.first(where: { $0.providerID == .codex }),
              let pending = store.accounts(for: .claude).first(where: { $0.id == AccountID("loading-pending") }),
              let work = store.accounts(for: .claude).first(where: { $0.id == AccountID("loading-work") }) else {
            throw CaptureFailure.checkpoint("loading accounts")
        }
        var held: [LoadingDemoCheckpoint] = []
        for account in mains + [pending] {
            let gate = await owner.sources.checkpoint(for: account.key)
            await gate.hold()
            held.append(gate)
        }
        let spends = await [owner.sources.spendCheckpoint(for: .claude), owner.sources.spendCheckpoint(for: .codex)]
        for gate in spends { await gate.hold() }
        owner.refresh()
        try await wait("full refresh mains") { Set(mains.map(\.key)).isSubset(of: store.probingAccounts) }
        guard !store.probingAccounts.contains(pending.key), store.snapshot(for: pending.key).freshness == .pending else {
            throw CaptureFailure.checkpoint("pending account queued")
        }
        owner.clock.set(anchor.addingTimeInterval(0.05))
        guard recipe(store, at: owner.clock.now()).phase == .spinner else { throw CaptureFailure.checkpoint("spinner") }
        try await capture("spinner-wipe-pending-queued", store: store, date: owner.clock.now(), directory: directory)
        owner.clock.set(anchor.addingTimeInterval(0.25))
        guard recipe(store, at: owner.clock.now()).pills.allSatisfy({ $0.ink == .ghost }) else {
            throw CaptureFailure.checkpoint("ghost")
        }
        try await capture("ghost-two", store: store, date: owner.clock.now(), directory: directory)
        store.setMenuBarFillSource(.providers(Set(DemoFixture.registeredProviderOrder)))
        // Copilot plan U6/U7: every registered provider draws a pill, five at most.
        guard recipe(store, at: owner.clock.now()).pills.count == DemoFixture.registeredProviderOrder.count else {
            throw CaptureFailure.checkpoint("every provider pill")
        }
        try await capture("ghost-all-providers", store: store, date: owner.clock.now(), directory: directory)
        store.setMenuBarFillSource(.auto)
        try await capture("ghost-automatic", store: store, date: owner.clock.now(), directory: directory)
        store.setMenuBarFillSource(.both)

        await held[0].release()
        try await wait("Claude landed and pending probing") {
            store.userRefreshRun?.entries[claude.key]?.outcome == .live && store.probingAccounts.contains(pending.key)
        }
        owner.clock.set(anchor.addingTimeInterval(0.425))
        guard case .printing = recipe(store, at: owner.clock.now()).pills.first?.ink else {
            throw CaptureFailure.checkpoint("real fresh print")
        }
        try await capture("printing-pending-active", store: store, date: owner.clock.now(), directory: directory)
        for gate in held { await gate.release() }
        try await wait("spend tail") { store.apiSpendInFlightProviders == [.claude, .codex] && store.probingAccounts.isEmpty }
        owner.clock.set(anchor.addingTimeInterval(1))
        guard recipe(store, at: owner.clock.now()).phase == .spendTail else { throw CaptureFailure.checkpoint("spend tail") }
        try await capture("spend-tail-fetching", store: store, date: owner.clock.now(), directory: directory)
        for gate in spends { await gate.release() }
        try await wait("full refresh completed") { !store.isRefreshing }
        owner.clock.set(anchor.addingTimeInterval(1.25))
        guard recipe(store, at: owner.clock.now()).phase == .hold else { throw CaptureFailure.checkpoint("end hold") }
        try await capture("end-hold", store: store, date: owner.clock.now(), directory: directory)

        owner.clock.set(anchor.addingTimeInterval(3))
        let workGate = await owner.sources.checkpoint(for: work.key)
        await workGate.hold()
        store.refreshAccountNow(work.key, origin: .accountAction)
        try await wait("single account check") { store.accountActionCheckingKeys.contains(work.key) && store.probingAccounts.contains(work.key) }
        try await capture("account-check", store: store, date: owner.clock.now(), directory: directory)
        await workGate.release()
        await store.waitForAccountProbesToFinish()
        owner.clock.set(anchor.addingTimeInterval(5))
        for gate in spends { await gate.hold() }
        owner.refresh(spendOnly: true)
        try await wait("spend only") { store.apiSpendInFlightProviders == [.claude, .codex] }
        try await capture("spend-check", store: store, date: owner.clock.now(), directory: directory)
        for gate in spends { await gate.release() }
        try await wait("spend only completed") { !store.isRefreshing }

        owner.clock.set(anchor.addingTimeInterval(7))
        await owner.preparation.hold()
        SetupSessions.openSetup(for: codex, onRetry: {})
        try await wait("opening") { await owner.preparation.waiterCount == 1 }
        guard SetupSessions.state(for: codex) == .preparing else { throw CaptureFailure.checkpoint("opening state") }
        try await capture("setup-opening", store: store, date: owner.clock.now(), directory: directory)
        await owner.preparation.release()
        try await wait("user waiting") { SetupSessions.state(for: codex) == .waiting(attempt: 0) }
        owner.clock.set(anchor.addingTimeInterval(7.8))
        try await capture("setup-waiting", store: store, date: owner.clock.now(), directory: directory)
        SetupSessions.resetSetup(for: claude)
        try await wait("two setup waits") { SetupSessions.state(for: claude) == .waiting(attempt: 0) }
        try await capture("setup-dual-waiting", store: store, date: owner.clock.now(), directory: directory)
        let verification = await owner.sources.checkpoint(for: codex.key)
        await verification.hold()
        await owner.completeHandoff(codex.key)
        try await wait("final verification") { store.probingAccounts.contains(codex.key) }
        guard SetupSessions.state(for: codex) == .verifying,
              store.userRefreshRun?.entries[codex.key]?.origin == .setupCheck,
              recipe(store, at: owner.clock.now()).isEnabled else { throw CaptureFailure.checkpoint("confirming without user refresh") }
        try await capture("setup-confirming", store: store, date: owner.clock.now(), directory: directory)
        await verification.release()
        await store.waitForAccountProbesToFinish()
        print("✓ 13 real loading checkpoints × both appearances; owned requests released")
    }

    private static func capture(_ name: String, store: UsageStore, date: Date, directory: URL) async throws {
        for dark in [false, true] {
            let url = directory.appendingPathComponent("loading-\(name)-\(dark ? "dark" : "light").png")
            let root = PopoverView(store: store, onOpenSettings: {}, forceSolidSurface: true, forcedCardsHeight: 960)
                .environment(\.loadingDate, date)
                .environment(\.colorScheme, dark ? .dark : .light)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
            let hosting = NSHostingView(rootView: root)
            hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            hosting.frame = NSRect(x: 0, y: 0, width: 384, height: 1080)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = hosting.appearance
            window.contentView = hosting
            // Deliberately never ordered: bitmap capture proves layout, not native window appearance.
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(550))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw CaptureFailure.bitmap(name)
            }
            window.appearance?.performAsCurrentDrawingAppearance { hosting.cacheDisplay(in: hosting.bounds, to: rep) }
            guard let png = rep.representation(using: .png, properties: [:]), png.count > 10_000 else {
                throw CaptureFailure.bitmap(name)
            }
            try png.write(to: url)
            print("✓ \(url.lastPathComponent)")
        }
    }
}
