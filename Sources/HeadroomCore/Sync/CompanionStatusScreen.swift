import Foundation

/// U10 (R4, R23; batch items G5–G9): the phone's screens for every state with nothing to
/// show. One row per state of the plan's table, so each one leads somewhere: its primary
/// action, Explore Demo, and on waiting and paused the Mac app (G9).
public enum CompanionStatusScreen: String, CaseIterable, Equatable, Sendable {
    case waiting
    case paused
    case iCloudUnavailable
    /// No resolved state reaches this today: the build-33 lift folds a corrupt read into
    /// `.waiting(nil)`. The row stays so the copy is pinned and DEBUG captures can pose it.
    case unreadable
    /// This iPhone's reader is older than the Mac's data.
    case updatePhone
    /// The Mac is too old for this phone. Content from an old Mac carries a notice instead;
    /// this screen covers `.waiting(.updateMac)` so the mapping stays total.
    case updateMac

    /// Nil for content: the mirror shows it.
    public init?(_ state: CompanionResolvedState) {
        switch state {
        case .content: return nil
        case .accountScopeUnavailable: self = .iCloudUnavailable
        case .paused: self = .paused
        case .waiting(.none): self = .waiting
        case .waiting(.some(.updatePhone)): self = .updatePhone
        case .waiting(.some(.updateMac)): self = .updateMac
        }
    }

    public var title: String {
        switch self {
        case .waiting: CompanionStatusCopy.waitingTitle
        case .paused: CompanionStatusCopy.pausedTitle
        case .iCloudUnavailable: CompanionStatusCopy.iCloudUnavailableTitle
        case .unreadable: CompanionStatusCopy.unreadableTitle
        case .updatePhone: CompanionStatusCopy.updatePhoneTitle
        case .updateMac: CompanionStatusCopy.updateMacTitle
        }
    }

    public var message: String {
        switch self {
        case .waiting: CompanionStatusCopy.waitingMessage
        case .paused: CompanionStatusCopy.pausedMessage
        case .iCloudUnavailable: CompanionStatusCopy.iCloudUnavailableMessage
        case .unreadable: CompanionStatusCopy.unreadableMessage
        case .updatePhone: CompanionStatusCopy.updatePhoneMessage
        case .updateMac: CompanionStatusCopy.updateMacMessage
        }
    }

    public var primaryAction: CompanionStatusAction {
        switch self {
        case .waiting, .paused, .unreadable: .refresh
        case .iCloudUnavailable: .openSettings
        case .updatePhone: .open(AboutLinks.iPhoneApp)
        case .updateMac: .open(AboutLinks.getHeadroomForMac)
        }
    }

    /// G9: the Mac app, for someone who reached the phone first or turned sync off.
    public var secondaryLink: AboutLink? {
        switch self {
        case .waiting, .paused: AboutLinks.getHeadroomForMac
        case .iCloudUnavailable, .unreadable, .updatePhone, .updateMac: nil
        }
    }

    /// Every screen offers Explore Demo (U10 table).
    public var offersExploreDemo: Bool { true }

    /// Only Refresh runs a check, so only these screens ever show the checking row; nothing
    /// moves on a screen that is not working.
    public var canCheck: Bool { primaryAction == .refresh }
}

public enum CompanionStatusAction: Equatable, Sendable {
    /// Re-read iCloud and the cache (the 550ms-floored local check).
    case refresh
    /// The app's page in iOS Settings, where iCloud access is turned on.
    case openSettings
    case open(AboutLink)

    public var title: String {
        switch self {
        case .refresh: CompanionStatusCopy.refresh
        case .openSettings: CompanionStatusCopy.openSettings
        case .open(let link) where link == AboutLinks.iPhoneApp: CompanionStatusCopy.openAppStore
        case .open(let link): link.title
        }
    }

    /// Nil for actions the app performs itself.
    public var url: URL? {
        if case .open(let link) = self { link.url } else { nil }
    }
}

/// U10's phone copy (R2C6: curly apostrophes, one sign-in verb, no "connect").
public enum CompanionStatusCopy {
    public static let waitingTitle = "Waiting for Mac"
    public static let waitingMessage = "Open Headroom on your Mac to start syncing your usage to this device."
    public static let pausedTitle = "Companion Sync Paused"
    /// G8: the switch's name as the Mac prints it, and where it lives.
    public static let pausedMessage =
        "Turn on Sync usage to iPhone in Headroom on your Mac, under Settings › Widgets & iPhone."
    public static let iCloudUnavailableTitle = "iCloud Not Available"
    public static let iCloudUnavailableMessage =
        "Sign in to iCloud on this device and on your Mac with the same Apple Account."
    public static let unreadableTitle = "Snapshot Unreadable"
    /// Never "publish a fresh snapshot": nothing on the Mac is called that.
    public static let unreadableMessage =
        "This device couldn’t read your Mac’s last update. Open Headroom on your Mac to send a new one."
    public static let updatePhoneTitle = "Update Needed"
    public static let updatePhoneMessage = "Update Headroom on this iPhone to read your Mac’s usage."
    public static let updateMacTitle = "Update Headroom on your Mac"
    public static let updateMacMessage = "This iPhone needs a newer version of Headroom on your Mac."

    public static let refresh = "Refresh"
    public static let checking = "Checking…"
    public static let openSettings = "Open iOS Settings"
    public static let openAppStore = "Open App Store"
    public static let exploreDemo = "Explore Demo"
    public static let exploreDemoHint = "Shows sample usage. Nothing is read from your Mac or iCloud."

    static var all: [String] {
        [
            waitingTitle, waitingMessage, pausedTitle, pausedMessage,
            iCloudUnavailableTitle, iCloudUnavailableMessage, unreadableTitle, unreadableMessage,
            updatePhoneTitle, updatePhoneMessage, updateMacTitle, updateMacMessage,
            refresh, checking, openSettings, openAppStore, exploreDemo, exploreDemoHint,
            AboutLinks.getHeadroomForMac.title,
        ]
    }
}
