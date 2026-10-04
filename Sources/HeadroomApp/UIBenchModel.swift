import Foundation
import HeadroomCore

/// The `--bench-ui` command line, parsed without touching AppKit so it can be unit-tested.
struct UIBenchOptions: Equatable {
    enum Section: String, CaseIterable {
        case popover, scroll, settings, `switch`, counts, scene, all
    }

    /// Store fixtures: the single-account demo, `multi-3`, `multi-5`, and the `multi-20`
    /// envelope (4 provider cards, 60 account sections).
    enum Scenario: String, CaseIterable {
        case single, multi3, multi5, multi20
    }

    enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingSection
        case unknownSection(String)
        case unknownScenario(String)
        case unknownPane(String)
        case invalidRuns(String)
        case missingValue(flag: String)
        case unknownArgument(String)
        case notApplicable(flag: String, section: Section)

        var description: String {
            switch self {
            case .missingSection:
                "Missing section after --bench-ui."
            case .unknownSection(let token):
                "Unknown section '\(token)'. Valid: \(Section.allCases.map(\.rawValue).joined(separator: ", "))."
            case .unknownScenario(let token):
                "Unknown scenario '\(token)'. Valid: \(Scenario.allCases.map(\.rawValue).joined(separator: ", "))."
            case .unknownPane(let token):
                "Unknown pane '\(token)'. Valid: \(SettingsPane.allCases.map(\.rawValue).joined(separator: ", "))."
            case .invalidRuns(let token):
                "Invalid --runs '\(token)'. Expected a whole number (at least 1 for scroll and switch)."
            case .missingValue(let flag):
                "\(flag) needs a value."
            case .unknownArgument(let token):
                "Unknown argument '\(token)'."
            case .notApplicable(let flag, let section):
                "\(flag) does not apply to the \(section.rawValue) section."
            }
        }
    }

    static let usage = """
        usage: Headroom --bench-ui <popover|scroll|settings|switch|counts|scene|all>
                        [--scenario single|multi3|multi5|multi20] [--pane <settings pane>]
                        [--runs n] [--json <path>] [--no-animated]
        """

    var section: Section
    var scenario: Scenario?
    var pane: SettingsPane?
    var runs: Int?
    var jsonPath: String?
    var animatedSwitches = true

    /// Everything after `--bench-ui`; arguments before it (the executable) are ignored.
    static func parse(_ arguments: [String]) throws -> UIBenchOptions {
        guard let flagIndex = arguments.firstIndex(of: "--bench-ui") else { throw ParseError.missingSection }
        var tokens = Array(arguments[(flagIndex + 1)...])
        guard let first = tokens.first, !first.hasPrefix("--") else { throw ParseError.missingSection }
        guard let section = Section(rawValue: first) else { throw ParseError.unknownSection(first) }
        tokens.removeFirst()
        var options = UIBenchOptions(section: section)

        func value(after flag: String) throws -> String {
            guard !tokens.isEmpty, !tokens[0].hasPrefix("--") else { throw ParseError.missingValue(flag: flag) }
            return tokens.removeFirst()
        }

        while !tokens.isEmpty {
            let flag = tokens.removeFirst()
            switch flag {
            case "--scenario":
                let token = try value(after: flag)
                guard let scenario = Scenario(rawValue: token) else { throw ParseError.unknownScenario(token) }
                guard section != .all else { throw ParseError.notApplicable(flag: flag, section: section) }
                options.scenario = scenario
            case "--pane":
                let token = try value(after: flag)
                guard let pane = SettingsPane(rawValue: token) else { throw ParseError.unknownPane(token) }
                guard section == .settings else { throw ParseError.notApplicable(flag: flag, section: section) }
                options.pane = pane
            case "--runs":
                let token = try value(after: flag)
                let floor = section == .scroll || section == .switch ? 1 : 0
                guard let runs = Int(token), runs >= floor else { throw ParseError.invalidRuns(token) }
                guard section != .counts, section != .scene else {
                    throw ParseError.notApplicable(flag: flag, section: section)
                }
                options.runs = runs
            case "--json":
                options.jsonPath = try value(after: flag)
            case "--no-animated":
                guard section == .switch || section == .all else {
                    throw ParseError.notApplicable(flag: flag, section: section)
                }
                options.animatedSwitches = false
            default:
                throw ParseError.unknownArgument(flag)
            }
        }
        return options
    }

    /// Scroll and the scene stand-in default to `multi20`: the list only scrolls past the
    /// 640pt cap, and ML1's cost was measured at the envelope. Everything else uses `multi5`.
    var resolvedScenario: Scenario {
        scenario ?? (section == .scroll || section == .scene ? .multi20 : .multi5)
    }

    /// Popover and Settings: warm opens after the cold run 0. Scroll: sweeps of ten steps.
    /// Switch: instant passes over every ordered pane pair.
    var resolvedRuns: Int {
        runs ?? {
            switch section {
            case .scroll: 1
            case .switch: 2
            default: 12
            }
        }()
    }

    var resolvedPanes: [SettingsPane] { pane.map { [$0] } ?? SettingsPane.allCases }
}

/// Order statistics over one metric's samples. The median averages the two middle values of
/// an even count; p90 is nearest-rank, so it is always one of the samples.
struct UIBenchStats: Equatable {
    let n: Int
    let median: Double
    let p90: Double
    let min: Double
    let max: Double

    init?(_ values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        n = count
        median = count % 2 == 1 ? sorted[count / 2] : (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        let rank = Int((0.9 * Double(count)).rounded(.up))
        p90 = sorted[Swift.max(0, Swift.min(count - 1, rank - 1))]
        min = sorted[0]
        max = sorted[count - 1]
    }

    var text: String {
        String(format: "med %7.2f  p90 %7.2f  min %7.2f  max %7.2f  (n=%d)", median, p90, min, max, n)
    }
}

// MARK: - Machine-readable report (`--json <path>`)

/// One number per scenario, shaped so two runs can be diffed: `value` for a single
/// observation, `cold` for run 0 of a process, and warm order statistics for the rest.
struct UIBenchMetric: Encodable, Equatable {
    var value: Double?
    var cold: Double?
    var warmMedian: Double?
    var warmP90: Double?
    var warmMin: Double?
    var warmMax: Double?
    var warmN: Int?

    /// Run 0 is the cold sample; the rest are warm.
    static func coldWarm(_ samples: [Double]) -> UIBenchMetric {
        coldWarm(cold: samples.first, warm: Array(samples.dropFirst()))
    }

    static func coldWarm(cold: Double?, warm samples: [Double]) -> UIBenchMetric {
        var metric = warm(samples)
        metric.cold = cold.map(rounded)
        return metric
    }

    static func warm(_ samples: [Double]) -> UIBenchMetric {
        guard let stats = UIBenchStats(samples) else { return UIBenchMetric() }
        return UIBenchMetric(
            warmMedian: rounded(stats.median),
            warmP90: rounded(stats.p90),
            warmMin: rounded(stats.min),
            warmMax: rounded(stats.max),
            warmN: stats.n
        )
    }

    static func single(_ value: Double) -> UIBenchMetric { UIBenchMetric(value: rounded(value)) }

    private static func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
}

struct UIBenchBodyCount: Encodable, Equatable {
    let total: Int
    let byView: [String: Int]

    init(_ counts: [String: Int]) {
        byView = counts
        total = counts.values.reduce(0, +)
    }
}

/// One post-open frame of the popover's frame-by-frame probe.
struct UIBenchFrame: Encodable, Equatable {
    let frame: Int
    let elapsedMs: Int
    let fittingHeight: Double
    let viewportHeight: Double?
    /// Scroll viewport heights the popover's `onScrollGeometryChange` reported this frame.
    let geometryReports: [Double]?
    let bodies: Int?
    let rootPasses: Int?
}

struct UIBenchResult: Encodable {
    let id: String
    let kind: String
    var scenario: String?
    var pane: String?
    var metrics: [String: UIBenchMetric] = [:]
    /// Nil when the binary was built without `HEADROOM_BENCH`.
    var bodies: [String: UIBenchBodyCount]?
    var frames: [UIBenchFrame]?
    var note: String?
}

struct UIBenchReport: Encodable {
    let schema = 1
    let section: String
    let arguments: [String]
    let bodyCountsAvailable: Bool
    let operatingSystem: String
    let startedAt: String
    var results: [UIBenchResult] = []

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
