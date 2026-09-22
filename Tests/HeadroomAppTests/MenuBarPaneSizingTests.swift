import AppKit
import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

/// AppKit pins the Settings detail column's minimum height to the pane's size at a
/// zero-width proposal. The Menu Bar pane's pinned preview tile sits outside a scroll view,
/// so its text wrapped a word per line there and demanded ~1,000pt: the split view outgrew
/// the window, which centred it and clipped both columns' tops under the title bar.
@MainActor
struct MenuBarPaneSizingTests {
    @Test func theMenuBarPaneDemandsNoMinimumHeight() {
        let suiteName = "co.zantos.headroom.menu-bar-sizing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            preferences: Preferences(defaults: defaults)
        )
        let controller = NSHostingController(rootView: MenuBarSettingsPane(store: store))
        let minimum = controller.sizeThatFits(in: .zero)
        // The scaffold panes report 0 here; the regression reported ~1,000.
        #expect(minimum.height < SettingsView.minimumWindowHeight / 2)
    }
}
