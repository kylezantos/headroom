import Foundation
import Observation

/// Compact, self-contained menu bar summary (R5): the tightest live window plus its
/// provider identity, so the bar means something without opening the popover.
public struct MenuBarSummary: Sendable, Equatable {
    public let text: String            // e.g. "12%"
    public let providerID: ProviderID? // which provider the number is about
    public let detail: String?         // e.g. "Claude 5h"
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
        severity: UsageSeverity = .healthy,
        needsAttention: Bool = false
    ) {
        self.text = text
        self.providerID = providerID
        self.detail = detail
        self.isNeutral = isNeutral
        self.severity = severity
        self.needsAttention = needsAttention
    }

    public static let neutral = MenuBarSummary(text: "—", providerID: nil, detail: nil, isNeutral: true)

    /// Copy of this summary with the menu-bar attention flag set — lets the neutral
    /// (no-live-data) case still surface a needs-reauth provider.
    func withAttention(_ flag: Bool) -> MenuBarSummary {
        MenuBarSummary(text: text, providerID: providerID, detail: detail,
                       isNeutral: isNeutral, severity: severity, needsAttention: flag)
    }
}

/// One compact status unit for the menu bar. Single-provider modes render one meter;
/// `Both` renders one per enabled provider so Claude and Codex can be scanned together.
public struct MenuBarMeter: Sendable, Equatable {
    public let summary: MenuBarSummary
    /// 0...1 fill for the vessel, or nil for the static decorative level.
    public let fill: Double?

    public init(summary: MenuBarSummary, fill: Double?) {
        self.summary = summary
        self.fill = fill
    }
}

/// The observable view model the UI and menu bar label bind to (U6). `@MainActor`
/// and `@Observable`: snapshots are published on the main actor; providers are
/// fetched concurrently off-main (KTD10). Per-provider isolation — one provider's
/// failure updates only its own snapshot (KTD7).
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshots: [ProviderID: UsageSnapshot]
    public private(set) var apiSpendSnapshots: [ProviderID: APISpendSnapshot]
    public private(set) var showMenuBarPercentage: Bool
    public private(set) var menuBarFillSource: MenuBarFillSource
    public private(set) var showCodexSparkCountersInApp: Bool
    public private(set) var showCodexSparkCountersInWidgets: Bool
    public private(set) var enabledSurfaces: Set<UsageSurface>
    public let displayNames: [ProviderID: String]
    public let apiSpendDisplayNames: [ProviderID: String]

    /// True while a fetch cycle is in flight. Doubles as the popover's "Refreshing…"
    /// signal (UI-02): a manual refresh spawns a 20–30s Claude CLI session, so the UI
    /// must show progress or the button reads as broken. Also the reentrancy guard that
    /// coalesces overlapping triggers into one cycle.
    public private(set) var isRefreshing = false

    private let providers: [any UsageProvider]
    private let apiSpendProviders: [any APISpendProvider]
    private let preferences: Preferences
    private let widgetExporter: (any WidgetSnapshotExporting)?
    private let phoneSyncExporter: (any WidgetSnapshotExporting)?
    private var engine: PollingEngine?
    private var isStarting = false

    public init(
        providers: [any UsageProvider],
        apiSpendProviders: [any APISpendProvider] = [],
        preferences: Preferences = Preferences(),
        widgetExporter: (any WidgetSnapshotExporting)? = nil,
        phoneSyncExporter: (any WidgetSnapshotExporting)? = nil
    ) {
        self.providers = providers
        self.apiSpendProviders = apiSpendProviders
        self.preferences = preferences
        self.widgetExporter = widgetExporter
        self.phoneSyncExporter = phoneSyncExporter
        self.displayNames = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.displayName) })
        self.apiSpendDisplayNames = Dictionary(uniqueKeysWithValues: apiSpendProviders.map { ($0.id, $0.displayName) })
        self.snapshots = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, .pending(for: $0.id)) })
        self.apiSpendSnapshots = Dictionary(uniqueKeysWithValues: apiSpendProviders.map {
            ($0.id, .pending(providerID: $0.id, displayName: $0.displayName, periodLabel: preferences.apiSpendPeriod.label))
        })
        self.showMenuBarPercentage = preferences.showMenuBarPercentage
        self.menuBarFillSource = preferences.menuBarFillSource
        self.showCodexSparkCountersInApp = preferences.showCodexSparkCountersInApp
        self.showCodexSparkCountersInWidgets = preferences.showCodexSparkCountersInWidgets
        self.enabledSurfaces = Set(UsageSurface.allCases.filter { preferences.isSurfaceEnabled($0) })
    }

    public var providerOrder: [ProviderID] {
        providers.map(\.id).filter { enabledSurfaces.contains(subscriptionSurface(for: $0)) }
    }

    public var apiSpendProviderOrder: [ProviderID] {
        apiSpendProviders.map(\.id).filter { enabledSurfaces.contains(apiSurface(for: $0)) }
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
            tick: { [weak self] in await self?.refreshAll() }
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

    public func setMenuBarFillSource(_ source: MenuBarFillSource) {
        preferences.menuBarFillSource = source
        menuBarFillSource = source
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

    /// How full to draw the menu-bar vessel, 0…1: the selected provider's *weekly*
    /// window `percentRemaining`. Reads from the last-known windows regardless of
    /// freshness, so a transient failure doesn't make the pill jump. Nil when the
    /// source is `.none` or that provider has no weekly window yet — the label then
    /// falls back to a static decorative fill.
    public var menuBarFill: Double? {
        guard let id = menuBarFillSource.providerID,
              let weekly = weeklyWindow(for: id)
        else { return nil }
        return weekly.window.percentRemaining / 100
    }

    /// Render-ready menu bar meters. In `Both` mode each enabled provider gets its own
    /// vessel/percentage pair; other modes keep the existing single compact summary.
    public var menuBarMeters: [MenuBarMeter] {
        guard menuBarFillSource == .both else {
            return [MenuBarMeter(summary: menuBarSummary, fill: menuBarFill)]
        }

        let ids = [ProviderID.claude, .codex].filter { providerOrder.contains($0) }
        let meters = ids.map { providerMenuBarMeter(for: $0) }
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
        if surface.isSubscription {
            exportWidgetSnapshot()
            exportPhoneSyncSnapshot()
        }
    }

    public var apiSpendPeriod: APISpendPeriod {
        preferences.apiSpendPeriod
    }

    public func setAPISpendPeriod(_ period: APISpendPeriod) {
        preferences.apiSpendPeriod = period
    }

    /// Fetch every provider concurrently and merge results with continuity. Guarded
    /// so overlapping triggers (a timer tick during a popover-open `refreshNow()`)
    /// coalesce into one in-flight cycle instead of racing duplicate fetches.
    public func refreshAll() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshSubscriptions()
        await refreshAPISpend()
    }

    public func refreshAPISpendOnly() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshAPISpend()
    }

    private func refreshSubscriptions() async {
        let results = await withTaskGroup(of: (ProviderID, UsageSnapshot).self) { group in
            for provider in providers {
                guard enabledSurfaces.contains(subscriptionSurface(for: provider.id)) else { continue }
                group.addTask { (provider.id, await provider.fetchSnapshot()) }
            }
            var acc: [(ProviderID, UsageSnapshot)] = []
            for await pair in group { acc.append(pair) }
            return acc
        }
        for (id, fresh) in results { merge(id: id, fresh: fresh) }
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    private func refreshAPISpend() async {
        let spendPeriod = preferences.apiSpendPeriod
        let spendResults = await withTaskGroup(of: (ProviderID, APISpendSnapshot).self) { group in
            for provider in apiSpendProviders {
                guard enabledSurfaces.contains(apiSurface(for: provider.id)) else { continue }
                group.addTask { (provider.id, await provider.fetchSpend(period: spendPeriod)) }
            }
            var acc: [(ProviderID, APISpendSnapshot)] = []
            for await pair in group { acc.append(pair) }
            return acc
        }
        for (id, fresh) in spendResults { mergeSpend(id: id, fresh: fresh) }
    }

    /// Continuity (KTD7): a failure with no fresh windows keeps the prior windows
    /// shown dimmed rather than blanking the card; it never touches another provider.
    private func merge(id: ProviderID, fresh: UsageSnapshot) {
        let next: UsageSnapshot
        if case .stale(let reason) = fresh.freshness,
           fresh.windows.isEmpty,
           let prior = snapshots[id], !prior.windows.isEmpty {
            next = prior.markedStale(reason)
        } else {
            next = fresh
        }
        // Skip the assignment when nothing changed so an unchanging state (e.g. a
        // provider that stays logged-out) doesn't invalidate observers every cycle.
        if snapshots[id] != next { snapshots[id] = next }
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

    public func snapshot(for id: ProviderID) -> UsageSnapshot {
        snapshots[id] ?? .pending(for: id)
    }

    public func appDisplaySnapshot(for id: ProviderID) -> UsageSnapshot {
        filterCodexSparkCounters(
            from: snapshot(for: id),
            shouldShow: preferences.showCodexSparkCountersInApp
        )
    }

    public func apiSpendSnapshot(for id: ProviderID) -> APISpendSnapshot {
        apiSpendSnapshots[id] ?? .pending(
            providerID: id,
            displayName: apiSpendDisplayNames[id] ?? id.raw,
            periodLabel: preferences.apiSpendPeriod.label
        )
    }

    private func exportWidgetSnapshot(generatedAt: Date = .now) {
        guard let widgetExporter else { return }
        widgetExporter.export(widgetSnapshot(widgetsEnabled: preferences.widgetsEnabled, generatedAt: generatedAt))
    }

    private func exportPhoneSyncSnapshot(generatedAt: Date = .now) {
        guard let phoneSyncExporter else { return }
        phoneSyncExporter.export(widgetSnapshot(widgetsEnabled: preferences.syncToIPhoneEnabled, generatedAt: generatedAt))
    }

    private func widgetSnapshot(widgetsEnabled: Bool, generatedAt: Date) -> WidgetSnapshotEnvelope {
        WidgetSnapshotProjector.project(
            snapshots: snapshots,
            providerOrder: providerOrder,
            displayNames: displayNames,
            renewalDate: { [preferences] in preferences.renewalDate(for: $0) },
            widgetsEnabled: widgetsEnabled,
            showsCodexSparkCounters: preferences.showCodexSparkCountersInWidgets,
            generatedAt: generatedAt
        )
    }

    private func filterCodexSparkCounters(from snapshot: UsageSnapshot, shouldShow: Bool) -> UsageSnapshot {
        guard snapshot.providerID == .codex, !shouldShow else { return snapshot }
        return UsageSnapshot(
            providerID: snapshot.providerID,
            windows: snapshot.windows.filter { !$0.kind.isCodexSparkCounter },
            planLabel: snapshot.planLabel,
            capturedAt: snapshot.capturedAt,
            freshness: snapshot.freshness
        )
    }

    /// The menu bar summary: weekly allotment remaining, tagged with provider identity.
    /// If Settings chooses a fill source, the number and severity follow that provider's
    /// weekly window so the text, vessel fill, and color all mean the same thing. If no
    /// source is chosen, the text/tint use the lowest enabled weekly balance while the
    /// vessel level stays decorative. Neutral until weekly data exists.
    public var menuBarSummary: MenuBarSummary {
        // A provider stuck in a permanent failure (needs the user to re-auth) should
        // flag the glyph even when there is no live number to show yet.
        let needsAttention = providerOrder.contains { id in
            if case .stale(let reason) = snapshots[id]?.freshness { return reason.isPermanent }
            return false
        }
        let best = menuBarWeeklyWindow()
        guard let best else { return MenuBarSummary.neutral.withAttention(needsAttention) }
        let pct = Int(best.window.percentRemaining.rounded())
        let name = displayNames[best.id] ?? best.id.raw
        return MenuBarSummary(
            text: "\(pct)%",
            providerID: best.id,
            detail: "\(name) weekly",
            isNeutral: false,
            severity: best.window.severity,
            needsAttention: needsAttention
        )
    }

    private func menuBarWeeklyWindow() -> (id: ProviderID, window: UsageWindow)? {
        if let id = menuBarFillSource.providerID {
            return weeklyWindow(for: id)
        }
        return providerOrder.compactMap { weeklyWindow(for: $0) }
            .min { $0.window.percentRemaining < $1.window.percentRemaining }
    }

    private func providerMenuBarMeter(for id: ProviderID) -> MenuBarMeter {
        let needsAttention = providerNeedsAttention(id)
        guard let weekly = weeklyWindow(for: id) else {
            let name = displayNames[id] ?? id.raw
            return MenuBarMeter(
                summary: MenuBarSummary(
                    text: "—",
                    providerID: id,
                    detail: "\(name) weekly",
                    isNeutral: true,
                    needsAttention: needsAttention
                ),
                fill: nil
            )
        }

        let pct = Int(weekly.window.percentRemaining.rounded())
        let name = displayNames[id] ?? id.raw
        return MenuBarMeter(
            summary: MenuBarSummary(
                text: "\(pct)%",
                providerID: id,
                detail: "\(name) weekly",
                isNeutral: false,
                severity: weekly.window.severity,
                needsAttention: needsAttention
            ),
            fill: weekly.window.percentRemaining / 100
        )
    }

    private func providerNeedsAttention(_ id: ProviderID) -> Bool {
        if case .stale(let reason) = snapshots[id]?.freshness { return reason.isPermanent }
        return false
    }

    private func weeklyWindow(for id: ProviderID) -> (id: ProviderID, window: UsageWindow)? {
        guard providerOrder.contains(id),
              snapshots[id]?.freshness != .pending,
              let window = snapshots[id]?.windows.first(where: { $0.kind == .weekly })
        else { return nil }
        return (id, window)
    }

    private func subscriptionSurface(for id: ProviderID) -> UsageSurface {
        id == .claude ? .claudeSubscription : .codexSubscription
    }

    private func apiSurface(for id: ProviderID) -> UsageSurface {
        id == .claude ? .anthropicAPI : .openAIAPI
    }
}
