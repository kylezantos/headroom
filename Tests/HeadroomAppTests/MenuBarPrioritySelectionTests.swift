import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// The Menu Bar pane used to name a provider whose subscription switch is off as the live
/// priority, while `UsageStore.menuBarMeters` had already dropped it and gone neutral.
struct MenuBarPrioritySelectionTests {
    private let names: (ProviderID) -> String = { $0.raw.capitalized }

    @Test func autoIsReportedAsAuto() {
        #expect(MenuBarPrioritySelection.label(
            source: .auto,
            fetchedOrder: [.claude, .codex],
            displayName: names
        ) == "Auto")
    }

    @Test func selectedProvidersAreNamedInRegistryOrder() {
        #expect(MenuBarPrioritySelection.label(
            source: .providers([.codex, .claude]),
            fetchedOrder: [.claude, .codex, .grok],
            displayName: names
        ) == "Claude + Codex")
    }

    /// The stored preference keeps the switched-off provider (R11: "off" means "not fetched",
    /// not "forgotten"), but the control stops claiming it drives the pill.
    @Test func aSwitchedOffProviderDropsOutOfTheReportedSelection() {
        #expect(MenuBarPrioritySelection.label(
            source: .providers([.claude, .grok]),
            fetchedOrder: [.claude, .codex],
            displayName: names
        ) == "Claude")
    }

    /// Every stored pick is off: the menu bar renders a neutral pill, which is neither the
    /// named provider nor Auto's live behavior.
    @Test func anEntirelySwitchedOffSelectionReportsNone() {
        #expect(MenuBarPrioritySelection.label(
            source: .providers([.grok]),
            fetchedOrder: [.claude, .codex],
            displayName: names
        ) == "None")
    }

    /// Switching the provider back on restores it without the user re-picking it — the label
    /// is derived, so the stored selection is all that has to survive.
    @Test func switchingAProviderBackOnRestoresItToTheLabel() {
        let stored = MenuBarFillSource.providers([.claude, .grok])
        #expect(MenuBarPrioritySelection.label(
            source: stored,
            fetchedOrder: [.claude, .codex, .grok],
            displayName: names
        ) == "Claude + Grok")
    }
}
