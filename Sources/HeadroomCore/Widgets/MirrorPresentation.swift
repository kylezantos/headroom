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
    /// `UsageSnapshot.fiveHourFirst()` rank, stable within a rank. KTD11/KTD13: Spark rows
    /// arrive flagged and are shown only when the resolved display choice allows them.
    public static func rows(for account: CompanionResolvedAccount, showsSparkRows: Bool) -> [WidgetWindowSummary] {
        account.windows
            .filter { !$0.isSpark || showsSparkRows }
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
        if case .stale(_, needsAttention: false) = account.freshness { return !account.windows.isEmpty }
        return false
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
