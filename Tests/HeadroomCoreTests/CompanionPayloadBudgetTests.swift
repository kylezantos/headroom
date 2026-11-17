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
    static func envelopeFixture(
        accountsPerProvider: Int = 20, title: ((_ provider: String, _ index: Int) -> String)? = nil
    ) throws -> [CompanionProviderPayload] {
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
                    id: i == 0 ? "primary" : id(p, i), title: title?(provider, i) ?? label(i),
                    planName: "Prolite Plus",
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
                    id: "primary", title: title?("cursor", 0) ?? "Personal", planName: "Pro", capturedAt: F.date(),
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
        // KTD16 (OpenCode plan): OpenCode carries the full envelope, three windows each (KTD6:
        // rolling → 5-hour, weekly → weekly, monthly → a 30-day billing period). It has no
        // spend row (D1) and no plan label, so the payload is no heavier than it will be.
        let opencode = try (0..<accountsPerProvider).map { i -> CompanionAccountSummary in
            try CompanionAccountSummary(
                id: i == 0 ? "primary" : id(5, i), title: title?("opencode", i) ?? label(i),
                capturedAt: F.date(-Int64(i) * 13),
                windows: [
                    row(.fiveHour, nil, i), row(.weekly, nil, i),
                    row(.billingPeriod, "Monthly", i, duration: 2_592_000, stale: i % 4 == 0),
                ])
        }
        payloads.append(
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "opencode", payloadGeneration: 4_000_000_005,
                mode: .subscription, mainAccount: opencode[0], accounts: Array(opencode.dropFirst())))
        // Antigravity is single-account: four pool rows and its credits badge as the plan name,
        // with no spend row.
        payloads.append(
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "antigravity", payloadGeneration: 4_000_000_006,
                mode: .subscription,
                mainAccount: try CompanionAccountSummary(
                    id: "primary", title: title?("antigravity", 0) ?? "Antigravity", planName: "1,200 Credits",
                    capturedAt: F.date(),
                    windows: [
                        row(.other, "Gemini 5h", 0), row(.other, "Gemini weekly", 1),
                        row(.other, "Other weekly", 2), row(.other, "Other 5h", 3),
                    ])))
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
                    macAppVersion: "1.5 (40)",
                    providerOrder: ["claude", "codex", "grok", "cursor", "copilot", "opencode", "antigravity"],
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
        #expect(payloads.map(\.allAccounts.count) == [20, 20, 20, 1, 1, 20, 1])
        let protocolValues = try Self.protocolValues(devices: 5)
        var levels: [Int: CompanionBudgetMeasurement] = [:]
        for level in 0...1 {
            let fit = try CompanionPayloadBudget.fit(
                payloads: payloads, protocolValues: protocolValues, minimumLevel: level,
                manifest: Self.manifest)
            levels[fit.ladderLevel] = fit.measurement
            #expect(fit.payloads.map(\.allAccounts.count) == [20, 20, 20, 1, 1, 20, 1])
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

    /// KTD9 amended (Nov 2026): with "Use email as account name" on, every title can be an
    /// email. At the envelope, with realistic-length addresses on every Claude, Codex, Grok
    /// and Cursor account (Copilot captures none), the whole set still fits at level 0.
    @Test func multiTwentyWithEmailTitlesStillFitsAtLevelZero() throws {
        func email(_ provider: String, _ index: Int) -> String {
            "alexandra.rivera-\(provider)\(index + 1)@northwind-research.example.com"
        }
        let payloads = try Self.envelopeFixture(title: email)
        #expect(payloads.map(\.allAccounts.count) == [20, 20, 20, 1, 1, 20, 1])
        #expect(payloads[0].allAccounts.allSatisfy { $0.title.count >= 50 })
        let fit = try CompanionPayloadBudget.fit(
            payloads: payloads, protocolValues: try Self.protocolValues(devices: 5), manifest: Self.manifest)
        for (key, bytes) in fit.measurement.valueBytes.sorted(by: { $0.key < $1.key }) {
            print("EMAIL-TITLE-BUDGET level=\(fit.ladderLevel) key=\(key) bytes=\(bytes)")
        }
        print("EMAIL-TITLE-BUDGET level=\(fit.ladderLevel) total=\(fit.measurement.totalBytes)")
        #expect(fit.ladderLevel == 0)
        #expect(fit.measurement.fits)
        #expect(fit.payloads.allSatisfy { $0.omittedAccountCount == 0 })
        for id in CompanionSyncKeys.knownProviderIDs {
            #expect(try #require(fit.measurement.valueBytes[CompanionSyncKeys.provider(id)!]) <= 15_000)
        }
        #expect(fit.measurement.totalBytes <= 64_000)
    }

    /// Default-login plan U9 (Risks: "20 accounts plus 20 remembered accounts"): Claude and
    /// Codex each carry 20 engine accounts and 20 remembered ones (stale rows with their own
    /// read times, long labels), beside the rest of the envelope. The write fits by the
    /// existing ladder, and wherever the ladder caps it drops remembered rows first, because
    /// they sort after every engine row.
    @Test func twentyAccountsPlusTwentyRememberedFitByTheExistingLadder() throws {
        var payloads = try Self.envelopeFixture()
        func remembered(_ provider: String, _ i: Int) throws -> CompanionAccountSummary {
            let used = Double((i * 41 + 7) % 100) + 0.654321
            let read = F.date(-86_400 - Int64(i) * 97)
            func row(_ kind: CompanionWindowKind, _ name: String? = nil) -> CompanionSlimWindow {
                F.window(kind, name: name, remaining: 100 - used, utilization: used,
                         resetAt: 7_200 + Int64(i) * 59, freshness: .stale, observed: read,
                         spark: provider == "codex" && name != nil)
            }
            let windows = provider == "claude"
                ? [row(.fiveHour), row(.weekly), row(.other, "Weekly (Fable)"), row(.other, "Weekly (Sonnet)")]
                : [row(.fiveHour), row(.weekly), row(.other, "GPT-5.3-Codex-Spark 5h"),
                   row(.other, "GPT-5.3-Codex-Spark Weekly")]
            return try CompanionAccountSummary(
                id: UUID().uuidString.lowercased(), title: "Remembered client account \(i + 1) — long label",
                planName: "Prolite Plus", freshness: .stale, capturedAt: read, needsAttention: false,
                bankedResets: provider == "codex" ? i % 4 : nil, windows: windows, isRemembered: true)
        }
        for index in 0..<2 {
            let base = payloads[index]
            payloads[index] = try CompanionProviderPayload(
                sourceID: base.sourceID, providerID: base.providerID, payloadGeneration: base.payloadGeneration,
                mode: base.mode, capabilityAttention: base.capabilityAttention, mainAccount: base.mainAccount,
                accounts: base.accounts + (0..<20).map { try remembered(base.providerID, $0) },
                apiSpend: base.apiSpend)
        }
        #expect(payloads.map(\.allAccounts.count) == [40, 40, 20, 1, 1, 20, 1])
        let protocolValues = try Self.protocolValues(devices: 5)

        let fit = try CompanionPayloadBudget.fit(
            payloads: payloads, protocolValues: protocolValues, manifest: Self.manifest)
        for (key, bytes) in fit.measurement.valueBytes.sorted(by: { $0.key < $1.key }) {
            print("U9-REMEMBERED-BUDGET level=\(fit.ladderLevel) key=\(key) bytes=\(bytes)")
        }
        print("U9-REMEMBERED-BUDGET level=\(fit.ladderLevel) total=\(fit.measurement.totalBytes)")
        #expect(fit.measurement.fits)
        for payload in fit.payloads.prefix(2) {
            // Whatever reaches the phone keeps every engine row, remembered rows after them.
            let flags = payload.allAccounts.map(\.isRemembered)
            #expect(flags.prefix(20).allSatisfy { !$0 })
            #expect(flags.dropFirst(20).allSatisfy { $0 })
            #expect(payload.allAccounts.count + payload.omittedAccountCount == 40)
        }

        // Every level the ladder can reach, measured; the cap step drops remembered rows only.
        for level in 0...2 {
            let stepped = try payloads.map { try CompanionPayloadBudget.apply(level: level, to: $0) }
            let values = try stepped.map { try CompanionSyncCodec.encode($0) }
            print("U9-REMEMBERED-BUDGET forced-level=\(level) claude=\(values[0].count) codex=\(values[1].count) "
                + "providers=\(values.map(\.count).reduce(0, +))")
            if level == 2 {
                for payload in stepped.prefix(2) {
                    #expect(payload.allAccounts.count == 20)
                    #expect(payload.allAccounts.allSatisfy { !$0.isRemembered })
                    #expect(payload.omittedAccountCount == 20)
                }
            }
        }
    }

    @Test func overTheEnvelopeTheLadderCapsOnlyAboveTwentyAndReportsTheCount() throws {
        let payloads = try Self.envelopeFixture(accountsPerProvider: 120)
        let fit = try CompanionPayloadBudget.fit(
            payloads: payloads, protocolValues: try Self.protocolValues(devices: 5), manifest: Self.manifest)
        #expect(fit.ladderLevel == 2)
        #expect(fit.payloads.prefix(3).allSatisfy { $0.allAccounts.count == 20 && $0.omittedAccountCount == 100 })
        #expect(fit.payloads.dropFirst(3).prefix(2).allSatisfy { $0.allAccounts.count == 1 })
        #expect(fit.payloads.first { $0.providerID == "opencode" }
            .map { $0.allAccounts.count == 20 && $0.omittedAccountCount == 100 } == true)
        #expect(fit.payloads.first { $0.providerID == "antigravity" }?.allAccounts.count == 1)
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
            // KTD10/KTD19 (OpenCode plan): no XDG home, OpenCode path, workspace or Console URL.
            "XDG_", ".local/share/opencode", ".config/opencode", "Accounts/opencode", "wrk_",
            "usageURL", "/console/", "opencode.ai",
            "access_token", "refresh_token", "auth.json", "Claude Code-credentials", "Authorization",
            "x-api-key", "email",
        ] {
            #expect(!encoded.contains(banned), "\(banned)")
        }
    }

    /// KTD16 (OpenCode plan): the monthly window is a window, not a model row, so ladder
    /// level 1 (extras lose model rows) keeps every OpenCode account's three windows.
    @Test func ladderLevelOneKeepsEveryOpenCodeWindowIncludingMonthly() throws {
        let payloads = try Self.envelopeFixture()
        let opencode = try #require(payloads.first { $0.providerID == "opencode" })
        let trimmed = try CompanionPayloadBudget.apply(level: 1, to: opencode)
        #expect(trimmed.allAccounts.count == 20)
        #expect(trimmed.allAccounts.allSatisfy { $0.windows.map(\.kind) == [.fiveHour, .weekly, .billingPeriod] })
        #expect(trimmed.allAccounts.allSatisfy { $0.windows.last?.kindName == "Monthly" })
        #expect(try CompanionSyncCodec.encode(trimmed) == CompanionSyncCodec.encode(opencode))
    }
}
