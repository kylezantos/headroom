import Testing
import Foundation
@testable import HeadroomCore

struct DemoScreenshotDataVariantsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func variantKeyRoundTripsInCompanionDemoModeStore() throws {
        let suiteName = "DemoScreenshotDataVariantsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)

        // Defaults to "full" when unset
        #expect(store.variant == "full")

        // Rounds-trips the variant through set/get
        #expect(store.setVariant("claudeOnly") == .changed)
        #expect(store.variant == "claudeOnly")

        // Returns unchanged when setting to the same value
        #expect(store.setVariant("claudeOnly") == .unchanged)
        #expect(store.variant == "claudeOnly")

        // Updates to a different variant
        #expect(store.setVariant("codexFiveHourReturns") == .changed)
        #expect(store.variant == "codexFiveHourReturns")
    }

    @Test func unknownVariantDefaultsToFull() {
        let suiteName = "DemoScreenshotDataVariantsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        defaults?.set("unknownVariant", forKey: CompanionDemoModeStore.variantKey)
        let store = CompanionDemoModeStore(defaults: defaults)

        #expect(store.variant == "unknownVariant")
        let envelope = DemoScreenshotData.envelope(for: store.variant)
        let fullEnvelope = DemoScreenshotData.envelope(for: "full")
        // Unknown variant falls back to full fixture - compare provider counts and shapes
        #expect(envelope.providers.count == fullEnvelope.providers.count)
        #expect(envelope.apiSpendProviders.count == fullEnvelope.apiSpendProviders.count)
    }







    @Test func claudeFixturesHaveExtraWeeklyWindow() {
        let fixtures = ["full", "noSpend", "claudeOnly", "claudeOnlyNoSpend", "codexFiveHourReturns", "attention"]
        for variantName in fixtures {
            let envelope = DemoScreenshotData.envelope(for: variantName)
            guard let claudeProvider = envelope.providers.first(where: { $0.id == ProviderID.claude.raw }) else {
                Issue.record("Claude provider not found in \(variantName)")
                return
            }
            #expect(claudeProvider.extraWeeklyWindows.count == 1)
        }
    }

    @Test func allFixturesAreValidEnvelopes() throws {
        let variants = ["full", "noSpend", "claudeOnly", "claudeOnlyNoSpend", "codexFiveHourReturns", "attention", "fourProviders"]
        for variant in variants {
            let envelope = DemoScreenshotData.envelope(for: variant)
            // Schema version should be current
            #expect(envelope.schemaVersion == WidgetSnapshotEnvelope.schemaVersion)
            // Status should be enabled
            #expect(envelope.status == .enabled)
            // Providers must be non-empty
            #expect(!envelope.providers.isEmpty)
            // Each provider must have at least one window
            for provider in envelope.providers {
                #expect(!provider.subscriptionWindows.isEmpty || !provider.extraCounterWindows.isEmpty)
            }
        }
    }

    @Test func fullAndCodexFiveHourHaveSpend() {
        #expect(!DemoScreenshotData.envelope(for: "full").apiSpendProviders.isEmpty)
        #expect(!DemoScreenshotData.envelope(for: "codexFiveHourReturns").apiSpendProviders.isEmpty)
    }

    @Test func noSpendAndClaudeOnlyNoSpendHaveNoSpend() {
        #expect(DemoScreenshotData.envelope(for: "noSpend").apiSpendProviders.isEmpty)
        #expect(DemoScreenshotData.envelope(for: "claudeOnlyNoSpend").apiSpendProviders.isEmpty)
    }

    @Test func attentionFixtureHasStaleProvider() {
        let envelope = DemoScreenshotData.envelope(for: "attention")
        let claudeProvider = envelope.providers.first { $0.id == ProviderID.claude.raw }
        guard let claudeProvider else {
            Issue.record("Could not find Claude provider")
            return
        }
        if case .stale = claudeProvider.freshness {
            // Expected
        } else {
            Issue.record("Claude provider should be stale in attention fixture")
        }
    }

    // MARK: - L9P settings preview fixture

    /// The Settings › Widgets & iPhone strip renders the real widget bodies, so its
    /// fixture has to be frozen: any `Date()` in it would make the medium tile's
    /// "Updated N min ago" footer drift and invite the reader to trust the preview as
    /// live data.
    @Test func settingsPreviewFixtureIsFrozen() {
        let first = DemoScreenshotData.settingsPreviewEnvelope
        let second = DemoScreenshotData.settingsPreviewEnvelope
        #expect(first == second)
        #expect(first.generatedAt == DemoScreenshotData.settingsPreviewNow.addingTimeInterval(-4 * 60))
        for provider in first.providers {
            for window in provider.windows {
                #expect(window.resetSchedule == .scheduled(DemoScreenshotData.settingsPreviewNow.addingTimeInterval(3 * 3_600)))
                #expect(window.resetLabel?.isEmpty == false)
            }
        }
    }

    /// The strip previews the small and medium families, which draw
    /// `primarySubscriptionWindow` and `displaySubscriptionWindows`. A fixture whose
    /// windows fell outside those accessors would preview as an empty tile.
    @Test func settingsPreviewFixtureFillsBothWidgetFamilies() {
        let envelope = DemoScreenshotData.settingsPreviewEnvelope
        // `widgetProviders` caps the list at two; the fixture is already that shape, so
        // neither tile silently drops a provider.
        #expect(envelope.widgetProviders.count == 2)
        #expect(envelope.widgetProviders.map(\.id) == [ProviderID.claude.raw, ProviderID.codex.raw])
        // No API spend: the medium tile shows its "from Mac · …" footer instead of the
        // spend strip, whose provider marks would bypass the app's injected renderer.
        #expect(envelope.apiSpendProviders.isEmpty)
        for provider in envelope.widgetProviders {
            #expect(provider.primarySubscriptionWindow != nil)
            #expect(provider.displaySubscriptionWindows.count == 2)
        }
    }
}
