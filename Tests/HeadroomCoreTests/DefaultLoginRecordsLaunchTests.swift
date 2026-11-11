import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U13: the first launch after an upgrade, a downgrade or a crash
/// never pins a label, a reminder entry or a reading on the wrong account.
@MainActor
struct DefaultLoginRecordsLaunchTests {
    private let a = "aaaaaaaa-0000-4000-8000-000000000001"
    private let b = "bbbbbbbb-0000-4000-8000-000000000002"

    /// An install that has only ever run a build from before identities.
    private func upgraded(
        email: String?,
        label: String? = "Esper Labs",
        weeklyUsed: Double = 90,
        due: Bool = false
    ) async -> DefaultLoginRig {
        let rig = DefaultLoginRig()
        rig.launch(records: false)
        let saved = rig.legacyReading(email: email, weeklyUsed: weeklyUsed)
        await rig.read(due ? rig.reading(nil, weeklyUsed: 73, email: .some(email), identity: .some(nil), weeklyResetIn: 5 * 3_600) : saved)
        if let label { rig.store.renameAccount(rig.key, to: label) }
        return rig
    }

    private func boundToWork(due: Bool = true) async -> DefaultLoginRig {
        let rig = DefaultLoginRig()
        await rig.read(due ? rig.dueReading(a) : rig.reading(a))
        rig.store.renameAccount(rig.key, to: "Work")
        return rig
    }

    // MARK: Never bound (KTD7)

    /// Covers AE10.
    @Test func firstLaunchOnADifferentLoginKeepsTheOldAccountUnderItsOldName() async {
        let rig = await upgraded(email: "work@example.com")
        let savedAt = rig.clock.now()
        rig.launch()
        #expect(rig.label == "Esper Labs")
        #expect(rig.snapshot.windows.last?.utilization == 90)

        rig.advance(600)
        await rig.read(rig.reading(b, weeklyUsed: 4, email: "me@gmail.example"))

        #expect(rig.label == "Main")
        #expect(rig.snapshot.windows.last?.utilization == 4)
        #expect(rig.rows.count == 1)
        let row = rig.rows.first
        #expect(row?.label == "Esper Labs")
        #expect(row?.identity == nil)
        #expect(row?.provisionalEmail == "work@example.com")
        #expect(row?.snapshot?.capturedAt == savedAt)
        #expect(row?.snapshot?.snapshot?.windows.last?.utilization == 90)
    }

    @Test func aProvisionalAccountIsClaimedByItsEmailAndKeepsItsLocalId() async {
        let rig = await upgraded(email: "work@example.com")
        rig.launch()
        await rig.read(rig.reading(b, email: "me@gmail.example"))
        let id = rig.rows.first?.id

        rig.advance(600)
        await rig.read(rig.reading(a, email: "Work@Example.com"))
        #expect(rig.label == "Esper Labs")
        let claimed = rig.state.remembered.first { $0.id == id }
        #expect(claimed?.identity == DefaultLoginRig.identity(a))
        #expect(claimed?.provisionalEmail == nil)
        #expect(claimed?.hasRow == false)
        #expect(rig.rows.map(\.identity) == [DefaultLoginRig.identity(b)])

        rig.advance(600)
        await rig.read(rig.reading(b, email: "me@gmail.example"))
        #expect(rig.rows.first { $0.identity == DefaultLoginRig.identity(a) }?.id == id)
        #expect(rig.rows.count == 1)
    }

    @Test func firstLaunchOnTheSameLoginAdoptsLabelAndHistory() async {
        let rig = await upgraded(email: "work@example.com", due: true)
        #expect(rig.poster.posted.count == 1)
        rig.launch()

        await rig.read(rig.reading(a, weeklyUsed: 73, email: "work@example.com", weeklyResetIn: 5 * 3_600))
        #expect(rig.label == "Esper Labs")
        #expect(rig.slot?.binding == DefaultLoginRig.identity(a))
        #expect(rig.state.remembered.isEmpty)
        // The reminder it already fired stays spent.
        #expect(rig.poster.posted.count == 1)
    }

    @Test func theDecisionUsesTheSavedEmailEvenWhenEverySavedWindowExpired() async {
        let rig = await upgraded(email: "work@example.com")
        rig.advance(30 * 24 * 3_600)
        rig.launch()
        #expect(rig.snapshot.freshness == .pending)

        await rig.read(rig.reading(b, email: "me@gmail.example"))
        #expect(rig.label == "Main")
        #expect(rig.rows.first?.label == "Esper Labs")
    }

    @Test func aCustomLabelWithNoSavedEmailStaysOnTheRow() async {
        let rig = await upgraded(email: nil, label: "Mine")
        rig.launch()
        await rig.read(rig.reading(b))
        #expect(rig.label == "Mine")
        #expect(rig.state.remembered.isEmpty)
        #expect(rig.slot?.binding == DefaultLoginRig.identity(b))
    }

    @Test func neverBoundAdoptAppliesToAnExtraRow() async {
        let rig = DefaultLoginRig(extraLabels: ["Side"])
        let side = rig.extras[0]
        rig.launch(records: false)
        side.set(rig.reading(nil, weeklyUsed: 73, email: "one@example.com", identity: .some(nil), weeklyResetIn: 5 * 3_600))
        await rig.read(rig.legacyReading(email: "main@example.com"))
        #expect(rig.ledger.entry(for: side.accountKey, windowID: "weekly") != nil)

        rig.launch()
        side.set(rig.reading("side-two", email: "two@example.com"))
        await rig.read(rig.reading(a, email: "main@example.com"))

        #expect(rig.store.accounts(for: .codex).first { $0.key == side.accountKey }?.label == "Side")
        #expect(rig.ledger.entry(for: side.accountKey, windowID: "weekly") == nil)
        #expect(rig.state.remembered.isEmpty)
        #expect(rig.label == "Main")
    }

    // MARK: Attribution (KTD6)

    @Test func anOrdinaryRelaunchKeepsTheReadingAndTheReminderState() async {
        let rig = await boundToWork()
        rig.launch()
        #expect(rig.label == "Work")
        #expect(rig.snapshot.windows.last?.utilization == 73)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)

        await rig.read(rig.dueReading(a))
        #expect(rig.poster.posted.count == 1)
    }

    /// A Cursor status read that misses gives a live reading with no identity evidence.
    @Test func aReadingWithNoIdentityEvidenceOnABoundRowSurvivesARelaunch() async {
        let rig = await boundToWork()
        rig.advance(300)
        await rig.read(rig.reading(nil, weeklyUsed: 73, identity: .some(nil), weeklyResetIn: 5 * 3_600))
        #expect(rig.label == "Work")
        #expect(rig.continuity.load()[rig.key]?.identity == nil)

        rig.launch()
        #expect(rig.snapshot.windows.last?.utilization == 73)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)
        #expect(rig.label == "Work")
    }

    @Test func aSavedReadingCarryingAnotherAccountsDigestIsDropped() async {
        let rig = await boundToWork()
        rig.continuity.save(rig.reading(b, weeklyUsed: 40), for: rig.key)

        rig.launch()
        #expect(rig.snapshot.freshness == .pending)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
    }

    /// 1.6.2 rewrites the whole continuity envelope on any save, which drops the digest
    /// from this row's record without changing whose reading it is.
    @Test func aRecordAnOlderBuildOnlyReEncodedIsStillAttributedByItsCaptureTime() async {
        let rig = await boundToWork()
        Release162Stores.rewrite(Release162ContinuityEnvelope.self, key: Release162Stores.continuityKey, in: rig.defaults)
        #expect(rig.continuity.load()[rig.key]?.identity == nil)

        rig.launch()
        #expect(rig.snapshot.windows.last?.utilization == 73)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)
    }

    @Test func aDowngradeThatReadAnotherAccountLeavesNothingToMisattribute() async {
        let rig = await boundToWork()
        // 1.6.2 runs on a different login: it saves that account's reading, fires and
        // records a reminder for it, and the user renames the row.
        rig.launch(records: false)
        rig.advance(600)
        await rig.read(rig.reading(nil, weeklyUsed: 60, email: "other@example.com", identity: .some(nil), weeklyResetIn: 5 * 3_600))
        rig.store.renameAccount(rig.key, to: "Other")
        Release162Stores.rewrite(Release162ContinuityEnvelope.self, key: Release162Stores.continuityKey, in: rig.defaults)

        rig.launch()
        #expect(rig.snapshot.freshness == .pending)
        #expect(rig.continuity.load()[rig.key] == nil)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)

        await rig.read(rig.reading(b, email: "other@example.com"))
        #expect(rig.label == "Main")
        #expect(rig.rows.isEmpty)
        // Work keeps the label this build gave it, and none of the other build's data.
        let work = rig.state.remembered.first { $0.identity == DefaultLoginRig.identity(a) }
        #expect(work?.label == "Work")
        #expect(work?.reminders == ParkedReminders.none)
        #expect(work?.snapshot == nil)
    }

    @Test func anOlderBuildsSignOutPurgesTheReminderStateInsteadOfParkingIt() async {
        let rig = await boundToWork()
        rig.launch(records: false)
        await rig.read(rig.signedOut)
        #expect(rig.continuity.load()[rig.key] == nil)

        rig.launch()
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
        await rig.read(rig.reading(b))
        #expect(rig.rows.isEmpty)
        #expect(rig.state.remembered.first?.reminders == ParkedReminders.none)
    }

    @Test func aClockSetBackwardsInTheOlderBuildDoesNotPassAsAttributed() async {
        let rig = await boundToWork()
        rig.launch(records: false)
        rig.advance(-24 * 3_600)
        await rig.read(rig.legacyReading(email: "other@example.com", weeklyUsed: 60))

        rig.advance(24 * 3_600 + 60)
        rig.launch()
        #expect(rig.snapshot.freshness == .pending)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
    }

    // MARK: Crash recovery (KTD4)

    /// U3's write order is: commit the records, then the registry label, the reminder
    /// entries and the continuity record, then mark the mirrors written.
    @Test(arguments: 1...4) func aCrashAfterAnyStepOfAChangeIsFinishedAtTheNextLaunch(step: Int) async {
        let rig = await boundToWork()
        var state = rig.state
        let effects = DefaultLoginTransition.apply(
            DefaultLoginReading(rig.reading(b))!,
            for: rig.key,
            context: DefaultLoginSlotContext(
                isBuiltIn: true, label: "Work", defaultLabel: "Main", snapshot: rig.snapshot,
                reminders: ParkedReminders(useItUp: rig.ledger.entries(), bankedBaseline: nil, bankedAcknowledged: nil),
                launchSnapshot: nil, otherReaders: []
            ),
            to: &state
        )
        #expect(effects.label == "Main")
        // Step 1: the single record commit.
        rig.records.write(DefaultLoginRecordsCodec.encode(state)!)
        if step >= 2 { rig.registry.renameAccount(rig.key, to: "Main") }
        if step >= 3 { rig.ledger.purge(for: rig.key) }
        if step >= 4 { rig.continuity.remove(for: rig.key) }

        rig.launch()

        #expect(rig.label == "Main")
        #expect(rig.snapshot.freshness == .pending)
        #expect(rig.continuity.load()[rig.key] == nil)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") == nil)
        #expect(rig.slot?.pendingMirror == nil)
        #expect(rig.slot?.binding == DefaultLoginRig.identity(b))
        // Work is remembered once, with its reading and its reminder state.
        #expect(rig.rows.map(\.label) == ["Work"])
        #expect(rig.rows.first?.reminders.useItUp.count == 1)

        await rig.read(rig.reading(b))
        #expect(rig.label == "Main")
        #expect(rig.rows.count == 1)
    }

    @Test func aRememberedRowWhoseAccountIsBoundAgainIsRetiredAtLaunch() async {
        let rig = await boundToWork()
        await rig.read(rig.reading(b))
        var state = rig.state
        var slot = state.slot(for: rig.key)!
        slot.binding = DefaultLoginRig.identity(a)
        state.upsert(slot)
        rig.records.write(DefaultLoginRecordsCodec.encode(state)!)

        rig.launch()
        #expect(rig.rows.isEmpty)
    }

    // MARK: Envelope (KTD4)

    @Test func oneMalformedEntryCostsOnlyThatEntry() async throws {
        let rig = await boundToWork()
        let data = try #require(rig.records.read())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var slots = try #require(object["slots"] as? [Any])
        slots.insert(["key": "not a key"], at: 0)
        object["slots"] = slots
        rig.records.write(try JSONSerialization.data(withJSONObject: object))

        rig.launch()
        #expect(rig.state.slots.count == 1)
        #expect(rig.slot?.binding == DefaultLoginRig.identity(a))
    }

    @Test func anEnvelopeWithAFutureSchemaIsNeverWrittenOver() async {
        let rig = DefaultLoginRig()
        let future = Data(#"{"schemaVersion":99,"slots":[],"remembered":[],"somethingNew":true}"#.utf8)
        rig.records.write(future)
        rig.launch()
        #expect(rig.store.defaultLoginState == nil)

        await rig.read(rig.reading(a))
        rig.store.renameAccount(rig.key, to: "Work")
        await rig.read(rig.reading(b))

        #expect(rig.records.read() == future)
        // With the records unreadable the row behaves as it did before identities.
        #expect(rig.label == "Work")
    }

    // MARK: 1.6.2 compatibility

    @Test func everyExistingStoreStillDecodesIn162AfterAParkAndRestoreCycle() async throws {
        let rig = DefaultLoginRig(extraLabels: ["Side"], banked: true)
        rig.extras[0].set(rig.reading("side", banked: 1))
        await rig.read(rig.reading(a, weeklyUsed: 73, banked: 2, weeklyResetIn: 5 * 3_600))
        rig.store.renameAccount(rig.key, to: "Work")
        _ = rig.store.claimBankedResetReveal(for: rig.key, currentCount: 2)
        rig.advance(120)
        await rig.read(rig.reading(b, banked: 4))
        rig.advance(120)
        await rig.read(rig.reading(a, weeklyUsed: 73, banked: 2, weeklyResetIn: 5 * 3_600))

        let continuity = try #require(Release162Stores.decode(
            Release162ContinuityEnvelope.self, key: Release162Stores.continuityKey, in: rig.defaults
        ))
        #expect(continuity.schemaVersion == Release162ContinuityEnvelope.currentSchemaVersion)
        #expect(continuity.records.count == 2)
        let ledger = try #require(Release162Stores.decode(
            Release162UseItUpStored.self, key: Release162Stores.useItUpKey, in: rig.defaults
        ))
        #expect(ledger.entries.contains { $0.account.accountID.raw == "primary" && $0.windowID == "weekly" })
        let baseline = try #require(Release162Stores.decode(
            Release162BankedStored.self, key: Release162Stores.bankedBaselineKey, in: rig.defaults
        ))
        #expect(baseline.entries.first { $0.account.accountID.raw == "primary" }?.count == 2)
        let acknowledged = try #require(Release162Stores.decode(
            Release162BankedStored.self, key: Release162Stores.bankedAcknowledgementsKey, in: rig.defaults
        ))
        #expect(acknowledged.entries.first { $0.account.accountID.raw == "primary" }?.count == 2)
        let accounts = try #require(Release162Stores.decode(
            [Release162ProviderAccount].self, key: Release162Stores.accountsKey, in: rig.defaults
        ))
        #expect(accounts.map(\.label).sorted() == ["Side", "Work"])
        #expect(accounts.count == 2)
    }

    @Test func a162RewriteKeepsThatBuildsOwnEntries() async throws {
        let rig = await boundToWork()
        let before = try #require(Release162Stores.decode(
            Release162UseItUpStored.self, key: Release162Stores.useItUpKey, in: rig.defaults
        ))
        Release162Stores.rewrite(Release162UseItUpStored.self, key: Release162Stores.useItUpKey, in: rig.defaults)
        Release162Stores.rewrite(Release162ContinuityEnvelope.self, key: Release162Stores.continuityKey, in: rig.defaults)
        Release162Stores.rewrite([Release162ProviderAccount].self, key: Release162Stores.accountsKey, in: rig.defaults)

        #expect(rig.ledger.entries().count == before.entries.count)
        #expect(rig.ledger.entry(for: rig.key, windowID: "weekly") != nil)
        #expect(rig.continuity.load()[rig.key]?.windows.count == 2)
        #expect(rig.registry.accounts(for: .codex).first?.label == "Work")
        // The record store's own key is one 1.6.2 never reads or writes.
        #expect(rig.defaults.data(forKey: "defaultLoginRecords.v1") != nil)
    }
}
