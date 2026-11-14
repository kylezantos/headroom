import Foundation
import Testing

@testable import HeadroomCore

/// U21: the usage screen's pure decisions — the freshness line, the past-reset and dimmed
/// rows, the shared spend rows and the old-Mac line. Inputs are the bundled demo variants
/// through the real codec and resolver, so the fixtures the UI tests launch are the ones
/// pinned here.
@Suite
struct PhoneUsageScreenTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private let utc = TimeZone(identifier: "UTC")!
    private let posix = Locale(identifier: "en_US_POSIX")

    private func content(_ variant: CompanionDemoVariant) throws -> CompanionResolvedContent {
        try #require(CompanionDemoData.snapshot(variant, now: now).content)
    }

    private func allWindows(_ account: CompanionResolvedAccount) -> [WidgetWindowSummary] {
        account.widgetWindows
    }

    // MARK: R9: "Updated" is the oldest live reading

    @Test func updatedNamesTheOldestLiveReadingNotThePublishTime() throws {
        let content = try content(.multiAccount)
        let line = MirrorPresentation.freshness(content, shownWindows: allWindows, now: now, timeZone: utc, locale: posix)
        // Every demo reading is 135 s old; the publish is newer than that.
        #expect(line == .stamp(FreshnessStamp(kind: .updated, text: "2 min ago", rollValue: 2)))
        #expect(line.text == "Updated 2 min ago")
        #expect(!line.isDimmed)
        #expect(MirrorPresentation.subtitle(for: FreshnessStamp(kind: .updated, text: "Just now", rollValue: 0))
            == "Updated just now")
    }

    @Test func aStaleAccountAndAPastResetRowDoNotDragTheStampBack() throws {
        let content = try content(.pastReset)
        let anchors = MirrorPresentation.stampAnchors(content, shownWindows: allWindows, now: now)
        // Claude Personal is stale and observed 50 min ago; every live reading is 135 s old.
        #expect(anchors.oldestLive == now.addingTimeInterval(-CompanionDemoData.captureAge))
    }

    /// Review 2 testing gap: the past-reset guard on its own. The Claude main account is live;
    /// add a live 5-hour reading observed two hours ago. Before its reset it is the oldest live
    /// reading and anchors "Updated"; once its reset has passed it is hidden, so it does not.
    @Test func aLiveAccountsPastResetRowDoesNotDragTheStampBack() throws {
        let content = try content(.multiAccount)
        let main = try #require(content.providers.first { $0.id == "claude" }?.mainAccount)
        #expect(main.freshness == .live)
        let observed = now.addingTimeInterval(-2 * 3_600)
        func window(resetsAt: Date) -> WidgetWindowSummary {
            WidgetWindowSummary(
                kind: .fiveHour, label: "5-hour", percentRemaining: 40, resetSchedule: .scheduled(resetsAt),
                resetLabel: nil, observedAt: observed, severity: .healthy, freshness: .live)
        }
        func anchors(_ added: WidgetWindowSummary) -> FreshnessStamp.Anchors {
            MirrorPresentation.stampAnchors(content, shownWindows: { account in
                account == main ? account.widgetWindows + [added] : account.widgetWindows
            }, now: now)
        }
        let beforeReset = window(resetsAt: now.addingTimeInterval(3_600))
        #expect(CompanionFreshnessRule.pastResetTime(beforeReset, at: now) == nil)
        #expect(anchors(beforeReset).oldestLive == observed, "a live reading before its reset anchors the stamp")

        let pastReset = window(resetsAt: now.addingTimeInterval(-25 * 60))
        #expect(CompanionFreshnessRule.pastResetTime(pastReset, at: now) != nil)
        let anchored = anchors(pastReset)
        #expect(anchored.oldestLive == now.addingTimeInterval(-CompanionDemoData.captureAge))
        #expect(anchored.newestCheck != nil)
    }

    // MARK: R10: dimming

    @Test func aQuietMacDimsTheSurfaceWithTheNoUpdateSentence() throws {
        let content = try content(.dimmed)
        let line = MirrorPresentation.freshness(content, shownWindows: allWindows, now: now, timeZone: utc, locale: posix)
        #expect(line.isDimmed)
        let heard = WidgetClockText.text(for: now.addingTimeInterval(-2 * 3_600), now: now, timeZone: utc, locale: posix)
        #expect(line.text == "No update from your Mac since \(heard)")
        #expect(!line.text.localizedCaseInsensitiveContains("asleep"))
    }

    /// AE5 / KTD15: a stale row under a dimmed surface is demoted once, exactly like a live
    /// row; a row is dimmed or it isn't.
    @Test func surfaceDimmingAndRowStaleDemoteOnce() {
        let live = CompanionCardPresentation.rowsDimmed(accountDimmed: false, surfaceDimmed: true)
        let stale = CompanionCardPresentation.rowsDimmed(accountDimmed: true, surfaceDimmed: true)
        #expect(live == stale)
        #expect(CompanionCardPresentation.rowsDimmed(accountDimmed: true, surfaceDimmed: false))
        #expect(!CompanionCardPresentation.rowsDimmed(accountDimmed: false, surfaceDimmed: false))
    }

    // MARK: R11: past reset

    @Test func aPastResetRowHidesItsNumberAndNamesTheReset() throws {
        let content = try content(.pastReset)
        let personal = try #require(content.providers.first { $0.id == "claude" }?.mainAccount)
        let rows = CompanionCardPresentation.meterRows(personal.windows, now: now)
        let fiveHour = try #require(rows.first { $0.window.kind == .fiveHour })
        let resetAt = now.addingTimeInterval(-25 * 60)
        #expect(fiveHour.pastResetAt == resetAt)
        #expect(fiveHour.window.displayPercentRemaining == nil)
        #expect(fiveHour.window.freshness.isUnavailable)
        // Rows not past their reset keep their numbers.
        #expect(rows.filter { $0.pastResetAt == nil }.allSatisfy { $0.window.displayPercentRemaining != nil })
        let time = WidgetClockText.text(for: resetAt, now: now, timeZone: utc, locale: posix)
        #expect(CompanionCardPresentation.pastResetLine(resetAt, now: now, timeZone: utc, locale: posix)
            == "Reset at \(time) · waiting for your Mac")
    }

    @Test func rowsKeepTheReadingOrder() throws {
        let content = try content(.multiAccount)
        let personal = try #require(content.providers.first?.mainAccount)
        #expect(CompanionCardPresentation.meterRows(personal.windows, now: now).map(\.window)
            == CompanionCardPresentation.rows(personal.windows))
    }

    // MARK: R14: old Mac

    @Test func onlyAnOlderMacAsksToBeUpdated() throws {
        #expect(CompanionCardPresentation.compatibilityLine(try content(.oldMac))
            == "Update Headroom on your Mac to see every account")
        #expect(CompanionCardPresentation.compatibilityLine(try content(.multiAccount)) == nil)
        // AE1: the old Mac's v3 carries main accounts only.
        #expect(try content(.oldMac).providers.allSatisfy { $0.extraAccounts.isEmpty })
    }

    // MARK: Spend rows (P45–P53)

    @Test func spendRowsResolveThePopoverDecisions() throws {
        let rows = try content(.multiAccount).apiSpend.map(CompanionSpendRowModel.init)
        #expect(rows.map(\.title) == ["Anthropic API", "OpenAI API"])
        #expect(rows.map(\.amount) == ["$142.67", "$58.90"])
        #expect(rows.allSatisfy { $0.snapshot.freshness == .live && $0.status.message == nil })
        #expect(rows.allSatisfy { $0.contextLabel == $0.snapshot.periodLabel })
        #expect(APISpendPresentation.directionTerm(kind: rows[0].snapshot.kind) == "used")
    }

    @Test func aRetainedSpendRowIsNotLiveAndCarriesItsStaleTag() throws {
        let rows = try content(.staleSpend).apiSpend.map(CompanionSpendRowModel.init)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.snapshot.freshness != .live && $0.snapshot.freshness != .pending })
        #expect(rows.allSatisfy { $0.status.shortBadge == "Stale" })
        #expect(rows.allSatisfy { $0.amount != nil }, "a retained figure stays visible")
    }

    /// X5: a balance row's "Balance" (CA-S8, was "Remaining balance") outranks the name's
    /// qualifier.
    @Test func aBalanceRowKeepsRemainingBalanceOverTheQualifier() {
        let summary = WidgetAPISpendSummary(
            id: "grok", displayName: "xAI prepaid", amount: 12, currency: "usd", periodLabel: "October",
            kind: .balance, capturedAt: now, freshness: .live)
        let row = CompanionSpendRowModel(summary)
        #expect(row.title == "xAI")
        #expect(row.contextLabel == "Balance")
        #expect(APISpendPresentation.popoverIdentity(displayName: "xAI prepaid").chipOverride != nil,
                "the name does carry a qualifier the balance label outranks")
    }

    /// A stale summary that needs attention maps to the re-auth failure, not a transient one,
    /// and its status is the attention status (no typed attention on the wire: setup required).
    @Test func aStaleSummaryThatNeedsAttentionMapsToReauth() {
        let summary = WidgetAPISpendSummary(
            id: "claude", displayName: "Anthropic API", amount: 142.67, currency: "usd", periodLabel: "Current month",
            capturedAt: now, freshness: .stale(message: "Key revoked", needsAttention: true))
        let row = CompanionSpendRowModel(summary)
        #expect(row.snapshot.freshness == .stale(.needsReauth("Key revoked")))
        #expect(row.status == APISpendPresentation.rowStatus(
            freshness: .stale(message: "Key revoked", needsAttention: true), attention: .setupRequired,
            providerID: .claude, displayName: "Anthropic API"))
        let transient = CompanionSpendRowModel(WidgetAPISpendSummary(
            id: "claude", displayName: "Anthropic API", amount: 142.67, currency: "usd", periodLabel: "Current month",
            capturedAt: now, freshness: .stale(message: "Timed out", needsAttention: false)))
        #expect(transient.snapshot.freshness == .stale(.transient("Timed out")))
        #expect(transient.status != row.status)
    }

    @Test func aQualifiedNameMovesItsQualifierIntoTheChip() {
        let summary = WidgetAPISpendSummary(
            id: "cursor", displayName: "Cursor on-demand", amount: 3, currency: "usd", periodLabel: "October",
            capturedAt: now, freshness: .live)
        let row = CompanionSpendRowModel(summary)
        #expect(row.title == "Cursor")
        #expect(row.contextLabel == "On-demand")
    }
}
