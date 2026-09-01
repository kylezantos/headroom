import Foundation
import Testing
@testable import HeadroomCore

struct GrokProviderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func provider(_ result: GrokUsageSourceResult) -> GrokProvider {
        // No emailSource: pins that the default is inert (nil identity, no file reads) —
        // these tests must never touch a developer's real ~/.grok/auth.json.
        GrokProvider(source: MockGrokSource(result: result), now: { now })
    }

    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "grok-billing", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test func liveCaptureFixtureDecodesWeeklyZeroUsage() async throws {
        let snapshot = await provider(.payload(try fixture(), transport: .http)).fetchSnapshot()
        #expect(snapshot.freshness == .live)
        #expect(snapshot.providerID == .grok)
        #expect(snapshot.planLabel == nil)
        #expect(snapshot.windows.count == 1)
        let window = try #require(snapshot.windows.first)
        #expect(window.utilization == 0)
        #expect(window.percentRemaining == 100)
        #expect(window.resetSchedule == .scheduled(
            DateParsing.iso8601("2026-08-04T10:27:26.251601+00:00")!
        ))
        #expect(window.kind == .billingPeriod(label: "Weekly", duration: 7 * 24 * 60 * 60))
    }

    @Test func preferredPercentageAndTierWin() async {
        let body = Data("""
        {"config":{"creditUsagePercent":42.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY","start":"2026-07-01T00:00:00Z","end":"2026-08-01T00:00:00Z"},"monthlyLimit":{"val":10000},"used":{"val":9000}},"subscriptionTier":"SuperGrok"}
        """.utf8)
        let snapshot = await provider(.payload(body, transport: .stdio)).fetchSnapshot()
        #expect(snapshot.freshness == .live)
        #expect(snapshot.planLabel == "SuperGrok")
        #expect(snapshot.windows.first?.utilization == 42.5)
        #expect(snapshot.windows.first?.kind == .billingPeriod(label: "Monthly", duration: 31 * 24 * 60 * 60))
    }

    @Test func deprecatedCentFieldsRemainSupported() async {
        let body = Data("""
        {"config":{"monthlyLimit":{"val":"2000"},"used":{"val":500},"billingPeriodStart":"2026-07-01T00:00:00Z","billingPeriodEnd":"2026-08-01T00:00:00Z"}}
        """.utf8)
        let snapshot = await provider(.payload(body, transport: .http)).fetchSnapshot()
        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.first?.utilization == 25)
        #expect(snapshot.windows.first?.kind == .billingPeriod(label: "Monthly", duration: 31 * 24 * 60 * 60))
    }

    @Test func exhaustedPoolIsLiveZeroRemaining() async {
        let body = Data("""
        {"config":{"creditUsagePercent":100,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-01T00:00:00Z","end":"2026-07-08T00:00:00Z"}}}
        """.utf8)
        let snapshot = await provider(.payload(body, transport: .http)).fetchSnapshot()
        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.first?.percentRemaining == 0)
    }

    @Test func missingRealPeriodEndFailsSafe() async {
        let body = Data("""
        {"config":{"creditUsagePercent":10,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-01T00:00:00Z"}}}
        """.utf8)
        let snapshot = await provider(.payload(body, transport: .http)).fetchSnapshot()
        guard case .stale(let reason) = snapshot.freshness else {
            Issue.record("expected stale snapshot")
            return
        }
        #expect(reason == .decode("Couldn't read Grok usage response"))
    }

    @Test func wrappedACPResultDecodes() async {
        let body = Data("""
        {"result":{"config":{"creditUsagePercent":12,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-01T00:00:00Z","end":"2026-07-08T00:00:00Z"}}}}
        """.utf8)
        let snapshot = await provider(.payload(body, transport: .stdio)).fetchSnapshot()
        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.first?.utilization == 12)
    }

    @Test func setupFailuresAreTypedAndRedacted() async {
        let cases: [(GrokUsageSourceResult, ProviderSetupOutcome)] = [
            (.cliNotFound, .grokCLIMissing),
            (.authAbsent, .grokAuthAbsent),
            (.authPermissionDenied, .grokPermissionDenied),
            (.authUnsafePermissions, .grokUnsafePermissions),
            (.authMalformed, .grokMalformedAuth),
            (.authIOFailure, .grokCredentialIO),
            (.rejectedAuth, .grokRejectedAuth),
        ]
        for (result, expected) in cases {
            let snapshot = await provider(result).fetchSnapshot()
            guard case .stale(let reason) = snapshot.freshness else {
                Issue.record("expected stale snapshot")
                continue
            }
            #expect(reason.providerSetupOutcome == expected)
        }
    }

    @Test func fallbackRunsOnlyForMissingACPMethod() async {
        let primary = CountingGrokSource(.methodUnavailable)
        let fallback = CountingGrokSource(.payload(Data("{}".utf8), transport: .http))
        let source = GrokFallbackUsageSource(primary: primary, fallback: fallback)
        #expect(await source.fetchUsage() == .payload(Data("{}".utf8), transport: .http))
        #expect(primary.fetchCount == 1)
        #expect(fallback.fetchCount == 1)

        let failingPrimary = CountingGrokSource(.failure(.transient("Network unavailable")))
        let unusedFallback = CountingGrokSource(.payload(Data("{}".utf8), transport: .http))
        let noFallback = GrokFallbackUsageSource(primary: failingPrimary, fallback: unusedFallback)
        #expect(await noFallback.fetchUsage() == .failure(.transient("Network unavailable")))
        #expect(unusedFallback.fetchCount == 0)
    }

    @Test func authBlobUsesOnlyFirstPartyOIDCScope() throws {
        let data = Data("""
        {"xai::api_key":{"key":"wrong","user_id":"wrong"},"https://auth.x.ai::client":{"auth_mode":"oidc","key":"secret","user_id":"user"}}
        """.utf8)
        let credential = try GrokAuthBlob.parse(data)
        #expect(credential.accessToken == "secret")
        #expect(credential.userID == "user")
    }

    @Test func malformedAuthNeverFallsBackToArbitraryScope() {
        let data = Data("""
        {"https://enterprise.invalid::client":{"auth_mode":"oidc","key":"secret","user_id":"user"}}
        """.utf8)
        #expect(throws: CredentialError.malformed) { try GrokAuthBlob.parse(data) }
    }

    @Test func builtInCLIEnvironmentDropsInheritedAlternateHome() {
        let builtIn = GrokACPUsageSource.environment(
            inherited: ["GROK_HOME": "/tmp/wrong", "KEEP": "yes"],
            overrides: [:],
            loginPath: "/usr/bin:/bin"
        )
        #expect(builtIn["GROK_HOME"] == nil)
        #expect(builtIn["KEEP"] == "yes")
        #expect(builtIn["PATH"] == "/usr/bin:/bin")

        let extra = GrokACPUsageSource.environment(
            inherited: ["GROK_HOME": "/tmp/wrong"],
            overrides: ["GROK_HOME": "/tmp/headroom-account"],
            loginPath: "/usr/bin:/bin"
        )
        #expect(extra["GROK_HOME"] == "/tmp/headroom-account")
    }

    @Test func executableDisappearingBeforeProbeFailsClosedWithoutACPSpawn() async {
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-removed-grok-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(
            atPath: executable.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o700]
        ))
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        try? FileManager.default.removeItem(at: executable)

        #expect(await GrokACPUsageSource(grokPath: executable.path).fetchUsage() == .cliNotFound)
    }
}
