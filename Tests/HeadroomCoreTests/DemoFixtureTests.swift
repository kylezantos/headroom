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
        #expect(DemoFixture.multiFixture(for: .multiFive).accounts.count == 8)  // 5 Claude + 3 Codex (past the cap for scroll)
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
        // Provider instances are 1:1 with accounts.
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            let fixture = DemoFixture.multiFixture(for: scenario)
            #expect(fixture.providers.count == fixture.accounts.count)
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

    /// Cursor bills a monthly included pool with a calendar reset day, 31% used = 69% left.
    @Test func cursorDemoSnapshotIsBillingPeriodMonthly() {
        let cursor = DemoFixture.cursorSnapshot
        #expect(cursor.planLabel == "Pro+")
        #expect(cursor.windows.count == 1)
        guard case .billingPeriod(let label, _)? = cursor.windows.first?.kind else {
            Issue.record("expected a billing-period window"); return
        }
        #expect(label == "Monthly")
        #expect(remaining(cursor, cursor.windows[0].kind) == 69)
    }

    /// U12 parity: the four-provider scenario's provider list is derived from — and equals —
    /// the registry order, rather than a Claude/Codex literal.
    @Test func fourProviderScenarioMatchesRegistryOrder() {
        let fixture = DemoFixture.multiFixture(for: .multiProviders)
        #expect(fixture.accounts.map(\.providerID) == DemoFixture.registeredProviderOrder)
        #expect(fixture.providers.map(\.id) == DemoFixture.registeredProviderOrder)
        #expect(DemoFixture.registeredProviderOrder == [.claude, .codex, .grok, .cursor])
    }

    @Test func fourDefaultScenarioKeepsStoredDefaultLabels() {
        let fixture = DemoFixture.multiFixture(for: .fourDefault)
        let accountsByProvider = Dictionary(grouping: fixture.accounts, by: \.providerID)

        #expect(fixture.accounts.map(\.providerID) == DemoFixture.registeredProviderOrder)
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
