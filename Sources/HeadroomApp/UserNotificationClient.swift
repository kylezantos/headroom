import AppKit
import Foundation
import HeadroomCore
import UserNotifications

/// KTD11: the permission states the Notifications pane reads. `authorized` includes
/// provisional; `unavailable` is an unbundled process that must never reach the center.
enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional: self = .authorized
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        // A state this build does not know posts nothing, the same as a refusal.
        @unknown default: self = .denied
        }
    }
}

/// The permission half of the client, which Settings drives (R17, R18).
protocol NotificationAuthorizing: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    /// Asks once with alert and sound (KTD11) and returns the state that results.
    func requestAuthorization() async -> NotificationAuthorization
    /// R18: Headroom's row in System Settings › Notifications.
    @MainActor func openSystemSettings()
}

/// What composition hands the store's coordinator and `SettingsView`: one object that
/// posts (Core's seam, KTD1) and reports permission.
protocol NotificationClient: NotificationPosting, NotificationAuthorizing {
    /// KTD10: `AppDelegate` installs the presentation delegate before launch completes.
    @MainActor func installPresentationDelegate()
}

extension NotificationClient {
    @MainActor func installPresentationDelegate() {}
}

/// The main bundle as KTD9 reads it, injected so tests prove the guard without a launch.
struct NotificationBundleDescriptor: Sendable, Equatable {
    let identifier: String?
    let url: URL

    static var main: NotificationBundleDescriptor {
        NotificationBundleDescriptor(identifier: Bundle.main.bundleIdentifier, url: Bundle.main.bundleURL)
    }

    /// KTD9: `UNUserNotificationCenter.current()` raises an uncatchable Objective-C
    /// exception without a bundle proxy, so only a real `.app` with an identifier may call it.
    var supportsUserNotifications: Bool {
        guard let identifier, !identifier.isEmpty else { return false }
        return url.pathExtension == "app"
    }
}

/// The slice of `UNUserNotificationCenter` the client uses, so tests substitute a
/// recording fake and never touch the real center.
protocol UserNotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    @MainActor func setDelegate(_ delegate: NotificationPresentationDelegate)
}

/// The real center. Built only behind the KTD9 guard.
private struct SystemUserNotificationCenter: UserNotificationCenterClient, @unchecked Sendable { // the center is thread-safe
    let center: UNUserNotificationCenter

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    @MainActor func setDelegate(_ delegate: NotificationPresentationDelegate) {
        center.delegate = delegate
    }
}

/// KTD10: nonisolated and completion-handler based — a `@MainActor` delegate with async
/// methods fails to compile over the non-Sendable `UNNotification` parameters. KTD8: only
/// `willPresent`, so banners still show while Settings is frontmost; taps keep the
/// system default. `center.delegate` is weak, so the client holds this strongly.
final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.presentationOptions)
    }
}

/// The bundled app's client (U5). Posts through `UNUserNotificationCenter` and reports its
/// permission. Built by `make`, which returns an inert client whenever KTD9's guard fails.
struct UserNotificationClient: NotificationClient {
    /// KTD11: never provisional, because a quiet delivery defeats a reminder.
    static let requestedOptions: UNAuthorizationOptions = [.alert, .sound]
    static let settingsPaneURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    private let center: any UserNotificationCenterClient
    private let bundleIdentifier: String?
    private let presentationDelegate = NotificationPresentationDelegate()
    private let openURL: @MainActor @Sendable (URL) -> Bool

    init(
        center: any UserNotificationCenterClient,
        bundleIdentifier: String?,
        openURL: @escaping @MainActor @Sendable (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.center = center
        self.bundleIdentifier = bundleIdentifier
        self.openURL = openURL
    }

    /// KTD9: `center` is only evaluated once the bundle guard passes.
    static func make(
        bundle: NotificationBundleDescriptor = .main,
        center: () -> any UserNotificationCenterClient = {
            SystemUserNotificationCenter(center: UNUserNotificationCenter.current())
        }
    ) -> any NotificationClient {
        guard bundle.supportsUserNotifications else { return InertNotificationClient() }
        return UserNotificationClient(center: center(), bundleIdentifier: bundle.identifier)
    }

    /// KTD12: the Core identifiers become the request and thread identifiers unchanged, so
    /// a repost replaces its banner. Interruption level stays `.active` (KTD10).
    static func request(for content: NotificationContent) -> UNNotificationRequest {
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.body = content.body
        body.threadIdentifier = content.threadIdentifier
        body.sound = .default
        return UNNotificationRequest(identifier: content.identifier, content: body, trigger: nil)
    }

    /// Deep link to Headroom's own row; the bare pane when there is no identifier or the
    /// deep link cannot be opened. `?id=` is community-documented, not Apple API.
    static func systemSettingsURLs(bundleIdentifier: String?) -> [URL] {
        var urls: [URL] = []
        if let bundleIdentifier, !bundleIdentifier.isEmpty,
           let deepLink = URL(string: "\(settingsPaneURL.absoluteString)?id=\(bundleIdentifier)") {
            urls.append(deepLink)
        }
        urls.append(settingsPaneURL)
        return urls
    }

    func authorizationStatus() async -> NotificationAuthorization {
        NotificationAuthorization(await center.authorizationStatus())
    }

    func requestAuthorization() async -> NotificationAuthorization {
        // A thrown request (already denied, or a system error) is read back as the status.
        _ = try? await center.requestAuthorization(options: Self.requestedOptions)
        return await authorizationStatus()
    }

    /// KTD6: accepted only when authorized and the center took the request. macOS accepts
    /// `add` silently while denied, so the status is checked first; otherwise a denied
    /// post would mark rules fired that the user never saw.
    func post(_ content: NotificationContent) async -> Bool {
        guard await authorizationStatus() == .authorized else { return false }
        do {
            try await center.add(Self.request(for: content))
            return true
        } catch {
            return false
        }
    }

    @MainActor func openSystemSettings() {
        for url in Self.systemSettingsURLs(bundleIdentifier: bundleIdentifier) where openURL(url) {
            return
        }
    }

    @MainActor func installPresentationDelegate() {
        center.setDelegate(presentationDelegate)
    }
}

/// KTD9: the client for `swift run`, `--demo`, `--render-popover`, and hosted tests. It
/// never touches the center: nothing posts and permission reads `unavailable`.
struct InertNotificationClient: NotificationClient {
    func post(_ content: NotificationContent) async -> Bool { false }
    func authorizationStatus() async -> NotificationAuthorization { .unavailable }
    func requestAuthorization() async -> NotificationAuthorization { .unavailable }
    @MainActor func openSystemSettings() {}
}

/// A scripted client for app tests and the render harness (U6): a fixed status, the
/// state a request resolves to, and a record of what was asked.
final class ScriptedNotificationClient: NotificationClient, @unchecked Sendable { // state is lock-guarded
    private let lock = NSLock()
    private var _status: NotificationAuthorization
    private var _requestOutcome: NotificationAuthorization
    private var _requestCount = 0
    private var _openSettingsCount = 0
    private var _posted: [NotificationContent] = []

    init(status: NotificationAuthorization, requestOutcome: NotificationAuthorization? = nil) {
        _status = status
        _requestOutcome = requestOutcome ?? status
    }

    var status: NotificationAuthorization {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }

    var requestOutcome: NotificationAuthorization {
        get { lock.withLock { _requestOutcome } }
        set { lock.withLock { _requestOutcome = newValue } }
    }

    var requestCount: Int { lock.withLock { _requestCount } }
    var openSettingsCount: Int { lock.withLock { _openSettingsCount } }
    var posted: [NotificationContent] { lock.withLock { _posted } }

    func authorizationStatus() async -> NotificationAuthorization { status }

    func requestAuthorization() async -> NotificationAuthorization {
        lock.withLock {
            _requestCount += 1
            // Only an undecided prompt changes anything, as with the real center.
            if _status == .notDetermined { _status = _requestOutcome }
            return _status
        }
    }

    func post(_ content: NotificationContent) async -> Bool {
        lock.withLock {
            _posted.append(content)
            return _status == .authorized
        }
    }

    @MainActor func openSystemSettings() {
        lock.withLock { _openSettingsCount += 1 }
    }
}
