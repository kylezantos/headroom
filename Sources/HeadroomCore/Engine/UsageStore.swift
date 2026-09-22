import Foundation
import Observation

/// Compact, self-contained menu bar summary (R5): the tightest live window plus its
/// provider identity, so the bar means something without opening the popover.
public struct MenuBarSummary: Sendable, Equatable {
    public let text: String            // e.g. "12%"
    public let providerID: ProviderID? // which provider the number is about
    public let detail: String?         // e.g. "Claude 5h"
    public let percentageMode: UsagePercentageMode?
    public let isNeutral: Bool         // true when no live data yet
    /// Health of the shown window — tints the glyph by urgency, not brand (UI-03).
    public let severity: UsageSeverity
    /// Any provider is permanently stale (needs the user to re-auth in its CLI) — the
    /// glyph shows a warning dot so a dead provider isn't invisible in the menu bar.
    public let needsAttention: Bool

    public init(
        text: String,
        providerID: ProviderID?,
        detail: String?,
        isNeutral: Bool,
        percentageMode: UsagePercentageMode? = nil,
        severity: UsageSeverity = .healthy,
        needsAttention: Bool = false
    ) {
        self.text = text
        self.providerID = providerID
        self.detail = detail
        self.isNeutral = isNeutral
        self.percentageMode = percentageMode
        self.severity = severity
        self.needsAttention = needsAttention
    }

    public static let neutral = MenuBarSummary(text: "—", providerID: nil, detail: nil, isNeutral: true)

    /// Copy of this summary with the menu-bar attention flag set — lets the neutral
    /// (no-live-data) case still surface a needs-reauth provider.
    func withAttention(_ flag: Bool) -> MenuBarSummary {
        MenuBarSummary(text: text, providerID: providerID, detail: detail,
                       isNeutral: isNeutral, percentageMode: percentageMode,
                       severity: severity, needsAttention: flag)
    }
}

/// One compact status unit for the menu bar. Automatic mode renders one summary;
/// an explicit provider selection renders one meter per provider.
public struct MenuBarMeter: Sendable, Equatable {
    public let summary: MenuBarSummary
    /// 0...1 fill for the vessel, or nil for the static decorative level.
    public let fill: Double?

    public init(summary: MenuBarSummary, fill: Double?) {
        self.summary = summary
        self.fill = fill
    }
}

private struct ResolvedMenuBarWindow {
    let id: ProviderID
    let window: UsageWindow
    let kind: WindowKind

    var shortLabel: String { kind.shortLabel.lowercased() }
}

public enum AccountRemovalState: Sendable, Equatable {
    case removing
    case setupActive
    case failed
}

public enum AccountRemovalResult: Sendable, Equatable {
    case removed
    case setupActive
    case failed
    case notAllowed
}

/// The observable view model the UI and menu bar label bind to (U6). `@MainActor`
/// and `@Observable`: snapshots are published on the main actor; providers are
/// fetched concurrently off-main (KTD10). Per-provider isolation — one provider's
/// failure updates only its own snapshot (KTD7).
///
/// Multi-account (Jul 2026): snapshots are keyed by `AccountKey` — one provider can
/// carry up to `AccountRegistry.testedEnvelope` signed-in accounts. The menu bar and
/// widgets follow each provider's selected primary account so those compact surfaces
/// keep meaning one thing; the popover shows every account.
@MainActor
@Observable
public final class UsageStore {
    public internal(set) var snapshots: [AccountKey: UsageSnapshot]
    public internal(set) var accountsByProvider: [ProviderID: [ProviderAccount]]
    public private(set) var apiSpendSnapshots: [ProviderID: APISpendSnapshot]
    public private(set) var showMenuBarPercentage: Bool
    public private(set) var usagePercentageMode: UsagePercentageMode
    /// G1A: popover-only account-title ink, mirrored the same way `meterStyle` is — the
    /// menu bar, widgets, and phone projections deliberately carry no title ink.
    public private(set) var accountTitleInk: AccountTitleInk
    public private(set) var meterStyle: MeterStyle
    public private(set) var menuBarFillSource: MenuBarFillSource
    private var savedMenuBarProviderOrder: [ProviderID]
    public private(set) var widgetPrioritySource: MenuBarFillSource
    public private(set) var menuBarWindowSources: [ProviderID: MenuBarWindowSource]
    public private(set) var showCodexSparkCountersInApp: Bool
    public private(set) var showCodexSparkCountersInWidgets: Bool
    public private(set) var enabledSurfaces: Set<UsageSurface>
    public private(set) var providerCapabilities: [ProviderID: ProviderCapabilityStatus]
    public internal(set) var accountRemovalStates: [AccountKey: AccountRemovalState] = [:]
    public let displayNames: [ProviderID: String]
    public let apiSpendDisplayNames: [ProviderID: String]

    /// The popover's "Refreshing…" signal (UI-02). KTD2 (2026-09-19 polling plan): true
    /// only while a user-initiated request — Refresh, Check Now, a setup check — still has
    /// unmerged work. Timer-driven lane passes never set it, so the Refresh button does not
    /// disappear for half of every interval at the account envelope.
    public private(set) var isRefreshing = false
    @ObservationIgnored private var userWorkPending = false
    @ObservationIgnored private var apiSpendUserRefreshDepth = 0
    @ObservationIgnored private var apiSpendInFlight = false
    /// KTD12: per-provider chosen vs effective interval for Settings, refreshed whenever a
    /// lane goes idle so the General pane observes it like any other store value.
    public private(set) var pollCadences: [ProviderID: PollCadence] = [:]
    /// Depth of user-initiated full refreshes in flight. While one runs, primary merges
    /// skip their own export because the refresh exports once at its end (KTD9), which
    /// keeps launch to a single widget write.
    @ObservationIgnored private var fullRefreshDepth = 0
    /// KTD1: per-lane due-queue engine. Owns the attempt clock, probe log, and priority
    /// requests; everything that touches snapshots comes back through the host protocol.
    let scheduler = AccountProbeScheduler()

    var providers: [any UsageProvider]
    private let apiSpendProviders: [any APISpendProvider]
    private let preferences: Preferences
    let accountRegistry: AccountRegistry?
    let accountStorage: any AccountStorageManaging
    let continuityCache: (any UsageContinuityCaching)?
    /// KTD14 (2026-09-19 sign-in plan): diagnostics-only record of observed Claude
    /// sign-outs. Optional so the render harness, demo stores, and tests that don't
    /// care compose without it.
    let signOutRecord: SignOutRecord?
    /// Per-account banked-reset announcements. Optional so tests and the demo
    /// store compose without it; the shipping store always has one (KTD6).
    let bankedResetAcknowledgements: BankedResetAcknowledgements?
    private let now: @Sendable () -> Date
    /// Builds the concrete provider for a newly added account. Lives in the composition
    /// root (R13) and is injected so the store never names concrete provider types.
    let providerFactory: (@MainActor (ProviderAccount) -> any UsageProvider)?
    let widgetExporter: (any WidgetSnapshotExporting)?
    let phoneSyncExporter: (any WidgetSnapshotExporting)?
    private(set) var engine: PollingEngine?
    private var isStarting = false
    @ObservationIgnored var removingAccounts: Set<AccountKey> = []
    @ObservationIgnored private var capabilityGenerations: [ProviderID: UInt64] = [:]
    /// Per-key attach/detach epoch. A fetch result is only merged when the attachment
    /// it started against is still current; a stop-track/remove bumps the epoch so a
    /// late pre-detach result can't overwrite a reattached row's fresh pending state
    /// or repopulate the continuity cache the detach cleared (code-review finding).
    @ObservationIgnored var attachmentGenerations: [AccountKey: UInt64] = [:]
    @ObservationIgnored var setupCoordinator: SetupSessionCoordinator?
    /// Provider-ID order fixed at composition time. Account add/detach mutates the
    /// instance array at arbitrary positions, so deriving group order from instance
    /// order would demote a provider whose built-in was stop-tracked (code-review
    /// finding); this keeps settings/popover/widget provider order stable.
    private let composedProviderOrder: [ProviderID]

    public init(
        providers: [any UsageProvider],
        apiSpendProviders: [any APISpendProvider] = [],
        preferences: Preferences = Preferences(),
        accounts: [ProviderAccount]? = nil,
        accountRegistry: AccountRegistry? = nil,
        accountStorage: any AccountStorageManaging = DefaultAccountStorage(),
        providerFactory: (@MainActor (ProviderAccount) -> any UsageProvider)? = nil,
        continuityCache: (any UsageContinuityCaching)? = nil,
        signOutRecord: SignOutRecord? = nil,
        bankedResetAcknowledgements: BankedResetAcknowledgements? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        widgetExporter: (any WidgetSnapshotExporting)? = nil,
        phoneSyncExporter: (any WidgetSnapshotExporting)? = nil
    ) {
        self.providers = providers
        self.apiSpendProviders = apiSpendProviders
        self.preferences = preferences
        self.accountRegistry = accountRegistry
        self.accountStorage = accountStorage
        self.providerFactory = providerFactory
        self.continuityCache = continuityCache
        self.signOutRecord = signOutRecord
        self.bankedResetAcknowledgements = bankedResetAcknowledgements
        self.now = now
        self.widgetExporter = widgetExporter
        self.phoneSyncExporter = phoneSyncExporter
        self.displayNames = Dictionary(providers.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        self.apiSpendDisplayNames = Dictionary(
            apiSpendProviders.map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        // Uniquing, never trapping: a duplicated persisted account entry must degrade
        // to one row, not a launch crash loop (code-review finding).
        let cachedSnapshots = continuityCache?.load() ?? [:]
        let restorationDate = now()
        self.snapshots = Dictionary(
            providers.map { provider in
                let snapshot = Self.restoredSnapshot(
                    cachedSnapshots[provider.accountKey],
                    for: provider.id,
                    after: restorationDate
                )
                return (provider.accountKey, snapshot)
            },
            uniquingKeysWith: { first, _ in first }
        )
        self.providerCapabilities = Dictionary(
            providers.filter(\.reportsProviderCapability).map {
                ($0.id, ProviderCapabilityStatus(state: .unknown, observedAt: restorationDate))
            },
            uniquingKeysWith: { first, _ in first }
        )
        self.accountsByProvider = Self.accountsIndex(providers: providers, accounts: accounts, registry: accountRegistry)
        self.apiSpendSnapshots = Dictionary(uniqueKeysWithValues: apiSpendProviders.map {
            ($0.id, .pending(providerID: $0.id, displayName: $0.displayName, periodLabel: preferences.apiSpendPeriod.label))
        })
        self.showMenuBarPercentage = preferences.showMenuBarPercentage
        self.usagePercentageMode = preferences.usagePercentageMode
        self.accountTitleInk = preferences.accountTitleInk
        self.meterStyle = preferences.meterStyle
        let registeredProviderIDs = providers.map(\.id).uniqued()
        self.composedProviderOrder = registeredProviderIDs
        self.menuBarFillSource = preferences.menuBarFillSource.filtered(to: registeredProviderIDs)
        self.savedMenuBarProviderOrder = preferences.menuBarProviderOrder
        if let saved = preferences.widgetPriorityProviders {
            self.widgetPrioritySource = saved.isEmpty ? .auto : .providers(Set(saved))
        } else {
            self.widgetPrioritySource = preferences.menuBarFillSource
        }
        self.menuBarWindowSources = Dictionary(uniqueKeysWithValues: registeredProviderIDs.map {
            ($0, preferences.menuBarWindowSource(for: $0))
        })
        self.showCodexSparkCountersInApp = preferences.showCodexSparkCountersInApp
        self.showCodexSparkCountersInWidgets = preferences.showCodexSparkCountersInWidgets
        self.enabledSurfaces = Set(UsageSurface.allCases.filter { preferences.isSurfaceEnabled($0) })
        scheduler.host = self
        for provider in providers { scheduler.register(provider) }
    }

    private static func restoredSnapshot(
        _ cached: UsageSnapshot?,
        for providerID: ProviderID,
        after restorationDate: Date
    ) -> UsageSnapshot {
        UsageContinuityPolicy.restoredSnapshot(
            cached,
            for: providerID,
            at: restorationDate
        )
    }

    /// Account metadata for every provider instance. Explicit `accounts` (render
    /// harness/tests) wins, then the registry, then a synthesized built-in per provider
    /// so plain single-account construction keeps working with no extra wiring.
    private static func accountsIndex(
        providers: [any UsageProvider],
        accounts: [ProviderAccount]?,
        registry: AccountRegistry?
    ) -> [ProviderID: [ProviderAccount]] {
        var index: [ProviderID: [ProviderAccount]] = [:]
        for id in providers.map(\.id).uniqued() {
            let known: [ProviderAccount]
            if let accounts {
                known = accounts.filter { $0.providerID == id }
            } else if let registry {
                known = registry.accounts(for: id)
            } else {
                known = []
            }
            let instanceIDs = providers
                .filter { $0.id == id }
                .map(\.accountID)
                .uniqued()
            let instanceIDSet = Set(instanceIDs)
            let orderedKnown = known.filter { instanceIDSet.contains($0.id) }
            let knownIDs = Set(orderedKnown.map(\.id))
            let orderedIDs = orderedKnown.map(\.id) + instanceIDs.filter { !knownIDs.contains($0) }
            index[id] = orderedIDs.map { accountID in
                known.first(where: { $0.id == accountID })
                    ?? ProviderAccount(id: accountID, providerID: id, label: "Main", isBuiltIn: accountID == .primary)
            }
        }
        return index
    }

    public var providerOrder: [ProviderID] {
        registeredProviderOrder.filter { id in
            guard let surface = UsageSurface.subscription(for: id) else { return false }
            return enabledSurfaces.contains(surface)
        }
    }

    /// Every composed subscription provider, including surfaces currently switched off.
    /// Settings/account management use this registry order; display surfaces use
    /// `providerOrder`, which additionally applies the user's surface toggles.
    public var registeredProviderOrder: [ProviderID] {
        let live = providers.map(\.id).uniqued()
        let liveSet = Set(live)
        return composedProviderOrder.filter(liveSet.contains)
            + live.filter { !composedProviderOrder.contains($0) }
    }

    public var apiSpendProviderOrder: [ProviderID] {
        registeredAPISpendProviderOrder.filter { id in
            guard let surface = UsageSurface.api(for: id) else { return false }
            guard enabledSurfaces.contains(surface) else { return false }
            // A live nil amount is an explicit "not applicable" result (currently
            // Cursor with on-demand disabled), so no empty spend row is rendered.
            if let snapshot = apiSpendSnapshots[id],
               snapshot.freshness == .live, snapshot.amount == nil {
                return false
            }
            return true
        }
    }

    public var registeredAPISpendProviderOrder: [ProviderID] {
        apiSpendProviders.map(\.id).uniqued()
    }

    /// Begin polling: an immediate refresh, then the interval loop. Idempotent — a
    /// second call (e.g. the popover re-appearing) does not restart the loop or
    /// reset the cadence.
    public func start() async {
        guard engine == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await refreshAll()
        // KTD6: the loop sleeps until the earliest due account in an idle lane (each
        // account phased toward its own reset, R2M3 carried per account) and a tick only
        // dispatches; the lanes drain in their own tasks and re-arm the sleep at pass end.
        let engine = PollingEngine(
            nextWake: { [weak self] in
                self?.scheduler.wakeDelay()
                    ?? LaneSchedule.chosenInterval(minutes: Preferences.defaultIntervalMinutes)
            },
            now: now,
            tick: { [weak self] in self?.scheduler.dispatchDue() }
        )
        engine.start()
        self.engine = engine
    }

    /// Immediate off-cadence refresh — the Refresh button and other explicit user actions
    /// (KTD9). Popover open deliberately does *not* land here: it goes through
    /// `refreshOnPopoverOpen()`, which gates on capture age (R2M2).
    public func refreshNow() {
        Task { await refreshAll() }
    }

    /// R2M2: freshen on popover open, but only when the timer was about to fire anyway.
    /// The popover is the app's highest-frequency moment and a Claude poll is a full CLI
    /// session, so this wakes the queue only once the oldest live capture has already aged
    /// past a full poll interval; the lane's pass-end rephase then puts the next tick a full
    /// interval after the fresh data. At most one extra poll per interval; the cadence
    /// itself is never raised (AGENTS.md's cost warning).
    public func refreshOnPopoverOpen() {
        // A user refresh already in flight is freshening the data by itself.
        guard !isRefreshing else { return }
        guard Self.shouldRefreshOnPopoverOpen(
            oldestLiveCapture: oldestLiveCapture,
            now: now(),
            intervalMinutes: preferences.pollIntervalMinutes
        ) else { return }
        // KTD6: wake the queue for whatever is due instead of forcing every account; the
        // lane's pass-end rephase moves the next tick a full interval past the fresh data.
        scheduler.dispatchDue()
    }

    /// Oldest capture time among snapshots that are actually live. Permanently stale rows
    /// are excluded on purpose: their retained `capturedAt` only gets older, so counting
    /// them would make every popover open trigger a refresh forever.
    var oldestLiveCapture: Date? {
        snapshots.values
            .filter { $0.freshness == .live }
            .compactMap(\.capturedAt)
            .min()
    }

    nonisolated static func shouldRefreshOnPopoverOpen(
        oldestLiveCapture: Date?,
        now: Date,
        intervalMinutes: Int
    ) -> Bool {
        // Nothing live means nothing to freshen — a never-signed-in or failing account has
        // its own recovery affordance in the card, and probing it on every open would burn a
        // CLI session per open.
        guard let oldestLiveCapture else { return false }
        let interval = Double(PollingEngine.clampedIntervalMinutes(intervalMinutes)) * 60
        return now.timeIntervalSince(oldestLiveCapture) >= interval
    }

    /// Refresh only API spend providers. Settings uses this for spend-only controls so
    /// a checkbox click doesn't spawn the expensive Claude subscription CLI probe.
    public func refreshAPISpendNow() {
        Task { await refreshAPISpendOnly() }
    }

    /// Restart the loop so a changed poll interval takes effect now (R14).
    public func reschedulePolling() {
        refreshPollCadences()
        engine?.reschedule()
    }

    public func setShowMenuBarPercentage(_ enabled: Bool) {
        preferences.showMenuBarPercentage = enabled
        showMenuBarPercentage = enabled
    }

    public func setUsagePercentageMode(_ mode: UsagePercentageMode) {
        preferences.usagePercentageMode = mode
        usagePercentageMode = mode
    }

    public func setAccountTitleInk(_ ink: AccountTitleInk) {
        guard accountTitleInk != ink else { return }
        preferences.accountTitleInk = ink
        accountTitleInk = ink
    }

    public func setMeterStyle(_ style: MeterStyle) {
        guard meterStyle != style else { return }
        preferences.meterStyle = style
        meterStyle = style
    }

    public func setMenuBarFillSource(_ source: MenuBarFillSource) {
        // Freeze the old shared selection before the first menu-bar edit, so an
        // upgrade preserves widget contents across launches as well as in memory.
        if preferences.widgetPriorityProviders == nil {
            preferences.widgetPriorityProviders = widgetPrioritySource.providerIDs?.sorted { $0.raw < $1.raw } ?? []
        }
        let filtered = source.filtered(to: registeredProviderOrder)
        preferences.menuBarFillSource = filtered
        menuBarFillSource = filtered
    }

    public func setWidgetPrioritySource(_ source: MenuBarFillSource) {
        let filtered = source.filtered(to: registeredProviderOrder)
        preferences.widgetPriorityProviders = filtered.providerIDs?.sorted { $0.raw < $1.raw } ?? []
        widgetPrioritySource = filtered
        exportWidgetSnapshot()
    }

    public var menuBarProviderOrder: [ProviderID] {
        let registered = registeredProviderOrder
        return savedMenuBarProviderOrder.filter(registered.contains).uniqued()
            + registered.filter { !savedMenuBarProviderOrder.contains($0) }
    }

    /// The same ordered IDs drive both the arranger and the actual menu-bar label.
    public var selectedMenuBarProviders: [ProviderID] {
        guard let selected = menuBarFillSource.providerIDs else { return [] }
        return menuBarProviderOrder.filter { selected.contains($0) && providerOrder.contains($0) }
    }

    public func addMenuBarProvider(_ id: ProviderID) {
        guard providerOrder.contains(id) else { return }
        var selected = menuBarFillSource.providerIDs ?? []
        guard selected.insert(id).inserted else { return }
        saveMenuBarOrder(menuBarProviderOrder.filter { $0 != id } + [id])
        setMenuBarFillSource(.providers(selected))
    }

    public func removeMenuBarProvider(_ id: ProviderID) {
        // Keep an explicit escape to the automatic summary instead of silently
        // switching modes when the last visible provider is removed.
        guard selectedMenuBarProviders.count > 1,
              var selected = menuBarFillSource.providerIDs,
              selected.remove(id) != nil else { return }
        setMenuBarFillSource(.providers(selected))
    }

    /// A nil target appends the dragged pill. Ignore external/stale drop payloads.
    public func moveMenuBarProvider(_ id: ProviderID, before target: ProviderID?) {
        let visible = selectedMenuBarProviders
        guard visible.contains(id), target != id,
              target.map(visible.contains) ?? true else { return }
        var order = menuBarProviderOrder.filter { $0 != id }
        let index = target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(id, at: index)
        saveMenuBarOrder(order)
    }

    public func moveMenuBarProvider(_ id: ProviderID, by offset: Int) {
        let visible = selectedMenuBarProviders
        guard let index = visible.firstIndex(of: id),
              [-1, 1].contains(offset), visible.indices.contains(index + offset) else { return }
        let insertion = offset < 0 ? index - 1 : index + 2
        moveMenuBarProvider(id, before: visible.indices.contains(insertion) ? visible[insertion] : nil)
    }

    private func saveMenuBarOrder(_ order: [ProviderID]) {
        // Preserve temporarily unregistered IDs rather than forgetting their preference.
        let saved = order + savedMenuBarProviderOrder.filter { !order.contains($0) }
        savedMenuBarProviderOrder = saved.uniqued()
        preferences.menuBarProviderOrder = savedMenuBarProviderOrder
    }

    public func menuBarWindowSource(for id: ProviderID) -> MenuBarWindowSource {
        menuBarWindowSources[id] ?? preferences.menuBarWindowSource(for: id)
    }

    public func setMenuBarWindowSource(_ source: MenuBarWindowSource, for id: ProviderID) {
        preferences.setMenuBarWindowSource(source, for: id)
        menuBarWindowSources[id] = source
    }

    /// The source currently rendered after availability fallback. Settings compares
    /// this with the preferred source so a provider removing a window is never silent.
    public func resolvedMenuBarWindowSource(for id: ProviderID) -> MenuBarWindowSource? {
        guard let kind = menuBarWindow(for: id)?.kind else { return nil }
        return MenuBarWindowSource.allCases.first { $0.kind == kind }
    }

    public func resolvedMenuBarWindowKind(for id: ProviderID) -> WindowKind? {
        menuBarWindow(for: id)?.kind
    }

    public func hasSelectableMenuBarWindows(for id: ProviderID) -> Bool {
        let windows = snapshot(for: id).windows
        // Pending/no-data providers retain the existing selector until their real
        // shape is known; a live billing-period-only provider then hides it.
        guard !windows.isEmpty else { return true }
        return windows.contains { window in
            MenuBarWindowSource.allCases.contains { $0.kind == window.kind }
        }
    }

    public func setShowCodexSparkCountersInApp(_ enabled: Bool) {
        preferences.showCodexSparkCountersInApp = enabled
        showCodexSparkCountersInApp = enabled
    }

    public func setShowCodexSparkCountersInWidgets(_ enabled: Bool) {
        preferences.showCodexSparkCountersInWidgets = enabled
        showCodexSparkCountersInWidgets = enabled
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    /// How full to draw the menu-bar vessel, 0…1: the selected provider's chosen
    /// menu-bar window percentage in the selected display mode (weekly or 5-hour,
    /// per Settings). Reads
    /// from the last-known windows regardless of
    /// freshness, so a transient failure doesn't make the pill jump. Nil when the
    /// source is automatic or that provider has no supported window yet — the label
    /// then falls back to a static decorative fill.
    public var menuBarFill: Double? {
        guard case .providers(let ids) = menuBarFillSource,
              ids.count == 1,
              let id = ids.first,
              let resolved = menuBarWindow(for: id)
        else { return nil }
        return usagePercentageMode.fraction(for: resolved.window)
    }

    /// Render-ready menu bar meters. Explicit selection gives each chosen provider its
    /// own vessel/percentage pair; automatic mode keeps the existing compact summary.
    public var menuBarMeters: [MenuBarMeter] {
        guard menuBarFillSource.providerIDs != nil else {
            return [MenuBarMeter(summary: menuBarSummary, fill: menuBarFill)]
        }

        let meters = selectedMenuBarProviders.map { providerMenuBarMeter(for: $0) }
        return meters.isEmpty ? [MenuBarMeter(summary: .neutral, fill: nil)] : meters
    }

    public var widgetsEnabled: Bool { preferences.widgetsEnabled }
    public var syncToIPhoneEnabled: Bool { preferences.syncToIPhoneEnabled }

    public func setWidgetsEnabled(_ enabled: Bool) {
        preferences.widgetsEnabled = enabled
        exportWidgetSnapshot()
    }

    public func setSyncToIPhoneEnabled(_ enabled: Bool) {
        preferences.syncToIPhoneEnabled = enabled
        exportPhoneSyncSnapshot()
    }

    public func isSurfaceEnabled(_ surface: UsageSurface) -> Bool {
        enabledSurfaces.contains(surface)
    }

    public func setSurfaceEnabled(_ enabled: Bool, for surface: UsageSurface) {
        preferences.setSurfaceEnabled(enabled, for: surface)
        if enabled {
            enabledSurfaces.insert(surface)
            // KTD11: a re-enabled provider's accounts are due now once, with no attempt
            // history, so the toggle can neither burst-stretch the lane nor read as overdue.
            let keys = providers.map(\.accountKey).filter { UsageSurface.subscription(for: $0.providerID) == surface }
            scheduler.markDueNow(keys)
        } else {
            enabledSurfaces.remove(surface)
            // KTD11: queued user requests for these accounts can no longer be served.
            let keys = providers.map(\.accountKey).filter { UsageSurface.subscription(for: $0.providerID) == surface }
            scheduler.withdraw(keys)
        }
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    public var apiSpendPeriod: APISpendPeriod {
        preferences.apiSpendPeriod
    }

    public func setAPISpendPeriod(_ period: APISpendPeriod) {
        preferences.apiSpendPeriod = period
    }

    /// KTD2: a user asked for everything. Every enabled account is due now, bypasses the
    /// duty-cycle gate, and the call returns once the lanes it started have drained — the
    /// contract the store tests and the launch refresh rely on.
    public func refreshAll() async {
        fullRefreshDepth += 1
        // Raised before the subscription work so the flag does not blink off between the
        // last merge and the spend fetch.
        apiSpendUserRefreshDepth += 1
        recomputeRefreshing()
        scheduler.markAllDue()
        scheduler.dispatchDue()
        await scheduler.waitUntilUserWorkDrains()
        // Timer candidates a lane keeps serving after the user's work merged export on their
        // own; the refresh's single export below still follows every lane going idle.
        fullRefreshDepth -= 1
        await scheduler.waitUntilLanesIdle()
        await refreshAPISpend(exportAfter: false)
        apiSpendUserRefreshDepth -= 1
        recomputeRefreshing()
        refreshPollCadences()
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    /// Refresh a single account — Check Now, Check Again, Try Again, Make Main, and the
    /// setup coordinator's checks (R4, KTD7). A front-of-queue request, so watching one
    /// sign-in never fans out into a full fleet poll.
    public func refreshAccountNow(_ key: AccountKey) {
        scheduler.requestPriority(key)
    }

    func refreshAccount(_ key: AccountKey) async {
        scheduler.requestPriority(key)
        await scheduler.waitForCompletion(of: key)
    }

    /// Timer tick, popover open, or a Settings surface change: probe whatever is due, one
    /// per CLI lane, without marking anything due that is not (KTD6, KTD11).
    public func dispatchDueNow() {
        scheduler.dispatchDue()
    }

    public func dispatchDueNow(for providerID: ProviderID) {
        scheduler.dispatchDue(for: providerID)
    }

    /// KTD12: what Settings shows for a provider — the chosen interval, the interval its
    /// accounts actually experience, and how many accounts share the lane.
    public func pollCadence(for providerID: ProviderID) -> PollCadence {
        let chosen = schedulerChosenInterval
        return PollCadence(
            chosenInterval: chosen,
            effectiveInterval: scheduler.effectiveInterval(forProvider: providerID, chosen: chosen),
            accountCount: scheduler.accountCount(for: providerID)
        )
    }

    /// KTD2: spend controls keep working while a CLI lane drains; only a spend fetch
    /// already in flight coalesces the click.
    public func refreshAPISpendOnly() async {
        if apiSpendInFlight { return }
        apiSpendInFlight = true
        apiSpendUserRefreshDepth += 1
        recomputeRefreshing()
        defer {
            apiSpendInFlight = false
            apiSpendUserRefreshDepth -= 1
            recomputeRefreshing()
        }
        await refreshAPISpend()
    }

    func refreshPollCadences() {
        var next: [ProviderID: PollCadence] = [:]
        for providerID in registeredProviderOrder {
            next[providerID] = pollCadence(for: providerID)
        }
        if pollCadences != next { pollCadences = next }
    }

    private func recomputeRefreshing() {
        let next = userWorkPending || apiSpendUserRefreshDepth > 0
        if isRefreshing != next { isRefreshing = next }
    }

    private func refreshAPISpend(exportAfter: Bool = true) async {
        let spendPeriod = preferences.apiSpendPeriod
        let spendResults = await withTaskGroup(of: (ProviderID, APISpendSnapshot).self) { group in
            for provider in apiSpendProviders {
                guard let surface = UsageSurface.api(for: provider.id),
                      enabledSurfaces.contains(surface)
                else { continue }
                group.addTask { (provider.id, await provider.fetchSpend(period: spendPeriod)) }
            }
            var acc: [(ProviderID, APISpendSnapshot)] = []
            for await pair in group { acc.append(pair) }
            return acc
        }
        for (id, fresh) in spendResults { mergeSpend(id: id, fresh: fresh) }
        if exportAfter {
            exportWidgetSnapshot()
            exportPhoneSyncSnapshot()
        }
    }

    /// Continuity (KTD7): a failure with no fresh windows keeps the prior windows
    /// shown dimmed rather than blanking the card; it never touches another account.
    private func mergeResult(
        key: AccountKey,
        result: UsageProviderFetchResult,
        notifiesSetup: Bool,
        attachmentGeneration: UInt64?
    ) -> Bool {
        let isCapabilityFailure = result.capability.map { $0 != .available } == true
        if isCapabilityFailure {
            // A provider-wide discovery failure says nothing about this account. Keep a
            // pending row neutral and preserve any prior usage or login/trust setup state.
            return acceptsResult(for: key, attachmentGeneration: attachmentGeneration)
        }
        return merge(key: key, fresh: result.snapshot, notifiesSetup: notifiesSetup,
                     attachmentGeneration: attachmentGeneration)
    }

    private func acceptsResult(for key: AccountKey, attachmentGeneration: UInt64?) -> Bool {
        accounts(for: key.providerID).contains(where: { $0.key == key })
            && !removingAccounts.contains(key)
            && attachmentGeneration == attachmentGenerations[key, default: 0]
    }

    @discardableResult
    private func merge(
        key: AccountKey,
        fresh: UsageSnapshot,
        notifiesSetup: Bool = true,
        attachmentGeneration: UInt64?
    ) -> Bool {
        // The account may have been removed — or its built-in row stop-tracked and
        // resumed, reusing the key — while its fetch was in flight. A late result from
        // a detached instance must not resurrect or overwrite the row.
        guard acceptsResult(for: key, attachmentGeneration: attachmentGeneration) else { return false }
        let next = UsageContinuityPolicy.mergedSnapshot(
            fresh,
            with: snapshots[key],
            at: now()
        )
        recordSignOutEdge(next, for: key)
        if next.freshness == .live {
            bankedResetAcknowledgements?.lower(for: key, currentCount: next.bankedResets)
        }
        // Skip the assignment when nothing changed so an unchanging state (e.g. a
        // provider that stays logged-out) doesn't invalidate observers every cycle.
        if snapshots[key] != next { snapshots[key] = next }
        updateContinuityCache(next, for: key)
        if notifiesSetup { setupCoordinator?.receive(next, for: key) }
        return true
    }

    /// KTD14 (2026-09-19 sign-in plan): merge is the one place the prior row and the
    /// merged one are both settled and capability failures have already short-circuited,
    /// so it is where the signed-in → signed-out edge is observed. A transient capture or
    /// an unrecognized surface says nothing about the login, so both leave the flag and
    /// the list alone — only a live reading re-arms the account.
    private func recordSignOutEdge(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard let signOutRecord, key.providerID == .claude else { return }
        switch snapshot.freshness {
        case .live:
            signOutRecord.noteSignedIn(key)
        case .stale(.providerSetup(.claudeLoginRequired)):
            signOutRecord.noteSignedOut(key)
        default:
            break
        }
    }

    private func updateContinuityCache(_ snapshot: UsageSnapshot, for key: AccountKey) {
        if case .stale(let reason) = snapshot.freshness, reason.isPermanent {
            continuityCache?.remove(for: key)
        } else if !snapshot.windows.isEmpty {
            continuityCache?.save(snapshot, for: key)
        } else {
            continuityCache?.remove(for: key)
        }
    }

    private func beginCapabilityRefresh(
        for providers: [any UsageProvider]
    ) -> [ProviderID: UInt64] {
        var cycle: [ProviderID: UInt64] = [:]
        for providerID in providers.filter(\.reportsProviderCapability).map(\.id).uniqued() {
            capabilityGenerations[providerID, default: 0] &+= 1
            let generation = capabilityGenerations[providerID] ?? 0
            cycle[providerID] = generation
            // Keep the last actionable verdict visible during later polls. Only the
            // first discovery has no prior result to preserve.
            if providerCapabilities[providerID]?.state == .unknown
                || providerCapabilities[providerID] == nil {
                providerCapabilities[providerID] = ProviderCapabilityStatus(
                    state: .discovering,
                    observedAt: now()
                )
            }
        }
        return cycle
    }

    private func applyCapability(
        _ state: ProviderCapabilityState,
        for providerID: ProviderID,
        generation: UInt64?
    ) {
        guard let generation, capabilityGenerations[providerID] == generation else { return }
        providerCapabilities[providerID] = ProviderCapabilityStatus(state: state, observedAt: now())
        switch state {
        case .inconclusive, .confirmedAbsent:
            setupCoordinator?.receiveCapabilityFailure(state, for: providerID)
        case .unknown, .discovering, .available:
            break
        }
    }

    private func mergeSpend(id: ProviderID, fresh: APISpendSnapshot) {
        let next: APISpendSnapshot
        if case .stale(let reason) = fresh.freshness,
           fresh.amount == nil,
           let prior = apiSpendSnapshots[id], prior.amount != nil {
            next = prior.markedStale(reason)
        } else {
            next = fresh
        }
        if apiSpendSnapshots[id] != next { apiSpendSnapshots[id] = next }
    }

    public func snapshot(for key: AccountKey) -> UsageSnapshot {
        snapshots[key] ?? .pending(for: key.providerID)
    }

    /// Primary-account snapshot — the single-account view compact surfaces use.
    public func snapshot(for id: ProviderID) -> UsageSnapshot {
        snapshot(for: primaryKey(for: id))
    }

    public func appDisplaySnapshot(for key: AccountKey) -> UsageSnapshot {
        weeklyFirst(
            filterCodexSparkCounters(
                from: snapshot(for: key),
                shouldShow: preferences.showCodexSparkCountersInApp
            )
        )
    }

    public func appDisplaySnapshot(for id: ProviderID) -> UsageSnapshot {
        appDisplaySnapshot(for: primaryKey(for: id))
    }

    private func primaryKey(for id: ProviderID) -> AccountKey {
        AccountKey(providerID: id, accountID: primaryAccount(for: id)?.id ?? .primary)
    }

    /// Popover display order matches the widgets: weekly leads, 5-hour second, unknown
    /// windows keep their provider-given order after (providers emit 5-hour first). The rule
    /// lives on `UsageSnapshot.weeklyFirst()` so the Settings specimen renders the same order.
    private func weeklyFirst(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        snapshot.weeklyFirst()
    }

    public func apiSpendSnapshot(for id: ProviderID) -> APISpendSnapshot {
        apiSpendSnapshots[id] ?? .pending(
            providerID: id,
            displayName: apiSpendDisplayNames[id] ?? id.raw,
            periodLabel: preferences.apiSpendPeriod.label
        )
    }

    func exportWidgetSnapshot(generatedAt: Date = .now) {
        guard let widgetExporter else { return }
        widgetExporter.export(widgetSnapshot(widgetsEnabled: preferences.widgetsEnabled, generatedAt: generatedAt))
    }

    func exportPhoneSyncSnapshot(generatedAt: Date = .now) {
        guard let phoneSyncExporter else { return }
        phoneSyncExporter.export(widgetSnapshot(widgetsEnabled: preferences.syncToIPhoneEnabled, generatedAt: generatedAt))
    }

    /// Widgets mirror each provider's *primary* account — the widget schema and the
    /// iPhone mirror stay single-account (a glanceable tile can't rank five logins).
    private func widgetSnapshot(widgetsEnabled: Bool, generatedAt: Date) -> WidgetSnapshotEnvelope {
        let primarySnapshots = Dictionary(uniqueKeysWithValues: providerOrder.map { ($0, snapshot(for: $0)) })
        return WidgetSnapshotProjector.project(
            snapshots: primarySnapshots,
            providerOrder: providerOrder,
            displayNames: displayNames,
            renewalDate: { [preferences] in preferences.renewalDate(for: $0) },
            widgetsEnabled: widgetsEnabled,
            widgetProviderSelection: resolvedWidgetProviderSelection(),
            showsCodexSparkCounters: preferences.showCodexSparkCountersInWidgets,
            apiSpendSnapshots: apiSpendSnapshots,
            apiSpendProviderOrder: apiSpendProviderOrder,
            generatedAt: generatedAt
        )
    }

    private func resolvedWidgetProviderSelection() -> [ProviderID] {
        switch widgetPrioritySource.filtered(to: providerOrder) {
        case .auto:
            return Array(providerOrder.prefix(2))
        case .providers(let selected):
            return Array(providerOrder.lazy.filter(selected.contains).prefix(2))
        }
    }

    private func filterCodexSparkCounters(from snapshot: UsageSnapshot, shouldShow: Bool) -> UsageSnapshot {
        guard snapshot.providerID == .codex, !shouldShow else { return snapshot }
        return UsageSnapshot(
            providerID: snapshot.providerID,
            windows: snapshot.windows.filter { !$0.kind.isCodexSparkCounter },
            planLabel: snapshot.planLabel,
            accountEmail: snapshot.accountEmail,
            bankedResets: snapshot.bankedResets,
            codexResetCreditsField: snapshot.codexResetCreditsField,
            capturedAt: snapshot.capturedAt,
            freshness: snapshot.freshness
        )
    }

    /// The menu bar summary: selected percentage presentation in each provider's chosen
    /// window, tagged with provider identity. If Settings chooses a fill source, the
    /// number and severity follow that provider's window so the text, vessel fill, and
    /// color all mean the same thing. If no source is chosen, the text/tint use the
    /// lowest enabled balance while the vessel level stays decorative. Neutral until
    /// data exists.
    public var menuBarSummary: MenuBarSummary {
        // Any account stuck in a permanent failure (needs the user to re-auth) should
        // flag the glyph even when there is no live number to show yet.
        let needsAttention = providerOrder.contains { providerNeedsAttention($0) }
        let best = menuBarBestWindow()
        guard let best else { return MenuBarSummary.neutral.withAttention(needsAttention) }
        let pct = usagePercentageMode.roundedPercentage(for: best.window)
        let name = displayNames[best.id] ?? best.id.raw
        return MenuBarSummary(
            text: "\(pct)%",
            providerID: best.id,
            detail: "\(name) \(best.shortLabel)",
            isNeutral: false,
            percentageMode: usagePercentageMode,
            severity: best.window.severity,
            needsAttention: needsAttention
        )
    }

    private func menuBarBestWindow() -> ResolvedMenuBarWindow? {
        let candidateIDs: [ProviderID]
        switch menuBarFillSource {
        case .auto:
            candidateIDs = providerOrder
        case .providers(let selected):
            candidateIDs = providerOrder.filter { selected.contains($0) }
        }
        return candidateIDs.compactMap { menuBarWindow(for: $0) }
            .min { $0.window.percentRemaining < $1.window.percentRemaining }
    }

    public func providerMenuBarMeter(for id: ProviderID) -> MenuBarMeter {
        let needsAttention = providerNeedsAttention(id)
        guard let resolved = menuBarWindow(for: id) else {
            let name = displayNames[id] ?? id.raw
            let preferred = menuBarWindowSource(for: id)
            return MenuBarMeter(
                summary: MenuBarSummary(
                    text: "—",
                    providerID: id,
                    detail: "\(name) \(preferred.shortLabel)",
                    isNeutral: true,
                    needsAttention: needsAttention
                ),
                fill: nil
            )
        }

        let pct = usagePercentageMode.roundedPercentage(for: resolved.window)
        let name = displayNames[id] ?? id.raw
        return MenuBarMeter(
            summary: MenuBarSummary(
                text: "\(pct)%",
                providerID: id,
                detail: "\(name) \(resolved.shortLabel)",
                isNeutral: false,
                percentageMode: usagePercentageMode,
                severity: resolved.window.severity,
                needsAttention: needsAttention
            ),
            fill: usagePercentageMode.fraction(for: resolved.window)
        )
    }

    private func providerNeedsAttention(_ id: ProviderID) -> Bool {
        accounts(for: id).contains { account in
            if case .stale(let reason) = snapshots[account.key]?.freshness { return reason.isPermanent }
            return false
        }
    }

    /// Resolve one provider's preferred window. If the provider temporarily stops
    /// reporting that window, use the other supported window while retaining the saved
    /// preference so it resumes automatically when the data returns.
    private func menuBarWindow(for id: ProviderID) -> ResolvedMenuBarWindow? {
        guard providerOrder.contains(id) else { return nil }
        let snapshot = snapshot(for: id)
        guard snapshot.freshness != .pending else { return nil }

        let preferred = menuBarWindowSource(for: id)
        let candidates = [preferred] + MenuBarWindowSource.allCases.filter { $0 != preferred }
        for source in candidates {
            if let window = snapshot.windows.first(where: { $0.kind == source.kind }) {
                return ResolvedMenuBarWindow(id: id, window: window, kind: window.kind)
            }
        }
        guard let window = snapshot.windows.min(by: { $0.percentRemaining < $1.percentRemaining }) else {
            return nil
        }
        return ResolvedMenuBarWindow(id: id, window: window, kind: window.kind)
    }

}

private extension Array where Element: Hashable {
    /// Order-preserving de-dupe for provider and account identity lists.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Scheduler host (KTD1)

extension UsageStore: AccountProbeSchedulerHost {
    var schedulerNow: Date { now() }

    var schedulerChosenInterval: TimeInterval {
        LaneSchedule.chosenInterval(minutes: preferences.pollIntervalMinutes)
    }

    func schedulerProvider(for key: AccountKey) -> (any UsageProvider)? {
        providers.first(where: { $0.accountKey == key })
    }

    func schedulerIsEligible(_ key: AccountKey) -> Bool {
        guard accounts(for: key.providerID).contains(where: { $0.key == key }),
              !removingAccounts.contains(key),
              let surface = UsageSurface.subscription(for: key.providerID)
        else { return false }
        return enabledSurfaces.contains(surface)
    }

    func schedulerIsPrimary(_ key: AccountKey) -> Bool {
        primaryAccount(for: key.providerID)?.key == key
    }

    func schedulerFreshness(for key: AccountKey) -> Freshness? {
        snapshots[key]?.freshness
    }

    /// R2M3 per account: the earliest live reset deadline on this account's own windows
    /// later than `reference` (its last attempt). `.unavailable` rows are excluded — their
    /// retained deadline is no longer evidence of anything on screen.
    func schedulerResetDeadline(for key: AccountKey, after reference: Date) -> Date? {
        snapshots[key]?.windows
            .filter { !$0.freshness.isUnavailable }
            .compactMap(\.resetSchedule.deadline)
            .filter { $0 > reference }
            .min()
    }

    func schedulerAttachmentGeneration(for key: AccountKey) -> UInt64 {
        attachmentGenerations[key] ?? 0
    }

    func schedulerBeginCapabilityRefresh(for providers: [any UsageProvider]) -> [ProviderID: UInt64] {
        beginCapabilityRefresh(for: providers)
    }

    func schedulerApplyCapability(_ state: ProviderCapabilityState, for providerID: ProviderID, generation: UInt64?) {
        applyCapability(state, for: providerID, generation: generation)
    }

    func schedulerMerge(key: AccountKey, result: UsageProviderFetchResult, attachmentGeneration: UInt64) -> Bool {
        let notifiesSetup = result.capability == nil || result.capability == .available
        let accepted = mergeResult(
            key: key, result: result, notifiesSetup: notifiesSetup, attachmentGeneration: attachmentGeneration
        )
        // KTD9 / R19: compact surfaces mirror the primary, so its merge exports at once
        // instead of waiting for every extra in the lane. A full refresh exports once at
        // its end instead.
        if accepted, fullRefreshDepth == 0, primaryKey(for: key.providerID) == key {
            exportWidgetSnapshot()
            exportPhoneSyncSnapshot()
        }
        return accepted
    }

    func schedulerLaneDidGoIdle(_ lane: ProviderPollingLane) {
        refreshPollCadences()
        // KTD6: the next sleep is computed from the pass's new due times.
        engine?.rephase()
    }

    func schedulerUserWorkDidChange(hasPending: Bool) {
        userWorkPending = hasPending
        recomputeRefreshing()
    }
}
