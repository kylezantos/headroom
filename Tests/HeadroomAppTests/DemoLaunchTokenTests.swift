import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// The launch-time seams demo captures depend on: which UserDefaults domain a run may touch,
/// and the two diagnostic style overrides.
@MainActor
struct DemoLaunchTokenTests {
    // MARK: Isolated demo defaults

    /// A `--demo` run must not read or write the user's settings. `HeadroomApp.init` used to
    /// build `Preferences()` on `.standard` while the store took the demo suite, so demo runs
    /// wrote `appearancePreference` / `settingsPane` / `showMenuBarPercentage` /
    /// `menuBarFillSource` into the real domain — and read their theme back out of it.
    @Test func everyDemoLaunchWritesOutsideTheStandardDomain() {
        for arguments in [
            ["Headroom", "--demo"],
            ["Headroom", "--demo", "multi-2"],
            ["Headroom", "--demo", "multi-4", "--meter-style", "full.chip.ghost"],
        ] {
            let key = "headroom-launch-domain-probe-\(UUID().uuidString)"
            let defaults = AppComposition.resolveLaunchDefaults(arguments: arguments)
            #expect(defaults !== UserDefaults.standard)
            defaults.set(true, forKey: key)
            defer { defaults.removeObject(forKey: key) }
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
    }

    /// Non-demo behavior stays byte-identical: the shipping app still reads and writes
    /// `.standard`, which is also what this (non-demo) test process resolves to.
    @Test func aNormalLaunchKeepsTheStandardDomain() {
        #expect(AppComposition.resolveLaunchDefaults(arguments: ["Headroom"]) === UserDefaults.standard)
        #expect(AppComposition.resolveLaunchDefaults(
            arguments: ["Headroom", "--render-popover", "shots"]
        ) === UserDefaults.standard)
        #expect(AppComposition.launchDefaults === UserDefaults.standard)
    }

    // MARK: --account-title-ink

    /// The review seam `AccountTitleInk.brand` had no path to: the demo prefs suite cannot be
    /// preset by hand and the popover is not an accessibility window (round-3 residual).
    @Test func accountTitleInkTokenParsesLikeMeterStyle() {
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Headroom", "--demo", "--account-title-ink", "brand"]
        ) == .brand)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Headroom", "--demo", "--account-title-ink", "neutral"]
        ) == .neutral)
    }

    /// An absent or malformed token reseeds the landed default, exactly like `demoMeterStyle`,
    /// so a previous run cannot leak into a later capture. Entry rejects the malformed ones
    /// before the menu bar launches.
    @Test func absentOrMalformedAccountTitleInkFallsBackToTheDefault() {
        #expect(AppComposition.demoAccountTitleInk(arguments: ["Headroom", "--demo"]) == .neutral)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Headroom", "--demo", "--account-title-ink"]
        ) == .neutral)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Headroom", "--demo", "--account-title-ink", "Brand"]
        ) == .neutral)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Headroom", "--demo", "--account-title-ink", "rainbow"]
        ) == .neutral)
    }

    @Test func meterStyleAndAccountTitleInkTokensCoexist() {
        let arguments = [
            "Headroom", "--demo", "multi-2",
            "--meter-style", "full.segmented.ghost",
            "--account-title-ink", "brand",
        ]
        #expect(AppComposition.demoMeterStyle(arguments: arguments) == MeterStyle(
            format: .full,
            shape: .segmented,
            fill: .ghost
        ))
        #expect(AppComposition.demoAccountTitleInk(arguments: arguments) == .brand)
    }
}
