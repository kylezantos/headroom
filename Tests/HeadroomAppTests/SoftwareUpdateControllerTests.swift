import Foundation
import Observation
import Sparkle
import Synchronization
import Testing
@testable import Headroom

@Suite(.sharedAppState) @MainActor
struct SoftwareUpdateControllerTests {
    private func withPreferencesFixture(
        allowsAutomaticUpdates: Bool = true,
        _ body: (SoftwareUpdateController, SPUUpdater, String) throws -> Void
    ) throws {
        let identifier = "co.zantos.headroom.update-test.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
        let contents = root.appendingPathComponent("Fixture.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
            try? FileManager.default.removeItem(at: root)
        }
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier, "CFBundleName": "Updater Fixture",
            "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
            "SUEnableAutomaticChecks": true, "SUAllowsAutomaticUpdates": allowsAutomaticUpdates,
            "SUAutomaticallyUpdate": false,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: contents.deletingLastPathComponent()))
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        let subject = SoftwareUpdateController(updater: updater)
        try body(subject, updater, identifier)
    }

    @Test func automaticInstallationIsOptInAndPersists() throws {
        try withPreferencesFixture { subject, updater, identifier in
            #expect(subject.allowsAutomaticUpdates)
            #expect(!subject.automaticallyDownloadsUpdates)
            subject.automaticallyDownloadsUpdates = true
            #expect(updater.automaticallyDownloadsUpdates)
            #expect(subject.automaticallyDownloadsUpdates)
            #expect(UserDefaults.standard.persistentDomain(forName: identifier)?["SUAutomaticallyUpdate"] as? Bool == true)
            let bundle = updater.hostBundle
            let reopened = SPUUpdater(
                hostBundle: bundle, applicationBundle: bundle,
                userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil), delegate: nil
            )
            #expect(SoftwareUpdateController(updater: reopened).automaticallyDownloadsUpdates)
            subject.automaticallyDownloadsUpdates = false
            #expect(!updater.automaticallyDownloadsUpdates)
            #expect(!subject.automaticallyDownloadsUpdates)
        }
    }

    @Test func rejectedPreferenceNeverLooksEnabled() throws {
        try withPreferencesFixture(allowsAutomaticUpdates: false) { subject, _, _ in
            #expect(!subject.allowsAutomaticUpdates)
            subject.automaticallyDownloadsUpdates = true
            #expect(!subject.automaticallyDownloadsUpdates)
        }
    }

    @Test func sparklePreferenceChangesReachSettingsWithoutReopening() throws {
        try withPreferencesFixture { subject, updater, _ in
            updater.automaticallyDownloadsUpdates = true
            #expect(subject.automaticallyDownloadsUpdates)
            updater.automaticallyChecksForUpdates = false
            #expect(!subject.automaticallyChecksForUpdates)
            // Disabling checks suspends automatic work without erasing the user's opt-in.
            #expect(subject.automaticallyDownloadsUpdates)
            updater.automaticallyChecksForUpdates = true
            #expect(subject.automaticallyChecksForUpdates)
        }
    }

    /// Real Sparkle objects, never started: exercises the delegate bridge without a feed,
    /// network request, update window, download, or installation.
    private func fixture() -> (SoftwareUpdateController, SPUStandardUpdaterController, SUAppcastItem) {
        let subject = SoftwareUpdateController(enabled: false)
        let sparkle = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: subject, userDriverDelegate: subject
        )
        return (subject, sparkle, SUAppcastItem.empty())
    }

    @Test func disabledUpdaterHasNoAction() {
        let subject = SoftwareUpdateController(enabled: false)
        #expect(!subject.canCheckForUpdates)
        #expect(!subject.presentation.canCheckForUpdates)
        #expect(subject.presentation.availability.title == nil)
        subject.checkForUpdates()
        #expect(subject.presentation.availability == .none)
    }

    @Test func discoveredUpdateIsObservedBySettings() {
        let (subject, sparkle, item) = fixture()
        let changed = Mutex(false)
        withObservationTracking {
            _ = subject.presentation.availability
        } onChange: {
            changed.withLock { $0 = true }
        }
        subject.updater(sparkle.updater, didFindValidUpdate: item)
        #expect(changed.withLock { $0 })
        #expect(subject.presentation.availability.title == "Update Available")
    }

    @Test func scheduledInstallOffersRestartWithoutTakingOverSparkle() {
        let (subject, sparkle, item) = fixture()
        subject.updater(sparkle.updater, didFindValidUpdate: item)
        var installed = false
        let takesOwnership = subject.updater(
            sparkle.updater, willInstallUpdateOnQuit: item,
            immediateInstallationBlock: { installed = true }
        )
        #expect(!takesOwnership)
        #expect(!installed)
        #expect(subject.presentation.availability.title == "Restart to Update")
        #expect(subject.presentation.availability.symbol == "arrow.clockwise")
    }

    @Test func finishedUserSessionClearsDismissedOrSkippedUpdate() {
        let (subject, sparkle, item) = fixture()
        subject.updater(sparkle.updater, didFindValidUpdate: item)
        subject.standardUserDriverWillFinishUpdateSession()
        #expect(subject.presentation.availability == .none)
    }

    @Test func failedOrUnavailableUpdateClearsReadyState() {
        let (subject, sparkle, item) = fixture()
        let error = NSError(domain: "SoftwareUpdateControllerTests", code: 1)
        _ = subject.updater(sparkle.updater, willInstallUpdateOnQuit: item, immediateInstallationBlock: {})
        subject.updater(sparkle.updater, didAbortWithError: error)
        #expect(subject.presentation.availability == .none)
        subject.updater(sparkle.updater, didFindValidUpdate: item)
        subject.updaterDidNotFindUpdate(sparkle.updater, error: error)
        #expect(subject.presentation.availability == .none)
    }
}
