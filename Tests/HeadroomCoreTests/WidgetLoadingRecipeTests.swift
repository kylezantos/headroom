import Foundation
import Testing
@testable import HeadroomCore

struct WidgetLoadingRecipeTests {
    @Test func placeholdersRespectExistingGuttersAndTheRowBoundary() throws {
        for state in WidgetStatusState.allCases {
            for family in WidgetFamily.allCases {
                let placeholder = state.loadingPlaceholder(availableWidth: WidgetMetrics.markSlot(for: family))
                if state == .macPending || state == .iosWaitingForMac {
                    let mark = try #require(placeholder)
                    #expect(mark.pills.count == 1)
                    #expect(mark.width <= WidgetMetrics.markSlot(for: family))
                    #expect(mark.pills[0].level == 0.46)
                    #expect(mark.pills[0].ink == .ghost)
                    #expect(!mark.pills[0].isSloshing)
                } else {
                    #expect(placeholder == nil)
                }
            }
        }
        #expect(!WidgetLoadingPlaceholderRecipe(availableWidth: 43.99).usesRow)
        let row = WidgetLoadingPlaceholderRecipe(availableWidth: 44)
        #expect(row.usesRow)
        #expect(row.pills.count == 3)
        #expect(Set(row.pills.map(\.id)).count == 3)
        #expect(Set(row.pills.map(\.level)) == [0.46])
    }

    @Test func waitingInkIsProviderAndStyleIndependentButRequiresNoReading() throws {
        for id in ["claude", "codex", "grok", "cursor"] {
            let pending = StyleFixture.provider(id, id, freshness: .pending, [])
            for style in WidgetLayoutStyle.allCases {
                for family in WidgetFamily.allCases {
                    let provider = try #require(StyleFixture.recipe(style, family, [pending]).providers.first)
                    let pill = try #require(provider.waitingPill)
                    #expect(pill.level == 0.46)
                    #expect(pill.ink == .ghost)
                    #expect(!pill.isSloshing)
                    #expect(provider.primary == nil)
                }
            }
            let stale = StyleFixture.provider(id, id, freshness: .stale(message: "Unavailable", needsAttention: false), [])
            #expect(WidgetStyleProviderRecipe(summary: stale).waitingPill == nil)
            let unavailable = StyleFixture.provider(id, id, [
                StyleFixture.window(.weekly, label: "Weekly", percent: 70, freshness: .unavailable(since: StyleFixture.now)),
            ])
            #expect(WidgetStyleProviderRecipe(summary: unavailable).waitingPill == nil)
        }
    }

    @Test func checkingStaysBusyUntilItsWaveWrapsAndNeverPrintsAReading() {
        let end = Date(timeIntervalSince1970: 10.55)
        let checking = LoadingCheckRecipe(isChecking: true, endedAt: nil, now: end, reduceMotion: false)
        #expect(checking.isWorking)
        #expect(checking.pills.allSatisfy { $0.isSloshing })
        #expect(checking.waveEnd == nil)
        let tail = LoadingCheckRecipe(isChecking: false, endedAt: end, now: Date(timeIntervalSince1970: 10.99), reduceMotion: false)
        #expect(tail.isWorking)
        #expect(tail.waveEnd == Date(timeIntervalSince1970: 11))
        #expect(tail.pills.allSatisfy { !$0.isSloshing && $0.ink == .ghost && $0.level == 0.46 })
        #expect(!LoadingCheckRecipe(isChecking: false, endedAt: end, now: Date(timeIntervalSince1970: 11), reduceMotion: false).isWorking)
        #expect(!LoadingCheckRecipe(isChecking: false, endedAt: nil, now: end, reduceMotion: false).isWorking)
    }

    @Test func reducedMotionKeepsCheckingDistinctAndReleasesImmediatelyAfterTheRead() {
        let now = Date(timeIntervalSince1970: 10.55)
        let checking = LoadingCheckRecipe(isChecking: true, endedAt: nil, now: now, reduceMotion: true)
        #expect(checking.isWorking)
        #expect(checking.pills.count == 3)
        #expect(checking.pills.allSatisfy { !$0.isSloshing && $0.ink == .ghost })
        let finished = LoadingCheckRecipe(isChecking: false, endedAt: now, now: now, reduceMotion: true)
        #expect(!finished.isWorking)
        #expect(finished.waveEnd == nil)
    }

    @Test func pendingRenderFixturesExerciseEveryProviderWithoutAReading() throws {
        var ids: Set<String> = []
        for name in ["pendingAll", "pendingPools", "pendingCodex", "pendingCursor"] {
            let envelope = try #require(DemoScreenshotData.styleFixture(name, now: StyleFixture.now))
            for style in WidgetLayoutStyle.allCases {
                for family in WidgetFamily.allCases {
                    let recipe = WidgetStyleRecipe(style: style, family: family, envelope: envelope)
                    #expect(!recipe.providers.isEmpty)
                    #expect(recipe.providers.allSatisfy { $0.waitingPill != nil && !$0.hasDisplayValue })
                    #expect(recipe.washSegments.allSatisfy { $0.fraction == nil })
                }
            }
            ids.formUnion(envelope.widgetProviders.map(\.id))
        }
        #expect(ids == ["claude", "codex", "grok", "cursor"])
    }
}
