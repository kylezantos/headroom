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
    @Test func fiveProviderScenarioMatchesRegistryOrder() async {
        let fixture = DemoFixture.multiFixture(for: .fiveProviders)
        #expect(fixture.accounts.map(\.providerID) == DemoFixture.registeredProviderOrder)
        #expect(fixture.providers.map(\.id) == DemoFixture.registeredProviderOrder)
        #expect(DemoFixture.registeredProviderOrder == [.claude, .codex, .grok, .cursor, .copilot])
        #expect(DemoFixture.multiFixture(for: .multiProviders).accounts.map(\.providerID)
            == DemoFixture.registeredProviderOrder.filter { $0 != .copilot })
        // Single-account like Cursor: the demo must not offer "Add Account…" for Copilot.
        let copilot = fixture.providers.first { $0.id == .copilot }
        #expect(copilot?.accountCapacity == 1)
        #expect(await copilot?.fetchSnapshot().planLabel == nil)
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
