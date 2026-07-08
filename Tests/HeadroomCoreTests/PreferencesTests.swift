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
        prefs.pollIntervalMinutes = 0            // clamped to >= 1
        #expect(prefs.pollIntervalMinutes >= 1)
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

    @Test func menuBarFillSourceSupportsBothProviders() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.menuBarFillSource == .none)
        prefs.menuBarFillSource = .both
        #expect(prefs.menuBarFillSource == .both)
    }

    @Test func widgetsEnabledDefaultsOnAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.widgetsEnabled)
        prefs.widgetsEnabled = false
        #expect(!prefs.widgetsEnabled)
        prefs.widgetsEnabled = true
        #expect(prefs.widgetsEnabled)
    }

    @Test func codexSparkCountersDefaultBySurfaceAndPersist() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.showCodexSparkCountersInApp)
        #expect(!prefs.showCodexSparkCountersInWidgets)

        prefs.showCodexSparkCountersInApp = false
        prefs.showCodexSparkCountersInWidgets = true

        #expect(!prefs.showCodexSparkCountersInApp)
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
        #expect(!prefs.isSurfaceEnabled(.anthropicAPI))
        #expect(!prefs.isSurfaceEnabled(.openAIAPI))

        prefs.setSurfaceEnabled(false, for: .claudeSubscription)
        prefs.setSurfaceEnabled(true, for: .openAIAPI)
        #expect(!prefs.isSurfaceEnabled(.claudeSubscription))
        #expect(prefs.isSurfaceEnabled(.openAIAPI))
    }

    @Test func apiSpendPeriodDefaultsAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.apiSpendPeriod == .currentMonth)
        prefs.apiSpendPeriod = .rolling30Days
        #expect(prefs.apiSpendPeriod == .rolling30Days)
    }
}
