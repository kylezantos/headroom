import Foundation
import Testing
@testable import HeadroomCore

@Suite
struct UsageDisplayValueTests {
    @Test func actualWindowSubtractionDoesNotLoseTheDecimalCriticalTie() throws {
        let window = UsageWindow(kind: .fiveHour, utilization: 84.95, resetsAt: Date(timeIntervalSince1970: 1234))
        #expect(window.percentRemaining < 15.05)
        let display = try #require(UsageDisplayValue(window: window))
        #expect(display.percentRemaining == 15.1)
        #expect(display.severity == .low)
        #expect(display.sourceUtilization == 84.95)
        #expect(UsageDisplayValue(window: UsageWindow(kind: .weekly, utilization: 84.96, resetsAt: Date(timeIntervalSince1970: 1234)))?.percentRemaining == 15.0)
    }

    @Test(arguments: [
        (15.04, 15.0, UsageSeverity.critical),
        (15.05, 15.1, .low),
        (50.04, 50.0, .low),
        (50.05, 50.1, .healthy),
        (15.0, 15.0, .critical),
        (50.0, 50.0, .low),
        (0.05, 0.1, .critical),
        (99.95, 100.0, .healthy)
    ])
    func directRemainingRoundsTiesAwayAndClassifiesTheNormalizedValue(input: Double, expected: Double, severity: UsageSeverity) throws {
        let display = try #require(UsageDisplayValue(percentRemaining: input))
        #expect(display.percentRemaining == expected)
        #expect(display.severity == severity)
        #expect(display.sourceUtilization == nil)
    }

    @Test(arguments: [(84.95, 15.1), (84.96, 15.0), (49.95, 50.1), (49.96, 50.0), (99.95, 0.1), (0.05, 100.0)])
    func sourceDecimalComplementRoundsBeforeSeverity(utilization: Double, expected: Double) throws {
        let display = try #require(UsageDisplayValue(utilization: utilization))
        #expect(display.percentRemaining == expected)
        #expect(display.severity == UsageSeverity(percentRemaining: expected))
        #expect(display.sourceUtilization == utilization)
    }

    @Test func finiteExtremesClampWithoutOverflowingDecimal() throws {
        for (input, remaining) in [(-Double.greatestFiniteMagnitude, 0.0), (-1.0, 0.0), (101.0, 100.0), (Double.greatestFiniteMagnitude, 100.0)] {
            #expect(UsageDisplayValue(percentRemaining: input)?.percentRemaining == remaining)
            let source = try #require(UsageDisplayValue(utilization: input))
            #expect(source.percentRemaining == 100 - remaining)
            #expect(source.sourceUtilization == input)
        }
        #expect(UsageDisplayValue(percentRemaining: Double.leastNonzeroMagnitude)?.percentRemaining == 0)
        #expect(UsageDisplayValue(utilization: Double.leastNonzeroMagnitude)?.percentRemaining == 100)
    }

    @Test func adjacentRepresentableValuesAreNotPromotedByAnEpsilon() {
        #expect(UsageDisplayValue(percentRemaining: Double(15.05).nextDown)?.percentRemaining == 15.0)
        #expect(UsageDisplayValue(percentRemaining: Double(15.05).nextUp)?.percentRemaining == 15.1)
        #expect(UsageDisplayValue(utilization: Double(84.95).nextUp)?.percentRemaining == 15.0)
        #expect(UsageDisplayValue(utilization: Double(84.95).nextDown)?.percentRemaining == 15.1)
        #expect(UsageDisplayValue(percentRemaining: Double(50.05).nextDown)?.percentRemaining == 50.0)
        #expect(UsageDisplayValue(percentRemaining: Double(50.05).nextUp)?.percentRemaining == 50.1)
    }

    @Test func everyDisplayedTenthAndRoundedBoundaryIsIdempotent() throws {
        for tenth in 0...1000 {
            let value = Double(tenth) / 10
            let once = try #require(UsageDisplayValue(percentRemaining: value))
            let twice = try #require(UsageDisplayValue(percentRemaining: once.percentRemaining))
            #expect(once.percentRemaining == value)
            #expect(twice == once)
        }
        for boundary in [15.04, 15.05, 50.04, 50.05, -1, 101] {
            let once = try #require(UsageDisplayValue(percentRemaining: boundary))
            var repeated = once
            for _ in 0..<10 {
                repeated = try #require(UsageDisplayValue(percentRemaining: repeated.percentRemaining))
                #expect(repeated == once)
            }
        }
    }

    @Test func normalizationPreservesSourcePrecisionAndProvenance() throws {
        let window = UsageWindow(kind: .weekly, utilization: 84.95123456789012,
                                 resetsAt: Date(timeIntervalSince1970: 1234), resetLabel: "source provenance")
        let original = window
        let display = try #require(UsageDisplayValue(window: window))
        #expect(display.percentRemaining == 15.0)
        #expect(display.sourceUtilization == window.utilization)
        #expect(window == original)
        #expect(window.utilization == 84.95123456789012)
        #expect(window.resetLabel == "source provenance")
    }

    @Test func nonfiniteInputsNeverFabricateAvailabilityOrZero() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            #expect(UsageDisplayValue(percentRemaining: value) == nil)
            #expect(UsageDisplayValue(utilization: value) == nil)
            let window = UsageWindow(kind: .fiveHour, utilization: value, resetsAt: Date(timeIntervalSince1970: 1234))
            #expect(UsageDisplayValue(window: window) == nil)
        }
        #expect(UsageDisplayValue(percentRemaining: 100)?.sourceUtilization == nil)
        #expect(UsageDisplayValue(utilization: 0)?.sourceUtilization == 0)
    }
}
