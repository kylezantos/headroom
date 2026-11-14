import Foundation
import Testing
@testable import HeadroomCore

struct LockScreenWidgetRecipeTests {
    typealias F = StyleFixture

    private func recipe(
        _ style: WidgetLayoutStyle = .liquidLevel,
        _ family: LockScreenWidgetFamily = .circle,
        _ providers: [WidgetProviderSummary],
        choice: LockScreenProviderChoice = .automatic,
        demo: Bool = false
    ) -> LockScreenWidgetRecipe {
        let envelope = F.envelope(providers)
        return LockScreenWidgetRecipe(style: style, family: family, providerChoice: choice,
                                      state: demo ? .demo(envelope) : .content(envelope), now: F.now)
    }

    @Test func automaticTightestRanksBeyondTheTwoWidgetProviders() throws {
        let r = recipe(.tightestFirst, .circle, [F.claude(), F.codex(), F.cursor(otherModels: 8)])
        let slot = try #require(r.slots.first)
        #expect(slot.providerID == "cursor")
        #expect(slot.primary.caption == "Other")
        #expect(slot.primary.numberText == "8%")
        #expect(slot.primary.state == .critical)
        #expect(slot.primary.usesKnockout)
    }

    @Test func absentPinnedProviderNeverSubstitutesInAnyFamilyOrStyle() throws {
        for style in WidgetLayoutStyle.allCases {
            for family in LockScreenWidgetFamily.allCases {
                let r = recipe(style, family, [F.claude(), F.codex()], choice: .grok)
                let slot = try #require(r.slots.first)
                #expect(r.slots.count == 1)
                #expect(slot.providerID == "grok")
                #expect(slot.primary.state == .off)
                #expect(slot.primary.numberText == "—")
                #expect(slot.primary.fillFraction == 0)
                #expect(slot.primary.caption == "Off")
                #expect(r.inlineTextCandidates.first == "Grok · Off")
                #expect(r.inlineImage == .warning)
            }
        }
    }

    @Test func pinnedCopilotWithNoSyncedCopilotShowsOff() throws {
        for family in LockScreenWidgetFamily.allCases {
            let r = recipe(.liquidLevel, family, [F.claude(), F.codex()], choice: .copilot)
            let slot = try #require(r.slots.first)
            #expect(r.slots.count == 1)
            #expect(slot.providerID == "copilot")
            #expect(slot.primary.state == .off)
            #expect(r.inlineTextCandidates.first == "Copilot · Off")
        }
    }

    @Test func pinnedOpenCodeWithNoSyncedOpenCodeShowsOffAndNeverFallsBack() throws {
        for style in WidgetLayoutStyle.allCases {
            for family in LockScreenWidgetFamily.allCases {
                let r = recipe(style, family, [F.claude(), F.codex(), F.grok()], choice: .opencode)
                let slot = try #require(r.slots.first)
                #expect(r.slots.count == 1)
                #expect(slot.providerID == "opencode")
                #expect(slot.primary.state == .off)
                #expect(slot.primary.numberText == "—")
                #expect(r.inlineTextCandidates.first == "OpenCode · Off")
            }
        }
    }

    /// KTD15 (OpenCode plan): OpenCode's three windows project from the Mac (KTD6) with
    /// weekly as the primary; a family with less room sheds the monthly window, the last
    /// secondary, and never relabels it.
    @Test func openCodeSecondariesDropMonthlyByFamilyWithoutRelabelling() throws {
        let envelope = OpenCodePhoneFixture.project(OpenCodePhoneFixture.go())
        for style in WidgetLayoutStyle.allCases where style != .tightestFirst {
            for family in LockScreenWidgetFamily.allCases {
                let r = LockScreenWidgetRecipe(
                    style: style, family: family, providerChoice: .opencode,
                    state: .content(envelope), now: OpenCodePhoneFixture.captured)
                let slot = try #require(r.slots.first)
                #expect(slot.primary.window?.kind == .weekly, "\(style) \(family)")
                let kinds = slot.secondary.map(\.window?.kind)
                let order: [WidgetWindowKind?] = [.fiveHour, .other("Monthly")]
                #expect(Array(order.prefix(kinds.count)) == kinds, "\(style) \(family)")
                if let monthly = slot.secondary.first(where: { $0.window?.kind == .other("Monthly") }) {
                    #expect(monthly.window?.label == "Monthly")
                    #expect(monthly.caption.contains("Month") || monthly.caption.contains("Mo"), "\(monthly.caption)")
                }
            }
        }
        let liquid = LockScreenWidgetRecipe(
            style: .liquidLevel, family: .rectangle, providerChoice: .opencode,
            state: .content(envelope), now: OpenCodePhoneFixture.captured)
        #expect(liquid.slots.first?.secondary.map(\.window?.kind) == [.fiveHour])
        let nested = LockScreenWidgetRecipe(
            style: .nestedMeter, family: .rectangle, providerChoice: .opencode,
            state: .content(envelope), now: OpenCodePhoneFixture.captured)
        #expect(nested.slots.first?.secondary.map(\.window?.kind) == [.fiveHour, .other("Monthly")])
    }

    @Test func unavailableWeeklyRemainsPrimary() throws {
        let claude = F.provider("claude", "Claude", [
            F.window(.fiveHour, label: "5h", percent: 72),
            F.window(.weekly, label: "Weekly", percent: 9, freshness: .unavailable(since: F.now)),
        ])
        let main = try #require(recipe(.liquidLevel, .circle, [claude], choice: .claude).slots.first?.primary)
        #expect(main.window?.kind == .weekly)
        #expect(main.state == .unavailable)
        #expect(main.numberText == "—")
        #expect(main.fillFraction == 0)
        #expect(main.caption == "Weekly")
    }

    @Test func gaugePairSkipsUnavailableSecondButKeepsAMissingSlot() throws {
        let claude = F.provider("claude", "Claude", [
            F.window(.weekly, label: "Weekly", percent: 15),
            F.window(.fiveHour, label: "5h", percent: 72),
            F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 5, freshness: .unavailable(since: F.now)),
        ])
        let r = recipe(.tightestFirst, .rectangle, [claude], choice: .claude)
        #expect(r.slots.map(\.primary.numberText) == ["15%", "72%"])
        #expect(!r.showsOnlyLimit)
        let missing = F.provider("claude", "Claude", [
            F.window(.weekly, label: "Weekly", percent: 15),
            F.window(.fiveHour, label: "5h", percent: 72, freshness: .unavailable(since: F.now)),
        ])
        let m = recipe(.tightestFirst, .rectangle, [missing], choice: .claude)
        #expect(m.slots.map(\.primary.numberText) == ["15%", "—"])
        #expect(!m.showsOnlyLimit)
        let only = recipe(.tightestFirst, .rectangle, [F.grok()], choice: .grok)
        #expect(only.showsOnlyLimit)
        #expect(only.slots.count == 1)
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        let withPending = recipe(.tightestFirst, .rectangle, [F.grok(), pending])
        #expect(withPending.slots.map(\.primary.numberText) == ["56%", "—"])
        #expect(withPending.slots.last?.primary.state == .pending)
        #expect(!withPending.showsOnlyLimit)
    }

    @Test func inlinePoolNamesHaveHonestLongAndShortCandidates() {
        let r = recipe(.liquidLevel, .inline, [F.grok(), F.cursor()])
        #expect(r.inlineTextCandidates.first == "Grok 56% · Other Models 37%")
        #expect(r.inlineTextCandidates.contains("Grok 56% · Cursor Other 37%"))
        #expect(r.inlineTextCandidates.last == "56% · Cursor Other 37%")
    }

    /// CA-W6 (revisits design 10 / R11 for this rung only): with two providers on one line, a
    /// rung that keeps every owner's name and drops only Cursor's pool comes before the
    /// minimal one, so the first number never loses its owner.
    @Test func inlineKeepsEveryOwnerBeforeTheMinimalRung() throws {
        let r = recipe(.liquidLevel, .inline, [F.grok(), F.cursor()])
        let attributed = try #require(r.inlineTextCandidates.firstIndex(of: "Grok 56% · Cursor 37%"))
        let minimal = try #require(r.inlineTextCandidates.firstIndex(of: "56% · Cursor Other 37%"))
        #expect(attributed < minimal)
        #expect(r.inlineTextCandidates.firstIndex(of: "Grok 56% · Cursor Other 37%").map { $0 < attributed } == true)
        let pair = recipe(.liquidLevel, .inline, [F.claude(), F.codex()])
        #expect(pair.inlineTextCandidates == ["Claude 38% · Codex 64%", "38% · 64%"])
        let opencode = F.provider("opencode", "OpenCode", [
            F.window(.weekly, label: "Weekly", percent: 44, resetIn: 3 * 86_400),
            F.window(.other("Monthly"), label: "Monthly", percent: 90, resetIn: 19 * 86_400, billingPeriod: F.month),
        ])
        let withOpenCode = recipe(.liquidLevel, .inline, [opencode, F.cursor()])
        #expect(withOpenCode.inlineTextCandidates.contains("OpenCode 44% · Cursor 37%"))
    }

    @Test func singleCursorInlineStillAlwaysNamesItsPool() {
        let r = recipe(.liquidLevel, .inline, [F.cursor()], choice: .cursor)
        #expect(r.inlineTextCandidates.allSatisfy { !$0.contains("Cursor 37%") })
    }

    /// CA-W6: a caption tries its full label, then the compact one, before it truncates.
    @Test func vesselHeroRectangleCaptionFallsBackToTheCompactPoolName() throws {
        let r = recipe(.vesselHero, .rectangle, [F.grok(), F.cursor()])
        let cursor = try #require(r.slots.first { $0.providerID == "cursor" })
        #expect(cursor.primary.captionLadder == ["Other Models", "Other"])
        let grok = try #require(r.slots.first { $0.providerID == "grok" })
        #expect(grok.primary.captionLadder == ["Weekly"])
    }

    /// CA-W6: a stale circle caption of six characters or fewer drops its warning glyph before
    /// it truncates; the dimmed ink still says the reading is old.
    @Test func staleShortCircleCaptionDropsTheGlyphBeforeTruncating() throws {
        let staleFable = F.provider("claude", "Claude", [
            F.window(.weekly, label: "Weekly", percent: 38, resetIn: 4 * 86_400),
            F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 5,
                     freshness: .stale(observedAt: F.now.addingTimeInterval(-7_200)), resetIn: 4 * 86_400),
        ])
        let r = recipe(.tightestFirst, .circle, [staleFable])
        let slot = try #require(r.slots.first)
        #expect(slot.primary.state == .stale)
        #expect(slot.primary.captionLadder == ["⚠ Fable", "Fable"])
        let long = F.provider("cursor", "Cursor", freshness: .stale(message: "Offline", needsAttention: false), [
            F.window(.other("Cursor Models"), label: "Cursor Models", percent: 37, billingPeriod: F.month),
        ])
        let cursor = try #require(recipe(.liquidLevel, .circle, [long], choice: .cursor).slots.first)
        #expect(cursor.primary.captionLadder == ["⚠ Models", "Models"])
        let live = try #require(recipe(.liquidLevel, .circle, [F.claude()]).slots.first)
        #expect(live.primary.captionLadder == ["Weekly"])
    }

    @Test func captionLadderEntriesKeepTheWindowsState() throws {
        let r = recipe(.vesselHero, .rectangle, [F.grok(), F.cursor()])
        let cursor = try #require(r.slots.first { $0.providerID == "cursor" })
        let compact = cursor.primary.captioned("Other")
        #expect(compact.caption == "Other")
        #expect(compact.state == cursor.primary.state)
        #expect(compact.numberText == cursor.primary.numberText)
    }

    @Test func inlineShortensBeforeTruncatingWithoutLosingStateOrCursorPool() {
        #expect(recipe(.liquidLevel, .inline, [F.claude(), F.codex()]).inlineTextCandidates.last == "38% · 64%")
        let window = F.window(.fiveHour, label: "5h", percent: 8, resetIn: 3 * 3600 + 15 * 60)
        let r = recipe(.tightestFirst, .inline, [F.provider("claude", "Claude", [window])])
        #expect(r.inlineTextCandidates.first == "Claude 5-hour 8% · refills in 3h 15m")
        #expect(r.inlineTextCandidates.contains("5-hour 8% · 3h"))
        #expect(r.inlineTextCandidates.last == "8% · 3h")
        let cursor = recipe(.tightestFirst, .inline, [F.cursor(otherModels: 8)])
        #expect(cursor.inlineTextCandidates.last == "Cursor Other 8% · 2d")
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        #expect(recipe(.liquidLevel, .inline, [pending, F.grok()]).inlineTextCandidates.last == "Claude · Waiting · 56%")
    }

    @Test func accessibilityIncludesOnlyTheWindowsEachDesignDraws() {
        let circle = recipe(.liquidLevel, .circle, [F.claude()])
        #expect(circle.slots.first?.secondary.isEmpty == true)
        #expect(!circle.accessibilityText.contains("5-hour"))
        let nested = recipe(.nestedMeter, .circle, [F.claude()])
        #expect(nested.slots.first?.secondary.count == 2)
        let pair = recipe(.vesselHero, .rectangle, [F.claude(), F.codex()])
        #expect(pair.slots.allSatisfy { $0.secondary.isEmpty })
        let pinnedLiquid = recipe(.liquidLevel, .rectangle, [F.claude()], choice: .claude)
        #expect(pinnedLiquid.slots.first?.secondary.map(\.window?.kind) == [.fiveHour])
    }

    @Test func resetReachedWinsOverCriticalButNotStale() throws {
        let reached = F.window(.weekly, label: "Weekly", percent: 9, resetIn: -60)
        for family in [LockScreenWidgetFamily.circle, .rectangle] {
            let main = try #require(recipe(.liquidLevel, family, [F.provider("claude", "Claude", [reached])]).slots.first?.primary)
            #expect(main.state == .resetReached)
            #expect(!main.usesKnockout)
            #expect(main.fillFraction == 0.09)
            #expect(main.refillText == "Refills now")
        }
        let stale = F.provider("claude", "Claude", freshness: .stale(message: "Offline", needsAttention: false), [reached])
        #expect(recipe(.liquidLevel, .circle, [stale]).slots.first?.primary.state == .stale)
    }

    @Test func everyNonTightestCircleUsesTheHomeSingleProviderPick() {
        let pending = F.provider("claude", "Claude", freshness: .pending, [])
        for style in WidgetLayoutStyle.allCases where style != .tightestFirst {
            let r = recipe(style, .circle, [pending, F.codex()])
            let home = F.recipe(.liquidLevel, .small, [pending, F.codex()])
            #expect(r.slots.map(\.providerID) == home.providers.map(\.id))
        }
        let single = recipe(.liquidLevel, .rectangle, [F.grok()])
        #expect(single.isSingleProvider)
        #expect(single.slots.count == 1)
    }

    @Test func signedOutAndPendingNeverBorrowAnotherProvidersNumber() throws {
        for family in LockScreenWidgetFamily.allCases {
            for style in WidgetLayoutStyle.allCases {
                let signedOut = F.provider("claude", "Claude", freshness: .stale(message: "Sign in", needsAttention: true), [])
                let r = recipe(style, family, [signedOut, F.codex()], choice: .claude)
                let main = try #require(r.slots.first?.primary)
                #expect(main.state == .signIn)
                #expect(main.numberText == "—")
                #expect(main.fillFraction == 0)
                #expect(main.caption == "Sign in")
                #expect(r.inlineTextCandidates.first == "Claude · Sign in")
                let pending = F.provider("claude", "Claude", freshness: .pending, [])
                let p = recipe(style, family, [pending], choice: .claude)
                #expect(p.slots.first?.primary.state == .pending)
                #expect(p.slots.first?.primary.caption == "Waiting")
                #expect(p.inlineImage == .warning)
            }
        }
    }

    @Test func providerStalenessDemotesEveryWindowAndCaptionsWarn() throws {
        let live = F.claude()
        let stale = F.provider(live.id, live.displayName, freshness: .stale(message: "Offline", needsAttention: false), live.windows)
        let slot = try #require(recipe(.nestedMeter, .rectangle, [stale]).slots.first)
        for window in [slot.primary] + slot.secondary {
            #expect(window.state == .stale)
            #expect(window.window?.freshness.isStale == true)
            #expect(window.caption.hasPrefix("⚠ "))
            #expect(!window.usesKnockout)
            #expect(window.accessibilityText.contains("last known"))
        }
    }

    @Test func criticalFollowsSourceSeverityNotARecalculatedThreshold() throws {
        let window = F.window(.weekly, label: "Weekly", percent: 50, severity: .critical)
        let main = try #require(recipe(.liquidLevel, .circle, [F.provider("claude", "Claude", [window])]).slots.first?.primary)
        #expect(main.state == .critical)
        #expect(main.usesKnockout)
        let lowNumber = F.window(.weekly, label: "Weekly", percent: 9, severity: .healthy)
        #expect(recipe(.liquidLevel, .circle, [F.provider("claude", "Claude", [lowNumber])]).slots.first?.primary.state == .live)
    }

    @Test func demoCaptionWinsOverCursorPoolAndAllOtherSizesHavePrefix() {
        for family in LockScreenWidgetFamily.allCases {
            let r = recipe(.liquidLevel, family, [F.cursor()], choice: .cursor, demo: true)
            #expect(r.isDemo)
            if family == .circle { #expect(r.slots.first?.primary.caption == "Demo") }
            #expect(r.inlineTextCandidates.allSatisfy { $0.hasPrefix("Demo · ") })
            #expect(r.headingPrefix == "Demo · ")
            #expect(r.accessibilityText.hasPrefix("Demo"))
        }
    }

    @Test func cursorAlwaysNamesItsPoolIncludingLoneFallbackAndStale() throws {
        for label in ["Cursor Models", "Other Models", "Included"] {
            let window = F.window(.other(label), label: label, percent: 37, billingPeriod: F.month)
            let cursor = F.provider("cursor", "Cursor", [window])
            let circle = recipe(.liquidLevel, .circle, [cursor], choice: .cursor)
            #expect(circle.slots.first?.primary.caption == (label == "Cursor Models" ? "Models" : label == "Other Models" ? "Other" : "Included"))
            let rectangle = recipe(.liquidLevel, .rectangle, [cursor], choice: .cursor)
            #expect(rectangle.slots.first?.primary.caption == label)
            let inline = recipe(.liquidLevel, .inline, [cursor], choice: .cursor)
            #expect(inline.inlineTextCandidates.allSatisfy { !$0.contains("Cursor 37%") })
            #expect(inline.inlineTextCandidates.last?.contains("Cursor \(label == "Cursor Models" ? "Models" : label == "Other Models" ? "Other" : "Included") 37%") == true)
            let stale = F.provider("cursor", "Cursor", freshness: .stale(message: "Offline", needsAttention: false), [window])
            #expect(recipe(.liquidLevel, .circle, [stale]).slots.first?.primary.caption.hasPrefix("⚠ ") == true)
        }
    }

    @Test func inlineVesselStepUsesLowestPrintedValueAndPositiveNeverEmpty() {
        #expect(recipe(.liquidLevel, .inline, [F.grok(56), F.cursor(otherModels: 37)]).inlineImage == .vessel(level: 4))
        #expect(recipe(.liquidLevel, .inline, [F.grok(3)]).inlineImage == .vessel(level: 1))
        #expect(recipe(.liquidLevel, .inline, [F.grok(0)]).inlineImage == .vessel(level: 0))
        let stale = F.provider("grok", "Grok", freshness: .stale(message: "Offline", needsAttention: false), F.grok().windows)
        #expect(recipe(.liquidLevel, .inline, [stale]).inlineImage == .warning)
    }

    @Test func tightestIncludesModelAndSparkAndStableTies() {
        let r = recipe(.tightestFirst, .rectangle, [F.claude(fable: 5), F.codex(spark: 3)])
        #expect(r.slots.map(\.primary.caption) == ["Spark", "Fable"])
        let tied = recipe(.tightestFirst, .rectangle, [F.grok(37), F.cursor(otherModels: 37)])
        #expect(tied.slots.map(\.providerID) == ["grok", "cursor"])
    }

    @Test func refillAndAbsoluteResetUseSharedFormattersAndUnavailableOmitsBoth() throws {
        let main = try #require(recipe(.tightestFirst, .inline, [F.claude(fiveHour: 8)]).slots.first?.primary)
        #expect(main.refillText == "Refills in 3h")
        let window = try #require(main.window)
        #expect(main.resetText == "Resets \(ResetClockFormatter.phrase(for: F.now.addingTimeInterval(3 * 3600), now: F.now))")
        #expect(main.refillText == "Refills in \(try #require(window.resetSchedule.meterResetLine(now: F.now)).countdown)")
        #expect(recipe(.tightestFirst, .inline, [F.claude(fiveHour: 8)]).inlineTextCandidates.first?.contains("refills in 3h") == true)
        let unavailable = F.provider("grok", "Grok", [F.window(.other("Weekly"), label: "Weekly", percent: 8, freshness: .unavailable(since: F.now), billingPeriod: F.week)])
        #expect(recipe(.liquidLevel, .rectangle, [unavailable]).slots.first?.primary.resetText == nil)
        #expect(recipe(.liquidLevel, .rectangle, [unavailable]).slots.first?.primary.refillText == nil)
    }

    @Test func everyStatusGetsFormsInAllFamiliesAndEmptyEnabledIsSyncOff() throws {
        let cases: [(IOSWidgetSnapshotState, String, String)] = [
            (.setupNeeded, "Setup", "iCloud is off"),
            (.waitingForMac, "Waiting", "Waiting for your Mac"),
            (.disabled, "Off", "Sync is off"),
            (.corrupt, "Unreadable", "Couldn’t read the data"),
            (.incompatibleSchema, "Update", "Update Headroom"),
        ]
        for (state, word, title) in cases {
            for family in LockScreenWidgetFamily.allCases {
                let r = LockScreenWidgetRecipe(style: .liquidLevel, family: family, providerChoice: .automatic, state: state, now: F.now)
                let status = try #require(r.status)
                #expect(r.slots.isEmpty)
                #expect(status.circleWord == word)
                #expect(status.title == title)
                #expect(!status.message.isEmpty)
                #expect(status.inlineText == "Headroom · \(title)")
                #expect(r.inlineTextCandidates == [status.inlineText])
                #expect(r.inlineImage == .warning)
            }
        }
        let empty = recipe(.liquidLevel, .circle, [])
        #expect(empty.status?.title == "Sync is off")
        let disabled = LockScreenWidgetRecipe(style: .liquidLevel, family: .circle, providerChoice: .claude, state: .content(.disabled(generatedAt: F.now)), now: F.now)
        #expect(disabled.status?.title == "Sync is off")
    }

    @Test func accessibilityFollowsVisualOrderAndSaysUnavailableInsteadOfZero() throws {
        let r = recipe(.tightestFirst, .rectangle, [F.grok(5), F.cursor(otherModels: 8)])
        #expect(r.accessibilityElements.count == 2)
        #expect(r.accessibilityElements[0].hasPrefix("Grok, Weekly, 5 percent left"))
        #expect(r.accessibilityElements[1].hasPrefix("Cursor, Other Models, 8 percent left"))
        let unavailable = F.provider("claude", "Claude", [F.window(.weekly, label: "Weekly", percent: 9, freshness: .unavailable(since: F.now))])
        let spoken = recipe(.liquidLevel, .circle, [unavailable]).accessibilityText
        #expect(spoken.contains("unavailable"))
        #expect(!spoken.contains("9 percent"))
        #expect(!spoken.contains("0 percent"))
        #expect(recipe(.liquidLevel, .rectangle, [F.grok(), F.cursor()]).accessibilityElements.count == 2)
        #expect(recipe(.nestedMeter, .circle, [F.claude()]).accessibilityElements.count == 1)
    }

    @Test func schemaThreeResolutionPreservesSelectionAndMixedWindowFreshness() throws {
        let claude = F.provider("claude", "Claude", [
            F.window(.weekly, label: "Weekly", percent: 9, freshness: .unavailable(since: F.now)),
            F.window(.fiveHour, label: "5h", percent: 72),
            F.window(.other("Weekly (Fable)"), label: "Weekly (Fable)", percent: 5, freshness: .stale(observedAt: F.now.addingTimeInterval(-3600))),
        ])
        let original = WidgetSnapshotEnvelope(generatedAt: F.now, status: .enabled, providers: [F.codex(), claude], widgetProviderSelection: ["claude"])
        let decoded = try JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: JSONEncoder().encode(original))
        #expect(decoded.schemaVersion == 3)
        let state = IOSWidgetSnapshotState.from(cacheRead: .snapshot(decoded))
        let r = LockScreenWidgetRecipe(style: .nestedMeter, family: .rectangle, providerChoice: .automatic, state: state, now: F.now)
        let slot = try #require(r.slots.first)
        #expect(r.slots.map(\.providerID) == ["claude"])
        #expect(slot.primary.state == .unavailable)
        #expect(slot.secondary.first { $0.window?.widgetRole == .model }?.state == .stale)
        #expect(slot.secondary.first { $0.window?.widgetRole == .model }?.window?.observedAt == F.now.addingTimeInterval(-3600))
        #expect(slot.secondary.first { $0.window?.kind == .fiveHour }?.state == .live)
    }

    @Test func lockFixturesAreSeparateFromTheUnchangedHomeJobs() throws {
        #expect(!DemoScreenshotData.styleFixtureNames.contains("thirdProviderTightest"))
        for name in DemoScreenshotData.lockScreenFixtureNames {
            #expect(DemoScreenshotData.lockScreenFixture(name, now: F.now) != nil, "\(name)")
        }
        #expect(DemoScreenshotData.lockScreenFixture("unknown", now: F.now) == nil)
        let third = try #require(DemoScreenshotData.lockScreenFixture("thirdProviderTightest", now: F.now))
        #expect(!third.widgetProviders.contains { $0.id == "cursor" })
        #expect(LockScreenWidgetRecipe(style: .tightestFirst, family: .circle, providerChoice: .automatic, state: .content(third), now: F.now).slots.first?.providerID == "cursor")
        #expect(DemoScreenshotData.lockScreenFixture("signedOut", now: F.now) == DemoScreenshotData.styleFixture("signedOut", now: F.now))
    }

    @Test func demoNamesFollowTheRectangleLayout() {
        let pair = recipe(.vesselHero, .rectangle, [F.claude(), F.codex()], demo: true)
        #expect(pair.slots.count == 2)
        #expect(pair.displayName(forSlotAt: 0) == "Demo")
        #expect(pair.displayName(forSlotAt: 1) == "Codex")
        #expect(pair.slots.allSatisfy { $0.primary.caption != "Demo" })
        let single = recipe(.nestedMeter, .rectangle, [F.claude()], choice: .claude, demo: true)
        #expect(single.displayName(forSlotAt: 0) == "Demo · Claude")
        let gauges = recipe(.tightestFirst, .rectangle, [F.claude(), F.codex()], demo: true)
        #expect(gauges.slots.allSatisfy { $0.primary.caption == "Demo" })
        let live = recipe(.vesselHero, .rectangle, [F.claude(), F.codex()])
        #expect(live.displayName(forSlotAt: 0) == "Claude")
        #expect(live.displayName(forSlotAt: 5) == "")
    }

    /// U9 follow-up: "Demo · OpenCode" overflowed Vessel Hero's single column, which never
    /// shrinks sideways. A name not verified to fit the prefix reads "Demo", as a pair's
    /// first slot does, and its mark still names the provider.
    @Test func aLongDemoNameDropsToDemoInEveryRectangle() throws {
        let envelope = OpenCodePhoneFixture.project(OpenCodePhoneFixture.go())
        for style in WidgetLayoutStyle.allCases where style != .tightestFirst {
            let demo = LockScreenWidgetRecipe(
                style: style, family: .rectangle, providerChoice: .opencode,
                state: .demo(envelope), now: OpenCodePhoneFixture.captured)
            #expect(demo.slots.map(\.providerID) == ["opencode"], "\(style)")
            #expect(demo.displayName(forSlotAt: 0) == "Demo", "\(style)")
            let live = LockScreenWidgetRecipe(
                style: style, family: .rectangle, providerChoice: .opencode,
                state: .content(envelope), now: OpenCodePhoneFixture.captured)
            #expect(live.displayName(forSlotAt: 0) == "OpenCode", "\(style)")
        }
        #expect(recipe(.vesselHero, .rectangle, [F.claude()], choice: .claude, demo: true).displayName(forSlotAt: 0) == "Demo · Claude")
        #expect(recipe(.vesselHero, .rectangle, [F.claude(), F.codex()], choice: .codex, demo: true).displayName(forSlotAt: 0) == "Demo · Codex")
    }

    @Test func cursorTitleNamesThePoolWhereNoCaptionDoes() {
        let cursor = recipe(.nestedMeter, .rectangle, [F.cursor()], choice: .cursor)
        #expect(["Cursor Models", "Other Models"].contains(cursor.title(forSlotAt: 0)))
        #expect(recipe(.nestedMeter, .rectangle, [F.cursor()], choice: .cursor, demo: true).title(forSlotAt: 0).hasPrefix("Demo · "))
        #expect(recipe(.nestedMeter, .rectangle, [F.claude()], choice: .claude).title(forSlotAt: 0) == "Claude")
        #expect(recipe(.nestedMeter, .rectangle, [F.claude()], choice: .cursor).title(forSlotAt: 0) == "Cursor")
    }

    @Test func homeFreshnessRulesDimAndHideLockScreenReadings() throws {
        let envelope = F.envelope([F.claude()])
        let dimmed = WidgetFreshnessTreatment(now: F.now, dimmedSince: F.now.addingTimeInterval(-7200), host: .phone)
        let r = LockScreenWidgetRecipe(style: .liquidLevel, family: .circle, providerChoice: .claude,
                                       state: .content(envelope), now: F.now, freshness: dimmed)
        let main = try #require(r.slots.first?.primary)
        #expect(main.state == .stale)
        #expect(main.caption.hasPrefix("⚠ "))
        let past = F.provider("claude", "Claude", [F.window(.weekly, label: "Weekly", percent: 40, resetIn: -900)])
        let reset = LockScreenWidgetRecipe(style: .liquidLevel, family: .circle, providerChoice: .claude,
                                           state: .content(F.envelope([past])), now: F.now,
                                           freshness: WidgetFreshnessTreatment(now: F.now, host: .phone))
        #expect(reset.slots.first?.primary.state == .unavailable)
        #expect(reset.slots.first?.primary.numberText == "—")
    }

    @Test func countdownTextIsTheBareSharedCountdown() throws {
        let main = try #require(recipe(.nestedMeter, .rectangle, [F.claude()], choice: .claude).slots.first?.primary)
        let countdown = try #require(main.countdownText)
        #expect(main.refillText == "Refills in \(countdown)")
        let unavailable = F.provider("claude", "Claude", [
            F.window(.weekly, label: "Weekly", percent: 9, freshness: .unavailable(since: F.now)),
        ])
        #expect(recipe(.nestedMeter, .rectangle, [unavailable], choice: .claude).slots.first?.primary.countdownText == nil)
    }
}

struct LockScreenInlineVesselArtTests {
    @Test func elevenTemplateLevelsKeepTheWidgetVesselProportion() {
        let g = LockScreenInlineVesselArt.geometry
        #expect(LockScreenInlineVesselArt.levels.count == 11)
        #expect(abs(g.width / g.height - WidgetVesselGeometry.aspect) < 0.03)
        #expect(g.stroke >= WidgetVesselGeometry.heroStrokeRange.lowerBound)
        let names = Set(LockScreenInlineVesselArt.levels.map(LockScreenInlineVesselArt.assetName(level:)))
        #expect(names.count == 11)
        #expect(LockScreenInlineVesselArt.assetName(level: 42) == "LockScreenInlineVessel10")
    }

    @Test func onlyLevelZeroIsAnEmptyOutline() {
        #expect(!LockScreenInlineVesselArt.svg(level: 0).contains("clip-path"))
        for level in 1...10 { #expect(LockScreenInlineVesselArt.svg(level: level).contains("clip-path")) }
        #expect(LockScreenInlineVesselArt.svg(level: 3) != LockScreenInlineVesselArt.svg(level: 4))
        #expect(LockScreenInlineVesselArt.imagesetContents.contains("\"template\""))
    }
}
