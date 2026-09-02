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
        static let usagePercentageMode = "usagePercentageMode"
        static let meterFormat = "meterFormat"
        static let meterShape = "meterShape"
        static let meterFill = "meterFill"
        static let menuBarFillSource = "menuBarFillSource"
        static let menuBarFillProviders = "menuBarFillProviders"
        /// Kept as a read-through migration source for installs that saved one shared
        /// menu-bar window before providers became independently configurable.
        static let legacyMenuBarWindowSource = "menuBarWindowSource"
        static let widgetsEnabled = "widgetsEnabled"
        static let showCodexSparkCountersInApp = "showCodexSparkCountersInApp"
        static let showCodexSparkCountersInWidgets = "showCodexSparkCountersInWidgets"
        static let syncToIPhoneEnabled = "syncToIPhoneEnabled"
        static let apiSpendPeriod = "apiSpendPeriod"
        static func menuBarWindowSource(_ id: ProviderID) -> String { "menuBarWindowSource.\(id.raw)" }
        static func renewal(_ id: ProviderID) -> String { "renewalDate.\(id.raw)" }
        static func surfaceEnabled(_ surface: UsageSurface) -> String { "surfaceEnabled.\(surface.rawValue)" }
    }

    public static let defaultIntervalMinutes = 5
    public static let minimumIntervalMinutes = 2

    public var pollIntervalMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.interval)
            return v > 0 ? max(Self.minimumIntervalMinutes, v) : Self.defaultIntervalMinutes
        }
        nonmutating set { defaults.set(max(Self.minimumIntervalMinutes, newValue), forKey: Key.interval) }
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

    public var usagePercentageMode: UsagePercentageMode {
        get {
            guard let raw = defaults.string(forKey: Key.usagePercentageMode),
                  let mode = UsagePercentageMode(rawValue: raw)
            else { return .remaining }
            return mode
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.usagePercentageMode) }
    }

    public var meterFormat: GaugeFormat {
        get {
            guard let raw = defaults.string(forKey: Key.meterFormat),
                  let format = GaugeFormat(rawValue: raw)
            else { return MeterStyle.default.format }
            return format
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.meterFormat) }
    }

    public var meterShape: GaugeShape {
        get {
            guard let raw = defaults.string(forKey: Key.meterShape),
                  let shape = GaugeShape(rawValue: raw)
            else { return MeterStyle.default.shape }
            return shape
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.meterShape) }
    }

    public var meterFill: GaugeFill {
        get {
            guard let raw = defaults.string(forKey: Key.meterFill),
                  let fill = GaugeFill(rawValue: raw)
            else { return MeterStyle.default.fill }
            return fill
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.meterFill) }
    }

    public var meterStyle: MeterStyle {
        get {
            MeterStyle(format: meterFormat, shape: meterShape, fill: meterFill)
        }
        nonmutating set {
            if meterFormat != newValue.format { meterFormat = newValue.format }
            if meterShape != newValue.shape { meterShape = newValue.shape }
            if meterFill != newValue.fill { meterFill = newValue.fill }
        }
    }

    public var menuBarFillSource: MenuBarFillSource {
        get {
            switch defaults.string(forKey: Key.menuBarFillSource) {
            case "providers":
                let ids = Set((defaults.stringArray(forKey: Key.menuBarFillProviders) ?? []).map(ProviderID.init))
                return ids.isEmpty ? .auto : .providers(ids)
            case "claude":
                return .claude
            case "codex":
                return .codex
            case "both":
                return .both
            default:
                // Legacy `none` was the shipped automatic tightest-window summary,
                // despite its label suggesting an empty selection (KTD4).
                return .auto
            }
        }
        nonmutating set {
            switch newValue {
            case .auto:
                defaults.set("auto", forKey: Key.menuBarFillSource)
                defaults.removeObject(forKey: Key.menuBarFillProviders)
            case .providers(let ids):
                guard !ids.isEmpty else {
                    defaults.set("auto", forKey: Key.menuBarFillSource)
                    defaults.removeObject(forKey: Key.menuBarFillProviders)
                    return
                }
                defaults.set("providers", forKey: Key.menuBarFillSource)
                defaults.set(ids.map(\.raw).sorted(), forKey: Key.menuBarFillProviders)
            }
        }
    }

    /// The preferred menu-bar window for one provider. A provider-specific value wins;
    /// otherwise the pre-1.1 shared value is inherited so upgrading does not change the
    /// existing menu-bar presentation. Fresh installs default both providers to weekly.
    public func menuBarWindowSource(for id: ProviderID) -> MenuBarWindowSource {
        if let raw = defaults.string(forKey: Key.menuBarWindowSource(id)),
           let source = MenuBarWindowSource(rawValue: raw) {
            return source
        }
        if let raw = defaults.string(forKey: Key.legacyMenuBarWindowSource),
           let source = MenuBarWindowSource(rawValue: raw) {
            return source
        }
        return .weekly
    }

    public func setMenuBarWindowSource(_ source: MenuBarWindowSource, for id: ProviderID) {
        defaults.set(source.rawValue, forKey: Key.menuBarWindowSource(id))
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
            return surface.isEnabledByDefault
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
