import Foundation
@testable import HeadroomCore

/// Codex reader double.
struct MockCodexReader: CodexAuthReading {
    var credential: CodexCredential?
    func readCodexCredential() throws -> CodexCredential {
        guard let credential else { throw CredentialError.notLoggedIn }
        return credential
    }
}

/// HTTP double for the Codex provider. Returns a queued response and captures the last
/// request's headers.
final class MockFetcher: UsageFetching, @unchecked Sendable {
    var responses: [Result<HTTPResult, FailureReason>]
    private let lock = NSLock()
    private var index = 0
    private(set) var lastHeaders: [String: String] = [:]
    private(set) var lastURL: URL?
    private(set) var requestedURLs: [URL] = []
    private(set) var requestCount = 0

    init(_ responses: [Result<HTTPResult, FailureReason>]) { self.responses = responses }
    convenience init(status: Int, body: String) {
        self.init([.success(HTTPResult(status: status, body: Data(body.utf8)))])
    }

    func get(url: URL, headers: [String: String]) async -> Result<HTTPResult, FailureReason> {
        lock.withLock {
            lastHeaders = headers
            lastURL = url
            requestedURLs.append(url)
            requestCount += 1
            let r = responses[min(index, responses.count - 1)]
            index += 1
            return r
        }
    }
}

/// In-memory API key store double.
final class MockAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [APIKeyProvider: String]
    var shouldFail = false

    init(keys: [APIKeyProvider: String] = [:]) {
        self.keys = keys
    }

    func readAPIKey(for provider: APIKeyProvider) throws -> String {
        try lock.withLock {
            if shouldFail { throw CredentialError.keychainStatus(-1) }
            guard let key = keys[provider] else { throw CredentialError.notLoggedIn }
            return key
        }
    }

    func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        try lock.withLock {
            if shouldFail { throw CredentialError.keychainStatus(-1) }
            keys[provider] = key
        }
    }

    func deleteAPIKey(for provider: APIKeyProvider) throws {
        try lock.withLock {
            if shouldFail { throw CredentialError.keychainStatus(-1) }
            keys.removeValue(forKey: provider)
        }
    }
}

/// Claude usage-source double — returns a fixed panel/result so the provider is tested
/// without spawning the real CLI.
struct MockClaudeSource: ClaudeUsageSource {
    let result: ClaudePanelResult
    func capturePanel() async -> ClaudePanelResult { result }
}

struct MockGrokSource: GrokUsageSource {
    let result: GrokUsageSourceResult
    func fetchUsage() async -> GrokUsageSourceResult { result }
}

final class CountingGrokSource: GrokUsageSource, @unchecked Sendable {
    private let lock = NSLock()
    private let result: GrokUsageSourceResult
    private var _fetchCount = 0
    var fetchCount: Int { lock.withLock { _fetchCount } }

    init(_ result: GrokUsageSourceResult) { self.result = result }

    func fetchUsage() async -> GrokUsageSourceResult {
        lock.withLock { _fetchCount += 1 }
        return result
    }
}

/// Provider double for engine tests.
struct StubProvider: UsageProvider {
    let id: ProviderID
    let displayName: String
    let snapshot: UsageSnapshot
    func fetchSnapshot() async -> UsageSnapshot { snapshot }
}

struct CapabilityStubProvider: UsageProvider {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    let result: UsageProviderFetchResult
    let reportsProviderCapability = true
    let pollingLane: ProviderPollingLane = .serial("claude-cli")

    func fetchSnapshot() async -> UsageSnapshot { result.snapshot }
    func fetchResult() async -> UsageProviderFetchResult { result }
}

final class MutableCapabilityStubProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    let reportsProviderCapability = true
    let pollingLane: ProviderPollingLane = .serial("claude-cli")
    private let lock = NSLock()
    private var result: UsageProviderFetchResult

    init(
        id: ProviderID,
        accountID: AccountID = .primary,
        displayName: String,
        result: UsageProviderFetchResult
    ) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.result = result
    }

    func setResult(_ result: UsageProviderFetchResult) {
        lock.withLock { self.result = result }
    }

    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { result.snapshot } }
    func fetchResult() async -> UsageProviderFetchResult { lock.withLock { result } }
}

/// Provider double whose returned snapshot can change between refreshes.
final class MutableStubProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    private let lock = NSLock()
    private var _snapshot: UsageSnapshot
    init(id: ProviderID, displayName: String, snapshot: UsageSnapshot) {
        self.id = id
        self.displayName = displayName
        self._snapshot = snapshot
    }
    func set(_ s: UsageSnapshot) { lock.withLock { _snapshot = s } }
    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { _snapshot } }
}

final class MutableDateSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.withLock { value }
    }

    func set(_ value: Date) {
        lock.withLock { self.value = value }
    }
}

/// Provider double that counts how many times it was fetched.
final class CountingProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    private let lock = NSLock()
    private var _count = 0
    var fetchCount: Int { lock.withLock { _count } }
    init(id: ProviderID, displayName: String = "P") { self.id = id; self.displayName = displayName }
    func fetchSnapshot() async -> UsageSnapshot {
        lock.withLock { _count += 1 }
        return .live(id, windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: Date(timeIntervalSince1970: 3_000_000))])
    }
}

/// Provider double that blocks a fetch until the test releases it.
final class SlowCountingProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    let pollingLane: ProviderPollingLane
    private let lock = NSLock()
    private var _count = 0
    private var didStart = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var shouldRelease = false
    var fetchCount: Int { lock.withLock { _count } }

    init(
        id: ProviderID,
        accountID: AccountID = .primary,
        displayName: String = "P",
        pollingLane: ProviderPollingLane = .concurrent
    ) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.pollingLane = pollingLane
    }

    func waitUntilFetchStarts() async {
        let alreadyStarted = lock.withLock { didStart }
        if alreadyStarted { return }
        await withCheckedContinuation { continuation in
            var resumeImmediately = false
            lock.withLock {
                if didStart {
                    resumeImmediately = true
                } else {
                    startContinuation = continuation
                }
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    func releaseFetch() {
        let continuation = lock.withLock {
            shouldRelease = true
            let continuation = releaseContinuation
            releaseContinuation = nil
            return continuation
        }
        continuation?.resume()
    }

    func fetchSnapshot() async -> UsageSnapshot {
        let start = lock.withLock {
            _count += 1
            didStart = true
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        start?.resume()

        let released = lock.withLock { shouldRelease }
        if !released {
            await withCheckedContinuation { continuation in
                var resumeImmediately = false
                lock.withLock {
                    if shouldRelease {
                        resumeImmediately = true
                    } else {
                        releaseContinuation = continuation
                    }
                }
                if resumeImmediately { continuation.resume() }
            }
        }

        return .live(id, windows: [
            UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: Date(timeIntervalSince1970: 3_000_000)),
        ])
    }
}

/// Widget exporter double for store tests.
final class SpyWidgetExporter: WidgetSnapshotExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _exports: [WidgetSnapshotEnvelope] = []
    var exports: [WidgetSnapshotEnvelope] { lock.withLock { _exports } }

    func export(_ envelope: WidgetSnapshotEnvelope) {
        lock.withLock { _exports.append(envelope) }
    }
}

final class FailingWidgetExporter: WidgetSnapshotExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _exportCount = 0
    var exportCount: Int { lock.withLock { _exportCount } }

    func export(_ envelope: WidgetSnapshotEnvelope) {
        lock.withLock { _exportCount += 1 }
    }
}

/// API spend provider double that counts how many times it was fetched.
final class CountingSpendProvider: APISpendProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    private let lock = NSLock()
    private var _count = 0
    let snapshot: APISpendSnapshot
    var fetchCount: Int { lock.withLock { _count } }

    init(id: ProviderID, displayName: String = "API", snapshot: APISpendSnapshot? = nil) {
        self.id = id
        self.displayName = displayName
        self.snapshot = snapshot ?? APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: 1,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            freshness: .live
        )
    }

    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        lock.withLock { _count += 1 }
        return snapshot
    }
}

extension UsageSnapshot {
    static func live(_ id: ProviderID, windows: [UsageWindow], plan: String? = nil, at: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(providerID: id, windows: windows, planLabel: plan, capturedAt: at, freshness: .live)
    }
}

/// One-shot suspend gate for provider doubles: `suspendNextFetch()` holds the next fetch
/// open until `release()`, and `waitUntilStarted()` lets a test observe that fetch begin.
/// Providers call `enter()` at the top of each fetch. One waiter at a time: a second
/// concurrent `waitUntilStarted()` would replace the first.
final class FetchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var suspendNext = false
    private var didStart = false
    private var started: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var shouldRelease = false

    func suspendNextFetch() {
        lock.withLock { suspendNext = true; shouldRelease = false; didStart = false }
    }

    func waitUntilStarted() async {
        if lock.withLock({ didStart }) { return }
        await withCheckedContinuation { continuation in
            var resumeNow = false
            lock.withLock { if didStart { resumeNow = true } else { started = continuation } }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            shouldRelease = true
            let pending = releaseContinuation
            releaseContinuation = nil
            return pending
        }
        pending?.resume()
    }

    func enter() async {
        let (suspend, started) = lock.withLock { () -> (Bool, CheckedContinuation<Void, Never>?) in
            didStart = true
            let pending = self.started
            self.started = nil
            let suspend = suspendNext
            suspendNext = false
            return (suspend, pending)
        }
        started?.resume()
        guard suspend, !lock.withLock({ shouldRelease }) else { return }
        await withCheckedContinuation { continuation in
            var resumeNow = false
            lock.withLock { if shouldRelease { resumeNow = true } else { releaseContinuation = continuation } }
            if resumeNow { continuation.resume() }
        }
    }
}

/// Notification poster double (KTD1): records every request and answers with `accepts`.
/// `gate.suspendNextFetch()` holds the next post open until `gate.release()`, so a test
/// can merge again or remove the account while that post is in flight (KTD6).
final class RecordingNotificationPoster: NotificationPosting, @unchecked Sendable {
    let gate = FetchGate()
    private let lock = NSLock()
    private var _posted: [NotificationContent] = []
    private var _accepts: Bool

    init(accepts: Bool = true) { _accepts = accepts }

    var posted: [NotificationContent] { lock.withLock { _posted } }

    func setAccepts(_ accepts: Bool) { lock.withLock { _accepts = accepts } }

    func post(_ content: NotificationContent) async -> Bool {
        lock.withLock { _posted.append(content) }
        await gate.enter()
        return lock.withLock { _accepts }
    }
}
