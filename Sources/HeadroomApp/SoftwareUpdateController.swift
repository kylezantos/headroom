import Foundation
import Observation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
protocol SoftwareUpdateControlling: AnyObject {
    /// Whether this build has an updater. Temporary busy state is in `presentation` so
    /// update preferences stay visible while Sparkle downloads in the background.
    var canCheckForUpdates: Bool { get }
    var presentation: SoftwareUpdatePresentation { get }
    var allowsAutomaticUpdates: Bool { get }
    /// L13: Sparkle's own persisted background-check preference, surfaced as a switch in
    /// the General pane's Updates tile. Read/written straight through to the updater —
    /// Sparkle owns the storage (`SUEnableAutomaticChecks`), so Headroom keeps no
    /// second copy that could drift from it.
    var automaticallyChecksForUpdates: Bool { get set }
    /// Sparkle's own persisted silent-install preference (`SUAutomaticallyUpdate`): a found
    /// update downloads in the background and installs when the app quits. Only takes effect
    /// while background checks are on, so the switch is dependent on that one.
    var automaticallyDownloadsUpdates: Bool { get set }
    /// Sparkle's record of its last completed check (manual or background), shown as
    /// "Last checked …" under the Updates rows. Nil before the first check.
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
}

/// Transient Sparkle state, observed only by Settings. Never persisted: an old download
/// must not look ready after relaunch until Sparkle has resumed and validated it.
@MainActor @Observable
final class SoftwareUpdatePresentation {
    enum Availability: String, CaseIterable {
        case none, available, readyToRestart

        var title: String? {
            switch self {
            case .none: nil
            case .available: "Update Available"
            case .readyToRestart: "Restart to Update"
            }
        }

        var symbol: String {
            self == .readyToRestart ? "arrow.clockwise" : "arrow.down.circle"
        }
    }

    var availability: Availability = .none
    var canCheckForUpdates = false
    var allowsAutomaticUpdates = false
    var automaticChecks = false
    var automaticDownloads = false
}

/// Sparkle integration for direct website distribution. Debug/CLI builds commonly lack
/// the release-only Info.plist keys, so the controller stays inert until both the appcast
/// URL and EdDSA public key are stamped into the app bundle.
@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject, SoftwareUpdateControlling {
    let canCheckForUpdates: Bool
    let presentation = SoftwareUpdatePresentation()

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    private var updater: SPUUpdater?
    private var observations: [NSKeyValueObservation] = []
    #endif

    init(enabled: Bool = true) {
        #if canImport(Sparkle)
        canCheckForUpdates = enabled && Self.hasReleaseConfiguration
        #else
        canCheckForUpdates = false
        #endif
        super.init()
        #if canImport(Sparkle)
        if canCheckForUpdates {
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: self,
                userDriverDelegate: self
            )
            updaterController = controller
            observe(controller.updater)
            controller.startUpdater()
        }
        #endif
    }

    #if canImport(Sparkle)
    /// Inject an unstarted updater with an isolated host bundle for preference tests.
    init(updater: SPUUpdater) {
        canCheckForUpdates = true
        super.init()
        observe(updater)
    }

    private func observe(_ updater: SPUUpdater) {
        self.updater = updater
        // Sparkle requires these KVO properties on the main thread. Reading them back
        // also handles rejected writes and choices made in Sparkle's own update window.
        observations = [
            \.canCheckForUpdates, \.allowsAutomaticUpdates,
            \.automaticallyChecksForUpdates, \.automaticallyDownloadsUpdates,
        ].map { (keyPath: KeyPath<SPUUpdater, Bool>) in
            updater.observe(keyPath, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.readPreferences() }
            }
        }
    }

    private func readPreferences() {
        guard let updater else { return }
        presentation.canCheckForUpdates = updater.canCheckForUpdates
        presentation.allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        presentation.automaticChecks = updater.automaticallyChecksForUpdates
        presentation.automaticDownloads = updater.automaticallyDownloadsUpdates
    }
    #endif

    var allowsAutomaticUpdates: Bool { presentation.allowsAutomaticUpdates }

    var automaticallyChecksForUpdates: Bool {
        get {
            presentation.automaticChecks
        }
        set {
            #if canImport(Sparkle)
            updater?.automaticallyChecksForUpdates = newValue
            readPreferences()
            #endif
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            presentation.automaticDownloads
        }
        set {
            #if canImport(Sparkle)
            updater?.automaticallyDownloadsUpdates = newValue
            readPreferences()
            #endif
        }
    }

    var lastUpdateCheckDate: Date? {
        #if canImport(Sparkle)
        return updater?.lastUpdateCheckDate
        #else
        return nil
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        guard presentation.canCheckForUpdates else { return }
        // Also resumes a downloaded update or fronts an existing update window. Sparkle
        // owns confirmation, installation and relaunch; never quit the app ourselves.
        updater?.checkForUpdates()
        #endif
    }

    private static var hasReleaseConfiguration: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feedURL),
              ["https", "http"].contains(url.scheme), url.host != nil,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else { return false }
        return !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#if canImport(Sparkle)
extension SoftwareUpdateController: SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        presentation.availability = .available
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        presentation.availability = state.stage == .notDownloaded ? .available : .readyToRestart
    }

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        presentation.availability = .readyToRestart
        // Keep Sparkle's scheduler and install-on-quit behavior. Returning true would
        // stall future checks and require Headroom to own the immediate install handler.
        return false
    }

    func standardUserDriverWillFinishUpdateSession() {
        presentation.availability = .none
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        presentation.availability = .none
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        presentation.availability = .none
    }
}
#endif

@MainActor
final class DisabledSoftwareUpdateController: SoftwareUpdateControlling {
    var canCheckForUpdates: Bool { false }
    var allowsAutomaticUpdates: Bool { false }
    let presentation = SoftwareUpdatePresentation()
    /// No updater to defer to, so this is a plain stored value: previews and tests can
    /// still drive the switch without Sparkle present.
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    var lastUpdateCheckDate: Date? { nil }
    func checkForUpdates() {}
}
