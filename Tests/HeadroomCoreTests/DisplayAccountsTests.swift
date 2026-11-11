import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U7 (KTD8, KTD12, R6, R12, R15): one display projection gives every
/// surface the same rows, in the same order, with the same main account, while
/// `accounts(for:)` stays the engine list.
@MainActor
struct DisplayAccountsTests {
    private let a = "aaaaaaaa-0000-4000-8000-000000000001"
    private let b = "bbbbbbbb-0000-4000-8000-000000000002"

    // MARK: Pure resolver

    private func summary(_ id: String, label: String, hidden: Bool = false) -> RememberedAccountSummary {
        RememberedAccountSummary(
            id: AccountID(id), providerID: .codex, label: label, email: nil,
            snapshot: nil, lastReadAt: nil, isHidden: hidden
        )
    }

    private let engine = [
        ProviderAccount.builtIn(for: .codex),
        ProviderAccount(id: AccountID("side"), providerID: .codex, label: "Side"),
    ]

    /// Covers AE5.
    @Test func withNothingRememberedTheProjectionIsTheEngineList() {
        let projection = DisplayAccountsResolver.resolve(providerID: .codex, engine: engine, remembered: [])
        #expect(projection.accounts == engine)
        #expect(projection.rows.allSatisfy { $0.kind == .engine })
        #expect(projection.primaryKey == engine[0].key)
        #expect(projection.mergeMap.isEmpty)
    }

    @Test func rememberedRowsFollowTheEngineRowsInStoredOrder() {
        let projection = DisplayAccountsResolver.resolve(
            providerID: .codex, engine: engine,
            remembered: [summary("r2", label: "Work"), summary("r1", label: "Old")]
        )
        #expect(projection.rows.map(\.label) == ["Main", "Side", "Work", "Old"])
        #expect(projection.rows.map(\.kind) == [.engine, .engine, .remembered, .remembered])
        #expect(projection.rows[2].account.isBuiltIn == false)
        #expect(projection.primaryKey == engine[0].key)
    }

    /// R12: only a probed row offers retry, sign-in or recovery; every surface reads this.
    @Test func onlyAnEngineRowOffersRetry() {
        #expect(DisplayAccountKind.engine.offersRetry)
        #expect(DisplayAccountKind.remembered.offersRetry == false)
    }

    @Test func aHiddenRememberedRowIsLeftOut() {
        let projection = DisplayAccountsResolver.resolve(
            providerID: .codex, engine: engine,
            remembered: [summary("r1", label: "Work", hidden: true), summary("r2", label: "Old")]
        )
        #expect(projection.rows.map(\.label) == ["Main", "Side", "Old"])
    }

    @Test func theDisplayPrimaryIsNeverARememberedRow() {
        let projection = DisplayAccountsResolver.resolve(
            providerID: .codex, engine: [], remembered: [summary("r1", label: "Work")]
        )
        #expect(projection.primaryKey == nil)
        #expect(projection.isEnginePrimary(AccountKey(providerID: .codex, accountID: AccountID("r1"))) == false)
    }

    @Test func aRememberedRowThatCollidesWithAnEngineKeyOrAnotherProviderIsDropped() {
        let other = RememberedAccountSummary(
            id: AccountID("r9"), providerID: .claude, label: "Elsewhere", email: nil,
            snapshot: nil, lastReadAt: nil, isHidden: false
        )
        let projection = DisplayAccountsResolver.resolve(
            providerID: .codex, engine: engine,
            remembered: [summary("side", label: "Clash"), other, summary("r1", label: "Work"), summary("r1", label: "Twice")]
        )
        #expect(projection.rows.map(\.label) == ["Main", "Side", "Work"])
    }

    /// The map's shape for U10: a merged engine row is hidden, and the display primary
    /// and the engine primary follow it to the row that stands for it.
    @Test func aMergedEngineRowIsHiddenAndThePrimaryFollowsTheMap() {
        let merged = [engine[0].key: engine[1].key]
        let projection = DisplayAccountsResolver.resolve(
            providerID: .codex, engine: engine, remembered: [], mergeMap: merged
        )
        #expect(projection.rows.map(\.label) == ["Side"])
        #expect(projection.primaryKey == engine[1].key)
        #expect(projection.isEnginePrimary(engine[0].key))
        #expect(projection.isEnginePrimary(engine[1].key))
    }

    // MARK: Store

    private func workThenPersonal(_ rig: DefaultLoginRig) async -> AccountKey {
        await rig.read(rig.reading(a, weeklyUsed: 90))
        rig.store.renameAccount(rig.key, to: "Work")
        rig.advance(120)
        await rig.read(rig.reading(b, weeklyUsed: 3))
        return rig.store.rememberedAccounts(for: .codex).first!.key
    }

    /// Covers AE5: a default login that never changes sees the engine list everywhere.
    @Test func aStoreWhoseLoginNeverChangesProjectsItsEngineList() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        rig.extras[0].set(rig.reading("side"))
        await rig.read(rig.reading(a))
        let projection = rig.store.displayProjection(for: .codex)
        #expect(projection.accounts == rig.store.accounts(for: .codex))
        #expect(projection.primaryKey == rig.store.primaryAccount(for: .codex)?.key)
        #expect(projection.mergeMap.isEmpty)
        #expect(rig.store.providerMenuBarMeter(for: .codex).sourceAccountKey == rig.key)
        #expect(rig.store.refreshReceiptTitle(for: rig.key) == "Codex Main")
    }

    @Test func oneRememberedAccountFollowsTheEngineRows() async {
        let rig = DefaultLoginRig()
        let work = await workThenPersonal(rig)

        #expect(rig.store.accounts(for: .codex).map(\.key) == [rig.key])
        let rows = rig.store.displayAccounts(for: .codex)
        #expect(rows.map(\.key) == [rig.key, work])
        #expect(rows.map(\.kind) == [.engine, .remembered])
        #expect(rows.map(\.label) == ["Main", "Work"])
        #expect(rig.store.displayPrimaryKey(for: .codex) == rig.key)
        // The menu bar and the widgets follow the engine main account.
        #expect(rig.store.providerMenuBarMeter(for: .codex).sourceAccountKey == rig.key)
        #expect(rig.store.snapshot(for: .codex).windows.last?.utilization == 3)
        // The receipt names accounts once the provider shows several rows.
        #expect(rig.store.refreshReceiptTitle(for: rig.key) == "Codex Main")
        #expect(rig.store.refreshReceiptTitle(for: work) == "Codex Work")
        // The row draws its last reading.
        #expect(rig.store.snapshot(for: work).windows.last?.utilization == 90)
        #expect(rig.store.snapshot(for: work).freshness != .live)
    }

    @Test func aReminderNamesTheMainAccountOnceARememberedRowIsShown() async {
        let rig = DefaultLoginRig()
        _ = await workThenPersonal(rig)
        rig.advance(600)
        await rig.read(rig.dueReading(b))
        let posted = rig.poster.posted
        #expect(posted.count == 1)
        #expect(posted.contains { ($0.title + $0.body).contains("(Main)") })
    }

    @Test func aHiddenRememberedAccountIsAbsentFromEveryConsumer() async {
        let rig = DefaultLoginRig()
        let work = await workThenPersonal(rig)
        #expect(rig.store.removeRememberedAccount(work))

        #expect(rig.store.displayAccounts(for: .codex).map(\.key) == [rig.key])
        #expect(rig.store.snapshot(for: work).freshness == .pending)
        #expect(rig.store.snapshot(for: work).windows.isEmpty)
        #expect(rig.store.refreshReceiptTitle(for: rig.key) == "Codex")
        #expect(rig.store.displayProjection(for: .codex).row(for: work) == nil)
    }

    @Test func makeMainIsNotOfferedForARememberedRowAndTheMainPointerNeverNamesOne() async throws {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        rig.extras[0].set(rig.reading("side"))
        let work = await workThenPersonal(rig)

        #expect(rig.store.canPromoteAccount(work) == false)
        #expect(rig.store.promoteAccount(work) == false)
        #expect(rig.store.schedulerIsPrimary(work) == false)
        #expect(rig.store.schedulerIsEligible(work) == false)
        #expect(rig.store.displayPrimaryKey(for: .codex) == rig.key)

        // A pointer that names the remembered id is dangling: the canonical order stands.
        let pointer = try JSONEncoder().encode([ProviderID.codex: work.accountID])
        rig.defaults.set(pointer, forKey: "primaryAccounts.v1")
        rig.launch()
        #expect(rig.store.displayPrimaryKey(for: .codex) == rig.key)
        #expect(rig.store.displayAccounts(for: .codex).first?.kind == .engine)
        #expect(rig.store.displayAccounts(for: .codex).map(\.key).contains(work))
    }

    @Test func stopTrackingTheBuiltInIsRefusedWhenOnlyRememberedRowsExistBesideIt() async {
        let rig = DefaultLoginRig()
        _ = await workThenPersonal(rig)
        #expect(rig.store.displayAccounts(for: .codex).count == 2)
        #expect(rig.store.canStopTrackingBuiltInAccount(for: .codex) == false)
        #expect(await rig.store.stopTrackingBuiltInAccount(for: .codex) == .notAllowed)
        #expect(rig.store.accounts(for: .codex).map(\.key) == [rig.key])
    }

    @Test func aRememberedRowDoesNotCountTowardAddAccountCapacity() async {
        let rig = DefaultLoginRig()
        _ = await workThenPersonal(rig)
        let before = rig.store.accounts(for: .codex).count
        #expect(before == 1)
        #expect(rig.store.canAddAccount(for: .codex))
    }

    @Test func renamingARememberedRowWritesTheRecordStoreNotTheRegistry() async {
        let rig = DefaultLoginRig()
        let work = await workThenPersonal(rig)
        let registryBefore = rig.defaults.data(forKey: "providerAccounts.v1")
        let recordsBefore = rig.defaults.data(forKey: "defaultLoginRecords.v1")

        #expect(rig.store.renameRememberedAccount(work, to: "Esper Labs"))

        #expect(rig.defaults.data(forKey: "providerAccounts.v1") == registryBefore)
        #expect(rig.defaults.data(forKey: "defaultLoginRecords.v1") != recordsBefore)
        #expect(rig.store.accounts(for: .codex).map(\.label) == ["Main"])
        #expect(rig.store.displayAccounts(for: .codex).map(\.label) == ["Main", "Esper Labs"])
        #expect(rig.store.refreshReceiptTitle(for: work) == "Codex Esper Labs")
    }

    @Test func aRememberedAccountAppearingRenamedAndRemovedExportsOnceEach() async throws {
        let rig = DefaultLoginRig(countsPhoneExports: true)
        await rig.read(rig.reading(a, weeklyUsed: 90))
        rig.advance(120)
        let phone = try #require(rig.phone)

        // One reading, outside a full refresh: the merge's own export is the only one.
        rig.primary.set(rig.reading(b))
        var count = phone.captures.count
        await rig.store.refreshAccount(rig.key)
        #expect(rig.store.rememberedAccounts(for: .codex).count == 1)
        #expect(phone.captures.count == count + 1)

        let work = rig.store.rememberedAccounts(for: .codex)[0].key
        count = phone.captures.count
        #expect(rig.store.renameRememberedAccount(work, to: "Work"))
        #expect(phone.captures.count == count + 1)

        count = phone.captures.count
        #expect(rig.store.removeRememberedAccount(work))
        #expect(phone.captures.count == count + 1)

        // A refused rename and a second remove (already hidden, so U5 commits nothing)
        // export nothing.
        count = phone.captures.count
        #expect(rig.store.renameRememberedAccount(work, to: "  ") == false)
        _ = rig.store.removeRememberedAccount(work)
        #expect(phone.captures.count == count)
    }

    // MARK: Aging (KTD10, U6 mode)

    @Test func aRememberedRowPastItsResetCarriesNoNumberAndOneBeforeItIsStaleFromItsRead() async throws {
        let rig = DefaultLoginRig()
        await rig.read(rig.reading(a, weeklyUsed: 90))
        let workCapture = rig.clock.now()
        rig.advance(120)
        await rig.read(rig.reading(b))
        let work = try #require(rig.store.rememberedAccounts(for: .codex).first).key

        // Before either reset: both windows last-known, from the original read.
        var windows = rig.store.snapshot(for: work).windows
        #expect(windows.map(\.freshness) == [.stale(observedAt: workCapture), .stale(observedAt: workCapture)])

        // Five hours on, the five-hour window has reset; it ages when the popover opens.
        rig.advance(5 * 3_600)
        #expect(rig.store.snapshot(for: work).windows.first?.freshness.isUnavailable == false)
        rig.store.refreshOnPopoverOpen()
        windows = rig.store.snapshot(for: work).windows
        let fiveHour = try #require(windows.first { $0.kind == .fiveHour })
        let weekly = try #require(windows.first { $0.kind == .weekly })
        #expect(fiveHour.freshness.isUnavailable)
        #expect(UsagePercentageMode.remaining.displayedPercentage(for: fiveHour) == nil)
        #expect(weekly.freshness == .stale(observedAt: workCapture))
        #expect(UsagePercentageMode.remaining.displayedPercentage(for: weekly) == 10)

        // Past the weekly reset, an engine wake ages it too; no window is dropped.
        rig.advance(6 * 24 * 3_600)
        rig.store.engineDidWake()
        windows = rig.store.snapshot(for: work).windows
        #expect(windows.count == 2)
        #expect(windows.allSatisfy { $0.freshness.isUnavailable })
        #expect(rig.store.snapshot(for: work).freshness != .pending)
    }

    @Test func aRelaunchAgesTheRememberedRowsBeforeAnyRead() async throws {
        let rig = DefaultLoginRig()
        await rig.read(rig.reading(a, weeklyUsed: 90))
        rig.advance(120)
        await rig.read(rig.reading(b))
        rig.advance(5 * 3_600)
        rig.launch()
        let work = try #require(rig.store.rememberedAccounts(for: .codex).first).key
        let fiveHour = try #require(rig.store.snapshot(for: work).windows.first { $0.kind == .fiveHour })
        #expect(fiveHour.freshness.isUnavailable)
    }
}
