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

    @Test func menuBarWindowSourcesDefaultAndPersistIndependently() {
        let prefs = Preferences(defaults: freshDefaults())

        #expect(prefs.menuBarWindowSource(for: .claude) == .weekly)
        #expect(prefs.menuBarWindowSource(for: .codex) == .weekly)

        prefs.setMenuBarWindowSource(.fiveHour, for: .claude)

        #expect(prefs.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowSource(for: .codex) == .weekly)
    }

    @Test func providerWindowSourcesInheritLegacySharedPreferenceUntilOverridden() {
        let defaults = freshDefaults()
        defaults.set(MenuBarWindowSource.fiveHour.rawValue, forKey: "menuBarWindowSource")
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowSource(for: .codex) == .fiveHour)

        prefs.setMenuBarWindowSource(.weekly, for: .codex)

        #expect(prefs.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowSource(for: .codex) == .weekly)
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
            "anthropicAPI",
            "openAIAPI",
            "xaiAPI",
            "cursorAPI",
        ])
    }

    @Test func apiSpendPeriodDefaultsAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.apiSpendPeriod == .currentMonth)
        prefs.apiSpendPeriod = .rolling30Days
        #expect(prefs.apiSpendPeriod == .rolling30Days)
    }
}
