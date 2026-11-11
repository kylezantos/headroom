import Foundation

/// U8 (R8, KTD7): every line the phone's provider cards print on their own. Pinned here so
/// the copy tests (R2C6: curly apostrophes, one sign-in verb) cover them; the attention
/// sentences come from `CompanionAttentionCopy`.
public enum CompanionCardCopy {
    /// M3: a Mac that tracks nothing gets a line, never a blank screen.
    public static let noSubscriptions = "Your Mac isn’t tracking any subscriptions"
    /// P24: a pending account or provider before the Mac's first reading. No spinner beside
    /// it — nothing on the phone is working, it is waiting.
    public static let firstReading = "Waiting for your Mac’s first reading"
    /// KTD6.3: the same skeleton once the surface's freshness rule dims.
    public static let waitingForMac = CompanionFreshnessCopy.waitingForMac
    /// P25: a live account with no rows, as the popover prints it.
    public static let noUsageData = "No usage data"
    /// KTD7 level 1: the Mac dropped extra accounts' model rows to fit the budget.
    public static let modelRowsOnMac = "Model rows are on your Mac"
    /// KTD7 level 2: extra accounts the Mac capped off the end of the stack.
    public static func moreOnMac(_ count: Int) -> String { "\(count) more on your Mac" }
    /// U3-A note: the widget glyph's explanation. Make Main is the Mac's word for it.
    public static let widgetFollows = "Your widgets follow this account. Change it with Make Main on your Mac."
}

/// What one account section shows under its identity row.
public enum CompanionAccountBody: Equatable, Sendable {
    /// Live or transient stale: the meter rows, dimmed when the reading is not live.
    case meters(dimmed: Bool)
    /// R4/KTD10: a typed line in neutral ink, with any retained rows dimmed beneath it.
    case attention(String, keepsMeters: Bool)
    /// P24/R8: skeleton meters and the waiting line.
    case pending
}

/// U8: the phone card's pure decisions over the resolved model (KTD6). SwiftUI only lays
/// these out with the popover's shared rows.
public enum CompanionCardPresentation {
    /// KTD9's surface-wide flip, as the popover makes it: one provider with two or more
    /// accounts turns every card to account titles.
    public static func usesAccountRows(_ providers: [CompanionResolvedProvider]) -> Bool {
        providers.contains { $0.accounts.count > 1 }
    }

    /// The Mac's `rowTitle` over the Mac-resolved title (KTD9): provider names on a surface
    /// with one account each, account titles otherwise, and a lone default label still
    /// reads as its provider. Titles keep their " · N" suffix; nothing here invents one.
    public static func title(
        for account: CompanionResolvedAccount, in provider: CompanionResolvedProvider, usesAccountRows: Bool
    ) -> String {
        guard usesAccountRows else { return provider.displayName }
        if provider.accounts.count == 1,
            account.title.isEmpty || ProviderAccount.isDefaultLabel(account.title)
        {
            return provider.displayName
        }
        return account.title
    }

    /// R3/P20: 5-hour first, then weekly and billing pools, then model rows — the popover's
    /// `UsageSnapshot.fiveHourFirst()` rank, stable within a rank. KTD11/KTD13: the caller
    /// passes the windows the phone's display choice keeps (`ResolvedPhoneDisplay.appWindows`
    /// filters flagged Spark rows by the phone's switch).
    public static func rows(_ windows: [CompanionResolvedWindow]) -> [WidgetWindowSummary] {
        windows
            .map(\.summary)
            .enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private static func rank(_ window: WidgetWindowSummary) -> Int {
        switch window.kind {
        case .fiveHour: 0
        case .weekly: 1
        case .other: isBillingPool(window) ? 1 : 2
        }
    }

    private static func isBillingPool(_ window: WidgetWindowSummary) -> Bool {
        guard let duration = window.billingPeriodDuration else { return false }
        return duration.isFinite && duration > 0
    }

    /// R4/P39: what an account's section says. A permanent problem — or a stale account with
    /// nothing left to show — is one typed sentence naming the account; transient staleness
    /// keeps its dimmed meters and the Stale chip, as the popover does.
    public static func body(for account: CompanionResolvedAccount, title: String) -> CompanionAccountBody {
        // Default-login R7, R12: a remembered row is its dimmed last reading, never a typed
        // problem; its last-read tag stands in for the line.
        if account.isRemembered { return .meters(dimmed: true) }
        switch account.freshness {
        case .pending:
            return .pending
        case .live:
            return .meters(dimmed: false)
        case .stale(_, let needsAttention):
            let hasRows = !account.windows.isEmpty
            guard needsAttention || !hasRows else { return .meters(dimmed: true) }
            return .attention(
                CompanionAttentionCopy.account(account.attention, title: title), keepsMeters: hasRows)
        }
    }

    /// P23/P33: the outlined Stale chip marks transient staleness only; a permanent problem
    /// has its sentence instead.
    public static func showsStaleChip(_ account: CompanionResolvedAccount) -> Bool {
        // A remembered row carries "Last read …" in the chip's place (R7).
        guard !account.isRemembered else { return false }
        if case .stale(_, needsAttention: false) = account.freshness { return !account.windows.isEmpty }
        return false
    }

    /// Default-login R7, R21: "Last read 2 min ago" beside a remembered row's title, the
    /// Mac's wording through the shared `Countdown` label. Nil for every other account.
    public static func lastReadLabel(for account: CompanionResolvedAccount, now: Date) -> String? {
        guard account.isRemembered else { return nil }
        return Countdown.lastReadLabel(capturedAt: account.capturedAt, now: now)
    }

    /// KTD6.3 / P24: the waiting line under a skeleton.
    public static func pendingLine(surfaceDimmed: Bool) -> String {
        surfaceDimmed ? CompanionCardCopy.waitingForMac : CompanionCardCopy.firstReading
    }

    /// R5/KTD6.2: the capsule opens on its own while a live 5-hour or weekly window is
    /// Critical, read through the same normalized readings the shared row paints, so the
    /// phone and the Mac capsule agree at every rounding boundary.
    public static func autoOpensPlanCapsule(_ account: CompanionResolvedAccount) -> Bool {
        PlanCapsulePresentation.hasLiveCriticalResettableWindow(
            snapshotIsLive: account.freshness == .live,
            readings: account.widgetWindows.map(UsageMeterReading.init(widgetSummary:)))
    }

    /// The providers the Home Screen widgets show, from the same projection they read
    /// (KTD13): the Mac's selection, else the first two providers.
    public static func widgetProviderIDs(_ content: CompanionResolvedContent) -> [String] {
        CompanionResolvedSnapshot(state: .content(content)).primaryProjection()?.widgetProviders.map(\.id) ?? []
    }

    /// U3-A: the glyph marks the account the widgets follow — the main account of a provider
    /// the widgets show — only where accounts are titled by name. A card titled by its
    /// provider already says which account that is.
    public static func showsWidgetGlyph(
        account: CompanionResolvedAccount, in provider: CompanionResolvedProvider, title: String,
        usesAccountRows: Bool, widgetProviderIDs: [String]
    ) -> Bool {
        account.isMain && usesAccountRows && title != provider.displayName
            && widgetProviderIDs.contains(provider.id)
    }

    /// KTD7: the lines that end a stack. "Model rows are on your Mac" once the Mac has
    /// dropped extra accounts' model rows, for a provider that has them; "N more on your
    /// Mac" when the stack itself was capped.
    public static func footerLines(for provider: CompanionResolvedProvider, ladder: CompanionDropLadder) -> [String] {
        var lines: [String] = []
        let trimmed = ladder == .modelRowsDropped || ladder == .accountCap
        let hasModelRows = provider.mainAccount?.widgetWindows.contains { rank($0) == 2 } ?? false
        if trimmed, hasModelRows, !provider.extraAccounts.isEmpty {
            lines.append(CompanionCardCopy.modelRowsOnMac)
        }
        if provider.omittedAccountCount > 0 {
            lines.append(CompanionCardCopy.moreOnMac(provider.omittedAccountCount))
        }
        return lines
    }
}

public enum MirrorPresentation {
    public static func updatedLabel(generatedAt: Date?, now: Date) -> String? {
        Countdown.updatedLabel(capturedAt: generatedAt, now: now)
    }
}

// MARK: - U21: freshness line, meter rows and spend rows

/// U21 (R9, R10, KTD15): what the slot under "Usage" says when no check-now line is showing.
public enum CompanionScreenFreshness: Equatable, Sendable {
    /// R9: the oldest live reading on screen, never the Mac's publish time.
    case stamp(FreshnessStamp)
    /// R10: "No update from your Mac since <time>", in the stamp's own slot.
    case dimmed(String)

    public var text: String {
        switch self {
        case .stamp(let stamp): MirrorPresentation.subtitle(for: stamp)
        case .dimmed(let line): line
        }
    }

    public var isDimmed: Bool {
        if case .dimmed = self { true } else { false }
    }
}

/// One meter row as the phone draws it (R11): a window past its reset with no newer reading
/// goes through the unavailable path — no numeral, no fill — and carries the reset time its
/// "Reset at <time> · waiting for your Mac" line names.
public struct CompanionMeterRow: Equatable, Sendable {
    public let window: WidgetWindowSummary
    public let pastResetAt: Date?
}

/// U21 (KTD3, P45–P53): one API spend row, resolved for the shared `APISpendRow` from the
/// synced summary. The same Core decisions the popover's row model makes — title and chip
/// split, context label, amount text, status — so the two rows cannot drift.
public struct CompanionSpendRowModel: Equatable, Sendable, Identifiable {
    public let snapshot: APISpendSnapshot
    public let status: APISpendRowStatus
    public let title: String
    public let contextLabel: String
    /// The figure alone; the shared row prints the "used"/"left" term after it.
    public let amount: String?

    public var id: String { snapshot.providerID.raw }

    public init(_ summary: WidgetAPISpendSummary) {
        let kind = summary.semanticKind
        let freshness: Freshness = switch summary.freshness {
        case .pending: .pending
        case .live: .live
        // The row only distinguishes live, pending and not-live; the typed status below
        // carries what the stale line says, so no message is re-derived from this reason.
        case .stale(let message, let needsAttention): .stale(needsAttention ? .needsReauth(message) : .transient(message))
        }
        snapshot = APISpendSnapshot(
            providerID: ProviderID(summary.id), displayName: summary.displayName, amount: summary.amount,
            currency: summary.currency, periodLabel: summary.periodLabel, kind: kind,
            capturedAt: summary.capturedAt, freshness: freshness)
        status = APISpendPresentation.rowStatus(
            freshness: summary.freshness, attention: summary.attention, providerID: ProviderID(summary.id),
            displayName: summary.displayName, kind: kind)
        let identity = APISpendPresentation.popoverIdentity(displayName: summary.displayName)
        let context = APISpendPresentation.contextLabel(kind: kind, periodLabel: summary.periodLabel)
        title = identity.title
        // X5: a balance row's "Remaining balance" outranks the name's qualifier.
        contextLabel = kind == .balance ? context : (identity.chipOverride ?? context)
        amount = APISpendPresentation.amountText(amount: summary.amount, currency: summary.currency)
    }
}

extension MirrorPresentation {
    /// R10/KTD15: the dimmed sentence once the app surface passes its threshold, otherwise the
    /// R9 stamp over the windows the screen shows (`shownWindows` applies the phone's Spark
    /// switch). Times use the shared clock formatter in the user's zone.
    public static func freshness(
        _ content: CompanionResolvedContent,
        shownWindows: (CompanionResolvedAccount) -> [WidgetWindowSummary],
        now: Date, timeZone: TimeZone = .current, locale: Locale = .current
    ) -> CompanionScreenFreshness {
        if CompanionFreshnessRule.isDimmed(content.freshness, surface: .app, at: now) {
            let heard = CompanionFreshnessRule.lastHeardFromMac(content.freshness)
            return .dimmed(CompanionFreshnessCopy.noUpdate(
                since: WidgetClockText.text(for: heard, now: now, timeZone: timeZone, locale: locale)))
        }
        return .stamp(FreshnessStamp.resolve(
            stampAnchors(content, shownWindows: shownWindows, now: now), now: now))
    }

    /// R9 (P57): `FreshnessStamp`'s aggregation over the phone's model. A live account's live
    /// windows anchor "Updated" at their own observation time (the account's capture time when
    /// a window carries none); a row hidden past its reset is not a reading on screen. Every
    /// other row only answers "when was this last checked".
    public static func stampAnchors(
        _ content: CompanionResolvedContent,
        shownWindows: (CompanionResolvedAccount) -> [WidgetWindowSummary],
        now: Date
    ) -> FreshnessStamp.Anchors {
        var anchors = FreshnessStamp.Anchors()
        // Default-login R12: a remembered row is not a reading the Mac keeps current, so it
        // neither anchors "Updated" nor answers "when was this last checked".
        for account in content.providers.flatMap(\.accounts) where !account.isRemembered {
            for window in shownWindows(account) {
                guard let observed = window.observedAt ?? account.capturedAt else { continue }
                anchors.newestCheck = anchors.newestCheck.map { max($0, observed) } ?? observed
                guard account.freshness == .live, window.freshness.isLive,
                    CompanionFreshnessRule.pastResetTime(window, at: now) == nil
                else { continue }
                anchors.oldestLive = anchors.oldestLive.map { min($0, observed) } ?? observed
            }
        }
        return anchors
    }

    /// "Updated 2 min ago", "Updated just now"; the stamp's other kinds read as they are.
    public static func subtitle(for stamp: FreshnessStamp) -> String {
        guard stamp.kind == .updated else { return stamp.text }
        return "Updated \(stamp.text.prefix(1).lowercased() + stamp.text.dropFirst())"
    }
}

extension CompanionCardPresentation {
    /// R3 + R11: the rows in reading order, each past-reset window taken through the
    /// unavailable path with its reset time.
    /// A remembered row (default-login R8) hides each window at its reset with no grace,
    /// and keeps the reset time on a window the Mac already sent as unavailable, so every
    /// reset window says when it reset.
    public static func meterRows(
        _ windows: [CompanionResolvedWindow], now: Date, isRemembered: Bool = false
    ) -> [CompanionMeterRow] {
        rows(windows).map { window in
            guard window.hasDisplayValue || isRemembered,
                let resetAt = CompanionFreshnessRule.pastResetTime(window, at: now, isRemembered: isRemembered)
            else {
                return CompanionMeterRow(window: window, pastResetAt: nil)
            }
            let hidden = window.hasDisplayValue ? window.madeUnavailable(since: resetAt) : window
            return CompanionMeterRow(window: hidden, pastResetAt: resetAt)
        }
    }

    /// KTD15: whole-surface dimming and an account's own stale treatment are one secondary-ink
    /// demotion. A row is dimmed or it isn't; nothing multiplies a second time.
    public static func rowsDimmed(accountDimmed: Bool, surfaceDimmed: Bool) -> Bool {
        accountDimmed || surfaceDimmed
    }

    /// AE6: "Reset at 2:00 PM · waiting for your Mac".
    public static func pastResetLine(
        _ resetAt: Date, now: Date, timeZone: TimeZone = .current, locale: Locale = .current
    ) -> String {
        CompanionFreshnessCopy.pastReset(
            at: WidgetClockText.text(for: resetAt, now: now, timeZone: timeZone, locale: locale))
    }

    /// Default-login R8, R21: a remembered row is never read again, so it says the window
    /// reset and has not been read since, in the Mac's words, instead of waiting for the Mac.
    public static func pastResetLine(
        _ resetAt: Date, now: Date, isRemembered: Bool, timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        isRemembered
            ? Countdown.resetNotReadLine(resetAt: resetAt, now: now, timeZone: timeZone, locale: locale)
            : pastResetLine(resetAt, now: now, timeZone: timeZone, locale: locale)
    }
}

extension CompanionCardPresentation {
    /// R14/AE1: only a lineage-less v3 (an older Mac) says what updating adds. A current
    /// Mac's v3 mirror read without its manifest carries no notice, so it never asks an
    /// up-to-date Mac to update (KTD6.5).
    public static func compatibilityLine(_ content: CompanionResolvedContent) -> String? {
        content.notice == .updateMac ? CompanionCompatibilityNotice.updateMac.message : nil
    }
}
