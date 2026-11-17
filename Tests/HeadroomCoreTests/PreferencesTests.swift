import Testing
import Foundation
@testable import HeadroomCore

/// U8 test scenarios: renewal-date round-trip and poll-interval persistence/default.
struct PreferencesTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func renewalDateRoundTrips() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.renewalDate(for: .claude) == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        prefs.setRenewalDate(date, for: .claude)
        #expect(prefs.renewalDate(for: .claude)?.timeIntervalSince1970 == date.timeIntervalSince1970)
        // Per-provider isolation: setting Claude doesn't set Codex.
        #expect(prefs.renewalDate(for: .codex) == nil)
        prefs.setRenewalDate(nil, for: .claude)
        #expect(prefs.renewalDate(for: .claude) == nil)
    }

    @Test func intervalPersistsAndDefaults() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.pollIntervalMinutes == Preferences.defaultIntervalMinutes) // unset default
        prefs.pollIntervalMinutes = 12
        #expect(prefs.pollIntervalMinutes == 12)
        prefs.pollIntervalMinutes = 1
        #expect(prefs.pollIntervalMinutes == Preferences.minimumIntervalMinutes)

        // Persisted values from older builds are clamped on read as well as write.
        let defaults = freshDefaults()
        defaults.set(1, forKey: "pollIntervalMinutes")
        #expect(Preferences(defaults: defaults).pollIntervalMinutes == Preferences.minimumIntervalMinutes)
    }

    @Test func pollingEngineUsesTheSameTwoMinuteFloor() {
        #expect(PollingEngine.clampedIntervalMinutes(1) == Preferences.minimumIntervalMinutes)
        #expect(PollingEngine.clampedIntervalMinutes(5) == 5)
    }

    @Test func appearancePreferenceDefaultsPersistsAndIgnoresUnknownValues() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.appearancePreference == .system)

        prefs.appearancePreference = .dark
        #expect(prefs.appearancePreference == .dark)

        defaults.set("sepia", forKey: "appearancePreference")
        #expect(prefs.appearancePreference == .system)
    }

    @Test func menuBarPercentageDefaultsOffAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(!prefs.showMenuBarPercentage)
        prefs.showMenuBarPercentage = true
        #expect(prefs.showMenuBarPercentage)
    }

    @Test func usagePercentageModeDefaultsPersistsAndIgnoresUnknownValues() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.usagePercentageMode == .remaining)

        prefs.usagePercentageMode = .used
        #expect(prefs.usagePercentageMode == .used)

        defaults.set("spent", forKey: "usagePercentageMode")
        #expect(prefs.usagePercentageMode == .remaining)
    }

    @Test func accountTitleInkDefaultsPersistsAndIgnoresUnknownValues() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.accountTitleInk == .neutral)

        prefs.accountTitleInk = .brand
        #expect(prefs.accountTitleInk == .brand)

        defaults.set("tinted", forKey: "accountTitleInk")
        #expect(prefs.accountTitleInk == .neutral)
    }

    @Test func accountLayoutDefaultsPersistsAndIgnoresUnknownValues() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.accountLayout == .standard)

        prefs.accountLayout = .compact
        #expect(prefs.accountLayout == .compact)
        #expect(Preferences(defaults: defaults).accountLayout == .compact)

        defaults.set("dense", forKey: "accountLayout")
        #expect(prefs.accountLayout == .standard)
    }

    @Test func emailAccountNamesAreOptInAndPersist() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(!prefs.useEmailAsAccountName)
        prefs.useEmailAsAccountName = true
        #expect(Preferences(defaults: defaults).useEmailAsAccountName)
        prefs.useEmailAsAccountName = false
        #expect(!Preferences(defaults: defaults).useEmailAsAccountName)
    }

    @Test func horizontalExpansionDefaultsOnAndPersistsAnOptOut() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.expandAccountsHorizontally)
        prefs.expandAccountsHorizontally = false
        #expect(!Preferences(defaults: defaults).expandAccountsHorizontally)
        prefs.expandAccountsHorizontally = true
        #expect(Preferences(defaults: defaults).expandAccountsHorizontally)
    }

    @Test func meterStyleComponentsDefaultPersistAndIgnoreUnknownValuesIndependently() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.meterFormat == MeterStyle.default.format)
        #expect(prefs.meterShape == MeterStyle.default.shape)
        #expect(prefs.meterFill == MeterStyle.default.fill)

        prefs.meterFormat = .full
        prefs.meterShape = .tube
        prefs.meterFill = .ghost
        #expect(prefs.meterStyle == MeterStyle(format: .full, shape: .tube, fill: .ghost))
        #expect(prefs.meterFormat == .full)
        #expect(prefs.meterShape == .tube)
        #expect(prefs.meterFill == .ghost)

        defaults.set("wide", forKey: "meterFormat")
        #expect(prefs.meterFormat == MeterStyle.default.format)
        #expect(prefs.meterShape == .tube)
        #expect(prefs.meterFill == .ghost)

        defaults.set("blob", forKey: "meterShape")
        #expect(prefs.meterShape == MeterStyle.default.shape)
        #expect(prefs.meterFill == .ghost)

        defaults.set("sparkle", forKey: "meterFill")
        #expect(prefs.meterFill == MeterStyle.default.fill)

        let replacement = MeterStyle(format: .micro, shape: .segmented, fill: .hueRamp)
        prefs.meterStyle = replacement
        #expect(prefs.meterStyle == replacement)
    }

    @Test func menuBarFillSourceMigratesEveryLegacyValue() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.menuBarFillSource == .auto)

        let migrations: [(String, MenuBarFillSource)] = [
            ("none", .auto),
            ("both", .providers([.claude, .codex])),
            ("claude", .providers([.claude])),
            ("codex", .providers([.codex])),
        ]
        for (raw, expected) in migrations {
            defaults.set(raw, forKey: "menuBarFillSource")
            #expect(prefs.menuBarFillSource == expected)
        }
    }

    @Test func menuBarProviderSetPersistsInDeterministicOrder() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.menuBarFillSource = .providers([.grok, .claude, .codex])

        #expect(defaults.string(forKey: "menuBarFillSource") == "providers")
        #expect(defaults.stringArray(forKey: "menuBarFillProviders") == ["claude", "codex", "grok"])
        #expect(prefs.menuBarFillSource == .providers([.claude, .codex, .grok]))
    }

    @Test func menuBarOrderAndWidgetMigrationStatePersistIndependently() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.menuBarProviderOrder.isEmpty)
        #expect(prefs.widgetPriorityProviders == nil)
        prefs.menuBarProviderOrder = [.cursor, .claude, .codex, .grok]
        prefs.widgetPriorityProviders = [.codex]
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.menuBarProviderOrder == [.cursor, .claude, .codex, .grok])
        #expect(reloaded.widgetPriorityProviders == [.codex])
        prefs.widgetPriorityProviders = []
        #expect(reloaded.widgetPriorityProviders == [])
        #expect(reloaded.menuBarFillSource == .auto)
    }

    @Test func menuBarWindowSourcesDefaultAndPersistIndependently() {
        let prefs = Preferences(defaults: freshDefaults())

        #expect(prefs.menuBarWindowChoice(for: .claude) == .weekly)
        #expect(prefs.menuBarWindowChoice(for: .codex) == .weekly)

        prefs.setMenuBarWindowChoice(.fiveHour, for: .claude)

        #expect(prefs.menuBarWindowChoice(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowChoice(for: .codex) == .weekly)
    }

    @Test func providerWindowSourcesInheritLegacySharedPreferenceUntilOverridden() {
        let defaults = freshDefaults()
        defaults.set(MenuBarWindowChoice.fiveHour.rawValue, forKey: "menuBarWindowSource")
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.menuBarWindowChoice(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowChoice(for: .codex) == .fiveHour)

        prefs.setMenuBarWindowChoice(.weekly, for: .codex)

        #expect(prefs.menuBarWindowChoice(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowChoice(for: .codex) == .weekly)
    }

    @Test func menuBarWindowChoiceReadsPreIDValuesAndTracksExplicitChoices() {
        let defaults = freshDefaults()
        defaults.set("weekly", forKey: "menuBarWindowSource")
        defaults.set("fiveHour", forKey: "menuBarWindowSource.codex")
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.menuBarWindowChoice(for: .codex) == .fiveHour)
        #expect(prefs.hasChosenMenuBarWindow(for: .codex))
        // The shared legacy value is inherited but does not count as a choice for this provider.
        #expect(prefs.menuBarWindowChoice(for: .cursor) == .weekly)
        #expect(!prefs.hasChosenMenuBarWindow(for: .cursor))

        prefs.setMenuBarWindowChoice(.window(id: "billing:Other Models"), for: .cursor)
        #expect(prefs.menuBarWindowChoice(for: .cursor) == .window(id: "billing:Other Models"))
        #expect(defaults.string(forKey: "menuBarWindowSource.cursor") == "billing:Other Models")

        prefs.setMenuBarWindowChoice(.closest, for: .claude)
        #expect(prefs.menuBarWindowChoice(for: .claude) == .closest)
    }

    @Test func widgetsEnabledDefaultsOnAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.widgetsEnabled)
        prefs.widgetsEnabled = false
        #expect(!prefs.widgetsEnabled)
        prefs.widgetsEnabled = true
        #expect(prefs.widgetsEnabled)
    }

    @Test func codexSparkCountersDefaultOffOnBothSurfacesAndPersist() {
        let prefs = Preferences(defaults: freshDefaults())
        // Both surfaces default off (Jul 2026 density audit); Settings opts back in.
        #expect(!prefs.showCodexSparkCountersInApp)
        #expect(!prefs.showCodexSparkCountersInWidgets)

        prefs.showCodexSparkCountersInApp = true
        prefs.showCodexSparkCountersInWidgets = true

        #expect(prefs.showCodexSparkCountersInApp)
        #expect(prefs.showCodexSparkCountersInWidgets)
    }

    @Test func syncToIPhoneDefaultsOffAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(!prefs.syncToIPhoneEnabled)
        prefs.syncToIPhoneEnabled = true
        #expect(prefs.syncToIPhoneEnabled)
        prefs.syncToIPhoneEnabled = false
        #expect(!prefs.syncToIPhoneEnabled)
    }

    @Test func surfacesDefaultToSubscriptionsOnlyAndPersist() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.isSurfaceEnabled(.claudeSubscription))
        #expect(prefs.isSurfaceEnabled(.codexSubscription))
        #expect(!prefs.isSurfaceEnabled(.grokSubscription))
        #expect(!prefs.isSurfaceEnabled(.cursorSubscription))
        #expect(!prefs.isSurfaceEnabled(.copilotSubscription))
        #expect(!prefs.isSurfaceEnabled(.opencodeSubscription))
        #expect(!prefs.isSurfaceEnabled(.antigravitySubscription))
        #expect(!prefs.isSurfaceEnabled(.anthropicAPI))
        #expect(!prefs.isSurfaceEnabled(.openAIAPI))
        #expect(!prefs.isSurfaceEnabled(.xaiAPI))
        #expect(!prefs.isSurfaceEnabled(.cursorAPI))

        prefs.setSurfaceEnabled(false, for: .claudeSubscription)
        prefs.setSurfaceEnabled(true, for: .openAIAPI)
        #expect(!prefs.isSurfaceEnabled(.claudeSubscription))
        #expect(prefs.isSurfaceEnabled(.openAIAPI))
    }

    @Test func usageSurfaceRawValuesRemainStable() {
        #expect(UsageSurface.allCases.map(\.rawValue) == [
            "claudeSubscription",
            "codexSubscription",
            "grokSubscription",
            "cursorSubscription",
            "copilotSubscription",
            "anthropicAPI",
            "openAIAPI",
            "xaiAPI",
            "cursorAPI",
            // KTD13: appended, never inserted, so every stored key above keeps its meaning.
            "opencodeSubscription",
            "antigravitySubscription",
        ])
        #expect(UsageSurface.opencodeSubscription.providerID == .opencode)
        #expect(UsageSurface.opencodeSubscription.isSubscription)
        #expect(UsageSurface.subscription(for: .opencode) == .opencodeSubscription)
        #expect(UsageSurface.api(for: .opencode) == nil)
        #expect(UsageSurface.antigravitySubscription.providerID == .antigravity)
        #expect(UsageSurface.antigravitySubscription.isSubscription)
        #expect(UsageSurface.antigravitySubscription.displayName == "Antigravity subscription")
        #expect(UsageSurface.subscription(for: .antigravity) == .antigravitySubscription)
        #expect(UsageSurface.api(for: .antigravity) == nil)
    }

    /// An install that already chose its surfaces has no Antigravity key, and must not start
    /// running `agy` on upgrade.
    @Test func antigravityStaysOffAfterAnUpgrade() {
        let defaults = freshDefaults()
        let before = Preferences(defaults: defaults)
        for surface in UsageSurface.allCases where surface != .antigravitySubscription {
            before.setSurfaceEnabled(true, for: surface)
        }
        #expect(defaults.object(forKey: "surfaceEnabled.antigravitySubscription") == nil)

        let upgraded = Preferences(defaults: defaults)
        #expect(!upgraded.isSurfaceEnabled(.antigravitySubscription))
        #expect(upgraded.isSurfaceEnabled(.opencodeSubscription))
        upgraded.setSurfaceEnabled(true, for: .antigravitySubscription)
        #expect(Preferences(defaults: defaults).isSurfaceEnabled(.antigravitySubscription))
    }

    /// R11: an install that already chose its surfaces has no OpenCode key, and must not
    /// start fetching OpenCode on upgrade.
    @Test func openCodeStaysOffAfterAnUpgrade() {
        let defaults = freshDefaults()
        let before = Preferences(defaults: defaults)
        for surface in UsageSurface.allCases where surface != .opencodeSubscription {
            before.setSurfaceEnabled(true, for: surface)
        }
        #expect(defaults.object(forKey: "surfaceEnabled.opencodeSubscription") == nil)

        let upgraded = Preferences(defaults: defaults)
        #expect(!upgraded.isSurfaceEnabled(.opencodeSubscription))
        #expect(upgraded.isSurfaceEnabled(.copilotSubscription))
        upgraded.setSurfaceEnabled(true, for: .opencodeSubscription)
        #expect(Preferences(defaults: defaults).isSurfaceEnabled(.opencodeSubscription))
    }

    @Test func settingsPaneDefaultsPersistsAndIgnoresUnknownValues() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.settingsPane == .general)

        prefs.settingsPane = .accounts
        // A second reader over the same suite sees the persisted pane (R4: reopening
        // Settings lands on the last-visited pane, across launches).
        #expect(Preferences(defaults: defaults).settingsPane == .accounts)

        defaults.set("billing", forKey: "settingsPane")
        #expect(prefs.settingsPane == .general)
    }

    @Test func retiredAboutDestinationReopensGeneral() {
        let defaults = freshDefaults()
        defaults.set("about", forKey: "settingsPane")
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.settingsPane == .general)
        #expect(prefs.initialSettingsPane(hasSignedInAccount: false) == .general)
        #expect(prefs.initialSettingsPane(hasSignedInAccount: true) == .general)
    }

    @Test func firstOpenDefaultsToAccountsOnlyWhileNothingIsSignedIn() {
        // R2B1: the first open is the only one with a decision to make — and General is the
        // wrong answer on a Mac with nothing signed in, where all the work is in Accounts.
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.initialSettingsPane(hasSignedInAccount: false) == .accounts)
        #expect(prefs.initialSettingsPane(hasSignedInAccount: true) == .general)
        // The plain accessor is unchanged: nothing stored still reads General (R4).
        #expect(prefs.settingsPane == .general)

        // Once a pane has been visited the stored choice wins in both states — the first-run
        // rule must never override "reopen where I left off".
        prefs.settingsPane = .appearance
        #expect(prefs.initialSettingsPane(hasSignedInAccount: false) == .appearance)
        #expect(prefs.initialSettingsPane(hasSignedInAccount: true) == .appearance)

        // Including when the user deliberately parked on General.
        prefs.settingsPane = .general
        #expect(prefs.initialSettingsPane(hasSignedInAccount: false) == .general)
    }

    @Test func settingsPaneOrderAndGroupsMatchTheSidebar() {
        // R1: sidebar order and its two section headers are derived from the enum.
        #expect(SettingsPane.allCases == [.general, .appearance, .menuBar, .widgets, .notifications, .accounts, .apiSpend])
        #expect(SettingsPane.allCases.map(\.label) == [
            "General",
            "Appearance",
            "Menu Bar",
            "Widgets & iPhone",
            "Notifications",
            "Accounts",
            "API Spend",
        ])

        #expect(SettingsPane.Group.allCases == [.preferences, .sources])
        // R2B1: the header reads "App"; the raw value stays `preferences` so nothing that
        // persisted a group name migrates.
        #expect(SettingsPane.Group.allCases.map(\.label) == ["App", "Sources"])
        #expect(SettingsPane.Group.preferences.rawValue == "preferences")
        // R1 (notifications plan): Notifications is the last App destination, after Widgets.
        #expect(SettingsPane.Group.preferences.panes == [.general, .appearance, .menuBar, .widgets, .notifications])
        #expect(SettingsPane.Group.sources.panes == [.accounts, .apiSpend])
        // The groups partition every pane without overlap.
        #expect(SettingsPane.Group.allCases.flatMap(\.panes) == SettingsPane.allCases)
    }

    @Test func apiSpendPeriodDefaultsAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.apiSpendPeriod == .currentMonth)
        prefs.apiSpendPeriod = .rolling30Days
        #expect(prefs.apiSpendPeriod == .rolling30Days)
    }
}
