import Foundation
import Testing
@testable import HeadroomCore

private struct StubAntigravitySource: AntigravityUsageSource {
    let captureResult: AntigravityCapture
    func capture() async -> AntigravityCapture { captureResult }
}

private final class SpyGPUCreditsSource: AntigravityGPUCreditsSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    let reading: AntigravityGPUCreditsReading

    init(reading: AntigravityGPUCreditsReading) {
        self.reading = reading
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func capture() async -> AntigravityGPUCreditsReading {
        lock.withLock { _calls += 1 }
        return reading
    }
}

@Suite(.serialized)
struct AntigravityGPUCreditsTests {
    private let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: - ColabUsageParser

    @Test func parsesStandardColabUsageOutput() {
        let raw = """
        Current balance: 2608.04 compute units
        Usage rate: 0.00/hr
        Active assignments: 0
        """
        let parsed = ColabUsageParser.parse(raw)
        #expect(parsed == AntigravityGPUCredits(balanceUnits: 2608.04, usageRatePerHour: 0, activeAssignments: 0))
    }

    @Test func parsesCommaFormattedBalanceAndActiveBurn() {
        let raw = """
        Current balance: 1,450.50 compute units
        Usage rate: 11.20/hr
        Active assignments: 1
        """
        let parsed = ColabUsageParser.parse(raw)
        #expect(parsed == AntigravityGPUCredits(balanceUnits: 1450.5, usageRatePerHour: 11.2, activeAssignments: 1))
    }

    @Test func parsesZeroBalanceAndRejectsGarbageOrNegative() {
        #expect(ColabUsageParser.parse("Current balance: 0.00 compute units")?.balanceUnits == 0)
        #expect(ColabUsageParser.parse("Current balance: -5.00 compute units") == nil)
        #expect(ColabUsageParser.parse("Error: not authenticated") == nil)
        #expect(ColabUsageParser.parse("") == nil)
    }

    // MARK: - ColabCLIGPUCreditsSource (injectable runner, zero real CLI spawns)

    @Test func cliSourcePrefersColabAndFallsBackToUvx() async {
        let capturedArgs = LockedBox<[String]>([])
        let colabSource = ColabCLIGPUCreditsSource(
            resolveExecutable: { $0 == "colab" ? "/opt/homebrew/bin/colab" : nil },
            runCommand: { exe, args, _, _ in
                capturedArgs.set([exe] + args)
                return .init(exitCode: 0, stdout: Data("Current balance: 2608.04 compute units\n".utf8))
            }
        )
        let r1 = await colabSource.capture()
        #expect(r1 == .balance(AntigravityGPUCredits(balanceUnits: 2608.04)))
        #expect(capturedArgs.get() == ["/opt/homebrew/bin/colab", "--auth=oauth2", "usage"])

        let uvxSource = ColabCLIGPUCreditsSource(
            resolveExecutable: { $0 == "uvx" ? "/opt/homebrew/bin/uvx" : nil },
            runCommand: { exe, args, _, _ in
                capturedArgs.set([exe] + args)
                return .init(exitCode: 0, stdout: Data("Current balance: 500.00 compute units\n".utf8))
            }
        )
        let r2 = await uvxSource.capture()
        #expect(r2 == .balance(AntigravityGPUCredits(balanceUnits: 500)))
        #expect(capturedArgs.get() == ["/opt/homebrew/bin/uvx", "--from", "google-colab-cli", "colab", "--auth=oauth2", "usage"])

        let failSource = ColabCLIGPUCreditsSource(
            resolveExecutable: { _ in "/opt/homebrew/bin/colab" },
            runCommand: { _, _, _, _ in .init(exitCode: 1, stdout: Data()) }
        )
        #expect(await failSource.capture() == .unavailable)
    }

    // MARK: - 3-Month Tank & Refill Date Math

    @Test func threeMonthTankCalculatesRemainingPercentAndClamps() {
        let now = date(2026, 11, 25)
        let win = AntigravityProvider.gpuCreditsWindow(
            credits: AntigravityGPUCredits(balanceUnits: 2_608.04),
            tier: .aiUltra,
            refillDay: 1,
            now: now,
            calendar: utc
        )
        #expect(win.kind == AntigravityGPUCreditsWindow.windowKind)
        #expect(abs(win.percentRemaining - (2_608.04 / 6_000.0 * 100.0)) < 0.01)
        #expect(win.resetSchedule.deadline == date(2026, 12, 1, 0))

        // Over 3-month tank clamps to 100% remaining (0% utilization)
        let full = AntigravityProvider.gpuCreditsWindow(
            credits: AntigravityGPUCredits(balanceUnits: 7_500),
            tier: .aiUltra,
            refillDay: nil,
            now: now,
            calendar: utc
        )
        #expect(full.utilization == 0)
        #expect(full.resetSchedule == .unresolved(.absent))
    }

    @Test func nextMonthlyRefillDateClampsShortMonthsAndRollsForward() {
        // Nov 25 -> day 28 is still this month
        #expect(
            AntigravityGPUCreditsWindow.nextMonthlyRefillDate(day: 28, after: date(2026, 11, 25), calendar: utc)
                == date(2026, 11, 28, 0)
        )
        // Jan 31 noon -> next month is Feb 2026 (28 days), clamped to Feb 28
        #expect(
            AntigravityGPUCreditsWindow.nextMonthlyRefillDate(day: 31, after: date(2026, 1, 31), calendar: utc)
                == date(2026, 2, 28, 0)
        )
        // Invalid days return nil
        #expect(AntigravityGPUCreditsWindow.nextMonthlyRefillDate(day: 0, after: date(2026, 11, 25), calendar: utc) == nil)
        #expect(AntigravityGPUCreditsWindow.nextMonthlyRefillDate(day: 32, after: date(2026, 11, 25), calendar: utc) == nil)
    }

    // MARK: - Provider & Visibility Filtering

    @Test func providerNeverCallsGPUSourceWhenOffAndFailsOpenWhenUnavailable() async {
        let now = date(2026, 11, 25)
        let usage = AntigravityUsage(
            buckets: [
                AntigravityBucket(pool: .gemini, window: .weekly, remainingFraction: 0.63, resetsAt: date(2026, 11, 30)),
                AntigravityBucket(pool: .claudeAndGPT, window: .weekly, remainingFraction: 1.0, resetsAt: nil),
            ],
            credits: 0
        )

        let spyOff = SpyGPUCreditsSource(reading: .balance(AntigravityGPUCredits(balanceUnits: 2_608)))
        let pOff = AntigravityProvider(
            source: StubAntigravitySource(captureResult: .usage(usage)),
            gpuCreditsSource: spyOff,
            gpuCreditsMode: { .off },
            now: { now }
        )
        let snapOff = await pOff.fetchSnapshot()
        #expect(spyOff.calls == 0)
        #expect(snapOff.windows.count == 2)

        let spyFail = SpyGPUCreditsSource(reading: .unavailable)
        let pFail = AntigravityProvider(
            source: StubAntigravitySource(captureResult: .usage(usage)),
            gpuCreditsSource: spyFail,
            gpuCreditsMode: { .replaceOtherWeekly },
            now: { now }
        )
        let snapFail = await pFail.fetchSnapshot()
        #expect(spyFail.calls == 1)
        #expect(snapFail.freshness == .live)
        // Unavailable GPU credits falls back to showing Other · Weekly
        let visibleFail = AntigravityFiveHourWindows.visibleSnapshot(
            snapFail, showsFiveHourWindows: false, gpuCreditsMode: .replaceOtherWeekly
        )
        #expect(visibleFail.windows.map(\.kind) == [
            AntigravityProvider.windowKind(.gemini, .weekly),
            AntigravityProvider.windowKind(.claudeAndGPT, .weekly),
        ])
    }

    @Test func replaceOtherWeeklyAndAddModesFilterConsistently() async {
        let now = date(2026, 11, 25)
        let usage = AntigravityUsage(
            buckets: [
                AntigravityBucket(pool: .gemini, window: .weekly, remainingFraction: 0.63, resetsAt: date(2026, 11, 30)),
                AntigravityBucket(pool: .claudeAndGPT, window: .weekly, remainingFraction: 1.0, resetsAt: nil),
            ],
            credits: 0
        )
        let spy = SpyGPUCreditsSource(reading: .balance(AntigravityGPUCredits(balanceUnits: 2_608.04)))
        let provider = AntigravityProvider(
            source: StubAntigravitySource(captureResult: .usage(usage)),
            gpuCreditsSource: spy,
            gpuCreditsMode: { .replaceOtherWeekly },
            colabTier: { .aiUltra },
            gpuCreditsRefillDay: { 1 },
            calendar: utc,
            now: { now }
        )
        let raw = await provider.fetchSnapshot()
        #expect(raw.windows.count == 3)

        let replaced = AntigravityFiveHourWindows.visibleSnapshot(
            raw, showsFiveHourWindows: false, gpuCreditsMode: .replaceOtherWeekly
        )
        #expect(replaced.windows.map(\.kind) == [
            AntigravityProvider.windowKind(.gemini, .weekly),
            AntigravityGPUCreditsWindow.windowKind,
        ])

        let added = AntigravityFiveHourWindows.visibleSnapshot(
            raw, showsFiveHourWindows: false, gpuCreditsMode: .add
        )
        #expect(added.windows.map(\.kind) == [
            AntigravityProvider.windowKind(.gemini, .weekly),
            AntigravityProvider.windowKind(.claudeAndGPT, .weekly),
            AntigravityGPUCreditsWindow.windowKind,
        ])

        let hidden = AntigravityFiveHourWindows.visibleSnapshot(
            raw, showsFiveHourWindows: false, gpuCreditsMode: .off
        )
        #expect(hidden.windows.map(\.kind) == [
            AntigravityProvider.windowKind(.gemini, .weekly),
            AntigravityProvider.windowKind(.claudeAndGPT, .weekly),
        ])

        // Compact row picks up GPU short label cleanly in Replace mode
        let compact = CompactAccountRowRecipe(
            snapshot: raw,
            meterStyle: .default,
            percentageMode: .remaining,
            now: now,
            requiresStandardSection: false,
            showsCodexSparkCounters: false,
            showsAntigravityFiveHourWindows: false,
            antigravityGPUCreditsMode: .replaceOtherWeekly
        )
        #expect(compact.shownWindows.map { CompactAccountRowRecipe.shortLabel(for: $0.window.kind) } == ["Gemini wk", "GPU"])
    }

    // MARK: - Preferences Round-Trip

    @Test func preferencesDefaultOffAndPersistRoundTrip() {
        let suite = "headroom.test.gpucredits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.antigravityGPUCreditsMode == .off)
        #expect(prefs.antigravityColabTier == .aiUltra)
        #expect(prefs.antigravityGPUCreditsRefillDay == nil)

        prefs.antigravityGPUCreditsMode = .replaceOtherWeekly
        prefs.antigravityColabTier = .proPlus
        prefs.antigravityGPUCreditsRefillDay = 15

        #expect(prefs.antigravityGPUCreditsMode == .replaceOtherWeekly)
        #expect(prefs.antigravityColabTier == .proPlus)
        #expect(prefs.antigravityGPUCreditsRefillDay == 15)

        prefs.antigravityGPUCreditsRefillDay = nil
        #expect(prefs.antigravityGPUCreditsRefillDay == nil)
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ next: Value) { lock.lock(); defer { lock.unlock() }; value = next }
}
