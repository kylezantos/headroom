import Foundation

// U12: pure derivations behind the phone's Settings sheet, so the gating rules are tested
// without a SwiftUI host. Every input is the one resolved snapshot the app shows (KTD6) —
// the demo variant's in Explore Demo, so demo rows read the fixture (R30).

/// Rule 7 of U12: rows that read manifest fields (the Mac's widget provider selection and
/// reminder summary).
public enum PhoneSettingsManifestRows: Equatable, Sendable {
    /// Sync is paused, nothing has arrived yet, or the iCloud account can't be verified.
    case hidden
    /// Only primary-only v3 data is readable: the fields don't exist on that Mac (R14).
    case updateMac
    /// `widgetProviders` are the display names the Mac's widgets show, in widget order.
    case available(widgetProviders: [String], reminders: CompanionReminderSummary?)

    public init(snapshot: CompanionResolvedSnapshot?) {
        guard let snapshot, let content = snapshot.content else {
            self = .hidden
            return
        }
        guard content.origin == .v4 else {
            // Only a lineage-less v3 (an older Mac) asks for an update. A current Mac's v3
            // mirror read without its manifest carries no manifest fields, so the rows hide
            // rather than tell an up-to-date Mac to update (KTD6.5).
            self = content.notice == .updateMac ? .updateMac : .hidden
            return
        }
        let widgetProviders = snapshot.primaryProjection()?.widgetProviders.map(\.displayName) ?? []
        self = .available(widgetProviders: widgetProviders, reminders: content.reminderSummary)
    }
}

/// The iPhone sync section's status rows (KTD22 diagnostics): state, the manifest's age and,
/// once the Mac has gone quiet, the KTD15 sentence. Never the source ID.
public struct PhoneSyncStatus: Equatable, Sendable {
    public let state: String
    /// "2 min ago": the age of the shown generation's publish time (manifest or v3).
    public let lastUpdate: String?
    /// "No update from your Mac since 9:41 AM" while the app surface is dimmed.
    public let dimmedLine: String?

    public init(
        snapshot: CompanionResolvedSnapshot?, now: Date,
        timeZone: TimeZone = .current, locale: Locale = .current
    ) {
        guard let snapshot else {
            self.init(state: "Checking…", lastUpdate: nil, dimmedLine: nil)
            return
        }
        switch snapshot.state {
        case .accountScopeUnavailable:
            self.init(state: "iCloud not available", lastUpdate: nil, dimmedLine: nil)
        case .paused:
            self.init(state: "Paused on your Mac", lastUpdate: nil, dimmedLine: nil)
        case .waiting:
            self.init(state: CompanionFreshnessCopy.waitingForMac, lastUpdate: nil, dimmedLine: nil)
        case .unreadable:
            self.init(state: "Couldn’t read your Mac’s last update", lastUpdate: nil, dimmedLine: nil)
        case .content(let content):
            let inputs = content.freshness
            let dimmed = CompanionFreshnessRule.isDimmed(inputs, surface: .app, at: now)
            let heard = CompanionFreshnessRule.lastHeardFromMac(inputs)
            self.init(
                state: "On",
                lastUpdate: Countdown.updatedLabel(capturedAt: heard, now: now),
                dimmedLine: dimmed
                    ? CompanionFreshnessCopy.noUpdate(
                        since: WidgetClockText.text(for: heard, now: now, timeZone: timeZone, locale: locale))
                    : nil)
        }
    }

    init(state: String, lastUpdate: String?, dimmedLine: String?) {
        self.state = state
        self.lastUpdate = lastUpdate
        self.dimmedLine = dimmedLine
    }
}

/// KTD22: "the last check-now round trip". U9 owns the check-now state machine and hands the
/// sheet one of these once a request finishes; until then the row is absent, never faked.
public struct PhoneCheckNowRoundTrip: Equatable, Sendable {
    public let requestedAt: Date
    public let finishedAt: Date

    public init(requestedAt: Date, finishedAt: Date) {
        self.requestedAt = requestedAt
        self.finishedAt = finishedAt
    }

    /// "12 s · 3 min ago".
    public func text(now: Date) -> String {
        let seconds = max(0, finishedAt.timeIntervalSince(requestedAt))
        let duration = seconds < 60 ? "\(Int(seconds.rounded())) s" : "\(Int((seconds / 60).rounded())) min"
        let age = Countdown.updatedLabel(capturedAt: finishedAt, now: now) ?? "just now"
        return "\(duration) · \(age)"
    }
}

/// Settings sheet copy (R2C6: curly apostrophes, one sign-in verb, no "connect").
public enum PhoneSettingsCopy {
    public static let updateMac = "Update Headroom on your Mac"
    /// KTD22's what-syncs list, as the shipped build sends it. Reminder text joins when U16's
    /// CloudKit reminders ship (KTD19), and not before.
    public static let whatSyncs = [
        "Account names, as your Mac shows them",
        "Plan names",
        "Usage and reset times",
        "API spend",
        "Display choices",
        "Check-now requests",
        "A random ID for your Mac and for each iPhone or iPad",
        // KTD22 (2026-10-05): the scope marker, so saved data never outlives an account switch.
        "A random ID that tells this app which iCloud account its saved data belongs to",
    ]
    public static let whatSyncsFooter =
        "If you use an email address as an account name, that address syncs as the name. "
        + "Sign-ins, passwords and API keys never leave your Mac. iCloud key-value data isn’t end-to-end encrypted."
    /// What the phone can't change. The July 2026 audit cut renewal dates from every surface.
    public static let managedOnMac =
        "Accounts, the refresh interval, API keys and the API spend period are set in Headroom on your Mac."
    public static let widgetsFooter =
        "Each widget has its own style. Long-press a widget, then Edit Widget, to pick a Style and Color."
    public static let widgetProvidersFooter =
        "Set on your Mac in Settings › Widgets & iPhone. Widgets show each provider’s main account."
    public static let remindersFromMac = "Reminders come from Headroom on your Mac"
    public static let demoActive = "You are viewing sample data. Your synced snapshot is unchanged."
    public static let demoActiveWidgetsUnavailable =
        "You are viewing sample data in the app. Widgets could not join Demo Mode on this install. Your synced snapshot is unchanged."
    public static let demoVariantFooter = "Sample states for trying every screen. Nothing here reads or writes iCloud."

    static var all: [String] {
        whatSyncs + [
            updateMac, whatSyncsFooter, managedOnMac, widgetsFooter, widgetProvidersFooter,
            remindersFromMac, demoActive, demoActiveWidgetsUnavailable, demoVariantFooter,
        ]
    }
}
