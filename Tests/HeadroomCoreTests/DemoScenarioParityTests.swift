import Foundation
import Testing
@testable import HeadroomCore

struct DemoScenarioParityTests {
    @Test func iOSDemoCoversCurrentMacScenario() {
        let ios = DemoScreenshotData.envelope(for: "full")
        let projected = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: DemoFixture.claudeSnapshot,
                .codex: DemoFixture.codexSnapshot,
            ],
            providerOrder: [.claude, .codex],
            displayNames: [.claude: "Claude", .codex: "Codex"],
            renewalDate: DemoFixture.renewalDate,
            widgetsEnabled: true,
            apiSpendSnapshots: [
                .claude: DemoFixture.anthropicSpend,
                .codex: DemoFixture.openAISpend,
            ],
            apiSpendProviderOrder: [.claude, .codex]
        )

        #expect(providerSignature(ios) == providerSignature(projected))
        #expect(spendSignature(ios) == spendSignature(projected))
    }

    @Test func iOSDemoIncludesEveryReviewableSection() {
        let envelope = DemoScreenshotData.envelope(for: "full")

        #expect(envelope.status == .enabled)
        #expect(envelope.providers.map(\.id) == [ProviderID.claude.raw, ProviderID.codex.raw])
        #expect(envelope.apiSpendProviders.map(\.id) == [ProviderID.claude.raw, ProviderID.codex.raw])
        #expect(envelope.providers.first?.windows.contains {
            $0.kind == .other("Weekly (Fable)") && $0.roundedPercentRemaining == 54
        } == true)
    }

    /// U12, Copilot plan U7: the five-provider demo envelope's provider list equals the
    /// registry order, so a screenshot/QA scenario exercises every registered provider rather
    /// than a literal. The four-provider envelope stays the registry without Copilot.
    @Test func fiveProviderDemoEnvelopeCoversTheRegistry() {
        let envelope = DemoScreenshotData.envelope(for: "fiveProviders")
        #expect(envelope.status == .enabled)
        #expect(envelope.providers.map(\.id) == DemoFixture.registeredProviderOrder.map(\.raw))
        #expect(DemoScreenshotData.envelope(for: "fourProviders").providers.map(\.id)
            == DemoFixture.registeredProviderOrder.filter { $0 != .copilot }.map(\.raw))
        let copilot = envelope.providers.first { $0.id == ProviderID.copilot.raw }
        #expect(copilot?.planLabel == nil)
        #expect(copilot?.windows.map(\.label) == ["Monthly"])
        #expect(copilot?.windows.first?.isBillingPeriod == true)
        #expect(copilot?.windows.first?.displayPercentRemaining == 76)
        // Grok/Cursor bill as period pools, which project to `.other` widget windows.
        let grok = envelope.providers.first { $0.id == ProviderID.grok.raw }
        let cursor = envelope.providers.first { $0.id == ProviderID.cursor.raw }
        #expect(grok?.windows.first?.label == "Weekly")
        #expect(grok?.windows.first?.isBillingPeriod == true)
        #expect(grok?.windows.first?.displayPercentRemaining == 56)
        #expect(grok?.primarySubscriptionWindow != nil)
        #expect(cursor?.windows.map(\.label) == ["Cursor Models", "Other Models"])
        #expect(cursor?.windows.allSatisfy(\.isBillingPeriod) == true)
        #expect(cursor?.windows.map(\.displayPercentRemaining) == [69, 37])
        #expect(cursor?.primarySubscriptionWindow?.label == "Other Models")
    }

    @Test func encodedIOSDemoContainsNoSensitiveSentinels() throws {
        let encoded = try JSONEncoder().encode(DemoScreenshotData.envelope(for: "full"))
        let text = String(decoding: encoded, as: UTF8.self).lowercased()

        for forbidden in [
            "bearer ",
            "api_key",
            "access_token",
            "auth.json",
            "claude code-credentials",
            "/users/",
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    // MARK: - v4 demo variants against the Mac `--demo` scenarios (U7, KTD21)

    /// Each phone variant and the Mac scenario that poses the same moment.
    private static let macScenarios: [(CompanionDemoVariant, DemoFixture.MultiAccountScenario)] = [
        (.multiAccount, .multiThree),
        (.fourProviders, .multiProviders),
        (.fiveProviders, .fiveProviders),
        (.bankedResets, .bankedResets),
        (.multi20, .envelope),
    ]

    /// Demo phone numbers match the Mac `--demo` numbers: every account, in order, with the
    /// Mac projector's window kinds, labels, normalized values, severities and reset offsets,
    /// plan labels in display form and banked resets. Rows the Mac scenario lacks are only
    /// Claude's unified Fable row (held to the bare `--demo` snapshot below) and flagged
    /// Spark rows (the Mac's in-app switch, KTD11).
    @Test func v4VariantsMatchTheMacDemoScenarios() async throws {
        for (variant, scenario) in Self.macScenarios {
            let now = Date()
            let content = try #require(CompanionDemoData.snapshot(variant, now: now).content, "\(variant)")
            let fixture = DemoFixture.multiFixture(for: scenario)
            var mac: [(ProviderAccount, UsageSnapshot)] = []
            for (account, provider) in zip(fixture.accounts, fixture.providers) {
                mac.append((account, await provider.fetchSnapshot()))
            }
            let phone = content.providers.flatMap { provider in provider.accounts.map { (provider.id, $0) } }
            #expect(phone.count == mac.count, "\(variant)")
            #expect(phone.map(\.0) == mac.map(\.0.providerID.raw), "\(variant)")
            for ((providerID, account), (macAccount, snapshot)) in zip(phone, mac) {
                let context = "\(variant) \(providerID) \(account.title)"
                #expect(account.accountID == macAccount.id.raw, "\(context)")
                #expect(account.title == expectedTitle(macAccount), "\(context)")
                #expect(account.planName == PlanLabelPresentation.displayName(snapshot.planLabel), "\(context)")
                #expect(account.bankedResets == snapshot.bankedResets, "\(context)")
                let phoneRows = account.windows.filter { !$0.isSpark && !isFable($0.summary) }.map(\.summary)
                expectSameRows(phoneRows, macRows(snapshot, providerID: providerID), now: now, context)
            }
        }
    }

    /// The unified Fable value and Claude Personal's numbers equal the bare `--demo` snapshot,
    /// and the multi-account spend rows equal the Mac's demo spend. Reset times follow the
    /// Mac's multi-account scenarios, which pose 3.2 hours and 4 days.
    @Test func multiAccountMatchesTheBareDemoClaudeAndSpend() throws {
        let now = Date()
        let content = try #require(CompanionDemoData.snapshot(.multiAccount, now: now).content)
        let claude = try #require(content.providers.first?.mainAccount)
        #expect(claude.widgetWindows.map(RowSignature.init)
            == macRows(DemoFixture.claudeSnapshot, providerID: "claude").map(RowSignature.init))
        #expect(claude.widgetWindows.first(where: isFable)?.roundedPercentRemaining == 54)

        let projected = WidgetSnapshotProjector.project(
            snapshots: [:], providerOrder: [], displayNames: [:], renewalDate: { _ in nil },
            widgetsEnabled: true,
            apiSpendSnapshots: [.claude: DemoFixture.anthropicSpend, .codex: DemoFixture.openAISpend],
            apiSpendProviderOrder: [.claude, .codex])
        #expect(content.apiSpend.map(\.id) == projected.apiSpendProviders.map(\.id))
        #expect(content.apiSpend.map(\.displayName) == projected.apiSpendProviders.map(\.displayName))
        #expect(content.apiSpend.map(\.amount) == projected.apiSpendProviders.map(\.amount))
        #expect(content.apiSpend.map(\.currency) == projected.apiSpendProviders.map(\.currency))
        #expect(content.apiSpend.map(\.periodLabel) == projected.apiSpendProviders.map(\.periodLabel))
    }

    /// KTD13 shape: the widget envelope the phone builds from each demo variant carries main
    /// accounts only, in provider order, with the same rows the app shows for those mains.
    @Test(arguments: CompanionDemoVariant.allCases)
    func primaryProjectionCarriesMainAccountsOnly(_ variant: CompanionDemoVariant) throws {
        let snapshot = CompanionDemoData.snapshot(variant, now: Date())
        guard let content = snapshot.content else {
            #expect(snapshot.primaryProjection() == nil)
            return
        }
        let envelope = try #require(snapshot.primaryProjection())
        #expect(envelope.providers.map(\.id) == content.providers.map(\.id))
        for (summary, provider) in zip(envelope.providers, content.providers) {
            let main = try #require(provider.mainAccount)
            #expect(summary.planLabel == main.planName)
            let shown = main.windows.filter { !$0.isSpark || content.widgetSparkEnabled }.map(\.summary)
            #expect(summary.windows == shown)
        }
    }

    /// Default-login U11 (R20: Claude and Codex both get remembered rows): the `remembered`
    /// scenario poses the same moment for each, so a render or a review of one provider
    /// stands for the other. Same labels, kinds, window kinds, numbers and states;
    /// no other provider is posed.
    @MainActor
    @Test func rememberedScenarioPosesClaudeAndCodexAlike() async throws {
        let fixture = DemoFixture.multiFixture(for: .remembered)
        let suite = "headroom.demo-parity.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = UsageStore(
            providers: fixture.providers,
            preferences: Preferences(defaults: defaults),
            accounts: fixture.accounts,
            defaultLoginRecords: fixture.makeDefaultLoginRecordStore()
        )
        await store.refreshAll()
        #expect(store.registeredProviderOrder == [.claude, .codex])

        func signature(_ providerID: ProviderID) -> [RememberedRowSignature] {
            store.displayAccounts(for: providerID).map { row in
                let snapshot = store.snapshot(for: row.key)
                return RememberedRowSignature(
                    label: row.label,
                    kind: row.kind,
                    windows: snapshot.windows.map { window in
                        let state = window.freshness.isLive ? "live" : window.freshness.isUnavailable ? "unavailable" : "stale"
                        let number = window.freshness.isUnavailable
                            ? nil : UsagePercentageMode.remaining.roundedPercentage(for: window)
                        return "\(window.kind.shortLabel) \(state) \(number.map(String.init) ?? "—")"
                    }
                )
            }
        }
        let claude = signature(.claude)
        #expect(claude.count == 3)
        #expect(claude == signature(.codex))
        #expect(claude.map(\.kind) == [.engine, .remembered, .remembered])
        #expect(claude[1].windows.allSatisfy { $0.contains(" stale ") })
        #expect(claude[2].windows.allSatisfy { $0.hasSuffix("unavailable —") })
    }

    private func isFable(_ window: WidgetWindowSummary) -> Bool { window.kind == .other("Weekly (Fable)") }

    /// KTD9: the phone title is the user's label; a built-in Grok/Cursor row carries the
    /// provider name as its label on the Mac.
    private func expectedTitle(_ account: ProviderAccount) -> String { account.label }

    /// The Mac's own projection of one account: the production `WidgetSnapshotProjector`.
    private func macRows(_ snapshot: UsageSnapshot, providerID: String) -> [WidgetWindowSummary] {
        let id = ProviderID(providerID)
        return WidgetSnapshotProjector.project(
            snapshots: [id: snapshot], providerOrder: [id], displayNames: [id: id.displayName],
            renewalDate: { _ in nil }, widgetsEnabled: true
        ).providers.first?.windows ?? []
    }

    /// Same kinds, labels, normalized values and severities, and the same reset offsets
    /// from `now` within a few seconds: the Mac fixtures read the wall clock a moment later,
    /// and the wire floors to whole seconds.
    private func expectSameRows(
        _ phone: [WidgetWindowSummary], _ mac: [WidgetWindowSummary], now: Date, _ context: String
    ) {
        #expect(phone.map(RowSignature.init) == mac.map(RowSignature.init), "\(context)")
        #expect(phone.count == mac.count, "\(context)")
        for (a, b) in zip(phone, mac) {
            guard case .scheduled(let phoneReset) = a.resetSchedule, case .scheduled(let macReset) = b.resetSchedule else {
                Issue.record("\(context) \(a.label) reset is not scheduled on both")
                continue
            }
            #expect(abs(phoneReset.timeIntervalSince(macReset)) <= 5, "\(context) \(a.label)")
        }
    }

    private func providerSignature(_ envelope: WidgetSnapshotEnvelope) -> [ProviderSignature] {
        envelope.providers.map { provider in
            ProviderSignature(
                id: provider.id,
                displayName: provider.displayName,
                planLabel: provider.planLabel,
                freshness: provider.freshness,
                windows: provider.windows.map {
                    WindowSignature(
                        kind: $0.kind,
                        label: $0.label,
                        percentRemaining: $0.roundedPercentRemaining,
                        resetLabel: $0.resetLabel,
                        severity: $0.severity
                    )
                }
            )
        }
    }

    private func spendSignature(_ envelope: WidgetSnapshotEnvelope) -> [SpendSignature] {
        envelope.apiSpendProviders.map {
            SpendSignature(
                id: $0.id,
                displayName: $0.displayName,
                amount: $0.amount,
                currency: $0.currency,
                periodLabel: $0.periodLabel,
                freshness: $0.freshness
            )
        }
    }
}

private struct ProviderSignature: Equatable {
    let id: String
    let displayName: String
    let planLabel: String?
    let freshness: WidgetProviderFreshness
    let windows: [WindowSignature]
}

private struct WindowSignature: Equatable {
    let kind: WidgetWindowKind
    let label: String
    let percentRemaining: Int
    let resetLabel: String?
    let severity: WidgetUsageSeverity
}

private struct SpendSignature: Equatable {
    let id: String
    let displayName: String
    let amount: Double?
    let currency: String?
    let periodLabel: String
    let freshness: WidgetProviderFreshness
}

private struct RememberedRowSignature: Equatable {
    let label: String
    let kind: DisplayAccountKind
    let windows: [String]
}

private struct RowSignature: Equatable {
    let kind: WidgetWindowKind
    let label: String
    let percent: Int
    let severity: WidgetUsageSeverity
    let isBillingPeriod: Bool

    init(_ window: WidgetWindowSummary) {
        kind = window.kind
        label = window.label
        percent = window.roundedPercentRemaining
        severity = window.severity
        isBillingPeriod = window.isBillingPeriod
    }
}
