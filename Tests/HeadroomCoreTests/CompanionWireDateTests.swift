import Foundation
import Testing
@testable import HeadroomCore

@Suite
struct CompanionWireDateTests {
    @Test(arguments: [(0.0, Int64(0)), (0.75, 0), (1.25, 1), (-0.1, -1), (-1.25, -2), (978_307_200.75, 978_307_200)])
    func fractionalDatesFloorToSignedUnixSeconds(interval: Double, expected: Int64) throws {
        let source = Date(timeIntervalSince1970: interval)
        let value = try #require(CompanionWireDate(date: source))
        #expect(value.epochSeconds == expected)
        #expect(value.date.timeIntervalSince1970 == Double(expected))
    }

    @Test func canonicalizationIsIdempotentAndLeavesSourceFractionsUntouched() throws {
        let source = Date(timeIntervalSince1970: -1.25)
        let originalInterval = source.timeIntervalSince1970
        let canonical = try #require(CompanionWireDate.canonicalize(source))
        #expect(canonical.timeIntervalSince1970 == -2)
        #expect(CompanionWireDate.canonicalize(canonical) == canonical)
        #expect(CompanionWireDate(date: canonical)?.date == canonical)
        #expect(source.timeIntervalSince1970 == originalInterval)
        #expect(source.timeIntervalSince1970 == -1.25)
    }

    @Test(arguments: [Int64(0), 1, -1, 978_307_200, 1_790_355_600, 1 << 53, -(1 << 53), Int64.min])
    func representableSignedSecondsRoundTripAndEncodeAsIntegerJSON(seconds: Int64) throws {
        let value = try #require(CompanionWireDate(epochSeconds: seconds))
        #expect(CompanionWireDate(date: value.date) == value)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        #expect(String(data: data, encoding: .utf8) == String(seconds))
        #expect(try JSONDecoder().decode(CompanionWireDate.self, from: data) == value)
    }

    @Test func unrepresentableWireSecondsNeverRoundToAnotherInteger() {
        #expect(CompanionWireDate(epochSeconds: Int64.max) == nil)
        #expect(CompanionWireDate(epochSeconds: (1 << 53) + 1) == nil)
        // Date's internal 2001 reference offset can lose this otherwise exact Double integer.
        #expect(CompanionWireDate(epochSeconds: -(1 << 53) + 1) == nil)
    }

    @Test func nonfiniteAndOverflowDatesRejectWithoutTrappingOrFallback() {
        for interval in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude,
                         -Double.greatestFiniteMagnitude, Double(Int64.max), Double(Int64.min).nextDown] {
            let source = Date(timeIntervalSince1970: interval)
            #expect(CompanionWireDate(date: source) == nil)
            #expect(CompanionWireDate.canonicalize(source) == nil)
        }
    }

    @Test(arguments: ["\"1\"", "true", "null", "[]", "{}", "1.25", "9223372036854775807", "9223372036854775808", "9007199254740993", "1e200"])
    func invalidPrimitiveFractionOverflowOrUnrepresentableEpochRejects(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CompanionWireDate.self, from: Data(json.utf8))
        }
    }
}
