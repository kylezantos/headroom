import Testing
import Foundation
@testable import HeadroomCore

struct DemoScreenshotDataVariantsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func variantKeyRoundTripsInCompanionDemoModeStore() throws {
        let suiteName = "DemoScreenshotDataVariantsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)

        // Defaults to "full" when unset
        #expect(store.variant == "full")

        // Rounds-trips the variant through set/get
        #expect(store.setVariant("claudeOnly") == .changed)
        #expect(store.variant == "claudeOnly")

        // Returns unchanged when setting to the same value
        #expect(store.setVariant("claudeOnly") == .unchanged)
        #expect(store.variant == "claudeOnly")

        // Updates to a different variant
        #expect(store.setVariant("codexFiveHourReturns") == .changed)
        #expect(store.variant == "codexFiveHourReturns")
    }

    @Test func unknownVariantDefaultsToFull() {
        let suiteName = "DemoScreenshotDataVariantsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        defaults?.set("unknownVariant", forKey: CompanionDemoModeStore.variantKey)
        let store = CompanionDemoModeStore(defaults: defaults)

        #expect(store.variant == "unknownVariant")
        let envelope = DemoScreenshotData.envelope(for: store.variant)
        let fullEnvelope = DemoScreenshotData.envelope(for: "full")
        // Unknown variant falls back to full fixture - compare provider counts and shapes
        #expect(envelope.providers.count == fullEnvelope.providers.count)
        #expect(envelope.apiSpendProviders.count == fullEnvelope.apiSpendProviders.count)
    }

    @Test func claudeFixturesHaveExtraWeeklyWindow() {
        let fixtures = ["full", "noSpend", "claudeOnly", "claudeOnlyNoSpend", "codexFiveHourReturns", "attention"]
        for variantName in fixtures {
            let envelope = DemoScreenshotData.envelope(for: variantName)
            guard let claudeProvider = envelope.providers.first(where: { $0.id == ProviderID.claude.raw }) else {
                Issue.record("Claude provider not found in \(variantName)")
                return
            }
            #expect(claudeProvider.extraWeeklyWindows.count == 1)
        }
    }

    @Test func allFixturesAreValidEnvelopes() throws {
        let variants = ["full", "noSpend", "claudeOnly", "claudeOnlyNoSpend", "codexFiveHourReturns", "attention", "fourProviders"]
        for variant in variants {
            let envelope = DemoScreenshotData.envelope(for: variant)
            // Schema version should be current
            #expect(envelope.schemaVersion == WidgetSnapshotEnvelope.schemaVersion)
            // Status should be enabled
            #expect(envelope.status == .enabled)
            // Providers must be non-empty
            #expect(!envelope.providers.isEmpty)
            // Each provider must have at least one window
            for provider in envelope.providers {
                #expect(!provider.subscriptionWindows.isEmpty || !provider.extraCounterWindows.isEmpty)
            }
        }
    }

    @Test func fullAndCodexFiveHourHaveSpend() {
        #expect(!DemoScreenshotData.envelope(for: "full").apiSpendProviders.isEmpty)
        #expect(!DemoScreenshotData.envelope(for: "codexFiveHourReturns").apiSpendProviders.isEmpty)
    }

    @Test func noSpendAndClaudeOnlyNoSpendHaveNoSpend() {
        #expect(DemoScreenshotData.envelope(for: "noSpend").apiSpendProviders.isEmpty)
        #expect(DemoScreenshotData.envelope(for: "claudeOnlyNoSpend").apiSpendProviders.isEmpty)
    }

    @Test func attentionFixtureHasStaleProvider() {
        let envelope = DemoScreenshotData.envelope(for: "attention")
        let claudeProvider = envelope.providers.first { $0.id == ProviderID.claude.raw }
        guard let claudeProvider else {
            Issue.record("Could not find Claude provider")
            return
        }
        if case .stale = claudeProvider.freshness {
            // Expected
        } else {
            Issue.record("Claude provider should be stale in attention fixture")
        }
    }

    // MARK: - L9P settings preview fixture

    /// The Settings › Widgets & iPhone strip renders the real widget bodies, so its
    /// fixture has to be frozen: any `Date()` in it would make the medium tile's
    /// "Updated N min ago" footer drift and invite the reader to trust the preview as
    /// live data.
    @Test func settingsPreviewFixtureIsFrozen() {
        let first = DemoScreenshotData.settingsPreviewEnvelope
        let second = DemoScreenshotData.settingsPreviewEnvelope
        #expect(first == second)
        #expect(first.generatedAt == DemoScreenshotData.settingsPreviewNow.addingTimeInterval(-4 * 60))
        for provider in first.providers {
            for window in provider.windows {
                #expect(window.resetSchedule == .scheduled(DemoScreenshotData.settingsPreviewNow.addingTimeInterval(3 * 3_600)))
                #expect(window.resetLabel?.isEmpty == false)
            }
        }
    }

    /// The strip previews the small and medium families, which draw
    /// `primarySubscriptionWindow` and `displaySubscriptionWindows`. A fixture whose
    /// windows fell outside those accessors would preview as an empty tile.
    @Test func settingsPreviewFixtureFillsBothWidgetFamilies() {
        let envelope = DemoScreenshotData.settingsPreviewEnvelope
        // `widgetProviders` caps the list at two; the fixture is already that shape, so
        // neither tile silently drops a provider.
        #expect(envelope.widgetProviders.count == 2)
        #expect(envelope.widgetProviders.map(\.id) == [ProviderID.claude.raw, ProviderID.codex.raw])
        // No API spend: the medium tile shows its "from Mac · …" footer instead of the
        // spend strip, whose provider marks would bypass the app's injected renderer.
        #expect(envelope.apiSpendProviders.isEmpty)
        for provider in envelope.widgetProviders {
            #expect(provider.primarySubscriptionWindow != nil)
            #expect(provider.displaySubscriptionWindows.count == 2)
        }
    }

    // MARK: - v4 demo variants (U7, KTD21)

    private func content(_ variant: CompanionDemoVariant) throws -> CompanionResolvedContent {
        try #require(CompanionDemoData.snapshot(variant, now: now).content)
    }

    private func provider(_ id: String, in content: CompanionResolvedContent) throws -> CompanionResolvedProvider {
        try #require(content.providers.first { $0.id == id })
    }

    /// Every variant's bytes go through the real codec: the manifest decodes, each provider
    /// key decodes against its suffix, and every digest is SHA-256 of the exact stored bytes.
    @Test(arguments: CompanionDemoVariant.allCases)
    func everyVariantPublishesBytesTheRealCodecAccepts(_ variant: CompanionDemoVariant) throws {
        let publication = try CompanionDemoData.publication(variant, now: now)
        switch CompanionSyncCodec.decodeManifest(publication.manifest) {
        case .value(.active(let manifest)):
            #expect(manifest.sourceID == CompanionDemoData.sourceID)
            #expect(Set(manifest.providers.keys) == Set(publication.providerKeys.keys))
            for (id, data) in publication.providerKeys {
                guard case .value(let payload) = CompanionSyncCodec.decodeProviderPayload(data, providerID: id) else {
                    Issue.record("\(variant) \(id) key did not decode")
                    continue
                }
                #expect(payload.payloadGeneration == manifest.providers[id]?.payloadGeneration)
                #expect(CompanionSyncCodec.digest(data) == manifest.providers[id]?.digest)
                #expect(data.count <= CompanionSyncBudget.providerKeyBytes)
            }
            #expect(manifest.dropLadderLevel == publication.ladderLevel)
        case .value(.disabled):
            #expect(variant == .paused)
        case .missing:
            #expect(variant == .waiting || variant == .oldMac)
        default:
            Issue.record("\(variant) manifest did not decode")
        }
        if variant == .oldMac {
            #expect(SyncedWidgetSnapshotCodec.decode(publication.v3).envelope?.companionLineage == nil)
        } else {
            #expect(publication.v3 == nil)
        }
        let snapshot = CompanionDemoData.resolve(publication, now: now)
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test(arguments: CompanionDemoVariant.allCases)
    func everyVariantResolvesToItsIntendedState(_ variant: CompanionDemoVariant) {
        let snapshot = CompanionDemoData.snapshot(variant, now: now)
        switch variant {
        case .paused: #expect(snapshot.state == .paused)
        case .waiting: #expect(snapshot.state == .waiting(nil))
        case .oldMac:
            #expect(snapshot.content?.origin == .v3)
            #expect(snapshot.content?.notice == .updateMac)
        default:
            #expect(snapshot.content?.origin == .v4)
            #expect(snapshot.content?.notice == nil)
            #expect(snapshot.content?.providers.allSatisfy { if case .v4(.manifestDigestMatched) = $0.source { true } else { false } } == true)
        }
    }

    @Test func unknownMissingAndLegacyVariantTokensFallBackToMultiAccount() {
        #expect(CompanionDemoVariant.default == .multiAccount)
        for token in [nil, "", "full", "noSpend", "nope", "MULTIACCOUNT"] as [String?] {
            #expect(CompanionDemoVariant.resolving(token) == .multiAccount)
        }
        for variant in CompanionDemoVariant.allCases {
            #expect(CompanionDemoVariant.resolving(variant.rawValue) == variant)
            #expect(!variant.title.isEmpty)
        }
        // Mac `--demo <scenario>` names pose the same moment on the phone.
        #expect(CompanionDemoVariant.resolving("multi-3") == .multiAccount)
        #expect(CompanionDemoVariant.resolving("multi-4") == .fourProviders)
        #expect(CompanionDemoVariant.resolving("banked-resets") == .bankedResets)
        #expect(CompanionDemoVariant.resolving("multi-20") == .multi20)
    }

    @Test func multiAccountIsFiveAccountsAcrossTwoProvidersWithASampleReminder() throws {
        let content = try content(.multiAccount)
        #expect(content.providers.map(\.id) == ["claude", "codex"])
        #expect(content.providers.map { $0.accounts.map(\.title) } == [["Personal", "Work", "Studio"], ["Personal", "Work"]])
        #expect(content.providers.allSatisfy { $0.mainAccount?.title == "Personal" })
        #expect(content.apiSpend.map(\.displayName) == ["Anthropic API", "OpenAI API"])
        let reminder = try #require(content.reminderSummary)
        #expect(reminder.macUseItUpEnabled)
        #expect(reminder.rules == [try CompanionReminderRuleSummary(amount: 1, unit: .days, threshold: 50)])
        #expect(content.display == CompanionDisplayBlock())
        #expect(content.ladder == .full)
    }

    /// One Fable number on every demo and screenshot surface (KTD21).
    @Test func fableIsOneValueAcrossEveryDemoSurface() throws {
        func fable(_ windows: [WidgetWindowSummary]) -> [Int] {
            windows.filter { $0.kind == .other("Weekly (Fable)") }.map(\.roundedPercentRemaining)
        }
        var seen: [Int] = []
        for variant in CompanionDemoVariant.allCases {
            let snapshot = CompanionDemoData.snapshot(variant, now: now)
            seen += fable(snapshot.shownWindows(for: .app))
        }
        // The style fixtures that pose the shared moment; the rest pose tight, stale and
        // pending states with their own deliberate numbers.
        for name in ["claudeCodex", "claudeGrok", "sparkOn", "spend"] {
            let envelope = try #require(DemoScreenshotData.styleFixture(name, now: now))
            seen += envelope.providers.flatMap { fable($0.windows) }
        }
        for name in ["full", "noSpend", "claudeOnly", "claudeOnlyNoSpend", "codexFiveHourReturns", "attention", "fourProviders"] {
            seen += DemoScreenshotData.envelope(for: name).providers.flatMap { fable($0.windows) }
        }
        #expect(!seen.isEmpty)
        #expect(Set(seen) == [54])
    }

    @Test(arguments: CompanionDemoVariant.allCases)
    func planLabelsAreStoredInDisplayForm(_ variant: CompanionDemoVariant) {
        let content = CompanionDemoData.snapshot(variant, now: now).content
        for account in content?.providers.flatMap(\.accounts) ?? [] {
            let plan = account.planName
            // U8's never-signed-in account has no plan to report, and Copilot's CLI reports
            // none (Copilot plan parity exception); every other account does.
            if account.attention != .neverOnboarded, account.title != "Copilot" { #expect(plan != nil) }
            #expect(PlanLabelPresentation.displayName(plan) == plan)
        }
    }

    /// The wire carries no reset labels: every surface formats the deadline relative to now.
    /// Only the past-reset fixture's own 5-hour window lies in the past, and the remembered
    /// fixture's "Studio" rows, which the Mac sends unavailable since their resets.
    @Test(arguments: CompanionDemoVariant.allCases)
    func resetsAreDeadlinesRelativeToNow(_ variant: CompanionDemoVariant) {
        let later = now.addingTimeInterval(86_400)
        let a = CompanionDemoData.snapshot(variant, now: now).shownWindows(for: .app)
        let b = CompanionDemoData.snapshot(variant, now: later).shownWindows(for: .app)
        #expect(a.count == b.count)
        for (early, late) in zip(a, b) {
            #expect(early.resetLabel == nil)
            guard case .scheduled(let first) = early.resetSchedule, case .scheduled(let second) = late.resetSchedule else {
                Issue.record("\(variant) window has no scheduled reset")
                continue
            }
            #expect(second.timeIntervalSince(first) == 86_400)
            let pastReset = variant == .pastReset && early.kind == .fiveHour && first < now
            let rememberedReset = variant == .remembered && early.freshness.isUnavailable && first < now
            #expect(first > now || pastReset || rememberedReset)
        }
    }

    @Test func fourProvidersCoversTheRegistryWithBillingPools() throws {
        let content = try content(.fourProviders)
        #expect(content.providers.map(\.id) == ["claude", "codex", "grok", "cursor"])
        let grok = try #require(try provider("grok", in: content).mainAccount)
        #expect(grok.windows.map(\.summary.label) == ["Weekly"])
        #expect(grok.windows.allSatisfy { $0.summary.isBillingPeriod })
        let cursor = try #require(try provider("cursor", in: content).mainAccount)
        #expect(cursor.windows.map(\.summary.label) == ["Cursor Models", "Other Models"])
        #expect(cursor.windows.map(\.summary.roundedPercentRemaining) == [69, 37])
    }

    /// Copilot plan U7: the five-provider moment adds Copilot's single monthly pool, with no
    /// plan name and no spend row.
    @Test func fiveProvidersAddsCopilotsMonthlyPool() throws {
        let content = try content(.fiveProviders)
        #expect(content.providers.map(\.id) == DemoFixture.registeredProviderOrder.map(\.raw))
        let copilot = try provider("copilot", in: content)
        #expect(copilot.accounts.count == 1)
        #expect(copilot.mainAccount?.planName == nil)
        #expect(copilot.mainAccount?.windows.map(\.summary.label) == ["Monthly"])
        #expect(copilot.mainAccount?.windows.map(\.summary.roundedPercentRemaining) == [76])
        #expect(content.apiSpend.map(\.id) == ["claude", "codex"])
        #expect(CompanionDemoVariant.resolving("five-providers") == .fiveProviders)
    }

    /// U8 (V12, V13): a never-signed-in extra, a shared long name with its " · 2" twin,
    /// banked resets on the main, and widgets that follow Codex only.
    @Test func accountStatesPosesTheStackedCardStates() throws {
        let content = try content(.accountStates)
        let claude = try provider("claude", in: content)
        #expect(claude.accounts.map(\.title) == ["Personal", "Account 2"])
        let signedOut = try #require(claude.extraAccounts.first)
        #expect(signedOut.attention == .neverOnboarded)
        #expect(signedOut.windows.isEmpty)
        #expect(signedOut.freshness == .stale(message: "Sign in to this account on your Mac", needsAttention: true))
        let codex = try provider("codex", in: content)
        #expect(codex.accounts.map(\.title)
            == ["Northwind Research Workspace", "Northwind Research Workspace · 2"])
        #expect(codex.mainAccount?.bankedResets == 2)
        #expect(codex.extraAccounts.first?.attention == .retrying)
        #expect(content.widgetProviderSelection == ["codex"])
    }

    @Test func staleSpendRetainsBothSpendRowsAsRetryableStale() throws {
        let content = try content(.staleSpend)
        #expect(content.apiSpend.map(\.displayName) == ["Anthropic API", "OpenAI API"])
        #expect(content.apiSpend.map(\.amount) == [142.67, 58.90])
        for spend in content.apiSpend {
            guard case .stale(_, let needsAttention) = spend.freshness else {
                Issue.record("\(spend.id) should be stale"); continue
            }
            #expect(needsAttention == false)
        }
        #expect(content.providers.map { $0.accounts.count } == [3, 2])
    }

    @Test func bankedResetsPosesTwoOneAndAReportedZero() throws {
        let codex = try provider("codex", in: try content(.bankedResets))
        #expect(codex.accounts.map(\.title) == ["Northwind Research Workspace", "On call", "Quiet"])
        #expect(codex.accounts.map(\.bankedResets) == [2, 1, 0])
        // The one-credit account is Critical, so its capsule opens on its own.
        #expect(codex.accounts[1].widgetWindows.first { $0.kind == .fiveHour }?.severity == .critical)
        #expect(try provider("claude", in: try content(.bankedResets)).mainAccount?.bankedResets == nil)
    }

    @Test func displayChoicesCarriesANonDefaultDisplayBlockAndSparkRows() throws {
        let content = try content(.displayChoices)
        let display = try #require(content.display)
        #expect(display.meterStyle == MeterStyle(format: .full, shape: .segmented, fill: .ghost))
        #expect(display.percentageMode == .used)
        #expect(display.accountTitleInk == .brand)
        #expect(display.appSparkEnabled)
        let codex = try provider("codex", in: content)
        #expect(codex.accounts.allSatisfy { $0.windows.contains(where: \.isSpark) })
        // Spark is flagged by the Mac, never inferred: Claude's Fable row is not Spark.
        #expect(try provider("claude", in: content).accounts.flatMap(\.windows).allSatisfy { !$0.isSpark })
    }

    @Test func dimmedDimsEverySurfaceButMultiAccountDoesNot() throws {
        let dimmed = try content(.dimmed)
        let fresh = try content(.multiAccount)
        for surface in CompanionFreshnessSurface.allCases {
            #expect(CompanionFreshnessRule.isDimmed(dimmed.freshness, surface: surface, at: now))
            #expect(!CompanionFreshnessRule.isDimmed(fresh.freshness, surface: surface, at: now))
        }
        #expect(CompanionFreshnessRule.lastHeardFromMac(dimmed.freshness) == now.addingTimeInterval(-2 * 3_600))
    }

    @Test func pastResetHidesOnlyThatWindowsNumber() throws {
        let content = try content(.pastReset)
        #expect(!CompanionFreshnessRule.isDimmed(content.freshness, surface: .app, at: now))
        let claude = try #require(try provider("claude", in: content).mainAccount)
        #expect(claude.attention == .retrying)
        let hidden = claude.widgetWindows.filter { CompanionFreshnessRule.visiblePercentRemaining($0, at: now) == nil }
        #expect(hidden.map(\.kind) == [.fiveHour])
        #expect(CompanionFreshnessRule.pastResetTime(hidden[0], at: now) == now.addingTimeInterval(-25 * 60))
    }

    /// R2/KTD7: at the tested envelope every account reaches the phone.
    @Test func multi20CarriesEveryAccountWithSparkRowsWithinBudget() throws {
        let publication = try CompanionDemoData.publication(.multi20, now: now)
        let content = try content(.multi20)
        #expect(content.providers.map { $0.accounts.count } == [20, 20, 20, 1, 1])
        #expect(content.providers.allSatisfy { $0.omittedAccountCount == 0 })
        #expect(content.display?.appSparkEnabled == true)
        #expect(try provider("codex", in: content).mainAccount?.windows.contains(where: \.isSpark) == true)
        #expect(content.ladder == CompanionDropLadder(level: publication.ladderLevel ?? -1))
        #expect((publication.ladderLevel ?? 2) < 2)
        var image = publication.providerKeys.reduce(into: [String: Data]()) { $0[CompanionSyncKeys.provider($1.key)!] = $1.value }
        image[CompanionSyncKeys.manifest] = publication.manifest
        #expect(CompanionBudgetMeasurement(image).fits)
    }

    /// KTD7 level 2: above the envelope the real budget fit caps extras at 20 per provider and
    /// the phone shows "N more on your Mac".
    @Test func aboveEnvelopeReachesTheAccountCapOnItsOwn() throws {
        let publication = try CompanionDemoData.publication(.aboveEnvelope, now: now)
        #expect(publication.ladderLevel == 2)
        let content = try content(.aboveEnvelope)
        #expect(content.ladder == .accountCap)
        let omitted = CompanionDemoData.aboveEnvelopeCount - CompanionSyncBudget.accountEnvelope
        #expect(content.providers.map(\.omittedAccountCount) == [omitted, omitted, omitted, 0, 0])
        #expect(content.providers.map { $0.accounts.count } == [20, 20, 20, 1, 1])
    }

    @Test func oldMacShowsMainAccountsOnlyWithTheUpdateLine() throws {
        let content = try content(.oldMac)
        #expect(content.notice?.message == "Update Headroom on your Mac to see every account")
        #expect(content.display == nil)
        #expect(content.providers.map { $0.accounts.map(\.title) } == [["Claude"], ["Codex"]])
        #expect(content.freshness.isV3Only)
    }

    /// Build-33 hosts read the stored token through `envelope(for:)`: a v4-only variant name
    /// shows its main accounts, legacy names keep their envelopes.
    @Test func legacyEnvelopeLookupProjectsV4OnlyVariants() {
        let multi = DemoScreenshotData.envelope(for: "multiAccount")
        #expect(multi.providers.map(\.id) == ["claude", "codex"])
        #expect(multi.providers.map(\.planLabel) == ["Max", "Pro Lite"])
        #expect(DemoScreenshotData.envelope(for: "bankedResets").providers.last?.planLabel == "Plus")
        #expect(DemoScreenshotData.envelope(for: "fourProviders").providers.first?.windows.first?.resetLabel == "Resets 2:15pm")
        #expect(DemoScreenshotData.envelope(for: "paused").providers.count == DemoScreenshotData.envelope(for: "full").providers.count)
    }

    @Test func publicationIsDeterministicForOneClock() throws {
        for variant in CompanionDemoVariant.allCases {
            let first = try CompanionDemoData.publication(variant, now: now)
            let second = try CompanionDemoData.publication(variant, now: now)
            // v4 bytes are deterministic (sorted keys, KTD6.2), so digests are stable. The v3
            // codec has no sorted-keys contract; its decoded content must match.
            #expect(first.manifest == second.manifest, "\(variant)")
            #expect(first.providerKeys == second.providerKeys, "\(variant)")
            #expect(SyncedWidgetSnapshotCodec.decode(first.v3) == SyncedWidgetSnapshotCodec.decode(second.v3), "\(variant)")
        }
    }
}

