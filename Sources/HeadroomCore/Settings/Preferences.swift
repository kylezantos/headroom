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
        static let accountTitleInk = "accountTitleInk"
        static let accountLayout = "accountLayout"
        static let expandAccountsHorizontally = "expandAccountsHorizontally"
        static let useEmailAsAccountName = "useEmailAsAccountName"
        static let meterFormat = "meterFormat"
        static let meterShape = "meterShape"
        static let meterFill = "meterFill"
        static let menuBarFillSource = "menuBarFillSource"
        static let menuBarFillProviders = "menuBarFillProviders"
        static let menuBarProviderOrder = "menuBarProviderOrder"
        static let widgetPriorityProviders = "widgetPriorityProviders"
        /// Kept as a read-through migration source for installs that saved one shared
        /// menu-bar window before providers became independently configurable.
        static let legacyMenuBarWindowSource = "menuBarWindowSource"
        static let widgetsEnabled = "widgetsEnabled"
        static let showCodexSparkCountersInApp = "showCodexSparkCountersInApp"
        static let showCodexSparkCountersInWidgets = "showCodexSparkCountersInWidgets"
        static let syncToIPhoneEnabled = "syncToIPhoneEnabled"
        static let apiSpendPeriod = "apiSpendPeriod"
        static let settingsPane = "settingsPane"
        static let useItUpRemindersEnabled = "useItUpRemindersEnabled"
        static let bankedResetNotificationsEnabled = "bankedResetNotificationsEnabled"
        static let reminderRules = "reminderRules.v1"
        static let reminderScope = "reminderScope.v1"
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

    /// G1A: no widget or menu-bar projection reads it; the phone's display block does (KTD11).
    public var accountTitleInk: AccountTitleInk {
        get {
            guard let raw = defaults.string(forKey: Key.accountTitleInk),
                  let ink = AccountTitleInk(rawValue: raw)
            else { return .neutral }
            return ink
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.accountTitleInk) }
    }

    /// KTD8: Mac popover only; no phone, widget or menu-bar projection reads it.
    public var accountLayout: AccountLayout {
        get {
            guard let raw = defaults.string(forKey: Key.accountLayout),
                  let layout = AccountLayout(rawValue: raw)
            else { return .standard }
            return layout
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.accountLayout) }
    }

    /// Desktop naming only; saved registry labels and phone/widget projections stay intact.
    public var useEmailAsAccountName: Bool {
        get { defaults.bool(forKey: Key.useEmailAsAccountName) }
        nonmutating set { defaults.set(newValue, forKey: Key.useEmailAsAccountName) }
    }

    /// Mac popover only: keep existing installs' automatic second column unless opted out.
    public var expandAccountsHorizontally: Bool {
        get {
            guard defaults.object(forKey: Key.expandAccountsHorizontally) != nil else { return true }
            return defaults.bool(forKey: Key.expandAccountsHorizontally)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.expandAccountsHorizontally) }
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

    /// Independent from the app's provider order. Unknown IDs survive temporarily
    /// missing providers; the store filters them when resolving the visible order.
    public var menuBarProviderOrder: [ProviderID] {
        get { (defaults.stringArray(forKey: Key.menuBarProviderOrder) ?? []).map(ProviderID.init) }
        nonmutating set { defaults.set(newValue.map(\.raw), forKey: Key.menuBarProviderOrder) }
    }

    /// Nil means this install still inherits its legacy menu-bar priority selection.
    /// An empty array is an explicit automatic widget selection, not an unmigrated one.
    public var widgetPriorityProviders: [ProviderID]? {
        get { defaults.stringArray(forKey: Key.widgetPriorityProviders)?.map(ProviderID.init) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.map(\.raw), forKey: Key.widgetPriorityProviders)
            } else {
                defaults.removeObject(forKey: Key.widgetPriorityProviders)
            }
        }
    }

    /// The chosen menu-bar limit for one provider. A provider-specific value wins;
    /// otherwise the pre-1.1 shared value is inherited so upgrading does not change the
    /// existing menu-bar presentation. Fresh installs default every provider to weekly.
    /// Stored values from before per-limit IDs ("weekly", "fiveHour") are already valid IDs.
    public func menuBarWindowChoice(for id: ProviderID) -> MenuBarWindowChoice {
        if let raw = defaults.string(forKey: Key.menuBarWindowSource(id)),
           let choice = MenuBarWindowChoice(rawValue: raw) {
            return choice
        }
        if let raw = defaults.string(forKey: Key.legacyMenuBarWindowSource),
           let choice = MenuBarWindowChoice(rawValue: raw) {
            return choice
        }
        return .weekly
    }

    /// True once the user has picked this provider's limit. Only such a choice is worth
    /// listing when the provider stops reporting it: the weekly default names a limit
    /// Cursor and Grok never had.
    public func hasChosenMenuBarWindow(for id: ProviderID) -> Bool {
        defaults.string(forKey: Key.menuBarWindowSource(id)).flatMap(MenuBarWindowChoice.init(rawValue:)) != nil
    }

    public func setMenuBarWindowChoice(_ choice: MenuBarWindowChoice, for id: ProviderID) {
        defaults.set(choice.rawValue, forKey: Key.menuBarWindowSource(id))
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

    /// Last-visited Settings destination (R4/KTD7). A plain preference rather than
    /// `@SceneStorage` so the choice survives quitting the app, not just closing the
    /// window; an unrecognized stored pane falls back to General.
    public var settingsPane: SettingsPane {
        get {
            guard let raw = defaults.string(forKey: Key.settingsPane),
                  let pane = SettingsPane(rawValue: raw)
            else { return .general }
            return pane
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.settingsPane) }
    }

    /// R2B1: the destination Settings opens on. Once the user has visited a pane the stored
    /// choice always wins (R4). Only the *first* open has a decision to make, and General is
    /// the wrong answer there — it holds two controls and several hundred points of empty
    /// pane, while a Mac with nothing signed in has all of its work in Accounts.
    public func initialSettingsPane(hasSignedInAccount: Bool) -> SettingsPane {
        guard defaults.object(forKey: Key.settingsPane) == nil else { return settingsPane }
        return hasSignedInAccount ? .general : .accounts
    }

    /// R3: off by default.
    public var useItUpRemindersEnabled: Bool {
        get { defaults.bool(forKey: Key.useItUpRemindersEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.useItUpRemindersEnabled) }
    }

    /// R14: off by default.
    public var bankedResetNotificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.bankedResetNotificationsEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.bankedResetNotificationsEnabled) }
    }

    /// KTD14: a missing key yields the defaults; a corrupt one yields the defaults without
    /// overwriting, so a newer build's data survives a downgrade. Stored values clamp on
    /// read so the evaluator never sees an out-of-range rule.
    public var reminderRules: [ReminderRule] {
        get {
            guard let data = defaults.data(forKey: Key.reminderRules),
                  let rules = try? JSONDecoder().decode([ReminderRule].self, from: data)
            else { return ReminderRules.defaults }
            return rules.map { $0.clamped() }
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.reminderRules)
        }
    }

    /// Stored as sorted raw strings; an unknown value from a newer build is dropped
    /// rather than discarding the whole set.
    public var reminderScope: Set<ReminderScope> {
        get {
            guard let data = defaults.data(forKey: Key.reminderScope),
                  let raw = try? JSONDecoder().decode([String].self, from: data)
            else { return ReminderScope.defaults }
            return Set(raw.compactMap(ReminderScope.init(rawValue:)))
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue.map(\.rawValue).sorted()) else { return }
            defaults.set(data, forKey: Key.reminderScope)
        }
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
