import Foundation
import Testing
@testable import HeadroomCore

/// WCL1: three reachable tiers, chosen from `providers + rendered meters`, with the spend
/// strip deliberately not counted.
struct LargeWidgetDensityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Tier thresholds

    @Test func rowCountsUpToFourAreRoomy() {
        for rows in 2...4 {
            #expect(
                LargeWidgetDensity(providerCount: 1, meterCount: rows - 1) == .roomy,
                "\(rows) rows"
            )
        }
    }

    @Test func rowCountsOfFiveAndSixAreRegular() {
        for rows in 5...6 {
            #expect(
                LargeWidgetDensity(providerCount: 2, meterCount: rows - 2) == .regular,
                "\(rows) rows"
            )
        }
    }

    @Test func rowCountsAboveSixAreCompact() {
        for rows in 7...9 {
            #expect(
                LargeWidgetDensity(providerCount: 2, meterCount: rows - 2) == .compact,
                "\(rows) rows"
            )
        }
    }

    /// The whole reachable range, since the envelope caps widget providers at two: one
    /// provider with one meter (2) through two providers with a Fable/Spark-heavy mix (9).
    @Test func everyReachableRowCountLandsOnATier() {
        let expected: [Int: LargeWidgetDensity] = [
            2: .roomy, 3: .roomy, 4: .roomy,
            5: .regular, 6: .regular,
            7: .compact, 8: .compact, 9: .compact,
        ]
        for (rows, tier) in expected {
            #expect(LargeWidgetDensity(providerCount: 1, meterCount: rows - 1) == tier, "\(rows) rows")
        }
    }

    /// The three content mixes the audit measured: Single 4 → roomy, Everyday 6 → regular,
    /// Dense 8 → compact.
    @Test func theAuditsThreeContentMixesLandOnTheThreeTiers() {
        #expect(LargeWidgetDensity(providerCount: 1, meterCount: 3) == .roomy)
        #expect(LargeWidgetDensity(providerCount: 2, meterCount: 4) == .regular)
        #expect(LargeWidgetDensity(providerCount: 2, meterCount: 6) == .compact)
    }

    @Test func negativeCountsClampInsteadOfWrappingATier() {
        #expect(LargeWidgetDensity(providerCount: -3, meterCount: 2) == .roomy)
        #expect(LargeWidgetDensity(providerCount: 2, meterCount: -9) == .roomy)
    }

    // MARK: - Envelope arithmetic

    @Test func envelopeCountsProvidersPlusRenderedMeters() {
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [provider(id: "claude"), provider(id: "codex")]
        )

        // 2 headers + 4 meters = 6 rows.
        #expect(LargeWidgetDensity(envelope: envelope) == .regular)
    }

    /// WCL1's correction to the retired ladder: the spend strip is one horizontal row outside
    /// the meter stack, so it must not push the meters a tier tighter.
    @Test func theSpendStripDoesNotCountAsARow() {
        let providers = [provider(id: "claude"), provider(id: "codex")]
        let withoutSpend = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: providers
        )
        let withSpend = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: providers,
            apiSpendProviders: [
                spendProvider(id: "anthropic-api"),
                spendProvider(id: "openai-api"),
            ]
        )

        #expect(LargeWidgetDensity(envelope: withSpend) == LargeWidgetDensity(envelope: withoutSpend))
        #expect(LargeWidgetDensity(envelope: withSpend) == .regular)
    }

    @Test func envelopeCountsOnlySelectedWidgetProviders() {
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [
                provider(id: "claude"),
                provider(id: "codex"),
                provider(id: "grok"),
                provider(id: "cursor"),
            ],
            widgetProviderSelection: ["grok", "cursor"]
        )

        // Two of four providers are shown: 2 headers + 4 meters = 6 rows.
        #expect(LargeWidgetDensity(envelope: envelope) == .regular)
    }

    @Test func weeklyLabeledExtraWindowsCountAsRows() {
        let claude = WidgetProviderSummary(
            id: "claude",
            displayName: "Claude",
            planLabel: "Max",
            freshness: .live,
            windows: [weeklyWindow(), fiveHourWindow(), extraWeeklyWindow(label: "Weekly (Fable)")],
            renewalDate: nil
        )
        let envelope = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [claude])

        #expect(claude.subscriptionWindows.count == 2)
        #expect(claude.extraWeeklyWindows.count == 1)
        // 1 header + 3 meters = 4 rows.
        #expect(LargeWidgetDensity(envelope: envelope) == .roomy)
    }

    @Test func nonWeeklyLabeledExtraWindowsDoNotCount() {
        let claude = WidgetProviderSummary(
            id: "claude",
            displayName: "Claude",
            planLabel: "Max",
            freshness: .live,
            windows: [weeklyWindow(), fiveHourWindow(), extraWeeklyWindow(label: "Sonnet burst")],
            renewalDate: nil
        )
        let envelope = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [claude])

        #expect(claude.extraWeeklyWindows.isEmpty)
        // 1 header + 2 meters = 3 rows.
        #expect(LargeWidgetDensity(envelope: envelope) == .roomy)
    }

    /// A provider whose only rows are extra weekly sub-limits still draws the placeholder
    /// meter *and* those rows, so it costs its header plus both.
    @Test func extraWeeklyRowsCountOnTopOfThePlaceholderMeter() {
        let extraOnly = WidgetProviderSummary(
            id: "claude",
            displayName: "Claude",
            planLabel: "Max",
            freshness: .live,
            windows: [extraWeeklyWindow(label: "Weekly (Fable)")],
            renewalDate: nil
        )
        let envelope = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [extraOnly])

        // 1 header + 1 placeholder + 1 extra row = 3 rows → roomy; the old count made it 2.
        #expect(LargeWidgetDensity(envelope: envelope) == .roomy)
        #expect(LargeWidgetDensity(providerCount: 1, meterCount: 2) == .roomy)
    }

    /// A provider with no windows still draws one placeholder meter, so it costs two rows.
    @Test func aProviderWithNoWindowsStillCostsItsPlaceholderMeterRow() {
        let empty = WidgetProviderSummary(
            id: "grok",
            displayName: "Grok",
            planLabel: nil,
            freshness: .pending,
            windows: [],
            renewalDate: nil
        )
        let loaded = WidgetProviderSummary(
            id: "claude",
            displayName: "Claude",
            planLabel: "Max",
            freshness: .live,
            windows: [weeklyWindow(), fiveHourWindow(), extraWeeklyWindow(label: "Weekly (Fable)")],
            renewalDate: nil
        )
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [loaded, empty]
        )

        // 2 headers + 3 meters + 1 placeholder = 6 rows.
        #expect(LargeWidgetDensity(envelope: envelope) == .regular)
    }

    @Test func anEmptyEnvelopeIsRoomy() {
        let envelope = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        #expect(LargeWidgetDensity(envelope: envelope) == .roomy)
    }

    // MARK: - Tokens

    @Test func roomyTokenValues() {
        let tier = LargeWidgetDensity.roomy
        #expect(tier.typeStep == .standard)
        #expect(tier.barHeight == 8)
        #expect(tier.headerSpacing == 6)
        #expect(tier.meterSpacing == 12)
        #expect(tier.providerGapFloor == 16)
        #expect(tier.edgeGapWeight == 0.6)
        #expect(tier.showsPlanPill)
    }

    @Test func regularTokenValues() {
        let tier = LargeWidgetDensity.regular
        #expect(tier.typeStep == .standard)
        #expect(tier.barHeight == 7)
        #expect(tier.headerSpacing == 6)
        #expect(tier.meterSpacing == 12)
        #expect(tier.providerGapFloor == 16)
        #expect(tier.edgeGapWeight == 0.6)
        #expect(tier.showsPlanPill)
    }

    @Test func compactTokenValues() {
        let tier = LargeWidgetDensity.compact
        #expect(tier.typeStep == .dense)
        #expect(tier.barHeight == 6)
        #expect(tier.headerSpacing == 4)
        #expect(tier.meterSpacing == 8)
        #expect(tier.providerGapFloor == 12)
        #expect(tier.edgeGapWeight == 0.6)
        #expect(tier.showsPlanPill == false)
    }

    /// Only the tightest tier gives up type; the plan pill is the first thing it drops.
    @Test func onlyCompactStepsTheTypeLadderDownOrHidesThePlanPill() {
        for tier in [LargeWidgetDensity.roomy, .regular] {
            #expect(tier.typeStep == .standard)
            #expect(tier.showsPlanPill)
        }
        #expect(LargeWidgetDensity.compact.typeStep == .dense)
        #expect(LargeWidgetDensity.compact.showsPlanPill == false)
    }

    @Test func tokensNeverGrowAsTheTileGetsDenser() {
        let tiers: [LargeWidgetDensity] = [.roomy, .regular, .compact]
        for (looser, tighter) in zip(tiers, tiers.dropFirst()) {
            #expect(looser.barHeight > tighter.barHeight)
            #expect(looser.headerSpacing >= tighter.headerSpacing)
            #expect(looser.meterSpacing >= tighter.meterSpacing)
        }
        #expect(LargeWidgetDensity.roomy.barHeight > LargeWidgetDensity.compact.barHeight)
    }

    /// WCL2's grouping ratio has to survive the tier: header → first meter is always tighter
    /// than meter → meter, or the header stops belonging to the meters under it.
    @Test func everyTierKeepsTheHeaderCloserToItsMetersThanTheMetersAreToEachOther() {
        for tier in [LargeWidgetDensity.roomy, .regular, .compact] {
            #expect(tier.headerSpacing < tier.meterSpacing, "\(tier)")
            #expect(tier.meterSpacing < tier.providerGapFloor, "\(tier)")
        }
    }

    /// WCL1: the edge spacers are weighted below the provider gap so the tile's outer air
    /// never reads as wide as the space between two providers.
    @Test func edgeGapIsWeightedBelowTheProviderGap() {
        for tier in [LargeWidgetDensity.roomy, .regular, .compact] {
            #expect(tier.edgeGapWeight > 0 && tier.edgeGapWeight < 1, "\(tier)")
        }
    }

    // MARK: - Fixtures

    private func provider(id: String) -> WidgetProviderSummary {
        WidgetProviderSummary(
            id: id,
            displayName: id.capitalized,
            planLabel: nil,
            freshness: .live,
            windows: [weeklyWindow(), fiveHourWindow()],
            renewalDate: nil
        )
    }

    private func spendProvider(id: String) -> WidgetAPISpendSummary {
        WidgetAPISpendSummary(
            id: id,
            displayName: "OpenAI API",
            amount: 12.34,
            currency: "USD",
            periodLabel: "This month",
            capturedAt: now,
            freshness: .live
        )
    }

    private func weeklyWindow() -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .weekly,
            label: "Weekly",
            percentRemaining: 60,
            resetsAt: now,
            resetLabel: "Resets tomorrow",
            severity: .healthy
        )
    }

    private func fiveHourWindow() -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .fiveHour,
            label: "5-hour",
            percentRemaining: 60,
            resetsAt: now,
            resetLabel: "Resets in 2h",
            severity: .healthy
        )
    }

    private func extraWeeklyWindow(label: String) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .other(label),
            label: label,
            percentRemaining: 54,
            resetsAt: now,
            resetLabel: "Resets tomorrow",
            severity: .healthy
        )
    }
}
