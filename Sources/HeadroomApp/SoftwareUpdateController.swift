import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
protocol SoftwareUpdateControlling: AnyObject {
    var canCheckForUpdates: Bool { get }
    /// L13: Sparkle's own persisted background-check preference, surfaced as a switch in
    /// the General pane's Updates tile. Read/written straight through to the updater —
    /// Sparkle owns the storage (`SUEnableAutomaticChecks`), so Headroom keeps no
    /// second copy that could drift from it.
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

/// Sparkle integration for direct website distribution. Debug/CLI builds commonly lack
/// the release-only Info.plist keys, so the controller stays inert until both the appcast
/// URL and EdDSA public key are stamped into the app bundle.
@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject, SoftwareUpdateControlling {
    @Published private(set) var canCheckForUpdates: Bool

    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
    #endif

    override init() {
        #if canImport(Sparkle)
        if Self.hasReleaseConfiguration {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = controller
            canCheckForUpdates = true
        } else {
            updaterController = nil
            canCheckForUpdates = false
        }
        #else
        canCheckForUpdates = false
        #endif
        super.init()
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            #if canImport(Sparkle)
            return updaterController?.updater.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            updaterController?.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController?.checkForUpdates(nil)
        #endif
    }

    private static var hasReleaseConfiguration: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else { return false }
        return URL(string: feedURL) != nil && !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class DisabledSoftwareUpdateController: SoftwareUpdateControlling {
    var canCheckForUpdates: Bool { false }
    /// No updater to defer to, so this is a plain stored value: previews and tests can
    /// still drive the switch without Sparkle present.
    var automaticallyChecksForUpdates: Bool = false
    func checkForUpdates() {}
}
