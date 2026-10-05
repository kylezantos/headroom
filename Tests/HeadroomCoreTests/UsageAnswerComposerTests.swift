import Foundation
import Testing

@testable import HeadroomCore

/// U14 / KTD18: every Siri and Shortcuts answer comes from the pure composer, so each
/// state the plan names is pinned here rather than only on a device.
@Suite
struct UsageAnswerComposerTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private let locale = Locale(identifier: "en_US")
    /// Friday 25 Sep 2026, 10:00 AM in Los Angeles.
    private let now = Date(timeIntervalSince1970: 1_790_355_600)
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 60 * 60

    // MARK: Fixtures

    private func window(
        _ kind: WidgetWindowKind, label: String? = nil, left: Double, resetIn: TimeInterval? = 6 * 60 * 60,
        observedAgo: TimeInterval = 4 * 60, freshness: WidgetWindowFreshness? = nil,
        pool: TimeInterval? = nil
    ) -> CompanionResolvedWindow {
        let observed = now.addingTimeInterval(-observedAgo)
        let summary = WidgetWindowSummary(
            kind: kind, label: label ?? kind.id, percentRemaining: left, utilization: 100 - left,
            resetSchedule: resetIn.map { .scheduled(now.addingTimeInterval($0)) } ?? .unresolved(.absent),
            resetLabel: nil, observedAt: observed,
            severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: left)),
            freshness: freshness ?? .live, billingPeriodDuration: pool)
        let spark = label?.localizedCaseInsensitiveContains("spark") == true
        return CompanionResolvedWindow(summary: summary, isSpark: spark)
    }

    private func account(
        _ id: String?, title: String, isMain: Bool, windows: [CompanionResolvedWindow],
        freshness: WidgetProviderFreshness = .live, attention: CompanionAttention? = nil
    ) -> CompanionResolvedAccount {
        CompanionResolvedAccount(
            accountID: id, title: title, planName: nil, freshness: freshness, attention: attention,
            bankedResets: nil, capturedAt: freshness == .pending ? nil : now.addingTimeInterval(-4 * minute),
            windows: windows, isMain: isMain)
    }

    private func provider(
        _ id: ProviderID, main: CompanionResolvedAccount?, extras: [CompanionResolvedAccount] = [],
        source: CompanionProviderSource = .v4(.manifestDigestMatched),
        capability: CompanionAttention? = nil
    ) -> CompanionResolvedProvider {
        CompanionResolvedProvider(
            id: id.raw, displayName: id.displayName, source: source, capabilityAttention: capability,
            mainAccount: main, extraAccounts: extras, omittedAccountCount: 0, lag: .current,
            payloadGeneration: 1, effectiveIntervalSeconds: 300)
    }

    private func snapshot(
        _ providers: [CompanionResolvedProvider], generatedAgo: TimeInterval = 4 * 60,
        interval: Double? = 300, isV3Only: Bool = false, display: CompanionDisplayBlock? = nil
    ) -> CompanionResolvedSnapshot {
        let generatedAt = now.addingTimeInterval(-generatedAgo)
        return CompanionResolvedSnapshot(
            state: .content(
                CompanionResolvedContent(
                    origin: isV3Only ? .v3 : .v4, notice: nil, sourceID: nil, generation: 1,
                    generatedAt: generatedAt, chosenIntervalSeconds: 300, display: display,
                    widgetProviderSelection: nil, widgetSparkEnabled: false, reminderSummary: nil,
                    answeredRequests: [], ladder: .full, providers: providers, apiSpend: [],
                    freshness: CompanionFreshnessInputs(
                        generatedAt: generatedAt, firstSeen: generatedAt,
                        largestEffectiveIntervalSeconds: interval, isV3Only: isV3Only))))
    }

    private func context(locked: Bool = false, sample: Bool = false, spark: Bool? = nil)
        -> UsageAnswerContext
    {
        UsageAnswerContext(
            now: now, isProtectedDataAvailable: !locked, isSampleData: sample, sparkEnabled: spark,
            timeZone: zone, locale: locale)
    }

    /// Current ICU puts a narrow no-break space before AM/PM; compare on plain spaces.
    private func answer(
        _ id: ProviderID, _ snapshot: CompanionResolvedSnapshot, _ context: UsageAnswerContext? = nil
    ) -> UsageAnswer {
        UsageAnswerComposer.answer(for: id, in: snapshot, context: context ?? self.context())
    }

    private func text(_ answer: UsageAnswer) -> String {
        answer.dialog.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private var claudeSingle: CompanionResolvedSnapshot {
        snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 38),
                window(.weekly, left: 62, resetIn: 47 * hour),
                window(.other("Weekly (Fable)"), label: "Weekly (Fable)", left: 70, resetIn: 47 * hour),
            ]))
        ])
    }

    private var claudeMulti: CompanionResolvedSnapshot {
        snapshot([
            provider(
                .claude,
                main: account("primary", title: "Personal", isMain: true, windows: [
                    window(.fiveHour, left: 38), window(.weekly, left: 62, resetIn: 47 * hour),
                ]),
                extras: [
                    account("x1", title: "Work", isMain: false, windows: [
                        window(.fiveHour, left: 12, resetIn: 3 * hour, observedAgo: 6 * minute),
                        window(.weekly, left: 80, resetIn: 47 * hour, observedAgo: 6 * minute),
                    ]),
                    account("x2", title: "Studio", isMain: false, windows: [
                        window(.fiveHour, left: 50), window(.weekly, left: 70, resetIn: 47 * hour),
                    ]),
                ])
        ])
    }

    // MARK: Live answers

    @Test func liveMainAccountAnswersTightestWindowPlusWeeklyWithAge() {
        let result = answer(.claude, claudeSingle)
        #expect(text(result) == "Claude has 38% left in the 5-hour window, resetting today at 4:00 PM, "
            + "and 62% left in the weekly window, resetting Sunday at 9:00 AM. Updated 4 min ago.")
        #expect(result.kind == .usage)
        #expect(result.percentLeft == 38)
        #expect(result.windowLabel == "5-hour")
        #expect(result.updatedAt == now.addingTimeInterval(-4 * minute))
        #expect(!result.isDimmed && !result.isSampleData && result.lastUpdateFromMac == nil)
    }

    @Test func weeklyIsSpokenOnceWhenItIsTheTightest() {
        let snapshot = snapshot([
            provider(.codex, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 70), window(.weekly, left: 20, resetIn: 47 * hour),
            ]))
        ])
        #expect(text(answer(.codex, snapshot))
            == "Codex has 20% left in the weekly window, resetting Sunday at 9:00 AM. Updated 4 min ago.")
    }

    @Test func aModelRowCanBeTheTightestAndWeeklyStillFollows() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 80),
                window(.weekly, left: 62, resetIn: 47 * hour),
                window(.other("Weekly (Fable)"), label: "Weekly (Fable)", left: 9, resetIn: 47 * hour),
            ]))
        ])
        let result = answer(.claude, snapshot)
        #expect(text(result).hasPrefix("Claude has 9% left in the Fable weekly window, resetting Sunday at 9:00 AM, "
            + "and 62% left in the weekly window"))
        #expect(result.windowLabel == "Fable")
    }

    @Test func theAgeIsTheOldestSpokenReading() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 38, observedAgo: 2 * minute),
                window(.weekly, left: 62, resetIn: 47 * hour, observedAgo: 75 * minute,
                       freshness: .stale(observedAt: now.addingTimeInterval(-75 * minute))),
            ]))
        ])
        let result = answer(.claude, snapshot)
        #expect(text(result).hasSuffix("Updated 1 hr ago."))
        #expect(result.updatedAt == now.addingTimeInterval(-75 * minute))
    }

    @Test func aTighterExtraAccountIsMentionedWithItsOwnAge() {
        let result = answer(.claude, claudeMulti)
        #expect(text(result) == "Your main Claude account, Personal, has 38% left in the 5-hour window, "
            + "resetting today at 4:00 PM, and 62% left in the weekly window, resetting Sunday at 9:00 AM. "
            + "Updated 4 min ago. Work is tighter, with 12% left in the 5-hour window, resetting today at "
            + "1:00 PM. Updated 6 min ago.")
        #expect(!text(result).contains("Studio"))
        #expect(result.percentLeft == 38)
    }

    @Test func noExtraAccountIsMentionedWhenNoneIsTighter() {
        let snapshot = snapshot([
            provider(
                .codex,
                main: account("primary", title: "Personal", isMain: true, windows: [window(.fiveHour, left: 30)]),
                extras: [account("x1", title: "Work", isMain: false, windows: [window(.fiveHour, left: 30)])])
        ])
        let result = text(answer(.codex, snapshot))
        #expect(result.hasPrefix("Your main Codex account, Personal, has 30% left"))
        #expect(!result.contains("Work") && !result.contains("tighter"))
    }

    @Test func manyTighterAccountsAreCappedWithACount() {
        let extras = (1...5).map { index in
            account("x\(index)", title: "Team \(index)", isMain: false, windows: [window(.fiveHour, left: Double(index))])
        }
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true,
                                            windows: [window(.fiveHour, left: 40)]), extras: extras)
        ])
        let result = text(answer(.claude, snapshot))
        #expect(result.contains("Team 1 is tighter") && result.contains("Team 3 is tighter"))
        #expect(!result.contains("Team 4") && !result.contains("Team 5"))
        #expect(result.hasSuffix("2 more Claude accounts are tighter."))
    }

    // MARK: Locked

    @Test func lockedModeOmitsAccountTitles() {
        let result = text(answer(.claude, claudeMulti, context(locked: true)))
        for title in ["Personal", "Work", "Studio"] { #expect(!result.contains(title)) }
        #expect(result.hasPrefix("Your main Claude account has 38% left in the 5-hour window"))
        #expect(result.contains("Another Claude account is tighter, with 12% left in the 5-hour window"))
    }

    @Test func lockedModeOmitsTitlesFromCappedAndAttentionLinesToo() {
        let extras = (1...4).map { index in
            account("x\(index)", title: "Team \(index)", isMain: false, windows: [window(.fiveHour, left: Double(index))])
        }
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true,
                                            windows: [window(.fiveHour, left: 40)],
                                            freshness: .stale(message: "", needsAttention: true),
                                            attention: .signInAgain), extras: extras)
        ])
        let result = text(answer(.claude, snapshot, context(locked: true)))
        #expect(!result.contains("Team") && !result.contains("Personal"))
        #expect(result.contains("Sign in again on your Mac."))
    }

    // MARK: Dimmed (AE5)

    @Test func dimmedAnswerOpensWithNoUpdateFromYourMac() {
        // 5-minute interval, Mac asleep 30 minutes: the 15-minute rule threshold has passed.
        var single = claudeSingle
        single = snapshot(single.content!.providers, generatedAgo: 30 * minute)
        let result = answer(.claude, single)
        #expect(text(result).hasPrefix("No update from your Mac since 9:30 AM. Claude has 38% left"))
        #expect(result.isDimmed)
        #expect(result.lastUpdateFromMac == now.addingTimeInterval(-30 * minute))
        #expect(result.kind == .usage)
    }

    @Test func aSixtyMinuteIntervalDoesNotDimAfterThirtyMinutes() {
        let result = answer(.claude, snapshot(claudeSingle.content!.providers, generatedAgo: 30 * minute, interval: 3_600))
        #expect(!result.isDimmed)
        #expect(!text(result).contains("No update"))
    }

    @Test func dimmedTimeFromAnEarlierDayNamesTheDay() {
        let result = answer(.claude, snapshot(claudeSingle.content!.providers, generatedAgo: 20 * hour))
        #expect(text(result).hasPrefix("No update from your Mac since yesterday at 2:00 PM."))
        let older = answer(.claude, snapshot(claudeSingle.content!.providers, generatedAgo: 3 * 24 * hour))
        #expect(text(older).hasPrefix("No update from your Mac since Sep 22 at 10:00 AM."))
    }

    // MARK: Past reset (AE6)

    @Test func aWindowTenMinutesPastItsResetIsSpokenAsResetNeverAsAPercentage() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 40, observedAgo: 3 * hour),
                window(.weekly, left: 3, resetIn: -10 * minute, observedAgo: 3 * hour),
            ]))
        ])
        let result = answer(.claude, snapshot)
        #expect(text(result) == "Claude has 40% left in the 5-hour window, resetting today at 4:00 PM. "
            + "The weekly window reset at 9:50 AM, waiting for your Mac. Updated 3 hr ago.")
        #expect(!text(result).contains("3%"))
        #expect(result.percentLeft == 40)
    }

    @Test func anOnlyWindowPastItsResetHasNoNumber() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 7, resetIn: -2 * hour, observedAgo: 3 * hour),
            ]))
        ])
        let result = answer(.claude, snapshot)
        #expect(text(result) == "Claude’s 5-hour window reset at 8:00 AM, waiting for your Mac. Updated 3 hr ago.")
        #expect(result.percentLeft == nil && !text(result).contains("%"))
    }

    @Test func aMultiAccountMainPastItsResetNamesItsAccountOnlyWhenUnlocked() {
        let snapshot = snapshot([
            provider(
                .claude,
                main: account("primary", title: "Personal", isMain: true, windows: [
                    window(.fiveHour, left: 7, resetIn: -2 * hour, observedAgo: 3 * hour),
                ]),
                extras: [account("x1", title: "Work", isMain: false, windows: [window(.fiveHour, left: 2)])])
        ])
        #expect(text(answer(.claude, snapshot)) == "On your main Claude account, Personal, the 5-hour window "
            + "reset at 8:00 AM, waiting for your Mac. Updated 3 hr ago.")
        #expect(text(answer(.claude, snapshot, context(locked: true))) == "On your main Claude account, the "
            + "5-hour window reset at 8:00 AM, waiting for your Mac. Updated 3 hr ago.")
    }

    @Test func insideTheTenMinuteGraceTheNumberStillSpeaks() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 7, resetIn: -9 * minute, observedAgo: 3 * hour),
            ]))
        ])
        #expect(text(answer(.claude, snapshot)) == "Claude has 7% left in the 5-hour window, resetting now. Updated 3 hr ago.")
    }

    @Test func aReadingNewerThanTheResetIsNotPastReset() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 90, resetIn: -30 * minute, observedAgo: 5 * minute),
            ]))
        ])
        #expect(text(answer(.claude, snapshot)).hasPrefix("Claude has 90% left in the 5-hour window"))
    }

    @Test func aPastResetExtraAccountIsNeverCountedTighter() {
        let snapshot = snapshot([
            provider(
                .claude,
                main: account("primary", title: "Personal", isMain: true, windows: [window(.fiveHour, left: 40)]),
                extras: [account("x1", title: "Work", isMain: false, windows: [
                    window(.fiveHour, left: 2, resetIn: -hour, observedAgo: 2 * hour),
                ])])
        ])
        #expect(!text(answer(.claude, snapshot)).contains("Work"))
    }

    // MARK: Every provider

    @Test func grokSpeaksItsWeeklyPool() {
        let snapshot = snapshot([
            provider(.grok, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.other("Weekly"), label: "Weekly", left: 56, resetIn: 3 * 24 * hour, pool: 7 * 24 * hour),
            ]))
        ])
        #expect(text(answer(.grok, snapshot))
            == "Grok has 56% left in the weekly pool, resetting Monday at 10:00 AM. Updated 4 min ago.")
    }

    @Test func cursorSpeaksItsTightestMonthlyPoolOnce() {
        let snapshot = snapshot([
            provider(.cursor, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.other("Cursor Models"), label: "Cursor Models", left: 69, resetIn: 12 * 24 * hour, pool: 30 * 24 * hour),
                window(.other("Other Models"), label: "Other Models", left: 37, resetIn: 12 * 24 * hour, pool: 30 * 24 * hour),
            ]))
        ])
        let result = answer(.cursor, snapshot)
        #expect(text(result) == "Cursor has 37% left in Other Models, resetting Oct 7. Updated 4 min ago.")
        #expect(result.windowLabel == "Other Models")
    }

    @Test func cursorsIncludedPoolReadsAsAPool() {
        let snapshot = snapshot([
            provider(.cursor, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.other("Included"), label: "Included", left: 80, resetIn: 12 * 24 * hour, pool: 30 * 24 * hour),
            ]))
        ])
        #expect(text(answer(.cursor, snapshot)).hasPrefix("Cursor has 80% left in the included pool"))
    }

    @Test func everyProviderAnswersFromTheSameSnapshot() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "A", isMain: true, windows: [window(.fiveHour, left: 50)])),
            provider(.codex, main: account("primary", title: "B", isMain: true, windows: [window(.weekly, left: 51)])),
            provider(.grok, main: account("primary", title: "C", isMain: true, windows: [
                window(.other("Weekly"), label: "Weekly", left: 52, pool: 7 * 24 * hour)])),
            provider(.cursor, main: account("primary", title: "D", isMain: true, windows: [
                window(.other("Monthly"), label: "Monthly", left: 53, pool: 30 * 24 * hour)])),
        ])
        for (id, value) in [(ProviderID.claude, 50), (.codex, 51), (.grok, 52), (.cursor, 53)] {
            let result = answer(id, snapshot)
            #expect(result.kind == .usage && result.percentLeft == value)
            #expect(text(result).hasPrefix("\(id.displayName) has \(value)% left"))
        }
        #expect(text(answer(.cursor, snapshot)).contains("the monthly pool"))
    }

    // MARK: Spark and unavailable rows

    @Test func sparkRowsFollowTheSparkSwitch() {
        let snapshot = snapshot([
            provider(.codex, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.weekly, left: 60, resetIn: 47 * hour),
                window(.other("Spark Weekly"), label: "Spark Weekly", left: 5, resetIn: 47 * hour),
            ]))
        ])
        #expect(answer(.codex, snapshot).percentLeft == 60)
        let on = answer(.codex, snapshot, context(spark: true))
        #expect(on.percentLeft == 5 && text(on).hasPrefix("Codex has 5% left in the Spark weekly window"))
        // nil follows the Mac's app Spark switch.
        let macOn = self.snapshot(snapshot.content!.providers, display: CompanionDisplayBlock(appSparkEnabled: true))
        #expect(answer(.codex, macOn).percentLeft == 5)
    }

    @Test func anUnavailableWindowNeverSpeaksANumber() {
        let snapshot = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [
                window(.fiveHour, left: 40),
                window(.weekly, left: 1, resetIn: 47 * hour, freshness: .unavailable(since: now.addingTimeInterval(-hour))),
            ]))
        ])
        let result = text(answer(.claude, snapshot))
        #expect(result == "Claude has 40% left in the 5-hour window, resetting today at 4:00 PM. Updated 4 min ago.")
    }

    // MARK: States without a number

    @Test func pendingProviderHasItsSentence() {
        let pending = snapshot([
            provider(.claude, main: account("primary", title: "Personal", isMain: true, windows: [], freshness: .pending))
        ])
        let result = answer(.claude, pending)
        #expect(result.kind == .pending && result.percentLeft == nil)
        #expect(text(result) == "Waiting for your Mac’s first Claude reading.")

        let skeleton = snapshot([provider(.codex, main: nil, source: .skeleton)])
        #expect(text(answer(.codex, skeleton)) == "Waiting for your Mac’s first Codex reading.")
    }

    @Test func aSkeletonPastTheDimThresholdIsWaitingForYourMac() {
        let skeleton = snapshot([provider(.codex, main: nil, source: .skeleton)], generatedAgo: 40 * minute)
        let result = answer(.codex, skeleton)
        #expect(result.kind == .waitingForMac && result.isDimmed)
        #expect(text(result) == "No update from your Mac since 9:20 AM. Waiting for your Mac to send Codex usage.")
    }

    @Test func pausedHasItsSentence() {
        let result = answer(.claude, CompanionResolvedSnapshot(state: .paused))
        #expect(result.kind == .paused)
        #expect(text(result) == "Companion Sync is paused. Turn on Sync usage to iPhone in Headroom on your Mac.")
    }

    @Test func waitingHasItsSentence() {
        let result = answer(.claude, CompanionResolvedSnapshot(state: .waiting(nil)))
        #expect(result.kind == .waiting)
        #expect(text(result) == "Waiting for your Mac. Open Headroom on your Mac to send a reading.")
        let update = answer(.claude, CompanionResolvedSnapshot(state: .waiting(.updatePhone)))
        #expect(update.kind == .updatePhone)
        #expect(text(update) == "Update Headroom on this iPhone to read your Mac’s usage.")
    }

    @Test func accountScopeUnavailableHasItsSentence() {
        let result = answer(.claude, CompanionResolvedSnapshot(state: .accountScopeUnavailable))
        #expect(result.kind == .accountScopeUnavailable)
        #expect(text(result) == "iCloud isn’t available on this iPhone, so Headroom can’t read your usage.")
    }

    @Test func untrackedProviderHasItsSentence() {
        let result = answer(.grok, claudeSingle)
        #expect(result.kind == .untracked && result.percentLeft == nil)
        #expect(text(result) == "Your Mac isn’t tracking Grok.")
    }

    @Test func anAccountWithNoReadingSpeaksItsAttention() {
        let snapshot = snapshot([
            provider(.claude, main: account(
                "primary", title: "Personal", isMain: true, windows: [],
                freshness: .stale(message: CompanionAttentionCopy.account(.signInAgain), needsAttention: true),
                attention: .signInAgain))
        ])
        let result = answer(.claude, snapshot)
        #expect(result.kind == .noReading)
        #expect(text(result) == "Headroom has no Claude reading to share. Sign in again on your Mac.")
    }

    @Test func aStaleAccountNeedingAttentionAddsItAfterItsNumbers() {
        let snapshot = snapshot([
            provider(.claude, main: account(
                "primary", title: "Personal", isMain: true, windows: [
                    window(.fiveHour, left: 38, observedAgo: 2 * hour,
                           freshness: .stale(observedAt: now.addingTimeInterval(-2 * hour)))],
                freshness: .stale(message: "", needsAttention: true), attention: .signInAgain))
        ])
        #expect(text(answer(.claude, snapshot)).hasSuffix("Updated 2 hr ago. Sign in again on your Mac."))
    }

    @Test func aProviderCapabilityProblemIsSpoken() {
        let snapshot = snapshot([
            provider(.cursor, main: account("primary", title: "Personal", isMain: true, windows: [], freshness: .pending),
                     capability: .cliMissing)
        ])
        let result = answer(.cursor, snapshot)
        #expect(result.kind == .noReading)
        #expect(text(result) == "Headroom has no Cursor reading to share. Install the official CLI on your Mac.")
    }

    // MARK: Demo

    @Test func demoAnswersSayTheyAreSampleData() {
        let result = answer(.claude, claudeSingle, context(sample: true))
        #expect(result.isSampleData)
        #expect(text(result).hasPrefix("This is sample data. Claude has 38% left"))
    }

    // MARK: Copy rules across every answer

    private var everyAnswer: [UsageAnswer] {
        let snapshots: [CompanionResolvedSnapshot] = [
            claudeSingle, claudeMulti, snapshot(claudeSingle.content!.providers, generatedAgo: 3 * hour),
            CompanionResolvedSnapshot(state: .paused), CompanionResolvedSnapshot(state: .waiting(nil)),
            CompanionResolvedSnapshot(state: .waiting(.updatePhone)),
            CompanionResolvedSnapshot(state: .accountScopeUnavailable),
            snapshot([provider(.codex, main: nil, source: .skeleton)]),
            snapshot([provider(.codex, main: nil, source: .skeleton)], generatedAgo: 2 * hour),
            snapshot([provider(.claude, main: account("primary", title: "P", isMain: true, windows: [
                window(.weekly, left: 3, resetIn: -hour, observedAgo: 2 * hour)]))]),
        ]
        var answers: [UsageAnswer] = []
        for snapshot in snapshots {
            for id in [ProviderID.claude, .codex, .grok, .cursor] {
                for locked in [false, true] {
                    for sample in [false, true] {
                        answers.append(answer(id, snapshot, context(locked: locked, sample: sample)))
                    }
                }
            }
        }
        for attention in CompanionAttention.allCases {
            let snapshot = snapshot([provider(.claude, main: account(
                "primary", title: "P", isMain: true, windows: [],
                freshness: .stale(message: "", needsAttention: true), attention: attention))])
            answers.append(answer(.claude, snapshot))
        }
        return answers
    }

    @Test func answersAlwaysSayLeftAndNeverUsed() {
        for answer in everyAnswer {
            let words = text(answer)
            #expect(words.firstMatch(of: /\b[Uu]sed\b/) == nil, "\(words)")
            var rest = Substring(words)
            while let range = rest.range(of: "%") {
                #expect(rest[range.upperBound...].hasPrefix(" left"), "\(words)")
                rest = rest[range.upperBound...]
            }
        }
    }

    @Test func answersObeyTheR2C6CopyRules() {
        for answer in everyAnswer {
            let words = answer.dialog
            #expect(!words.contains("'"), "\(words) carries a straight apostrophe")
            #expect(!words.localizedCaseInsensitiveContains("connect"), "\(words)")
            #expect(!words.localizedCaseInsensitiveContains("asleep"), "\(words)")
            let characters = Array(words)
            for (index, character) in characters.enumerated() where character == "\u{2014}" {
                #expect(index > 0 && characters[index - 1] == "\u{00A0}", "\(words)")
                #expect(index + 1 < characters.count && characters[index + 1] == "\u{00A0}", "\(words)")
            }
        }
    }

    @Test func everyAnswerCarriesItsSampleFlag() {
        for answer in everyAnswer {
            #expect(!answer.dialog.isEmpty)
            #expect(answer.dialog.hasPrefix("This is sample data.") == answer.isSampleData)
        }
    }
}
