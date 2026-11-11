import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U3: the store knows which account each row holds and handles a
/// change of account as one committed step. Driven through `UsageStore.merge` with a real
/// registry and real reminder stores.
@MainActor
struct DefaultLoginRecordsTests {
    private let a = "aaaaaaaa-0000-4000-8000-000000000001"
    private let b = "bbbbbbbb-0000-4000-8000-000000000002"

    private func boundToWork() async -> DefaultLoginRig {
        let rig = DefaultLoginRig()
        await rig.read(rig.reading(a))
        rig.store.renameAccount(rig.key, to: "Work")
        return rig
    }

    @Test func aFirstKnownReadingBindsTheRowAndChangesNothingVisible() async {
        let rig = DefaultLoginRig()
        await rig.read(rig.reading(a))
        #expect(rig.label == "Main")
        #expect(rig.slot?.binding == DefaultLoginRig.identity(a))
        #expect(rig.slot?.phase == .attached)
        #expect(rig.snapshot.freshness == .live)
        #expect(rig.state.remembered.isEmpty)
    }

    /// Covers AE7 (R4).
    @Test func aReadingWithNoReadableIdentityShowsUnderTheDefaultNameUntilTheAccountReturns() async {
        let rig = await boundToWork()
        await rig.read(rig.dueReading(a))
        #expect(rig.poster.posted.count == 1)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)

        rig.advance(300)
        await rig.read(rig.reading(nil, weeklyUsed: 50))
        #expect(rig.label == "Main")
        #expect(rig.slot?.phase == .detached)
        #expect(rig.slot?.binding == DefaultLoginRig.identity(a))
        #expect(rig.snapshot.windows.last?.utilization == 50)
        // None of Work's reminder state sits under the unnamed reading.
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
        #expect(rig.rows.isEmpty)

        rig.advance(300)
        await rig.read(rig.dueReading(a))
        #expect(rig.label == "Work")
        #expect(rig.slot?.phase == .attached)
        #expect(rig.slot?.parked == nil)
        // Work's fired rule came back with it, so it does not fire a second time.
        #expect(rig.poster.posted.count == 1)
        #expect(rig.state.remembered.isEmpty)
    }

    @Test func reminderEntriesWrittenWhileTheIdentityWasUnreadableAreGoneOnReturn() async {
        let rig = await boundToWork()
        rig.advance(300)
        await rig.read(rig.dueReading(nil))
        #expect(rig.poster.posted.count == 1)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)

        rig.advance(300)
        await rig.read(rig.reading(a))
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
    }

    /// Covers AE8 (R15).
    @Test func aLoginThatLapsesAndReturnsAsTheSameAccountKeepsItsName() async {
        let rig = await boundToWork()
        await rig.read(rig.signedOut)
        #expect(rig.label == "Work")
        #expect(rig.slot?.phase == .lapsed)
        #expect(rig.slot?.parked?.snapshot != nil)

        rig.advance(600)
        await rig.read(rig.reading(a))
        #expect(rig.label == "Work")
        #expect(rig.slot?.phase == .attached)
        #expect(rig.state.remembered.isEmpty)
    }

    @Test func aLapsedAccountReplacedByAnotherIsRememberedFromItsParkedReading() async {
        let rig = await boundToWork()
        let workCapture = rig.clock.now()
        await rig.read(rig.signedOut)
        // A relaunch loses the in-memory windows; the parked reading survives it.
        rig.launch()
        rig.advance(600)
        await rig.read(rig.reading(b))

        #expect(rig.label == "Main")
        #expect(rig.rows.count == 1)
        #expect(rig.rows.first?.label == "Work")
        #expect(rig.rows.first?.snapshot?.capturedAt == workCapture)
    }

    /// Covers AE9 (R2).
    @Test func signOutAndSetUpAgainAsAnotherAccountTakesTheDefaultNameAndRemembersNothing() async {
        let rig = await boundToWork()
        rig.store.invalidateUsageForAccountReset(rig.key)
        #expect(rig.slot?.phase == .cleared)
        #expect(rig.label == "Work")

        await rig.read(rig.reading(b))
        #expect(rig.label == "Main")
        #expect(rig.snapshot.freshness == .live)
        #expect(rig.slot?.binding == DefaultLoginRig.identity(b))
        #expect(rig.state.remembered.isEmpty)
    }

    @Test func signOutAndSetUpAgainAsTheSameAccountKeepsItsName() async {
        let rig = await boundToWork()
        rig.store.invalidateUsageForAccountReset(rig.key)
        await rig.read(rig.reading(a))
        #expect(rig.label == "Work")
        #expect(rig.state.remembered.isEmpty)
    }

    /// Covers AE1 at the store (R2, R6).
    @Test func aChangeOfAccountTakesTheDefaultNameAndKeepsTheOldAccountsLastReading() async {
        let rig = await boundToWork()
        await rig.read(rig.dueReading(a))
        let workCapture = rig.clock.now()
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)

        rig.advance(120)
        await rig.read(rig.reading(b, weeklyUsed: 3))

        #expect(rig.label == "Main")
        #expect(rig.snapshot.windows.last?.utilization == 3)
        #expect(rig.snapshot.accountEmail == "\(b)@example.com")
        // No reminder state of Work's is attached to the new account.
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
        let row = rig.rows.first
        #expect(rig.rows.count == 1)
        #expect(row?.label == "Work")
        #expect(row?.identity == DefaultLoginRig.identity(a))
        #expect(row?.snapshot?.capturedAt == workCapture)
        #expect(row?.snapshot?.snapshot?.windows.last?.utilization == 73)
        #expect(row?.reminders.useItUp.count == 1)
        #expect(row?.id != .primary)
    }

    /// Covers AE3 at the store (R10).
    @Test func returningToARememberedAccountRestoresItsNameAndItsFiredReminders() async {
        let rig = await boundToWork()
        await rig.read(rig.dueReading(a))
        #expect(rig.poster.posted.count == 1)
        rig.advance(120)
        await rig.read(rig.reading(b))
        let workID = rig.rows.first?.id

        rig.advance(120)
        await rig.read(rig.dueReading(a))

        #expect(rig.label == "Work")
        // Inside the same reset cycle, the rule Work already spent does not repeat.
        #expect(rig.poster.posted.count == 1)
        #expect(rig.rows.map(\.identity) == [DefaultLoginRig.identity(b)])
        #expect(rig.rows.first?.label == "Main")
        // Work's entry stays, row-less, so its local id is reused if it leaves again.
        #expect(rig.state.remembered.first { $0.identity == DefaultLoginRig.identity(a) }?.id == workID)

        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(rig.rows.first { $0.identity == DefaultLoginRig.identity(a) }?.id == workID)
        #expect(rig.rows.count == 1)
    }

    @Test func theFirstMergeOfTheNewAccountNamesItNotThePreviousOne() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        rig.extras[0].set(rig.reading("side"))
        await rig.read(rig.reading(a))
        rig.store.renameAccount(rig.key, to: "Work")

        rig.advance(120)
        await rig.read(rig.dueReading(b))

        #expect(rig.poster.posted.count == 1)
        let banner = String(describing: rig.poster.posted.first)
        #expect(!banner.contains("Work"))
        #expect(banner.contains("Main"))
    }

    @Test func aReminderPostInFlightForThePreviousAccountWritesNothingUnderTheRow() async {
        let rig = await boundToWork()
        rig.poster.gate.suspendNextFetch()
        rig.primary.set(rig.dueReading(a))
        await rig.store.refreshAll()
        await rig.poster.gate.waitUntilStarted()

        rig.advance(120)
        rig.primary.set(rig.reading(b))
        await rig.store.refreshAll()
        rig.poster.gate.release()
        await rig.coordinator.waitForPendingPosts()

        #expect(rig.label == "Main")
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
    }

    @Test func theNewAccountsFirstBankedCountSeedsSilently() async {
        let rig = DefaultLoginRig(banked: true)
        await rig.read(rig.reading(a, banked: 1))
        await rig.read(rig.reading(a, banked: 2))
        #expect(rig.poster.posted.count == 1)

        rig.advance(120)
        await rig.read(rig.reading(b, banked: 5))
        #expect(rig.poster.posted.count == 1)
        #expect(rig.baseline.baselineCount(for: rig.key) == 5)

        // Back on A at the same count: its own baseline returned, so nothing fires.
        rig.advance(120)
        await rig.read(rig.reading(a, banked: 2))
        #expect(rig.poster.posted.count == 1)
        #expect(rig.baseline.baselineCount(for: rig.key) == 2)
    }

    @Test func aUserWithNoReadableIdentityKeepsTheirLabelAndNumbersAcrossARelaunch() async {
        let rig = DefaultLoginRig()
        await rig.read(rig.reading(nil, weeklyUsed: 44))
        rig.store.renameAccount(rig.key, to: "Mine")
        await rig.read(rig.reading(nil, weeklyUsed: 45))

        rig.launch()
        #expect(rig.label == "Mine")
        #expect(rig.snapshot.windows.last?.utilization == 45)
        await rig.read(rig.reading(nil, weeklyUsed: 46))
        #expect(rig.label == "Mine")
        #expect(rig.slot?.binding == nil)
    }

    @Test func anExtraRowReSignedToAnotherAccountResetsItsHistoryAndKeepsItsLabel() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        let side = rig.extras[0]
        let sideKey = side.accountKey
        side.set(rig.dueReading("side-one"))
        await rig.read(rig.reading(a))
        #expect(rig.ledger.entry(for: sideKey, windowID: "weekly") != nil)

        rig.advance(120)
        side.set(rig.reading("side-two"))
        await rig.read(rig.reading(a))

        #expect(rig.store.accounts(for: .codex).first { $0.key == sideKey }?.label == "Side")
        #expect(rig.state.slot(for: sideKey)?.binding == DefaultLoginRig.identity("side-two"))
        #expect(rig.ledger.entry(for: sideKey, windowID: "weekly") == nil)
        #expect(rig.state.remembered.isEmpty)
    }

    @Test func noRowIsRememberedWhileAnExtraAlreadyReadsThatAccount() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        rig.extras[0].set(rig.reading(a))
        await rig.read(rig.reading(a))

        rig.advance(120)
        await rig.read(rig.reading(b))

        #expect(rig.rows.isEmpty)
        #expect(rig.label == "Main")
    }

    @Test func aRenameBeforeTheChangeTravelsWithTheOutgoingAccount() async {
        let rig = await boundToWork()
        rig.store.renameAccount(rig.key, to: "Esper Labs")
        #expect(rig.slot?.mirroredLabel == "Esper Labs")

        rig.advance(120)
        await rig.read(rig.reading(b))
        #expect(rig.rows.first?.label == "Esper Labs")
    }

    @Test func remindersAreParkedEvenWhenFailuresEmptiedTheLastReading() async {
        let rig = await boundToWork()
        await rig.read(rig.dueReading(a))
        // Past every reset, a failed poll retains no window and removes the saved reading.
        rig.advance(6 * 3_600)
        await rig.read(rig.blip)
        #expect(rig.snapshot.windows.isEmpty)
        #expect(rig.slot?.continuityRemoved == true)

        await rig.read(rig.reading(b))
        // No reading, so no row; the reminder state is kept for Work's return.
        #expect(rig.rows.isEmpty)
        let parked = rig.state.remembered.first { $0.identity == DefaultLoginRig.identity(a) }
        #expect(parked?.label == "Work")
        #expect(parked?.reminders.useItUp.count == 1)
    }

    @Test func aWeakIdentityChangeRelabelsButRemembersNothing() {
        var state = DefaultLoginRecordsState()
        let key = AccountKey(providerID: .grok, accountID: .primary)
        func context(label: String, snapshot: UsageSnapshot?) -> DefaultLoginSlotContext {
            DefaultLoginSlotContext(
                isBuiltIn: true, label: label, defaultLabel: "Main", snapshot: snapshot,
                reminders: .none, launchSnapshot: nil, otherReaders: [], now: DefaultLoginRig.start
            )
        }
        func grok(_ email: String) -> UsageSnapshot {
            UsageSnapshot(
                providerID: .grok,
                windows: [UsageWindow(kind: .weekly, utilization: 5, resetsAt: .distantFuture)],
                planLabel: nil, accountEmail: email, capturedAt: DefaultLoginRig.start, freshness: .live,
                identity: .known(AccountIdentity.grok(email: email)!)
            )
        }
        _ = DefaultLoginTransition.apply(
            DefaultLoginReading(grok("a@example.com"))!, for: key,
            context: context(label: "Work", snapshot: nil), to: &state
        )
        let effects = DefaultLoginTransition.apply(
            DefaultLoginReading(grok("b@example.com"))!, for: key,
            context: context(label: "Work", snapshot: grok("a@example.com")), to: &state
        )
        #expect(effects.label == "Main")
        #expect(effects.prior == .none)
        #expect(effects.accountChanged)
        #expect(state.remembered.isEmpty)
    }

    @Test func aDigestVersionMismatchAdoptsAgainAndRemembersNothing() async {
        let rig = await boundToWork()
        var state = rig.state
        var slot = state.slot(for: rig.key)!
        let old = AccountIdentity(providerID: .codex, strength: .strong, digest: "old-scheme", digestVersion: 0)
        slot.binding = old
        state.upsert(slot)
        rig.records.write(DefaultLoginRecordsCodec.encode(state)!)
        rig.launch()

        await rig.read(rig.reading(a))
        #expect(rig.label == "Work")
        #expect(rig.slot?.binding == DefaultLoginRig.identity(a))
        #expect(rig.state.remembered.isEmpty)
    }

    @Test func theRememberedCapEvictsHiddenRowsFirstAndNeverTheAccountJustLeft() {
        var state = DefaultLoginRecordsState()
        let key = AccountKey(providerID: .codex, accountID: .primary)
        let window = UsageWindow(kind: .weekly, utilization: 5, resetsAt: .distantFuture)
        func snapshot(_ account: String, at date: Date) -> UsageSnapshot {
            UsageSnapshot(
                providerID: .codex, windows: [window], planLabel: nil, capturedAt: date,
                freshness: .live, identity: .known(DefaultLoginRig.identity(account))
            )
        }
        var current: UsageSnapshot?
        for index in 0...DefaultLoginRecordsCodec.rememberedCap + 1 {
            let date = DefaultLoginRig.start.addingTimeInterval(Double(index) * 60)
            let fresh = snapshot("account-\(index)", at: date)
            _ = DefaultLoginTransition.apply(
                DefaultLoginReading(fresh)!, for: key,
                context: DefaultLoginSlotContext(
                    isBuiltIn: true, label: "Main", defaultLabel: "Main", snapshot: current,
                    reminders: .none, launchSnapshot: nil, otherReaders: [], now: date
                ),
                to: &state
            )
            current = fresh
            // Hide the newest remembered row once, early on: it must be the first to go.
            if index == 3, let hidden = state.remembered.indices.last { state.remembered[hidden].isHidden = true }
        }
        let rows = state.remembered.filter(\.hasRow)
        #expect(rows.count == DefaultLoginRecordsCodec.rememberedCap)
        #expect(!rows.contains { $0.isHidden })
        // The oldest visible row survived because the hidden one was evicted instead.
        #expect(rows.contains { $0.identity == DefaultLoginRig.identity("account-0") })
        #expect(rows.contains { $0.identity == DefaultLoginRig.identity("account-\(DefaultLoginRecordsCodec.rememberedCap)") })
    }
}
