import Foundation
import Testing
@testable import HeadroomCore

@MainActor
struct ReprintSourceIdentityTests {
    private func identity(_ store: UsageStore) -> ReprintSourceIdentity {
        ReprintSourceIdentity(meters: store.menuBarMeters, automatic: true,
            currentMains: Dictionary(uniqueKeysWithValues: store.providerOrder.compactMap { id in
                store.primaryAccount(for: id).map { (id, $0.key) }
            }))
    }

    @Test func automaticIgnoresSummaryWinnerAndExplicitPreservesShownOrder() {
        let claude = AccountKey(providerID: .claude, accountID: .primary)
        let codex = AccountKey(providerID: .codex, accountID: .primary)
        func meter(_ id: ProviderID, key: AccountKey?) -> MenuBarMeter {
            MenuBarMeter(summary: .init(text: "50%", providerID: id, detail: nil, isNeutral: false), fill: 0.5, sourceAccountKey: key)
        }
        let mains: [ProviderID: AccountKey] = [.codex: codex, .claude: claude]
        let first = ReprintSourceIdentity(meters: [meter(.claude, key: nil)], automatic: true, currentMains: mains)
        let winnerChanged = ReprintSourceIdentity(meters: [meter(.codex, key: nil)], automatic: true,
            currentMains: [.claude: claude, .codex: codex])
        #expect(first == winnerChanged)
        #expect(first.keys == [claude, codex])
        let explicit = ReprintSourceIdentity(meters: [meter(.codex, key: codex), meter(.claude, key: claude)],
            automatic: false, currentMains: mains)
        #expect(explicit.keys == [codex, claude])
        #expect(explicit != ReprintSourceIdentity(meters: [meter(.claude, key: claude), meter(.codex, key: codex)],
            automatic: false, currentMains: mains))
    }

    @Test func automaticSourceChangesWhenPendingMainIsDetachedDuringSpend() async throws {
        let anchor = Date(timeIntervalSince1970: 2_000_000_000)
        let clock = MutableDateSource(anchor)
        let defaults = UserDefaults(suiteName: "headroom.footer-sources.\(UUID())")!
        let prefs = Preferences(defaults: defaults)
        prefs.menuBarFillSource = .auto
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)
        let accounts = [ProviderAccount.builtIn(for: .claude),
            ProviderAccount(id: AccountID("backup"), providerID: .claude, label: "Backup")]
        let registry = AccountRegistry(defaults: defaults)
        registry.seed(accounts)
        let probes = accounts.map { account in
            LaneProbe(id: .claude, accountID: account.id, lane: .concurrent, order: ProbeOrder(), result: {
                UsageProviderFetchResult(snapshot: UsageSnapshot(providerID: .claude,
                    windows: [UsageWindow(kind: .weekly, utilization: 30, resetsAt: anchor.addingTimeInterval(86_400))],
                    planLabel: "Demo", capturedAt: clock.now(), freshness: .live))
            })
        }
        let spend = IdentitySpendProbe()
        let store = UsageStore(providers: probes, apiSpendProviders: [spend], preferences: prefs,
            accounts: accounts, accountRegistry: registry, accountStorage: IdentityStorage(),
            providerFactory: { _ in probes[1] }, now: clock.now)
        await store.refreshAll()
        clock.set(anchor.addingTimeInterval(2))
        store.clearExpiredUserRefreshRun(at: clock.now())
        probes[0].suspendNextFetch()
        store.refreshAccountNow(accounts[0].key)
        await probes[0].waitUntilStarted()
        clock.set(anchor.addingTimeInterval(2.3))
        spend.gate.suspendNextFetch()
        let refresh = Task { await store.refreshAPISpendOnly() }
        await spend.gate.waitUntilStarted()
        let before = identity(store)
        func recipe() -> ReprintRecipe {
            ReprintRecipe(meters: store.menuBarMeters, automatic: true,
                currentMains: [.claude: store.primaryAccount(for: .claude)!.key],
                run: store.userRefreshRun, probingAccounts: store.probingAccounts,
                probeEndTimes: store.lastProbeEndTimes, spendInFlightProviders: store.apiSpendInFlightProviders,
                visibleWork: store.visibleRefreshWork, now: clock.now())
        }
        #expect(recipe().pills.first?.ink == .ghost)
        #expect(store.menuBarMeters.map(\.sourceAccountKey) == [nil])
        #expect(await store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(store.primaryAccount(for: .claude)?.key == accounts[1].key)
        #expect(store.userRefreshRun?.entries[accounts[1].key] == nil)
        #expect(recipe().pills.first?.ink == .full)
        #expect(!recipe().isEnabled)
        #expect(store.menuBarMeters.map(\.sourceAccountKey) == [nil])
        #expect(identity(store) != before)
        probes[0].release()
        spend.gate.release()
        await refresh.value
        await store.scheduler.waitUntilLanesIdle()
    }
}

private struct IdentityStorage: AccountStorageManaging {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> { .success(()) }
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> { .success(()) }
}

private final class IdentitySpendProbe: APISpendProvider, @unchecked Sendable {
    let id = ProviderID.claude
    let displayName = "Demo spend"
    let gate = FetchGate()
    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        await gate.enter()
        return .stale(providerID: id, displayName: displayName, periodLabel: period.label, reason: .transient("Demo"))
    }
}
