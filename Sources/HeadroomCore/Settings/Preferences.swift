import Foundation

/// UserDefaults-backed preferences (U8). Renewal dates and poll interval are
/// non-secret, so they live here, not the Keychain (KTD4). The `Preferences` type
/// lands early (with U2) because U6 reads the interval and U7 reads renewal dates.
public struct Preferences: @unchecked Sendable { // UserDefaults is thread-safe
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let interval = "pollIntervalMinutes"
        static let appearancePreference = "appearancePreference"
        static let showMenuBarPercentage = "showMenuBarPercentage"
        static let menuBarFillSource = "menuBarFillSource"
        static let menuBarWindowSource = "menuBarWindowSource"
        static let widgetsEnabled = "widgetsEnabled"
        static let showCodexSparkCountersInApp = "showCodexSparkCountersInApp"
        static let showCodexSparkCountersInWidgets = "showCodexSparkCountersInWidgets"
        static let syncToIPhoneEnabled = "syncToIPhoneEnabled"
        static let apiSpendPeriod = "apiSpendPeriod"
        static func renewal(_ id: ProviderID) -> String { "renewalDate.\(id.raw)" }
        static func surfaceEnabled(_ surface: UsageSurface) -> String { "surfaceEnabled.\(surface.rawValue)" }
    }

    public static let defaultIntervalMinutes = 5

    public var pollIntervalMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.interval)
            return v > 0 ? v : Self.defaultIntervalMinutes
        }
        nonmutating set { defaults.set(max(1, newValue), forKey: Key.interval) }
    }

    public var appearancePreference: AppearancePreference {
        get {
            guard let raw = defaults.string(forKey: Key.appearancePreference),
                  let preference = AppearancePreference(rawValue: raw)
            else { return .system }
            return preference
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearancePreference) }
    }

    public var showMenuBarPercentage: Bool {
        get { defaults.bool(forKey: Key.showMenuBarPercentage) }
        nonmutating set { defaults.set(newValue, forKey: Key.showMenuBarPercentage) }
    }

    public var menuBarFillSource: MenuBarFillSource {
        get {
            guard let raw = defaults.string(forKey: Key.menuBarFillSource),
                  let source = MenuBarFillSource(rawValue: raw)
            else { return .none }
            return source
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.menuBarFillSource) }
    }

    /// Which limit window the menu bar reports (percentage, fill, tint). Default weekly.
    public var menuBarWindowSource: MenuBarWindowSource {
        get {
            guard let raw = defaults.string(forKey: Key.menuBarWindowSource),
                  let source = MenuBarWindowSource(rawValue: raw)
            else { return .weekly }
            return source
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.menuBarWindowSource) }
    }

    public var widgetsEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.widgetsEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.widgetsEnabled)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.widgetsEnabled) }
    }

    /// Default **off**, matching widgets (Jul 2026 density audit): the Spark model
    /// counters are usually pinned at 100% and doubled the Codex card's height. The
    /// Settings toggle opts back in.
    public var showCodexSparkCountersInApp: Bool {
        get { defaults.bool(forKey: Key.showCodexSparkCountersInApp) }
        nonmutating set { defaults.set(newValue, forKey: Key.showCodexSparkCountersInApp) }
    }

    public var showCodexSparkCountersInWidgets: Bool {
        get { defaults.bool(forKey: Key.showCodexSparkCountersInWidgets) }
        nonmutating set { defaults.set(newValue, forKey: Key.showCodexSparkCountersInWidgets) }
    }

    public var syncToIPhoneEnabled: Bool {
        get { defaults.bool(forKey: Key.syncToIPhoneEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.syncToIPhoneEnabled) }
    }

    public var apiSpendPeriod: APISpendPeriod {
        get {
            guard let raw = defaults.string(forKey: Key.apiSpendPeriod),
                  let period = APISpendPeriod(rawValue: raw)
            else { return .currentMonth }
            return period
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.apiSpendPeriod) }
    }

    public func isSurfaceEnabled(_ surface: UsageSurface) -> Bool {
        let key = Key.surfaceEnabled(surface)
        guard defaults.object(forKey: key) != nil else {
            return surface.isSubscription
        }
        return defaults.bool(forKey: key)
    }

    public func setSurfaceEnabled(_ enabled: Bool, for surface: UsageSurface) {
        defaults.set(enabled, forKey: Key.surfaceEnabled(surface))
    }

    public func renewalDate(for id: ProviderID) -> Date? {
        let t = defaults.double(forKey: Key.renewal(id))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    public func setRenewalDate(_ date: Date?, for id: ProviderID) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: Key.renewal(id))
        } else {
            defaults.removeObject(forKey: Key.renewal(id))
        }
    }
}

public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
