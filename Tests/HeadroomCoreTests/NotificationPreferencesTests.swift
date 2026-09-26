import Foundation
import Testing
@testable import HeadroomCore

/// U1: notification switches, the reminder rule list, and the Applies-to scope.
struct NotificationPreferencesTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.notification-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func rule(_ amount: Int, _ unit: ReminderLeadUnit, _ threshold: Int) -> ReminderRule {
        ReminderRule(amount: amount, unit: unit, threshold: threshold)
    }

    private func values(_ rules: [ReminderRule]) -> [String] {
        rules.map { "\($0.amount)\($0.unit == .hours ? "h" : "d")/\($0.threshold)" }
    }

    // MARK: - Defaults and persistence

    @Test func freshSuiteYieldsSwitchesOffDefaultRulesAndDefaultScope() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.useItUpRemindersEnabled == false)
        #expect(prefs.bankedResetNotificationsEnabled == false)
        #expect(values(prefs.reminderRules) == ["1d/50", "6h/25"])
        #expect(prefs.reminderRules == ReminderRules.defaults)
        #expect(prefs.reminderScope == [.weekly, .billingPeriod])
    }

    @Test func switchesPersist() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.useItUpRemindersEnabled = true
        prefs.bankedResetNotificationsEnabled = true
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.useItUpRemindersEnabled)
        #expect(reloaded.bankedResetNotificationsEnabled)
    }

    /// KTD5: default rules carry fixed IDs, so their firing keys survive relaunch even
    /// though nothing was ever written.
    @Test func defaultRuleIDsAreStableAcrossReads() {
        let first = Preferences(defaults: freshDefaults()).reminderRules
        let second = Preferences(defaults: freshDefaults()).reminderRules
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.firingKey) == second.map(\.firingKey))
    }

    @Test func customRulesAndScopeRoundTrip() {
        let defaults = freshDefaults()
        let rules = [rule(2, .days, 70), rule(1, .days, 50), rule(3, .hours, 15)]
        Preferences(defaults: defaults).reminderRules = rules
        Preferences(defaults: defaults).reminderScope = [.weekly, .billingPeriod, .fiveHour]

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.reminderRules == rules)
        #expect(reloaded.reminderScope == [.weekly, .billingPeriod, .fiveHour])
    }

    /// R5: an empty list is a legitimate choice, distinct from a missing key.
    @Test func emptyRuleListAndEmptyScopePersist() {
        let defaults = freshDefaults()
        Preferences(defaults: defaults).reminderRules = []
        Preferences(defaults: defaults).reminderScope = []
        #expect(Preferences(defaults: defaults).reminderRules.isEmpty)
        #expect(Preferences(defaults: defaults).reminderScope.isEmpty)
    }

    @Test func corruptRulesFallBackToDefaultsWithoutOverwriting() {
        let defaults = freshDefaults()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: "reminderRules.v1")
        defaults.set(garbage, forKey: "reminderScope.v1")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.reminderRules == ReminderRules.defaults)
        #expect(prefs.reminderScope == ReminderScope.defaults)
        #expect(defaults.data(forKey: "reminderRules.v1") == garbage)
        #expect(defaults.data(forKey: "reminderScope.v1") == garbage)
    }

    @Test func storedOutOfRangeValuesClampOnRead() throws {
        let defaults = freshDefaults()
        let id = UUID()
        let json = #"[{"id":"\#(id.uuidString)","amount":99,"unit":"days","threshold":0}]"#
        defaults.set(Data(json.utf8), forKey: "reminderRules.v1")
        let rules = Preferences(defaults: defaults).reminderRules
        #expect(rules.count == 1)
        #expect(rules.first?.id == id)
        #expect(rules.first?.amount == 30)
        #expect(rules.first?.threshold == 1)
    }

    /// An unknown scope value from a newer build is dropped, not fatal to the whole set.
    @Test func unknownScopeValuesAreIgnored() {
        let defaults = freshDefaults()
        defaults.set(Data(#"["weekly","hourly"]"#.utf8), forKey: "reminderScope.v1")
        #expect(Preferences(defaults: defaults).reminderScope == [.weekly])
    }

    // MARK: - Clamping (R4)

    @Test func amountsAndThresholdsClampIntoRange() {
        #expect(rule(0, .hours, 50).clamped().amount == 1)
        #expect(rule(49, .hours, 50).clamped().amount == 48)
        #expect(rule(31, .days, 50).clamped().amount == 30)
        #expect(rule(-4, .days, 50).clamped().amount == 1)
        #expect(rule(1, .days, 0).clamped().threshold == 1)
        #expect(rule(1, .days, 150).clamped().threshold == 100)
        let inRange = rule(12, .hours, 40)
        #expect(inRange.clamped() == inRange)
    }

    @Test func blankInputClampsToTheLowerBound() {
        #expect(ReminderRule.clampedAmount(nil, unit: .hours) == 1)
        #expect(ReminderRule.clampedAmount(nil, unit: .days) == 1)
        #expect(ReminderRule.clampedThreshold(nil) == 1)
        #expect(ReminderRule.clampedAmount(72, unit: .hours) == 48)
        #expect(ReminderRule.clampedThreshold(55) == 55)
    }

    @Test func unitChangeKeepsTheNumberAndClamps() {
        let fortyEightHours = rule(48, .hours, 50)
        let changed = fortyEightHours.withUnit(.days)
        #expect(changed.amount == 30)
        #expect(changed.unit == .days)
        #expect(changed.id == fortyEightHours.id)

        let sixDays = rule(6, .days, 50).withUnit(.hours)
        #expect(sixDays.amount == 6)
        #expect(sixDays.unit == .hours)
    }

    @Test func leadIntervalFollowsTheUnit() {
        #expect(rule(6, .hours, 25).leadInterval == 6 * 3_600)
        #expect(rule(1, .days, 50).leadInterval == 24 * 3_600)
        #expect(rule(1, .days, 50).leadMinutes == 1_440)
    }

    // MARK: - Seeding (R5)

    @Test func seedHalvesTheShortestRule() {
        let seeded = ReminderRules.seed(from: [rule(1, .days, 50), rule(6, .hours, 25)])
        #expect(seeded.amount == 3)
        #expect(seeded.unit == .hours)
        #expect(seeded.threshold == 12)
    }

    @Test func seedFromAOneHourOnePercentRuleStaysAtTheFloor() {
        let seeded = ReminderRules.seed(from: [rule(1, .hours, 1)])
        #expect(values([seeded]) == ["1h/1"])
    }

    @Test func seedFromADayRuleIsExpressedInHours() {
        let seeded = ReminderRules.seed(from: [rule(1, .days, 50)])
        #expect(values([seeded]) == ["12h/25"])
    }

    @Test func seedFromAnEmptyListIsOneDayAtHalf() {
        let seeded = ReminderRules.seed(from: [])
        #expect(values([seeded]) == ["1d/50"])
    }

    @Test func seededRulesGetFreshIDs() {
        let base = [rule(6, .hours, 25)]
        #expect(ReminderRules.seed(from: base).id != ReminderRules.seed(from: base).id)
    }

    // MARK: - Sorting (R6)

    @Test func sortOrdersByLongestLeadFirst() {
        let sorted = ReminderRules.sorted([rule(6, .hours, 25), rule(2, .days, 70), rule(1, .days, 50)])
        #expect(values(sorted) == ["2d/70", "1d/50", "6h/25"])
    }

    @Test func identicalLeadsOrderByThresholdDescending() {
        let sorted = ReminderRules.sorted([rule(1, .days, 30), rule(24, .hours, 60), rule(1, .days, 45)])
        #expect(values(sorted) == ["24h/60", "1d/45", "1d/30"])
    }

    @Test func resortingKeepsIDs() {
        let rules = [rule(6, .hours, 25), rule(2, .days, 70)]
        let sorted = ReminderRules.sorted(rules)
        #expect(Set(sorted.map(\.id)) == Set(rules.map(\.id)))
        #expect(Set(sorted.map(\.firingKey)) == Set(rules.map(\.firingKey)))
    }

    /// KTD5: the row UUID never changes, so an edit animates in place; the firing key
    /// carries the values, so an edited rule counts as a new rule for the ledger.
    @Test func editingARuleKeepsTheRowIDButChangesTheFiringKey() {
        let original = rule(6, .hours, 25)
        var edited = original
        edited.amount = 7
        #expect(edited.id == original.id)
        #expect(edited.firingKey != original.firingKey)

        var thresholdEdit = original
        thresholdEdit.threshold = 30
        #expect(thresholdEdit.firingKey != original.firingKey)

        // Same lead expressed differently is the same firing identity.
        let asHours = ReminderRule(id: original.id, amount: 24, unit: .hours, threshold: 25)
        let asDays = ReminderRule(id: original.id, amount: 1, unit: .days, threshold: 25)
        #expect(asHours.firingKey == asDays.firingKey)
        #expect(original.firingKey == "\(original.id.uuidString):360:25")
    }

    // MARK: - Is default (R8)

    @Test func isDefaultTracksRulesAndScope() {
        #expect(ReminderRules.isDefault(rules: ReminderRules.defaults, scope: ReminderScope.defaults))

        var edited = ReminderRules.defaults
        edited[0].threshold = 60
        #expect(!ReminderRules.isDefault(rules: edited, scope: ReminderScope.defaults))

        #expect(!ReminderRules.isDefault(rules: ReminderRules.defaults, scope: [.weekly, .billingPeriod, .fiveHour]))
        #expect(!ReminderRules.isDefault(rules: [], scope: ReminderScope.defaults))

        // Values, not row IDs: a re-added 1d/50 + 6h/25 pair reads as default.
        let rebuilt = [rule(1, .days, 50), rule(6, .hours, 25)]
        #expect(ReminderRules.isDefault(rules: rebuilt, scope: ReminderScope.defaults))
    }
}

/// U1: `UsageStore` mirrors the notification preferences and writes through.
@MainActor
struct NotificationPreferencesStoreTests {
    private func freshPreferences() -> Preferences {
        let suite = "headroom.notification-store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Preferences(defaults: defaults)
    }

    private func makeStore(_ preferences: Preferences) -> UsageStore {
        UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: .pending(for: .claude))],
            preferences: preferences
        )
    }

    @Test func storeSeedsFromPreferences() {
        let preferences = freshPreferences()
        preferences.useItUpRemindersEnabled = true
        preferences.reminderScope = [.fiveHour]
        preferences.reminderRules = [ReminderRule(amount: 3, unit: .hours, threshold: 15)]
        let store = makeStore(preferences)
        #expect(store.useItUpRemindersEnabled)
        #expect(!store.bankedResetNotificationsEnabled)
        #expect(store.reminderScope == [.fiveHour])
        #expect(store.reminderRules == preferences.reminderRules)
        #expect(!store.reminderSettingsAreDefault)
    }

    @Test func switchSettersWriteThrough() {
        let preferences = freshPreferences()
        let store = makeStore(preferences)
        store.setUseItUpRemindersEnabled(true)
        store.setBankedResetNotificationsEnabled(true)
        #expect(store.useItUpRemindersEnabled)
        #expect(store.bankedResetNotificationsEnabled)
        #expect(preferences.useItUpRemindersEnabled)
        #expect(preferences.bankedResetNotificationsEnabled)
    }

    @Test func setReminderRulesClampsAndWritesThroughWithoutSorting() {
        let preferences = freshPreferences()
        let store = makeStore(preferences)
        let typed = [
            ReminderRule(amount: 6, unit: .hours, threshold: 25),
            ReminderRule(amount: 99, unit: .days, threshold: 70),
        ]
        store.setReminderRules(typed)
        #expect(store.reminderRules.map(\.amount) == [6, 30])
        #expect(preferences.reminderRules == store.reminderRules)
    }

    @Test func commitReminderRuleClampsReplacesAndSorts() {
        let preferences = freshPreferences()
        let store = makeStore(preferences)
        var shortest = store.reminderRules[1] // 6h/25
        shortest.amount = 3
        shortest.unit = .days
        shortest.threshold = 0
        store.commitReminderRule(shortest)
        #expect(store.reminderRules.first?.id == shortest.id)
        #expect(store.reminderRules.first?.amount == 3)
        #expect(store.reminderRules.first?.threshold == 1)
        #expect(store.reminderRules.count == 2)
        #expect(preferences.reminderRules == store.reminderRules)
    }

    @Test func commitOfAnUnknownRuleChangesNothing() {
        let preferences = freshPreferences()
        let store = makeStore(preferences)
        store.commitReminderRule(ReminderRule(amount: 5, unit: .hours, threshold: 5))
        #expect(store.reminderRules == ReminderRules.defaults)
    }

    @Test func addAndRemoveReminderRules() {
        let preferences = freshPreferences()
        let store = makeStore(preferences)
        let added = store.addReminderRule()
        #expect(store.reminderRules.last == added)
        #expect(added.amount == 3 && added.unit == .hours && added.threshold == 12)

        store.removeReminderRule(id: added.id)
        store.removeReminderRule(id: store.reminderRules[0].id)
        store.removeReminderRule(id: store.reminderRules[0].id)
        #expect(store.reminderRules.isEmpty)
        #expect(preferences.reminderRules.isEmpty)

        let fromEmpty = store.addReminderRule()
        #expect(fromEmpty.amount == 1 && fromEmpty.unit == .days && fromEmpty.threshold == 50)
    }

    @Test func resetToDefaultsRestoresRulesAndScope() {
        let preferences = freshPreferences()
        let store = makeStore(preferences)
        store.setReminderScope([.fiveHour])
        store.setReminderRules([])
        #expect(!store.reminderSettingsAreDefault)
        #expect(preferences.reminderScope == [.fiveHour])

        store.resetReminderSettingsToDefaults()
        #expect(store.reminderSettingsAreDefault)
        #expect(store.reminderRules == ReminderRules.defaults)
        #expect(preferences.reminderRules == ReminderRules.defaults)
        #expect(preferences.reminderScope == ReminderScope.defaults)
    }
}
