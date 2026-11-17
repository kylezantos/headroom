import Testing
import Foundation
@testable import HeadroomCore

struct DemoFixtureTests {
    @Test func claudeDemoSnapshotIncludesFableAllotment() {
        #expect(DemoFixture.claudeSnapshot.windows.contains {
            $0.kind == .other("Weekly (Fable)")
        })
    }

    private func remaining(_ snapshot: UsageSnapshot, _ kind: WindowKind) -> Int? {
        snapshot.windows.first { $0.kind == kind }
            .map { UsagePercentageMode.remaining.roundedPercentage(for: $0) }
    }

    /// The locked hero scenario (KTD5): Claude 5-hour 72% / Weekly 38% / Fable 54% left.
    @Test func claudeDemoMatchesHeroScenario() {
        let claude = DemoFixture.claudeSnapshot
        #expect(remaining(claude, .fiveHour) == 72)
        #expect(remaining(claude, .weekly) == 38)
        #expect(remaining(claude, .other("Weekly (Fable)")) == 54)
    }

    /// Codex Jul 2026 reality: weekly only (no 5-hour gate), 36% used = 64% left.
    @Test func codexDemoMatchesCurrentReality() {
        let codex = DemoFixture.codexSnapshot
        #expect(remaining(codex, .weekly) == 64)
        // Codex has no 5-hour window in current reality
        #expect(remaining(codex, .fiveHour) == nil)
    }

    /// The popover renders reset text from `resetsAt` via `Countdown.resetText`, NOT
    /// `resetLabel` (KTD5). Assert the computed relative durations match the artboard.
    /// The fixture's `soon(...)` buffer keeps truncation on the intended value.
    @Test func demoResetTextMatchesArtboard() {
        let now = Date()
        func resetText(_ snapshot: UsageSnapshot, _ kind: WindowKind) -> String? {
            snapshot.windows.first { $0.kind == kind }
                .map { Countdown.resetText(for: $0, now: now) }
        }
        #expect(resetText(DemoFixture.claudeSnapshot, .weekly) == "Resets in 4d")
        #expect(resetText(DemoFixture.claudeSnapshot, .fiveHour) == "Resets in 3h 15m")
        #expect(resetText(DemoFixture.claudeSnapshot, .other("Weekly (Fable)")) == "Resets in 4d")
        #expect(resetText(DemoFixture.codexSnapshot, .weekly) == "Resets in 6d 4h")
    }

    // MARK: - `--demo` scenario parsing (demo mode, Jul 2026)

    @Test func bareDemoRequestsSingleAccountFixtures() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo"]) == .singleAccount)
        // A following flag is not a scenario token — still a bare demo.
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "--verbose"]) == .singleAccount)
    }

    @Test func absentDemoFlagIsNotRequested() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom"]) == .notRequested)
    }

    @Test func knownScenarioTokensResolve() {
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            #expect(
                DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", scenario.rawValue])
                    == .multiAccount(scenario)
            )
        }
    }

    @Test func unknownScenarioTokenIsInvalid() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "multi-9"]) == .invalid("multi-9"))
    }

    @Test func multiFixtureAccountCountsMatchScenario() {
        #expect(DemoFixture.multiFixture(for: .multiTwo).accounts.count == 3)   // 2 Claude + 1 Codex
        #expect(DemoFixture.multiFixture(for: .multiThree).accounts.count == 5)
        #expect(DemoFixture.multiFixture(for: .multiFive).accounts.count == 8)  // 5 Claude + 3 Codex (past the old cap for scroll)
        #expect(DemoFixture.multiFixture(for: .multiSeven).accounts.count == 8)  // 7 Claude + 1 Codex (popover columns)
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "multi-7"]) == .multiAccount(.multiSeven))
        // R15: the tested envelope — 20 Claude, 20 Codex, 20 Grok, 1 Cursor, 1 Copilot, every
        // key unique.
        let envelope = DemoFixture.multiFixture(for: .envelope)
        #expect(envelope.accounts.count == 62)
        #expect(Set(envelope.accounts.map(\.key)).count == 62)
        #expect(envelope.accounts.filter { $0.providerID == .claude }.count == AccountRegistry.testedEnvelope)
        #expect(envelope.accounts.filter { $0.providerID == .cursor }.count == 1)
        #expect(envelope.accounts.filter { $0.providerID == .copilot }.count == 1)
        #expect(envelope.accounts.filter(\.isBuiltIn).count == 5)
        #expect(DemoFixture.settledEnvelopePairs().map(\.account.key) == envelope.accounts.map(\.key))
        // The generator's five-row shape matches the hand-authored scenario's fields.
        let generated = DemoFixture.generatedAccounts(provider: .claude, count: 5)
        #expect(generated.count == 5)
        #expect(generated.first?.account.isBuiltIn == true)
        #expect(Set(generated.map(\.account.label)).count == 5)
        // S2B/B3: 3 Claude + 1 Codex — the third Claude row poses the typed
        // `.claudeLoginRequired` outcome, the only state with a two-chip action row.
        #expect(DemoFixture.multiFixture(for: .multiMixed).accounts.count == 5)
        #expect(DemoFixture.multiFixture(for: .multiProviders).accounts.count == 4)  // one built-in per provider
        #expect(DemoFixture.multiFixture(for: .fourDefault).accounts.count == 4)
        #expect(DemoFixture.multiFixture(for: .duplicateLabels).accounts.count == 4)
        // S5A: reuses multi-4's accounts — only the spend snapshots beside them differ.
        #expect(DemoFixture.multiFixture(for: .spendStates).accounts.count == 4)
        // R2B2: one Claude account posing the partial capture, one Codex account beside it.
        #expect(DemoFixture.multiFixture(for: .windowUnavailable).accounts.count == 2)
        #expect(DemoFixture.multiFixture(for: .bankedResets).accounts.count == 4)
        #expect(DemoFixture.multiFixture(for: .fiveProviders).accounts.count == 5)
        #expect(DemoFixture.multiFixture(for: .copilotNoReading).accounts.count == 2)
        #expect(DemoFixture.multiFixture(for: .sixProviders).accounts.count == DemoFixture.registeredProviderOrder.count)
        #expect(DemoFixture.multiFixture(for: .opencodeNoGo).accounts.count == 2)
        #expect(DemoFixture.multiFixture(for: .opencodeUpdate).accounts.count == 2)
        #expect(DemoFixture.multiFixture(for: .opencodeLimited).accounts.count == 3)
        // Default-login U11: the engine holds only each provider's live default; the two
        // remembered rows per provider come from the record store.
        #expect(DemoFixture.multiFixture(for: .remembered).accounts.count == 2)
        // U10: each provider's built-in and "Account 2"; the built-in is merged away.
        #expect(DemoFixture.multiFixture(for: .merged).accounts.count == 4)
        // Provider instances are 1:1 with accounts.
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            let fixture = DemoFixture.multiFixture(for: scenario)
            #expect(fixture.providers.count == fixture.accounts.count)
        }
    }

    /// The banked-resets demo poses every capsule state and keeps the count off every other scenario.
    @Test func bankedResetsScenarioPosesCountsAndOneCriticalWindow() async {
        let fixture = DemoFixture.multiFixture(for: .bankedResets)
        let byAccount = Dictionary(uniqueKeysWithValues: fixture.accounts.map { ($0.key, $0.label) })
        var labeled: [String: Int?] = [:]
        var criticalLabels: [String] = []
        for provider in fixture.providers {
            let snapshot = await provider.fetchSnapshot()
            let key = AccountKey(providerID: provider.id, accountID: provider.accountID)
            let label = byAccount[key] ?? ""
            labeled[label] = snapshot.bankedResets
            if snapshot.hasLiveCriticalResettableWindow { criticalLabels.append(label) }
        }
        #expect(labeled["Personal"]! == nil)
        #expect(labeled["Northwind Research Workspace"]! == 2)
        #expect(labeled["On call"]! == 1)
        #expect(labeled["Quiet"]! == 0)
        #expect(criticalLabels == ["On call"])

        for scenario in DemoFixture.MultiAccountScenario.allCases where scenario != .bankedResets {
            for provider in DemoFixture.multiFixture(for: scenario).providers {
                let snapshot = await provider.fetchSnapshot()
                #expect(snapshot.bankedResets == nil)
            }
        }
    }

    /// R2B2: the partial-capture fixture is the only place a `.unavailable` window sits under
    /// live ones, which is the layout the reserved suffix column exists for. The live rows
    /// keep their percentages; the retained row keeps its label and loses its number.
    @Test func partialCaptureFixturePosesAnUnavailableWindow() {
        let snapshot = DemoFixture.claudePartialCaptureSnapshot
        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows.filter { $0.freshness.isLive }.map(\.kind) == [.fiveHour, .weekly])

        guard let retained = snapshot.windows.first(where: { $0.kind == .other("Weekly (Fable)") }) else {
            Issue.record("expected the model row to be retained"); return
        }
        #expect(retained.freshness.isUnavailable)
        // The row outlives its number, so continuity's original observation anchor survives.
        #expect(retained.observedAt != nil)
    }

    /// The scenario has to actually carry that snapshot, or the `--demo` preview shows the
    /// ordinary all-live card and the reserved column has nothing to prove itself against.
    @Test func windowUnavailableScenarioCarriesThePartialCapture() {
        let fixture = DemoFixture.multiFixture(for: .windowUnavailable)
        #expect(fixture.accounts.map(\.providerID) == [.claude, .codex])
        #expect(fixture.accounts.map(\.isBuiltIn) == [true, true])
    }

    /// Grok bills a single weekly credit pool as a billing-period window (not Claude's
    /// rolling 5h/weekly pair), 44% used = 56% left.
    @Test func grokDemoSnapshotIsBillingPeriodWeekly() {
        let grok = DemoFixture.grokSnapshot
        #expect(grok.planLabel == "SuperGrok")
        #expect(grok.windows.count == 1)
        guard case .billingPeriod(let label, _)? = grok.windows.first?.kind else {
            Issue.record("expected a billing-period window"); return
        }
        #expect(label == "Weekly")
        #expect(remaining(grok, grok.windows[0].kind) == 56)
    }

    /// Cursor exposes two named monthly pools with one calendar reset. Unequal values make
    /// accidental collapsing, duplication, or reordering visible in screenshots and tests.
    @Test func cursorDemoSnapshotIncludesBothNamedBillingPools() {
        let cursor = DemoFixture.cursorSnapshot
        #expect(cursor.planLabel == "Pro+")
        #expect(cursor.windows.count == 2)
        #expect(cursor.windows.map(\.kind.shortLabel) == ["Cursor Models", "Other Models"])
        #expect(cursor.windows.map { remaining(cursor, $0.kind) } == [69, 37])
        #expect(cursor.windows.map(\.resetSchedule).allSatisfy { $0 == cursor.windows[0].resetSchedule })
        for window in cursor.windows {
            guard case .billingPeriod(_, let duration) = window.kind else {
                Issue.record("expected a billing-period window"); return
            }
            #expect(duration == 30 * 24 * 60 * 60)
        }
    }

    /// U12 parity, Copilot plan U7: the five-provider scenario's provider list equals the
    /// registry order. `multi-4` keeps the four providers before Copilot, because its spend
    /// variants pose four API rows and `multi-5` already means five accounts.
    /// OpenCode plan U9 (KTD14): `five-providers` stays the five providers before OpenCode.
    @Test func fiveProviderScenarioMatchesRegistryOrder() async {
        let fixture = DemoFixture.multiFixture(for: .fiveProviders)
        let beforeOpenCode = DemoFixture.registeredProviderOrder.filter { $0 != .opencode && $0 != .antigravity }
        #expect(fixture.accounts.map(\.providerID) == beforeOpenCode)
        #expect(fixture.providers.map(\.id) == beforeOpenCode)
        #expect(DemoFixture.registeredProviderOrder == [.claude, .codex, .grok, .cursor, .copilot, .opencode, .antigravity])
        #expect(DemoFixture.multiFixture(for: .multiProviders).accounts.map(\.providerID)
            == beforeOpenCode.filter { $0 != .copilot })
        // Single-account like Cursor: the demo must not offer "Add Account…" for Copilot.
        let copilot = fixture.providers.first { $0.id == .copilot }
        #expect(copilot?.accountCapacity == 1)
        #expect(await copilot?.fetchSnapshot().planLabel == nil)
    }

    /// OpenCode plan U9: the demo registry is the same list the phone treats as known, so a
    /// provider the Mac can register cannot be missing from the demos (PR #189 found harness
    /// stores that silently drew two providers). The App suite ties it to the composition
    /// registry itself.
    @Test func demoRegistryMatchesEveryKnownProvider() {
        #expect(DemoFixture.registeredProviderOrder.map(\.raw) == CompanionSyncKeys.knownProviderIDs)
    }

    /// OpenCode plan U9 (KTD14): `six-providers` poses every registered provider, one live
    /// built-in each, so a provider added to the registry without a fixture fails here.
    @Test func sixProviderScenarioCoversTheRegistry() async {
        let fixture = DemoFixture.multiFixture(for: .sixProviders)
        #expect(fixture.accounts.map(\.providerID) == DemoFixture.registeredProviderOrder)
        #expect(fixture.providers.map(\.id) == DemoFixture.registeredProviderOrder)
        #expect(fixture.accounts.allSatisfy { $0.isBuiltIn })
        for provider in fixture.providers {
            let snapshot = await provider.fetchSnapshot()
            #expect(snapshot.providerID == provider.id)
            #expect(snapshot.freshness == .live, "\(provider.id)")
            #expect(!snapshot.windows.isEmpty, "\(provider.id)")
        }
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "six-providers"])
            == .multiAccount(.sixProviders))
    }

    /// OpenCode plan U9 (KTD6): the six-provider OpenCode row is realistic: Go's three
    /// windows in card order, distinct values, future resets, no plan label (KTD19), and the
    /// same tested-envelope capacity as the registry (KTD10).
    @Test func openCodeDemoSnapshotHasGosThreeWindows() async throws {
        let snapshot = DemoFixture.opencodeSnapshot
        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly, OpenCodeProvider.monthlyKind])
        let left = snapshot.windows.map { UsagePercentageMode.remaining.roundedPercentage(for: $0) }
        #expect(left == [82, 53, 29])
        #expect(Set(left).count == 3)
        #expect(snapshot.windows.allSatisfy { ($0.resetSchedule.deadline ?? .distantPast) > Date() })
        #expect(snapshot.windows.allSatisfy { !$0.isLimited })
        #expect(snapshot.planLabel == nil)
        #expect(snapshot.planStatus == nil)
        #expect(snapshot.accountEmail == nil)
        let provider = try #require(DemoFixture.multiFixture(for: .sixProviders).providers.first { $0.id == .opencode })
        #expect(provider.accountCapacity == AccountRegistry.testedEnvelope)
        #expect(UsageLimitSentence(snapshot: await provider.fetchSnapshot(), now: Date()) == nil)
    }

    /// OpenCode plan U9 (KTD7): the no-Go pose is the provider's own no-Go reading. Live,
    /// one Monthly row with no number, the See Go Plans row in Standard, the Standard
    /// section in Compact, and "No Go plan" as the exported plan name.
    @Test func openCodeNoGoPoseIsTheProvidersNoGoReading() async throws {
        let fixture = DemoFixture.multiFixture(for: .opencodeNoGo)
        #expect(fixture.accounts.map(\.providerID) == [.claude, .opencode])
        let provider = try #require(fixture.providers.first { $0.id == .opencode })
        let snapshot = await provider.fetchSnapshot()
        #expect(snapshot.freshness == .live)
        #expect(snapshot.planStatus == .noActivePlan)
        #expect(snapshot.exportedPlanLabel == "No Go plan")
        let window = try #require(snapshot.windows.first)
        #expect(snapshot.windows.count == 1)
        #expect(window.kind == OpenCodeProvider.monthlyKind)
        #expect(window.freshness.isUnavailable)
        let recovery = try #require(snapshot.planStatusRecovery)
        #expect(recovery.status == "No Go plan on this workspace")
        #expect(recovery.primaryLabel == "See Go Plans")
        let compact = CompactAccountRowRecipe(
            snapshot: snapshot, meterStyle: .default, percentageMode: .remaining, now: Date(),
            requiresStandardSection: false, showsCodexSparkCounters: false)
        #expect(compact.fallsBackToStandard)
    }

    /// OpenCode plan U9 (KTD3, KTD21): the too-old-CLI pose carries the typed outcome, so the
    /// card reads "Go usage needs OpenCode 2.2 or newer" with About OpenCode 2 and Check Now.
    @Test func openCodeUpdatePoseCarriesTheUpdateOutcome() async throws {
        let fixture = DemoFixture.multiFixture(for: .opencodeUpdate)
        #expect(fixture.accounts.map(\.providerID) == [.claude, .opencode])
        let provider = try #require(fixture.providers.first { $0.id == .opencode })
        let snapshot = await provider.fetchSnapshot()
        #expect(snapshot.freshness == .stale(.providerSetup(.opencodeUpdateRequired)))
        #expect(snapshot.windows.isEmpty)
        let recovery = ProviderSetupOutcome.opencodeUpdateRequired.recoveryPresentation
        #expect(recovery.status == "Go usage needs OpenCode 2.2 or newer")
        #expect(recovery.primaryLabel == "About OpenCode 2")
        #expect(recovery.secondaryLabel == "Check Now")
    }

    /// OpenCode plan U9 (KTD15, KTD21): the limited pose has a live, limited monthly window
    /// with a future reset beside a healthy OpenCode built-in. Standard gets the limited
    /// sentence; Compact keeps one line and gives the monthly window a slot, which names
    /// itself under the healthy row's 5-hour column.
    @Test func openCodeLimitedPoseDrawsTheSentenceAndTheCompactSlot() async throws {
        let fixture = DemoFixture.multiFixture(for: .opencodeLimited)
        #expect(fixture.accounts.map(\.providerID) == [.claude, .opencode, .opencode])
        #expect(fixture.accounts.map(\.label) == ["Personal", "Personal", "Work"])
        #expect(Set(fixture.accounts.map(\.key)).count == 3)
        let now = Date()
        let healthy = await fixture.providers[1].fetchSnapshot()
        let limited = await fixture.providers[2].fetchSnapshot()
        #expect(UsageLimitSentence(snapshot: healthy, now: now) == nil)
        let sentence = try #require(UsageLimitSentence(snapshot: limited, now: now))
        #expect(sentence.window.kind == OpenCodeProvider.monthlyKind)
        #expect(sentence.text.hasPrefix("Go’s monthly limit is reached until "))

        func recipe(_ snapshot: UsageSnapshot) -> CompactAccountRowRecipe {
            CompactAccountRowRecipe(
                snapshot: snapshot, meterStyle: .default, percentageMode: .remaining, now: now,
                requiresStandardSection: false, showsCodexSparkCounters: false)
        }
        let healthyRow = recipe(healthy), limitedRow = recipe(limited)
        #expect(!limitedRow.fallsBackToStandard)
        #expect(healthyRow.shownWindows.map(\.window.kind) == [.fiveHour, .weekly])
        #expect(limitedRow.shownWindows.map(\.window.kind) == [.weekly, OpenCodeProvider.monthlyKind])
        let placed = limitedRow.placedWindows(columns: healthyRow.shownWindows.map(\.window.kind))
        #expect(placed.map { $0?.window.window.kind } == [OpenCodeProvider.monthlyKind, .weekly])
        #expect(placed.first??.ownLabel != nil)
        #expect(placed.last??.ownLabel == nil)
    }

    /// Copilot plan U7: before the first usage reading the row is unavailable. It keeps its
    /// label and never prints a number: 0 used must not read as 100 left anywhere.
    @Test func copilotNoReadingRowShowsUnavailableWithoutANumber() async throws {
        let fixture = DemoFixture.multiFixture(for: .copilotNoReading)
        #expect(fixture.accounts.map(\.providerID) == [.claude, .copilot])
        let provider = try #require(fixture.providers.first { $0.id == .copilot })
        let snapshot = await provider.fetchSnapshot()
        #expect(snapshot.freshness == .live)
        let window = try #require(snapshot.windows.first)
        #expect(snapshot.windows.count == 1)
        #expect(window.freshness.isUnavailable)
        #expect(window.kind.shortLabel == "Monthly")
        #expect(MeterRecipe.fillRecipe(fill: .solid, severity: window.severity, freshness: window.freshness) == .none)

        let projected = WidgetSnapshotProjector.project(
            snapshots: [.copilot: snapshot], providerOrder: [.copilot], displayNames: [.copilot: "Copilot"],
            renewalDate: { _ in nil }, widgetsEnabled: true)
        let summary = try #require(projected.providers.first?.windows.first)
        #expect(summary.label == "Monthly")
        #expect(summary.displayPercentRemaining == nil)
        #expect(WidgetWindowText.percent(summary) == "—")
        let spoken = WidgetWindowText.accessibilityValue(summary, providerIsLive: true, now: Date())
        #expect(!spoken.contains("100"))
        #expect(spoken.contains("unavailable"))

        // The widget style fixture poses the same state for the render sweep.
        let fixtureRow = try #require(DemoScreenshotData.styleFixture("copilotNoReading", now: Date())?
            .providers.first { $0.id == ProviderID.copilot.raw }?.windows.first)
        #expect(fixtureRow.displayPercentRemaining == nil)
        #expect(WidgetWindowText.percent(fixtureRow) == "—")
    }

    @Test func fourDefaultScenarioKeepsStoredDefaultLabels() {
        let fixture = DemoFixture.multiFixture(for: .fourDefault)
        let accountsByProvider = Dictionary(grouping: fixture.accounts, by: \.providerID)

        #expect(fixture.accounts.map(\.providerID) == [.claude, .codex, .grok, .cursor])
        #expect(fixture.accounts.map(\.label) == ["Main", "Main", "Main", "Main"])
        #expect(fixture.accounts.allSatisfy { $0.isBuiltIn })
        #expect(!surfaceUsesAccountRows(accountsByProvider: accountsByProvider))
        #expect(fixture.accounts.map { account in
            rowTitle(
                for: account,
                in: accountsByProvider[account.providerID] ?? [],
                providerDisplayName: account.providerID.displayName
            )
        } == ["Claude", "Codex", "Grok", "Cursor"])
    }

    @Test func duplicateLabelsScenarioHasDistinctExplicitEmails() async {
        let fixture = DemoFixture.multiFixture(for: .duplicateLabels)

        #expect(fixture.accounts.map(\.label) == ["Main", "Account 2", "Work", "work"])

        var emails: [String] = []
        for provider in fixture.providers {
            if let email = await provider.fetchSnapshot().accountEmail {
                emails.append(email)
            }
        }
        #expect(emails == [
            "main@example.com",
            "second@example.com",
            "work-primary@example.com",
            "work-secondary@example.com",
        ])
        #expect(Set(emails).count == fixture.accounts.count)
        #expect(fixture.accounts.allSatisfy {
            showsPersistentEmail(for: $0, in: fixture.accounts)
        })
    }

    // MARK: - Remembered accounts (default-login plan U11)

    /// A store built the way `AppComposition.demoMultiAccountStore` and the render harness
    /// build one: fixture providers, fixture accounts, and the fixture's in-memory record
    /// store. Preferences live in a throwaway suite, never `.standard`.
    @MainActor
    private func demoStore(
        _ scenario: DemoFixture.MultiAccountScenario
    ) -> (store: UsageStore, records: DemoDefaultLoginRecordStore) {
        let fixture = DemoFixture.multiFixture(for: scenario)
        let suite = "headroom.demo-fixture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let records = fixture.makeDefaultLoginRecordStore()
        let store = UsageStore(
            providers: fixture.providers,
            preferences: Preferences(defaults: defaults),
            accounts: fixture.accounts,
            defaultLoginRecords: records
        )
        return (store, records)
    }

    /// U11: `--demo remembered` lists each of Claude and Codex as a live default followed by
    /// two remembered rows: Work, read two minutes ago and still before both resets (dimmed,
    /// numbers kept), and Studio, read two days ago with both resets passed (no numbers).
    @MainActor
    @Test func rememberedScenarioBuildsTheExpectedDisplayList() async throws {
        let (store, _) = demoStore(.remembered)
        await store.refreshAll()

        #expect(store.providerOrder == [.claude, .codex])
        for providerID in [ProviderID.claude, .codex] {
            let rows = store.displayAccounts(for: providerID)
            #expect(rows.map(\.label) == ["Personal", "Work", "Studio"], "\(providerID)")
            #expect(rows.map(\.kind) == [.engine, .remembered, .remembered], "\(providerID)")
            #expect(store.accounts(for: providerID).map(\.label) == ["Personal"], "\(providerID)")
            #expect(rows.first?.account.isBuiltIn == true)

            let live = store.snapshot(for: rows[0].key)
            #expect(live.freshness == .live)
            #expect(live.windows.allSatisfy { $0.freshness.isLive })

            let work = store.snapshot(for: rows[1].key)
            #expect(work.windows.count == 2)
            #expect(work.windows.allSatisfy { $0.freshness.observedAt != nil }, "\(providerID) Work is dimmed")
            #expect(work.windows.map { UsagePercentageMode.remaining.roundedPercentage(for: $0) } == [22, 10])

            let studio = store.snapshot(for: rows[2].key)
            #expect(studio.windows.count == 2)
            #expect(studio.windows.allSatisfy { $0.freshness.isUnavailable }, "\(providerID) Studio has reset")

            let remembered = store.rememberedAccounts(for: providerID)
            let workRead = try #require(remembered.first { $0.label == "Work" }?.lastReadAt)
            let studioRead = try #require(remembered.first { $0.label == "Studio" }?.lastReadAt)
            #expect(Date().timeIntervalSince(workRead) < 10 * 60)
            #expect(Date().timeIntervalSince(studioRead) > 36 * 3_600)
        }
        // Remembered rows are never the main account (R12).
        #expect(store.displayAccounts(for: .claude).first?.key == AccountKey(providerID: .claude, accountID: .primary))
    }

    /// U10: `--demo merged` is mock scenario B, step 2 (AE4), for Claude and Codex alike:
    /// "Account 2" shows once and live with the gmail account's reading, and "Esper Labs" is
    /// dimmed with the work account's. The built-in is still an engine row, hidden by the
    /// merge, and every main-account surface follows "Account 2".
    @MainActor
    @Test func mergedScenarioBuildsTheExpectedDisplayList() async throws {
        let (store, _) = demoStore(.merged)
        await store.refreshAll()

        #expect(store.providerOrder == [.claude, .codex])
        for providerID in [ProviderID.claude, .codex] {
            let extra = AccountKey(providerID: providerID, accountID: AccountID("\(providerID.raw)-account-2"))
            let rows = store.displayAccounts(for: providerID)
            #expect(rows.map(\.label) == ["Account 2", "Esper Labs"], "\(providerID)")
            #expect(rows.map(\.kind) == [.engine, .remembered], "\(providerID)")
            #expect(rows[0].key == extra)
            #expect(store.accounts(for: providerID).map(\.label) == ["Main", "Account 2"], "\(providerID)")
            #expect(store.displayProjection(for: providerID).mergeMap
                == [AccountKey(providerID: providerID, accountID: .primary): extra])
            #expect(store.displayPrimaryKey(for: providerID) == extra)

            let live = store.snapshot(for: extra)
            #expect(live.freshness == .live)
            #expect(live.windows.map { UsagePercentageMode.remaining.roundedPercentage(for: $0) } == [96, 69])

            let esper = store.snapshot(for: rows[1].key)
            #expect(esper.windows.allSatisfy { $0.freshness.observedAt != nil }, "\(providerID) Esper Labs is dimmed")
            #expect(esper.windows.map { UsagePercentageMode.remaining.roundedPercentage(for: $0) } == [22, 10])
            #expect(esper.planLabel == "Team")
        }
    }

    /// R15: no other scenario carries a record, so each display list is its engine list.
    @MainActor
    @Test func otherScenariosShowNoRememberedRows() async {
        for scenario in DemoFixture.MultiAccountScenario.allCases where scenario != .remembered && scenario != .merged {
            #expect(DemoFixture.multiFixture(for: scenario).defaultLoginRecords == nil, "\(scenario)")
            // multi-20 simulates 4s probes; its display list is fixed before any refresh.
            let (store, _) = demoStore(scenario)
            if scenario != .envelope, scenario != .loading { await store.refreshAll() }
            for providerID in store.registeredProviderOrder {
                #expect(
                    store.displayAccounts(for: providerID).map(\.account) == store.accounts(for: providerID),
                    "\(scenario) \(providerID)"
                )
                #expect(store.rememberedAccounts(for: providerID, includingHidden: true).isEmpty, "\(scenario)")
            }
        }
    }

    /// R18 and the U11 isolation rule: a demo store's records live in memory. Its writes
    /// (a rename here) land in the in-memory store, and the `defaultLoginRecords.v1` key in
    /// the process's standard domain is never written. Every provider is a fixture, so no
    /// identity reader runs and no CLI file is read.
    @MainActor
    @Test func demoStoreKeepsItsRecordsInMemory() async throws {
        let realKey = "defaultLoginRecords.v1"
        let before = UserDefaults.standard.data(forKey: realKey)
        let (store, records) = demoStore(.remembered)
        #expect(store.defaultLoginRecordStore is DemoDefaultLoginRecordStore)
        #expect(store.providers.allSatisfy { $0 is DemoUsageProvider })
        await store.refreshAll()

        let work = try #require(store.rememberedAccounts(for: .codex).first { $0.label == "Work" })
        let writes = records.writeCount
        #expect(store.renameRememberedAccount(work.key, to: "Work laptop"))
        #expect(records.writeCount == writes + 1)
        #expect(store.displayAccounts(for: .codex).map(\.label) == ["Personal", "Work laptop", "Studio"])
        #expect(UserDefaults.standard.data(forKey: realKey) == before)

        // A second store from the same fixture starts from the seed again: nothing a
        // previous demo run did carries over.
        let (fresh, _) = demoStore(.remembered)
        #expect(fresh.displayAccounts(for: .codex).map(\.label) == ["Personal", "Work", "Studio"])
    }

    // MARK: - Settings Appearance specimen (U3 / KTD4)

    /// The Appearance pane's live specimen must exercise the whole severity ramp: with
    /// every demo Claude window sitting in healthy/low territory, `Color as event` and
    /// `Hue ramp` would preview as identical neutrals (plan Assumptions).
    @Test func settingsSpecimenSpansEverySeverityBand() {
        let bands = DemoFixture.settingsSpecimenSnapshot.windows.map(\.severity)
        #expect(bands.count == 3)
        #expect(bands.filter { $0 == .healthy }.count == 1)
        #expect(bands.filter { $0 == .low }.count == 1)
        #expect(bands.filter { $0 == .critical }.count == 1)
    }

    /// KTD4: the specimen is a synthetic account, so its id must never collide with a
    /// real built-in account or any demo fixture account — a collision would let the
    /// preview card read (or reset) live per-account state.
    @Test func settingsSpecimenAccountIDIsUnusedElsewhere() {
        let specimenID = DemoFixture.settingsSpecimenAccount.id
        #expect(specimenID != ProviderAccount.builtIn(for: .claude).id)
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            let ids = DemoFixture.multiFixture(for: scenario).accounts.map(\.id)
            #expect(!ids.contains(specimenID))
        }
    }
}
