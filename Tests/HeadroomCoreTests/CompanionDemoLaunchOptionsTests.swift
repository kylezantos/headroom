import Foundation
import Testing
@testable import HeadroomCore

/// KTD21: `--demo`, `--demo-variant <name>` and `--demo-screen <usage|settings|widgets>`.
struct CompanionDemoLaunchOptionsTests {
    @Test func aPlainLaunchIsNotADemo() {
        let options = CompanionDemoLaunchOptions.parse(["Headroom"])
        #expect(options == CompanionDemoLaunchOptions(isDemoLaunch: false, variant: nil, screen: .usage))
    }

    @Test func screenshotLaunchParsesVariantAndScreen() {
        let options = CompanionDemoLaunchOptions.parse(
            ["Headroom", "--demo", "--demo-variant", "fourProviders", "--demo-screen", "settings"])
        #expect(options.isDemoLaunch)
        #expect(options.variant == .fourProviders)
        #expect(options.screen == .settings)
        #expect(CompanionDemoLaunchOptions.parse(["Headroom", "--demo-screen", "widgets", "--demo"]).screen == .widgets)
    }

    @Test func everyVariantNameAndMacAliasParses() {
        for variant in CompanionDemoVariant.allCases {
            #expect(CompanionDemoLaunchOptions.parse(["Headroom", "--demo", "--demo-variant", variant.rawValue]).variant == variant)
        }
        #expect(CompanionDemoLaunchOptions.parse(["Headroom", "--demo", "--demo-variant", "multi-4"]).variant == .fourProviders)
    }

    /// U7: an unknown or missing `--demo-variant` value falls back to the default variant.
    @Test func unknownOrMissingVariantFallsBackToTheDefault() {
        for arguments in [
            ["Headroom", "--demo", "--demo-variant", "nope"],
            ["Headroom", "--demo", "--demo-variant"],
            ["Headroom", "--demo", "--demo-variant", "--demo-screen", "usage"],
            ["Headroom", "--demo", "--demo-variant", "full"],
        ] {
            #expect(CompanionDemoLaunchOptions.parse(arguments).variant == .multiAccount)
        }
    }

    @Test func unknownOrMissingScreenFallsBackToUsage() {
        #expect(CompanionDemoLaunchOptions.parse(["Headroom", "--demo", "--demo-screen", "home"]).screen == .usage)
        #expect(CompanionDemoLaunchOptions.parse(["Headroom", "--demo", "--demo-screen"]).screen == .usage)
    }

    /// The launch argument wins over Explore Demo's stored choice; without it the stored
    /// choice applies.
    @Test func launchVariantOverridesTheStoredChoice() {
        let stored = CompanionDemoVariant.bankedResets
        #expect(CompanionDemoLaunchOptions.parse(["Headroom", "--demo"]).resolvedVariant(stored: stored) == .bankedResets)
        #expect(CompanionDemoLaunchOptions.parse(["Headroom", "--demo", "--demo-variant", "dimmed"])
            .resolvedVariant(stored: stored) == .dimmed)
    }

    /// The Mac's `--demo <scenario>` token is a separate parser; a phone flag after `--demo`
    /// leaves the Mac reading a bare `--demo`.
    @Test func phoneFlagsDoNotChangeTheMacScenarioParse() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "--demo-variant", "multiAccount"]) == .singleAccount)
    }
}
