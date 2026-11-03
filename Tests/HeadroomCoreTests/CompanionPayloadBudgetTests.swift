import Foundation
import Testing

@testable import HeadroomCore

/// KTD7 / V8 / V9: the 20-accounts-per-provider envelope with Spark rows, plus manifest,
/// receipt and request keys, measured with compact encoding at every ladder step.
@Suite
struct CompanionPayloadBudgetTests {
    typealias F = CompanionFixtures

    /// Deterministic, deliberately heavy: lowercase-UUID account IDs, long user labels,
    /// source-precision utilization on every row, two Claude model rows, two Codex Spark
    /// rows, banked resets, stale retained rows and API spend on every provider.
    static func envelopeFixture(accountsPerProvider: Int = 20) throws -> [CompanionProviderPayload] {
        func id(_ provider: Int, _ index: Int) -> String {
            String(format: "%08x-4f2b-4c1d-9a7e-%012x", provider * 1_000 + index, index * 7_919)
        }
        func label(_ index: Int) -> String {
            index == 0 ? "Personal" : "Client account \(index + 1) — long label"
        }
        func spend(_ provider: String) throws -> CompanionSpendSummary {
            try CompanionSpendSummary(
                id: provider, displayName: ProviderID(provider).displayName + " API",
                amount: 1_234.56, currency: "USD", periodLabel: "Oct 1 – Oct 31",
                capturedAt: F.date(-30))
        }
        func row(_ kind: CompanionWindowKind, _ name: String? = nil, _ i: Int, spark: Bool = false,
                 duration: Double? = nil, stale: Bool = false) -> CompanionSlimWindow {
            let used = Double((i * 37 + (name?.count ?? 0)) % 100) + 0.123456
            return F.window(
                kind, name: name, duration: duration, remaining: 100 - used, utilization: used,
                resetAt: 3_600 + Int64(i) * 61, freshness: stale ? .stale : .live,
                observed: stale ? F.date(-7_200) : nil, spark: spark)
        }
        var payloads: [CompanionProviderPayload] = []
        for (p, provider) in ["claude", "codex", "grok"].enumerated() {
            let accounts = try (0..<accountsPerProvider).map { i -> CompanionAccountSummary in
                let windows: [CompanionSlimWindow]
                switch provider {
                case "claude":
                    windows = [
                        row(.fiveHour, nil, i), row(.weekly, nil, i),
                        row(.other, "Weekly (Fable)", i), row(.other, "Weekly (Sonnet)", i, stale: i % 3 == 0),
                    ]
                case "codex":
                    windows = [
                        row(.fiveHour, nil, i), row(.weekly, nil, i),
                        row(.other, "GPT-5.3-Codex-Spark 5h", i, spark: true),
                        row(.other, "GPT-5.3-Codex-Spark Weekly", i, spark: true),
                    ]
                default:
                    windows = [row(.billingPeriod, "Weekly", i, duration: 604_800)]
                }
                return try CompanionAccountSummary(
                    id: i == 0 ? "primary" : id(p, i), title: label(i), planName: "Prolite Plus",
                    capturedAt: F.date(-Int64(i) * 13), bankedResets: provider == "codex" ? i % 4 : nil,
                    windows: windows)
            }
            payloads.append(
                try CompanionProviderPayload(
                    sourceID: F.macA, providerID: provider, payloadGeneration: 4_000_000_000 + Int64(p),
                    mode: .subscription, capabilityAttention: p == 0 ? .cliDiscoveryRetrying : nil,
                    mainAccount: accounts[0], accounts: Array(accounts.dropFirst()),
                    apiSpend: try spend(provider)))
        }
        // Cursor is single-account by design (no isolated config home).
        payloads.append(
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "cursor", payloadGeneration: 4_000_000_003,
                mode: .subscription,
                mainAccount: try CompanionAccountSummary(
                    id: "primary", title: "Personal", planName: "Pro", capturedAt: F.date(),
                    windows: [
                        row(.billingPeriod, "Cursor Models", 0, duration: 2_592_000),
                        row(.billingPeriod, "Other Models", 1, duration: 2_592_000),
                    ]),
                apiSpend: try spend("cursor")))
        // Copilot is single-account and has no spend or plan label (U5, Copilot plan).
        payloads.append(
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "copilot", payloadGeneration: 4_000_000_004,
                mode: .subscription,
                mainAccount: try CompanionAccountSummary(
                    id: "primary", title: "Personal", capturedAt: F.date(),
                    windows: [row(.billingPeriod, "Monthly", 0, duration: 2_592_000)])))
        return payloads
    }

    static func protocolValues(devices: Int) throws -> [String: Data] {
        let ids = (0..<devices).map { _ in UUID().uuidString.lowercased() }
        var values: [String: Data] = [:]
        for device in ids {
            let request = try CompanionRequest(
                requestID: UUID().uuidString, requestedAt: F.date(), sourceID: F.macA)
            values[CompanionSyncKeys.request(deviceUUID: device)!] = try CompanionSyncCodec.encode(request)
        }
        let answered = try (0..<8).map { _ in
            try CompanionAnsweredRequest(requestID: UUID().uuidString, outcome: .finished, finishedGeneration: 4_000_000_000)
        }
        let receipt = try CompanionReceipt(
            sourceID: F.macA, state: .finished, requestIDs: (0..<12).map { _ in UUID().uuidString },
            answeredRequests: answered, startedAt: F.date(-60), finishedAt: F.date(),
            total: 61, completed: 61,
            lastLanded: CompanionLastLanded(providerID: "codex", accountID: "primary", live: true),
            finishedGeneration: 4_000_000_000)
        values[CompanionSyncKeys.receipt] = try CompanionSyncCodec.encode(receipt)
        return values
    }

    static func manifest(level: Int, values: [String: Data]) throws -> Data {
        let rules = try [
            CompanionReminderRuleSummary(amount: 6, unit: .hours, threshold: 40),
            CompanionReminderRuleSummary(amount: 2, unit: .days, threshold: 25),
        ]
        let answered = try (0..<8).map { _ in
            try CompanionAnsweredRequest(requestID: UUID().uuidString, outcome: .cooldown, finishedGeneration: 4_000_000_000)
        }
        var entries: [String: CompanionManifestProviderEntry] = [:]
        for (id, data) in values {
            entries[id] = F.entry(data, generation: 4_000_000_000, interval: 1_234.5)
        }
        return try CompanionSyncCodec.encode(
            CompanionManifest.active(
                try CompanionActiveManifest(
                    sourceID: F.macA, generation: 4_000_000_123, generatedAt: F.date(),
                    macAppVersion: "1.5 (40)", providerOrder: ["claude", "codex", "grok", "cursor"],
                    providers: entries, spendOrder: ["claude", "codex", "grok", "cursor"],
                    chosenIntervalSeconds: 300,
                    display: CompanionDisplayBlock(
                        meterStyle: MeterStyle(launchToken: "full.segmented.ghost") ?? .default,
                        percentageMode: .used, accountTitleInk: .brand, appSparkEnabled: true),
                    widgetProviderSelection: ["codex", "claude"], widgetSparkEnabled: true,
                    reminderSummary: CompanionReminderSummary(
                        macUseItUpEnabled: true, macBankedResetEnabled: true,
                        phoneChannelEnabled: true, rules: rules, scope: [.weekly, .fiveHour]),
                    answeredRequests: answered, dropLadderLevel: level)))
    }

    /// V9 and the KTD7 stop condition: at the envelope every account reaches the phone.
    @Test func multiTwentyWithSparkRowsFitsWithoutCappingAnyAccount() throws {
        let payloads = try Self.envelopeFixture()
        #expect(payloads.map(\.allAccounts.count) == [20, 20, 20, 1, 1])
        let protocolValues = try Self.protocolValues(devices: 5)
        var levels: [Int: CompanionBudgetMeasurement] = [:]
        for level in 0...1 {
            let fit = try CompanionPayloadBudget.fit(
                payloads: payloads, protocolValues: protocolValues, minimumLevel: level,
                manifest: Self.manifest)
            levels[fit.ladderLevel] = fit.measurement
            #expect(fit.payloads.map(\.allAccounts.count) == [20, 20, 20, 1, 1])
            #expect(fit.payloads.allSatisfy { $0.omittedAccountCount == 0 })
            for (key, bytes) in fit.measurement.valueBytes.sorted(by: { $0.key < $1.key }) {
                print("U4-BUDGET level=\(fit.ladderLevel) key=\(key) bytes=\(bytes)")
            }
            print("U4-BUDGET level=\(fit.ladderLevel) total=\(fit.measurement.totalBytes)")
        }
        let full = try #require(levels[0])
        #expect(full.fits)
        for id in CompanionSyncKeys.knownProviderIDs {
            #expect(try #require(full.valueBytes[CompanionSyncKeys.provider(id)!]) <= 15_000)
        }
        #expect(full.totalBytes <= 64_000)
        // Step 1 only ever shrinks: extras lose model rows, the main keeps all of its rows.
        let trimmed = try #require(levels[1])
        #expect(trimmed.totalBytes < full.totalBytes)
    }

    @Test func overTheEnvelopeTheLadderCapsOnlyAboveTwentyAndReportsTheCount() throws {
        let payloads = try Self.envelopeFixture(accountsPerProvider: 120)
        let fit = try CompanionPayloadBudget.fit(
            payloads: payloads, protocolValues: try Self.protocolValues(devices: 5), manifest: Self.manifest)
        #expect(fit.ladderLevel == 2)
        #expect(fit.payloads.prefix(3).allSatisfy { $0.allAccounts.count == 20 && $0.omittedAccountCount == 100 })
        #expect(fit.payloads.suffix(2).allSatisfy { $0.allAccounts.count == 1 })
    }

    /// Decision 3: protocol overflow stops the write; it never caps accounts at or below 20.
    @Test func protocolOverflowAtTheEnvelopeStopsInsteadOfCapping() throws {
        let payloads = try Self.envelopeFixture()
        var flood = try Self.protocolValues(devices: 1)
        flood[CompanionSyncKeys.request(deviceUUID: UUID().uuidString)!] = Data(count: 60_000)
        #expect(throws: CompanionBudgetError.self) {
            try CompanionPayloadBudget.fit(payloads: payloads, protocolValues: flood, manifest: Self.manifest)
        }
    }

    @Test func oneRequestKeyPerInstallNoMatterHowManyPulls() throws {
        let store = SpyKeyValueStore()
        let device = UUID().uuidString
        for _ in 0..<100 {
            let request = try CompanionRequest(requestID: UUID().uuidString, requestedAt: F.date(), sourceID: F.macA)
            store.set(try CompanionSyncCodec.encode(request), forKey: CompanionSyncKeys.request(deviceUUID: device)!)
        }
        #expect(store.keys(withPrefix: CompanionSyncKeys.requestPrefix).count == 1)
    }

    /// V8: no email, config path, credential marker or upstream account ID in encoded v4,
    /// even when the Mac-side source carries them.
    @Test func encodedV4ContainsNoEmailConfigPathOrUpstreamIdentity() throws {
        let fixture = DemoFixture.multiFixture(for: .envelope)
        let titles = fixture.accounts.map(\.label)
        var payloads = try Self.envelopeFixture()
        payloads[0] = try CompanionProviderPayload(
            sourceID: F.macA, providerID: "claude", payloadGeneration: 1, mode: .subscription,
            mainAccount: payloads[0].mainAccount,
            accounts: try titles.prefix(19).enumerated().map { i, title in
                try CompanionAccountSummary(id: "claude-\(i)", title: title, capturedAt: F.date(), windows: [])
            })
        let fit = try CompanionPayloadBudget.fit(
            payloads: payloads, protocolValues: try Self.protocolValues(devices: 2), manifest: Self.manifest)
        let encoded = (Array(fit.providerValues.values) + [fit.manifest])
            .map { String(decoding: $0, as: UTF8.self) }.joined()
        for banned in [
            "@", "example.com", "/Users/", ".claude", ".codex", ".grok", "CLAUDE_CONFIG_DIR",
            "CODEX_HOME", "GROK_HOME", "COPILOT_HOME", ".copilot", "Application Support", "accountUuid", "oauthAccount",
            "access_token", "refresh_token", "auth.json", "Claude Code-credentials", "Authorization",
            "x-api-key", "email",
        ] {
            #expect(!encoded.contains(banned), "\(banned)")
        }
    }
}
