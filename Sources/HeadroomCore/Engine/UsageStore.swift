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
    /// KTD13: nil fill also means signed out or decorative; only pending means ghost.
    public let awaitingFirstReading: Bool
    /// U8 distinguishes a fresh first result from a stale result carrying retained windows.
    public let isLiveReading: Bool
    /// Explicit provider pills use this to avoid a first-reading print on Make Main.
    /// Automatic mode has one stable rendering identity and no single source account.
    public let sourceAccountKey: AccountKey?
    /// CA-MB2 (KTD7): the automatic summary is always marked, whatever the preference says.
    public let isAutomaticSummary: Bool

    public init(summary: MenuBarSummary, fill: Double?, awaitingFirstReading: Bool = false,
                isLiveReading: Bool = false, sourceAccountKey: AccountKey? = nil,
                isAutomaticSummary: Bool = false) {
        self.summary = summary
        self.fill = fill
        self.awaitingFirstReading = awaitingFirstReading
        self.isLiveReading = isLiveReading
        self.sourceAccountKey = sourceAccountKey
        self.isAutomaticSummary = isAutomaticSummary
    }

    /// CA-MB1: whose mark the pill carries. An explicit pill names its own provider; the
    /// automatic summary names the provider it follows right now; nil (no reading, or an
    /// empty selection) draws no mark.
    public var providerID: ProviderID? { summary.providerID }

    /// CA-MB1/CA-MB2: `explicitPillsMarked` is `UsageStore.menuBarShowsMarks`, the label's
    /// "shows marks" input.
    public func showsMark(explicitPillsMarked: Bool) -> Bool {
        providerID != nil && (isAutomaticSummary || explicitPillsMarked)
    }
}

private struct ResolvedMenuBarWindow {
    let id: ProviderID
    let window: UsageWindow
    let kind: WindowKind

    var menuBarTerm: String { kind.menuBarTerm }
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
    /// CA-MB1 (KTD7): the stored marks choice, nil until the user makes one. Read
    /// `menuBarShowsMarks` for the resolved value.
    public private(set) var menuBarMarksPreference: Bool?
    public private(set) var usagePercentageMode: UsagePercentageMode
    /// G1A: account-title ink, mirrored the same way `meterStyle` is. The menu bar and
    /// widgets carry no title ink; the phone's display block does (iPhone parity KTD11).
    public private(set) var accountTitleInk: AccountTitleInk
    /// Popover account layout, mirrored like `accountTitleInk` but Mac-only (KTD8).
    public private(set) var accountLayout: AccountLayout
    public private(set) var expandAccountsHorizontally: Bool
    public private(set) var useEmailAsAccountName: Bool
    public private(set) var meterStyle: MeterStyle
    public private(set) var menuBarFillSource: MenuBarFillSource
    private var savedMenuBarProviderOrder: [ProviderID]
    public private(set) var widgetPrioritySource: MenuBarFillSource
    public private(set) var menuBarWindowChoices: [ProviderID: MenuBarWindowChoice]
    private var chosenMenuBarWindowProviders: Set<ProviderID>
    public private(set) var showCodexSparkCountersInApp: Bool
    public private(set) var showCodexSparkCountersInWidgets: Bool
    /// Antigravity's "Show 5-hour windows" switch, one value for every surface.
    public private(set) var showsAntigravityFiveHourWindows: Bool
    /// Antigravity's optional Colab GPU credits mode (`Off` / `Replace Other · Weekly` / `Add`).
    public private(set) var antigravityGPUCreditsMode: AntigravityGPUCreditsMode
    public private(set) var antigravityColabTier: ColabComputeTier
    public private(set) var antigravityGPUCreditsRefillDay: Int?
    /// KTD14: notification preferences, mirrored so the Notifications pane edits through
    /// the store the way `meterStyle` does.
    public private(set) var useItUpRemindersEnabled: Bool
    public private(set) var bankedResetNotificationsEnabled: Bool
    public private(set) var reminderRules: [ReminderRule]
    public private(set) var reminderScope: Set<ReminderScope>
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
    /// Scheduler-wide clear time for run retention; visible work has its own hold clock.
    public private(set) var refreshingClearedAt: Date?
    public private(set) var visibleRefreshWork = VisibleRefreshWork()
    @ObservationIgnored private var visibleRefreshOperationDepth = 0
    /// A 0.5s visible hold plus 0.2s bookkeeping grace, distinct from ghost-wipe timing.
    private static let refreshRunRetentionDuration: TimeInterval = 0.7
    /// W4: the user-requested work behind `isRefreshing`, account by account. Nil once that
    /// work drains, even while a spend fetch keeps `isRefreshing` up.
    public private(set) var refreshProgress: RefreshProgress?
    /// Loading-language KTD1: retained through the entire spend tail and end hold.
    public private(set) var userRefreshRun: UserRefreshRun?
    public private(set) var fullRefreshInFlight = false
    @ObservationIgnored private var fullRefreshOperationDepth = 0
    /// KTD14.4 (iPhone parity U6): the one in-flight full refresh. Any second caller — the
    /// popover, the launch refresh, a phone's check-now request — awaits it instead of
    /// starting another probe round.
    @ObservationIgnored private var fullRefreshTask: Task<Void, Never>?
    /// When the in-flight full refresh started; nil while none runs.
    public private(set) var fullRefreshStartedAt: Date?
    /// KTD14.4: check-now's cooldown runs from the last completed full refresh, whatever
    /// started it.
    public private(set) var lastFullRefreshCompletedAt: Date?
    /// KTD14.3 / Decision 2: the Mac's recent check-now answers, echoed in every manifest.
    @ObservationIgnored var checkNowAnsweredRequests: [CompanionAnsweredRequest] = []
    /// U6: the check-now receipt follows the scheduler's user-progress callback.
    @ObservationIgnored var checkNowProgressObserver: (@MainActor () -> Void)?
    public private(set) var lastProbeEndTimes: [AccountKey: Date] = [:]
    public private(set) var apiSpendInFlightProviders: Set<ProviderID> = []
    @ObservationIgnored private var spendFetchDepths: [ProviderID: Int] = [:]
    @ObservationIgnored private var refreshRunRetentionTask: Task<Void, Never>?

    public var accountActionCheckingKeys: Set<AccountKey> {
        guard !fullRefreshInFlight, let run = userRefreshRun,
              !run.entries.values.contains(where: { $0.origin == .fullRefresh && $0.outcome == nil })
        else { return [] }
        return Set(run.entries.compactMap { key, entry in
            entry.origin == .accountAction && entry.outcome == nil ? key : nil
        })
    }
    /// Accounts whose probe is running right now, timer passes included (round-3 S2).
    public private(set) var probingAccounts: Set<AccountKey> = []
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
    /// Default-login plan KTD4: which account each row is bound to, and the accounts that
    /// left. Nil in demos, harnesses and most tests, which leaves every row as it was.
    let defaultLoginRecordStore: (any DefaultLoginRecordStoring)?
    /// The decoded records; nil when there is no store or its envelope is unreadable.
    @ObservationIgnored var defaultLoginState: DefaultLoginRecordsState?
    /// Default-login plan U5: the remembered accounts with a row, per provider, in stored
    /// order and hidden ones included, minus any a slot reads (KTD12). Observed, unlike
    /// the records, and reassigned only when it changes, so the steady per-reading
    /// commit does not invalidate views that read it.
    var rememberedAccountRows: [ProviderID: [RememberedAccountSummary]] = [:]
    /// Default-login plan U7 (KTD10): each visible remembered row's last reading, aged by
    /// `UsageContinuityPolicy.rememberedSnapshot` at launch, on each engine wake, when the
    /// popover opens and when the rows change, so no view body ages it. Keyed by the
    /// row's local id, which never collides with an engine key.
    var rememberedDisplaySnapshots: [AccountKey: UsageSnapshot] = [:]
    /// Default-login plan U10 (KTD11): per provider, the built-in key hidden by the
    /// one-row merge to the extra that shows it. Recomputed in the same turn as any gate
    /// change (`refreshDisplayMerge`) and reassigned only when it changes, so no view body
    /// rebuilds it. Empty for a setup with no merge.
    var displayMergeMaps: [ProviderID: [AccountKey: AccountKey]] = [:]
    /// U7: above zero while a caller that exports the phone capture itself (a merge, a
    /// detach, a reset) is changing the records, so a remembered-row change inside it
    /// does not export a second time.
    @ObservationIgnored var rememberedRowExportDeferrals = 0
    /// Raw continuity records from launch, for rows nothing has been bound to yet (KTD7).
    @ObservationIgnored var launchContinuity: [AccountKey: UsageSnapshot] = [:]
    /// KTD14 (2026-09-19 sign-in plan): diagnostics-only record of observed Claude
    /// sign-outs. Optional so the render harness, demo stores, and tests that don't
    /// care compose without it.
    let signOutRecord: SignOutRecord?
    let sessionReliabilityRecord: SessionReliabilityRecord?
    /// Per-account banked-reset announcements. Optional so tests and the demo
    /// store compose without it; the shipping store always has one (KTD6).
    let bankedResetAcknowledgements: BankedResetAcknowledgements?
    /// KTD1: use-it-up reminders and the banked-reset notice. Optional so tests, the demo
    /// store, and the render harness compose without it.
    let notificationCoordinator: NotificationCoordinator?
    let now: @Sendable () -> Date
    /// Builds the concrete provider for a newly added account. Lives in the composition
    /// root (R13) and is injected so the store never names concrete provider types.
    let providerFactory: (@MainActor (ProviderAccount) -> any UsageProvider)?
    let widgetExporter: (any WidgetSnapshotExporting)?
    /// KTD8 (iPhone parity plan): the coalesced v3 + v4 publisher. The store hands it a
    /// fresh capture on every change that reaches the phone; it decides when to write.
    let phoneSyncExporter: (any CompanionPhoneSyncing)?
    /// Test seam for the per-account setup-session overlay (KTD10). Nil reads the
    /// attached coordinator.
    @ObservationIgnored var companionSessionLookup: (@MainActor (AccountKey) -> CompanionSessionInput?)?
    /// The app-owned interactive-launch reason for an account's session. The coordinator
    /// knows the purpose but not the reason (it is chosen at staging, in the app), and the
    /// phone overlay needs it to tell a startup question from a workspace approval.
    @ObservationIgnored public var companionInteractiveReasonLookup:
        (@MainActor (AccountKey) -> ClaudeInteractiveLaunchReason?)?
    private(set) var engine: PollingEngine?
    private var isStarting = false
    @ObservationIgnored var removingAccounts: Set<AccountKey> = []
    /// KTD7 (OpenCode plan): accounts whose no-plan row sent the user to the plans page. The
    /// next popover open re-checks each one once, so a plan bought there shows up without a
    /// click and without raising any cadence.
    @ObservationIgnored var popoverOpenRechecks: Set<AccountKey> = []
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
        defaultLoginRecords: (any DefaultLoginRecordStoring)? = nil,
        signOutRecord: SignOutRecord? = nil,
        sessionReliabilityRecord: SessionReliabilityRecord? = nil,
        bankedResetAcknowledgements: BankedResetAcknowledgements? = nil,
        notificationCoordinator: NotificationCoordinator? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        widgetExporter: (any WidgetSnapshotExporting)? = nil,
        phoneSyncExporter: (any CompanionPhoneSyncing)? = nil
    ) {
        self.providers = providers
        self.apiSpendProviders = apiSpendProviders
        self.preferences = preferences
        self.accountRegistry = accountRegistry
        self.accountStorage = accountStorage
        self.providerFactory = providerFactory
        self.continuityCache = continuityCache
        self.defaultLoginRecordStore = defaultLoginRecords
        self.signOutRecord = signOutRecord
        self.sessionReliabilityRecord = sessionReliabilityRecord
        self.bankedResetAcknowledgements = bankedResetAcknowledgements
        self.notificationCoordinator = notificationCoordinator
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
        self.menuBarMarksPreference = preferences.showMenuBarMarks
        self.usagePercentageMode = preferences.usagePercentageMode
        self.accountTitleInk = preferences.accountTitleInk
        self.accountLayout = preferences.accountLayout
        self.expandAccountsHorizontally = preferences.expandAccountsHorizontally
        self.useEmailAsAccountName = preferences.useEmailAsAccountName
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
        self.menuBarWindowChoices = Dictionary(uniqueKeysWithValues: registeredProviderIDs.map {
            ($0, preferences.menuBarWindowChoice(for: $0))
        })
        self.chosenMenuBarWindowProviders = Set(registeredProviderIDs.filter {
            preferences.hasChosenMenuBarWindow(for: $0)
        })
        self.showCodexSparkCountersInApp = preferences.showCodexSparkCountersInApp
        self.showCodexSparkCountersInWidgets = preferences.showCodexSparkCountersInWidgets
        self.showsAntigravityFiveHourWindows = preferences.showsAntigravityFiveHourWindows
        self.antigravityGPUCreditsMode = preferences.antigravityGPUCreditsMode
        self.antigravityColabTier = preferences.antigravityColabTier
        self.antigravityGPUCreditsRefillDay = preferences.antigravityGPUCreditsRefillDay
        self.useItUpRemindersEnabled = preferences.useItUpRemindersEnabled
        self.bankedResetNotificationsEnabled = preferences.bankedResetNotificationsEnabled
        self.reminderRules = preferences.reminderRules
        self.reminderScope = preferences.reminderScope
        self.enabledSurfaces = Set(UsageSurface.allCases.filter { preferences.isSurfaceEnabled($0) })
        scheduler.host = self
        for provider in providers { scheduler.register(provider) }
        // KTD8: heartbeats and forced republishes capture fresh state on the main actor.
        phoneSyncExporter?.bind { [weak self] in self?.companionCapture() }
        prepareDefaultLogin(cached: cachedSnapshots)
        // U10: a relaunch while merged comes back merged before the first frame, from the
        // restored records and readings; the launch refresh exports, so this does not.
        for id in registeredProviderOrder { refreshDisplayMerge(for: id, exports: false) }
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
            tick: { [weak self] in
                self?.engineDidWake()
                self?.scheduler.dispatchDue()
            }
        )
        engine.start()
        self.engine = engine
    }

    /// Immediate off-cadence refresh — the Refresh button and other explicit user actions
    /// (KTD9). Popover open deliberately does *not* land here: it goes through
    /// `refreshOnPopoverOpen()`, which gates on capture age (R2M2).
    public func refreshNow(origin: UserRefreshOrigin = .fullRefresh) {
        Task { await refreshAll(origin: origin) }
    }

    /// R2M2: freshen on popover open, but only when the timer was about to fire anyway.
    /// The popover is the app's highest-frequency moment and a Claude poll is a full CLI
    /// session, so this wakes the queue only once the oldest live capture has already aged
    /// past a full poll interval; the lane's pass-end rephase then puts the next tick a full
    /// interval after the fresh data. At most one extra poll per interval; the cadence
    /// itself is never raised (AGENTS.md's cost warning).
    public func refreshOnPopoverOpen() {
        // KTD10: a remembered row shows its age as of this open, before any guard below.
        ageRememberedSnapshots()
        // Read before the re-checks: they are user-origin requests that raise `isRefreshing`
        // themselves, and must never cost the other accounts this open's wake.
        let userRefreshInFlight = isRefreshing
        runPopoverOpenRechecks()
        // A user refresh already in flight is freshening the data by itself.
        guard !userRefreshInFlight else { return }
        guard Self.shouldRefreshOnPopoverOpen(
            oldestLiveCapture: oldestLiveCapture,
            now: now(),
            intervalMinutes: preferences.pollIntervalMinutes
        ) else { return }
        // KTD6: wake the queue for whatever is due instead of forcing every account; the
        // lane's pass-end rephase moves the next tick a full interval past the fresh data.
        scheduler.dispatchDue()
    }

    /// KTD7 (OpenCode plan): after **See Go Plans**, arm one re-check of that account for the
    /// next popover open. Arming again before that open is still one re-check.
    public func armRecheckOnNextPopoverOpen(_ key: AccountKey) {
        popoverOpenRechecks.insert(key)
    }

    /// Spends every armed re-check, whatever happens to it: one open, one probe per account.
    /// It is a front-of-queue request like Check Now, so the duty-cycle gate does not hold it
    /// and the account's own row shows the work. An account that has since left the no-plan
    /// state, been removed or switched off has nothing to re-check.
    private func runPopoverOpenRechecks() {
        guard !popoverOpenRechecks.isEmpty else { return }
        let armed = popoverOpenRechecks
        popoverOpenRechecks.removeAll()
        for key in armed.sorted(by: { $0.description < $1.description })
        where snapshots[key]?.planStatus != nil && schedulerIsEligible(key) {
            refreshAccountNow(key)
        }
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
        // R17: the chosen interval travels in the manifest and sets the phone's dim rule.
        exportPhoneSyncSnapshot()
    }

    public func setShowMenuBarPercentage(_ enabled: Bool) {
        preferences.showMenuBarPercentage = enabled
        showMenuBarPercentage = enabled
    }

    /// CA-MB1 (KTD7): no `exportPhoneSyncSnapshot()`, the phone has no menu bar.
    public func setShowMenuBarMarks(_ enabled: Bool) {
        guard menuBarMarksPreference != enabled else { return }
        preferences.showMenuBarMarks = enabled
        menuBarMarksPreference = enabled
    }

    /// CA-MB1 (KTD7): whether explicit pills carry their provider's mark, with the unset
    /// default following the pill count. The automatic summary ignores this
    /// (`MenuBarMeter.showsMark`).
    public var menuBarShowsMarks: Bool {
        MenuBarMarksPolicy.explicitPillsMarked(
            preference: menuBarMarksPreference, explicitPillCount: selectedMenuBarProviders.count)
    }

    public func setUsagePercentageMode(_ mode: UsagePercentageMode) {
        // Settings loads its binding from the store, which echoes back through `onChange`.
        guard usagePercentageMode != mode else { return }
        preferences.usagePercentageMode = mode
        usagePercentageMode = mode
        // KTD11: display choices reach the phone's display block, never Mac widgets.
        exportPhoneSyncSnapshot()
    }

    public func setAccountTitleInk(_ ink: AccountTitleInk) {
        guard accountTitleInk != ink else { return }
        preferences.accountTitleInk = ink
        accountTitleInk = ink
        exportPhoneSyncSnapshot()
    }

    /// KTD8: no `exportPhoneSyncSnapshot()` — the phone has no popover to lay out.
    public func setAccountLayout(_ layout: AccountLayout) {
        guard accountLayout != layout else { return }
        preferences.accountLayout = layout
        accountLayout = layout
    }

    public func setUseEmailAsAccountName(_ enabled: Bool) {
        guard useEmailAsAccountName != enabled else { return }
        preferences.useEmailAsAccountName = enabled
        useEmailAsAccountName = enabled
        // KTD9 amended: the phone's titles follow the Mac's displayed name, so this changes
        // them; a title change forces the publisher's immediate flush (KTD8).
        exportPhoneSyncSnapshot()
    }

    public func setExpandAccountsHorizontally(_ enabled: Bool) {
        guard expandAccountsHorizontally != enabled else { return }
        preferences.expandAccountsHorizontally = enabled
        expandAccountsHorizontally = enabled
    }

    public func desktopAccountName(for account: ProviderAccount) -> String {
        DesktopAccountIdentity(
            // `snapshot(for:)`, so a remembered row names itself by its last reading's email.
            title: account.label, email: snapshot(for: account.key).accountEmail,
            showsPersistentEmail: false, usesEmailAsName: useEmailAsAccountName
        ).title
    }

    public func setMeterStyle(_ style: MeterStyle) {
        guard meterStyle != style else { return }
        preferences.meterStyle = style
        meterStyle = style
        exportPhoneSyncSnapshot()
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
        exportPhoneSyncSnapshot()
    }

    public var menuBarProviderOrder: [ProviderID] {
        let registered = registeredProviderOrder
        return savedMenuBarProviderOrder.filter(registered.contains).uniqued()
            + registered.filter { !savedMenuBarProviderOrder.contains($0) }
    }

    /// The most separate pills the menu bar shows. Seven would not fit the Settings arranger's
    /// row at its 720pt floor, and the menu bar itself has little more room.
    nonisolated public static let maximumMenuBarPills = 6

    /// The same ordered IDs drive both the arranger and the actual menu-bar label. Capped at
    /// `maximumMenuBarPills`, so a selected provider switched back on past the cap waits on
    /// the "Not shown" shelf instead of adding a seventh pill.
    public var selectedMenuBarProviders: [ProviderID] {
        guard let selected = menuBarFillSource.providerIDs else { return [] }
        return Array(
            menuBarProviderOrder.filter { selected.contains($0) && providerOrder.contains($0) }
                .prefix(Self.maximumMenuBarPills)
        )
    }

    public var canAddMenuBarProvider: Bool {
        selectedMenuBarProviders.count < Self.maximumMenuBarPills
    }

    /// Adds a pill before `target`, or at the end when `target` is nil or not a visible pill
    /// (a stale drop). From the automatic summary this switches to separate pills. Does
    /// nothing once the menu bar holds `maximumMenuBarPills`.
    public func addMenuBarProvider(_ id: ProviderID, before target: ProviderID? = nil) {
        guard providerOrder.contains(id), canAddMenuBarProvider else { return }
        var selected = menuBarFillSource.providerIDs ?? []
        guard selected.insert(id).inserted else { return }
        saveMenuBarOrder(menuBarProviderOrder.filter { $0 != id } + [id])
        setMenuBarFillSource(.providers(selected))
        // The move ignores a target that is not a visible pill, leaving the append.
        if let target { moveMenuBarProvider(id, before: target) }
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

    public func menuBarWindowChoice(for id: ProviderID) -> MenuBarWindowChoice {
        menuBarWindowChoices[id] ?? preferences.menuBarWindowChoice(for: id)
    }

    public func setMenuBarWindowChoice(_ choice: MenuBarWindowChoice, for id: ProviderID) {
        preferences.setMenuBarWindowChoice(choice, for: id)
        menuBarWindowChoices[id] = choice
        chosenMenuBarWindowProviders.insert(id)
    }

    /// What the limit picker shows as selected: the choice when it is listed, otherwise
    /// `closest`, which is what an unlisted default (weekly on Cursor) actually does.
    public func menuBarWindowPickerSelection(for id: ProviderID) -> MenuBarWindowChoice {
        let choice = menuBarWindowChoice(for: id)
        return menuBarWindowOptions(for: id).contains { $0.choice == choice } ? choice : .closest
    }

    /// The window the pill currently renders after availability fallback. Settings compares
    /// it with the choice so a provider dropping a limit is never silent.
    public func resolvedMenuBarWindowKind(for id: ProviderID) -> WindowKind? {
        menuBarWindow(for: id)?.kind
    }

    /// The limits a provider's pill can follow, in popover order (5-hour first), then
    /// `closest` whenever there is more than one limit to be closest among. A limit the user
    /// chose that the latest data does not carry is listed with no window, so the picker
    /// can still show it. One entry means there is nothing to choose.
    public func menuBarWindowOptions(for id: ProviderID) -> [MenuBarWindowOption] {
        let windows = menuBarCandidateWindows(for: id)
        var options = windows.map { window in
            MenuBarWindowOption(choice: .window(id: window.kind.persistentID), window: window)
        }
        let choice = menuBarWindowChoice(for: id)
        let isPending = snapshot(for: id).freshness == .pending
        if case .window = choice, chosenMenuBarWindowProviders.contains(id) || isPending,
           !windows.contains(where: { choice.matches($0.kind) }) {
            options.append(MenuBarWindowOption(choice: choice, window: nil))
        }
        if windows.count > 1 || choice == .closest || isPending {
            options.append(MenuBarWindowOption(choice: .closest, window: nil))
        }
        return options
    }

    /// A provider that has not reported yet keeps its picker (listing the choice and
    /// Closest to limit) so a choice can still be made before the first fetch lands.
    public func hasSelectableMenuBarWindows(for id: ProviderID) -> Bool {
        menuBarWindowOptions(for: id).count > 1
    }

    /// The main account's windows a pill may follow. Codex's Spark counters and Antigravity's
    /// 5-hour rows join only while the popover shows them, so the pill never follows a limit
    /// the popover hides.
    private func menuBarCandidateWindows(for id: ProviderID) -> [UsageWindow] {
        AntigravityFiveHourWindows.visibleSnapshot(
            filterCodexSparkCounters(
                from: snapshot(for: id),
                shouldShow: showCodexSparkCountersInApp
            ),
            showsFiveHourWindows: showsAntigravityFiveHourWindows,
            gpuCreditsMode: antigravityGPUCreditsMode
        ).fiveHourFirst().windows
    }

    public func setShowCodexSparkCountersInApp(_ enabled: Bool) {
        preferences.showCodexSparkCountersInApp = enabled
        showCodexSparkCountersInApp = enabled
        exportPhoneSyncSnapshot()
    }

    public func setShowCodexSparkCountersInWidgets(_ enabled: Bool) {
        preferences.showCodexSparkCountersInWidgets = enabled
        showCodexSparkCountersInWidgets = enabled
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    public func setShowsAntigravityFiveHourWindows(_ enabled: Bool) {
        preferences.showsAntigravityFiveHourWindows = enabled
        showsAntigravityFiveHourWindows = enabled
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    public func setAntigravityGPUCreditsMode(_ mode: AntigravityGPUCreditsMode) {
        guard antigravityGPUCreditsMode != mode else { return }
        let wasOff = antigravityGPUCreditsMode == .off
        preferences.antigravityGPUCreditsMode = mode
        antigravityGPUCreditsMode = mode
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
        if wasOff && mode != .off && providerOrder.contains(.antigravity) {
            refreshProviderNow(.antigravity)
        }
    }

    public func setAntigravityColabTier(_ tier: ColabComputeTier) {
        guard antigravityColabTier != tier else { return }
        preferences.antigravityColabTier = tier
        antigravityColabTier = tier
        if antigravityGPUCreditsMode != .off && providerOrder.contains(.antigravity) {
            refreshProviderNow(.antigravity)
        }
    }

    public func setAntigravityGPUCreditsRefillDay(_ day: Int?) {
        let normalized = day.flatMap { (1...31).contains($0) ? $0 : nil }
        guard antigravityGPUCreditsRefillDay != normalized else { return }
        preferences.antigravityGPUCreditsRefillDay = normalized
        antigravityGPUCreditsRefillDay = normalized
        if antigravityGPUCreditsMode != .off && providerOrder.contains(.antigravity) {
            refreshProviderNow(.antigravity)
        }
    }

    public func setUseItUpRemindersEnabled(_ enabled: Bool) {
        guard useItUpRemindersEnabled != enabled else { return }
        preferences.useItUpRemindersEnabled = enabled
        useItUpRemindersEnabled = enabled
        // KTD19: the manifest's reminder summary mirrors the Notifications pane.
        exportPhoneSyncSnapshot()
    }

    public func setBankedResetNotificationsEnabled(_ enabled: Bool) {
        guard bankedResetNotificationsEnabled != enabled else { return }
        preferences.bankedResetNotificationsEnabled = enabled
        bankedResetNotificationsEnabled = enabled
        exportPhoneSyncSnapshot()
    }

    /// Persists the list in the given order, clamped. R6: sorting belongs to a committed
    /// edit (`commitReminderRule`), never to typing.
    public func setReminderRules(_ rules: [ReminderRule]) {
        let clamped = rules.map { $0.clamped() }
        guard reminderRules != clamped else { return }
        preferences.reminderRules = clamped
        reminderRules = clamped
        exportPhoneSyncSnapshot()
    }

    /// R4/R6: a committed row edit clamps, replaces the row with the same ID, and resorts.
    /// An ID no longer in the list (removed mid-edit) changes nothing.
    public func commitReminderRule(_ rule: ReminderRule) {
        guard let index = reminderRules.firstIndex(where: { $0.id == rule.id }) else { return }
        var rules = reminderRules
        rules[index] = rule.clamped()
        setReminderRules(ReminderRules.sorted(rules))
    }

    /// R5: appends a rule seeded from the shortest one and returns it.
    @discardableResult
    public func addReminderRule() -> ReminderRule {
        let seeded = ReminderRules.seed(from: reminderRules)
        setReminderRules(reminderRules + [seeded])
        return seeded
    }

    public func removeReminderRule(id: ReminderRule.ID) {
        setReminderRules(reminderRules.filter { $0.id != id })
    }

    public func setReminderScope(_ scope: Set<ReminderScope>) {
        guard reminderScope != scope else { return }
        preferences.reminderScope = scope
        reminderScope = scope
        exportPhoneSyncSnapshot()
    }

    /// R8: whether "Reset to defaults" should show.
    public var reminderSettingsAreDefault: Bool {
        ReminderRules.isDefault(rules: reminderRules, scope: reminderScope)
    }

    /// R8: restores both the rules and the Applies-to choices.
    public func resetReminderSettingsToDefaults() {
        setReminderRules(ReminderRules.defaults)
        setReminderScope(ReminderScope.defaults)
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
        return UsageMeterReading(window: resolved.window).fraction(for: usagePercentageMode)
    }

    /// Render-ready menu bar meters. Explicit selection gives each chosen provider its
    /// own vessel/percentage pair; automatic mode keeps the existing compact summary.
    public var menuBarMeters: [MenuBarMeter] {
        guard menuBarFillSource.providerIDs != nil else {
            let summary = menuBarSummary
            return [MenuBarMeter(
                summary: summary, fill: menuBarFill,
                awaitingFirstReading: summary.isNeutral && providerOrder.contains { snapshot(for: $0).freshness == .pending },
                isLiveReading: summary.providerID.map { snapshot(for: $0).freshness == .live } ?? false,
                isAutomaticSummary: true
            )]
        }

        let meters = selectedMenuBarProviders.map { providerMenuBarMeter(for: $0) }
        return meters.isEmpty ? [MenuBarMeter(summary: .neutral, fill: nil)] : meters
    }

    /// Round-3 S2 (Oct 2026): providers whose main account is being probed right now. Each
    /// pill shows its provider's main account, so its liquid sloshes exactly while that
    /// number is being fetched, whether a timer or the user asked for it.
    public var menuBarUpdatingProviders: Set<ProviderID> {
        Set(probingAccounts.compactMap { key in
            primaryKey(for: key.providerID) == key ? key.providerID : nil
        })
    }

    /// W4: how the footer receipt names an account — the provider alone while it has one
    /// account (labels are hidden then), "Claude Work" once it has several.
    public func refreshReceiptTitle(for key: AccountKey) -> String {
        // KTD8: titled the way the popover titles its rows, remembered rows included.
        let accounts = displayAccounts(for: key.providerID).map(\.account)
        // U10: a merged built-in's probe lands under the row that shows it.
        let shown = displayMergeMaps[key.providerID]?[key] ?? key
        return RefreshReceiptPresentation.title(
            providerName: displayNames[key.providerID] ?? key.providerID.raw,
            accountTitle: accounts.first(where: { $0.key == shown }).map { desktopAccountName(for: $0) },
            providerAccountCount: accounts.count)
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
    ///
    /// KTD14.4: one full refresh at a time. A second caller while one runs awaits that same
    /// refresh, so five triggers in a row (or a phone joining the launch refresh) run one
    /// probe round.
    public func refreshAll(origin: UserRefreshOrigin = .fullRefresh) async {
        guard origin == .fullRefresh else {
            await performRefreshAll(origin: origin)
            return
        }
        if let fullRefreshTask {
            await fullRefreshTask.value
            return
        }
        fullRefreshStartedAt = now()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefreshAll(origin: .fullRefresh)
            // Cleared inside the task, so every waiter resumes to a settled store.
            self.fullRefreshTask = nil
            self.fullRefreshStartedAt = nil
            self.lastFullRefreshCompletedAt = self.now()
        }
        fullRefreshTask = task
        await task.value
    }

    private func performRefreshAll(origin: UserRefreshOrigin) async {
        if origin != .setupCheck { visibleRefreshOperationDepth += 1 }
        defer {
            if origin != .setupCheck {
                visibleRefreshOperationDepth -= 1
                recomputeVisibleRefreshWork()
            }
        }
        if origin == .fullRefresh {
            fullRefreshOperationDepth += 1
            fullRefreshInFlight = true
        }
        fullRefreshDepth += 1
        // Raised before the subscription work so the flag does not blink off between the
        // last merge and the spend fetch.
        apiSpendUserRefreshDepth += 1
        recomputeRefreshing()
        scheduler.markAllDue(origin: origin)
        scheduler.dispatchDue()
        await scheduler.waitUntilUserWorkDrains()
        // Timer candidates a lane keeps serving after the user's work merged export on their
        // own; the refresh's single export below still follows every lane going idle.
        fullRefreshDepth -= 1
        await scheduler.waitUntilLanesIdle()
        await refreshAPISpend(exportAfter: false)
        if origin == .fullRefresh {
            fullRefreshOperationDepth -= 1
            fullRefreshInFlight = fullRefreshOperationDepth > 0
        }
        apiSpendUserRefreshDepth -= 1
        recomputeRefreshing()
        refreshPollCadences()
        exportWidgetSnapshot()
        exportPhoneSyncSnapshot()
    }

    /// Refresh a single account — Check Now, Check Again, Try Again, Make Main, and the
    /// setup coordinator's checks (R4, KTD7). A front-of-queue request, so watching one
    /// sign-in never fans out into a full fleet poll.
    public func refreshAccountNow(_ key: AccountKey, origin: UserRefreshOrigin = .accountAction) {
        scheduler.requestPriority(key, origin: origin)
    }

    func refreshAccount(_ key: AccountKey, origin: UserRefreshOrigin = .accountAction) async {
        scheduler.requestPriority(key, origin: origin)
        await scheduler.waitForCompletion(of: key)
    }

    /// R18: provider capability recovery re-checks every attached account, bypassing
    /// capability-failure backoff without waking any other provider.
    public func refreshProviderNow(_ providerID: ProviderID) {
        for account in accounts(for: providerID) { refreshAccountNow(account.key) }
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
        visibleRefreshOperationDepth += 1
        apiSpendUserRefreshDepth += 1
        recomputeRefreshing()
        defer {
            apiSpendInFlight = false
            visibleRefreshOperationDepth -= 1
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
        recomputeVisibleRefreshWork()
        let next = userWorkPending || apiSpendUserRefreshDepth > 0
        guard isRefreshing != next else { return }
        isRefreshing = next
        refreshingClearedAt = next ? nil : now()
        if !next, userRefreshRun != nil {
            let clearedAt = refreshingClearedAt!
            userRefreshRun?.refreshingClearedAt = clearedAt
            let runID = userRefreshRun?.id
            refreshRunRetentionTask?.cancel()
            refreshRunRetentionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.refreshRunRetentionDuration))
                guard !Task.isCancelled, let self, self.userRefreshRun?.id == runID else { return }
                self.clearExpiredUserRefreshRun(at: self.now())
            }
        }
    }

    private func recomputeVisibleRefreshWork() {
        let pending = userRefreshRun?.entries.values.contains {
            $0.origin != .setupCheck && $0.outcome == nil
        } ?? false
        let next = pending || visibleRefreshOperationDepth > 0
        guard visibleRefreshWork.isInFlight != next else { return }
        visibleRefreshWork = VisibleRefreshWork(isInFlight: next, clearedAt: next ? nil : now())
    }

    /// A clock seam for testing the 0.5s hold plus 0.2s retention without a real wait.
    func clearExpiredUserRefreshRun(at date: Date) {
        guard !isRefreshing, let clearedAt = userRefreshRun?.refreshingClearedAt,
              date.timeIntervalSince(clearedAt) >= Self.refreshRunRetentionDuration else { return }
        userRefreshRun = nil
    }

    private func refreshAPISpend(exportAfter: Bool = true) async {
        let spendPeriod = preferences.apiSpendPeriod
        let spendResults = await withTaskGroup(of: (ProviderID, APISpendSnapshot).self) { group in
            for provider in apiSpendProviders {
                guard let surface = UsageSurface.api(for: provider.id),
                      enabledSurfaces.contains(surface)
                else { continue }
                spendFetchDepths[provider.id, default: 0] += 1
                apiSpendInFlightProviders.insert(provider.id)
                group.addTask { (provider.id, await provider.fetchSpend(period: spendPeriod)) }
            }
            var acc: [(ProviderID, APISpendSnapshot)] = []
            for await pair in group {
                spendFetchDepths[pair.0, default: 1] -= 1
                if spendFetchDepths[pair.0] == 0 {
                    spendFetchDepths.removeValue(forKey: pair.0)
                    apiSpendInFlightProviders.remove(pair.0)
                }
                acc.append(pair)
            }
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
        // KTD2 (default-login plan): a reading taken while the login was changing belongs
        // to neither account for certain. Refused here, before `merge`, so it never
        // reaches the snapshot, the continuity cache or a setup session.
        if result.discard != nil { return false }
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
        // Default-login plan U3: a change of account is settled here, first, so nothing
        // below files this reading under the previous account's name or history.
        // Every merge is followed by its caller's phone export (U7).
        let prior = deferringRememberedRowExport { defaultLoginPrior(for: key, fresh: fresh) }
        sessionReliabilityRecord?.note(
            fresh, for: key, expectedInterval: schedulerChosenInterval,
            trackedAccounts: providers.map(\.accountKey)
        )
        let next = UsageContinuityPolicy.mergedSnapshot(
            fresh,
            with: prior,
            at: now()
        )
        recordSignOutEdge(next, for: key)
        // Skip the assignment when nothing changed so an unchanging state (e.g. a
        // provider that stays logged-out) doesn't invalidate observers every cycle.
        if snapshots[key] != next { snapshots[key] = next }
        // U10: this reading may bind, rebind or lapse a row, or make E readable or not, so
        // the one-row merge is settled before anything below asks whether the row shows.
        // The caller exports (`schedulerMerge`, or a full refresh at its end).
        refreshDisplayMerge(for: key.providerID, exports: false)
        // KTD11: a merged built-in's reading is E's account, so E alone reminds and
        // acknowledges banked resets; the pair fires one reminder, not two.
        if next.freshness == .live, !isMergedAway(key) {
            bankedResetAcknowledgements?.lower(for: key, currentCount: next.bankedResets)
            evaluateNotifications(next, for: key)
        }
        updateContinuityCache(next, for: key)
        if notifiesSetup { setupCoordinator?.receive(next, for: key) }
        return true
    }

    /// KTD2: only a fresh live merge reaches here, so a launch restore, a failed poll's
    /// retained windows, and a capability failure never notify. The completion re-checks
    /// this attachment, so a post that races a removal or reset writes no ledger (KTD6).
    private func evaluateNotifications(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard let notificationCoordinator else { return }
        // KTD8: the label appears once the provider shows several rows, remembered included.
        let visible = displayAccounts(for: key.providerID).map(\.account)
        let context = NotificationEvaluationContext(
            providerName: key.providerID.displayName,
            accountLabel: visible.count > 1 ? visible.first { $0.key == key }?.label : nil,
            useItUp: UseItUpSettings(
                isEnabled: useItUpRemindersEnabled,
                rules: reminderRules,
                scope: reminderScope,
                showCodexSparkCounters: showCodexSparkCountersInApp,
                showsAntigravityFiveHourWindows: showsAntigravityFiveHourWindows,
                antigravityGPUCreditsMode: antigravityGPUCreditsMode
            ),
            bankedResetsEnabled: bankedResetNotificationsEnabled
        )
        let generation = attachmentGenerations[key, default: 0]
        notificationCoordinator.receive(snapshot, for: key, context: context, now: now()) { [weak self] in
            self?.acceptsResult(for: key, attachmentGeneration: generation) ?? false
        }
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
        let saves: Bool
        if case .stale(let reason) = snapshot.freshness, reason.isPermanent {
            saves = false
        } else {
            saves = !snapshot.windows.isEmpty
        }
        if saves {
            continuityCache?.save(snapshot, for: key)
        } else {
            continuityCache?.remove(for: key)
        }
        defaultLoginDidUpdateContinuity(for: key, removed: !saves)
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

    /// Claims a first-show reveal for a current, live account. A missing record,
    /// a stale or pending row, and an account mid-removal all return false and
    /// write nothing (KTD6, KTD7).
    public func claimBankedResetReveal(for key: AccountKey, currentCount: Int?) -> Bool {
        guard acceptsResult(for: key, attachmentGeneration: attachmentGenerations[key, default: 0]) else {
            return false
        }
        guard snapshot(for: key).freshness == .live, !isMergedAway(key) else { return false }
        return bankedResetAcknowledgements?.claimReveal(for: key, currentCount: currentCount) ?? false
    }

    /// An engine row's snapshot, or a visible remembered row's aged last reading (U7).
    public func snapshot(for key: AccountKey) -> UsageSnapshot {
        snapshots[key] ?? rememberedDisplaySnapshots[key] ?? .pending(for: key.providerID)
    }

    /// Primary-account snapshot — the single-account view compact surfaces use.
    public func snapshot(for id: ProviderID) -> UsageSnapshot {
        snapshot(for: primaryKey(for: id))
    }

    public func appDisplaySnapshot(for key: AccountKey) -> UsageSnapshot {
        fiveHourFirst(
            AntigravityFiveHourWindows.visibleSnapshot(
                filterCodexSparkCounters(
                    from: snapshot(for: key),
                    shouldShow: preferences.showCodexSparkCountersInApp
                ),
                showsFiveHourWindows: preferences.showsAntigravityFiveHourWindows,
                gpuCreditsMode: preferences.antigravityGPUCreditsMode
            )
        )
    }

    public func appDisplaySnapshot(for id: ProviderID) -> UsageSnapshot {
        appDisplaySnapshot(for: primaryKey(for: id))
    }

    /// KTD8: the display primary, which compact surfaces and the main-account widget
    /// export follow.
    private func primaryKey(for id: ProviderID) -> AccountKey {
        displayPrimaryKey(for: id) ?? AccountKey(providerID: id, accountID: .primary)
    }

    /// Popover display order: 5-hour leads, weekly second, model rows keep their
    /// provider-given order after. The rule
    /// lives on `UsageSnapshot.fiveHourFirst()` so the Settings specimen renders the same order.
    private func fiveHourFirst(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        snapshot.fiveHourFirst()
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

    /// KTD8 (iPhone parity plan): marks the phone path dirty with a fresh capture. The
    /// publisher coalesces, so calling this on every merge never means a write per merge.
    func exportPhoneSyncSnapshot() {
        guard let phoneSyncExporter else { return }
        phoneSyncExporter.submit(companionCapture())
    }

    /// KTD8: pending phone writes flush on system sleep and app quit.
    public func flushPhoneSync() async {
        await phoneSyncExporter?.flushNow()
    }

    /// Mac widgets mirror each provider's *primary* account — a glanceable tile can't rank
    /// five logins. The phone's v4 payload carries every account (`companionCapture`).
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
            showsAntigravityFiveHourWindows: preferences.showsAntigravityFiveHourWindows,
            antigravityGPUCreditsMode: preferences.antigravityGPUCreditsMode,
            apiSpendSnapshots: apiSpendSnapshots,
            apiSpendProviderOrder: apiSpendProviderOrder,
            generatedAt: generatedAt
        )
    }

    func resolvedWidgetProviderSelection() -> [ProviderID] {
        switch widgetPrioritySource.filtered(to: providerOrder) {
        case .auto:
            return Array(providerOrder.prefix(2))
        case .providers(let selected):
            return Array(providerOrder.lazy.filter(selected.contains).prefix(2))
        }
    }

    private func filterCodexSparkCounters(from snapshot: UsageSnapshot, shouldShow: Bool) -> UsageSnapshot {
        guard snapshot.providerID == .codex, !shouldShow else { return snapshot }
        return snapshot.replacingWindows(snapshot.windows.filter { !$0.kind.isCodexSparkCounter })
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
        let reading = UsageMeterReading(window: best.window)
        let name = displayNames[best.id] ?? best.id.raw
        return MenuBarSummary(
            text: menuBarText(reading),
            providerID: best.id,
            detail: "\(name) \(best.menuBarTerm)",
            isNeutral: false,
            percentageMode: usagePercentageMode,
            severity: reading.severity ?? best.window.severity,
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
            return MenuBarMeter(
                summary: MenuBarSummary(
                    text: "—",
                    providerID: id,
                    detail: "\(name) \(menuBarWindowChoice(for: id).menuBarTerm)",
                    isNeutral: true,
                    needsAttention: needsAttention
                ),
                fill: nil,
                awaitingFirstReading: snapshot(for: id).freshness == .pending,
                isLiveReading: snapshot(for: id).freshness == .live,
                sourceAccountKey: primaryKey(for: id)
            )
        }

        let reading = UsageMeterReading(window: resolved.window)
        let name = displayNames[id] ?? id.raw
        return MenuBarMeter(
            summary: MenuBarSummary(
                text: menuBarText(reading),
                providerID: id,
                detail: "\(name) \(resolved.menuBarTerm)",
                isNeutral: false,
                percentageMode: usagePercentageMode,
                severity: reading.severity ?? resolved.window.severity,
                needsAttention: needsAttention
            ),
            fill: reading.fraction(for: usagePercentageMode),
            awaitingFirstReading: snapshot(for: id).freshness == .pending,
            isLiveReading: snapshot(for: id).freshness == .live,
            sourceAccountKey: primaryKey(for: id)
        )
    }

    /// KTD6.2: the popover row's own reading prints, inks and fills the menu bar, so every
    /// Mac surface shows one integer and one severity for a window. A non-finite source has
    /// no figure, as in the row.
    private func menuBarText(_ reading: UsageMeterReading) -> String {
        reading.roundedPercentage(for: usagePercentageMode).map { "\($0)%" } ?? "—"
    }

    private func providerNeedsAttention(_ id: ProviderID) -> Bool {
        displayAccounts(for: id).contains { row in
            if case .stale(let reason) = snapshot(for: row.key).freshness { return reason.isPermanent }
            return false
        }
    }

    /// Resolve one provider's chosen window. If the latest data does not carry it, follow the
    /// closest-to-limit window while keeping the saved choice, so the pill returns to it
    /// automatically. An `.unavailable` retained row has no percentage to show, so it is
    /// neither chosen nor closest.
    private func menuBarWindow(for id: ProviderID) -> ResolvedMenuBarWindow? {
        guard providerOrder.contains(id) else { return nil }
        guard snapshot(for: id).freshness != .pending else { return nil }

        let windows = menuBarCandidateWindows(for: id).filter { !$0.freshness.isUnavailable }
        let choice = menuBarWindowChoice(for: id)
        let window = windows.first(where: { choice.matches($0.kind) })
            ?? windows.min(by: { $0.percentRemaining < $1.percentRemaining })
        guard let window else { return nil }
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

    /// Engine side, following the merge map (KTD8): never a remembered row.
    func schedulerIsPrimary(_ key: AccountKey) -> Bool {
        displayProjection(for: key.providerID).isEnginePrimary(key)
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
        let primaryBefore = primaryKey(for: key.providerID)
        let accepted = mergeResult(
            key: key, result: result, notifiesSetup: notifiesSetup, attachmentGeneration: attachmentGeneration
        )
        // KTD9 / R19: Mac widgets mirror the primary, so its merge exports at once instead
        // of waiting for every extra in the lane. iPhone parity KTD8 amends AE7: an extra's
        // merge now marks the phone path dirty too, but never reloads Mac WidgetKit
        // timelines. A full refresh exports once at its end instead. U10: a reading that
        // merges or unmerges the main account moves the display primary, so it reloads the
        // widget once too.
        if accepted, fullRefreshDepth == 0 {
            if primaryKey(for: key.providerID) == key || primaryKey(for: key.providerID) != primaryBefore {
                exportWidgetSnapshot()
            }
            exportPhoneSyncSnapshot()
        }
        return accepted
    }

    func schedulerLaneDidGoIdle(_ lane: ProviderPollingLane) {
        refreshPollCadences()
        // KTD6: the next sleep is computed from the pass's new due times.
        engine?.rephase()
    }

    func schedulerStartsNewUserRun(origin: UserRefreshOrigin) -> Bool {
        guard let run = userRefreshRun else { return true }
        guard let clearedAt = run.refreshingClearedAt else { return false }
        return origin != .setupCheck || now().timeIntervalSince(clearedAt) >= Self.refreshRunRetentionDuration
    }

    func schedulerUserRunDidChange(_ run: UserRefreshRun) {
        refreshRunRetentionTask?.cancel()
        userRefreshRun = run
        recomputeVisibleRefreshWork()
    }

    func schedulerUserWorkDidChange(hasPending: Bool) {
        userWorkPending = hasPending
        if !hasPending { refreshProgress = nil }
        recomputeRefreshing()
    }

    func schedulerProbeDidStart(_ key: AccountKey) {
        if !probingAccounts.contains(key) { probingAccounts.insert(key) }
    }

    func schedulerProbeDidEnd(_ key: AccountKey) {
        lastProbeEndTimes[key] = now()
        if probingAccounts.contains(key) { probingAccounts.remove(key) }
    }

    func schedulerUserProgressDidChange(total: Int, completed: Int, landed: AccountKey?) {
        refreshProgress = RefreshProgress(
            total: total,
            completed: completed,
            lastLanded: landed ?? refreshProgress?.lastLanded
        )
        checkNowProgressObserver?()
    }
}
