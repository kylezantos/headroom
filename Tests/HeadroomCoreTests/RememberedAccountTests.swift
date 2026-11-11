import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U5: an account the default login left is kept with its last reading
/// (R6), stays until the user removes it (R9), comes back when its account does (R10), and
/// can be renamed or removed (R11). Driven through `UsageStore` with a real registry,
/// reminder stores and record store.
@MainActor
struct RememberedAccountTests {
    private let a = "aaaaaaaa-0000-4000-8000-000000000001"
    private let b = "bbbbbbbb-0000-4000-8000-000000000002"
    private let c = "cccccccc-0000-4000-8000-000000000003"

    private func boundToWork(_ rig: DefaultLoginRig = DefaultLoginRig()) async -> DefaultLoginRig {
        await rig.read(rig.reading(a))
        rig.store.renameAccount(rig.key, to: "Work")
        return rig
    }

    private func remembered(_ rig: DefaultLoginRig, includingHidden: Bool = false) -> [RememberedAccountSummary] {
        rig.store.rememberedAccounts(for: .codex, includingHidden: includingHidden)
    }

    private func entry(_ rig: DefaultLoginRig, _ account: String) -> RememberedAccount? {
        rig.state.remembered.first { $0.identity == DefaultLoginRig.identity(account) }
    }

    // MARK: Creation (KTD9)

    /// Covers AE1.
    @Test func aChangeOfAccountKeepsTheOldAccountWithItsWindowsAndItsOriginalReadTime() async {
        let rig = await boundToWork()
        await rig.read(rig.reading(a, weeklyUsed: 90))
        let workCapture = rig.clock.now()

        rig.advance(120)
        await rig.read(rig.reading(b, weeklyUsed: 3))

        let rows = remembered(rig)
        #expect(rows.count == 1)
        #expect(rows.first?.label == "Work")
        #expect(rows.first?.email == "\(a)@example.com")
        #expect(rows.first?.lastReadAt == workCapture)
        #expect(rows.first?.snapshot?.capturedAt == workCapture)
        #expect(rows.first?.snapshot?.windows.map(\.utilization) == [99, 90])
        #expect(rows.first?.isHidden == false)
        #expect(rows.first?.id != .primary)
        #expect(rows.first?.key.providerID == .codex)
        // The built-in row is the new account, live, under the default name.
        #expect(rig.label == "Main")
        #expect(rig.snapshot.freshness == .live)
        #expect(rig.snapshot.windows.last?.utilization == 3)
    }

    @Test func anAccountThatWasNeverReadLeavesNoRow() async {
        let rig = DefaultLoginRig()
        // A live reading that names the account but carries no windows.
        await rig.read(UsageSnapshot(
            providerID: .codex, windows: [], planLabel: nil, accountEmail: "\(a)@example.com",
            capturedAt: rig.clock.now(), freshness: .live,
            identity: .known(DefaultLoginRig.identity(a))
        ))
        #expect(rig.slot?.binding == DefaultLoginRig.identity(a))

        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(remembered(rig).isEmpty)
        #expect(remembered(rig, includingHidden: true).isEmpty)
    }

    @Test func aSignedOutAccountReplacedByAnotherIsKeptFromItsParkedReading() async {
        let rig = await boundToWork()
        let workCapture = rig.clock.now()
        rig.advance(60)
        await rig.read(rig.signedOut)
        // A relaunch empties the row's windows; the parked reading is what survives.
        rig.launch()
        rig.advance(600)
        await rig.read(rig.reading(c))

        let rows = remembered(rig)
        #expect(rows.count == 1)
        #expect(rows.first?.label == "Work")
        #expect(rows.first?.snapshot?.capturedAt == workCapture)
        #expect(rows.first?.snapshot?.windows.isEmpty == false)
    }

    @Test func noRowIsKeptWhileAnExtraAlreadyReadsTheAccount() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        rig.extras[0].set(rig.reading(a))
        await rig.read(rig.reading(a))
        rig.advance(120)
        await rig.read(rig.reading(b))

        #expect(remembered(rig).isEmpty)
        #expect(remembered(rig, includingHidden: true).isEmpty)
    }

    /// KTD12: a row kept before an extra signed in to the same account yields to that
    /// extra, and returns when the extra is removed.
    @Test func aRememberedRowYieldsToAnExtraThatReadsTheSameAccount() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        let side = rig.extras[0]
        side.set(rig.reading("side"))
        await boundToWork(rig).read(rig.reading(a))
        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(remembered(rig).map(\.label) == ["Work"])

        rig.advance(120)
        side.set(rig.reading(a))
        await rig.read(rig.reading(b))
        #expect(remembered(rig).isEmpty)

        #expect(await rig.store.removeAccount(side.accountKey) == .removed)
        #expect(remembered(rig).map(\.label) == ["Work"])
    }

    /// KTD12 across a relaunch: the launch repair retires a remembered row only against
    /// the default login, so the row an extra hides still returns when the extra goes.
    @Test func aRememberedRowHiddenByAnExtraSurvivesARelaunchAndReturnsWithItsReading() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        let side = rig.extras[0]
        side.set(rig.reading("side"))
        await boundToWork(rig).read(rig.reading(a, weeklyUsed: 90))
        rig.advance(120)
        await rig.read(rig.reading(b))
        rig.advance(120)
        side.set(rig.reading(a))
        await rig.read(rig.reading(b))
        #expect(remembered(rig).isEmpty)

        rig.launch()
        #expect(remembered(rig).isEmpty)
        #expect(await rig.store.removeAccount(side.accountKey) == .removed)
        let rows = remembered(rig)
        #expect(rows.map(\.label) == ["Work"])
        #expect(rows.first?.snapshot?.windows.last?.utilization == 90)
    }

    // MARK: Launch repair (KTD4)

    /// A launch repair that changes the records (here a crash-interrupted mirror) still
    /// publishes the remembered rows for the session.
    @Test func aLaunchRepairThatChangesTheRecordsStillListsTheRememberedRows() async throws {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(remembered(rig).map(\.label) == ["Work"])
        var state = rig.state
        var slot = try #require(state.slot(for: rig.key))
        slot.pendingMirror = PendingMirror(label: "Main")
        state.upsert(slot)
        rig.records.write(try #require(DefaultLoginRecordsCodec.encode(state)))

        rig.launch()
        #expect(rig.slot?.pendingMirror == nil)
        #expect(remembered(rig).map(\.label) == ["Work"])
    }

    // MARK: Return (R10)

    /// Covers AE3.
    @Test func returningToARememberedAccountRetiresItsRowAndRestoresItsLabelAndReminders() async {
        let rig = await boundToWork()
        await rig.read(rig.dueReading(a))
        #expect(rig.poster.posted.count == 1)
        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)

        rig.advance(120)
        await rig.read(rig.reading(a))

        #expect(rig.label == "Work")
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)
        let rows = remembered(rig)
        #expect(rows.count == 1)
        #expect(rows.first?.email == "\(b)@example.com")
        // B never had a name, so it takes the next unused default label, not "Main".
        #expect(rows.first?.label == "Account 2")
    }

    @Test func anUnnamedAccountReturnsUnderTheDefaultName() async {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(b))
        rig.advance(120)
        await rig.read(rig.reading(a))
        #expect(remembered(rig).first?.label == "Account 2")

        rig.advance(120)
        await rig.read(rig.reading(b))
        // The number was only a name for the dimmed row; live, B is the built-in row again.
        #expect(rig.label == "Main")
        #expect(remembered(rig).map(\.label) == ["Work"])

        // Leaving again, B keeps the number it had.
        rig.advance(120)
        await rig.read(rig.reading(a))
        #expect(remembered(rig).map(\.label) == ["Account 2"])
    }

    // MARK: Rename and remove (R11)

    @Test func removeHidesTheRowUntilTheAccountIsTheDefaultLoginAgain() async {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(b))
        let work = try! #require(remembered(rig).first)

        #expect(rig.store.removeRememberedAccount(work.key))
        #expect(remembered(rig).isEmpty)
        #expect(remembered(rig, includingHidden: true).map(\.isHidden) == [true])
        // Still hidden across a relaunch and further readings of B.
        rig.launch()
        await rig.read(rig.reading(b))
        #expect(remembered(rig).isEmpty)

        rig.advance(120)
        await rig.read(rig.reading(a))
        #expect(rig.label == "Work")
        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(remembered(rig).map(\.label) == ["Work"])
        #expect(remembered(rig).first?.id == work.id)
    }

    /// R10 and R11 through the reset boundary: a removed account that becomes the default
    /// login again via "Sign Out & Set Up Again" is live under its own name, and is
    /// visible under that name when it leaves again. The account bound at the reset is
    /// still not remembered (KTD7).
    @Test func aRemovedAccountBackThroughTheResetIsLiveUnderItsNameAndVisibleWhenItLeaves() async throws {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(b))
        rig.store.renameAccount(rig.key, to: "Home")
        rig.advance(120)
        await rig.read(rig.reading(a))
        #expect(rig.label == "Work")
        let home = try #require(remembered(rig).first)
        #expect(home.label == "Home")
        #expect(rig.store.removeRememberedAccount(home.key))
        #expect(remembered(rig).isEmpty)

        rig.store.invalidateUsageForAccountReset(rig.key)
        rig.advance(60)
        await rig.read(rig.reading(b))
        #expect(rig.label == "Home")
        #expect(rig.slot?.binding == DefaultLoginRig.identity(b))
        #expect(remembered(rig, includingHidden: true).isEmpty)
        #expect(entry(rig, a)?.hasRow != true)
        #expect(entry(rig, b)?.isHidden == false)

        rig.advance(120)
        await rig.read(rig.reading(c))
        let rows = remembered(rig)
        #expect(rows.map(\.label) == ["Home"])
        #expect(rows.first?.id == home.id)
        #expect(rows.first?.isHidden == false)
    }

    /// R11: a hidden entry whose account leaves the slot is visible again, and a name the
    /// user chose is never replaced by a number.
    @Test func aHiddenEntryThatLeavesAgainIsVisibleUnderTheUsersName() {
        let key = AccountKey(providerID: .codex, accountID: .primary)
        let identityB = DefaultLoginRig.identity(b)
        var state = DefaultLoginRecordsState()
        var slot = SlotRecord(key: key)
        slot.binding = identityB
        slot.mirroredLabel = "Main"
        state.upsert(slot)
        var hidden = RememberedAccount(
            id: AccountID("home"), providerID: .codex, identity: identityB, label: "Home", email: nil
        )
        hidden.isHidden = true
        state.remembered = [hidden]
        let window = UsageWindow(kind: .weekly, utilization: 5, resetsAt: .distantFuture)
        let current = UsageSnapshot(
            providerID: .codex, windows: [window], planLabel: nil,
            capturedAt: DefaultLoginRig.start, freshness: .live, identity: .known(identityB)
        )
        let incoming = UsageSnapshot(
            providerID: .codex, windows: [window], planLabel: nil,
            capturedAt: DefaultLoginRig.start.addingTimeInterval(60), freshness: .live,
            identity: .known(DefaultLoginRig.identity(c))
        )
        _ = DefaultLoginTransition.apply(
            DefaultLoginReading(incoming)!,
            for: key,
            context: DefaultLoginSlotContext(
                isBuiltIn: true, label: "Main", defaultLabel: "Main", snapshot: current,
                reminders: .none, launchSnapshot: nil, otherReaders: [], registryLabels: ["Main"]
            ),
            to: &state
        )
        let kept = state.remembered.first { $0.identity == identityB }
        #expect(kept?.hasRow == true)
        #expect(kept?.isHidden == false)
        #expect(kept?.label == "Home")
    }

    @Test func aRenameSurvivesRetireAndRecreateAndKeepsTheLocalID() async {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(b))
        let work = try! #require(remembered(rig).first)

        #expect(rig.store.renameRememberedAccount(work.key, to: "  Esper Labs  "))
        #expect(remembered(rig).first?.label == "Esper Labs")

        rig.advance(120)
        await rig.read(rig.reading(a))
        #expect(rig.label == "Esper Labs")
        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(remembered(rig).first { $0.email == "\(a)@example.com" }?.label == "Esper Labs")
        #expect(remembered(rig).first { $0.email == "\(a)@example.com" }?.id == work.id)
    }

    @Test func renameAndRemoveRefuseAnUnknownRowAndAnEmptyName() async {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(b))
        let work = try! #require(remembered(rig).first)
        let before = rig.records.read()

        #expect(!rig.store.renameRememberedAccount(work.key, to: "   "))
        #expect(!rig.store.renameRememberedAccount(AccountKey(providerID: .codex, accountID: AccountID("nope")), to: "X"))
        #expect(!rig.store.removeRememberedAccount(AccountKey(providerID: .claude, accountID: work.id)))
        // An engine row is not a remembered account.
        #expect(!rig.store.removeRememberedAccount(rig.key))
        #expect(rig.records.read() == before)
        #expect(remembered(rig).first?.label == "Work")
    }

    @Test func eachRenameAndRemoveIsOneRecordCommit() async {
        let counting = CountingRecordStore()
        let rig = DefaultLoginRig()
        rig.launch(recordStore: counting)
        await boundToWork(rig).read(rig.reading(a))
        rig.advance(120)
        await rig.read(rig.reading(b))
        let work = try! #require(remembered(rig).first)

        let writes = counting.writes
        #expect(rig.store.renameRememberedAccount(work.key, to: "Esper"))
        #expect(counting.writes == writes + 1)
        #expect(rig.store.removeRememberedAccount(work.key))
        #expect(counting.writes == writes + 2)
        // Removing an already hidden row writes nothing.
        #expect(rig.store.removeRememberedAccount(work.key))
        #expect(counting.writes == writes + 2)
    }

    // MARK: Cap and eviction (KTD4)

    /// Seeds the record store with `count` remembered rows (and `rowless` row-less
    /// entries) bound to other accounts, then relaunches with the built-in row on A.
    private func seeded(rows count: Int, including extra: [String] = [], rowless: Int = 0) async -> DefaultLoginRig {
        let rig = await boundToWork()
        var state = rig.state
        let window = UsageWindow(kind: .weekly, utilization: 5, resetsAt: DefaultLoginRig.start.addingTimeInterval(5 * 24 * 3_600))
        func make(_ account: String, index: Int, row: Bool) -> RememberedAccount {
            let id = AccountID("seed-\(account)")
            var entry = RememberedAccount(
                id: id, providerID: .codex, identity: DefaultLoginRig.identity(account),
                label: "Seed \(account)", email: "\(account)@example.com",
                lastReadAt: DefaultLoginRig.start.addingTimeInterval(Double(index - 1_000))
            )
            if row {
                entry.snapshot = StoredSnapshot(key: entry.key, snapshot: UsageSnapshot(
                    providerID: .codex, windows: [window], planLabel: nil,
                    capturedAt: entry.lastReadAt, freshness: .live,
                    identity: .known(DefaultLoginRig.identity(account))
                ))
            }
            return entry
        }
        let accounts = extra + (0..<(count - extra.count)).map { "seed-row-\($0)" }
        state.remembered = accounts.enumerated().map { make($0.element, index: $0.offset, row: true) }
            + (0..<rowless).map { make("seed-rowless-\($0)", index: $0, row: false) }
        rig.records.write(DefaultLoginRecordsCodec.encode(state)!)
        rig.launch()
        rig.advance(60)
        await rig.read(rig.reading(a))
        return rig
    }

    @Test func atTheCapAChangeToARememberedAccountEvictsNeitherSide() async {
        let cap = DefaultLoginRecordsCodec.rememberedCap
        let rig = await seeded(rows: cap, including: [b], rowless: DefaultLoginRecordsCodec.rowlessCap)
        let bID = entry(rig, b)?.id
        #expect(remembered(rig).count == cap)

        rig.advance(120)
        await rig.read(rig.reading(b))

        #expect(remembered(rig).count == cap)
        #expect(remembered(rig).contains { $0.label == "Work" })
        // B is live now; its entry stays, row-less, with the same local id.
        #expect(entry(rig, b)?.id == bID)
        #expect(entry(rig, b)?.hasRow == false)
        #expect(entry(rig, a)?.hasRow == true)
    }

    @Test func theTwentyFirstRememberedAccountEvictsAHiddenRowBeforeAVisibleOne() async {
        let cap = DefaultLoginRecordsCodec.rememberedCap
        let rig = await seeded(rows: cap)
        let rows = remembered(rig)
        #expect(rows.count == cap)
        // Hide the most recently read row: the eviction must still prefer it.
        let newest = try! #require(rows.max { ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast) })
        #expect(rig.store.removeRememberedAccount(newest.key))

        rig.advance(120)
        await rig.read(rig.reading(b))

        let after = remembered(rig, includingHidden: true)
        #expect(after.count == cap)
        #expect(!after.contains { $0.id == newest.id })
        #expect(!after.contains { $0.isHidden })
        #expect(after.contains { $0.label == "Work" })
        // The oldest visible row survived because the hidden one went instead.
        #expect(after.contains { $0.id == AccountID("seed-seed-row-0") })
    }

    // MARK: Default labels

    @Test func unnamedRememberedAccountsAndExtrasNeverShareADefaultLabel() async {
        let rig = DefaultLoginRig(extraLabels: ["Account 2", "Account 3"])
        rig.extras[0].set(rig.reading("side-two"))
        rig.extras[1].set(rig.reading("side-three"))
        await rig.read(rig.reading(a))
        rig.advance(120)
        await rig.read(rig.reading(b))
        rig.advance(120)
        await rig.read(rig.reading(c))

        let rowLabels = remembered(rig).map(\.label)
        let extraLabels = rig.store.accounts(for: .codex).map(\.label)
        #expect(rowLabels == ["Account 4", "Account 5"])
        #expect(extraLabels == ["Main", "Account 2", "Account 3"])

        // An account added afterwards skips the numbers the remembered rows hold.
        let added = rig.store.addAccount(for: .codex)
        #expect(added?.label == "Account 6")
        let all = rig.store.accounts(for: .codex).map(\.label) + remembered(rig).map(\.label)
        #expect(Set(all).count == all.count)
    }

    @Test func aRenamedRememberedAccountFreesItsDefaultNumber() async {
        let rig = DefaultLoginRig()
        await rig.read(rig.reading(a))
        rig.advance(120)
        await rig.read(rig.reading(b))
        let first = try! #require(remembered(rig).first)
        #expect(first.label == "Account 2")
        #expect(rig.store.renameRememberedAccount(first.key, to: "Home"))

        // Account 2 is free again; the row count still starts the search past it.
        rig.advance(120)
        await rig.read(rig.reading(c))
        let labels = Set(remembered(rig).map(\.label))
        #expect(labels.contains("Home"))
        #expect(labels.count == 2)
        #expect(!labels.contains("Main"))
    }

    /// KTD7's never-bound edge with no custom name: the saved reading is kept under a
    /// number, not a second "Main".
    @Test func anUnnamedAccountKeptOnTheFirstLaunchAfterUpgradeIsNumbered() async {
        let rig = DefaultLoginRig()
        rig.launch(records: false)
        await rig.read(rig.legacyReading(email: "work@example.com"))
        rig.launch()
        rig.advance(120)
        await rig.read(rig.reading(b))

        #expect(rig.label == "Main")
        #expect(remembered(rig).map(\.label) == ["Account 2"])
        #expect(remembered(rig).first?.email == "work@example.com")
    }

    // MARK: Older builds

    @Test func anOlderBuildReadsItsOwnStoresUnchanged() async throws {
        let rig = await boundToWork()
        rig.advance(120)
        await rig.read(rig.reading(b))
        let accountsBefore = rig.defaults.data(forKey: Release162Stores.accountsKey)
        let work = try #require(remembered(rig).first)

        #expect(rig.store.renameRememberedAccount(work.key, to: "Esper"))
        #expect(rig.store.removeRememberedAccount(work.key))
        #expect(rig.defaults.data(forKey: Release162Stores.accountsKey) == accountsBefore)

        // 1.6.2 sees the built-in row only: the new key is not one it reads.
        let accounts = try #require(Release162Stores.decode(
            [Release162ProviderAccount].self, key: Release162Stores.accountsKey, in: rig.defaults
        ))
        #expect(accounts.map(\.label) == ["Main"])
        rig.launch(records: false)
        #expect(rig.store.accounts(for: .codex).map(\.label) == ["Main"])
        #expect(rig.store.rememberedAccounts(for: .codex, includingHidden: true).isEmpty)
        // And this build reads the record back as it left it.
        rig.launch()
        #expect(rig.store.rememberedAccounts(for: .codex, includingHidden: true).map(\.label) == ["Esper"])
    }

    // MARK: Scenario A (plan U5 verification)

    @Test func scenarioAWorkLeavesAgesAndReturnsUnderItsName() async {
        let rig = DefaultLoginRig()
        await rig.read(rig.reading(a, weeklyUsed: 90))
        rig.store.renameAccount(rig.key, to: "Work")
        await rig.read(rig.reading(a, weeklyUsed: 90))
        let workCapture = rig.clock.now()

        // The default login changes to Personal.
        rig.advance(120)
        await rig.read(rig.reading(b, weeklyUsed: 20))
        #expect(rig.label == "Main")
        #expect(rig.snapshot.freshness == .live)
        #expect(rig.snapshot.accountEmail == "\(b)@example.com")
        let work = try! #require(remembered(rig).first)
        #expect(work.label == "Work")
        #expect(work.snapshot?.capturedAt == workCapture)
        #expect(work.snapshot?.windows.last?.utilization == 90)

        // Two weeks later both of Work's resets have passed; the kept reading is unchanged.
        rig.advance(14 * 24 * 3_600)
        await rig.read(rig.reading(b, weeklyUsed: 25))
        #expect(remembered(rig).first?.snapshot?.capturedAt == workCapture)

        // The default login returns to Work.
        rig.advance(120)
        await rig.read(rig.reading(a, weeklyUsed: 30))
        #expect(rig.label == "Work")
        #expect(rig.snapshot.freshness == .live)
        #expect(rig.snapshot.windows.last?.utilization == 30)
        #expect(rig.slot?.binding == DefaultLoginRig.identity(a))
        let personal = remembered(rig)
        #expect(personal.count == 1)
        #expect(personal.first?.email == "\(b)@example.com")
        #expect(personal.first?.label == "Account 2")
        #expect(personal.first?.snapshot?.windows.last?.utilization == 25)
    }
}

/// Counts record-store writes, so a test can hold a mutation to one commit.
final class CountingRecordStore: DefaultLoginRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var count = 0

    var writes: Int { lock.withLock { count } }
    func read() -> Data? { lock.withLock { data } }
    func write(_ data: Data) { lock.withLock { self.data = data; count += 1 } }
}
