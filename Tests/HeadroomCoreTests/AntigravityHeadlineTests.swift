import Foundation
import Testing
@testable import HeadroomCore

/// Every single-slot surface headlines the Antigravity row with the least left across both
/// pools, whichever pool it is in. The reading here puts the Claude & GPT 5-hour row lowest
/// while the Gemini pool comes first, so a surface that took the first row would be wrong.
@Suite(.serialized)
struct AntigravityHeadlineTests {
    /// Friday 25 Sep 2026, 10:00 AM in Los Angeles.
    private let now = Date(timeIntervalSince1970: 1_790_355_600)
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60
    private let tightest = WindowKind.other("Claude & GPT 5h")

    private var snapshot: UsageSnapshot {
        let windows = AntigravityProvider.windows(for: [
            AntigravityBucket(pool: .gemini, window: .weekly, remainingFraction: 0.60, resetsAt: now.addingTimeInterval(5 * day)),
            AntigravityBucket(pool: .gemini, window: .fiveHour, remainingFraction: 0.80, resetsAt: now.addingTimeInterval(3 * hour)),
            AntigravityBucket(pool: .claudeAndGPT, window: .weekly, remainingFraction: 0.50, resetsAt: now.addingTimeInterval(5 * day)),
            AntigravityBucket(pool: .claudeAndGPT, window: .fiveHour, remainingFraction: 0.10, resetsAt: now.addingTimeInterval(2 * hour)),
        ])
        return UsageSnapshot(
            providerID: .antigravity, windows: windows, planLabel: "1,200 credits", capturedAt: now, freshness: .live)
    }

    private func envelope(_ context: WidgetProjectionContext) -> WidgetSnapshotEnvelope {
        WidgetSnapshotProjector.project(
            snapshots: [.antigravity: snapshot],
            providerOrder: [.antigravity],
            displayNames: [.antigravity: "Antigravity"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now,
            context: context
        )
    }

    @Test func theSnapshotLeadsWithTheGeminiPoolSoFirstRowWouldBeWrong() {
        #expect(snapshot.windows.first?.kind == .other("Gemini weekly"))
        #expect(snapshot.windows.map(\.kind).contains(tightest))
    }

    @Test(arguments: [WidgetProjectionContext.localWidget, .phoneSync(attention: [:])])
    func homeWidgetsHeadlineTheTightestRowAcrossBothPools(_ context: WidgetProjectionContext) throws {
        let provider = try #require(envelope(context).providers.first)
        #expect(provider.windows.count == 4)
        let recipe = WidgetStyleProviderRecipe(summary: provider)
        #expect(recipe.primary?.kind == .other("Claude & GPT 5h"))
        #expect(recipe.primary?.widgetDisplayLabel == "Claude & GPT 5h")
        #expect(recipe.tightest == recipe.primary)
        for style in WidgetLayoutStyle.allCases {
            let small = WidgetStyleRecipe(style: style, family: .small, envelope: envelope(context))
            #expect(small.providers.first?.primary?.kind == .other("Claude & GPT 5h"), "\(style)")
        }
    }

    @Test(arguments: LockScreenWidgetFamily.allCases)
    func lockScreenHeadlinesTheTightestRow(_ family: LockScreenWidgetFamily) {
        for choice in [LockScreenProviderChoice.automatic, .antigravity] {
            let recipe = LockScreenWidgetRecipe(
                style: .liquidLevel, family: family, providerChoice: choice,
                state: .content(envelope(.phoneSync(attention: [:]))), now: now)
            #expect(recipe.slots.first?.primary.window?.kind == .other("Claude & GPT 5h"), "\(family) \(choice)")
        }
    }

    /// The rectangle prints the short pool names ("Claude & GPT weekly" overflowed Vessel
    /// Hero's caption and squeezed its side column); VoiceOver keeps the full names.
    @Test func lockScreenRectangleUsesShortPoolNamesButSpeaksFullOnes() throws {
        let recipe = LockScreenWidgetRecipe(
            style: .vesselHero, family: .rectangle, providerChoice: .antigravity,
            state: .content(envelope(.phoneSync(attention: [:]))), now: now)
        let slot = try #require(recipe.slots.first)
        #expect(slot.primary.caption == "Other 5h")
        #expect(slot.secondary.map(\.caption) == ["Gemini wk", "Gemini 5h"])
        #expect(slot.primary.accessibilityText.hasPrefix("Claude & GPT 5h, 10 percent left"))
    }

    @MainActor
    @Test func theMenuBarPillFollowsTheTightestRow() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        preferences.setSurfaceEnabled(true, for: .antigravitySubscription)
        let store = UsageStore(
            providers: [StubProvider(id: .antigravity, displayName: "Antigravity", snapshot: snapshot)],
            preferences: preferences
        )
        await store.refreshAll()
        // The fresh-install weekly default names no Antigravity row, so the pill follows the
        // closest-to-limit row, which is the Claude & GPT 5-hour one.
        #expect(store.resolvedMenuBarWindowKind(for: .antigravity) == tightest)
    }

    @Test func siriSpeaksTheTightestRowFirst() throws {
        let rows = CompanionPhoneProjection.windows(of: snapshot).map {
            CompanionResolvedWindow(summary: $0.widgetSummary, isSpark: $0.isSpark)
        }
        let account = CompanionResolvedAccount(
            accountID: "primary", title: "Antigravity", planName: "1,200 credits", freshness: .live, attention: nil,
            bankedResets: nil, capturedAt: now, windows: rows, isMain: true)
        let provider = CompanionResolvedProvider(
            id: ProviderID.antigravity.raw, displayName: "Antigravity", source: .v4(.manifestDigestMatched),
            capabilityAttention: nil, mainAccount: account, extraAccounts: [], omittedAccountCount: 0,
            lag: .current, payloadGeneration: 1, effectiveIntervalSeconds: 300)
        let resolved = CompanionResolvedSnapshot(
            state: .content(
                CompanionResolvedContent(
                    origin: .v4, notice: nil, sourceID: nil, generation: 1,
                    generatedAt: now, chosenIntervalSeconds: 300, display: nil,
                    widgetProviderSelection: nil, widgetSparkEnabled: false, reminderSummary: nil,
                    answeredRequests: [], ladder: .full, providers: [provider], apiSpend: [],
                    freshness: CompanionFreshnessInputs(
                        generatedAt: now, firstSeen: now,
                        largestEffectiveIntervalSeconds: 300, isV3Only: false))))
        let answer = UsageAnswerComposer.answer(
            for: .antigravity, in: resolved,
            context: UsageAnswerContext(
                now: now, isProtectedDataAvailable: true, isSampleData: false, sparkEnabled: nil,
                timeZone: TimeZone(identifier: "America/Los_Angeles")!, locale: Locale(identifier: "en_US")))
        #expect(answer.kind == .usage)
        #expect(answer.percentLeft == 10)
        #expect(answer.windowLabel == "Claude & GPT 5h")
        #expect(answer.dialog.hasPrefix("Antigravity has 10% left in the Claude & GPT 5h window"))
    }
}
