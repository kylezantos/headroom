import Foundation
import Testing
@testable import HeadroomCore

/// U2: which fresh limits trigger a use-it-up reminder, and the cycle ledger that stops
/// repeats (R10–R13, KTD3–KTD5, KTD12).
struct UseItUpEvaluatorTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private let locale = Locale(identifier: "en_US")
    /// Friday 25 Sep 2026, 10:00 AM in Los Angeles.
    private let now = Date(timeIntervalSince1970: 1_790_355_600)
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60
    private let claude = AccountKey(providerID: .claude, accountID: .primary)
    private let claudeWork = AccountKey(providerID: .claude, accountID: AccountID("work"))
    private let codex = AccountKey(providerID: .codex, accountID: .primary)
    private let grok = AccountKey(providerID: .grok, accountID: .primary)
    private let cursor = AccountKey(providerID: .cursor, accountID: .primary)

    private func freshLedger() -> UseItUpLedger {
        let suite = "headroom.use-it-up.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UseItUpLedger(defaults: defaults)
    }

    private func settings(
        enabled: Bool = true,
        rules: [ReminderRule] = ReminderRules.defaults,
        scope: Set<ReminderScope> = ReminderScope.defaults,
        spark: Bool = false
    ) -> UseItUpSettings {
        UseItUpSettings(isEnabled: enabled, rules: rules, scope: scope, showCodexSparkCounters: spark)
    }

    private func window(
        _ kind: WindowKind = .weekly,
        left: Double,
        resetsIn seconds: TimeInterval,
        at reference: Date? = nil,
        freshness: UsageWindowFreshness = .live
    ) -> UsageWindow {
        UsageWindow(
            kind: kind,
            utilization: 100 - left,
            resetsAt: (reference ?? now).addingTimeInterval(seconds),
            freshness: freshness
        )
    }

    private func snapshot(_ provider: ProviderID, _ windows: [UsageWindow], at: Date? = nil) -> UsageSnapshot {
        UsageSnapshot.live(provider, windows: windows, at: at ?? now)
    }

    private func evaluate(
        _ snapshot: UsageSnapshot,
        account: AccountKey? = nil,
        settings: UseItUpSettings? = nil,
        ledger: UseItUpLedger? = nil,
        now: Date? = nil
    ) -> [UseItUpProposal] {
        UseItUpEvaluator.evaluate(
            snapshot: snapshot,
            account: account ?? AccountKey(providerID: snapshot.providerID, accountID: .primary),
            settings: settings ?? self.settings(),
            ledger: ledger?.entries() ?? [],
            now: now ?? self.now
        )
    }

    /// What the U4 coordinator does after a post succeeds.
    private func apply(_ proposals: [UseItUpProposal], to ledger: UseItUpLedger, rules: [ReminderRule] = ReminderRules.defaults, now: Date? = nil) {
        for proposal in proposals {
            ledger.record(proposal.ledgerEntry, activeFiringKeys: Set(rules.map(\.firingKey)), now: now ?? self.now)
        }
    }

    private var oneDay: ReminderRule { ReminderRules.defaults[0] }
    private var sixHours: ReminderRule { ReminderRules.defaults[1] }

    // MARK: - Due logic (R11, R12)

    @Test func ae1OneDayRuleFiresOnceThenStaysQuiet() {
        let ledger = freshLedger()
        let snap = snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)])
        let proposals = evaluate(snap, ledger: ledger)
        #expect(proposals.count == 1)
        #expect(proposals.first?.dueRules.map(\.id) == [oneDay.id])
        #expect(proposals.first?.percentLeft == 80)
        #expect(proposals.first?.windowID == "weekly")

        apply(proposals, to: ledger)
        #expect(evaluate(snap, ledger: ledger).isEmpty)
    }

    @Test func ae2BothRulesDueProduceOneProposalAndBothAreRecorded() {
        let ledger = freshLedger()
        let snap = snapshot(.codex, [window(left: 60, resetsIn: 4 * hour)])
        let proposals = evaluate(snap, ledger: ledger)
        #expect(proposals.count == 1)
        #expect(Set(proposals[0].dueRules.map(\.id)) == [oneDay.id, sixHours.id])
        #expect(Set(proposals[0].ledgerEntry.firedKeys) == [oneDay.firingKey, sixHours.firingKey])

        apply(proposals, to: ledger)
        #expect(Set(ledger.entry(for: codex, windowID: "weekly")?.firedKeys ?? []) == [oneDay.firingKey, sixHours.firingKey])
        #expect(evaluate(snap, ledger: ledger).isEmpty)
    }

    @Test func onlyTheRuleWhoseThresholdIsMetIsDue() {
        let proposals = evaluate(snapshot(.codex, [window(left: 30, resetsIn: 4 * hour)]))
        #expect(proposals.count == 1)
        #expect(proposals[0].dueRules.map(\.id) == [sixHours.id])
    }

    @Test func belowEveryThresholdNothingFires() {
        #expect(evaluate(snapshot(.codex, [window(left: 20, resetsIn: 4 * hour)])).isEmpty)
    }

    @Test func leadBoundaryIsInclusiveAndZeroIsNotDue() {
        let only6h = settings(rules: [sixHours])
        #expect(evaluate(snapshot(.claude, [window(left: 90, resetsIn: 6 * hour)]), settings: only6h).count == 1)
        #expect(evaluate(snapshot(.claude, [window(left: 90, resetsIn: 6 * hour + 1)]), settings: only6h).isEmpty)
        #expect(evaluate(snapshot(.claude, [window(left: 90, resetsIn: 0)]), settings: only6h).isEmpty)
        #expect(evaluate(snapshot(.claude, [window(left: 90, resetsIn: -60)]), settings: only6h).isEmpty)
        #expect(evaluate(snapshot(.claude, [window(left: 90, resetsIn: 1)]), settings: only6h).count == 1)
    }

    /// Popover rounding: 49.6% shows as 50% and meets a 50% threshold.
    @Test func thresholdUsesThePopoversRounding() {
        let proposals = evaluate(snapshot(.claude, [window(left: 49.6, resetsIn: 23 * hour)]))
        #expect(proposals.count == 1)
        #expect(proposals[0].percentLeft == 50)
        #expect(evaluate(snapshot(.claude, [window(left: 49.4, resetsIn: 23 * hour)])).isEmpty)
    }

    @Test func overLimitUtilizationReadsAsZeroLeft() {
        let snap = snapshot(.claude, [UsageWindow(kind: .weekly, utilization: 140, resetsAt: now.addingTimeInterval(hour))])
        #expect(evaluate(snap, settings: settings(rules: [ReminderRule(amount: 2, unit: .hours, threshold: 1)])).isEmpty)
    }

    @Test func switchOffProposesNothing() {
        #expect(evaluate(snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)]), settings: settings(enabled: false)).isEmpty)
    }

    @Test func emptyRuleListProposesNothing() {
        #expect(evaluate(snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)]), settings: settings(rules: [])).isEmpty)
    }

    /// KTD2: only a fresh live snapshot reaches the evaluator's due logic.
    @Test func nonLiveSnapshotsProposeNothing() {
        let live = snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)])
        #expect(evaluate(live.markedStale(.transient("offline"))).isEmpty)
        let pending = UsageSnapshot(providerID: .claude, windows: live.windows, planLabel: nil, capturedAt: nil, freshness: .pending)
        #expect(evaluate(pending).isEmpty)
    }

    /// AE4: a retained model row on a live snapshot never fires.
    @Test func ae4StaleRowOnALiveSnapshotFiresNothing() {
        let snap = snapshot(.claude, [
            window(left: 30, resetsIn: 23 * hour),
            window(.other("Weekly (Fable)"), left: 90, resetsIn: 23 * hour, freshness: .stale(observedAt: now.addingTimeInterval(-hour))),
            window(.other("Weekly (Fable)"), left: 90, resetsIn: 23 * hour, freshness: .unavailable(since: now)),
        ])
        #expect(evaluate(snap).isEmpty)
    }

    @Test func unresolvedResetEvidenceNeverFires() {
        let snap = snapshot(.claude, [
            UsageWindow(kind: .weekly, utilization: 10, resetSchedule: .unresolved(.absent)),
            UsageWindow(kind: .weekly, utilization: 10, resetSchedule: .unresolved(.elapsed)),
        ])
        #expect(evaluate(snap).isEmpty)
    }

    @Test func eachLimitGetsItsOwnProposal() {
        let snap = snapshot(.claude, [
            window(left: 80, resetsIn: 23 * hour),
            window(.other("Weekly (Fable)"), left: 90, resetsIn: 20 * hour),
        ])
        let proposals = evaluate(snap)
        #expect(proposals.map(\.windowID) == ["weekly", "other:Weekly (Fable)"])
    }

    // MARK: - Scope and length (R10, KTD3)

    @Test func ae3LeadLongerThanTheLimitIsIgnored() {
        let twoDays = ReminderRule(amount: 2, unit: .days, threshold: 50)
        let fiveHour = snapshot(.claude, [window(.fiveHour, left: 100, resetsIn: 4 * hour)])
        #expect(evaluate(fiveHour, settings: settings(rules: [twoDays], scope: [.fiveHour])).isEmpty)

        let threeHours = ReminderRule(amount: 3, unit: .hours, threshold: 50)
        let fiveHourSoon = snapshot(.claude, [window(.fiveHour, left: 100, resetsIn: 2 * hour)])
        let proposals = evaluate(fiveHourSoon, settings: settings(rules: [twoDays, threeHours], scope: [.fiveHour]))
        #expect(proposals.count == 1)
        #expect(proposals[0].dueRules.map(\.id) == [threeHours.id])
    }

    @Test func leadEqualToTheLimitLengthIsIgnored() {
        let sevenDays = ReminderRule(amount: 7, unit: .days, threshold: 50)
        #expect(evaluate(snapshot(.claude, [window(left: 90, resetsIn: 3 * day)]), settings: settings(rules: [sevenDays])).isEmpty)
        let sixDays = ReminderRule(amount: 6, unit: .days, threshold: 50)
        #expect(evaluate(snapshot(.claude, [window(left: 90, resetsIn: 3 * day)]), settings: settings(rules: [sixDays])).count == 1)
    }

    @Test func untickedKindsNeverFire() {
        let fiveHour = snapshot(.claude, [window(.fiveHour, left: 90, resetsIn: 3 * hour)])
        #expect(evaluate(fiveHour).isEmpty)

        let weekly = snapshot(.claude, [window(left: 90, resetsIn: 3 * hour)])
        #expect(evaluate(weekly, settings: settings(scope: [.billingPeriod, .fiveHour])).isEmpty)
    }

    @Test func billingPeriodsFireWhenTicked() {
        let monthly = snapshot(.grok, [window(.billingPeriod(label: "Monthly", duration: 30 * day), left: 80, resetsIn: 20 * hour)])
        #expect(evaluate(monthly).count == 1)
        #expect(evaluate(monthly, settings: settings(scope: [.weekly])).isEmpty)

        let pools = snapshot(.cursor, [
            window(.billingPeriod(label: "Cursor Models", duration: 30 * day), left: 80, resetsIn: 20 * hour),
            window(.billingPeriod(label: "Other Models", duration: 30 * day), left: 70, resetsIn: 20 * hour),
        ])
        #expect(evaluate(pools).count == 2)
    }

    /// U3 (OpenCode plan): Go's monthly billing-period window is evaluated like the others,
    /// and its 5-hour and weekly windows follow their own ticks.
    @Test func openCodeMonthlyFiresLikeAnyBillingPeriod() {
        #expect(UseItUpEvaluator.scope(for: OpenCodeProvider.monthlyKind, providerID: .opencode) == .billingPeriod)
        let go = snapshot(.opencode, [
            window(.fiveHour, left: 90, resetsIn: 3 * hour),
            window(.weekly, left: 70, resetsIn: 20 * hour),
            window(OpenCodeProvider.monthlyKind, left: 80, resetsIn: 20 * hour),
        ])
        #expect(evaluate(go).count == 2)
        #expect(evaluate(go, settings: settings(scope: [.billingPeriod])).count == 1)
        // The no-plan row is unavailable and has no reset: it never fires.
        let noGo = snapshot(.opencode, [UsageWindow(
            kind: OpenCodeProvider.monthlyKind, utilization: 0, resetSchedule: .unresolved(.absent),
            freshness: .unavailable(since: now.addingTimeInterval(-day))
        )])
        #expect(evaluate(noGo).isEmpty)
    }

    @Test func classificationFollowsKTD3() {
        #expect(UseItUpEvaluator.scope(for: .weekly, providerID: .claude) == .weekly)
        #expect(UseItUpEvaluator.scope(for: .fiveHour, providerID: .codex) == .fiveHour)
        #expect(UseItUpEvaluator.scope(for: .billingPeriod(label: "Monthly", duration: 30 * day), providerID: .grok) == .billingPeriod)
        #expect(UseItUpEvaluator.scope(for: .other("Weekly (Fable)"), providerID: .claude) == .weekly)
        #expect(UseItUpEvaluator.scope(for: .other("GPT-5 weekly"), providerID: .codex) == .weekly)
        #expect(UseItUpEvaluator.scope(for: .other("GPT-5 5h"), providerID: .codex) == .fiveHour)
        #expect(UseItUpEvaluator.scope(for: .other("Mystery pool"), providerID: .claude) == nil)
        #expect(UseItUpEvaluator.scope(for: .other("10d"), providerID: .codex) == nil)
        #expect(UseItUpEvaluator.scope(for: .other("Billing period"), providerID: .codex) == nil)
        #expect(UseItUpEvaluator.scope(for: .other("30d"), providerID: .grok) == .billingPeriod)
        #expect(UseItUpEvaluator.scope(for: .other("Billing period"), providerID: .grok) == .billingPeriod)
        #expect(UseItUpEvaluator.scope(for: .other("Billing period"), providerID: .cursor) == .billingPeriod)
        #expect(UseItUpEvaluator.scope(for: .other("12h"), providerID: .grok) == nil)
    }

    @Test func lengthFollowsTheKind() {
        #expect(UseItUpEvaluator.length(of: .fiveHour) == 5 * hour)
        #expect(UseItUpEvaluator.length(of: .weekly) == 7 * day)
        #expect(UseItUpEvaluator.length(of: .other("Weekly (Fable)")) == 7 * day)
        #expect(UseItUpEvaluator.length(of: .other("GPT-5 5h")) == 5 * hour)
        #expect(UseItUpEvaluator.length(of: .billingPeriod(label: "Monthly", duration: 31 * day)) == 31 * day)
        #expect(UseItUpEvaluator.length(of: .billingPeriod(label: "Monthly", duration: 0)) == nil)
        #expect(UseItUpEvaluator.length(of: .other("30d")) == 30 * day)
        #expect(UseItUpEvaluator.length(of: .other("Billing period")) == nil)
    }

    /// Unknown length skips the length check rather than blocking the rule.
    @Test func unknownLengthSkipsTheLengthCheck() {
        let thirtyDays = ReminderRule(amount: 30, unit: .days, threshold: 50)
        let snap = snapshot(.grok, [window(.other("Billing period"), left: 90, resetsIn: 20 * day)])
        #expect(evaluate(snap, settings: settings(rules: [thirtyDays])).count == 1)
    }

    @Test func unknownOtherLabelsAreExcluded() {
        #expect(evaluate(snapshot(.claude, [window(.other("Mystery pool"), left: 90, resetsIn: 3 * hour)])).isEmpty)
        #expect(evaluate(snapshot(.codex, [window(.other("10d"), left: 90, resetsIn: 3 * hour)])).isEmpty)
        #expect(evaluate(snapshot(.grok, [window(.other("30d"), left: 90, resetsIn: 3 * hour)])).count == 1)
    }

    @Test func codexSparkRowsFollowTheInAppSetting() {
        let spark = snapshot(.codex, [window(.other("GPT-5.3-Codex-Spark weekly"), left: 100, resetsIn: 20 * hour)])
        #expect(evaluate(spark, settings: settings(spark: false)).isEmpty)
        #expect(evaluate(spark, settings: settings(spark: true)).count == 1)
    }

    // MARK: - Cycles (KTD4, KTD5)

    @Test func smallDeadlineDriftStaysInTheSameCycle() {
        let ledger = freshLedger()
        let first = evaluate(snapshot(.codex, [window(left: 80, resetsIn: 23 * hour)]), ledger: ledger)
        apply(first, to: ledger)

        let later = now.addingTimeInterval(5 * 60)
        let drifted = snapshot(.codex, [window(left: 80, resetsIn: 23 * hour - 5 * 60 + 8, at: later)], at: later)
        #expect(evaluate(drifted, ledger: ledger, now: later).isEmpty)
    }

    @Test func nextWeeksDeadlineStartsANewCycle() {
        let ledger = freshLedger()
        apply(evaluate(snapshot(.codex, [window(left: 80, resetsIn: 23 * hour)]), ledger: ledger), to: ledger)

        let nextWeek = now.addingTimeInterval(7 * day)
        let snap = snapshot(.codex, [window(left: 80, resetsIn: 23 * hour, at: nextWeek)], at: nextWeek)
        let proposals = evaluate(snap, ledger: ledger, now: nextWeek)
        #expect(proposals.count == 1)
        apply(proposals, to: ledger, now: nextWeek)
        #expect(ledger.entry(for: codex, windowID: "weekly")?.firedKeys == [oneDay.firingKey])
    }

    @Test func aDeadlineJustOverTheToleranceIsANewCycle() {
        let ledger = freshLedger()
        apply(evaluate(snapshot(.codex, [window(left: 80, resetsIn: 23 * hour)]), ledger: ledger), to: ledger)
        #expect(evaluate(snapshot(.codex, [window(left: 80, resetsIn: 23 * hour + 30 * 60)]), ledger: ledger).isEmpty)
        #expect(evaluate(snapshot(.codex, [window(left: 80, resetsIn: 23 * hour + 31 * 60)]), ledger: ledger).count == 1)
    }

    @Test func anEditedRuleIsDueAgainInTheSameCycle() {
        let ledger = freshLedger()
        let snap = snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)])
        apply(evaluate(snap, ledger: ledger), to: ledger)

        var edited = ReminderRules.defaults
        edited[0].threshold = 40
        let proposals = evaluate(snap, settings: settings(rules: edited), ledger: ledger)
        #expect(proposals.count == 1)
        #expect(proposals[0].dueRules.map(\.id) == [oneDay.id])
    }

    @Test func secondRuleInTheSameCycleFiresLaterAndKeepsTheFirst() {
        let ledger = freshLedger()
        apply(evaluate(snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)]), ledger: ledger), to: ledger)

        let later = now.addingTimeInterval(18 * hour)
        let snap = snapshot(.claude, [window(left: 70, resetsIn: 5 * hour, at: later)], at: later)
        let proposals = evaluate(snap, ledger: ledger, now: later)
        #expect(proposals.count == 1)
        #expect(proposals[0].dueRules.map(\.id) == [sixHours.id])
        apply(proposals, to: ledger, now: later)
        #expect(Set(ledger.entry(for: claude, windowID: "weekly")?.firedKeys ?? []) == [oneDay.firingKey, sixHours.firingKey])
    }

    @Test func accountsHaveIndependentCycles() {
        let ledger = freshLedger()
        let snap = snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)])
        apply(evaluate(snap, account: claude, ledger: ledger), to: ledger)
        #expect(evaluate(snap, account: claude, ledger: ledger).isEmpty)
        #expect(evaluate(snap, account: claudeWork, ledger: ledger).count == 1)
    }

    // MARK: - Ledger

    @Test func ledgerSurvivesANewInstance() {
        let suite = "headroom.use-it-up.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let snap = snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)])
        apply(evaluate(snap, ledger: UseItUpLedger(defaults: defaults)), to: UseItUpLedger(defaults: defaults))
        #expect(evaluate(snap, ledger: UseItUpLedger(defaults: defaults)).isEmpty)
    }

    @Test func entriesADayPastTheirDeadlineArePrunedOnWrite() {
        let ledger = freshLedger()
        let old = UseItUpLedgerEntry(account: claude, windowID: "weekly", deadline: now.addingTimeInterval(hour), firedKeys: [oneDay.firingKey])
        let recent = UseItUpLedgerEntry(account: codex, windowID: "weekly", deadline: now.addingTimeInterval(hour), firedKeys: [oneDay.firingKey])
        let active = Set(ReminderRules.defaults.map(\.firingKey))
        ledger.record(old, activeFiringKeys: active, now: now)
        ledger.record(recent, activeFiringKeys: active, now: now)

        // 23h past both deadlines: nothing pruned yet.
        let fresh = UseItUpLedgerEntry(account: grok, windowID: "billing:Monthly", deadline: now.addingTimeInterval(30 * day), firedKeys: [oneDay.firingKey])
        ledger.record(fresh, activeFiringKeys: active, now: now.addingTimeInterval(24 * hour))
        #expect(ledger.entries().count == 3)

        // Over a day past: pruned on the next write.
        ledger.record(fresh, activeFiringKeys: active, now: now.addingTimeInterval(25 * hour + 1))
        #expect(ledger.entry(for: claude, windowID: "weekly") == nil)
        #expect(ledger.entry(for: codex, windowID: "weekly") == nil)
        #expect(ledger.entry(for: grok, windowID: "billing:Monthly") != nil)
    }

    @Test func firingKeysForRemovedRulesArePrunedOnWrite() {
        let ledger = freshLedger()
        let entry = UseItUpLedgerEntry(
            account: claude,
            windowID: "weekly",
            deadline: now.addingTimeInterval(hour),
            firedKeys: [oneDay.firingKey, "gone:60:10"]
        )
        ledger.record(entry, activeFiringKeys: [oneDay.firingKey], now: now)
        #expect(ledger.entry(for: claude, windowID: "weekly")?.firedKeys == [oneDay.firingKey])
    }

    @Test func purgeRemovesEveryEntryForTheAccountOnly() {
        let ledger = freshLedger()
        let active = Set(ReminderRules.defaults.map(\.firingKey))
        for id in ["weekly", "fiveHour"] {
            ledger.record(UseItUpLedgerEntry(account: claude, windowID: id, deadline: now.addingTimeInterval(hour), firedKeys: [oneDay.firingKey]), activeFiringKeys: active, now: now)
        }
        ledger.record(UseItUpLedgerEntry(account: claudeWork, windowID: "weekly", deadline: now.addingTimeInterval(hour), firedKeys: [oneDay.firingKey]), activeFiringKeys: active, now: now)
        ledger.purge(for: claude)
        #expect(ledger.entries().map(\.account) == [claudeWork])
    }

    @Test func corruptLedgerReadsAsEmpty() {
        let suite = "headroom.use-it-up.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(Data("nope".utf8), forKey: "useItUpLedger.v1")
        #expect(UseItUpLedger(defaults: defaults).entries().isEmpty)
    }

    // MARK: - Copy (R13, KTD12, KTD13)

    private func content(_ proposal: UseItUpProposal, provider: String, accountLabel: String? = nil) -> NotificationContent {
        let content = NotificationContent.useItUp(
            proposal,
            providerName: provider,
            accountLabel: accountLabel,
            now: now,
            timeZone: zone,
            locale: locale
        )
        return NotificationContent(
            identifier: content.identifier,
            threadIdentifier: content.threadIdentifier,
            title: content.title,
            body: content.body.replacingOccurrences(of: "\u{202F}", with: " ")
        )
    }

    @Test func singleAccountCopy() {
        let proposal = evaluate(snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)]))[0]
        let banner = content(proposal, provider: "Claude")
        #expect(banner.title == "80% of Claude Weekly is still unused")
        #expect(banner.body == "Resets in 23h, tomorrow at 9:00 AM.")
        let epochMinutes = Int(now.addingTimeInterval(23 * hour).timeIntervalSince1970 / 60)
        #expect(banner.identifier == "use-it-up.claude.primary.weekly.\(epochMinutes)")
        #expect(banner.threadIdentifier == "claude.primary")
    }

    @Test func multiAccountCopyNamesTheAccount() {
        let proposal = evaluate(snapshot(.claude, [window(left: 80, resetsIn: 23 * hour)]), account: claudeWork)[0]
        let banner = content(proposal, provider: "Claude", accountLabel: "Work")
        #expect(banner.title == "80% of Claude Weekly (Work) is still unused")
        #expect(banner.threadIdentifier == "claude.work")
        #expect(banner.identifier.hasPrefix("use-it-up.claude.work.weekly."))
    }

    @Test func limitNamesArePrefixedWithTheProviderOnce() {
        #expect(UseItUpEvaluator.limitName(for: .weekly, providerName: "Claude") == "Claude Weekly")
        #expect(UseItUpEvaluator.limitName(for: .fiveHour, providerName: "Codex") == "Codex 5-hour")
        #expect(UseItUpEvaluator.limitName(for: .other("Weekly (Fable)"), providerName: "Claude") == "Claude Fable weekly")
        #expect(UseItUpEvaluator.limitName(for: .other("GPT-5 weekly"), providerName: "Codex") == "Codex GPT-5 weekly")
        #expect(UseItUpEvaluator.limitName(for: .billingPeriod(label: "Monthly", duration: 30 * day), providerName: "Grok") == "Grok Monthly")
        #expect(UseItUpEvaluator.limitName(for: .billingPeriod(label: "Cursor Models", duration: 30 * day), providerName: "Cursor") == "Cursor Models")
        #expect(UseItUpEvaluator.limitName(for: .billingPeriod(label: "Other Models", duration: 30 * day), providerName: "Cursor") == "Cursor Other Models")
    }

    @Test func bodyBeyondAWeekUsesAShortDate() {
        let snap = snapshot(.grok, [window(.billingPeriod(label: "Monthly", duration: 30 * day), left: 90, resetsIn: 12 * day)])
        let proposal = evaluate(snap, settings: settings(rules: [ReminderRule(amount: 14, unit: .days, threshold: 50)]))[0]
        #expect(content(proposal, provider: "Grok").body == "Resets in 12d, Oct 7.")
    }
}
