import Foundation
import Testing
@testable import HeadroomCore

struct ReprintRecipeTests {
    private let ids: [ProviderID] = [.claude, .codex, .grok, .cursor, .copilot, .opencode, .antigravity]
    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
    private func key(_ id: ProviderID, _ account: AccountID = .primary) -> AccountKey {
        AccountKey(providerID: id, accountID: account)
    }
    private func meters(_ selected: [ProviderID]) -> [MenuBarMeter] {
        selected.enumerated().map { index, id in
            MenuBarMeter(summary: .init(text: "50%", providerID: id, detail: nil, isNeutral: false), fill: 0.2 + Double(index) * 0.1)
        }
    }
    private func entry(_ outcome: UserRefreshOutcome? = nil, at time: Double? = nil, origin: UserRefreshOrigin = .fullRefresh) -> UserRefreshEntry {
        .init(origin: origin, requestedAt: date(0), outcome: outcome, landedAt: time.map(date))
    }
    private func recipe(_ entries: [AccountKey: UserRefreshEntry], at time: Double, selected: [ProviderID]? = nil,
                        probing: Set<AccountKey> = [], ends: [AccountKey: Date] = [:], spend: Set<ProviderID> = [],
                        refreshing: Bool = true, clear: Double? = nil, automatic: Bool = false,
                        mains: [ProviderID: AccountKey]? = nil, reduceMotion: Bool = false) -> ReprintRecipe {
        let selected = selected ?? Array(ids.prefix(3))
        return ReprintRecipe(
            meters: automatic ? [.init(summary: .init(text: "50%", providerID: .codex, detail: nil, isNeutral: false), fill: nil)] : meters(selected),
            automatic: automatic, currentMains: mains ?? Dictionary(uniqueKeysWithValues: ids.map { ($0, key($0)) }),
            run: .init(startedAt: date(0), entries: entries, refreshingClearedAt: clear.map(date)),
            probingAccounts: probing, probeEndTimes: ends, spendInFlightProviders: spend,
            visibleWork: .init(isInFlight: refreshing && entries.values.contains { $0.origin != .setupCheck }, clearedAt: clear.map(date)), now: date(time), reduceMotion: reduceMotion
        )
    }

    @Test func threeIndependentLandingsPrintAndThenHandBackAfterHalfASecond() {
        let keys = Array(ids.prefix(3)).map { key($0) }
        let entries = Dictionary(uniqueKeysWithValues: zip(keys, [1.0, 1.8, 2.6]).map { ($0.0, entry(.live, at: $0.1)) })
        // Pure time derivation also makes a reopened popover pick up an in-progress print.
        let initial = recipe(entries, at: 0.3)
        #expect(initial.pills.allSatisfy { $0.ink == .ghost })
        #expect(initial.phase == .spinner)
        let first = recipe(entries, at: 1.175)
        #expect(first.pills[0].ink.progress.map { abs($0 - 0.5) < 0.00001 } == true)
        #expect(first.pills[1].ink == .ghost)
        let second = recipe(entries, at: 2)
        #expect(second.pills[0].ink == .full)
        #expect(second.pills[1].ink.isTransitioning)
        #expect(second.pills[2].ink == .ghost)
        let held = recipe(entries, at: 2.775, refreshing: false, clear: 2.6)
        #expect(held.phase == .hold && !held.isEnabled)
        #expect(held.pills[2].ink.isTransitioning)
        #expect(recipe(entries, at: 3.09, refreshing: false, clear: 2.6).phase == .hold)
        #expect(recipe(entries, at: 3.1, refreshing: false, clear: 2.6).phase == .rest)
        #expect(recipe(entries, at: 3.1, refreshing: false, clear: 2.6).isEnabled)
    }

    @Test func initialGhostWipeAndFreshPrintHaveOppositeTravelDirections() {
        let wiped = recipe([key(.claude): entry()], at: 0.1)
        guard case .ghostWipe(let wipeProgress) = wiped.pills[0].ink else {
            Issue.record("Refresh must wipe its main's old ink before the probe lands")
            return
        }
        #expect(abs(wipeProgress - 0.5) < 0.00001)
        #expect(wiped.pills[0].ink.coverage(at: 0.2) == 0.45)
        #expect(wiped.pills[0].ink.coverage(at: 0.8) == 1)
        #expect(wiped.pills[0].ink.coverage(at: 0.2) < wiped.pills[0].ink.coverage(at: 0.8))
        let printing = recipe([key(.claude): entry(.live, at: 1)], at: 1.175).pills[0].ink
        #expect(printing.coverage(at: 0.8) > printing.coverage(at: 0.2))
        #expect(printing.coverage(at: 0.2) == 0.45)
        #expect(printing.coverage(at: 0.8) == 1)
    }

    /// One to seven providers draw that many pills in menu bar order, and four or more are
    /// slim.
    @Test func oneToSevenPillsKeepMenuBarOrderAndFourOrMoreAreSlim() {
        for count in 1...7 {
            let selected = Array(ids.reversed().prefix(count))
            let result = recipe([key(.cursor): entry()], at: 0.3, selected: selected)
            #expect(result.pills.map(\.id) == selected.map(\.raw))
            #expect(result.usesSlimGeometry == (count >= 4))
            #expect(result.pills.map(\.level) == meters(selected).map { $0.fill! })
        }
    }

    @Test func mainActionFadesOnlyItsOwnPillAndExtraActionOnlySloshes() {
        let main = recipe([key(.claude): entry(origin: .accountAction)], at: 0.3, probing: [key(.claude)])
        #expect(main.pills[0].ink == .ghost && main.pills[0].isSloshing)
        #expect(main.pills.dropFirst().allSatisfy { $0.ink == .full && !$0.isSloshing })
        let extra = key(.claude, AccountID("work"))
        let result = recipe([extra: entry(origin: .accountAction)], at: 0.3, probing: [extra])
        #expect(result.pills[0].ink == .full && result.pills[0].isSloshing)
    }

    @Test func setupOnlyWorkLeavesTheButtonEnabledAndInkUntouched() {
        let result = recipe([key(.claude): entry(origin: .setupCheck)], at: 0.3, probing: [key(.claude)])
        #expect(result.phase == .rest && result.isEnabled)
        #expect(result.pills.allSatisfy { $0.ink == .full && !$0.isSloshing })
    }

    @Test func staleNeverPrintsAndDroppedEntriesDoNotHoldGhosts() {
        let stale = recipe([key(.claude): entry(.stale, at: 1.3)], at: 2, refreshing: false, clear: 1.3)
        #expect(stale.pills[0].ink == .ghost && !stale.pills[0].isSloshing)
        let dropped = recipe([key(.claude): entry(.dropped, at: 1.3)], at: 1.4)
        #expect(dropped.pills[0].ink == .full)
    }

    @Test func mainSwitchToAnUnrequestedAccountDoesNotPrintOldMain() {
        let replacement = key(.claude, AccountID("replacement"))
        let result = recipe([key(.claude): entry()], at: 0.3, mains: [.claude: replacement])
        #expect(result.pills[0].ink == .full)
        #expect(result.pills[0].level == 0.2)
    }

    @Test func spendTailMovesMatchingProvidersOrTheWholeUnmatchedRowAndHoldUsesClearTime() {
        let landed = [key(.claude): entry(.live, at: 1)]
        let matched = recipe(landed, at: 3.2, selected: [.claude, .grok], spend: [.claude])
        #expect(matched.phase == .spendTail)
        #expect(matched.pills[0].isSloshing && !matched.pills[1].isSloshing)
        #expect(matched.pills.allSatisfy { $0.ink == .full })
        let unmatched = recipe(landed, at: 3.2, selected: [.grok, .cursor], spend: [.codex])
        #expect(unmatched.pills.allSatisfy { $0.isSloshing })
        let idleLanesTail = recipe(landed, at: 3.2)
        #expect(idleLanesTail.phase == .spendTail && idleLanesTail.pills.allSatisfy { $0.isSloshing })
        #expect(recipe(landed, at: 4.1, refreshing: false, clear: 4).phase == .hold)
    }

    @Test func spendOnlyWithoutASubscriptionRunStillWorks() {
        let result = ReprintRecipe(meters: meters([.claude, .grok]), automatic: false,
            currentMains: [:], run: nil, probingAccounts: [], probeEndTimes: [:], spendInFlightProviders: [.claude],
            visibleWork: .init(isInFlight: true), now: date(4))
        #expect(result.phase == .spendTail && !result.isEnabled)
        #expect(result.pills[0].isSloshing && !result.pills[1].isSloshing)
    }

    @Test func waveFinishesFromProbeEndRatherThanViewLifetime() {
        #expect(recipe([key(.claude): entry()], at: 4.9, ends: [key(.claude): date(4.3)]).pills[0].isSloshing)
        #expect(!recipe([key(.claude): entry()], at: 5, ends: [key(.claude): date(4.3)]).pills[0].isSloshing)
    }

    @Test func automaticUsesAllMainsEvenWhenTheSummaryNamesCodexAndPrintsDecorativeLevel() {
        let pending = recipe([key(.claude): entry()], at: 0.3, probing: [key(.grok, AccountID("extra"))], automatic: true)
        #expect(pending.pills.count == 1)
        #expect(pending.pills[0].id == "automatic")
        #expect(pending.pills[0].ink == .ghost && pending.pills[0].isSloshing)
        let printed = recipe([key(.claude): entry(.live, at: 1)], at: 1.2, automatic: true)
        #expect(printed.pills[0].ink.isTransitioning)
        #expect(printed.pills[0].level == 0.46)
    }

    @Test func automaticWaitsForAllCurrentMainReadingsAndStalePreventsFalsePrint() {
        let partial = recipe([key(.claude): entry(.live, at: 1), key(.codex): entry()], at: 1.2, automatic: true)
        #expect(partial.pills[0].ink == .ghost)
        let stale = recipe([key(.claude): entry(.live, at: 1), key(.codex): entry(.stale, at: 2)], at: 2.1, automatic: true)
        #expect(stale.pills[0].ink == .ghost)
    }

    @Test func reduceMotionCrossfadesInkAndKeepsWavesFlat() {
        let wipe = recipe([key(.claude): entry()], at: 0.1, probing: [key(.claude)], reduceMotion: true)
        guard case .crossfade(let wipeProgress) = wipe.pills[0].ink else {
            Issue.record("Reduce Motion must crossfade the whole filled level uniformly")
            return
        }
        #expect(abs(wipeProgress - 0.5) < 0.00001)
        #expect(wipe.pills.allSatisfy { !$0.isSloshing && !$0.ink.isTravelling })
        let print = recipe([key(.claude): entry(.live, at: 1)], at: 1.175, reduceMotion: true)
        #expect(print.pills[0].ink.progress.map { abs($0 - 0.5) < 0.00001 } == true)
        #expect(!print.pills[0].ink.isTravelling)
        #expect(abs(print.pills[0].ink.coverage(at: 0.2) - print.pills[0].ink.coverage(at: 0.8)) < 0.00001)
    }
}
