import AppKit
import Foundation
import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

/// U6 (2026-09-26 notifications plan): the Notifications pane's states and effects, driven
/// through its presentation and interaction seams with a `ScriptedNotificationClient` and
/// isolated defaults. Nothing here reaches `UNUserNotificationCenter` (KTD9).
@MainActor
@Suite(.sharedAppState, .serialized)
struct NotificationsSettingsPaneTests {
    private struct Fixture {
        let store: UsageStore
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture() -> Fixture {
        let suiteName = "co.zantos.headroom.notifications-pane.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            preferences: Preferences(defaults: defaults)
        )
        return Fixture(store: store, defaults: defaults, suiteName: suiteName)
    }

    private func presentation(
        _ store: UsageStore,
        _ authorization: NotificationAuthorization?,
        lateness: Int = 5
    ) -> NotificationsPanePresentation {
        NotificationsPanePresentation(store: store, authorization: authorization, latenessMinutes: lateness)
    }

    // MARK: R1

    @Test func paneIsTheLastDestinationInTheAppGroup() {
        // About now lives in General, leaving seven App and Sources destinations.
        #expect(SettingsPane.allCases.count == 7)
        #expect(SettingsPane.Group.preferences.panes.last == .notifications)
        let appPanes = SettingsPane.Group.preferences.panes
        #expect(appPanes.firstIndex(of: .notifications) == appPanes.firstIndex(of: .widgets).map { $0 + 1 })
        #expect(SettingsPane.notifications.label == "Notifications")
        #expect(SettingsPane.notifications.symbolName == "bell")
        #expect(SettingsPane.notifications.symbolScale == SettingsPane.widgets.symbolScale)
    }

    // MARK: R3, R6, R8, R9 default state

    @Test func defaultStateHasBothSwitchesOffDimmedRulesTwoDefaultsAndNoReset() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let state = presentation(fixture.store, .notDetermined)

        #expect(!state.useItUpEnabled)
        #expect(!state.bankedResetsEnabled)
        #expect(state.switchesEnabled)
        #expect(!state.ruleControlsEnabled)
        #expect(fixture.store.reminderRules.count == 2)
        #expect(fixture.store.reminderRules == ReminderRules.defaults)
        #expect(!state.showsResetToDefaults)
        #expect(!state.showsPermissionNotice)
        #expect(!state.showsInstalledAppHelp)
    }

    @Test func addingARuleShowsResetAndResettingRestoresTheDefaultsAndHidesIt() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.store.addReminderRule()
        fixture.store.setReminderScope([.weekly, .billingPeriod, .fiveHour])
        #expect(fixture.store.reminderRules.count == 3)
        #expect(presentation(fixture.store, .authorized).showsResetToDefaults)

        fixture.store.resetReminderSettingsToDefaults()
        #expect(fixture.store.reminderRules == ReminderRules.defaults)
        #expect(fixture.store.reminderScope == ReminderScope.defaults)
        #expect(!presentation(fixture.store, .authorized).showsResetToDefaults)
    }

    @Test func removingEveryRuleShowsTheEmptyHelpLineAndTheSwitchStaysOn() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let client = ScriptedNotificationClient(status: .authorized)
        _ = await NotificationsSettingsInteractions.setSwitch(
            .useItUp, isOn: true, store: fixture.store, client: client, known: .authorized
        )
        for rule in fixture.store.reminderRules {
            fixture.store.removeReminderRule(id: rule.id)
        }

        let state = presentation(fixture.store, .authorized)
        #expect(fixture.store.reminderRules.isEmpty)
        #expect(fixture.store.useItUpRemindersEnabled)
        #expect(state.ruleControlsEnabled)
        #expect(state.rulesHelp == NotificationsPanePresentation.rulesHelpEmpty)
    }

    @Test func rulesHelpQuotesTheLatenessFigure() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        // R9: the figure is whatever the root binds from the slowest lane.
        // CA-S9: plain words, both figures bound to the same lane.
        #expect(presentation(fixture.store, .authorized, lateness: 12).rulesHelp
            == "Each reminder fires once per reset. It can arrive up to 12\u{00A0}min late, since Headroom checks every 12\u{00A0}min.")
    }

    // MARK: CA-F1 billing-periods hint

    private func windows(_ snapshots: [ProviderID: UsageSnapshot]) -> (ProviderID) -> [UsageWindow] {
        { snapshots[$0]?.windows ?? [] }
    }

    @Test func theBillingPeriodHintIsDerivedFromWhatEachProviderReports() {
        let order: [ProviderID] = [.claude, .codex, .grok, .cursor, .copilot]
        let snapshots: [ProviderID: UsageSnapshot] = [
            .claude: DemoFixture.claudeSnapshot, .codex: DemoFixture.codexSnapshot,
            .grok: DemoFixture.grokSnapshot, .cursor: DemoFixture.cursorSnapshot,
            .copilot: DemoFixture.copilotSnapshot,
        ]
        let providers = BillingPeriodScopeHint.providers(in: order, windows: windows(snapshots))
        #expect(providers == [.grok, .cursor, .copilot])
        #expect(BillingPeriodScopeHint.text(for: providers, displayName: \.displayName) == "Grok, Cursor, Copilot")
    }

    @Test func theBillingPeriodHintGainsAProviderThatBillsByPeriod() {
        // OpenCode's monthly limit classifies as a billing period, so it joins without a
        // new literal; so would any later provider that reports one.
        let acme = ProviderID("acme")
        var snapshots: [ProviderID: UsageSnapshot] = [
            .grok: DemoFixture.grokSnapshot, .cursor: DemoFixture.cursorSnapshot,
            .copilot: DemoFixture.copilotSnapshot, .opencode: DemoFixture.opencodeSnapshot,
            // Antigravity's pool rows are 5-hour and weekly limits, never a billing period.
            .antigravity: DemoFixture.antigravitySnapshot,
        ]
        snapshots[acme] = UsageSnapshot(
            providerID: acme,
            windows: [UsageWindow(kind: .billingPeriod(label: "Monthly", duration: 2_592_000),
                                  utilization: 20, resetsAt: Date().addingTimeInterval(86_400))],
            planLabel: nil,
            capturedAt: Date(),
            freshness: .live
        )
        let order: [ProviderID] = [.claude, .grok, .cursor, .antigravity, .copilot, .opencode, acme]
        let providers = BillingPeriodScopeHint.providers(in: order, windows: windows(snapshots))
        #expect(providers == [.grok, .cursor, .copilot, .opencode, acme])
        #expect(BillingPeriodScopeHint.text(for: [], displayName: \.displayName) == nil)
    }

    /// CA-S12 (SET-13): the denied notice is one container drawn on the pane, not a callout
    /// inside a `SettingsTile`.
    @Test func theDeniedNoticeIsOneContainer() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HeadroomApp/UI/NotificationsSettingsPane.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let start = try #require(text.range(of: "private var permissionNotice: some View"))
        let end = try #require(text.range(of: "// MARK: Use-it-up reminders", range: start.upperBound..<text.endIndex))
        let body = text[start.upperBound..<end.lowerBound]
        #expect(!body.contains("SettingsTile"))
        #expect(body.components(separatedBy: ".background(").count - 1 == 1)
    }

    // MARK: R17, R18, KTD11 permission

    @Test func turningOnWithUndecidedPermissionThatIsDeniedRevertsAndShowsTheNotice() async {
        // AE7.
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let client = ScriptedNotificationClient(status: .notDetermined, requestOutcome: .denied)

        let status = await NotificationsSettingsInteractions.setSwitch(
            .useItUp, isOn: true, store: fixture.store, client: client, known: .notDetermined
        )

        #expect(client.requestCount == 1)
        #expect(status == .denied)
        #expect(!fixture.store.useItUpRemindersEnabled)
        #expect(!fixture.store.bankedResetNotificationsEnabled)
        let state = presentation(fixture.store, status)
        #expect(state.showsPermissionNotice)
        #expect(!state.switchesEnabled)
    }

    @Test func turningOnWithUndecidedPermissionThatIsAllowedKeepsTheSwitchOn() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let client = ScriptedNotificationClient(status: .notDetermined, requestOutcome: .authorized)

        let status = await NotificationsSettingsInteractions.setSwitch(
            .bankedResets, isOn: true, store: fixture.store, client: client, known: .notDetermined
        )

        #expect(client.requestCount == 1)
        #expect(status == .authorized)
        #expect(fixture.store.bankedResetNotificationsEnabled)
        #expect(!fixture.store.useItUpRemindersEnabled)
        #expect(!presentation(fixture.store, status).showsPermissionNotice)
    }

    @Test func alreadyAuthorizedTurnsOnWithoutAskingAgainAndOffNeverAsks() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let client = ScriptedNotificationClient(status: .authorized)

        _ = await NotificationsSettingsInteractions.setSwitch(
            .useItUp, isOn: true, store: fixture.store, client: client, known: .authorized
        )
        #expect(fixture.store.useItUpRemindersEnabled)
        _ = await NotificationsSettingsInteractions.setSwitch(
            .useItUp, isOn: false, store: fixture.store, client: client, known: .authorized
        )
        #expect(!fixture.store.useItUpRemindersEnabled)
        #expect(client.requestCount == 0)
    }

    @Test func deniedAtSettingsOpenPersistsBothOffAndAReGrantClearsOnlyTheNotice() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.store.setUseItUpRemindersEnabled(true)
        fixture.store.setBankedResetNotificationsEnabled(true)
        let client = ScriptedNotificationClient(status: .denied)

        let denied = await NotificationsSettingsInteractions.refreshAuthorization(
            store: fixture.store, client: client
        )
        #expect(denied == .denied)
        #expect(!fixture.store.useItUpRemindersEnabled)
        #expect(!fixture.store.bankedResetNotificationsEnabled)
        // Persisted, not just mirrored: a fresh Preferences on the suite reads off.
        let reread = Preferences(defaults: fixture.defaults)
        #expect(!reread.useItUpRemindersEnabled)
        #expect(!reread.bankedResetNotificationsEnabled)
        #expect(presentation(fixture.store, denied).showsPermissionNotice)

        // KTD11: re-granted in System Settings, then Settings reopens.
        client.status = .authorized
        let granted = await NotificationsSettingsInteractions.refreshAuthorization(
            store: fixture.store, client: client
        )
        let state = presentation(fixture.store, granted)
        #expect(!state.showsPermissionNotice)
        #expect(state.switchesEnabled)
        #expect(!fixture.store.useItUpRemindersEnabled)
        #expect(!fixture.store.bankedResetNotificationsEnabled)
        #expect(client.requestCount == 0)
    }

    @Test func unavailableDisablesBothSwitchesShowsTheInstalledAppLineAndNeverAsks() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let client = ScriptedNotificationClient(status: .unavailable)

        let status = await NotificationsSettingsInteractions.refreshAuthorization(
            store: fixture.store, client: client
        )
        let state = presentation(fixture.store, status)
        #expect(!state.switchesEnabled)
        #expect(!state.ruleControlsEnabled)
        #expect(state.showsInstalledAppHelp)
        #expect(!state.showsPermissionNotice)

        _ = await NotificationsSettingsInteractions.setSwitch(
            .useItUp, isOn: true, store: fixture.store, client: client, known: status
        )
        #expect(!fixture.store.useItUpRemindersEnabled)
        #expect(client.requestCount == 0)
    }

    @Test func theInertClientReadsAsUnavailable() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let status = await NotificationsSettingsInteractions.refreshAuthorization(
            store: fixture.store, client: InertNotificationClient()
        )
        #expect(presentation(fixture.store, status).showsInstalledAppHelp)
    }

    // MARK: R4, R6, KTD15 rule editing

    @Test func committingALeadTimeEditResortsTheListAndTypingAloneDoesNot() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let sixHours = fixture.store.reminderRules[1]
        #expect(sixHours.unit == .hours)

        // Typing stays in the row's draft: nothing reaches the store until commit.
        let draft = "48"
        #expect(fixture.store.reminderRules == ReminderRules.defaults)

        let committed = ReminderRuleDraft.committed(sixHours, amountText: draft)
        fixture.store.commitReminderRule(committed)
        #expect(fixture.store.reminderRules.map(\.id) == [sixHours.id, ReminderRules.defaults[0].id])
        #expect(fixture.store.reminderRules.first?.amount == 48)
    }

    @Test func draftsClampOnCommit() {
        let rule = ReminderRule(amount: 6, unit: .hours, threshold: 25)
        #expect(ReminderRuleDraft.committed(rule, amountText: "0").amount == 1)
        #expect(ReminderRuleDraft.committed(rule, amountText: "49").amount == 48)
        #expect(ReminderRuleDraft.committed(rule, amountText: "").amount == 1)
        #expect(ReminderRuleDraft.committed(rule, amountText: "99999999999999999999").amount == 48)
        #expect(ReminderRuleDraft.committed(rule, amountText: " 12h").amount == 12)
        #expect(ReminderRuleDraft.committed(rule, thresholdText: "150").threshold == 100)
        #expect(ReminderRuleDraft.committed(rule, thresholdText: "0").threshold == 1)
        #expect(ReminderRuleDraft.committed(rule, thresholdText: "").threshold == 1)
        let days = ReminderRule(amount: 1, unit: .days, threshold: 50)
        #expect(ReminderRuleDraft.committed(days, amountText: "31").amount == 30)
        // A commit keeps the row's identity (KTD5: the ID names the row).
        #expect(ReminderRuleDraft.committed(rule, amountText: "3").id == rule.id)
    }

    @Test func steppersMoveByOneLeadUnitAndToTheNextFivePercent() {
        #expect(ReminderRuleDraft.steppedThreshold(25, up: true) == 30)
        #expect(ReminderRuleDraft.steppedThreshold(23, up: true) == 25)
        #expect(ReminderRuleDraft.steppedThreshold(23, up: false) == 20)
        #expect(ReminderRuleDraft.steppedThreshold(5, up: false) == 1)
        #expect(ReminderRuleDraft.steppedThreshold(1, up: true) == 5)
        #expect(ReminderRuleDraft.steppedThreshold(100, up: true) == 100)
        let hours = ReminderRule(amount: 48, unit: .hours, threshold: 25)
        #expect(ReminderRuleDraft.steppedAmount(hours, up: true) == 48)
        #expect(ReminderRuleDraft.steppedAmount(hours, up: false) == 47)
        let oneDay = ReminderRule(amount: 1, unit: .days, threshold: 50)
        #expect(ReminderRuleDraft.steppedAmount(oneDay, up: false) == 1)
    }

    @Test func eachRowNamesItsFieldsAndRemoveButtonForVoiceOver() {
        let first = ReminderRuleDraft.AccessibilityLabels(position: 1)
        let second = ReminderRuleDraft.AccessibilityLabels(position: 2)
        #expect(first.leadTime == "Lead time, reminder 1")
        #expect(first.threshold == "Percent left, reminder 1")
        #expect(first.unit == "Lead time unit, reminder 1")
        #expect(first.remove == "Remove reminder 1")
        #expect(second.remove == "Remove reminder 2")
        let all = [first, second].flatMap {
            [$0.leadTime, $0.leadTimeStepper, $0.unit, $0.threshold, $0.thresholdStepper, $0.remove]
        }
        #expect(Set(all).count == all.count)
    }

    // MARK: Sizing

    /// The `MenuBarPaneSizingTests` guard: a pane that demands height at a zero-width
    /// proposal pushes the split view past the 600pt window floor.
    @Test func theNotificationsPaneDemandsNoMinimumHeight() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let pane = NotificationsSettingsPane(
            store: fixture.store,
            authorization: .denied,
            latenessMinutes: 5,
            onSetSwitch: { _, _ in },
            onOpenSystemSettings: {}
        )
        let minimum = NSHostingController(rootView: pane).sizeThatFits(in: .zero)
        #expect(minimum.height < SettingsView.minimumWindowHeight / 2)
    }
}
