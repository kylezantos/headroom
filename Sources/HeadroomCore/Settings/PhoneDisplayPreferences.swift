import Foundation
import Observation

// MARK: - Resolution (KTD11)

/// Where the phone's display choices came from.
public enum PhoneDisplaySource: Equatable, Sendable {
    /// Match my Mac is on and the Mac sent its display block.
    case mac
    /// Match my Mac is on, but the shown data carries no display block (a v3-only Mac): the
    /// defaults, with the explanatory line (V24).
    case macUnavailable
    /// Match my Mac is off: the phone's remembered override.
    case phone
}

/// The display choices every phone card reads (U8) and the Settings specimen draws (U12).
/// Theme is separate: it is a phone-only choice and never syncs (S3).
public struct ResolvedPhoneDisplay: Equatable, Sendable {
    public let meterStyle: MeterStyle
    public let percentageMode: UsagePercentageMode
    public let accountTitleInk: AccountTitleInk
    /// The app's Codex Spark rows. The widgets follow the Mac's widget Spark switch instead
    /// (KTD13), so this never reaches a widget (V26).
    public let showsSparkRows: Bool
    public let source: PhoneDisplaySource

    /// KTD11: widgets always show what's left, whatever the app shows (V25).
    public static let widgetPercentageMode: UsagePercentageMode = .remaining

    public init(
        meterStyle: MeterStyle, percentageMode: UsagePercentageMode,
        accountTitleInk: AccountTitleInk, showsSparkRows: Bool, source: PhoneDisplaySource
    ) {
        self.meterStyle = meterStyle
        self.percentageMode = percentageMode
        self.accountTitleInk = accountTitleInk
        self.showsSparkRows = showsSparkRows
        self.source = source
    }

    init(_ block: CompanionDisplayBlock, source: PhoneDisplaySource) {
        self.init(
            meterStyle: block.meterStyle, percentageMode: block.percentageMode,
            accountTitleInk: block.accountTitleInk, showsSparkRows: block.appSparkEnabled,
            source: source)
    }

    /// The four values as a display block, for seeding and comparison.
    public var block: CompanionDisplayBlock {
        CompanionDisplayBlock(
            meterStyle: meterStyle, percentageMode: percentageMode,
            accountTitleInk: accountTitleInk, appSparkEnabled: showsSparkRows)
    }

    /// V24: Settings says why the phone isn't matching an old Mac.
    public var note: String? {
        source == .macUnavailable ? PhoneDisplayCopy.oldMacNote : nil
    }

    /// The windows an app card shows for one account: Spark rows are flagged by the Mac and
    /// filtered here by the phone's switch, never by label (KTD13).
    public func appWindows(_ windows: [CompanionResolvedWindow]) -> [CompanionResolvedWindow] {
        showsSparkRows ? windows : windows.filter { !$0.isSpark }
    }
}

/// KTD11: the phone's one "Match my Mac" switch over meter style, percentages, account-name
/// ink and the app's Spark rows, plus the override it remembers. A pure value: the store below
/// persists it, and `resolve(mac:phone:)` is the one function every phone surface calls.
public struct PhoneDisplayPreferences: Equatable, Sendable {
    public private(set) var matchesMac: Bool
    /// The phone's own choices. Seeded from the Mac the first time Match turns off, so nothing
    /// jumps, and kept when Match turns back on, so turning it off again restores them.
    public private(set) var override: CompanionDisplayBlock?

    public static let `default` = PhoneDisplayPreferences(matchesMac: true, override: nil)

    public init(matchesMac: Bool, override: CompanionDisplayBlock?) {
        // Match off with nothing stored would invent values, so it reads as Match on.
        self.matchesMac = matchesMac || override == nil
        self.override = override
    }

    /// `mac` is the shown data's display block (`CompanionResolvedContent.display`); nil for a
    /// v3-only Mac, which resolves to the defaults with Spark rows off (KTD11).
    public static func resolve(mac: CompanionDisplayBlock?, phone: PhoneDisplayPreferences)
        -> ResolvedPhoneDisplay
    {
        if !phone.matchesMac, let override = phone.override {
            return ResolvedPhoneDisplay(override, source: .phone)
        }
        guard let mac else { return ResolvedPhoneDisplay(CompanionDisplayBlock(), source: .macUnavailable) }
        return ResolvedPhoneDisplay(mac, source: .mac)
    }

    public mutating func setMatchesMac(_ matches: Bool, mac: CompanionDisplayBlock?) {
        if !matches, override == nil {
            override = Self.resolve(mac: mac, phone: self).block
        }
        matchesMac = matches
    }

    /// Choosing a value is choosing a phone override: Match turns off (seeding first) and only
    /// the chosen value moves.
    public mutating func setMeterStyle(_ style: MeterStyle, mac: CompanionDisplayBlock?) {
        edit(mac: mac) { CompanionDisplayBlock(meterStyle: style, percentageMode: $0.percentageMode, accountTitleInk: $0.accountTitleInk, appSparkEnabled: $0.appSparkEnabled) }
    }

    public mutating func setPercentageMode(_ mode: UsagePercentageMode, mac: CompanionDisplayBlock?) {
        edit(mac: mac) { CompanionDisplayBlock(meterStyle: $0.meterStyle, percentageMode: mode, accountTitleInk: $0.accountTitleInk, appSparkEnabled: $0.appSparkEnabled) }
    }

    public mutating func setAccountTitleInk(_ ink: AccountTitleInk, mac: CompanionDisplayBlock?) {
        edit(mac: mac) { CompanionDisplayBlock(meterStyle: $0.meterStyle, percentageMode: $0.percentageMode, accountTitleInk: ink, appSparkEnabled: $0.appSparkEnabled) }
    }

    public mutating func setShowsSparkRows(_ shows: Bool, mac: CompanionDisplayBlock?) {
        edit(mac: mac) { CompanionDisplayBlock(meterStyle: $0.meterStyle, percentageMode: $0.percentageMode, accountTitleInk: $0.accountTitleInk, appSparkEnabled: shows) }
    }

    private mutating func edit(mac: CompanionDisplayBlock?, _ change: (CompanionDisplayBlock) -> CompanionDisplayBlock) {
        // Seed from what's on screen right now, so only the chosen value moves.
        let current = Self.resolve(mac: mac, phone: self).block
        override = change(matchesMac ? current : (override ?? current))
        matchesMac = false
    }
}

// MARK: - Store

/// The phone app's persisted `PhoneDisplayPreferences`. Stored in the app's own defaults, not
/// the App Group: widgets always show "left" and follow the Mac's widget Spark switch, so no
/// extension reads these (KTD11, KTD13).
@MainActor @Observable
public final class PhoneDisplayPreferencesStore {
    public enum Key {
        public static let matchesMac = "phoneDisplay.matchesMac"
        public static let override = "phoneDisplay.override"
    }

    public private(set) var preferences: PhoneDisplayPreferences

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let matches = defaults.object(forKey: Key.matchesMac) as? Bool ?? true
        let override = defaults.data(forKey: Key.override)
            .flatMap { try? JSONDecoder().decode(CompanionDisplayBlock.self, from: $0) }
        preferences = PhoneDisplayPreferences(matchesMac: matches, override: override)
    }

    /// The view-layer closure U8's cards call with the shown data's display block.
    public func resolve(mac: CompanionDisplayBlock?) -> ResolvedPhoneDisplay {
        PhoneDisplayPreferences.resolve(mac: mac, phone: preferences)
    }

    public func setMatchesMac(_ matches: Bool, mac: CompanionDisplayBlock?) {
        update { $0.setMatchesMac(matches, mac: mac) }
    }

    public func setMeterStyle(_ style: MeterStyle, mac: CompanionDisplayBlock?) {
        update { $0.setMeterStyle(style, mac: mac) }
    }

    public func setPercentageMode(_ mode: UsagePercentageMode, mac: CompanionDisplayBlock?) {
        update { $0.setPercentageMode(mode, mac: mac) }
    }

    public func setAccountTitleInk(_ ink: AccountTitleInk, mac: CompanionDisplayBlock?) {
        update { $0.setAccountTitleInk(ink, mac: mac) }
    }

    public func setShowsSparkRows(_ shows: Bool, mac: CompanionDisplayBlock?) {
        update { $0.setShowsSparkRows(shows, mac: mac) }
    }

    private func update(_ change: (inout PhoneDisplayPreferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        preferences = next
        defaults.set(next.matchesMac, forKey: Key.matchesMac)
        if let override = next.override, let data = try? JSONEncoder().encode(override) {
            defaults.set(data, forKey: Key.override)
        } else {
            defaults.removeObject(forKey: Key.override)
        }
    }
}

// MARK: - Copy (R2C6: curly apostrophes, one sign-in verb, no "connect")

public enum PhoneDisplayCopy {
    public static let matchTitle = "Match my Mac"
    public static let matchFooter = "Turn off Match my Mac to choose a style for this phone only. Your Mac keeps its own."
    /// V24: an old Mac sends no display choices.
    public static let oldMacNote =
        "Update Headroom on your Mac to match its look. Until then, this phone uses the defaults."
    public static let sparkTitle = "Show Codex Spark rows"
    public static let sparkFooter =
        "Spark counters appear under Codex when this is on. The widgets keep their own switch on your Mac."
    /// KTD11 / V25: shown beside the percentages choice and in the widgets gallery.
    public static let widgetsAlwaysLeft = "Widgets always show what’s left."

    /// "Micro · Chip · Only when low": the style as drawn, so a Tube stored under Full reads
    /// as the Chip it renders.
    public static func styleSummary(_ style: MeterStyle) -> String {
        [style.format.label, style.resolvedShape.label, style.fill.label].joined(separator: " · ")
    }

    static var all: [String] {
        [matchTitle, matchFooter, oldMacNote, sparkTitle, sparkFooter, widgetsAlwaysLeft]
    }
}
