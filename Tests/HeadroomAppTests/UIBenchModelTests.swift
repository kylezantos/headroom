import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// `--bench-ui`'s pure pieces: the command line, and the order statistics its reports and
/// JSON are built from.
struct UIBenchModelTests {
    private func parse(_ tail: String) throws -> UIBenchOptions {
        try UIBenchOptions.parse(["Headroom", "--bench-ui"] + tail.split(separator: " ").map(String.init))
    }

    // MARK: Command line

    @Test func parsesEveryFlagAfterTheSection() throws {
        let options = try parse("settings --scenario multi20 --pane apiSpend --runs 3 --json /tmp/out.json")
        #expect(options.section == .settings)
        #expect(options.scenario == .multi20)
        #expect(options.pane == .apiSpend)
        #expect(options.runs == 3)
        #expect(options.jsonPath == "/tmp/out.json")
        #expect(options.resolvedPanes == [.apiSpend])
    }

    /// Popover account layout plan (U8): `multi7` is the reported two-column case, and the
    /// account layout reaches every section so Compact can be measured too.
    @Test func parsesTheMultiSevenScenarioAndTheAccountLayout() throws {
        #expect(try parse("popover --scenario multi7").scenario == .multi7)
        let compact = try parse("scroll --account-layout compact")
        #expect(compact.accountLayout == .compact)
        // Compact still scrolls at the envelope, so the scroll default needs no override.
        #expect(compact.resolvedScenario == .multi20)
        #expect(try parse("all --account-layout standard").accountLayout == .standard)
        #expect(try parse("popover").accountLayout == nil)
        #expect(throws: UIBenchOptions.ParseError.unknownAccountLayout("dense")) {
            try parse("popover --account-layout dense")
        }
        #expect(throws: UIBenchOptions.ParseError.missingValue(flag: "--account-layout")) {
            try parse("popover --account-layout --runs 2")
        }
    }

    @Test func sectionDefaultsMatchWhatEachMeasures() throws {
        let popover = try parse("popover")
        #expect(popover.resolvedScenario == .multi5)
        #expect(popover.resolvedRuns == 12)
        // The list only scrolls past the 640pt cap, and ML1 was measured at the envelope.
        #expect(try parse("scroll").resolvedScenario == .multi20)
        #expect(try parse("scroll").resolvedRuns == 1)
        #expect(try parse("scene").resolvedScenario == .multi20)
        #expect(try parse("switch").resolvedRuns == 2)
        #expect(try parse("switch").animatedSwitches)
        #expect(try parse("switch --no-animated").animatedSwitches == false)
        // Without --pane, Settings opens on every stored pane in turn.
        #expect(try parse("settings").resolvedPanes == SettingsPane.allCases)
        #expect(try parse("popover --runs 0").resolvedRuns == 0)
    }

    @Test func rejectsWhatItCannotRun() {
        #expect(throws: UIBenchOptions.ParseError.missingSection) { try UIBenchOptions.parse(["Headroom", "--bench-ui"]) }
        #expect(throws: UIBenchOptions.ParseError.missingSection) { try parse("--runs 3") }
        #expect(throws: UIBenchOptions.ParseError.unknownSection("popvoer")) { try parse("popvoer") }
        #expect(throws: UIBenchOptions.ParseError.unknownScenario("multi4")) { try parse("popover --scenario multi4") }
        #expect(throws: UIBenchOptions.ParseError.unknownPane("display")) { try parse("settings --pane display") }
        #expect(throws: UIBenchOptions.ParseError.invalidRuns("-1")) { try parse("popover --runs -1") }
        #expect(throws: UIBenchOptions.ParseError.invalidRuns("two")) { try parse("popover --runs two") }
        #expect(throws: UIBenchOptions.ParseError.invalidRuns("0")) { try parse("scroll --runs 0") }
        #expect(throws: UIBenchOptions.ParseError.missingValue(flag: "--json")) { try parse("popover --json") }
        #expect(throws: UIBenchOptions.ParseError.missingValue(flag: "--scenario")) { try parse("popover --scenario --runs 2") }
        #expect(throws: UIBenchOptions.ParseError.unknownArgument("--tag")) { try parse("popover --tag x") }
    }

    @Test func rejectsFlagsTheSectionWouldIgnore() {
        #expect(throws: UIBenchOptions.ParseError.notApplicable(flag: "--pane", section: .popover)) {
            try parse("popover --pane general")
        }
        #expect(throws: UIBenchOptions.ParseError.notApplicable(flag: "--scenario", section: .all)) {
            try parse("all --scenario single")
        }
        #expect(throws: UIBenchOptions.ParseError.notApplicable(flag: "--runs", section: .counts)) {
            try parse("counts --runs 3")
        }
        #expect(throws: UIBenchOptions.ParseError.notApplicable(flag: "--no-animated", section: .settings)) {
            try parse("settings --no-animated")
        }
    }

    // MARK: Statistics

    @Test func medianAveragesTheMiddlePairAndP90IsNearestRank() throws {
        let odd = try #require(UIBenchStats([5, 1, 3]))
        #expect(odd.median == 3)
        #expect(odd.p90 == 5)
        #expect(odd.min == 1)
        #expect(odd.max == 5)

        let even = try #require(UIBenchStats([4, 1, 3, 2]))
        #expect(even.median == 2.5)
        #expect(even.p90 == 4)

        // Nearest rank: ceil(0.9 × 10) = the 9th smallest of ten.
        let ten = try #require(UIBenchStats(Array((1...10).map(Double.init).reversed())))
        #expect(ten.p90 == 9)
        #expect(ten.n == 10)

        let one = try #require(UIBenchStats([7]))
        #expect(one.median == 7)
        #expect(one.p90 == 7)
        #expect(UIBenchStats([]) == nil)
    }

    @Test func coldIsRunZeroAndWarmStatisticsCoverTheRest() {
        let metric = UIBenchMetric.coldWarm([100.12345, 10, 30, 20])
        #expect(metric.cold == 100.123)
        #expect(metric.warmMedian == 20)
        #expect(metric.warmP90 == 30)
        #expect(metric.warmN == 3)
        #expect(metric.value == nil)

        let coldOnly = UIBenchMetric.coldWarm([42])
        #expect(coldOnly.cold == 42)
        #expect(coldOnly.warmMedian == nil)
        #expect(coldOnly.warmN == nil)
    }

    @Test func bodyCountsCarryTheirTotal() {
        let counts = UIBenchBodyCount(["PopoverView": 1, "ProviderCardView": 4])
        #expect(counts.total == 5)
        #expect(counts.byView["ProviderCardView"] == 4)
    }
}
