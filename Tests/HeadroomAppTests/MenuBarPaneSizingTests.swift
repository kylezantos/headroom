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
        // Every subscription on, so every provider can take a pill (Antigravity is off by default).
        let preferences = Preferences(defaults: defaults)
        for surface in UsageSurface.allCases { preferences.setSurfaceEnabled(true, for: surface) }
        let store = UsageStore(
            providers: DemoFixture.registeredProviderOrder.map { id in
                DemoUsageProvider(id: id, displayName: id.displayName, snapshot: DemoFixture.claudeSnapshot)
            },
            preferences: preferences
        )
        store.setShowMenuBarMarks(true)
        store.setShowMenuBarPercentage(true)
        // Every pill the menu bar allows, from all seven providers: the cap keeps registry
        // order, so Antigravity's mark is in the strip.
        store.setMenuBarFillSource(.providers(Set(DemoFixture.registeredProviderOrder)))
        #expect(store.selectedMenuBarProviders.count == UsageStore.maximumMenuBarPills)
        #expect(store.selectedMenuBarProviders.contains(.antigravity))
        #expect(store.menuBarShowsMarks)

        let controller = NSHostingController(rootView: MenuBarSettingsPane(store: store))
        #expect(controller.sizeThatFits(in: .zero).height < SettingsView.minimumWindowHeight / 2)

        // The detail column at the window floor and at the window's default size: the window
        // less the sidebar's 216pt.
        for window in [CGSize(width: SettingsView.minimumWindowWidth, height: SettingsView.minimumWindowHeight),
                       CGSize(width: SettingsView.windowWidth, height: SettingsView.windowHeight)] {
            let column = CGSize(width: window.width - 216, height: window.height)
            let fitted = controller.sizeThatFits(in: column)
            #expect(fitted.width <= column.width + 0.5, "the pane is \(fitted.width)pt wide in \(window)")
            #expect(fitted.height <= column.height + 0.5, "the pane is \(fitted.height)pt tall in \(window)")
        }
    }
}
