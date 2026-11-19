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
@Suite(.sharedAppState)
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

    /// CA-MB1: the pinned tile gained the "Show provider marks" row and its help line, and
    /// with marks and percentages on every pill and sample is at its widest. The pane must
    /// still demand no height at the zero-width proposal, and at the minimum window it must
    /// leave the arranger's scroll view room below the pinned tile.
    @Test func theMenuBarPaneFitsWithMarksAndPercentagesOn() {
        let suiteName = "co.zantos.headroom.menu-bar-sizing-marks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(
            providers: DemoFixture.registeredProviderOrder.map { id in
                DemoUsageProvider(id: id, displayName: id.displayName, snapshot: DemoFixture.claudeSnapshot)
            },
            preferences: Preferences(defaults: defaults)
        )
        store.setShowMenuBarMarks(true)
        store.setShowMenuBarPercentage(true)
        #expect(store.menuBarShowsMarks)

        let controller = NSHostingController(rootView: MenuBarSettingsPane(store: store))
        #expect(controller.sizeThatFits(in: .zero).height < SettingsView.minimumWindowHeight / 2)

        // The detail column at the window floor: the window less the sidebar's 216pt.
        let floor = CGSize(width: SettingsView.minimumWindowWidth - 216, height: SettingsView.minimumWindowHeight)
        let fitted = controller.sizeThatFits(in: floor)
        #expect(fitted.width <= floor.width + 0.5, "the pane is \(fitted.width)pt wide at the floor")
        #expect(fitted.height <= floor.height + 0.5, "the pane is \(fitted.height)pt tall at the floor")
    }
}
