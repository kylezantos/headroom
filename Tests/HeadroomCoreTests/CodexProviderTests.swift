import Testing
import Foundation
@testable import HeadroomCore

/// U5 test scenarios: Codex decode, unknown plan_type (#709 guard), additional
/// rate limits → `.other`, missing token, 401→reauth, network error.
struct CodexProviderTests {
    private func provider(_ fetcher: MockFetcher, credential: CodexCredential? = CodexCredential(accessToken: "at", refreshToken: "rt", accountID: "acc", lastRefresh: nil)) -> CodexProvider {
        let store = CredentialStore(codexReader: MockCodexReader(credential: credential))
        return CodexProvider(credentials: store, http: fetcher,
                             now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    private func fixture(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // Shape mirrors a real chatgpt.com/backend-api/wham/usage capture: each window carries
    // `limit_window_seconds` (18000 = 5h, 604800 = 7d) and `reset_at` as an epoch number.
    @Test func decodesLiveResponse() async {
        let json = """
        { "rate_limit": {
            "primary_window": {"used_percent": 30, "limit_window_seconds": 18000, "reset_at": 1783023708},
            "secondary_window": {"used_percent": 55, "limit_window_seconds": 604800, "reset_at": "2026-07-08T00:00:00Z"} },
          "plan_type": "pro" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "pro")
        #expect(snap.windows.first { $0.kind == .fiveHour }?.percentRemaining == 70)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 45)
    }

    // Regression (#codex-window-kind): the "prolite" plan returns its weekly window in
    // `primary_window` with `secondary_window: null`. Keying off the slot mislabeled it
    // "5-hour" and dropped the weekly row; keying off `limit_window_seconds` fixes it.
    @Test func realProliteCaptureLabelsPrimaryWindowAsWeekly() async throws {
        let body = try fixture(named: "codex-wham-usage-prolite")
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 200, body: body))])).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "prolite")
        #expect(snap.windows.count == 2)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 67)
        #expect(!snap.windows.contains { $0.kind == .fiveHour })
        #expect(snap.windows.contains { $0.kind == .other("GPT-5.3-Codex-Spark Weekly") })
        #expect(!snap.windows.contains { $0.kind == .other("GPT-5.3-Codex-Spark 5h") })
    }

    @Test func realProliteCaptureContainsOnlyRedactedIdentity() throws {
        let body = try fixture(named: "codex-wham-usage-prolite")
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["user_id"] as? String == "<REDACTED_USER_ID>")
        #expect(json["account_id"] as? String == "<REDACTED_ACCOUNT_ID>")
        #expect(json["email"] as? String == "redacted@example.invalid")
    }

    @Test func unknownDeclaredDurationIsNotForcedIntoKnownKind() {
        #expect(CodexWindowClassifier.kind(limitWindowSeconds: 21_600, positionalDefault: .fiveHour) == .other("6h"))
        #expect(CodexWindowClassifier.kind(limitWindowSeconds: 691_200, positionalDefault: .weekly) == .other("8d"))
    }

    @Test func unknownPlanTypeDecodesLeniently() async {
        // A new plan_type value (the CodexBar #709 break) passes through as a string
        // and does not fail the snapshot.
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 5, "reset_at": "2026-07-02T12:00:00Z"} },
          "plan_type": "prolite" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "prolite")
    }

    @Test func additionalRateLimitsSurfaceAsOther() async {
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 5, "reset_at": "2026-07-02T12:00:00Z"} },
          "additional_rate_limits": [ {"limit_name": "codex-spark", "rate_limit": {
              "primary_window": {"used_percent": 12, "reset_after_seconds": 3600},
              "secondary_window": {"used_percent": 22, "reset_at": 1783023708}
          }} ],
          "plan_type": "pro" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        // No `limit_window_seconds` here → positional fallback; suffix comes from
        // `WindowKind.shortLabel` ("5h"/"Weekly"), consistent with the main windows.
        #expect(snap.windows.contains { $0.kind == .other("codex-spark 5h") })
        #expect(snap.windows.contains { $0.kind == .other("codex-spark Weekly") })
    }

    @Test func legacyResetFieldNamesStillDecode() async {
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 5, "resets_at": "2026-07-02T12:00:00Z"} },
          "additional_rate_limits": [ {"label": "legacy", "utilization": 12, "resets_in_seconds": 3600} ] }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.windows.contains { $0.kind == .other("legacy") })
    }

    @Test func missingTokenIsNotLoggedIn() async {
        let snap = await provider(MockFetcher(status: 200, body: "{}"), credential: nil).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.isPermanent)
    }

    @Test func unauthorizedSaysRunCodex() async {
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 401, body: Data()))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .codexRejectedAuth)
    }

    @Test func networkErrorIsTransient() async {
        let snap = await provider(MockFetcher([.failure(.transient("Network unavailable"))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(!reason.isPermanent)
    }

    @Test func redirectsAreBlocked() {
        // R12: the session delegate (used by the Codex HTTP client) refuses redirects,
        // so the Authorization header can never be forwarded to another host.
        let blocker = RedirectBlocker()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://chatgpt.com")!)
        let response = HTTPURLResponse(url: URL(string: "https://chatgpt.com")!,
                                       statusCode: 302, httpVersion: nil, headerFields: nil)!
        var handed: URLRequest? = URLRequest(url: URL(string: "https://evil.example.com")!)
        blocker.urlSession(session, task: task, willPerformHTTPRedirection: response,
                           newRequest: URLRequest(url: URL(string: "https://evil.example.com")!)) { req in
            handed = req
        }
        #expect(handed == nil)
    }

    // MARK: - Banked resets (R1, R2, R3)

    @Test func proliteFixtureCarriesTwoBankedResetsWithoutChangingWindows() async throws {
        let body = try fixture(named: "codex-wham-usage-prolite")
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 200, body: body))])).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 2)
        #expect(snap.codexResetCreditsField == .count(2))
        #expect(snap.windows.count == 2)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 67)
        #expect(snap.codexBankedResetProbeLine == "banked resets: 2")
    }

    @Test func nullResetCreditsObjectIsReportedZero() async {
        let snap = await live(credits: "null")
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 0)
        #expect(snap.codexResetCreditsField == .nullObject)
        #expect(snap.codexBankedResetProbeLine == "banked resets: null (reported zero)")
    }

    @Test func omittedResetCreditsKeyIsNotReported() async {
        let snap = await live()
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.codexResetCreditsField == .absent)
        #expect(snap.codexBankedResetProbeLine == "banked resets: absent (field not present)")
    }

    @Test func fractionalAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "available_count": 2.5 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.windows.isEmpty == false)
    }

    @Test func missingAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "limit_name": "spare" }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
    }

    @Test func zeroAvailableCountIsReportedZero() async {
        let snap = await live(credits: #"{ "available_count": 0 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 0)
        #expect(snap.codexResetCreditsField == .count(0))
        #expect(snap.codexBankedResetProbeLine == "banked resets: 0")
    }

    @Test func overflowingAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "available_count": 1e100 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.codexResetCreditsField == .notReported)
    }

    @Test func negativeAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "available_count": -1 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
    }

    @Test func stringAvailableCountDecodesFlexibly() async {
        let snap = await live(credits: #"{ "available_count": "2" }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 2)
    }

    @Test func nonObjectResetCreditsDoesNotFailTheBody() async {
        let snap = await live(credits: "\"unexpected\"")
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.windows.contains { $0.kind == .fiveHour })
    }

    @Test func snapshotTransformsPreserveOrDropTheCount() {
        let live = UsageSnapshot(
            providerID: .codex,
            windows: [],
            planLabel: "plus",
            bankedResets: 2,
            capturedAt: Date(timeIntervalSince1970: 1),
            freshness: .live
        )
        let stale = live.markedStale(.transient("offline"))
        #expect(stale.bankedResets == 2)
        #expect(stale.freshness != .live)
        #expect(live.weeklyFirst().bankedResets == 2)
        #expect(UsageSnapshot.pending(for: .codex).bankedResets == nil)
        #expect(UsageSnapshot.stale(for: .codex, reason: .transient("x")).bankedResets == nil)
    }

    @Test func rejectedAuthCarriesNoCount() async {
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 401, body: Data()))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .codexRejectedAuth)
        #expect(snap.bankedResets == nil)
    }

    private func live(credits: String? = nil) async -> UsageSnapshot {
        let field = credits.map { ", \"rate_limit_reset_credits\": \($0)" } ?? ""
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 30, "limit_window_seconds": 18000, "reset_at": 1783023708} },
          "plan_type": "plus"\(field) }
        """
        return await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
    }
}
