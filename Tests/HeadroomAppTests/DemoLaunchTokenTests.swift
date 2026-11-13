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
    /// `.standard`, even though the hosted unit suite itself launches isolated fixtures.
    @Test func aNormalLaunchKeepsTheStandardDomain() {
        #expect(AppComposition.resolveLaunchDefaults(arguments: ["Headroom"], environment: [:]) === UserDefaults.standard)
        #expect(AppComposition.resolveLaunchDefaults(
            arguments: ["Headroom", "--render-popover", "shots"], environment: [:]
        ) === UserDefaults.standard)
    }

    @Test func hostedLaunchWithoutDemoArgumentUsesIsolatedDefaults() {
        #expect(AppComposition.resolveLaunchDefaults(
            arguments: ["Headroom"],
            environment: ["XCTestConfigurationFilePath": "/tmp/fixture.xctestconfiguration"]
        ) !== UserDefaults.standard)
    }

    @Test func hostedUnitSuiteUsesIsolatedLaunchDefaults() {
        #expect(DemoFixture.isEnabled)
        #expect(AppComposition.launchDefaults !== UserDefaults.standard)
        let key = "headroom-hosted-suite-domain-probe-\(UUID().uuidString)"
        AppComposition.launchDefaults.set(true, forKey: key)
        defer { AppComposition.launchDefaults.removeObject(forKey: key) }
        #expect(AppComposition.launchDefaults.bool(forKey: key))
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    @Test func sessionReliabilityCollectionIsAbsentFromEveryInertLaunch() {
        let defaults = UserDefaults(suiteName: "headroom.session-composition.tests.\(UUID().uuidString)")!
        for flag in ["--demo", "--render-popover", "--render-widgets", "--render-loading-preview", "--bench-ui"] {
            #expect(AppComposition.makeSessionReliabilityRecord(
                arguments: ["Headroom", flag], environment: [:], defaults: defaults
            ) == nil)
        }
        #expect(AppComposition.makeSessionReliabilityRecord(
            arguments: ["Headroom"],
            environment: ["XCTestConfigurationFilePath": "/tmp/fixture.xctestconfiguration"],
            defaults: defaults
        ) == nil)
        #expect(AppComposition.makeSessionReliabilityRecord(
            arguments: ["Headroom"], environment: [:], defaults: defaults
        ) != nil)
        #expect(defaults.dictionaryRepresentation()["sessionReliability.v1"] == nil)
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

    // MARK: --account-layout

    @Test func accountLayoutTokenSeedsTheDemoLayout() {
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Headroom", "--demo", "multi-7", "--account-layout", "compact"]
        ) == .compact)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Headroom", "--demo", "--account-layout", "standard"]
        ) == .standard)
    }

    /// Like `--account-title-ink`, an absent or malformed token reseeds the default so one
    /// capture cannot leak into the next; entry rejects the malformed ones under `--demo`.
    @Test func absentOrMalformedAccountLayoutFallsBackToStandard() {
        #expect(AppComposition.demoAccountLayout(arguments: ["Headroom", "--demo"]) == .standard)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Headroom", "--demo", "--account-layout"]
        ) == .standard)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Headroom", "--demo", "--account-layout", "Compact"]
        ) == .standard)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Headroom", "--demo", "--account-layout", "columns"]
        ) == .standard)
    }

    // MARK: XCTest-host widget exporter

    /// The app hosts its own test bundle, so a run launches it for real and its first refresh
    /// reached the App Group container — which made macOS put up the "access data from other
    /// apps" alert and block the run until someone dismissed it. Only the XCTest host may
    /// swap the exporter; every other launch still composes the App Group one.
    ///
    /// The real branch is asserted through the decision rather than by building it: calling
    /// `widgetExporter(environment: [:])` here would reach the container and raise the very
    /// alert this exists to avoid.
    @Test func onlyTheXCTestHostComposesANoOpWidgetExporter() {
        #expect(AppComposition.usesNoOpWidgetExporter(
            environment: ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]
        ))
        #expect(!AppComposition.usesNoOpWidgetExporter(environment: [:]))
        #expect(!AppComposition.usesNoOpWidgetExporter(
            environment: ["PATH": "/usr/bin", "XCTestConfigurationFilePathX": "/tmp/probe"]
        ))
        // This process is the test host, so its own composition must take the no-op branch.
        #expect(AppComposition.usesNoOpWidgetExporter())
        #expect(AppComposition.widgetExporter() is NoOpWidgetSnapshotExporter)
    }

    // MARK: Claude identity reader (default-login plan U2)

    /// Only a real launch reads `.claude.json`. Demo scenarios (`remembered`, `merged`,
    /// `multi-3` and the rest), the render and bench harnesses and this XCTest host get no
    /// reader, so their Claude providers read no file. The decision is asserted without
    /// reading: building a reader opens nothing until a fetch runs.
    @Test func onlyARealLaunchWiresTheClaudeIdentityReaderAndEachRowGetsItsOwnFile() throws {
        for arguments in [
            ["Headroom", "--demo", "remembered"],
            ["Headroom", "--demo", "merged"],
            ["Headroom", "--demo", "multi-3"],
            ["Headroom", "--render-popover", "/tmp/x"],
            ["Headroom", "--render-widgets", "/tmp/x"],
            ["Headroom", "--bench-ui", "popover"],
        ] {
            #expect(AppComposition.claudeIdentityReader(configDirectory: nil, arguments: arguments, environment: [:]) == nil,
                    "\(arguments)")
        }
        #expect(AppComposition.claudeIdentityReader(configDirectory: nil) == nil)

        let builtIn = try #require(AppComposition.claudeIdentityReader(
            configDirectory: nil, arguments: ["Headroom"], environment: [:]
        ) as? ClaudeAccountEmailFileReader)
        #expect(builtIn.accountFile.path
            == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json").path)
        let extraHome = URL(fileURLWithPath: "/tmp/headroom-tests/claude/work/config", isDirectory: true)
        let extra = try #require(AppComposition.claudeIdentityReader(
            configDirectory: extraHome, arguments: ["Headroom"], environment: [:]
        ) as? ClaudeAccountEmailFileReader)
        #expect(extra.accountFile.path == "/tmp/headroom-tests/claude/work/config/.claude.json")
    }

    @Test func widgetStyleTokenSelectsThePreviewedStyle() {
        #expect(AppComposition.demoWidgetStyle(arguments: ["Headroom", "--widget-style", "tightestFirst"]) == .tightestFirst)
    }

    @Test func absentOrUnknownWidgetStyleTokenPreviewsNestedMeter() {
        #expect(AppComposition.demoWidgetStyle(arguments: ["Headroom"]) == .nestedMeter)
        #expect(AppComposition.demoWidgetStyle(arguments: ["Headroom", "--widget-style", "classic"]) == .nestedMeter)
        #expect(AppComposition.demoWidgetStyle(arguments: ["Headroom", "--widget-style"]) == .nestedMeter)
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
