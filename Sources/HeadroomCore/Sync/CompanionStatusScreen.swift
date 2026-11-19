import Foundation

/// U10 (R4, R23; batch items G5–G9): the phone's screens for every state with nothing to
/// show. One row per state of the plan's table, so each one leads somewhere: its primary
/// action, Explore Demo, and on waiting and paused the Mac app (G9).
public enum CompanionStatusScreen: String, CaseIterable, Equatable, Sendable {
    case waiting
    case paused
    case iCloudUnavailable
    /// A corrupt v3 key with nothing usable behind it (`CompanionResolvedState.unreadable`).
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
        case .unreadable: self = .unreadable
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
    /// CA-I6 (COPY-10): the four titles a widget shows for the same cause, in the Title Case
    /// a full-screen iOS title takes, derived so the two surfaces cannot drift again. WCW4
    /// retired "Companion" and "Snapshot" from the widgets; the app kept them.
    public static let waitingTitle = titleCased(WidgetStatusState.iosWaitingForMac.title)
    public static let waitingMessage = "Open Headroom on your Mac to start syncing your usage to this device."
    public static let pausedTitle = titleCased(WidgetStatusState.iosDisabled.title)
    /// G8: the switch's name as the Mac prints it, and where it lives.
    public static let pausedMessage =
        "Turn on Sync usage to iPhone in Headroom on your Mac, under Settings › Widgets & iPhone."
    public static let iCloudUnavailableTitle = "iCloud Not Available"
    public static let iCloudUnavailableMessage =
        "Sign in to iCloud on this device and on your Mac with the same Apple Account."
    public static let unreadableTitle = titleCased(WidgetStatusState.iosCorrupt.title)
    /// Never "publish a fresh snapshot": nothing on the Mac is called that.
    public static let unreadableMessage =
        "This device couldn’t read your Mac’s last update. Open Headroom on your Mac to send a new one."
    public static let updatePhoneTitle = titleCased(WidgetStatusState.iosIncompatibleSchema.title)
    public static let updatePhoneMessage = "Update Headroom on this iPhone to read your Mac’s usage."
    public static let updateMacTitle = "Update Headroom on your Mac"
    public static let updateMacMessage = "This iPhone needs a newer version of Headroom on your Mac."

    public static let refresh = "Refresh"
    public static let checking = "Checking…"
    public static let openSettings = "Open iOS Settings"
    public static let openAppStore = "Open App Store"
    public static let exploreDemo = "Explore Demo"
    public static let exploreDemoHint = "Shows sample usage. Nothing is read from your Mac or iCloud."

    /// Title Case as Apple's style applies it: every word capitalized except articles, short
    /// conjunctions and short prepositions after the first ("Waiting for Your Mac",
    /// "Couldn’t Read the Data"). Words that already carry capitals ("iCloud") are kept.
    static func titleCased(_ sentence: String) -> String {
        let minor: Set<String> = ["a", "an", "the", "and", "or", "but", "for", "of", "on", "in", "to", "at", "by"]
        return sentence.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { index, word in
            let text = String(word)
            guard let first = text.first, first.isLowercase, !text.contains(where: \.isUppercase) else { return text }
            if index > 0, minor.contains(text) { return text }
            return first.uppercased() + text.dropFirst()
        }.joined(separator: " ")
    }

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
