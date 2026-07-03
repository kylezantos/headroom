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
    private var engine: PollingEngine?

    public init(
        providers: [any UsageProvider],
        apiSpendProviders: [any APISpendProvider] = [],
        preferences: Preferences = Preferences(),
        widgetExporter: (any WidgetSnapshotExporting)? = nil
    ) {
        self.providers = providers
        self.apiSpendProviders = apiSpendProviders
        self.preferences = preferences
        self.widgetExporter = widgetExporter
        self.displayNames = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.displayName) })
        self.apiSpendDisplayNames = Dictionary(uniqueKeysWithValues: apiSpendProviders.map { ($0.id, $0.displayName) })
        self.snapshots = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, .pending(for: $0.id)) })
        self.apiSpendSnapshots = Dictionary(uniqueKeysWithValues: apiSpendProviders.map {
            ($0.id, .pending(providerID: $0.id, displayName: $0.displayName, periodLabel: preferences.apiSpendPeriod.label))
        })
        self.showMenuBarPercentage = preferences.showMenuBarPercentage
        self.menuBarFillSource = preferences.menuBarFillSource
    }

    public var providerOrder: [ProviderID] {
        providers.map(\.id).filter { preferences.isSurfaceEnabled(subscriptionSurface(for: $0)) }
    }

    public var apiSpendProviderOrder: [ProviderID] {
        apiSpendProviders.map(\.id).filter { preferences.isSurfaceEnabled(apiSurface(for: $0)) }
    }

    /// Begin polling: an immediate refresh, then the interval loop. Idempotent — a
    /// second call (e.g. the popover re-appearing) does not restart the loop or
    /// reset the cadence.
    public func start() async {
        guard engine == nil else { return }
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

    /// How full to draw the menu-bar vessel, 0…1: the selected provider's *weekly*
    /// window `percentRemaining`. Reads from the last-known windows regardless of
    /// freshness, so a transient failure doesn't make the pill jump. Nil when the
    /// source is `.none` or that provider has no weekly window yet — the label then
    /// falls back to a static decorative fill.
    public var menuBarFill: Double? {
        guard let id = menuBarFillSource.providerID,
              let weekly = snapshots[id]?.windows.first(where: { $0.kind == .weekly })
        else { return nil }
        return weekly.percentRemaining / 100
    }

    public var widgetsEnabled: Bool { preferences.widgetsEnabled }

    public func setWidgetsEnabled(_ enabled: Bool) {
        preferences.widgetsEnabled = enabled
        exportWidgetSnapshot()
    }

    public func isSurfaceEnabled(_ surface: UsageSurface) -> Bool {
        preferences.isSurfaceEnabled(surface)
    }

    public func setSurfaceEnabled(_ enabled: Bool, for surface: UsageSurface) {
        preferences.setSurfaceEnabled(enabled, for: surface)
        if surface.isSubscription {
            exportWidgetSnapshot()
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
        let results = await withTaskGroup(of: (ProviderID, UsageSnapshot).self) { group in
            for provider in providers {
                guard preferences.isSurfaceEnabled(subscriptionSurface(for: provider.id)) else { continue }
                group.addTask { (provider.id, await provider.fetchSnapshot()) }
            }
            var acc: [(ProviderID, UsageSnapshot)] = []
            for await pair in group { acc.append(pair) }
            return acc
        }
        for (id, fresh) in results { merge(id: id, fresh: fresh) }
        exportWidgetSnapshot()

        let spendPeriod = preferences.apiSpendPeriod
        let spendResults = await withTaskGroup(of: (ProviderID, APISpendSnapshot).self) { group in
            for provider in apiSpendProviders {
                guard preferences.isSurfaceEnabled(apiSurface(for: provider.id)) else { continue }
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

    public func apiSpendSnapshot(for id: ProviderID) -> APISpendSnapshot {
        apiSpendSnapshots[id] ?? .pending(
            providerID: id,
            displayName: apiSpendDisplayNames[id] ?? id.raw,
            periodLabel: preferences.apiSpendPeriod.label
        )
    }

    private func exportWidgetSnapshot(generatedAt: Date = .now) {
        guard let widgetExporter else { return }
        let envelope = WidgetSnapshotProjector.project(
            snapshots: snapshots,
            providerOrder: providerOrder,
            displayNames: displayNames,
            renewalDate: { [preferences] in preferences.renewalDate(for: $0) },
            widgetsEnabled: preferences.widgetsEnabled,
            generatedAt: generatedAt
        )
        widgetExporter.export(envelope)
    }

    /// The menu bar summary: the lowest `percentRemaining` among all live windows,
    /// tagged with its provider+window identity. Neutral until any live data exists.
    public var menuBarSummary: MenuBarSummary {
        // A provider stuck in a permanent failure (needs the user to re-auth) should
        // flag the glyph even when there is no live number to show yet.
        let needsAttention = providerOrder.contains { id in
            if case .stale(let reason) = snapshots[id]?.freshness { return reason.isPermanent }
            return false
        }
        var best: (id: ProviderID, window: UsageWindow)?
        for id in providerOrder {
            guard let snap = snapshots[id], snap.freshness == .live else { continue }
            for window in snap.windows {
                if best == nil || window.percentRemaining < best!.window.percentRemaining {
                    best = (id, window)
                }
            }
        }
        guard let best else { return MenuBarSummary.neutral.withAttention(needsAttention) }
        let pct = Int(best.window.percentRemaining.rounded())
        let name = displayNames[best.id] ?? best.id.raw
        return MenuBarSummary(
            text: "\(pct)%",
            providerID: best.id,
            detail: "\(name) \(best.window.kind.shortLabel)",
            isNeutral: false,
            severity: best.window.severity,
            needsAttention: needsAttention
        )
    }

    private func subscriptionSurface(for id: ProviderID) -> UsageSurface {
        id == .claude ? .claudeSubscription : .codexSubscription
    }

    private func apiSurface(for id: ProviderID) -> UsageSurface {
        id == .claude ? .anthropicAPI : .openAIAPI
    }
}
