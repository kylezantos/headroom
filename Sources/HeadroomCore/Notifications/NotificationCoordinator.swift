import Foundation

/// What the store knows at merge time that the evaluators need: display names and the
/// user's switches. Captured as a value so a post's completion reads what was decided.
public struct NotificationEvaluationContext: Sendable, Equatable {
    public var providerName: String
    /// Nil unless the provider shows more than one account (R13, R16).
    public var accountLabel: String?
    public var useItUp: UseItUpSettings
    public var bankedResetsEnabled: Bool

    public init(providerName: String, accountLabel: String?, useItUp: UseItUpSettings, bankedResetsEnabled: Bool) {
        self.providerName = providerName
        self.accountLabel = accountLabel
        self.useItUp = useItUp
        self.bankedResetsEnabled = bankedResetsEnabled
    }
}

/// KTD1: runs both evaluators on each fresh live merge and posts through the injected
/// seam. KTD6: a ledger is written only after the poster accepts, and only while the
/// account is still attached; an in-flight marker stops a second merge from posting the
/// same limit (or the same account's banked notice) before the first post returns.
@MainActor
public final class NotificationCoordinator {
    private struct LimitKey: Hashable {
        let account: AccountKey
        let windowID: String
    }

    private let poster: any NotificationPosting
    private let useItUpLedger: UseItUpLedger
    private let bankedResetBaseline: BankedResetNotificationBaseline
    private var limitsInFlight: Set<LimitKey> = []
    private var bankedInFlight: Set<AccountKey> = []
    private var pendingPosts: [UUID: Task<Void, Never>] = [:]

    public init(
        poster: any NotificationPosting,
        useItUpLedger: UseItUpLedger = UseItUpLedger(),
        bankedResetBaseline: BankedResetNotificationBaseline = BankedResetNotificationBaseline()
    ) {
        self.poster = poster
        self.useItUpLedger = useItUpLedger
        self.bankedResetBaseline = bankedResetBaseline
    }

    /// KTD2: the store calls this only for a fresh live merge. `isStillAttached` is read
    /// when a post returns, so a removal or reset that raced it leaves no ledger behind.
    public func receive(
        _ snapshot: UsageSnapshot,
        for account: AccountKey,
        context: NotificationEvaluationContext,
        now: Date,
        isStillAttached: @escaping @MainActor () -> Bool
    ) {
        evaluateUseItUp(snapshot, for: account, context: context, now: now, isStillAttached: isStillAttached)
        evaluateBankedReset(snapshot, for: account, context: context, isStillAttached: isStillAttached)
    }

    /// Account removal and Sign Out & Set Up Again, beside the acknowledgement purge (KTD7).
    public func purge(for account: AccountKey) {
        useItUpLedger.purge(for: account)
        bankedResetBaseline.purge(for: account)
    }

    /// Awaits every post started so far and its ledger write. Tests use it to settle.
    public func waitForPendingPosts() async {
        while let post = pendingPosts.values.first {
            await post.value
        }
    }

    private func evaluateUseItUp(
        _ snapshot: UsageSnapshot,
        for account: AccountKey,
        context: NotificationEvaluationContext,
        now: Date,
        isStillAttached: @escaping @MainActor () -> Bool
    ) {
        guard context.useItUp.isEnabled, !context.useItUp.rules.isEmpty else { return }
        let proposals = UseItUpEvaluator.evaluate(
            snapshot: snapshot,
            account: account,
            settings: context.useItUp,
            ledger: useItUpLedger.entries(),
            now: now
        )
        let activeFiringKeys = Set(context.useItUp.rules.map(\.firingKey))
        for proposal in proposals {
            let limit = LimitKey(account: account, windowID: proposal.windowID)
            guard !limitsInFlight.contains(limit) else { continue }
            limitsInFlight.insert(limit)
            let content = NotificationContent.useItUp(
                proposal,
                providerName: context.providerName,
                accountLabel: context.accountLabel,
                now: now
            )
            post(content) { [useItUpLedger] accepted in
                self.limitsInFlight.remove(limit)
                guard accepted, isStillAttached() else { return }
                useItUpLedger.record(proposal.ledgerEntry, activeFiringKeys: activeFiringKeys, now: now)
            }
        }
    }

    private func evaluateBankedReset(
        _ snapshot: UsageSnapshot,
        for account: AccountKey,
        context: NotificationEvaluationContext,
        isStillAttached: @escaping @MainActor () -> Bool
    ) {
        // The in-flight post decides this account's next baseline; every fresh poll
        // re-decides, so skipping here loses nothing.
        guard !bankedInFlight.contains(account) else { return }
        switch bankedResetBaseline.decide(snapshot: snapshot, account: account, isEnabled: context.bankedResetsEnabled) {
        case .ignore:
            return
        case .record(let count):
            bankedResetBaseline.record(count: count, for: account)
        case .notify(let proposal):
            bankedInFlight.insert(account)
            let content = NotificationContent.bankedReset(proposal, accountLabel: context.accountLabel)
            post(content) { [bankedResetBaseline] accepted in
                self.bankedInFlight.remove(account)
                guard accepted, isStillAttached() else { return }
                bankedResetBaseline.record(count: proposal.count, for: account)
            }
        }
    }

    private func post(_ content: NotificationContent, completion: @escaping @MainActor (Bool) -> Void) {
        let poster = poster
        let id = UUID()
        // Main-actor isolated, so the body cannot run before this assignment lands.
        pendingPosts[id] = Task { @MainActor in
            completion(await poster.post(content))
            self.pendingPosts[id] = nil
        }
    }
}
