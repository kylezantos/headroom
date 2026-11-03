import Foundation
import Testing

@testable import HeadroomCore

@Suite
struct CompanionCheckNowModelsTests {
    private let sourceID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    private let requestID = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
    private let stamp = CompanionWireDate(epochSeconds: -1)!

    private func object<T: Encodable>(_ model: T) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any])
    }
    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    private func roundtrip<T: Codable & Equatable>(_ model: T) throws {
        #expect(try JSONDecoder().decode(T.self, from: JSONEncoder().encode(model)) == model)
    }

    @Test func requestHasExactKeysCanonicalUUIDsAndSignedIntegerDate() throws {
        let request = try CompanionRequest(
            requestID: requestID, requestedAt: stamp, sourceID: sourceID)
        try roundtrip(request)
        #expect(request.requestID == requestID.lowercased())
        #expect(request.sourceID == sourceID.lowercased())
        let json = try object(request)
        #expect(Set(json.keys) == Set(["v", "r", "q", "t", "i"]))
        #expect(json["v"] as? Int == 4 && json["r"] as? Int == 1)
        #expect(json["t"] as? Int64 == -1)
        #expect(
            try CompanionRequest(
                schemaVersion: 9, minimumReaderVersion: 2, requestID: requestID,
                requestedAt: stamp, sourceID: sourceID
            ).schemaVersion == 9)
    }

    @Test func requestRequiredFieldsAndConstructorDecodeInvariantsAgree() throws {
        let valid = try object(
            try CompanionRequest(requestID: requestID, requestedAt: stamp, sourceID: sourceID))
        for key in ["v", "r", "q", "t", "i"] {
            for wrong in [nil, NSNull(), "malformed", true] as [Any?] {
                var json = valid
                json[key] = wrong
                #expect(throws: (any Error).self) { try decode(CompanionRequest.self, json) }
            }
        }
        for version in [-1, 0, 1, 3] {
            #expect(throws: (any Error).self) {
                try CompanionRequest(
                    schemaVersion: version, requestID: requestID, requestedAt: stamp,
                    sourceID: sourceID)
            }
        }
        for minimum in [-1, 0] {
            #expect(throws: (any Error).self) {
                try CompanionRequest(
                    minimumReaderVersion: minimum, requestID: requestID, requestedAt: stamp,
                    sourceID: sourceID)
            }
        }
        for id in ["", "primary", "not-a-uuid"] {
            #expect(throws: (any Error).self) {
                try CompanionRequest(requestID: id, requestedAt: stamp, sourceID: sourceID)
            }
            #expect(throws: (any Error).self) {
                try CompanionRequest(requestID: requestID, requestedAt: stamp, sourceID: id)
            }
        }
    }

    @Test func answeredOutcomesRequireOnlyLegitimateTerminalGeneration() throws {
        for outcome in [CompanionAnsweredOutcome.finished, .cooldown] {
            let answer = try CompanionAnsweredRequest(
                requestID: requestID, outcome: outcome, finishedGeneration: 0)
            try roundtrip(answer)
            #expect(Set(try object(answer).keys) == Set(["q", "o", "g"]))
            #expect(answer.requestID == requestID.lowercased())
            #expect(throws: (any Error).self) {
                try CompanionAnsweredRequest(requestID: requestID, outcome: outcome)
            }
            var absent = try object(answer)
            absent.removeValue(forKey: "g")
            #expect(throws: (any Error).self) { try decode(CompanionAnsweredRequest.self, absent) }
        }
        let failed = try CompanionAnsweredRequest(requestID: requestID, outcome: .failed)
        try roundtrip(failed)
        #expect(failed.finishedGeneration == nil)
        #expect(try object(failed)["g"] == nil)
        #expect(throws: (any Error).self) {
            try CompanionAnsweredRequest(requestID: requestID, outcome: .unknown)
        }
        #expect(throws: (any Error).self) {
            try CompanionAnsweredRequest(
                requestID: requestID, outcome: .failed, finishedGeneration: -1)
        }
        for (key, wrong) in [("q", "bad" as Any), ("o", "future"), ("o", 1), ("g", -1), ("g", "0")]
        {
            var json = try object(failed)
            json[key] = wrong
            #expect(throws: (any Error).self) { try decode(CompanionAnsweredRequest.self, json) }
        }
    }

    @Test func landedRequiresKnownProviderAccountAndExplicitLiveBool() throws {
        // KTD13 (Copilot plan): Copilot rows must land too.
        for provider in ["claude", "codex", "grok", "cursor", "copilot"] {
            let landed = try CompanionLastLanded(
                providerID: provider, accountID: "primary", live: false)
            try roundtrip(landed)
            #expect(Set(try object(landed).keys) == Set(["p", "a", "l"]))
            #expect(try object(landed)["l"] as? Bool == false)
        }
        #expect(throws: (any Error).self) {
            try CompanionLastLanded(providerID: "future", accountID: "primary", live: true)
        }
        #expect(throws: (any Error).self) {
            try CompanionLastLanded(providerID: "claude", accountID: "", live: true)
        }
        let valid: [String: Any] = ["p": "claude", "a": "primary", "l": true]
        for key in ["p", "a", "l"] {
            var missing = valid
            missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(CompanionLastLanded.self, missing) }
            missing[key] = NSNull()
            #expect(throws: (any Error).self) { try decode(CompanionLastLanded.self, missing) }
        }
        #expect(throws: (any Error).self) {
            try decode(CompanionLastLanded.self, ["p": "claude", "a": "primary", "l": "true"])
        }
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
    private func id(_ index: Int) -> String {
        String(format: "00000000-0000-4000-8000-%012d", index)
    }

    @Test func receiptActiveMembershipIsRequiredSortedDistinctAndIndependentOfHistoryCap() throws {
        let members = (1...12).reversed().map(id) + [id(1)]
        let answers = try (1...12).map {
            try CompanionAnsweredRequest(
                requestID: id($0), outcome: .finished, finishedGeneration: Int64($0))
        }
        let receipt = try CompanionReceipt(
            sourceID: sourceID, state: .finished, requestIDs: members,
            answeredRequests: answers, finishedGeneration: 12)
        try roundtrip(receipt)
        #expect(receipt.requestIDs == (1...12).map(id))
        #expect(receipt.answeredRequests.map(\.requestID) == (5...12).map(id))
        let json = try object(receipt)
        #expect(Set(json.keys) == Set(["v", "r", "i", "s", "q", "a", "g"]))
        #expect((json["q"] as? [String])?.count == 12)
        let empty = try CompanionReceipt(sourceID: sourceID, state: .accepted, requestIDs: [])
        #expect((try object(empty)["q"] as? [Any])?.isEmpty == true)
        #expect(try object(empty)["a"] == nil)
        var missing = try object(empty)
        missing.removeValue(forKey: "q")
        #expect(throws: (any Error).self) { try decode(CompanionReceipt.self, missing) }
        for invalid in [NSNull(), "members", ["bad"]] as [Any] {
            missing["q"] = invalid
            #expect(throws: (any Error).self) { try decode(CompanionReceipt.self, missing) }
        }
        #expect(throws: (any Error).self) {
            try CompanionReceipt(sourceID: sourceID, state: .accepted, requestIDs: ["bad"])
        }
    }

    @Test func historyKeepsLatestValidDistinctAnswersInTerminalOrderAndSkipsInvalidItems() throws {
        let initial = try (1...10).map {
            try CompanionAnsweredRequest(
                requestID: id($0), outcome: .finished, finishedGeneration: Int64($0))
        }
        let newer = try CompanionAnsweredRequest(requestID: id(1), outcome: .failed)
        let history = CompanionAnsweredRequest.terminalHistory(initial + [newer])
        #expect(history.map(\.requestID) == (4...10).map(id) + [id(1)])
        #expect(history.last?.outcome == .failed && history.last?.finishedGeneration == nil)
        let receipt = try CompanionReceipt(
            sourceID: sourceID, state: .accepted, requestIDs: [],
            answeredRequests: initial + [newer])
        #expect(receipt.answeredRequests == history)
        var json = try object(receipt)
        json["a"] =
            try initial.map(object) + [
                ["q": id(1), "o": "future", "g": 100], ["q": id(2), "o": "finished"],
                ["q": "bad", "o": "finished", "g": 100], ["q": id(3), "o": 1],
                ["q": id(4), "o": "cooldown", "g": -1], try object(newer),
            ]
        let decoded = try decode(CompanionReceipt.self, json)
        #expect(decoded.answeredRequests == history)
        #expect(decoded.answeredRequests.count == 8)
        json["a"] = ["invalid", NSNull(), false]
        #expect(try decode(CompanionReceipt.self, json).answeredRequests.isEmpty)
        for invalid in [NSNull(), "answers"] as [Any] {
            json["a"] = invalid
            #expect(throws: (any Error).self) { try decode(CompanionReceipt.self, json) }
        }
    }

    @Test func receiptCountsGenerationsAndCooldownEvidenceValidateThroughBothEntryPoints() throws {
        for (total, completed) in [(0, 0), (5, 0), (5, 5)] {
            let running = try CompanionReceipt(
                sourceID: sourceID, state: .running, requestIDs: [requestID], total: total,
                completed: completed)
            try roundtrip(running)
            #expect(Set(try object(running).keys) == Set(["v", "r", "i", "s", "q", "n", "d"]))
        }
        #expect(throws: (any Error).self) {
            try CompanionReceipt(sourceID: sourceID, state: .running, requestIDs: [])
        }
        for (total, completed) in [(-1, 0), (1, -1), (1, 2)] {
            #expect(throws: (any Error).self) {
                try CompanionReceipt(
                    sourceID: sourceID, state: .running, requestIDs: [], total: total,
                    completed: completed)
            }
            #expect(throws: (any Error).self) {
                try decode(
                    CompanionReceipt.self,
                    [
                        "v": 4, "r": 1, "i": sourceID, "s": "running", "q": [], "n": total,
                        "d": completed,
                    ])
            }
        }
        #expect(throws: (any Error).self) {
            try CompanionReceipt(sourceID: sourceID, state: .accepted, requestIDs: [], total: 1)
        }
        #expect(throws: (any Error).self) {
            try CompanionReceipt(sourceID: sourceID, state: .finished, requestIDs: [])
        }
        #expect(throws: (any Error).self) {
            try CompanionReceipt(
                sourceID: sourceID, state: .cooldown, requestIDs: [], finishedGeneration: 0)
        }
        let cooldown = try CompanionReceipt(
            sourceID: sourceID, state: .cooldown, requestIDs: [requestID], checkedAt: stamp,
            finishedGeneration: 0)
        try roundtrip(cooldown)
        #expect(cooldown.startedAt == nil && cooldown.finishedAt == nil)
        #expect(try object(cooldown)["g"] as? Int64 == 0)
        #expect(throws: (any Error).self) {
            try CompanionReceipt(
                sourceID: sourceID, state: .accepted, requestIDs: [], finishedGeneration: -1)
        }
        for key in ["g", "c"] {
            var json = try object(cooldown)
            json.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(CompanionReceipt.self, json) }
        }
    }

    @Test func receiptLandedFallbackOmitsIncompleteUnknownOrWrongPrimitiveRows() throws {
        let landed = try CompanionLastLanded(
            providerID: "claude", accountID: "primary", live: false)
        let receipt = try CompanionReceipt(
            sourceID: sourceID, state: .running, requestIDs: [],
            startedAt: stamp, total: 1, completed: 0, lastLanded: landed)
        try roundtrip(receipt)
        for invalid in [
            ["p": "future", "a": "primary", "l": true], ["p": "claude", "a": "primary"],
            ["p": "claude", "a": "", "l": true], ["p": "claude", "a": "primary", "l": "true"],
            "invalid", NSNull(),
        ] as [Any] {
            var json = try object(receipt)
            json["l"] = invalid
            #expect(try decode(CompanionReceipt.self, json).lastLanded == nil)
        }
        var nullable = try object(
            try CompanionReceipt(sourceID: sourceID, state: .accepted, requestIDs: []))
        for key in ["t", "f", "c", "n", "d", "g", "l"] { nullable[key] = NSNull() }
        let decoded = try decode(CompanionReceipt.self, nullable)
        #expect(decoded.startedAt == nil && decoded.total == nil && decoded.lastLanded == nil)
        for (key, wrong) in [
            ("v", NSNull() as Any), ("r", false), ("i", "bad"), ("s", 1), ("n", "1"), ("d", false),
            ("t", "-1"), ("g", "0"),
        ] {
            var json = try object(receipt)
            json[key] = wrong
            #expect(throws: (any Error).self) { try decode(CompanionReceipt.self, json) }
        }
    }

    @Test func codecMissingMalformedAndUnsupportedVersionsRouteBeforeFutureBodies() throws {
        #expect(CompanionSyncCodec.decodeRequest(nil) == .missing)
        #expect(CompanionSyncCodec.decodeReceipt(nil) == .missing)
        for bytes in [Data(), Data("[]".utf8), Data("null".utf8), Data("{".utf8)] {
            #expect(CompanionSyncCodec.decodeRequest(bytes) == .corrupt)
            #expect(CompanionSyncCodec.decodeReceipt(bytes) == .corrupt)
        }
        for header in [
            ["v": 0, "r": 1], ["v": -1, "r": 1], ["v": 4, "r": 0], ["v": 4, "r": -1],
        ] {
            #expect(CompanionSyncCodec.decodeRequest(try data(header)) == .corrupt)
            #expect(CompanionSyncCodec.decodeReceipt(try data(header)) == .corrupt)
        }
        for schema in 1...3 {
            let bytes = try data(["v": schema, "r": 1, "q": ["future": true]])
            #expect(CompanionSyncCodec.decodeRequest(bytes) == .unsupportedSchema)
            #expect(CompanionSyncCodec.decodeReceipt(bytes) == .unsupportedSchema)
        }
        for body in [
            ["v": 8, "r": 2],
            ["v": 8, "r": 2, "q": false, "i": "bad", "t": ["future": true], "s": 1],
        ] as [[String: Any]] {
            #expect(CompanionSyncCodec.decodeRequest(try data(body)) == .unsupportedReader)
            #expect(CompanionSyncCodec.decodeReceipt(try data(body)) == .unsupportedReader)
        }
        for header in [["v": "4", "r": 1], ["v": 4, "r": NSNull()], ["v": 4], ["r": 1]]
            as [[String: Any]]
        {
            #expect(CompanionSyncCodec.decodeRequest(try data(header)) == .corrupt)
            #expect(CompanionSyncCodec.decodeReceipt(try data(header)) == .corrupt)
        }
    }

    @Test func codecCompatibleFutureUnknownStateAndStrictBodiesNeverInferCompletion() throws {
        let request = try CompanionRequest(
            schemaVersion: 8, requestID: requestID, requestedAt: stamp, sourceID: sourceID)
        var requestJSON = try object(request)
        requestJSON["future"] = ["unknown": true]
        #expect(CompanionSyncCodec.decodeRequest(try data(requestJSON)) == .value(request))
        let receipt = try CompanionReceipt(
            schemaVersion: 8, sourceID: sourceID, state: .finished, requestIDs: [requestID],
            finishedGeneration: 0)
        #expect(
            CompanionSyncCodec.decodeReceipt(try CompanionSyncCodec.encode(receipt))
                == .value(receipt))
        #expect(
            CompanionSyncCodec.decodeReceipt(
                try data(["v": 4, "r": 1, "s": "future", "i": false, "q": "future"]))
                == .unsupportedControlState)
        #expect(throws: (any Error).self) {
            try CompanionReceipt(sourceID: sourceID, state: .unknown, requestIDs: [])
        }
        for state in ["accepted", "running", "finished", "cooldown"] {
            #expect(
                CompanionSyncCodec.decodeReceipt(try data(["v": 4, "r": 1, "s": state])) == .corrupt
            )
        }
        for state in [NSNull(), 1] as [Any] {
            #expect(
                CompanionSyncCodec.decodeReceipt(try data(["v": 4, "r": 1, "s": state])) == .corrupt
            )
        }
        requestJSON["i"] = "bad"
        #expect(CompanionSyncCodec.decodeRequest(try data(requestJSON)) == .corrupt)
        requestJSON.removeValue(forKey: "q")
        #expect(CompanionSyncCodec.decodeRequest(try data(requestJSON)) == .corrupt)
    }

    @Test func codecSortedEncodingIsDeterministicWithoutReorderingTerminalHistory() throws {
        let answer = try CompanionAnsweredRequest(requestID: requestID, outcome: .failed)
        let a = try CompanionReceipt(
            sourceID: sourceID, state: .accepted, requestIDs: [requestID, id(1)],
            answeredRequests: [answer])
        let b = try CompanionReceipt(
            sourceID: sourceID.lowercased(), state: .accepted,
            requestIDs: [id(1), requestID.lowercased(), id(1)], answeredRequests: [answer])
        let bytes = try CompanionSyncCodec.encode(a)
        #expect(try bytes == CompanionSyncCodec.encode(b))
        #expect(try bytes == CompanionSyncCodec.encode(a))
        let json = String(decoding: bytes, as: UTF8.self)
        #expect(
            json
                == "{\"a\":[{\"o\":\"failed\",\"q\":\"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb\"}],\"i\":\"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa\",\"q\":[\"00000000-0000-4000-8000-000000000001\",\"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb\"],\"r\":1,\"s\":\"accepted\",\"v\":4}"
        )
        #expect(CompanionSyncCodec.decodeReceipt(bytes) == .value(a))
    }

    @Test func receiptRequiredPrimitivesAndConditionalNullsCannotFabricateEvidence() throws {
        let accepted = try CompanionReceipt(sourceID: sourceID, state: .accepted, requestIDs: [])
        let running = try CompanionReceipt(
            sourceID: sourceID, state: .running, requestIDs: [], total: 1, completed: 0)
        let finished = try CompanionReceipt(
            sourceID: sourceID, state: .finished, requestIDs: [], finishedGeneration: 0)
        let cooldown = try CompanionReceipt(
            sourceID: sourceID, state: .cooldown, requestIDs: [], checkedAt: stamp,
            finishedGeneration: 0)
        for key in ["v", "r", "i", "s", "q"] {
            for value in [nil, NSNull()] as [Any?] {
                var json = try object(accepted)
                json[key] = value
                #expect(throws: (any Error).self) { try decode(CompanionReceipt.self, json) }
                #expect(CompanionSyncCodec.decodeReceipt(try data(json)) == .corrupt)
            }
        }
        for (model, key) in [
            (running, "n"), (running, "d"), (finished, "g"), (cooldown, "c"), (cooldown, "g"),
        ] {
            for value in [nil, NSNull()] as [Any?] {
                var json = try object(model)
                json[key] = value
                #expect(throws: (any Error).self) { try decode(CompanionReceipt.self, json) }
            }
        }
        for schema in [-1, 0, 1, 3] {
            #expect(throws: (any Error).self) {
                try CompanionReceipt(
                    schemaVersion: schema, sourceID: sourceID, state: .accepted, requestIDs: [])
            }
        }
        for minimum in [-1, 0] {
            #expect(throws: (any Error).self) {
                try CompanionReceipt(
                    minimumReaderVersion: minimum, sourceID: sourceID, state: .accepted,
                    requestIDs: [])
            }
        }
        #expect(throws: (any Error).self) {
            try CompanionReceipt(sourceID: "bad", state: .accepted, requestIDs: [])
        }
        var invalidDate = try object(accepted)
        invalidDate["t"] = Int64.max
        #expect(CompanionSyncCodec.decodeReceipt(try data(invalidDate)) == .corrupt)
    }

    @Test func completeReceiptShapeAndExtremeGenerationRoundtripWithoutInventedTime() throws {
        let landed = try CompanionLastLanded(providerID: "codex", accountID: "primary", live: true)
        let answer = try CompanionAnsweredRequest(
            requestID: requestID, outcome: .finished, finishedGeneration: Int64.max)
        let receipt = try CompanionReceipt(
            sourceID: sourceID, state: .finished, requestIDs: [requestID],
            answeredRequests: [answer],
            startedAt: stamp, finishedAt: stamp, checkedAt: stamp, total: 1, completed: 1,
            lastLanded: landed, finishedGeneration: Int64.max)
        try roundtrip(receipt)
        #expect(
            Set(try object(receipt).keys)
                == Set(["v", "r", "i", "s", "q", "a", "t", "f", "c", "n", "d", "l", "g"]))
        #expect(
            CompanionSyncCodec.decodeReceipt(try CompanionSyncCodec.encode(receipt))
                == .value(receipt))
        let failed = try decode(
            CompanionAnsweredRequest.self, ["q": requestID, "o": "failed", "g": NSNull()])
        #expect(failed.finishedGeneration == nil)
        for outcome in ["finished", "cooldown"] {
            #expect(throws: (any Error).self) {
                try decode(
                    CompanionAnsweredRequest.self, ["q": requestID, "o": outcome, "g": NSNull()])
            }
        }
    }

    @Test func canonicalMembershipAndUnknownAnswersCannotReplaceValidTerminalEvidence() throws {
        let first = try CompanionAnsweredRequest(
            requestID: requestID, outcome: .finished, finishedGeneration: 9)
        let latest = try CompanionAnsweredRequest(
            requestID: requestID.lowercased(), outcome: .cooldown, finishedGeneration: 10)
        let receipt = try CompanionReceipt(
            sourceID: sourceID, state: .accepted, requestIDs: [requestID, requestID.lowercased()],
            answeredRequests: [first, latest])
        #expect(receipt.requestIDs == [requestID.lowercased()])
        #expect(receipt.answeredRequests == [latest])
        var json = try object(receipt)
        json["a"] = [try object(first), ["q": requestID, "o": "futureOutcome", "g": 100]]
        #expect(try decode(CompanionReceipt.self, json).answeredRequests == [first])
        json["a"] = [["q": requestID, "o": "futureOutcome", "g": 100]]
        #expect(try decode(CompanionReceipt.self, json).answeredRequests.isEmpty)
    }

}
