import Foundation
import Testing

@testable import HeadroomCore

/// U4 manifest/provider envelopes, header-first routing, keys and the raw-byte digest.
@Suite
struct CompanionSyncEnvelopeTests {
    typealias F = CompanionFixtures

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
    private func activeManifest() throws -> (CompanionManifest, Data) {
        let claude = F.bytes(F.payload())
        let manifest = F.manifest(
            generation: 12, order: ["claude", "codex", "claude", "future"],
            entries: ["claude": F.entry(claude, generation: 12)], spendOrder: ["claude"],
            display: CompanionDisplayBlock(percentageMode: .used), selection: [],
            widgetSpark: true, ladder: 1)
        return (manifest, F.bytes(manifest))
    }

    // MARK: Golden digest (KTD6.2)

    /// Pinned bytes and digest catch per-process hashing or an encoder change. The digest
    /// constant was computed independently with `shasum -a 256` over the literal below.
    static let goldenPayloadJSON =
        #"{"a":{"c":1790000000,"i":"primary","p":"Max","t":"Personal","w":[{"k":"fiveHour","p":63,"r":"scheduled","t":1790003600,"u":37}]},"g":7,"i":"6f1c2c1e-1b7a-4d6b-9d55-8f6f3b8f2a01","m":"subscription","p":"claude","r":1,"v":4}"#
    static let goldenPayloadDigest =
        "55bd8baaec44f646fe4b88eff2f2caf7ff712f8b15aceb55755d65d9e0656042"

    @Test func goldenPayloadBytesAndDigestArePinned() throws {
        let payload = F.payload(
            generation: 7,
            main: F.account(windows: [F.window(.fiveHour, remaining: 63, utilization: 37)]))
        let encoded = F.bytes(payload)
        #expect(String(decoding: encoded, as: UTF8.self) == Self.goldenPayloadJSON)
        #expect(CompanionSyncCodec.digest(encoded) == Self.goldenPayloadDigest)
        #expect(CompanionSyncCodec.digest(Data(Self.goldenPayloadJSON.utf8)) == Self.goldenPayloadDigest)
        // Re-encoding identical content yields identical bytes, in any construction order.
        let decoded = try #require(
            CompanionSyncCodec.decodeProviderPayload(encoded, providerID: "claude").valueForTest)
        #expect(F.bytes(decoded) == encoded)
    }

    @Test func digestCoversRawBytesSoUnknownFieldsSurviveVerification() throws {
        var json = try object(Data(Self.goldenPayloadJSON.utf8))
        json["futureField"] = ["nested": true]
        let raw = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        let decoded = try #require(
            CompanionSyncCodec.decodeProviderPayload(raw, providerID: "claude").valueForTest)
        // The decoded model drops the unknown field, so hashing a re-encoding would differ.
        #expect(CompanionSyncCodec.digest(F.bytes(decoded)) == Self.goldenPayloadDigest)
        #expect(CompanionSyncCodec.digest(raw) != Self.goldenPayloadDigest)
        #expect(CompanionSyncCodec.digest(raw).count == 64)
    }

    @Test func manifestEncodingIsDeterministicWithIntegerEpochsAndSortedKeys() throws {
        let (manifest, bytes) = try activeManifest()
        #expect(F.bytes(manifest) == bytes)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains(#""t":1790000000"#))
        let keys = try object(bytes).keys.sorted()
        #expect(keys == ["a", "c", "d", "g", "i", "j", "k", "l", "o", "p", "r", "s", "t", "v", "w"])
        // Map insertion order cannot change bytes: sorted keys at every level.
        let a = F.bytes(F.payload()), b = F.bytes(F.payload("codex"))
        let forward = F.manifest(entries: ["claude": F.entry(a, generation: 1), "codex": F.entry(b, generation: 2)])
        var reversed: [String: CompanionManifestProviderEntry] = [:]
        reversed["codex"] = F.entry(b, generation: 2)
        reversed["claude"] = F.entry(a, generation: 1)
        #expect(F.bytes(forward) == F.bytes(F.manifest(entries: reversed)))
        #expect(text.hasPrefix(#"{"a":"1.5","c":300,"d":"#))
    }

    // MARK: Manifest routing (contract Decision 1)

    @Test func disabledTombstoneIsTheLiteralTwoFieldPair() throws {
        let tombstone = try CompanionManifest.disabledTombstone(sourceID: F.macA.uppercased())
        let bytes = F.bytes(tombstone)
        #expect(String(decoding: bytes, as: UTF8.self) == #"{"i":"\#(F.macA)","s":"disabled"}"#)
        #expect(CompanionSyncCodec.decodeManifest(bytes) == .value(.disabled(sourceID: F.macA)))
        // Unknown fields, even a garbage or future version header, never block disabled routing.
        for extra in [
            ["v": 9, "r": 7], ["v": "x", "g": "bad", "future": [1]], ["t": NSNull()],
        ] as [[String: Any]] {
            var json: [String: Any] = ["i": F.macA, "s": "disabled"]
            json.merge(extra) { $1 }
            #expect(CompanionSyncCodec.decodeManifest(try data(json)) == .value(.disabled(sourceID: F.macA)))
        }
    }

    @Test func malformedTombstoneIsNeverMistakenForEitherState() throws {
        #expect(CompanionSyncCodec.decodeManifest(nil) == .missing)
        for json in [
            ["s": "disabled"], ["i": "not-a-uuid", "s": "disabled"], ["i": F.macA],
            ["i": 12, "s": "disabled"], ["i": F.macA, "s": 0],
        ] as [[String: Any]] {
            #expect(CompanionSyncCodec.decodeManifest(try data(json)) == .corrupt)
        }
        #expect(
            CompanionSyncCodec.decodeManifest(try data(["i": F.macA, "s": "paused"]))
                == .unsupportedControlState)
        // Enabled without its version header is corrupt, never a fabricated active manifest.
        #expect(CompanionSyncCodec.decodeManifest(try data(["i": F.macA, "s": "enabled"])) == .corrupt)
    }

    @Test func activeVersionsRouteBeforeTheBodyAndFutureCompatibleSchemasDecode() throws {
        let (manifest, bytes) = try activeManifest()
        #expect(CompanionSyncCodec.decodeManifest(bytes) == .value(manifest))
        var future = try object(bytes)
        future["v"] = 9
        future["futureBlock"] = ["x": 1]
        let decoded = try #require(CompanionSyncCodec.decodeManifest(try data(future)).valueForTest)
        #expect(decoded.active?.schemaVersion == 9 && decoded.active?.generation == 12)
        var tooNew = future
        tooNew["r"] = 2
        tooNew["p"] = "an unreadable future body"
        #expect(CompanionSyncCodec.decodeManifest(try data(tooNew)) == .unsupportedReader)
        var old = try object(bytes)
        old["v"] = 3
        #expect(CompanionSyncCodec.decodeManifest(try data(old)) == .unsupportedSchema)
        for key in ["g", "t", "o", "p", "c", "l"] {
            var missing = try object(bytes)
            missing.removeValue(forKey: key)
            #expect(CompanionSyncCodec.decodeManifest(try data(missing)) == .corrupt)
        }
        for (key, wrong) in [("g", -1), ("c", 0), ("l", -1), ("t", "now")] as [(String, Any)] {
            var invalid = try object(bytes)
            invalid[key] = wrong
            #expect(CompanionSyncCodec.decodeManifest(try data(invalid)) == .corrupt)
        }
    }

    @Test func manifestOrderSelectionAndBrokenEntriesFollowTheFieldTable() throws {
        let (_, bytes) = try activeManifest()
        var json = try object(bytes)
        var entries = try #require(json["p"] as? [String: Any])
        entries["codex"] = ["g": 3, "h": "not-a-digest", "e": 300]
        entries["grok"] = ["g": 3, "h": String(repeating: "a", count: 64), "e": 0]
        json["p"] = entries
        let manifest = try #require(CompanionSyncCodec.decodeManifest(try data(json)).valueForTest?.active)
        #expect(manifest.providers.keys.sorted() == ["claude"])
        #expect(manifest.providerOrder == ["claude", "codex", "future"])
        #expect(manifest.knownProviderOrder == ["claude", "codex"])
        #expect(manifest.widgetProviderSelection == [])
        #expect(manifest.widgetSparkEnabled && manifest.ladder == .modelRowsDropped)
        #expect(manifest.display?.percentageMode == .used)
        json.removeValue(forKey: "w")
        json.removeValue(forKey: "k")
        json.removeValue(forKey: "j")
        json["l"] = 7
        let defaults = try #require(CompanionSyncCodec.decodeManifest(try data(json)).valueForTest?.active)
        #expect(defaults.widgetProviderSelection == nil && !defaults.widgetSparkEnabled)
        #expect(defaults.spendOrder == [] && defaults.ladder == .unknown)
        json["k"] = NSNull()
        #expect(CompanionSyncCodec.decodeManifest(try data(json)) == .corrupt)
    }

    // MARK: Provider payload

    @Test func providerPayloadValidatesModeAccountsAndSuffix() throws {
        let payload = F.payload(
            extras: [F.account("a1", title: "Work"), F.account("a2", title: "Work · 2")])
        let bytes = F.bytes(payload)
        #expect(CompanionSyncCodec.decodeProviderPayload(bytes, providerID: "claude") == .value(payload))
        #expect(CompanionSyncCodec.decodeProviderPayload(bytes, providerID: "codex") == .corrupt)
        #expect(CompanionSyncCodec.decodeProviderPayload(nil, providerID: "claude") == .missing)
        #expect(payload.allAccounts.map(\.id) == ["primary", "a1", "a2"])

        let main = F.account()
        #expect(throws: (any Error).self) {
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "claude", payloadGeneration: 1, mode: .subscription,
                mainAccount: nil)
        }
        #expect(throws: (any Error).self) {
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "claude", payloadGeneration: 1, mode: .subscription,
                mainAccount: main, accounts: [main])
        }
        #expect(throws: (any Error).self) {
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "claude", payloadGeneration: 1, mode: .spendOnly,
                mainAccount: nil, accounts: [main])
        }
        #expect(throws: (any Error).self) {
            try CompanionProviderPayload(
                sourceID: F.macA, providerID: "claude", payloadGeneration: -1, mode: .subscription,
                mainAccount: main)
        }

        var json = try object(bytes)
        json["m"] = "familyPlan"
        #expect(CompanionSyncCodec.decodeProviderPayload(try data(json), providerID: "claude") == .unsupportedControlState)
        json = try object(bytes)
        json["r"] = 2
        json["a"] = "future"
        #expect(CompanionSyncCodec.decodeProviderPayload(try data(json), providerID: "claude") == .unsupportedReader)
        json = try object(bytes)
        json["x"] = [try object(F.bytes(F.account("a1"))), try object(F.bytes(F.account("a1")))]
        #expect(CompanionSyncCodec.decodeProviderPayload(try data(json), providerID: "claude") == .corrupt)
        json = try object(bytes)
        json["o"] = -1
        #expect(CompanionSyncCodec.decodeProviderPayload(try data(json), providerID: "claude") == .corrupt)
        json = try object(bytes)
        json["i"] = "not-a-uuid"
        #expect(CompanionSyncCodec.decodeProviderPayload(try data(json), providerID: "claude") == .corrupt)
    }

    @Test func spendOnlyPayloadCarriesSpendAndNoAccounts() throws {
        let spend = try CompanionSpendSummary(
            id: "codex", displayName: "OpenAI", amount: 12.5, currency: "USD",
            periodLabel: "This month", capturedAt: F.date())
        let payload = F.payload("codex", spend: spend, mode: .spendOnly)
        let json = try object(F.bytes(payload))
        #expect(Set(json.keys) == ["g", "i", "m", "p", "r", "s", "v"])
        #expect(json["m"] as? String == "spendOnly")
        #expect(
            CompanionSyncCodec.decodeProviderPayload(F.bytes(payload), providerID: "codex")
                == .value(payload))
    }

    @Test func ladderStepsDropOnlyExtraModelRowsThenCapAboveTheEnvelope() throws {
        let rows = [
            F.window(.fiveHour), F.window(.weekly, resetAt: 86_400),
            F.window(.other, name: "Weekly (Fable)", resetAt: 86_400),
            F.window(.billingPeriod, name: "Monthly", duration: 2_592_000, resetAt: 99),
        ]
        let payload = F.payload(
            main: F.account(windows: rows), extras: [F.account("x1", windows: rows), F.account("x2")])
        let trimmed = try payload.droppingExtraAccountModelRows()
        #expect(trimmed.mainAccount?.windows.count == 4)
        #expect(trimmed.accounts[0].windows.map(\.kind) == [.fiveHour, .weekly, .billingPeriod])
        let capped = try trimmed.cappingExtraAccounts(to: 1)
        #expect(capped.accounts.map(\.id) == ["x1"] && capped.omittedAccountCount == 1)
    }

    // MARK: Keys (KTD6.1)

    @Test func keysStayWithinSixtyFourBytesAndRejectUnknownSuffixes() throws {
        let device = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        let request = try #require(CompanionSyncKeys.request(deviceUUID: device))
        #expect(request.utf8.count == 61)
        #expect(request == "headroom.sync.v4.request.3f2504e0-4f89-11d3-9a0c-0305e82c3301")
        #expect(CompanionSyncKeys.deviceUUID(fromRequestKey: request) == device.lowercased())
        #expect(CompanionSyncKeys.deviceUUID(fromRequestKey: CompanionSyncKeys.requestPrefix + device) == nil)
        #expect(CompanionSyncKeys.deviceUUID(fromRequestKey: CompanionSyncKeys.requestPrefix + "iphone") == nil)
        #expect(CompanionSyncKeys.request(deviceUUID: "Kyle's iPhone") == nil)
        for id in CompanionSyncKeys.knownProviderIDs {
            let key = try #require(CompanionSyncKeys.provider(id))
            #expect(key.utf8.count <= CompanionSyncKeys.maximumKeyBytes)
            #expect(CompanionSyncKeys.providerID(fromKey: key) == id)
        }
        #expect(CompanionSyncKeys.provider(String(repeating: "p", count: 40)) == nil)
        #expect(CompanionSyncKeys.provider("") == nil)
        for key in [CompanionSyncKeys.manifest, CompanionSyncKeys.receipt] {
            #expect(key.hasPrefix(CompanionSyncKeys.namespace) && key.utf8.count <= 64)
        }
    }

    // MARK: v3 lineage (KTD5)

    @Test func v3LineagePairIsAdditiveAndMalformedLineageIsIgnored() throws {
        let envelope = F.v3(lineage: (F.macA, 12))
        let bytes = F.v3Bytes(envelope)
        let decoded = try #require(SyncedWidgetSnapshotCodec.decode(bytes).envelope)
        #expect(decoded == envelope)
        #expect(decoded.companionLineage == CompanionV3Lineage(sourceID: F.macA, generation: 12))
        #expect(decoded.sourceID == "Mac")
        var json = try object(bytes)
        for (source, generation) in [
            ("not-a-uuid", 12 as Any), (F.macA.uppercased(), 12), (F.macA, -1), (F.macA, "12"),
            (F.macA, NSNull()),
        ] as [(Any, Any)] {
            json["companionSourceID"] = source
            json["companionGeneration"] = generation
            let lenient = try #require(SyncedWidgetSnapshotCodec.decode(try data(json)).envelope)
            #expect(lenient.companionLineage == nil)
            #expect(lenient.snapshot == envelope.snapshot)
        }
        json["companionSourceID"] = 42
        #expect(SyncedWidgetSnapshotCodec.decode(try data(json)).envelope?.companionLineage == nil)
        // An older Mac's payload has neither field; nothing is written for it.
        let legacy = F.v3()
        #expect(try object(F.v3Bytes(legacy))["companionSourceID"] == nil)
        #expect(legacy.companionLineage == nil)
    }
}

extension CompanionSyncDecodeResult {
    var valueForTest: Value? {
        if case .value(let value) = self { value } else { nil }
    }
}
