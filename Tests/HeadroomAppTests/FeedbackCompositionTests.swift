import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// Feedback plan R8: demos, the render and bench harnesses and this test host read no CLI
/// versions and open no mail app from the Send Feedback sheet.
@MainActor
struct FeedbackCompositionTests {
    @Test func onlyARealLaunchReadsCLIsAndOpensMail() {
        for arguments in [
            ["Headroom", "--demo"],
            ["Headroom", "--render-popover", "/tmp/out", "--feedback-only"],
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
