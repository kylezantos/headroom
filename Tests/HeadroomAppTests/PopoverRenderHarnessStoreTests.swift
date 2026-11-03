import Testing
import HeadroomCore
@testable import Headroom

/// The multi-account capture once drew only Claude and Codex: Grok and Cursor surfaces default
/// OFF and no spend providers were wired (BUGS.md, resolved Oct 2026).
@MainActor
struct PopoverRenderHarnessStoreTests {
    @Test func envelopeShowsEveryProviderInTheFixture() {
        let store = PopoverRenderHarness.multiStore(for: .envelope)
        #expect(store.providerOrder == [.claude, .codex, .grok, .cursor, .copilot])
    }

    /// Copilot plan U7: Copilot defaults OFF like Grok and Cursor, so the five-provider
    /// capture must enable it or the card never draws.
    @Test func fiveProviderScenarioShowsEveryRegisteredProvider() {
        let store = PopoverRenderHarness.multiStore(for: .fiveProviders)
        #expect(store.providerOrder == DemoFixture.registeredProviderOrder)
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
