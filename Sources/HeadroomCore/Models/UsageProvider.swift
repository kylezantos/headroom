import Foundation

/// The single seam the polling engine depends on (R13). Concrete providers
/// (Claude, Codex, and any third later) implement this; the engine and shell
/// never reference a concrete provider.
///
/// `fetchSnapshot()` returns a stale/failed snapshot rather than throwing, so one
/// provider's failure can never abort the cycle or hide another provider (KTD7).
/// `Sendable` because the engine fetches providers concurrently (KTD10).
public enum ProviderPollingLane: Sendable, Equatable, Hashable {
    case concurrent
    case serial(String)
}

/// Machine/provider capability is independent from any configured account's login,
/// workspace trust, or usage result. Only `confirmedAbsent` proves installation is
/// missing; discovery failures remain retryable and inconclusive.
public enum ProviderCapabilityState: Sendable, Equatable {
    case unknown
    case discovering
    case available
    case inconclusive(CLIExecutableDiscoveryIssue)
    case confirmedAbsent
}

public struct ProviderCapabilityStatus: Sendable, Equatable {
    public let state: ProviderCapabilityState
    public let observedAt: Date

    public init(state: ProviderCapabilityState, observedAt: Date) {
        self.state = state
        self.observedAt = observedAt
    }
}

/// Why a fetch result must not reach the store at all.
public enum UsageFetchDiscard: Sendable, Equatable {
    /// The identity reads around the usage read failed or disagreed, so the login was
    /// changing and the reading belongs to neither account for certain (KTD2).
    case identityUnreadable
}

public struct UsageProviderFetchResult: Sendable, Equatable {
    public let snapshot: UsageSnapshot
    public let capability: ProviderCapabilityState?
    /// Set when the store must refuse this result instead of merging it. A discard is not
    /// a failure: it moves no backoff, dims no row and never reaches a setup session,
    /// which would read a stale snapshot during a handoff as retry exhaustion.
    public let discard: UsageFetchDiscard?

    public init(
        snapshot: UsageSnapshot,
        capability: ProviderCapabilityState? = nil,
        discard: UsageFetchDiscard? = nil
    ) {
        self.snapshot = snapshot
        self.capability = capability
        self.discard = discard
    }

    /// A reading taken while the login was changing (KTD2). The snapshot is a placeholder
    /// for callers that only ask for a snapshot; the store never merges it.
    public static func identityUnreadable(
        for providerID: ProviderID,
        capability: ProviderCapabilityState? = nil
    ) -> UsageProviderFetchResult {
        UsageProviderFetchResult(
            snapshot: .stale(for: providerID, reason: identityUnconfirmedReason),
            capability: capability,
            discard: .identityUnreadable
        )
    }

    /// What a refused reading becomes once the refusal bound is reached: an ordinary
    /// transient failure, so a permanently unreadable identity file shows a stale row
    /// with normal backoff instead of retrying forever (KTD2).
    public static let identityUnconfirmedReason = FailureReason.transient("Couldn’t confirm the account. Headroom tries again on its next check.")

    var withoutDiscard: UsageProviderFetchResult {
        UsageProviderFetchResult(snapshot: snapshot, capability: capability)
    }
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Which configured account this instance fetches for. Defaults to `.primary` so
    /// single-account providers (and tests) don't have to know accounts exist.
    var accountID: AccountID { get }
    var displayName: String { get }
    /// Fixed at composition time so one refresh partitions providers exactly once.
    /// Process-heavy CLIs declare a keyed serial lane; network providers stay concurrent.
    var pollingLane: ProviderPollingLane { get }
    /// Maximum configured accounts this provider can isolate. Single-login providers
    /// override the registry-wide default with `1`.
    var accountCapacity: Int { get }
    var reportsProviderCapability: Bool { get }
    /// True when a probe outside `UserRequestedProbeContext` may answer from a cached
    /// status, so a user request arriving mid-probe needs its own follow-up probe.
    var reusesCachedStatusOnTimerProbes: Bool { get }
    func fetchSnapshot() async -> UsageSnapshot
    func fetchResult() async -> UsageProviderFetchResult
    /// Called synchronously when the store removes, stops tracking or resets this account,
    /// so a provider that coalesces in-flight reads (OpenCode, KTD8) never lets a later
    /// request join a read that began before the boundary. Most providers keep nothing.
    func invalidateInFlightUsage()
}

public extension UsageProvider {
    var accountID: AccountID { .primary }
    var accountKey: AccountKey { AccountKey(providerID: id, accountID: accountID) }
    var pollingLane: ProviderPollingLane { .concurrent }
    var accountCapacity: Int { AccountRegistry.testedEnvelope }
    var reportsProviderCapability: Bool { false }
    var reusesCachedStatusOnTimerProbes: Bool { false }
    func fetchResult() async -> UsageProviderFetchResult {
        UsageProviderFetchResult(snapshot: await fetchSnapshot())
    }
    func invalidateInFlightUsage() {}
}

/// Money-based API cost providers are intentionally separate from subscription quota
/// providers: a dollar total over a billing period is not a resettable usage window.
public protocol APISpendProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    /// The credential this provider's endpoints actually accept. Declared here so the
    /// row copy names the right thing per vendor ("an admin key" vs "a management key")
    /// instead of hard-coding one vendor's noun for all three.
    var credential: APISpendCredentialDescriptor { get }
    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot
}

public extension APISpendProvider {
    var credential: APISpendCredentialDescriptor { .forProvider(id) }
}
