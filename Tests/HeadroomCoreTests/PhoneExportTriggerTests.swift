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

    private func live(
        _ id: ProviderID, used: Double, at: Date = Date(timeIntervalSince1970: 2_000_000), email: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .weekly, utilization: used, resetsAt: reset)],
            planLabel: "Max", accountEmail: email, capturedAt: at, freshness: .live)
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

    /// KTD9 amended (Nov 2026): "Use email as account name" changes the phone's titles, so
    /// toggling it exports, and the changed titles are a structural change that forces the
    /// publisher's immediate flush (KTD8). A newly captured email reaches the phone the same
    /// way while the setting is on.
    @Test func useEmailAsAccountNameExportsAndForcesAnImmediateFlush() async throws {
        let defaults = freshDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let work = try #require(registry.addAccount(for: .claude, label: "Work"))
        let preferences = Preferences(defaults: defaults)
        preferences.syncToIPhoneEnabled = true
        let phone = SpyPhoneSync()
        let main = EmailMutableProvider(accountID: .primary, snapshot: live(.claude, used: 30))
        let extra = EmailMutableProvider(accountID: work.id, snapshot: live(.claude, used: 50))
        let store = UsageStore(
            providers: [main, extra], preferences: preferences, accountRegistry: registry,
            accountStorage: DemoAccountStorage(), widgetExporter: SpyWidgetExporter(), phoneSyncExporter: phone)
        main.set(live(.claude, used: 30, email: "main@example.com"))
        await store.refreshAll()
        let off = try #require(phone.last)
        #expect(accounts(off).map(\.title) == ["Main", "Work"])

        var count = phone.captures.count
        store.setUseEmailAsAccountName(true)
        #expect(phone.captures.count == count + 1)
        let on = try #require(phone.last)
        // The extra has no captured email yet, so it keeps its label, as on the Mac.
        #expect(accounts(on).map(\.title) == ["main@example.com", "Work"])
        #expect(on.structure != off.structure)

        // A setter echo is not a change.
        count = phone.captures.count
        store.setUseEmailAsAccountName(true)
        #expect(phone.captures.count == count)

        // A newly captured email reaches the phone as the title, structurally.
        extra.set(live(.claude, used: 50, email: "work@example.com"))
        await store.refreshAccount(work.key)
        let captured = try #require(phone.last)
        #expect(accounts(captured).map(\.title) == ["main@example.com", "work@example.com"])
        #expect(captured.structure != on.structure)

        count = phone.captures.count
        store.setUseEmailAsAccountName(false)
        #expect(phone.captures.count == count + 1)
        let back = try #require(phone.last)
        #expect(accounts(back).map(\.title) == ["Main", "Work"])
        #expect(back.structure != captured.structure)
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

    /// OpenCode plan U8 (KTD16): the OpenCode subscription switch exports like every other
    /// provider's, and a no-Go account (KTD7) reaches the phone capture named "No Go plan".
    @Test func theOpenCodeSwitchExportsAndANoGoAccountReachesThePhoneAsNoGoPlan() async throws {
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.syncToIPhoneEnabled = true
        let phone = SpyPhoneSync()
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: live(.claude, used: 20)),
                DemoUsageProvider(id: .opencode, displayName: "OpenCode", snapshot: OpenCodePhoneFixture.noGo()),
            ],
            preferences: preferences, phoneSyncExporter: phone)
        var count = phone.captures.count
        store.setSurfaceEnabled(true, for: .opencodeSubscription)
        #expect(phone.captures.count == count + 1)
        await store.refreshAll()
        let opencode = try #require(phone.last?.providers.first { $0.providerID == "opencode" })
        #expect(opencode.mainAccount?.planName == "No Go plan")
        #expect(opencode.mainAccount?.windows.map(\.freshness) == [.unavailable])
        #expect(phone.last?.providerOrder == ["claude", "opencode"])
        let v3 = try #require(phone.last?.v3.providers.first { $0.id == "opencode" })
        #expect(v3.planLabel == "No Go plan")

        count = phone.captures.count
        store.setSurfaceEnabled(false, for: .opencodeSubscription)
        #expect(phone.captures.count == count + 1)
        #expect(phone.last?.providerOrder == ["claude"])
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

    // MARK: Remembered accounts (default-login plan U7, U9)

    private let accountA = "aaaaaaaa-0000-4000-8000-000000000001"
    private let accountB = "bbbbbbbb-0000-4000-8000-000000000002"

    /// The remembered rows' one choke point exports once per appear, rename and remove;
    /// an appearance inside a merge rides the merge's own export, and the capture carries
    /// the row (U9).
    @Test func aRememberedAccountAppearingRenamedOrRemovedExportsOnce() async throws {
        let rig = DefaultLoginRig(countsPhoneExports: true)
        let phone = try #require(rig.phone)
        await rig.read(rig.reading(accountA))
        rig.advance(120)

        rig.primary.set(rig.reading(accountB))
        var count = phone.captures.count
        await rig.store.refreshAccount(rig.key)
        let work = try #require(rig.store.rememberedAccounts(for: .codex).first).key
        #expect(phone.captures.count == count + 1)
        #expect(accounts(phone.last, "codex").map(\.isRemembered) == [false, true])

        count = phone.captures.count
        #expect(rig.store.renameRememberedAccount(work, to: "Work"))
        #expect(phone.captures.count == count + 1)
        #expect(accounts(phone.last, "codex").last?.title == "Work")

        count = phone.captures.count
        #expect(rig.store.removeRememberedAccount(work))
        #expect(phone.captures.count == count + 1)
        #expect(accounts(phone.last, "codex").count == 1)

        // A full refresh after the change still exports once, at its end.
        count = phone.captures.count
        await rig.store.refreshAll()
        #expect(phone.captures.count == count + 1)
    }

    /// U9 step 5: a row that retires (its account returns as the default login, or an extra
    /// signs in to it) and a hidden row that comes back each export once.
    @Test func aRememberedAccountRetiringOrComingBackExportsOnce() async throws {
        let rig = DefaultLoginRig(extraLabels: ["Side"], countsPhoneExports: true)
        let phone = try #require(rig.phone)
        let side = rig.extras[0]
        side.set(rig.reading("side"))
        await rig.read(rig.reading(accountA))
        rig.advance(120)
        await rig.read(rig.reading(accountB))
        #expect(rig.store.rememberedAccounts(for: .codex).count == 1)

        // Retire: an extra signs in to the remembered account, so the row yields to it.
        rig.advance(120)
        side.set(rig.reading(accountA))
        var count = phone.captures.count
        await rig.store.refreshAccount(side.accountKey)
        #expect(rig.store.rememberedAccounts(for: .codex).isEmpty)
        #expect(phone.captures.count == count + 1)
        #expect(accounts(phone.last, "codex").contains { $0.isRemembered } == false)

        // Unhide: removing that extra brings the row back.
        count = phone.captures.count
        #expect(await rig.store.removeAccount(side.accountKey) == .removed)
        #expect(rig.store.rememberedAccounts(for: .codex).count == 1)
        #expect(phone.captures.count == count + 1)
        #expect(accounts(phone.last, "codex").map(\.isRemembered) == [false, true])

        // Retire by return: A is the default login again. Its row retires and B's appears,
        // one change and one export.
        rig.advance(120)
        rig.primary.set(rig.reading(accountA))
        count = phone.captures.count
        await rig.store.refreshAccount(rig.key)
        #expect(rig.store.rememberedAccounts(for: .codex).map(\.email) == ["\(accountB)@example.com"])
        #expect(phone.captures.count == count + 1)

        // A hidden row reappears once its account is the default login and leaves again.
        let bRow = try #require(rig.store.rememberedAccounts(for: .codex).first).key
        #expect(rig.store.removeRememberedAccount(bRow))
        rig.advance(120)
        rig.primary.set(rig.reading(accountB))
        await rig.store.refreshAccount(rig.key)
        rig.advance(120)
        rig.primary.set(rig.reading(accountA))
        count = phone.captures.count
        await rig.store.refreshAccount(rig.key)
        #expect(rig.store.rememberedAccounts(for: .codex).map(\.key) == [bRow])
        #expect(phone.captures.count == count + 1)
    }

    /// U9 steps 2–3 and R12, R17: remembered rows follow the engine rows as flagged extras
    /// under their random local ids, carry their last reading and no attention, and the
    /// bytes hold no identity digest, upstream id or email.
    @Test func theCaptureCarriesRememberedRowsAsFlaggedExtrasWithoutIdentity() async throws {
        let rig = DefaultLoginRig(countsPhoneExports: true)
        let phone = try #require(rig.phone)
        await rig.read(rig.reading(accountA, weeklyUsed: 90))
        rig.store.renameAccount(rig.key, to: "Work")
        let workRead = rig.clock.now()
        rig.advance(120)
        await rig.read(rig.reading(accountB, weeklyUsed: 3))

        let row = try #require(rig.store.rememberedAccounts(for: .codex).first)
        let codex = accounts(phone.last, "codex")
        #expect(codex.map(\.title) == ["Main", "Work"])
        let main = try #require(codex.first), work = try #require(codex.last)
        #expect(main.isRemembered == false)
        #expect(work.isRemembered)
        #expect(work.id == row.id.raw)
        #expect(UUID(uuidString: work.id) != nil)
        #expect(work.freshness == .stale)
        #expect(work.needsAttention == false)
        #expect(work.attention == nil)
        #expect(work.capturedAt?.date == workRead)
        #expect(work.windows.map(\.freshness) == [.stale, .stale])
        #expect(work.windows.last?.percentRemaining == 10)
        let provider = try #require(phone.last?.providers.first { $0.providerID == "codex" })
        #expect(provider.capabilityAttention == nil)

        let encoded = try codex.map { String(decoding: try CompanionSyncCodec.encode($0), as: UTF8.self) }.joined()
            + String(decoding: try JSONEncoder().encode(try #require(phone.last?.v3)), as: UTF8.self)
        for banned in [
            DefaultLoginRig.identity(accountA).digest, DefaultLoginRig.identity(accountB).digest,
            accountA, accountB, "@", "example.com",
        ] {
            #expect(!encoded.contains(banned), "\(banned)")
        }
        #expect(!work.id.contains(DefaultLoginRig.identity(accountA).digest.prefix(8)))

        // With "Use email as account name" on, the email reaches the phone only as the title.
        rig.store.setUseEmailAsAccountName(true)
        let titled = accounts(phone.last, "codex")
        #expect(titled.map(\.title) == ["\(accountB)@example.com", "\(accountA)@example.com"])
        let bytes = try titled.map { String(decoding: try CompanionSyncCodec.encode($0), as: UTF8.self) }.joined()
        #expect(bytes.components(separatedBy: "@example.com").count - 1 == 2)
        #expect(bytes.components(separatedBy: "\"t\":\"").count - 1 == 2)
        for digest in [DefaultLoginRig.identity(accountA).digest, DefaultLoginRig.identity(accountB).digest] {
            #expect(!bytes.contains(digest))
        }
    }

    /// R15: with no remembered row the account bytes are what a build before U9 wrote — no
    /// flag key — so a Mac whose default login never changes rewrites nothing.
    @Test func aCaptureWithNoRememberedRowWritesThePreU9Bytes() async throws {
        let rig = DefaultLoginRig(extraLabels: ["Side"], countsPhoneExports: true)
        let phone = try #require(rig.phone)
        rig.extras[0].set(.stale(for: .codex, reason: .transient("blip")))
        await rig.read(rig.reading(accountA))
        let codex = accounts(phone.last, "codex")
        #expect(codex.count == 2)
        #expect(codex.allSatisfy { !$0.isRemembered })
        for account in codex {
            let json = try #require(
                try JSONSerialization.jsonObject(with: CompanionSyncCodec.encode(account)) as? [String: Any])
            #expect(Set(json.keys).isSubset(of: ["i", "t", "p", "f", "c", "a", "h", "b", "w"]))
        }
        // A stale, attention-carrying extra encodes to the exact pre-U9 literal.
        let summary = try CompanionAccountSummary(
            id: "side", title: "Side", freshness: .stale, capturedAt: CompanionWireDate(epochSeconds: 1_790_000_000),
            attention: .retrying, needsAttention: false, windows: [])
        #expect(String(decoding: try CompanionSyncCodec.encode(summary), as: UTF8.self)
            == #"{"a":"retrying","c":1790000000,"f":"stale","h":false,"i":"side","t":"Side","w":[]}"#)
    }

    /// U9 step 4: after the default login changes, the Mac widget file and the v3 key show
    /// the new account on the built-in row — the display primary — never the remembered one.
    @Test func theMacWidgetAndV3KeyFollowTheDisplayPrimaryAfterASwitch() async throws {
        let rig = DefaultLoginRig(countsPhoneExports: true)
        let phone = try #require(rig.phone)
        await rig.read(rig.reading(accountA, weeklyUsed: 90))
        func weeklyLeft(_ envelope: WidgetSnapshotEnvelope?) -> Double? {
            envelope?.providers.first { $0.id == "codex" }?.windows.first { $0.kind == .weekly }?.percentRemaining
        }
        #expect(weeklyLeft(rig.widgets.exports.last) == 10)
        #expect(weeklyLeft(phone.last?.v3) == 10)

        rig.advance(120)
        await rig.read(rig.reading(accountB, weeklyUsed: 3))
        #expect(rig.store.rememberedAccounts(for: .codex).count == 1)
        #expect(rig.store.displayPrimaryKey(for: .codex) == rig.key)
        #expect(weeklyLeft(rig.widgets.exports.last) == 97)
        #expect(weeklyLeft(phone.last?.v3) == 97)
        #expect(phone.last?.v3.providers.filter { $0.id == "codex" }.count == 1)
        #expect(accounts(phone.last, "codex").first?.windows.last?.percentRemaining == 97)
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

    /// Default-login U10: the one-row merge and its end each reach the widgets and the
    /// phone once. Both come from the built-in's own reading outside a full refresh, which
    /// moves the display primary: to "Account 2" on the merge, back to the built-in on the
    /// unmerge.
    @Test func theOneRowMergeAndItsEndExportOnceEach() async throws {
        let rig = DefaultLoginRig(extraLabels: ["Account 2"], countsPhoneExports: true)
        let phone = try #require(rig.phone)
        let extra = AccountKey(providerID: .codex, accountID: AccountID("account 2"))
        rig.extras[0].set(rig.reading("gmail"))
        await rig.read(rig.reading("work"))
        #expect(rig.store.displayPrimaryKey(for: .codex) == rig.key)

        rig.advance(120)
        rig.primary.set(rig.reading("gmail"))
        var (captures, widgets) = (phone.captures.count, rig.widgets.exports.count)
        await rig.store.refreshAccount(rig.key)
        #expect(rig.store.displayPrimaryKey(for: .codex) == extra)
        #expect(phone.captures.count == captures + 1)
        #expect(rig.widgets.exports.count == widgets + 1)

        rig.advance(120)
        rig.primary.set(rig.reading("c"))
        (captures, widgets) = (phone.captures.count, rig.widgets.exports.count)
        await rig.store.refreshAccount(rig.key)
        #expect(rig.store.displayPrimaryKey(for: .codex) == rig.key)
        #expect(phone.captures.count == captures + 1)
        #expect(rig.widgets.exports.count == widgets + 1)
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

/// A Claude account double whose snapshot (and so its captured email) can change between
/// refreshes.
private final class EmailMutableProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .claude
    let accountID: AccountID
    let displayName = "Claude"
    private let lock = NSLock()
    private var snapshot: UsageSnapshot

    init(accountID: AccountID, snapshot: UsageSnapshot) {
        self.accountID = accountID
        self.snapshot = snapshot
    }

    func set(_ snapshot: UsageSnapshot) { lock.withLock { self.snapshot = snapshot } }
    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { snapshot } }
}
