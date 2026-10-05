import Foundation
import Testing
import UserNotifications
import HeadroomCore
@testable import Headroom

/// U5: the UserNotifications adapter and its composition (KTD9–KTD12). Every test runs
/// against injected bundle, environment, and center seams; none reaches the real center.
@MainActor
struct NotificationClientTests {
    private let appBundle = NotificationBundleDescriptor(
        identifier: "co.zantos.headroom",
        url: URL(fileURLWithPath: "/Applications/Headroom.app")
    )
    private let sampleContent = NotificationContent(
        identifier: "use-it-up.codex.primary.weekly.29839260",
        threadIdentifier: "codex.primary",
        title: "27% of Codex Weekly is still unused",
        body: "Resets in 5h, today at 4:00 PM."
    )

    // MARK: KTD9 bundle guard

    @Test func unbundledProcessGetsTheInertClientWithoutTouchingTheCenter() async {
        let unbundled = [
            NotificationBundleDescriptor(identifier: nil, url: URL(fileURLWithPath: "/Users/me/headroom/.build/debug")),
            NotificationBundleDescriptor(identifier: "co.zantos.headroom", url: URL(fileURLWithPath: "/Users/me/.build/debug/Headroom")),
            NotificationBundleDescriptor(identifier: nil, url: URL(fileURLWithPath: "/Applications/Headroom.app")),
            NotificationBundleDescriptor(identifier: "", url: URL(fileURLWithPath: "/Applications/Headroom.app")),
        ]
        for bundle in unbundled {
            var centerBuilt = false
            let client = UserNotificationClient.make(bundle: bundle) {
                centerBuilt = true
                return RecordingNotificationCenter()
            }
            #expect(!bundle.supportsUserNotifications)
            #expect(client is InertNotificationClient)
            #expect(!centerBuilt)
            #expect(await client.authorizationStatus() == .unavailable)
        }
    }

    @Test func bundledAppBuildsTheRealClientOnce() {
        var builds = 0
        let client = UserNotificationClient.make(bundle: appBundle) {
            builds += 1
            return RecordingNotificationCenter()
        }
        #expect(appBundle.supportsUserNotifications)
        #expect(client is UserNotificationClient)
        #expect(builds == 1)
    }

    // MARK: KTD11 authorization

    @Test func authorizationStatusesMapToTheFourPaneStates() {
        #expect(NotificationAuthorization(.authorized) == .authorized)
        #expect(NotificationAuthorization(.provisional) == .authorized)
        #expect(NotificationAuthorization(.denied) == .denied)
        #expect(NotificationAuthorization(.notDetermined) == .notDetermined)
    }

    @Test func requestAsksForAlertAndSoundOnlyAndReturnsTheResultingState() async {
        let center = RecordingNotificationCenter(status: .notDetermined, statusAfterRequest: .denied)
        let client = UserNotificationClient(center: center, bundleIdentifier: appBundle.identifier)
        #expect(await client.authorizationStatus() == .notDetermined)
        #expect(await client.requestAuthorization() == .denied)
        #expect(center.requestedOptions == [[.alert, .sound]])
        #expect(!UserNotificationClient.requestedOptions.contains(.provisional))
    }

    @Test func aThrowingRequestReadsBackTheStatus() async {
        let center = RecordingNotificationCenter(status: .denied, requestThrows: true)
        let client = UserNotificationClient(center: center, bundleIdentifier: appBundle.identifier)
        #expect(await client.requestAuthorization() == .denied)
    }

    // MARK: KTD6 / KTD12 posting

    @Test func authorizedPostAddsARequestWithTheCoreIdentifiers() async throws {
        let center = RecordingNotificationCenter(status: .authorized)
        let client = UserNotificationClient(center: center, bundleIdentifier: appBundle.identifier)
        #expect(await client.post(sampleContent))

        let request = try #require(center.addedRequests.first)
        #expect(center.addedRequests.count == 1)
        #expect(request.identifier == sampleContent.identifier)
        #expect(request.content.threadIdentifier == sampleContent.threadIdentifier)
        #expect(request.content.title == sampleContent.title)
        #expect(request.content.body == sampleContent.body)
        #expect(request.trigger == nil)
    }

    @Test func deniedOrFailedPostReportsFailure() async {
        let denied = RecordingNotificationCenter(status: .denied)
        #expect(!(await UserNotificationClient(center: denied, bundleIdentifier: appBundle.identifier).post(sampleContent)))
        #expect(denied.addedRequests.isEmpty)

        let undecided = RecordingNotificationCenter(status: .notDetermined)
        #expect(!(await UserNotificationClient(center: undecided, bundleIdentifier: appBundle.identifier).post(sampleContent)))
        #expect(undecided.addedRequests.isEmpty)

        let failing = RecordingNotificationCenter(status: .authorized, addThrows: true)
        #expect(!(await UserNotificationClient(center: failing, bundleIdentifier: appBundle.identifier).post(sampleContent)))
    }

    @Test func inertClientPostsNothingAndReportsUnavailable() async {
        let client = InertNotificationClient()
        #expect(!(await client.post(sampleContent)))
        #expect(await client.authorizationStatus() == .unavailable)
        #expect(await client.requestAuthorization() == .unavailable)
    }

    // MARK: KTD10 delegate

    @Test func delegateIsInstalledAndPresentsBannerListAndSound() {
        let center = RecordingNotificationCenter()
        let client = UserNotificationClient(center: center, bundleIdentifier: appBundle.identifier)
        client.installPresentationDelegate()
        #expect(center.delegate != nil)
        #expect(NotificationPresentationDelegate.presentationOptions == [.banner, .list, .sound])
    }

    // MARK: R18 System Settings link

    @Test func openSystemSettingsTriesTheDeepLinkThenTheBarePane() {
        let opened = OpenedURLs()
        let deepLinkFails = UserNotificationClient(
            center: RecordingNotificationCenter(),
            bundleIdentifier: "co.zantos.headroom",
            openURL: { url in
                opened.urls.append(url)
                return !url.absoluteString.contains("?id=")
            }
        )
        deepLinkFails.openSystemSettings()
        #expect(opened.urls.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=co.zantos.headroom",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        ])

        opened.urls.removeAll()
        let deepLinkOpens = UserNotificationClient(
            center: RecordingNotificationCenter(),
            bundleIdentifier: "co.zantos.headroom",
            openURL: { url in
                opened.urls.append(url)
                return true
            }
        )
        deepLinkOpens.openSystemSettings()
        #expect(opened.urls.count == 1)

        #expect(UserNotificationClient.systemSettingsURLs(bundleIdentifier: nil) == [UserNotificationClient.settingsPaneURL])
    }

    // MARK: Composition

    @Test func compositionPicksTheInertClientWhereverTheCenterIsOffLimits() {
        let hosted = ["XCTestConfigurationFilePath": "/tmp/HeadroomAppTests.xctestconfiguration"]
        #expect(AppComposition.usesInertNotificationClient(arguments: ["Headroom"], environment: hosted, bundle: appBundle))
        #expect(AppComposition.usesInertNotificationClient(arguments: ["Headroom", "--demo"], environment: [:], bundle: appBundle))
        #expect(AppComposition.usesInertNotificationClient(arguments: ["Headroom", "--demo", "multi-2"], environment: [:], bundle: appBundle))
        #expect(AppComposition.usesInertNotificationClient(
            arguments: ["Headroom", "--render-popover", "/tmp/shots"], environment: [:], bundle: appBundle
        ))
        #expect(AppComposition.usesInertNotificationClient(
            arguments: ["Headroom", "--bench-ui", "popover"], environment: [:], bundle: appBundle
        ))
        #expect(AppComposition.usesInertNotificationClient(
            arguments: ["Headroom"],
            environment: [:],
            bundle: NotificationBundleDescriptor(identifier: nil, url: URL(fileURLWithPath: "/tmp/.build/debug"))
        ))
        #expect(!AppComposition.usesInertNotificationClient(arguments: ["Headroom"], environment: [:], bundle: appBundle))

        #expect(AppComposition.makeNotificationClient(arguments: ["Headroom"], environment: hosted, bundle: appBundle)
            is InertNotificationClient)
        // This process is the XCTest host: no system prompt or real banner during `xcodebuild test`.
        #expect(AppComposition.usesInertNotificationClient())
        #expect(AppComposition.notificationClient is InertNotificationClient)
    }

    // MARK: Scripted client (U6 fake)

    @Test func scriptedClientResolvesOnlyAnUndecidedPrompt() async {
        let client = ScriptedNotificationClient(status: .notDetermined, requestOutcome: .denied)
        #expect(await client.requestAuthorization() == .denied)
        #expect(await client.requestAuthorization() == .denied)
        #expect(client.requestCount == 2)
        client.status = .authorized
        #expect(await client.authorizationStatus() == .authorized)
        #expect(await client.post(sampleContent))
    }
}

@MainActor
private final class OpenedURLs {
    var urls: [URL] = []
}

/// `UNUserNotificationCenter` double: scripted status and failures, and a record of the
/// requests and options it was handed.
private final class RecordingNotificationCenter: UserNotificationCenterClient, @unchecked Sendable {
    private let lock = NSLock()
    private var status: UNAuthorizationStatus
    private let statusAfterRequest: UNAuthorizationStatus?
    private let requestThrows: Bool
    private let addThrows: Bool
    private var _requestedOptions: [UNAuthorizationOptions] = []
    private var _addedRequests: [UNNotificationRequest] = []
    private(set) var delegate: NotificationPresentationDelegate?

    init(
        status: UNAuthorizationStatus = .authorized,
        statusAfterRequest: UNAuthorizationStatus? = nil,
        requestThrows: Bool = false,
        addThrows: Bool = false
    ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
        self.requestThrows = requestThrows
        self.addThrows = addThrows
    }

    var requestedOptions: [UNAuthorizationOptions] { lock.withLock { _requestedOptions } }
    var addedRequests: [UNNotificationRequest] { lock.withLock { _addedRequests } }

    func authorizationStatus() async -> UNAuthorizationStatus { lock.withLock { status } }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try lock.withLock {
            _requestedOptions.append(options)
            if let statusAfterRequest { status = statusAfterRequest }
            if requestThrows { throw CenterFailure() }
            return status == .authorized
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try lock.withLock {
            if addThrows { throw CenterFailure() }
            _addedRequests.append(request)
        }
    }

    @MainActor func setDelegate(_ delegate: NotificationPresentationDelegate) {
        self.delegate = delegate
    }

    private struct CenterFailure: Error {}
}
