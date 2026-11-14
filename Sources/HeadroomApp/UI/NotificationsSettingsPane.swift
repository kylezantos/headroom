#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import HeadroomCore

// MARK: - Notifications (U6, 2026-09-26 notifications plan)

/// The two master switches the pane owns (R3, R14). Both share one permission (R17).
enum NotificationSwitch: Equatable, Sendable {
    case useItUp
    case bankedResets
}

/// What the pane shows for a given permission and preference state (R8, R9, R17, R18, KTD11).
/// Pure, so the states are testable without mounting the view.
struct NotificationsPanePresentation: Equatable {
    static let rulesHelpEmpty = "With no reminders, nothing is sent. The switch stays on so your scope is kept."
    static let emptyListText = "No reminders. Nothing will be sent until you add one."
    static let installedAppHelp = "Notifications need the installed Headroom app."
    static let permissionNotice =
        "Notifications are turned off for Headroom in System Settings, so nothing here can be sent."

    /// Nil until the first check lands; read as undecided, so nothing flashes a notice.
    let authorization: NotificationAuthorization?
    let useItUpEnabled: Bool
    let bankedResetsEnabled: Bool
    let ruleCount: Int
    let settingsAreDefault: Bool
    /// R9: the slowest effective interval, in whole minutes (`PollCadencePresentation`).
    let latenessMinutes: Int

    @MainActor
    init(store: UsageStore, authorization: NotificationAuthorization?, latenessMinutes: Int) {
        self.authorization = authorization
        self.useItUpEnabled = store.useItUpRemindersEnabled
        self.bankedResetsEnabled = store.bankedResetNotificationsEnabled
        self.ruleCount = store.reminderRules.count
        self.settingsAreDefault = store.reminderSettingsAreDefault
        self.latenessMinutes = latenessMinutes
    }

    /// R18: the notice tile at the top of the pane.
    var showsPermissionNotice: Bool { authorization == .denied }

    /// R18 / KTD11: denied and unavailable both leave the switches unreachable.
    var switchesEnabled: Bool { authorization != .denied && authorization != .unavailable }

    /// KTD9: an unbundled process can never post, so it says why instead of prompting.
    var showsInstalledAppHelp: Bool { authorization == .unavailable }

    /// R9: the rule list and Applies to stay visible, disabled and dimmed, while the switch
    /// is off or cannot be turned on.
    var ruleControlsEnabled: Bool { switchesEnabled && useItUpEnabled }

    /// R8: only when the rules or the Applies-to choices differ from the defaults.
    var showsResetToDefaults: Bool { !settingsAreDefault }

    /// R9: the firing guarantees, with the lateness figure bound to the slowest lane.
    /// CA-S9 (COPY-07): plain words for the same two facts; "fresh reading", "refresh
    /// interval" and "lead time" were internal terms.
    var rulesHelp: String {
        guard ruleCount > 0 else { return Self.rulesHelpEmpty }
        return "Each reminder fires once per reset. It can arrive up to \(latenessMinutes)\u{00A0}min late, "
            + "since Headroom checks every \(latenessMinutes)\u{00A0}min."
    }
}

/// CA-F1 (SET-08): the providers the "Billing periods" box governs, derived with the same
/// rule that routes a reminder (`UseItUpEvaluator.scope`), so the hint can never disagree with
/// what fires. The old literal "Grok, Cursor" missed Copilot, and would have missed the next
/// provider that bills by period too.
enum BillingPeriodScopeHint {
    /// Providers, in the given order, with at least one window that classifies as a billing
    /// period.
    static func providers(
        in order: [ProviderID],
        windows: (ProviderID) -> [UsageWindow]
    ) -> [ProviderID] {
        order.filter { id in
            windows(id).contains { UseItUpEvaluator.scope(for: $0.kind, providerID: id) == .billingPeriod }
        }
    }

    /// The hint beside the checkbox, or nil when no provider reports a billing period yet.
    static func text(for providers: [ProviderID], displayName: (ProviderID) -> String) -> String? {
        providers.isEmpty ? nil : providers.map(displayName).joined(separator: ", ")
    }

    /// The store's form: every shown account's windows, read from the display list.
    @MainActor
    static func text(store: UsageStore) -> String? {
        let ids = providers(in: store.registeredProviderOrder) { id in
            store.displayAccounts(for: id).flatMap { store.snapshot(for: $0.account.key).windows }
        }
        return text(for: ids) { store.displayNames[$0] ?? $0.displayName }
    }
}

/// Permission and switch effects shared by the pane and its deterministic tests (R17, R18,
/// KTD11). The client is injected; nothing here touches `UNUserNotificationCenter`.
@MainActor
enum NotificationsSettingsInteractions {
    /// R18: runs every time Settings opens. A denial turns both switches off and persists
    /// that; a re-grant clears the notice but leaves the switches for the user (KTD11).
    static func refreshAuthorization(
        store: UsageStore,
        client: any NotificationAuthorizing
    ) async -> NotificationAuthorization {
        let status = await client.authorizationStatus()
        if status == .denied { turnBothOff(store) }
        return status
    }

    /// R17: turning a switch on asks macOS the first time; a refusal reverts it. The switch
    /// moves at once so the row answers the click while the system prompt is up, and the
    /// live status, not the cached one, decides what sticks. Returns the resulting state.
    static func setSwitch(
        _ which: NotificationSwitch,
        isOn: Bool,
        store: UsageStore,
        client: any NotificationAuthorizing,
        known: NotificationAuthorization?
    ) async -> NotificationAuthorization? {
        guard isOn else {
            set(which, false, store)
            return known
        }
        // The switches are disabled in both states; this guards a stale binding.
        if known == .denied || known == .unavailable { return known }
        set(which, true, store)
        var status = await client.authorizationStatus()
        if status == .notDetermined {
            status = await client.requestAuthorization()
        }
        switch status {
        case .authorized:
            break
        case .denied:
            turnBothOff(store)
        case .notDetermined, .unavailable:
            set(which, false, store)
        }
        return status
    }

    private static func set(_ which: NotificationSwitch, _ isOn: Bool, _ store: UsageStore) {
        switch which {
        case .useItUp: store.setUseItUpRemindersEnabled(isOn)
        case .bankedResets: store.setBankedResetNotificationsEnabled(isOn)
        }
    }

    private static func turnBothOff(_ store: UsageStore) {
        store.setUseItUpRemindersEnabled(false)
        store.setBankedResetNotificationsEnabled(false)
    }
}

/// R1–R9, R14, R18: the Notifications destination. Stateless (KTD3): the permission state
/// and the switch effects live on `SettingsView`; the rules and scope are read from and
/// written through the store (KTD14). R20: every part is a current Settings component —
/// `SettingsTile`, `SettingsSwitchRow`, `SettingsHelpText`, `SettingsGroupLabel`,
/// `SettingsPillBadge`, the recessed well — and the rule row is the only new one.
struct NotificationsSettingsPane: View {
    let store: UsageStore
    let authorization: NotificationAuthorization?
    let latenessMinutes: Int
    let onSetSwitch: (NotificationSwitch, Bool) -> Void
    let onOpenSystemSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: NotificationsPanePresentation {
        NotificationsPanePresentation(
            store: store,
            authorization: authorization,
            latenessMinutes: latenessMinutes
        )
    }

    var body: some View {
        let _ = BenchCounters.hit("NotificationsSettingsPane")
        let presentation = presentation
        SettingsPaneScaffold(SettingsPane.notifications.label) {
            if presentation.showsPermissionNotice {
                permissionNotice
                    .transition(.settingsReveal(reduceMotion: reduceMotion))
            }
            useItUpTile(presentation)
            bankedResetsTile(presentation)
        }
        // RM1: `.movement`, so under Reduce Motion the notice's height snaps; its fade rides
        // `settingsReveal(reduceMotion:)`.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
            value: presentation.showsPermissionNotice
        )
    }

    // MARK: Permission notice (R18)

    /// CA-S12 (SET-13): one container, drawn straight on the pane. The callout used to sit
    /// inside a `SettingsTile`, two frames around one sentence, which also made the notice
    /// look like another setting. The step material says it is a state of the pane; r10
    /// matches the tiles it stands beside.
    private var permissionNotice: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(alignment: .center, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
                .accessibilityHidden(true)
            SettingsHelpText(text: NotificationsPanePresentation.permissionNotice)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open System Settings…", action: onOpenSystemSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeSetupStyle.stepBackground(dark: colorScheme == .dark), in: shape)
        .overlay(shape.strokeBorder(ClaudeSetupStyle.stepBorder(dark: colorScheme == .dark), lineWidth: 1))
    }

    // MARK: Use-it-up reminders (R2–R9)

    private func useItUpTile(_ presentation: NotificationsPanePresentation) -> some View {
        SettingsTile("Use-it-up reminders") {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                // CA-S9 (COPY-07): the title says the job; the help gives an example.
                SettingsSwitchRow(
                    title: "Remind me to use what’s left before a reset",
                    isOn: switchBinding(.useItUp, isOn: presentation.useItUpEnabled)
                )
                .disabled(!presentation.switchesEnabled)
                SettingsHelpText(text: "For example: 1 day before your weekly limit resets, if half or more is left.")
                if presentation.showsInstalledAppHelp {
                    SettingsHelpText(text: NotificationsPanePresentation.installedAppHelp)
                }
            }

            VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
                ruleWell
                SettingsHelpText(text: presentation.rulesHelp)
            }
            .dimmedUnless(presentation.ruleControlsEnabled, reduceMotion: reduceMotion)

            appliesTo
                .dimmedUnless(presentation.ruleControlsEnabled, reduceMotion: reduceMotion)

            if presentation.showsResetToDefaults {
                // CA-S2: neutral ink, not a system-blue link. CA-S8: Title Case for a button.
                SettingsInlineLink("Reset to Defaults") {
                    withAnimation(rowAnimation) { store.resetReminderSettingsToDefaults() }
                }
                .dimmedUnless(presentation.ruleControlsEnabled, reduceMotion: reduceMotion)
                .transition(.settingsReveal(reduceMotion: reduceMotion))
            }
        }
        .animation(rowAnimation, value: presentation.showsResetToDefaults)
    }

    /// KTD15: the rules in a recessed well with hairline separators, "Add reminder" at its foot.
    private var ruleWell: some View {
        let rules = store.reminderRules
        return VStack(alignment: .leading, spacing: 0) {
            if rules.isEmpty {
                Text(NotificationsPanePresentation.emptyListText)
                    .font(SettingsType.help)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 10)
                    .transition(.settingsReveal(reduceMotion: reduceMotion))
            }
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                ReminderRuleRow(
                    rule: rule,
                    position: index + 1,
                    onCommit: { edited in
                        // R6/KTD15: a committed edit resorts; the rows travel on `reorder`.
                        withAnimation(reorderAnimation) { store.commitReminderRule(edited) }
                    },
                    onRemove: {
                        withAnimation(rowAnimation) { store.removeReminderRule(id: rule.id) }
                    }
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .overlay(alignment: .top) {
                    if index > 0 { hairline }
                }
                .transition(.settingsReveal(reduceMotion: reduceMotion))
            }
            hairline
            // CA-S2: neutral ink, not a system-blue link. CA-S8: Title Case for a button.
            SettingsInlineLink("Add Reminder", systemImage: "plus") {
                withAnimation(rowAnimation) { _ = store.addReminderRule() }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ProviderStyle.recessedWell(dark: colorScheme == .dark),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(ClaudeSetupStyle.hairline(dark: colorScheme == .dark))
            .frame(height: 1)
    }

    /// R7: native checkboxes, the dependent-option idiom under a master switch.
    private var appliesTo: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
            SettingsGroupLabel("Applies to")
            Toggle("Weekly limits", isOn: scopeBinding(.weekly))
            Toggle(isOn: scopeBinding(.billingPeriod)) {
                HStack(spacing: 5) {
                    Text("Billing periods")
                    if let hint = BillingPeriodScopeHint.text(store: store) {
                        ScopeHint(text: hint)
                    }
                }
            }
            Toggle("5-hour windows", isOn: scopeBinding(.fiveHour))
            // CA-S9 (COPY-07): "lead time" was an internal term.
            SettingsHelpText(text: "5-hour windows reset too often for most people to want a reminder. A reminder skips any window shorter than its timing.")
        }
    }

    // MARK: Banked resets (R14)

    private func bankedResetsTile(_ presentation: NotificationsPanePresentation) -> some View {
        SettingsTile("Banked resets", titleAccessory: { SettingsPillBadge(text: "Codex") }) {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsSwitchRow(
                    title: "Tell me when Codex banks a new reset",
                    isOn: switchBinding(.bankedResets, isOn: presentation.bankedResetsEnabled)
                )
                .disabled(!presentation.switchesEnabled)
                SettingsHelpText(text: "Codex can bank spare limit resets for later. Headroom reads the count on each refresh and never spends one.")
                if presentation.showsInstalledAppHelp {
                    SettingsHelpText(text: NotificationsPanePresentation.installedAppHelp)
                }
            }
        }
    }

    // MARK: Bindings and motion

    private func switchBinding(_ which: NotificationSwitch, isOn: Bool) -> Binding<Bool> {
        Binding(get: { isOn }, set: { onSetSwitch(which, $0) })
    }

    private func scopeBinding(_ scope: ReminderScope) -> Binding<Bool> {
        Binding(
            get: { store.reminderScope.contains(scope) },
            set: { included in
                var next = store.reminderScope
                if included { next.insert(scope) } else { next.remove(scope) }
                store.setReminderScope(next)
            }
        )
    }

    /// KTD15: row insert and remove. `.movement`, so under Reduce Motion the well's height
    /// snaps while `settingsReveal(reduceMotion:)` keeps the fade.
    private var rowAnimation: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion)
    }

    /// M7A's list-reorder spring, for a committed edit that resorts the rows (R6).
    private var reorderAnimation: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
    }
}

/// R7: the provider hint beside Billing periods (`BillingPeriodScopeHint`). A checkbox greys its own title when
/// disabled but not a custom view in its label, so without this the hint read darker than
/// the label it qualifies whenever the rules were dimmed.
private struct ScopeHint: View {
    let text: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(text)
            .font(SettingsType.help)
            .foregroundStyle(isEnabled ? .secondary : .tertiary)
    }
}

private extension View {
    /// R9: the Accounts dim idiom — disabled and at 0.45 — cross-faded, never pulsed.
    func dimmedUnless(_ enabled: Bool, reduceMotion: Bool) -> some View {
        self
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                value: enabled
            )
    }
}
