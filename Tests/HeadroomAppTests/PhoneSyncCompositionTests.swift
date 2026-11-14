import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// U5 / R37 / KTD21: the phone publisher and its iCloud observers exist only in a real
/// launch. Demo runs, the render and bench harnesses and this XCTest host never write the
/// user's iCloud key-value store.
@MainActor
@Suite(.sharedAppState)
struct PhoneSyncCompositionTests {
    @Test func onlyARealLaunchComposesThePhonePublisher() {
        for arguments in [
            ["Headroom", "--demo"],
            ["Headroom", "--demo", "multi-20"],
            ["Headroom", "--render-popover", "/tmp/out"],
            ["Headroom", "--render-widgets", "/tmp/out"],
            ["Headroom", "--render-loading-preview", "/tmp/out"],
            ["Headroom", "--bench-ui", "popover"],
        ] {
            #expect(AppComposition.usesInertPhoneSync(arguments: arguments, environment: [:]), "\(arguments)")
        }
        #expect(AppComposition.usesInertPhoneSync(
            arguments: ["Headroom"],
            environment: ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]))
        #expect(!AppComposition.usesInertPhoneSync(arguments: ["Headroom"], environment: [:]))
    }

    /// This process is the test host (launched with `--demo`), so it has no publisher.
    @Test func theTestHostHasNoPhonePublisher() {
        #expect(AppComposition.usesInertPhoneSync())
        #expect(AppComposition.phoneSyncExporter() == nil)
    }

    /// U6 / R19 / KTD21: no check-now coordinator under `--demo` or in a test host, so
    /// neither ever runs a refresh for a phone or writes a receipt.
    @Test func demoAndTestHostsComposeNoCheckNowCoordinator() {
        let suite = "headroom.checknow.composition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(providers: [], preferences: Preferences(defaults: defaults))
        #expect(AppComposition.makeCheckNowCoordinator(
            store: store, arguments: ["Headroom", "--demo"], environment: [:]) == nil)
        #expect(AppComposition.makeCheckNowCoordinator(
            store: store, arguments: ["Headroom"],
            environment: ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]) == nil)
        #expect(AppComposition.makeCheckNowCoordinator(store: store) == nil)
        #expect(CompanionSyncObservers.checkNow == nil)
    }
}
