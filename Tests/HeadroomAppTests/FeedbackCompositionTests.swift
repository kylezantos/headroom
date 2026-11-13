import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// Feedback plan R8: demos, the render and bench harnesses and this test host read no CLI
/// versions and open no mail app from the Send Feedback row.
@MainActor
@Suite(.sharedAppState)
struct FeedbackCompositionTests {
    @Test func onlyARealLaunchReadsCLIsAndOpensMail() {
        for arguments in [
            ["Headroom", "--demo"],
            ["Headroom", "--render-popover", "/tmp/out"],
            ["Headroom", "--bench-ui", "settings"],
        ] {
            #expect(AppComposition.usesInertFeedback(arguments: arguments, environment: [:]), "\(arguments)")
        }
        #expect(AppComposition.usesInertFeedback(
            arguments: ["Headroom"],
            environment: ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]))
        #expect(!AppComposition.usesInertFeedback(arguments: ["Headroom"], environment: [:]))
    }

    @Test func theTestHostIsInert() {
        #expect(AppComposition.usesInertFeedback())
    }
}

@MainActor
@Suite(.sharedAppState)
struct FeedbackMailTests {
    /// R8: an inert launch returns before reading CLIs or opening anything.
    @Test func inertLaunchesSkipWithoutOpeningMail() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = UsageStore(providers: [], preferences: Preferences(defaults: defaults))
        #expect(await FeedbackMail.send(store: store, isInert: true) == .skipped)
    }
}
