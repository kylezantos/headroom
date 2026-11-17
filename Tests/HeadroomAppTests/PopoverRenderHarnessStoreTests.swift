import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// The multi-account capture once drew only Claude and Codex: Grok and Cursor surfaces default
/// OFF and no spend providers were wired (BUGS.md, resolved Oct 2026).
@MainActor
@Suite(.sharedAppState)
struct PopoverRenderHarnessStoreTests {
    /// OpenCode plan U9: the demo registry every parity test derives from is the app's own
    /// composition registry, so registering a provider without demo fixtures fails here.
    @Test func demoRegistryIsTheCompositionRegistry() {
        #expect(AppComposition.subscriptionProviderRegistry.map(\.id) == DemoFixture.registeredProviderOrder)
    }

    @Test func envelopeShowsEveryProviderInTheFixture() {
        let store = PopoverRenderHarness.multiStore(for: .envelope)
        #expect(store.providerOrder == [.claude, .codex, .grok, .cursor, .copilot])
    }

    /// Copilot plan U7: Copilot defaults OFF like Grok and Cursor, so the five-provider
    /// capture must enable it or the card never draws.
    @Test func fiveProviderScenarioShowsEveryRegisteredProvider() {
        let store = PopoverRenderHarness.multiStore(for: .fiveProviders)
        #expect(store.providerOrder == DemoFixture.registeredProviderOrder.filter { $0 != .opencode && $0 != .antigravity })
    }

    /// OpenCode plan U9 (KTD14): OpenCode defaults OFF like Copilot, so the six-provider
    /// capture must enable it or the card never draws.
    @Test func sixProviderScenarioShowsEveryRegisteredProvider() {
        let store = PopoverRenderHarness.multiStore(for: .sixProviders)
        #expect(store.providerOrder == DemoFixture.registeredProviderOrder)
        #expect(store.isSurfaceEnabled(.opencodeSubscription))
    }

    /// OpenCode plan U9: every scenario's harness store and live demo store draw every
    /// provider its fixture lists, in registry order (PR #189's two-provider captures).
    @Test(arguments: DemoFixture.MultiAccountScenario.allCases)
    func everyScenarioStoreDrawsEveryFixtureProvider(_ scenario: DemoFixture.MultiAccountScenario) {
        let listed = Set(DemoFixture.multiFixture(for: scenario).accounts.map(\.providerID))
        let expected = DemoFixture.registeredProviderOrder.filter(listed.contains)
        let harness = PopoverRenderHarness.multiStore(for: scenario)
        #expect(harness.providerOrder == expected, "\(scenario) harness")
        let suite = "headroom.render-harness.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let demo = AppComposition.demoMultiAccountStore(scenario: scenario, defaults: defaults)
        #expect(demo.providerOrder == expected, "\(scenario) demo")
    }

    @Test func fourProviderScenariosShowGrokAndCursor() {
        for scenario in [DemoFixture.MultiAccountScenario.multiProviders, .fourDefault] {
            let store = PopoverRenderHarness.multiStore(for: scenario)
            #expect(store.providerOrder.contains(.grok), "\(scenario)")
            #expect(store.providerOrder.contains(.cursor), "\(scenario)")
        }
    }

    @Test func spendStatesWiresAndEnablesEverySpendProvider() {
        let store = PopoverRenderHarness.multiStore(for: .spendStates)
        #expect(store.registeredAPISpendProviderOrder == [.claude, .codex, .grok, .cursor])
        for id in store.registeredAPISpendProviderOrder {
            #expect(UsageSurface.api(for: id).map(store.isSurfaceEnabled) == true, "\(id)")
        }
    }
}
