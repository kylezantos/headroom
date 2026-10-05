import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// U5 / R37 / KTD21: the phone publisher and its iCloud observers exist only in a real
/// launch. Demo runs, the render and bench harnesses and this XCTest host never write the
/// user's iCloud key-value store.
@MainActor
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
}
