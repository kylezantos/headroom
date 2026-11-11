import Foundation
import Testing
@testable import HeadroomCore

/// Default-login plan U1 and U2: the identity value, its readers, and the before-and-after
/// read every Codex and Grok fetch makes. Fixtures only; no test touches a real config home.
struct AccountIdentityTests {
    private let accountID = "6f1c2a34-5b6d-4e7f-8a90-b1c2d3e4f506"

    // MARK: Model (U1)

    /// KTD1: the canonical digest input is fixed. A change to it must come with a new
    /// `currentDigestVersion`, or every stored binding stops matching.
    @Test func goldenDigestsPinTheCanonicalInputPerProvider() {
        #expect(AccountIdentity.currentDigestVersion == 1)
        #expect(AccountIdentity.codex(accountID: accountID)?.digest
            == "d4e55d6154381be06a4c5e458111308e675a37a1a82c35662e68aa7f44ac68c2")
        #expect(AccountIdentity.grok(email: "work@example.com")?.digest
            == "ac96731af188e4101d81e6a2856a4d2a715d8feef69bdcef8140da78736dac6f")
        #expect(AccountIdentity.cursor(email: "work@example.com")?.digest
            == "f216692e06878976abbc04917870243fb4d4da671bf95d7e95b9aa384ff03cde")
        #expect(AccountIdentity.copilot(login: "octo-user")?.digest
            == "5af2d8cdd7b420d76e14e8d910be37b267ff6046fef2350495aa24f97a75ae00")
    }

    @Test func caseAndSurroundingWhitespaceDoNotChangeTheDigest() {
        #expect(AccountIdentity.codex(accountID: "  \(accountID.uppercased())\n")
            == AccountIdentity.codex(accountID: accountID))
        #expect(AccountIdentity.grok(email: " Work@Example.COM ") == AccountIdentity.grok(email: "work@example.com"))
    }

    @Test func strengthFollowsWhatTheClientExposes() {
        #expect(AccountIdentity.codex(accountID: accountID)?.strength == .strong)
        #expect(AccountIdentity.grok(email: "a@example.com")?.strength == .weak)
        #expect(AccountIdentity.cursor(email: "a@example.com")?.strength == .weak)
        #expect(AccountIdentity.copilot(login: "octo")?.strength == .weak)
    }

    @Test func aMissingOrEmptyValueYieldsNoIdentity() {
        #expect(AccountIdentity.codex(accountID: nil) == nil)
        #expect(AccountIdentity.codex(accountID: "   ") == nil)
        #expect(AccountIdentity.grok(email: nil) == nil)
    }

    @Test func theSameValueUnderTwoProvidersIsTwoIdentities() {
        #expect(AccountIdentity.grok(email: "a@example.com") != AccountIdentity.cursor(email: "a@example.com"))
    }

    @Test func theDigestNeverContainsTheRawIdOrEmail() throws {
        let codex = try #require(AccountIdentity.codex(accountID: accountID))
        let grok = try #require(AccountIdentity.grok(email: "work@example.com"))
        let encoded = String(decoding: try JSONEncoder().encode([codex, grok]), as: UTF8.self)
        #expect(!encoded.contains(accountID))
        #expect(!encoded.contains("work@example.com"))
        #expect(!encoded.contains("6f1c2a34"))
    }

    @Test func bracketingAgreesOnlyWhenBothReadsNameOneAccount() throws {
        let a = try #require(AccountIdentity.codex(accountID: "a"))
        let b = try #require(AccountIdentity.codex(accountID: "b"))
        #expect(AccountIdentityOutcome.bracketing(before: .identity(a, email: nil), after: .identity(a, email: nil)) == .known(a))
        #expect(AccountIdentityOutcome.bracketing(before: .identity(a, email: nil), after: .identity(b, email: nil)) == .unreadable)
        #expect(AccountIdentityOutcome.bracketing(before: .absent, after: .absent) == .absent)
        #expect(AccountIdentityOutcome.bracketing(before: .identity(a, email: nil), after: .absent) == .unreadable)
        #expect(AccountIdentityOutcome.bracketing(before: .absent, after: .identity(a, email: nil)) == .unreadable)
        #expect(AccountIdentityOutcome.bracketing(before: .unreadable, after: .identity(a, email: nil)) == .unreadable)
    }

    // MARK: Readers (U1)

    @Test func codexSessionCarriesTheAccountIdAsAStrongIdentity() async {
        let withID = CredentialStore(codexReader: MockCodexReader(credential: CodexCredential(
            accessToken: "at", refreshToken: nil, accountID: accountID, lastRefresh: nil
        )))
        let without = CredentialStore(codexReader: MockCodexReader(credential: CodexCredential(
            accessToken: "at", refreshToken: nil, accountID: nil, lastRefresh: nil
        )))
        let named = try? await withID.codexSession().get()
        let unnamed = try? await without.codexSession().get()
        #expect(named?.identity == AccountIdentity.codex(accountID: accountID))
        #expect(named?.identity != nil)
        #expect(unnamed != nil)
        #expect(unnamed?.identity == nil)
    }

    @Test func grokReaderTellsAMissingFileFromAnUndecodableOne() {
        func read(_ result: Result<GrokCredential, CredentialError>) -> AccountIdentityRead {
            GrokCredentialEmailReader(authReader: ResultGrokAuthReader(result: result)).readAccountIdentity()
        }
        let email = "Work@Example.com"
        #expect(read(.success(GrokCredential(accessToken: "t", userID: "u", email: email)))
            == .identity(AccountIdentity.grok(email: "work@example.com")!, email: "work@example.com"))
        #expect(read(.success(GrokCredential(accessToken: "t", userID: "u", email: nil))) == .absent)
        #expect(read(.failure(.notLoggedIn)) == .absent)
        #expect(read(.failure(.malformed)) == .unreadable)
        #expect(read(.failure(.ioFailure)) == .unreadable)
        #expect(read(.failure(.permissionDenied)) == .unreadable)
    }

    // MARK: Codex fetch (U2)

    private static let codexBody = """
    { "rate_limit": { "primary_window": {"used_percent": 30, "limit_window_seconds": 18000, "reset_at": 1783023708} },
      "plan_type": "pro" }
    """

    private func codexProvider(
        _ reader: ScriptedCodexReader,
        responses: [Result<HTTPResult, FailureReason>]? = nil
    ) -> CodexProvider {
        CodexProvider(
            credentials: CredentialStore(codexReader: reader),
            http: MockFetcher(responses ?? [.success(HTTPResult(status: 200, body: Data(Self.codexBody.utf8)))]),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    @Test func codexReadingIsKnownWhenBothReadsNameOneAccount() async {
        let result = await codexProvider(ScriptedCodexReader([.account("a"), .account("a")])).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.freshness == .live)
        #expect(result.snapshot.identity == .known(AccountIdentity.codex(accountID: "a")!))
        // The email shown comes from the same read as the identity.
        #expect(result.snapshot.accountEmail == "a@example.invalid")
    }

    /// Covers AE6: the login changed while the request was in flight.
    @Test func codexReadingTakenAcrossALoginChangeIsRefused() async {
        let result = await codexProvider(ScriptedCodexReader([.account("a"), .account("b")])).fetchResult()
        #expect(result.discard == .identityUnreadable)
        #expect(result.snapshot.freshness != .live)
        #expect(result.snapshot.windows.isEmpty)
    }

    @Test func codexReadingWithNoAccountIdOnEitherSideIsAbsentAndAccepted() async {
        let result = await codexProvider(ScriptedCodexReader([.noAccount, .noAccount])).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.freshness == .live)
        #expect(result.snapshot.identity == .absent)
    }

    @Test func codexReadingWhoseFileIsUnreadableAfterwardsIsRefused() async {
        for failure in [CredentialError.malformed, .ioFailure, .notLoggedIn] {
            let result = await codexProvider(ScriptedCodexReader([.account("a"), .failure(failure)])).fetchResult()
            #expect(result.discard == .identityUnreadable)
        }
    }

    @Test func codex401ReloadOntoADifferentAccountIsRefused() async {
        let reader = ScriptedCodexReader([.account("a", token: "old"), .account("b", token: "new"), .account("b", token: "new")])
        let result = await codexProvider(reader, responses: [
            .success(HTTPResult(status: 401, body: Data())),
            .success(HTTPResult(status: 200, body: Data(Self.codexBody.utf8))),
        ]).fetchResult()
        #expect(result.discard == .identityUnreadable)
    }

    @Test func codex401ReloadOfTheSameAccountKeepsTheReading() async {
        let reader = ScriptedCodexReader([.account("a", token: "old"), .account("a", token: "new"), .account("a", token: "new")])
        let result = await codexProvider(reader, responses: [
            .success(HTTPResult(status: 401, body: Data())),
            .success(HTTPResult(status: 200, body: Data(Self.codexBody.utf8))),
        ]).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.identity == .known(AccountIdentity.codex(accountID: "a")!))
    }

    @Test func codexFailureCarriesNoIdentityAndReadsTheFileOnce() async {
        let reader = ScriptedCodexReader([.account("a"), .account("b")])
        let result = await codexProvider(reader, responses: [.failure(.transient("offline"))]).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.identity == nil)
        #expect(reader.readCount == 1)
    }

    // MARK: Grok fetch (U2)

    private static let grokBody = Data("""
    {"config":{"creditUsagePercent":12,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-01T00:00:00Z","end":"2026-07-08T00:00:00Z"}}}
    """.utf8)

    private func grokProvider(_ reads: [AccountIdentityRead]?) -> GrokProvider {
        GrokProvider(
            source: MockGrokSource(result: .payload(Self.grokBody, transport: .http)),
            emailSource: reads.map(ScriptedGrokIdentity.init),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func grokRead(_ email: String) -> AccountIdentityRead {
        .identity(AccountIdentity.grok(email: email)!, email: email)
    }

    @Test func grokReadingIsKnownAndTakesItsEmailFromTheSameReadPair() async {
        let result = await grokProvider([grokRead("a@example.com"), grokRead("a@example.com")]).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.identity == .known(AccountIdentity.grok(email: "a@example.com")!))
        #expect(result.snapshot.accountEmail == "a@example.com")
    }

    @Test func grokReadingTakenAcrossALoginChangeIsRefused() async {
        let result = await grokProvider([grokRead("a@example.com"), grokRead("b@example.com")]).fetchResult()
        #expect(result.discard == .identityUnreadable)
    }

    @Test func grokUnreadableFileOnOneSideIsRefusedAndAMissingOneIsAbsent() async {
        #expect(await grokProvider([.unreadable, grokRead("a@example.com")]).fetchResult().discard == .identityUnreadable)
        #expect(await grokProvider([grokRead("a@example.com"), .unreadable]).fetchResult().discard == .identityUnreadable)
        let absent = await grokProvider([.absent, .absent]).fetchResult()
        #expect(absent.discard == nil)
        #expect(absent.snapshot.identity == .absent)
        #expect(absent.snapshot.freshness == .live)
    }

    @Test func grokWithNoReaderReportsNoIdentity() async {
        let result = await grokProvider(nil).fetchResult()
        #expect(result.discard == nil)
        #expect(result.snapshot.identity == nil)
        #expect(result.snapshot.freshness == .live)
    }
}

private struct ResultGrokAuthReader: GrokAuthReading {
    let result: Result<GrokCredential, CredentialError>
    func readGrokCredential() throws -> GrokCredential { try result.get() }
}

/// Returns its reads in order, repeating the last one.
private final class ScriptedGrokIdentity: GrokAccountEmailReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [AccountIdentityRead]

    init(_ reads: [AccountIdentityRead]) { self.reads = reads }

    func readAccountEmail() -> String? { readAccountIdentity().email }

    func readAccountIdentity() -> AccountIdentityRead {
        lock.withLock { reads.count > 1 ? reads.removeFirst() : reads[0] }
    }
}

/// Returns one scripted `auth.json` read per call, repeating the last one.
final class ScriptedCodexReader: CodexAuthReading, @unchecked Sendable {
    enum Read {
        case account(String, token: String = "at")
        case noAccount
        case failure(CredentialError)
    }

    private let lock = NSLock()
    private var reads: [Read]
    private var count = 0

    init(_ reads: [Read]) { self.reads = reads }

    var readCount: Int { lock.withLock { count } }

    func set(_ reads: [Read]) { lock.withLock { self.reads = reads } }

    func readCodexCredential() throws -> CodexCredential {
        let read = lock.withLock { () -> Read in
            count += 1
            return reads.count > 1 ? reads.removeFirst() : reads[0]
        }
        switch read {
        case .account(let id, let token):
            return CodexCredential(
                accessToken: token, refreshToken: nil, accountID: id, lastRefresh: nil,
                email: "\(id)@example.invalid"
            )
        case .noAccount:
            return CodexCredential(accessToken: "at", refreshToken: nil, accountID: nil, lastRefresh: nil)
        case .failure(let error):
            throw error
        }
    }
}
