import Testing
import HeadroomCore
@testable import Headroom

/// The multi-account capture once drew only Claude and Codex: Grok and Cursor surfaces default
/// OFF and no spend providers were wired (BUGS.md, resolved Oct 2026).
@MainActor
struct PopoverRenderHarnessStoreTests {
    @Test func envelopeShowsEveryProviderInTheFixture() {
        let store = PopoverRenderHarness.multiStore(for: .envelope)
        #expect(store.providerOrder == [.claude, .codex, .grok, .cursor])
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
