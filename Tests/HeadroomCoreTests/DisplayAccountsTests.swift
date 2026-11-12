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

    // MARK: One account, one row: pure planner (U10, KTD11)

    private func input(
        _ id: AccountID, builtIn: Bool = false, identity: AccountIdentity?,
        freshness: Freshness? = .live, setup: Bool = false
    ) -> DisplayMergeInput {
        DisplayMergeInput(
            key: AccountKey(providerID: identity?.providerID ?? .codex, accountID: id),
            isBuiltIn: builtIn, identity: identity, freshness: freshness, isInSetup: setup
        )
    }

    private var gmail: AccountIdentity { DefaultLoginRig.identity("gmail") }

    @Test func theBuiltInMergesIntoTheOneExtraWithItsStrongIdentity() {
        let rows = [input(.primary, builtIn: true, identity: gmail), input(AccountID("e"), identity: gmail)]
        #expect(DisplayMergePlanner.mergeMap(rows) == [rows[0].key: rows[1].key])
    }

    @Test func twoMatchingExtrasDoNotMerge() {
        let rows = [
            input(.primary, builtIn: true, identity: gmail),
            input(AccountID("e"), identity: gmail),
            input(AccountID("f"), identity: gmail),
        ]
        #expect(DisplayMergePlanner.mergeMap(rows).isEmpty)
    }

    @Test func anExtraThatIsNotReadableDoesNotMerge() {
        let builtIn = input(.primary, builtIn: true, identity: gmail)
        for freshness: Freshness? in [.stale(.providerSetup(.codexAuthAbsent)), .pending, nil] {
            let rows = [builtIn, input(AccountID("e"), identity: gmail, freshness: freshness)]
            #expect(DisplayMergePlanner.mergeMap(rows).isEmpty, "\(String(describing: freshness))")
        }
        // A transient failure keeps the row's numbers, so the merge holds through it.
        let blip = [builtIn, input(AccountID("e"), identity: gmail, freshness: .stale(.transient("blip")))]
        #expect(DisplayMergePlanner.mergeMap(blip).count == 1)
    }

    @Test func aSetupOnEitherRowHoldsTheMerge() {
        let onExtra = [input(.primary, builtIn: true, identity: gmail), input(AccountID("e"), identity: gmail, setup: true)]
        let onBuiltIn = [input(.primary, builtIn: true, identity: gmail, setup: true), input(AccountID("e"), identity: gmail)]
        #expect(DisplayMergePlanner.mergeMap(onExtra).isEmpty)
        #expect(DisplayMergePlanner.mergeMap(onBuiltIn).isEmpty)
    }

    @Test func aWeakOrUnknownIdentityNeverMerges() {
        let grok = AccountIdentity.grok(email: "one@example.com")!
        #expect(DisplayMergePlanner.mergeMap([
            input(.primary, builtIn: true, identity: grok), input(AccountID("e"), identity: grok),
        ]).isEmpty)
        #expect(DisplayMergePlanner.mergeMap([
            input(.primary, builtIn: true, identity: nil), input(AccountID("e"), identity: nil),
        ]).isEmpty)
        // A different account on the extra is not a match.
        #expect(DisplayMergePlanner.mergeMap([
            input(.primary, builtIn: true, identity: gmail), input(AccountID("e"), identity: DefaultLoginRig.identity("work")),
        ]).isEmpty)
    }

    @Test func theSetupStatesThatHoldTheMergeAreKTD11s() {
        let held: [SetupSessionState] = [
            .preparing, .waiting(attempt: 1), .verifying, .blockedByOpenHandoff,
            .blockedByProviderLogin(providerID: .codex, active: AccountKey(providerID: .codex, accountID: .primary)),
            .connected, .removing,
        ]
        let settled: [SetupSessionState] = [.idle, .failed(.stagingFailed), .cancelled, .removalFailed, .removed]
        #expect(held.allSatisfy { $0.holdsDisplayMerge })
        #expect(!settled.contains { $0.holdsDisplayMerge })
    }

    // MARK: One account, one row: store (U10)

    private var extraKey: AccountKey { AccountKey(providerID: .codex, accountID: AccountID("account 2")) }

    /// Mock scenario B, steps 1 and 2 (AE4): the built-in "Esper Labs" reads the work
    /// account, "Account 2" has its own sign-in to gmail, then the default login moves to
    /// gmail. The built-in's gmail reading is 32% used and E's 31%, so a test can tell
    /// whose reading a surface shows.
    private func mergedRig(countsPhoneExports: Bool = false) async -> DefaultLoginRig {
        let rig = DefaultLoginRig(extraLabels: ["Account 2"], countsPhoneExports: countsPhoneExports)
        rig.extras[0].set(rig.reading("gmail", weeklyUsed: 31))
        await rig.read(rig.reading("work", weeklyUsed: 90))
        rig.store.renameAccount(rig.key, to: "Esper Labs")
        rig.advance(120)
        await rig.read(rig.reading("gmail", weeklyUsed: 32))
        return rig
    }

    /// Covers AE4.
    @Test func theDefaultLoginAndAMatchingExtraShowAsOneRow() async {
        let rig = await mergedRig()
        let rows = rig.store.displayAccounts(for: .codex)
        #expect(rows.map(\.label) == ["Account 2", "Esper Labs"])
        #expect(rows.map(\.kind) == [.engine, .remembered])
        #expect(rows[0].key == extraKey)
        #expect(rig.store.snapshot(for: rows[0].key).freshness == .live)
        #expect(rig.store.snapshot(for: rows[0].key).windows.last?.utilization == 31)
        // Esper Labs holds the work account's last reading, dimmed.
        #expect(rig.store.snapshot(for: rows[1].key).windows.last?.utilization == 90)
        #expect(rig.store.snapshot(for: rows[1].key).freshness != .live)
        // Display-only: the built-in is still an engine row and is still read (KTD11).
        #expect(rig.store.accounts(for: .codex).map(\.key) == [rig.key, extraKey])
        #expect(rig.store.schedulerIsEligible(rig.key))
        #expect(rig.store.displayProjection(for: .codex).mergeMap == [rig.key: extraKey])
    }

    @Test func aPermanentlyStaleExtraShowsBothRows() async {
        let rig = await mergedRig()
        rig.extras[0].set(rig.signedOut)
        await rig.read(rig.reading("gmail", weeklyUsed: 32))
        #expect(rig.store.displayAccounts(for: .codex).map(\.key).prefix(2) == [rig.key, extraKey])
        #expect(rig.store.displayProjection(for: .codex).mergeMap.isEmpty)
        // A transient failure on E keeps the merge, since E keeps its numbers.
        rig.extras[0].set(rig.reading("gmail", weeklyUsed: 31))
        await rig.read(rig.reading("gmail", weeklyUsed: 32))
        rig.extras[0].set(rig.blip)
        await rig.read(rig.reading("gmail", weeklyUsed: 32))
        #expect(rig.store.displayProjection(for: .codex).mergeMap == [rig.key: extraKey])
    }

    @Test func aSetupOnEitherRowShowsBothRowsAndItsEndMergesWithOneExport() async throws {
        let rig = await mergedRig(countsPhoneExports: true)
        let phone = try #require(rig.phone)
        let setup = SuspendedSetup()
        rig.store.attachSetupCoordinator(setup.coordinator)
        #expect(rig.store.displayAccounts(for: .codex).count == 2)

        for key in [extraKey, rig.key] {
            let account = try #require(rig.store.accounts(for: .codex).first { $0.key == key })
            setup.coordinator.begin(for: account)
            #expect(setup.coordinator.state(for: key) == .preparing)
            #expect(rig.store.displayAccounts(for: .codex).map(\.key).prefix(2) == [rig.key, extraKey], "\(key)")

            let (captures, widgets) = (phone.captures.count, rig.widgets.exports.count)
            setup.coordinator.cancel(key)
            #expect(rig.store.displayAccounts(for: .codex).map(\.key) .first == extraKey, "\(key)")
            #expect(phone.captures.count == captures + 1, "\(key)")
            #expect(rig.widgets.exports.count == widgets + 1, "\(key)")
            setup.release()
            await Task.yield()
        }
    }

    @Test func removingTheExtraWhileMergedShowsTheBuiltInInTheSameTurn() async throws {
        let rig = await mergedRig(countsPhoneExports: true)
        let phone = try #require(rig.phone)
        let before = phone.captures.count
        #expect(await rig.store.removeAccount(extraKey) == .removed)

        let rows = rig.store.displayAccounts(for: .codex)
        #expect(rows.map(\.key).first == rig.key)
        #expect(rows.first?.kind == .engine)
        #expect(rig.store.snapshot(for: rig.key).freshness == .live)
        #expect(rig.store.snapshot(for: rig.key).windows.last?.utilization == 32)
        // No capture during the removal lacked a Codex main account.
        let during = phone.captures.dropFirst(before)
        #expect(!during.isEmpty)
        #expect(during.allSatisfy { capture in
            capture.providers.first { $0.providerID == "codex" }?.mainAccount != nil
        })
        #expect(rig.store.snapshot(for: .codex).windows.last?.utilization == 32)
    }

    @Test func theDefaultLoginLeavingEsAccountUnmergesAndRemembersNothingForIt() async {
        let rig = await mergedRig()
        rig.advance(120)
        await rig.read(rig.reading("c", weeklyUsed: 5))

        let rows = rig.store.displayAccounts(for: .codex)
        #expect(rows.map(\.key).prefix(2) == [rig.key, extraKey])
        #expect(rows.map(\.label) == ["Main", "Account 2", "Esper Labs"])
        #expect(rig.store.snapshot(for: rig.key).windows.last?.utilization == 5)
        // gmail is still read by Account 2, so it gets no remembered row (KTD9).
        #expect(!rig.rows.contains { $0.identity == DefaultLoginRig.identity("gmail") })
        #expect(rig.store.rememberedAccounts(for: .codex).map(\.label) == ["Esper Labs"])
    }

    @Test func theDefaultLoginSigningOutWhileMergedShowsTheBuiltInsSignInState() async {
        let rig = await mergedRig()
        await rig.read(rig.signedOut)
        let rows = rig.store.displayAccounts(for: .codex)
        #expect(rows.map(\.key).prefix(2) == [rig.key, extraKey])
        guard case .stale(let reason) = rig.store.snapshot(for: rig.key).freshness else {
            Issue.record("the built-in should show its sign-in state")
            return
        }
        #expect(reason.isPermanent)
        #expect(rig.store.snapshot(for: extraKey).freshness == .live)
        #expect(rig.store.snapshot(for: extraKey).windows.last?.utilization == 31)
    }

    @Test func aWeakIdentityNeverMergesInTheStore() async throws {
        let suite = "headroom.display-merge.grok.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let builtIn = ScriptedAccountProvider(id: .grok)
        let extra = ScriptedAccountProvider(id: .grok, accountID: AccountID("side"))
        let identity = AccountIdentity.grok(email: "one@example.com")!
        let start = DefaultLoginRig.start
        for provider in [builtIn, extra] {
            provider.set(UsageSnapshot(
                providerID: .grok,
                windows: [UsageWindow(kind: .weekly, utilization: 10, resetsAt: DefaultLoginRig.start.addingTimeInterval(86_400))],
                planLabel: nil, accountEmail: "one@example.com", capturedAt: DefaultLoginRig.start, freshness: .live,
                identity: .known(identity)
            ))
        }
        let preferences = Preferences(defaults: defaults)
        preferences.setSurfaceEnabled(true, for: UsageSurface.subscription(for: .grok)!)
        let store = UsageStore(
            providers: [builtIn, extra],
            preferences: preferences,
            accounts: [.builtIn(for: .grok), ProviderAccount(id: AccountID("side"), providerID: .grok, label: "Side")],
            defaultLoginRecords: DefaultLoginRecordStore(defaults: defaults),
            now: { start }
        )
        await store.refreshAll()
        #expect(store.defaultLoginState?.slot(for: AccountKey(providerID: .grok, accountID: .primary))?.binding == identity)
        #expect(store.displayAccounts(for: .grok).count == 2)
        #expect(store.displayProjection(for: .grok).mergeMap.isEmpty)
    }

    @Test func whileMergedEveryMainSurfaceShowsTheExtra() async throws {
        let rig = await mergedRig(countsPhoneExports: true)
        let phone = try #require(rig.phone)
        #expect(rig.store.displayPrimaryKey(for: .codex) == extraKey)
        #expect(rig.store.providerMenuBarMeter(for: .codex).sourceAccountKey == extraKey)
        #expect(rig.store.snapshot(for: .codex).windows.last?.utilization == 31)
        let widget = try #require(rig.widgets.exports.last?.providers.first { $0.id == "codex" })
        #expect(widget.windows.last?.roundedPercentRemaining == 69)
        let capture = try #require(phone.last)
        #expect(capture.v3.providers.first { $0.id == "codex" }?.windows.last?.roundedPercentRemaining == 69)
        #expect(capture.providers.first { $0.providerID == "codex" }?.mainAccount?.id == "account 2")

        // E's own merge reloads the Mac widget, as the main account's merge does.
        let widgets = rig.widgets.exports.count
        await rig.store.refreshAccount(extraKey)
        #expect(rig.widgets.exports.count == widgets + 1)
        // The built-in's merge does not: it shows nowhere.
        let afterExtra = rig.widgets.exports.count
        await rig.store.refreshAccount(rig.key)
        #expect(rig.widgets.exports.count == afterExtra)
    }

    @Test func theMergedRowCarriesTheMainBadgeAndIsNotOfferedMakeMain() async {
        let rig = await mergedRig()
        #expect(rig.store.displayPrimaryKey(for: .codex) == extraKey)
        #expect(rig.store.canPromoteAccount(extraKey) == false)
        #expect(rig.store.promoteAccount(extraKey) == false)
        // Both engine rows keep the primary lane priority (U7).
        #expect(rig.store.schedulerIsPrimary(rig.key))
        #expect(rig.store.schedulerIsPrimary(extraKey))
    }

    @Test func aMergedPairFiresOneReminder() async {
        let rig = await mergedRig()
        rig.advance(600)
        rig.extras[0].set(rig.dueReading("gmail"))
        await rig.read(rig.dueReading("gmail"))
        #expect(rig.poster.posted.count == 1)
        // It names the row that shows, not the hidden built-in.
        #expect(rig.poster.posted.contains { ($0.title + $0.body).contains("Account 2") })
    }

    /// KTD11: only the shown row reminded while merged, so the built-in takes that state
    /// when the merge ends; its next live reading posts nothing already posted.
    @Test func removingTheExtraAfterAMergedReminderDoesNotPostItAgain() async {
        let rig = await mergedRig()
        rig.advance(600)
        rig.extras[0].set(rig.dueReading("gmail"))
        await rig.read(rig.dueReading("gmail"))
        #expect(rig.poster.posted.count == 1)

        #expect(await rig.store.removeAccount(extraKey) == .removed)
        rig.advance(600)
        await rig.read(rig.dueReading("gmail"))
        #expect(rig.store.displayAccounts(for: .codex).first?.key == rig.key)
        #expect(rig.store.snapshot(for: rig.key).freshness == .live)
        #expect(rig.poster.posted.count == 1)
        #expect(rig.ledger.entry(for: rig.key, windowID: WindowKind.weekly.persistentID) != nil)
    }

    @Test func anExtraLapsingAfterAMergedReminderDoesNotPostItAgain() async {
        let rig = await mergedRig()
        rig.advance(600)
        rig.extras[0].set(rig.dueReading("gmail"))
        await rig.read(rig.dueReading("gmail"))
        #expect(rig.poster.posted.count == 1)

        rig.extras[0].set(rig.signedOut)
        rig.advance(600)
        await rig.read(rig.dueReading("gmail"))
        #expect(rig.store.displayProjection(for: .codex).mergeMap.isEmpty)
        // A second read, so the built-in is evaluated as a shown row at least once.
        rig.advance(600)
        await rig.read(rig.dueReading("gmail"))
        #expect(rig.store.displayAccounts(for: .codex).first?.key == rig.key)
        #expect(rig.poster.posted.count == 1)
    }

    /// The hand-over is for the same account only: a built-in reset while merged keeps
    /// none of the shown row's reminder state.
    @Test func aResetBuiltInTakesNoReminderStateFromTheMergedRow() async {
        let rig = await mergedRig()
        rig.advance(600)
        rig.extras[0].set(rig.dueReading("gmail"))
        await rig.read(rig.dueReading("gmail"))
        #expect(rig.poster.posted.count == 1)

        rig.store.invalidateUsageForAccountReset(rig.key)
        #expect(rig.ledger.entry(for: rig.key, windowID: WindowKind.weekly.persistentID) == nil)
        #expect(rig.ledger.entry(for: extraKey, windowID: WindowKind.weekly.persistentID) != nil)
    }

    @Test func resettingAMergedBuiltInShowsItsRowAgain() async {
        let rig = await mergedRig()
        #expect(!rig.store.displayProjection(for: .codex).mergeMap.isEmpty)
        rig.store.invalidateUsageForAccountReset(rig.key)
        #expect(rig.store.displayProjection(for: .codex).mergeMap.isEmpty)
        #expect(rig.store.displayMergeMaps.isEmpty)
        #expect(rig.store.displayAccounts(for: .codex).map(\.key).prefix(2) == [rig.key, extraKey])
    }

    /// KTD11: E alone acknowledges banked resets while merged.
    @Test func whileMergedOnlyTheShownRowClaimsAndLowersBankedResets() async {
        let rig = await mergedRig()
        rig.acknowledgements.restore(count: 3, for: rig.key)
        rig.extras[0].set(rig.reading("gmail", weeklyUsed: 31, banked: 2))
        await rig.read(rig.reading("gmail", weeklyUsed: 32, banked: 1))
        #expect(rig.store.displayProjection(for: .codex).mergeMap == [rig.key: extraKey])
        // The built-in's merge did not lower its acknowledgement to 1.
        #expect(rig.acknowledgements.acknowledgedCount(for: rig.key) == 3)
        #expect(rig.store.claimBankedResetReveal(for: rig.key, currentCount: 4) == false)
        #expect(rig.acknowledgements.acknowledgedCount(for: rig.key) == 3)
        #expect(rig.store.claimBankedResetReveal(for: extraKey, currentCount: 2) == true)
        #expect(rig.acknowledgements.acknowledgedCount(for: extraKey) == 2)
    }

    @Test func aMergedBuiltInsRefreshReceiptIsTitledAsTheShownRow() async {
        let rig = await mergedRig()
        #expect(rig.store.refreshReceiptTitle(for: rig.key) == rig.store.refreshReceiptTitle(for: extraKey))
        #expect(rig.store.refreshReceiptTitle(for: rig.key).contains("Account 2"))
    }

    @Test func aMergedBuiltInsProbeDoesNotSloshTheMenuBar() async {
        let rig = await mergedRig()
        rig.store.schedulerProbeDidStart(rig.key)
        #expect(rig.store.menuBarUpdatingProviders.isEmpty)
        rig.store.schedulerProbeDidEnd(rig.key)
        rig.store.schedulerProbeDidStart(extraKey)
        #expect(rig.store.menuBarUpdatingProviders == [.codex])
        rig.store.schedulerProbeDidEnd(extraKey)
    }

    /// Covers AE5 and R15: two accounts kept separate on purpose never merge.
    @Test func withNoIdentityMatchNothingMerges() async {
        let rig = DefaultLoginRig(extraLabels: ["Work"])
        rig.extras[0].set(rig.reading("work"))
        await rig.read(rig.reading("personal"))
        rig.advance(600)
        await rig.read(rig.reading("personal"))
        #expect(rig.store.displayMergeMaps.isEmpty)
        #expect(rig.store.displayAccounts(for: .codex).map(\.account) == rig.store.accounts(for: .codex))
        #expect(rig.store.displayPrimaryKey(for: .codex) == rig.key)
    }

    @Test func aRelaunchWhileMergedComesBackMergedWithNoExport() async throws {
        let rig = await mergedRig(countsPhoneExports: true)
        let phone = try #require(rig.phone)
        let (captures, widgets) = (phone.captures.count, rig.widgets.exports.count)
        rig.launch()
        #expect(rig.store.displayAccounts(for: .codex).map(\.label) == ["Account 2", "Esper Labs"])
        #expect(rig.store.displayPrimaryKey(for: .codex) == extraKey)
        #expect(phone.captures.count == captures)
        #expect(rig.widgets.exports.count == widgets)
    }

    @Test func thePhoneCarriesOneAccountForTheMergedPairWithNoIdentity() async throws {
        let rig = await mergedRig(countsPhoneExports: true)
        let capture = try #require(rig.phone?.last)
        let codex = try #require(capture.providers.first { $0.providerID == "codex" })
        let main = try #require(codex.mainAccount)
        #expect(main.id == "account 2")
        #expect(main.title == "Account 2")
        #expect(codex.extraAccounts.map(\.title) == ["Esper Labs"])
        #expect(codex.extraAccounts.allSatisfy { $0.isRemembered })
        let accounts = [main] + codex.extraAccounts
        #expect(!accounts.contains { $0.id == AccountID.primary.raw })
        let json = String(decoding: try JSONEncoder().encode(accounts), as: UTF8.self)
        for account in ["gmail", "work"] {
            #expect(!json.contains(DefaultLoginRig.identity(account).digest))
        }
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

/// A setup coordinator whose preparation waits until the test releases it, so a session
/// sits in `.preparing` for as long as a test needs it to.
@MainActor
final class SuspendedSetup {
    private var waiting: [CheckedContinuation<SetupPreparationResult, Never>] = []

    private(set) lazy var coordinator = SetupSessionCoordinator(
        prepare: { [weak self] _, _, _ in
            await withCheckedContinuation { continuation in
                guard let self else { return continuation.resume(returning: .failure(.stagingFailed)) }
                self.waiting.append(continuation)
            }
        },
        open: { _ in .success(()) },
        accountExists: { _ in true },
        requestRefresh: { _ in }
    )

    func release() {
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(returning: .failure(.stagingFailed)) }
    }
}
