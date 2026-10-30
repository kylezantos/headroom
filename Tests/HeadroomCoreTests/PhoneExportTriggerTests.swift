import Foundation
import Testing

@testable import HeadroomCore

/// U5 / R17, R36, KTD8: every Mac change that affects the phone hands the publisher a
/// fresh capture without waiting for the next main-account refresh, and an extra
/// account's merge reaches the phone path without reloading Mac widget timelines.
@MainActor
@Suite
struct PhoneExportTriggerTests {
    private let reset = Date(timeIntervalSince1970: 3_000_000)

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.phone-triggers.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func live(_ id: ProviderID, used: Double, at: Date = Date(timeIntervalSince1970: 2_000_000)) -> UsageSnapshot {
        UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .weekly, utilization: used, resetsAt: reset)],
            planLabel: "Max", capturedAt: at, freshness: .live)
    }

    private struct Fixture {
        let store: UsageStore
        let phone: SpyPhoneSync
        let widgets: SpyWidgetExporter
        let registry: AccountRegistry
        let preferences: Preferences
    }

    /// A Claude built-in plus `extras`, with sync on and a live provider factory.
    private func fixture(extras labels: [String] = ["Work"], builtInLabel: String? = nil) -> (Fixture, [ProviderAccount]) {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        if let builtInLabel { registry.renameAccount(AccountKey(providerID: .claude, accountID: .primary), to: builtInLabel) }
        let extras = labels.map { registry.addAccount(for: .claude, label: $0)! }
        let preferences = Preferences(defaults: defaults)
        preferences.syncToIPhoneEnabled = true
        let phone = SpyPhoneSync()
        let widgets = SpyWidgetExporter()
        let providers: [any UsageProvider] =
            [DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: live(.claude, used: 30))]
            + extras.enumerated().map { index, account in
                DemoUsageProvider(
                    id: .claude, displayName: "Claude", snapshot: live(.claude, used: 50 + Double(index)),
                    accountID: account.id)
            }
        let store = UsageStore(
            providers: providers, preferences: preferences, accountRegistry: registry,
            accountStorage: DemoAccountStorage(),
            providerFactory: { account in
                DemoUsageProvider(
                    id: account.providerID, displayName: "Claude",
                    snapshot: .pending(for: account.providerID), accountID: account.id)
            },
            widgetExporter: widgets, phoneSyncExporter: phone)
        return (Fixture(store: store, phone: phone, widgets: widgets, registry: registry, preferences: preferences), extras)
    }

    private func accounts(_ capture: CompanionPublishCapture?, _ id: String = "claude") -> [CompanionAccountSummary] {
        guard let provider = capture?.providers.first(where: { $0.providerID == id }) else { return [] }
        return (provider.mainAccount.map { [$0] } ?? []) + provider.extraAccounts
    }

    // MARK: Account lifecycle (V10, V11)

    @Test func addRenameRemoveMakeMainStopTrackAndResumeEachExport() async throws {
        let (f, extras) = fixture()
        await f.store.refreshAll()
        #expect(accounts(f.phone.last).map(\.title) == ["Main", "Work"])

        var count = f.phone.captures.count
        let added = try #require(f.store.addAccount(for: .claude, label: "Studio"))
        #expect(f.phone.captures.count == count + 1)
        #expect(accounts(f.phone.last).map(\.title) == ["Main", "Work", "Studio"])

        count = f.phone.captures.count
        f.store.renameAccount(added.key, to: "Lab")
        #expect(f.phone.captures.count == count + 1)
        #expect(accounts(f.phone.last).map(\.title) == ["Main", "Work", "Lab"])

        count = f.phone.captures.count
        #expect(f.store.promoteAccount(extras[0].key))
        #expect(f.phone.captures.count > count)
        #expect(accounts(f.phone.last).map(\.id) == [extras[0].id.raw, "primary", added.id.raw])

        count = f.phone.captures.count
        #expect(await f.store.removeAccount(added.key) == .removed)
        #expect(f.phone.captures.count > count)
        #expect(accounts(f.phone.last).map(\.title) == ["Work", "Main"])

        count = f.phone.captures.count
        #expect(await f.store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        #expect(f.phone.captures.count > count)
        #expect(accounts(f.phone.last).map(\.id) == [extras[0].id.raw])

        count = f.phone.captures.count
        #expect(f.store.resumeTrackingBuiltInAccount(for: .claude) != nil)
        #expect(f.phone.captures.count > count)
        #expect(Set(accounts(f.phone.last).map(\.id)) == ["primary", extras[0].id.raw])
    }

    /// V11: with the built-in stop-tracked, the first extra is main in v4 and in v3.
    @Test func aStopTrackedBuiltInMakesTheFirstExtraMainInBothFormats() async throws {
        let (f, extras) = fixture(extras: ["Work", "Studio"])
        await f.store.refreshAll()
        #expect(await f.store.stopTrackingBuiltInAccount(for: .claude) == .removed)
        let capture = try #require(f.phone.last)
        let claude = try #require(capture.providers.first)
        #expect(claude.mainAccount?.id == extras[0].id.raw)
        #expect(claude.extraAccounts.map(\.id) == [extras[1].id.raw])
        // v3 carries the same main: Work's weekly is 50% used.
        #expect(capture.v3.providers.first?.windows.first?.percentRemaining == 50)
    }

    /// V13 / AE7: two "Work" accounts read "Work" and "Work · 2", and Make Main keeps them.
    @Test func duplicateNamesKeepTheirSuffixesAcrossMakeMain() async throws {
        let (f, extras) = fixture(extras: ["work"], builtInLabel: "Work")
        await f.store.refreshAll()
        #expect(accounts(f.phone.last).map(\.title) == ["Work", "work · 2"])
        #expect(f.store.promoteAccount(extras[0].key))
        #expect(accounts(f.phone.last).map(\.title) == ["work · 2", "Work"])
        #expect(accounts(f.phone.last).first?.id == extras[0].id.raw)
    }

    // MARK: Extras' merges (KTD8 amending polling AE7)

    @Test func anExtraAccountsMergeExportsToThePhoneOnlyAndNeverReloadsMacWidgets() async throws {
        let (f, extras) = fixture()
        await f.store.refreshAll()
        let widgetExports = f.widgets.exports.count
        let phoneExports = f.phone.captures.count

        await f.store.refreshAccount(extras[0].key)
        #expect(f.phone.captures.count == phoneExports + 1)
        #expect(f.widgets.exports.count == widgetExports)

        // The main account's merge still reaches both.
        await f.store.refreshAccount(AccountKey(providerID: .claude, accountID: .primary))
        #expect(f.widgets.exports.count == widgetExports + 1)
        #expect(f.phone.captures.count == phoneExports + 2)
    }

    // MARK: Settings triggers (R17, R36)

    @Test func widgetProviderSelectionReachesThePhone() async throws {
        let (f, _) = fixture()
        await f.store.refreshAll()
        let count = f.phone.captures.count
        f.store.setWidgetPrioritySource(.providers([.claude]))
        #expect(f.phone.captures.count == count + 1)
        #expect(f.phone.last?.widgetProviderSelection == ["claude"])
        #expect(f.phone.last?.v3.widgetProviderSelection == ["claude"])
    }

    @Test func displaySettersExportANewDisplayBlock() async throws {
        let (f, _) = fixture()
        await f.store.refreshAll()
        f.store.setUsagePercentageMode(.used)
        #expect(f.phone.last?.display?.percentageMode == .used)
        f.store.setAccountTitleInk(.brand)
        #expect(f.phone.last?.display?.accountTitleInk == .brand)
        let style = MeterStyle(format: .full, shape: .segmented, fill: .ghost)
        f.store.setMeterStyle(style)
        #expect(f.phone.last?.display?.meterStyle == style)
        f.store.setShowCodexSparkCountersInApp(true)
        #expect(f.phone.last?.display?.appSparkEnabled == true)
        f.store.setShowCodexSparkCountersInWidgets(true)
        #expect(f.phone.last?.widgetSparkEnabled == true)
    }

    @Test func intervalProviderSwitchAndReminderChangesExport() async throws {
        let (f, _) = fixture()
        await f.store.refreshAll()
        var count = f.phone.captures.count
        f.preferences.pollIntervalMinutes = 10
        f.store.reschedulePolling()
        #expect(f.phone.captures.count == count + 1)
        #expect(f.phone.last?.chosenIntervalSeconds == 600)

        count = f.phone.captures.count
        f.store.setUseItUpRemindersEnabled(!f.store.useItUpRemindersEnabled)
        f.store.setBankedResetNotificationsEnabled(!f.store.bankedResetNotificationsEnabled)
        f.store.setReminderScope([.fiveHour])
        f.store.addReminderRule()
        #expect(f.phone.captures.count == count + 4)
        let summary = try #require(f.phone.last?.reminderSummary)
        #expect(summary.macUseItUpEnabled == f.store.useItUpRemindersEnabled)
        #expect(summary.macBankedResetEnabled == f.store.bankedResetNotificationsEnabled)
        #expect(summary.scope == [.fiveHour])
        #expect(summary.rules.count == f.store.reminderRules.count)

        count = f.phone.captures.count
        f.store.setSurfaceEnabled(false, for: .claudeSubscription)
        #expect(f.phone.captures.count == count + 1)
        #expect(f.phone.last?.providers.isEmpty == true)
        #expect(f.phone.last?.providerOrder == [])
    }

    /// KTD6.1: subscription off with API spend on keeps a spend-only key; both off removes it.
    @Test func spendOnlyProvidersCarrySpendWithoutAccounts() async throws {
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.syncToIPhoneEnabled = true
        let phone = SpyPhoneSync()
        let spend = DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend)
        let store = UsageStore(
            providers: [DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: live(.codex, used: 20))],
            apiSpendProviders: [spend], preferences: preferences, phoneSyncExporter: phone)
        store.setSurfaceEnabled(true, for: .openAIAPI)
        await store.refreshAll()
        #expect(phone.last?.providers.first?.mode == .subscription)
        #expect(phone.last?.providers.first?.apiSpend?.amount == DemoFixture.openAISpend.amount)

        store.setSurfaceEnabled(false, for: .codexSubscription)
        let spendOnly = try #require(phone.last?.providers.first)
        #expect(spendOnly.mode == .spendOnly && spendOnly.mainAccount == nil)
        #expect(spendOnly.apiSpend != nil)
        #expect(phone.last?.spendOrder == ["codex"] && phone.last?.providerOrder == [])

        store.setSurfaceEnabled(false, for: .openAIAPI)
        #expect(phone.last?.providers.isEmpty == true)
    }

    @Test func syncOffCapturesNoAccountContent() async throws {
        let (f, _) = fixture()
        await f.store.refreshAll()
        f.store.setSyncToIPhoneEnabled(false)
        let capture = try #require(f.phone.last)
        #expect(capture.status == .disabled)
        #expect(capture.providers.isEmpty && capture.v3.status == .disabled)
        f.store.setSyncToIPhoneEnabled(true)
        #expect(f.phone.last?.status == .enabled)
    }

    /// KTD10: a live setup session's typed overlay reaches the account; capability
    /// attention rides at provider level.
    @Test func attentionComesFromTheTypedMappingAndSessionOverlay() async throws {
        let (f, extras) = fixture()
        await f.store.refreshAll()
        f.store.companionSessionLookup = { key in
            key == extras[0].key ? CompanionSessionInput(state: .waiting(attempt: 1), purpose: .setup) : nil
        }
        f.store.setUsagePercentageMode(.used)
        #expect(accounts(f.phone.last).last?.attention == .finishingSignIn)
        #expect(accounts(f.phone.last).first?.attention == nil)
    }

    /// The coordinator knows a session's purpose but not its interactive reason, which the
    /// app chooses at staging. Without the app's lookup a startup-question launch would read
    /// on the phone as a workspace approval, because both are the `.trust` launch.
    @Test func theAppsInteractiveReasonTellsAStartupQuestionFromAnApproval() async throws {
        let (f, extras) = fixture()
        await f.store.refreshAll()
        let coordinator = SetupSessionCoordinator(
            scheduler: PhoneTriggerIgnoringScheduler(),
            prepare: { account, mode in .success(PreparedSetupHandoff(accountKey: account.key, mode: mode)) },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
        f.store.attachSetupCoordinator(coordinator)
        coordinator.restoreActiveHandoff(extras[0].key, purpose: .trust)

        f.store.setUsagePercentageMode(.used)
        #expect(accounts(f.phone.last).last?.attention == .workspaceApproval)

        f.store.companionInteractiveReasonLookup = { key in
            key == extras[0].key ? .startupQuestion : nil
        }
        f.store.setUsagePercentageMode(.remaining)
        #expect(accounts(f.phone.last).last?.attention == .setupScreenUnknown)
    }

    /// The facade stamps a strictly increasing, persisted generation on the main actor.
    @Test func theFacadeStampsIncreasingPersistedGenerations() async throws {
        let defaults = freshDefaults()
        let lineage = CompanionLineage(defaults: defaults)
        let source = lineage.sourceID
        #expect(UUID(uuidString: source) != nil && source == source.lowercased())
        #expect(CompanionLineage(defaults: defaults).sourceID == source)
        let first = lineage.nextGeneration()
        let second = CompanionLineage(defaults: defaults).nextGeneration()
        #expect(second == first + 1)
    }
}

@MainActor
private final class PhoneTriggerIgnoringScheduler: SetupRetryScheduling {
    private final class Cancellation: SetupRetryCancellation {
        func cancel() {}
    }

    func schedule(
        after _: Duration,
        operation _: @escaping @MainActor @Sendable () -> Void
    ) -> any SetupRetryCancellation {
        Cancellation()
    }
}
