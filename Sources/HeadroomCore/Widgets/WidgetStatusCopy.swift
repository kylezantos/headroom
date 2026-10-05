import Foundation

/// WCW4: every state a widget can show instead of usage, and the exact words for it.
///
/// The two hosts had written their own copy for the same nine situations, in two different
/// voices — title case on one side, a sentence fragment on the other, "Waiting for Mac data"
/// versus "No data yet". Keeping the strings in Core means the words are reviewable and
/// testable in one place, and a status card is the same object on a Mac tile and an iPhone
/// tile. Sentence case throughout; the message always names the one action that fixes it.
///
/// Not localised this round (recorded in the plan's "Not in this round").
public enum WidgetStatusState: Sendable, Equatable, CaseIterable {
    /// The Mac app has never written a snapshot (no container file yet).
    case macSetupNeeded
    /// The snapshot on disk is newer than this widget build can read.
    case macIncompatibleSchema
    /// The user turned "Share data with widgets" off.
    case macDisabled
    /// Sharing is on and the file exists, but no provider has been read yet.
    case macPending
    /// The Mac is not syncing to iPhone.
    case iosDisabled
    /// iCloud is off for Headroom on this iPhone.
    case iosSetupNeeded
    /// Sync is on, iCloud is on, and nothing has arrived yet.
    case iosWaitingForMac
    /// A payload arrived but could not be decoded.
    case iosCorrupt
    /// The payload's schema is newer than this build can read.
    case iosIncompatibleSchema

    public var title: String {
        switch self {
        case .macSetupNeeded: "No usage yet"
        case .macIncompatibleSchema: "Update Headroom"
        case .macDisabled: "Widgets are off"
        case .macPending: "Not checked yet"
        case .iosDisabled: "Sync is off"
        case .iosSetupNeeded: "iCloud is off"
        case .iosWaitingForMac: "Waiting for your Mac"
        case .iosCorrupt: "Couldn’t read the data"
        case .iosIncompatibleSchema: "Update Headroom"
        }
    }

    public var message: String {
        switch self {
        case .macSetupNeeded: "Open Headroom on this Mac to send usage to widgets."
        case .macIncompatibleSchema: "This widget needs a newer version of the app."
        case .macDisabled: "Turn on Share data with widgets in Headroom Settings."
        case .macPending: "Open Headroom to take the first reading."
        case .iosDisabled: "Turn on Sync usage to iPhone in Headroom on your Mac."
        case .iosSetupNeeded: "Turn on iCloud for Headroom in iPhone Settings."
        case .iosWaitingForMac: "Open Headroom on your Mac to send a reading."
        case .iosCorrupt: "Open Headroom on your Mac and choose Check Now."
        case .iosIncompatibleSchema: "Update the app on your Mac and iPhone."
        }
    }

    /// R9 (2026-10-04 Lock Screen plan): one word in the circle's caption slot.
    public var lockScreenWord: String {
        switch self {
        case .macSetupNeeded, .iosSetupNeeded: "Setup"
        case .macPending, .iosWaitingForMac: "Waiting"
        case .macDisabled, .iosDisabled: "Off"
        case .iosCorrupt: "Unreadable"
        case .macIncompatibleSchema, .iosIncompatibleSchema: "Update"
        }
    }

    /// WCW4: how full the vessel mark beside the card draws, 0…1.
    ///
    /// The mark is the only picture on a status card, so it must not imply a reading. The two
    /// "no reading has ever arrived" states draw an empty vessel; every other state draws the
    /// same neutral half-full mark, which says "this is a meter" without saying a number.
    public var vesselFill: Double {
        switch self {
        case .macPending, .iosWaitingForMac: 0
        case .macSetupNeeded, .macIncompatibleSchema, .macDisabled,
             .iosDisabled, .iosSetupNeeded, .iosCorrupt, .iosIncompatibleSchema: 0.46
        }
    }
}
