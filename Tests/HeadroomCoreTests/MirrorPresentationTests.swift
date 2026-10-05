import Foundation
import Testing
@testable import HeadroomCore

/// U8: the phone card's pure decisions. The phone renders the popover's own rows, so these
/// pin only what the phone decides on its own: titles, row order, Spark filtering, the body
/// each account state gets, the capsule's critical auto-open, the widget glyph and the KTD7
/// ladder lines. AP1/P19: there is no "Low" chip decision left to pin — critical is the red
/// numeral the shared row paints (`UsageMeterReading.usesCriticalInk`).
struct MirrorPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Copy (R8, KTD7, R2C6)

    @Test func phoneCopyIsPinned() {
        #expect(CompanionCardCopy.noSubscriptions == "Your Mac isn’t tracking any subscriptions")
        #expect(CompanionCardCopy.firstReading == "Waiting for your Mac’s first reading")
        #expect(CompanionCardCopy.waitingForMac == "Waiting for your Mac")
        #expect(CompanionCardCopy.noUsageData == "No usage data")
        #expect(CompanionCardCopy.modelRowsOnMac == "Model rows are on your Mac")
        #expect(CompanionCardCopy.moreOnMac(3) == "3 more on your Mac")
        #expect(CompanionCardCopy.widgetFollows
            == "Your widgets follow this account. Change it with Make Main on your Mac.")
    }

    /// R2C6/R2B1: curly apostrophes, no straight quotes, no retired "connect" verb.
    @Test func phoneCopyFollowsTheHouseRules() {
        let lines = [
            CompanionCardCopy.noSubscriptions, CompanionCardCopy.firstReading,
            CompanionCardCopy.waitingForMac, CompanionCardCopy.noUsageData,
            CompanionCardCopy.modelRowsOnMac, CompanionCardCopy.moreOnMac(2),
            CompanionCardCopy.widgetFollows,
        ]
        for line in lines {
            #expect(!line.contains("'"), "\(line)")
            #expect(!line.localizedCaseInsensitiveContains("connect"), "\(line)")
        }
    }

    // MARK: Titles (KTD9, R15)

    @Test func aSurfaceWithOneAccountPerProviderNamesProviders() {
        let providers = [
            provider("claude", main: account("primary", title: "Personal")),
            provider("codex", main: account("primary", title: "Work")),
        ]
        #expect(CompanionCardPresentation.usesAccountRows(providers) == false)
        #expect(CompanionCardPresentation.title(
            for: providers[1].accounts[0], in: providers[1], usesAccountRows: false) == "Codex")
    }

    /// One provider with two accounts flips every card to account titles; a lone default
    /// label still reads as its provider, exactly like the Mac's `rowTitle`.
    @Test func oneMultiAccountProviderFlipsEveryCardToAccountTitles() {
        let claude = provider(
            "claude", main: account("primary", title: "Personal"),
            extras: [account("work", title: "Work · 2", isMain: false)])
        let grok = provider("grok", main: account("primary", title: "Main"))
        let codex = provider("codex", main: account("primary", title: "Northwind"))
        let all = [claude, grok, codex]
        #expect(CompanionCardPresentation.usesAccountRows(all))
        #expect(claude.accounts.map { CompanionCardPresentation.title(for: $0, in: claude, usesAccountRows: true) }
            == ["Personal", "Work · 2"])
        #expect(CompanionCardPresentation.title(for: grok.accounts[0], in: grok, usesAccountRows: true) == "Grok")
        #expect(CompanionCardPresentation.title(for: codex.accounts[0], in: codex, usesAccountRows: true) == "Northwind")
    }

    // MARK: Rows (R3, KTD11)

    @Test func rowsReadFiveHourFirstThenWeeklyAndPoolsThenModelRows() {
        let fable = window(.other("Weekly (Fable)"))
        let weekly = window(.weekly)
        let fiveHour = window(.fiveHour)
        let pool = window(.other("Cursor Models"), billing: 30 * 86_400)
        let rows = CompanionCardPresentation.rows(account("primary", windows: [fable, weekly, pool, fiveHour]).windows)
        #expect(rows.map(\.kind) == [.fiveHour, .weekly, .other("Cursor Models"), .other("Weekly (Fable)")])
    }

    @Test func sparkRowsFollowTheResolvedSwitch() {
        let spark = CompanionResolvedWindow(summary: window(.other("GPT-5.3-Codex-Spark Weekly")), isSpark: true)
        let acct = CompanionResolvedAccount(
            accountID: "primary", title: "Personal", planName: nil, freshness: .live, attention: nil,
            bankedResets: nil, capturedAt: now,
            windows: [CompanionResolvedWindow(summary: window(.fiveHour), isSpark: false), spark], isMain: true)
        func display(spark: Bool) -> ResolvedPhoneDisplay {
            PhoneDisplayPreferences.resolve(
                mac: CompanionDisplayBlock(appSparkEnabled: spark), phone: .default)
        }
        #expect(CompanionCardPresentation.rows(display(spark: false).appWindows(acct.windows)).map(\.kind) == [.fiveHour])
        #expect(CompanionCardPresentation.rows(display(spark: true).appWindows(acct.windows)).count == 2)
    }

    // MARK: Bodies (R4, R8, KTD10)

    @Test func liveAndTransientStaleKeepTheirMeters() {
        #expect(CompanionCardPresentation.body(for: account("a"), title: "A") == .meters(dimmed: false))
        let stale = account("a", freshness: .stale(message: "x", needsAttention: false), attention: .retrying)
        #expect(CompanionCardPresentation.body(for: stale, title: "A") == .meters(dimmed: true))
        #expect(CompanionCardPresentation.showsStaleChip(stale))
        #expect(CompanionCardPresentation.showsStaleChip(account("a")) == false)
    }

    /// V12: a never-signed-in extra reads one typed line naming the account, never a
    /// skeleton forever, and never the provider's own error text.
    @Test func aSignedOutAccountReadsATypedLineNamingTheAccount() {
        let signedOut = account(
            "account-2", title: "Account 2", freshness: .stale(message: "Not logged in", needsAttention: true),
            attention: .neverOnboarded, windows: [])
        #expect(CompanionCardPresentation.body(for: signedOut, title: "Account 2")
            == .attention("Sign in to Account 2 on your Mac", keepsMeters: false))
        #expect(CompanionCardPresentation.showsStaleChip(signedOut) == false)
    }

    @Test func aPermanentProblemWithRetainedRowsKeepsThemDimmedUnderTheLine() {
        let denied = account(
            "a", freshness: .stale(message: "x", needsAttention: true), attention: .accessDenied,
            windows: [window(.fiveHour)])
        #expect(CompanionCardPresentation.body(for: denied, title: "Work")
            == .attention("Review this account’s access on your Mac", keepsMeters: true))
    }

    /// A lifted v3 row carries no typed attention, so it reads the generic line rather than
    /// guessing "sign in" from the Mac's message (KTD10).
    @Test func untypedAttentionReadsTheGenericLine() {
        let lifted = account("a", freshness: .stale(message: "Token expired", needsAttention: true), attention: nil)
        #expect(CompanionCardPresentation.body(for: lifted, title: "Claude")
            == .attention("Needs attention on your Mac", keepsMeters: true))
    }

    @Test func aTransientStaleAccountWithNothingToShowReadsItsLine() {
        let empty = account(
            "a", freshness: .stale(message: "x", needsAttention: false), attention: .retrying, windows: [])
        #expect(CompanionCardPresentation.body(for: empty, title: "Work")
            == .attention("Couldn’t read usage\u{00A0}—\u{00A0}your Mac will retry", keepsMeters: false))
    }

    @Test func pendingAccountsWaitForTheFirstReadingThenForTheMac() {
        let pending = account("a", freshness: .pending, windows: [])
        #expect(CompanionCardPresentation.body(for: pending, title: "A") == .pending)
        #expect(CompanionCardPresentation.pendingLine(surfaceDimmed: false) == "Waiting for your Mac’s first reading")
        #expect(CompanionCardPresentation.pendingLine(surfaceDimmed: true) == "Waiting for your Mac")
    }

    // MARK: Plan capsule (R5)

    @Test func theCapsuleAutoOpensOnlyForALiveCriticalFiveHourOrWeekly() {
        let critical = account("a", windows: [window(.fiveHour, remaining: 12)], banked: 1)
        let modelOnly = account("a", windows: [window(.other("Weekly (Fable)"), remaining: 5)], banked: 1)
        let staleCritical = account(
            "a", freshness: .stale(message: "x", needsAttention: false),
            windows: [window(.weekly, remaining: 5, freshness: .stale(observedAt: now))], banked: 1)
        #expect(CompanionCardPresentation.autoOpensPlanCapsule(critical))
        #expect(CompanionCardPresentation.autoOpensPlanCapsule(modelOnly) == false)
        #expect(CompanionCardPresentation.autoOpensPlanCapsule(staleCritical) == false)
        #expect(CompanionCardPresentation.autoOpensPlanCapsule(account("a", windows: [window(.weekly, remaining: 16)])) == false)
    }

    // MARK: Widget glyph (U3-A note, spec-flow M4)

    @Test func theWidgetGlyphMarksOnlyTheMainAccountOfAWidgetProviderTitledByName() {
        let claude = provider(
            "claude", main: account("primary", title: "Personal"),
            extras: [account("work", title: "Work", isMain: false)])
        let codex = provider("codex", main: account("primary", title: "Personal"))
        let grok = provider("grok", main: account("primary", title: "Personal"))
        let widgetIDs = ["claude", "codex"]
        func glyph(_ account: CompanionResolvedAccount, _ provider: CompanionResolvedProvider, rows: Bool = true) -> Bool {
            CompanionCardPresentation.showsWidgetGlyph(
                account: account, in: provider,
                title: CompanionCardPresentation.title(for: account, in: provider, usesAccountRows: rows),
                usesAccountRows: rows, widgetProviderIDs: widgetIDs)
        }
        #expect(glyph(claude.accounts[0], claude))
        #expect(glyph(claude.accounts[1], claude) == false)
        #expect(glyph(codex.accounts[0], codex))
        #expect(glyph(grok.accounts[0], grok) == false)
        // Titled by provider name: the card already says which account the widgets follow.
        #expect(glyph(codex.accounts[0], codex, rows: false) == false)
    }

    /// The glyph follows what the widgets actually show: the Mac's selection, else the first
    /// two providers, exactly like `WidgetSnapshotEnvelope.widgetProviders`.
    @Test func widgetProvidersComeFromTheResolvedProjection() throws {
        let multi = try #require(CompanionDemoData.snapshot(.multiAccount, now: now).content)
        #expect(CompanionCardPresentation.widgetProviderIDs(multi) == ["claude", "codex"])
        let states = try #require(CompanionDemoData.snapshot(.accountStates, now: now).content)
        #expect(CompanionCardPresentation.widgetProviderIDs(states) == ["codex"])
    }

    // MARK: Ladder lines (KTD7)

    @Test func aCappedStackEndsWithTheOmittedCount() {
        let capped = provider("claude", main: account("primary"), extras: [account("b", isMain: false)], omitted: 60)
        #expect(CompanionCardPresentation.footerLines(for: capped, ladder: .accountCap) == ["60 more on your Mac"])
        let withModelRows = provider(
            "claude", main: account("primary", windows: [window(.fiveHour), window(.other("Weekly (Fable)"))]),
            extras: [account("b", isMain: false)], omitted: 60)
        #expect(CompanionCardPresentation.footerLines(for: withModelRows, ladder: .accountCap)
            == ["Model rows are on your Mac", "60 more on your Mac"])
    }

    @Test func modelRowsLineNeedsTrimmedExtrasOfAProviderThatHasModelRows() {
        let main = account("primary", windows: [window(.fiveHour), window(.other("Weekly (Fable)"))])
        let withExtras = provider("claude", main: main, extras: [account("b", isMain: false)])
        let alone = provider("claude", main: main)
        let pools = provider(
            "grok", main: account("primary", windows: [window(.other("Weekly"), billing: 7 * 86_400)]),
            extras: [account("b", isMain: false)])
        #expect(CompanionCardPresentation.footerLines(for: withExtras, ladder: .modelRowsDropped)
            == ["Model rows are on your Mac"])
        #expect(CompanionCardPresentation.footerLines(for: withExtras, ladder: .full).isEmpty)
        #expect(CompanionCardPresentation.footerLines(for: alone, ladder: .modelRowsDropped).isEmpty)
        #expect(CompanionCardPresentation.footerLines(for: pools, ladder: .modelRowsDropped).isEmpty)
    }

    /// The above-envelope demo reaches the account cap on its own (KTD7 level 2).
    @Test func theAboveEnvelopeDemoShowsTheCap() throws {
        let content = try #require(CompanionDemoData.snapshot(.aboveEnvelope, now: now).content)
        let claude = try #require(content.providers.first)
        let omitted = CompanionDemoData.aboveEnvelopeCount - CompanionSyncBudget.accountEnvelope
        #expect(CompanionCardPresentation.footerLines(for: claude, ladder: content.ladder).last
            == "\(omitted) more on your Mac")
    }

    // MARK: Phone scale (KTD3)

    @Test func phoneScaleStopsGrowingAtXXXLarge() {
        #expect(PhoneScale.clamped(PhoneScale.defaultFactor) == PhoneScale.defaultFactor)
        #expect(abs(PhoneScale.maximumFactor - 1.15 * 23 / 17) < 0.0001)
        #expect(PhoneScale.clamped(1.15 * 53 / 17) == PhoneScale.maximumFactor)
        #expect(PhoneScale.clamped(0.5) == PhoneScale.popover)
        #expect(PhoneScale.clamped(.nan) == PhoneScale.defaultFactor)
    }

    // MARK: Updated label

    @Test func updatedLabelWrapsCountdown() {
        #expect(MirrorPresentation.updatedLabel(generatedAt: nil, now: now) == nil)
        #expect(MirrorPresentation.updatedLabel(generatedAt: now, now: now) == "just now")
        #expect(MirrorPresentation.updatedLabel(generatedAt: now.addingTimeInterval(-300), now: now) == "5 min ago")
    }

    // MARK: Fixtures

    private func window(
        _ kind: WidgetWindowKind, remaining: Double = 42, billing: TimeInterval? = nil,
        freshness: WidgetWindowFreshness = .live
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind, label: kind.id, percentRemaining: remaining,
            resetSchedule: .scheduled(now.addingTimeInterval(3_600)), resetLabel: nil,
            severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: remaining)), freshness: freshness,
            billingPeriodDuration: billing)
    }

    private func account(
        _ id: String, title: String = "Personal", freshness: WidgetProviderFreshness = .live,
        attention: CompanionAttention? = nil, windows: [WidgetWindowSummary]? = nil, banked: Int? = nil,
        isMain: Bool = true
    ) -> CompanionResolvedAccount {
        CompanionResolvedAccount(
            accountID: id, title: title, planName: "Max", freshness: freshness, attention: attention,
            bankedResets: banked, capturedAt: now,
            windows: (windows ?? [window(.fiveHour)]).map { CompanionResolvedWindow(summary: $0, isSpark: false) },
            isMain: isMain)
    }

    private func provider(
        _ id: String, main: CompanionResolvedAccount, extras: [CompanionResolvedAccount] = [], omitted: Int = 0
    ) -> CompanionResolvedProvider {
        CompanionResolvedProvider(
            id: id, displayName: ProviderID(id).displayName, source: .v4(.manifestDigestMatched),
            capabilityAttention: nil, mainAccount: main, extraAccounts: extras, omittedAccountCount: omitted,
            lag: .current, payloadGeneration: 1, effectiveIntervalSeconds: 300)
    }
}
