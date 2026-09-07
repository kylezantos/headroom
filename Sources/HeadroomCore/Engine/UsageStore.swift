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
/// carry up to `AccountRegistry.maxPerProvider` signed-in accounts. The menu bar and
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
    public private(set) var menuBarWindowSources: [ProviderID: MenuBarWindowSource]
    public private(set) var showCodexSparkCountersInApp: Bool
    public private(set) var showCodexSparkCountersInWidgets: Bool
    public private(set) var enabledSurfaces: Set<UsageSurface>
    public private(set) var providerCapabilities: [ProviderID: ProviderCapabilityStatus]
    public internal(set) var accountRemovalStates: [AccountKey: AccountRemovalState] = [:]
    public let displayNames: [ProviderID: String]
    public let apiSpendDisplayNames: [ProviderID: String]

    /// True while a fetch cycle is in flight. Doubles as the popover's "Refreshing…"
    /// signal (UI-02): a manual refresh spawns a 20–30s Claude CLI session, so the UI
    /// must show progress or the button reads as broken. Also the reentrancy guard that
    /// coalesces overlapping triggers into one cycle.
    public private(set) var isRefreshing = false

    var providers: [any UsageProvider]
    private let apiSpendProviders: [any APISpendProvider]
    private let preferences: Preferences
    let accountRegistry: AccountRegistry?
    let accountStorage: any AccountStorageManaging
    let continuityCache: (any UsageContinuityCaching)?
    private let now: @Sendable () -> Date
    /// Counts timer-driven cycles for the not-signed-in poll backoff.
    private var timerCycleCount = 0
    /// Builds the concrete provider for a newly added account. Lives in the composition
    /// root (R13) and is injected so the store never names concrete provider types.
    let providerFactory: (@MainActor (ProviderAccount) -> any UsageProvider)?
    let widgetExporter: (any WidgetSnapshotExporting)?
    let phoneSyncExporter: (any WidgetSnapshotExporting)?
    private var engine: PollingEngine?
    private var isStarting = false
    @ObservationIgnored var pendingAccountRefreshes: Set<AccountKey> = []
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
        self.menuBarWindowSources = Dictionary(uniqueKeysWithValues: registeredProviderIDs.map {
            ($0, preferences.menuBarWindowSource(for: $0))
        })
        self.showCodexSparkCountersInApp = preferences.showCodexSparkCountersInApp
        self.showCodexSparkCountersInWidgets = preferences.showCodexSparkCountersInWidgets
        self.enabledSurfaces = Set(UsageSurface.allCases.filter { preferences.isSurfaceEnabled($0) })
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
        let engine = PollingEngine(
            intervalMinutes: { [preferences] in preferences.pollIntervalMinutes },
            tick: { [weak self] in await self?.refreshAll(source: .timer) }
        )
        engine.start()
        self.engine = engine
    }

    /// Immediate off-cadence refresh — called on popover open (KTD9).
    public func refreshNow() {
        Task { await refreshAll() }
    }

    /// Refresh only API spend providers. Settings uses this for spend-only controls so
    /// a checkbox click doesn't spawn the expensive Claude subscription CLI probe.
    public func refreshAPISpendNow() {
        Task { await refreshAPISpendOnly() }
    }

    /// Restart the loop so a changed poll interval takes effect now (R14).
    public func reschedulePolling() { engine?.reschedule() }

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
        let filtered = source.filtered(to: registeredProviderOrder)
        preferences.menuBarFillSource = filtered
        menuBarFillSource = filtered
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
        guard case .providers(let selected) = menuBarFillSource else {
            return [MenuBarMeter(summary: menuBarSummary, fill: menuBarFill)]
        }

        let meters = providerOrder.filter { selected.contains($0) }.map { providerMenuBarMeter(for: $0) }
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
        } else {
            enabledSurfaces.remove(surface)
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

    /// What triggered a refresh cycle. Timer ticks back off never-signed-in extra
    /// accounts; user-initiated refreshes always probe everything.
    private enum RefreshSource { case manual, timer }

    /// Fetch every provider concurrently and merge results with continuity. Guarded
    /// so overlapping triggers (a timer tick during a popover-open `refreshNow()`)
    /// coalesce into one in-flight cycle instead of racing duplicate fetches.
    public func refreshAll() async {
        await refreshAll(source: .manual)
    }

    private func refreshAll(source: RefreshSource) async {
        if isRefreshing { return }
        isRefreshing = true
        if source == .timer { timerCycleCount += 1 }
        await refreshSubscriptions(source: source, exportAfter: false)
        await refreshAPISpend(exportAfter: false)
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
        await drainPendingAccountRefreshes()
        isRefreshing = false
    }

    /// Refresh a single account — the setup-session retry path, so watching one new
    /// sign-in never fans out into a full fleet poll (each Claude account is a
    /// 20–30s CLI session; code-review finding).
    public func refreshAccountNow(_ key: AccountKey) {
        Task { await refreshAccount(key) }
    }

    func refreshAccount(_ key: AccountKey) async {
        if isRefreshing {
            pendingAccountRefreshes.insert(key)
            return
        }
        isRefreshing = true
        await fetchAccountIfEligible(key)
        await drainPendingAccountRefreshes()
        isRefreshing = false
    }

    public func refreshAPISpendOnly() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshAPISpend()
    }

    private func refreshSubscriptions(source: RefreshSource = .manual, exportAfter: Bool = true) async {
        let candidates = providers.filter { provider in
            guard let surface = UsageSurface.subscription(for: provider.id) else { return false }
            return enabledSurfaces.contains(surface) && !shouldSkipOnTimer(provider: provider, source: source)
        }
        let capabilityCycle = beginCapabilityRefresh(for: candidates)
        let fetchAttachments = Dictionary(
            candidates.map { ($0.accountKey, attachmentGenerations[$0.accountKey] ?? 0) },
            uniquingKeysWith: { first, _ in first }
        )
        let executableRefreshGeneration = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: (AccountKey, UsageProviderFetchResult).self,
            bufferingPolicy: .unbounded
        )
        var capabilityResults: [ProviderID: ProviderCapabilityState] = [:]
        await withTaskGroup(of: Void.self) { group in
            // Partition once from the immutable provider declaration. Each process-heavy
            // CLI gets its own keyed serial lane, while network work and other CLI lanes
            // remain concurrent with it.
            var serialLanes: [String: [any UsageProvider]] = [:]
            var concurrentProviders: [any UsageProvider] = []
            for provider in candidates {
                switch provider.pollingLane {
                case .concurrent:
                    concurrentProviders.append(provider)
                case .serial(let laneID):
                    serialLanes[laneID, default: []].append(provider)
                }
            }
            for lane in serialLanes.values {
                group.addTask {
                    await CLIExecutableRefreshContext.$generation.withValue(executableRefreshGeneration) {
                        for provider in lane {
                            continuation.yield((provider.accountKey, await provider.fetchResult()))
                        }
                    }
                }
            }
            for provider in concurrentProviders {
                group.addTask {
                    continuation.yield((provider.accountKey, await provider.fetchResult()))
                }
            }
            var iterator = stream.makeAsyncIterator()
            for _ in candidates {
                guard let (key, result) = await iterator.next() else { break }
                let notifiesSetup = result.capability == nil || result.capability == .available
                if mergeResult(key: key, result: result, notifiesSetup: notifiesSetup,
                               attachmentGeneration: fetchAttachments[key]),
                   let capability = result.capability {
                    // Serial CLI lanes are ordered observations. Keep the newest
                    // provider-wide result so a recovered later account can clear an
                    // earlier path miss from the same refresh cycle.
                    capabilityResults[key.providerID] = capability
                }
            }
            await group.waitForAll()
        }
        continuation.finish()
        for (providerID, capability) in capabilityResults {
            applyCapability(capability, for: providerID, generation: capabilityCycle[providerID])
        }
        if exportAfter {
            exportWidgetSnapshot()
            exportPhoneSyncSnapshot()
        }
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

    /// Timer backoff for never-signed-in non-primary accounts: each one costs a full
    /// 20–30s Claude CLI session per probe, so an abandoned Add Account must not burn
    /// a session every cycle forever. Probed every 4th timer cycle; manual refreshes
    /// and the per-account retry path always probe. Whichever row the user selected
    /// as primary is exempt so its compact surfaces recover promptly.
    private func shouldSkipOnTimer(provider: any UsageProvider, source: RefreshSource) -> Bool {
        guard source == .timer else { return false }
        return Self.shouldBackOffNeverSignedInAccount(
            provider.accountKey,
            primary: primaryAccount(for: provider.id)?.key,
            timerCycle: timerCycleCount,
            freshness: snapshots[provider.accountKey]?.freshness
        )
    }

    static func shouldBackOffNeverSignedInAccount(
        _ key: AccountKey,
        primary: AccountKey?,
        timerCycle: Int,
        freshness: Freshness?
    ) -> Bool {
        guard key != primary,
              case .stale(let reason) = freshness,
              isNeverSignedIn(reason)
        else { return false }
        return timerCycle % 4 != 0
    }

    private static func isNeverSignedIn(_ reason: FailureReason) -> Bool {
        if case .notLoggedIn = reason { return true }
        guard case .providerSetup(let outcome) = reason else { return false }
        return outcome.isNeverSignedIn
    }

    private func fetchAccountIfEligible(_ key: AccountKey) async {
        guard let provider = providers.first(where: { $0.accountKey == key }),
              accounts(for: key.providerID).contains(where: { $0.key == key }),
              !removingAccounts.contains(key),
              let surface = UsageSurface.subscription(for: key.providerID),
              enabledSurfaces.contains(surface)
        else { return }
        let capabilityCycle = beginCapabilityRefresh(for: [provider])
        let fetchAttachment = attachmentGenerations[key] ?? 0
        let executableRefreshGeneration = CLIExecutableRefreshContext.generation ?? UUID()
        let result = await CLIExecutableRefreshContext.$generation.withValue(executableRefreshGeneration) {
            await provider.fetchResult()
        }
        let notifiesSetup = result.capability == nil || result.capability == .available
        if mergeResult(key: key, result: result, notifiesSetup: notifiesSetup,
                       attachmentGeneration: fetchAttachment),
           let capability = result.capability {
            applyCapability(capability, for: key.providerID, generation: capabilityCycle[key.providerID])
        }
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    private func drainPendingAccountRefreshes() async {
        while !pendingAccountRefreshes.isEmpty {
            let keys = pendingAccountRefreshes.sorted {
                if $0.providerID.raw == $1.providerID.raw { return $0.accountID.raw < $1.accountID.raw }
                return $0.providerID.raw < $1.providerID.raw
            }
            pendingAccountRefreshes.removeAll()
            for key in keys { await fetchAccountIfEligible(key) }
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
        // Skip the assignment when nothing changed so an unchanging state (e.g. a
        // provider that stays logged-out) doesn't invalidate observers every cycle.
        if snapshots[key] != next { snapshots[key] = next }
        updateContinuityCache(next, for: key)
        if notifiesSetup { setupCoordinator?.receive(next, for: key) }
        return true
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
    /// windows keep their provider-given order after (providers emit 5-hour first).
    private func weeklyFirst(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        func rank(_ kind: WindowKind) -> Int {
            switch kind {
            case .weekly, .billingPeriod: return 0
            case .fiveHour: return 1
            case .other: return 2
            }
        }
        let ordered = snapshot.windows.enumerated()
            .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
        guard ordered != snapshot.windows else { return snapshot }
        return UsageSnapshot(
            providerID: snapshot.providerID,
            windows: ordered,
            planLabel: snapshot.planLabel,
            accountEmail: snapshot.accountEmail,
            capturedAt: snapshot.capturedAt,
            freshness: snapshot.freshness
        )
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
        switch menuBarFillSource.filtered(to: providerOrder) {
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

    private func providerMenuBarMeter(for id: ProviderID) -> MenuBarMeter {
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
