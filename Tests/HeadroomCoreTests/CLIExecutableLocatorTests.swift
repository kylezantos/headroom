import Foundation
import Testing
@testable import HeadroomCore

struct CLIExecutableLocatorTests {
    @Test func validPersistedHintAvoidsLoginShellAndIsRevalidated() async {
        let hints = TestExecutableHintStore(["claude": "/persisted/claude"])
        let shell = ShellSearchRecorder(result: .completed(candidates: ["/shell/claude"]))
        let validation = CandidateValidationRecorder(statuses: ["/persisted/claude": .executable])
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: hints,
            shellSearch: { await shell.search() },
            validate: { validation.status(for: $0) }
        )

        #expect(await locator.locate() == .available(path: "/persisted/claude", source: .persistedHint))
        #expect(await shell.count == 0)
        #expect(validation.paths == ["/persisted/claude"])
    }

    @Test func invalidatedHintRediscoveriesOnceAndCachesReplacement() async {
        let hints = TestExecutableHintStore(["claude": "/moved/claude"])
        let shell = ShellSearchRecorder(result: .completed(candidates: ["/new/claude"]))
        let validation = CandidateValidationRecorder(statuses: [
            "/moved/claude": .missing,
            "/new/claude": .executable,
        ])
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: hints,
            shellSearch: { await shell.search() },
            validate: { validation.status(for: $0) }
        )

        #expect(await locator.locate() == .available(path: "/new/claude", source: .loginShell))
        #expect(await locator.locate() == .available(path: "/new/claude", source: .memoryHint))
        #expect(await shell.count == 1)
        #expect(hints.hint(for: "claude") == "/new/claude")
        #expect(await locator.recentDiagnosticEvents().map(\.category) == [
            .hintInvalidated,
            .loginShellResolved,
            .memoryHintValidated,
        ])
    }

    @Test func invalidatedHintIsInconclusiveForOneGenerationThenCanConfirmAbsence() async {
        let hints = TestExecutableHintStore(["claude": "/moved/claude"])
        let shell = ShellSearchRecorder(result: .completed(candidates: []))
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: hints,
            shellSearch: { await shell.search() },
            validate: { _ in .missing }
        )

        let firstGeneration = UUID()
        let secondGeneration = UUID()
        #expect(await CLIExecutableRefreshContext.$generation.withValue(firstGeneration) {
            await locator.locate()
        } == .inconclusive(.invalidatedHint))
        #expect(await CLIExecutableRefreshContext.$generation.withValue(firstGeneration) {
            await locator.locate()
        } == .inconclusive(.invalidatedHint))
        #expect(await CLIExecutableRefreshContext.$generation.withValue(secondGeneration) {
            await locator.locate()
        } == .confirmedAbsent)
        #expect(await shell.count == 2)
    }

    @Test func sequentialNegativeLookupsShareOneSearchWithinRefreshGenerationEvenAboveAccountCap() async {
        let shell = ShellSearchRecorder(result: .completed(candidates: []))
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { _ in .missing }
        )
        let generation = UUID()

        for _ in 0..<7 {
            #expect(await CLIExecutableRefreshContext.$generation.withValue(generation) {
                await locator.locate()
            } == .confirmedAbsent)
        }

        #expect(await shell.count == 1)
    }

    @Test func adjacentRefreshGenerationsSearchAgainRegardlessOfElapsedTime() async {
        let shell = ShellSearchRecorder(result: .completed(candidates: []))
        let clock = MutableLocatorClock(Date(timeIntervalSince1970: 1_000))
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { _ in .missing },
            now: { clock.now }
        )

        #expect(await CLIExecutableRefreshContext.$generation.withValue(UUID()) {
            await locator.locate()
        } == .confirmedAbsent)
        clock.advance(by: 60 * 60)
        #expect(await CLIExecutableRefreshContext.$generation.withValue(UUID()) {
            await locator.locate()
        } == .confirmedAbsent)

        #expect(await shell.count == 2)
    }

    @Test func unscopedNegativeLookupsDoNotPersistWithoutARefreshGeneration() async {
        let shell = ShellSearchRecorder(result: .completed(candidates: []))
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { _ in .missing }
        )

        #expect(await locator.locate() == .confirmedAbsent)
        #expect(await locator.locate() == .confirmedAbsent)
        #expect(await shell.count == 2)
    }

    @Test func forceRefreshFindsNewInstallAndRejectsOlderNegativePublish() async {
        let shell = ForceRaceShellSearch()
        let hints = TestExecutableHintStore()
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: hints,
            shellSearch: { await shell.search() },
            validate: { $0 == "/new/claude" ? .executable : .missing }
        )
        let generation = UUID()
        let stale = Task {
            await CLIExecutableRefreshContext.$generation.withValue(generation) {
                await locator.locate()
            }
        }
        while await shell.count == 0 { await Task.yield() }

        let forced = await CLIExecutableRefreshContext.$generation.withValue(generation) {
            await locator.locate(forceRefresh: true)
        }
        await shell.resumeStaleSearch()

        #expect(forced == .available(path: "/new/claude", source: .loginShell))
        #expect(await stale.value == .available(path: "/new/claude", source: .memoryHint))
        #expect(hints.hint(for: "claude") == "/new/claude")
        #expect(await CLIExecutableRefreshContext.$generation.withValue(generation) {
            await locator.locate()
        } == .available(path: "/new/claude", source: .memoryHint))
        #expect(await shell.count == 2)
    }

    @Test func staleGenerationCompletionJoinsReplacementWithoutStartingThirdSearch() async {
        let shell = CrossGenerationForceRaceShellSearch()
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { $0 == "/new/claude" ? .executable : .missing }
        )
        let stale = Task {
            await CLIExecutableRefreshContext.$generation.withValue(UUID()) {
                await locator.locate()
            }
        }
        while await shell.count < 1 { await Task.yield() }

        let replacement = Task {
            await CLIExecutableRefreshContext.$generation.withValue(UUID()) {
                await locator.locate(forceRefresh: true)
            }
        }
        while await shell.count < 2 { await Task.yield() }
        await shell.resumeSearch(1, with: .completed(candidates: []))
        for _ in 0..<20 { await Task.yield() }

        let countBeforeReplacementCompletes = await shell.count
        #expect(countBeforeReplacementCompletes == 2)
        if countBeforeReplacementCompletes > 2 {
            await shell.resumeSearch(3, with: .completed(candidates: ["/new/claude"]))
        }
        await shell.resumeSearch(2, with: .completed(candidates: ["/new/claude"]))
        #expect(await stale.value == .available(path: "/new/claude", source: .loginShell))
        #expect(await replacement.value == .available(path: "/new/claude", source: .loginShell))
        #expect(await shell.count == 2)
    }

    @Test func launchRaceAppliesToEverySearchStartedInInvalidationGeneration() async {
        let shell = LaunchRaceStraddleShellSearch()
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { $0 == "/old/claude" ? .executable : .missing }
        )
        let initialGeneration = UUID()
        let started = await CLIExecutableRefreshContext.$generation.withValue(initialGeneration) {
            let initial = await locator.locate()
            await locator.invalidate(path: "/old/claude", reason: .launchNotFound)
            let first = await locator.locate()
            let straddling = Task {
                await locator.locate()
            }
            while await shell.count < 3 { await Task.yield() }
            return (initial, first, straddling)
        }
        let laterGeneration = Task {
            await CLIExecutableRefreshContext.$generation.withValue(UUID()) {
                await locator.locate()
            }
        }
        for _ in 0..<20 { await Task.yield() }
        await shell.resumeSearch(3)

        #expect(started.0 == .available(path: "/old/claude", source: .loginShell))
        #expect(started.1 == .inconclusive(.launchRace))
        #expect(await started.2.value == .inconclusive(.launchRace))
        #expect(await laterGeneration.value == .confirmedAbsent)
        #expect(await shell.count == 4)
    }

    @Test func onlyCompletedSearchWithoutCandidatesConfirmsAbsence() async {
        for result in [
            CLIExecutableShellResult.timedOut,
            .spawnFailed,
            .invalidOutput,
        ] {
            let locator = makeLocator(shellResult: result)
            guard case .inconclusive = await locator.locate() else {
                Issue.record("Expected \(result) to remain inconclusive")
                continue
            }
        }

        let absent = makeLocator(shellResult: .completed(candidates: []))
        #expect(await absent.locate() == .confirmedAbsent)
    }

    @Test func inaccessibleCandidateIsInconclusiveButMissingFallbackConfirmsAbsence() async {
        let inaccessible = makeLocator(
            shellResult: .completed(candidates: ["/private/claude"]),
            validation: ["/private/claude": .inaccessible]
        )
        #expect(await inaccessible.locate() == .inconclusive(.inaccessibleCandidate))

        let absent = makeLocator(
            shellResult: .completed(candidates: []),
            fallbackPaths: ["/opt/homebrew/bin/claude"],
            validation: ["/opt/homebrew/bin/claude": .missing]
        )
        #expect(await absent.locate() == .confirmedAbsent)

        let nonPathShellCandidate = makeLocator(
            shellResult: .completed(candidates: ["claude"]),
            validation: ["claude": .missing]
        )
        #expect(await nonPathShellCandidate.locate() == .confirmedAbsent)

        let inaccessibleFallback = makeLocator(
            shellResult: .completed(candidates: []),
            fallbackPaths: ["/opt/homebrew/bin/claude"],
            validation: ["/opt/homebrew/bin/claude": .inaccessible]
        )
        #expect(await inaccessibleFallback.locate() == .inconclusive(.inaccessibleCandidate))
    }

    @Test func fallbackCanRecoverFromLoginShellFailure() async {
        let locator = makeLocator(
            shellResult: .timedOut,
            fallbackPaths: ["/opt/homebrew/bin/claude"],
            validation: ["/opt/homebrew/bin/claude": .executable]
        )

        #expect(await locator.locate() == .available(path: "/opt/homebrew/bin/claude", source: .fallback))
        #expect(await locator.recentDiagnosticEvents().last?.category == .fallbackResolved)
    }

    @Test func concurrentCallersShareDiscoveryAndCancelledWaiterDoesNotCancelIt() async {
        let shell = SuspendedShellSearch()
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { $0 == "/shell/claude" ? .executable : .missing }
        )

        let cancelled = Task { await locator.locate() }
        let surviving = Task { await locator.locate() }
        while await shell.count == 0 { await Task.yield() }
        cancelled.cancel()
        await shell.resume(with: .completed(candidates: ["/shell/claude"]))

        #expect(await surviving.value == .available(path: "/shell/claude", source: .loginShell))
        #expect(await shell.count == 1)
    }

    @Test func invalidationAllowsLaterCycleToFindNewInstall() async {
        let shell = ShellSearchRecorder(result: .completed(candidates: ["/old/claude"]))
        let validation = CandidateValidationRecorder(statuses: [
            "/old/claude": .executable,
            "/new/claude": .executable,
        ])
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { validation.status(for: $0) }
        )
        #expect(await locator.locate() == .available(path: "/old/claude", source: .loginShell))

        await locator.invalidate(path: "/old/claude", reason: .launchNotFound)
        await shell.setResult(.completed(candidates: ["/new/claude"]))

        #expect(await locator.locate() == .available(path: "/new/claude", source: .loginShell))
        #expect(await shell.count == 2)
        #expect(await locator.recentDiagnosticEvents().map(\.category).contains(.launchRace))
    }

    @Test func invalidationDuringDiscoveryRejectsTheStaleResult() async {
        let shell = InvalidationRaceShellSearch()
        let hints = TestExecutableHintStore()
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: hints,
            shellSearch: { await shell.search() },
            validate: { _ in .executable }
        )

        #expect(await locator.locate() == .available(path: "/old/claude", source: .loginShell))

        let refresh = Task { await locator.locate(forceRefresh: true) }
        while await shell.count < 2 { await Task.yield() }
        await locator.invalidate(path: "/old/claude", reason: .launchNotFound)
        await shell.resumeStaleSearch()

        #expect(await refresh.value == .available(path: "/new/claude", source: .loginShell))
        #expect(await shell.count == 3)
        #expect(hints.hint(for: "claude") == "/new/claude")
        #expect(await locator.locate() == .available(path: "/new/claude", source: .memoryHint))
    }

    @Test func diagnosticsDistinguishValidHintTimeoutAndSupportedLocationMiss() async {
        let clock = Date(timeIntervalSince1970: 20_000)
        let hinted = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(["claude": "/hint/claude"]),
            shellSearch: { .completed(candidates: []) },
            validate: { $0 == "/hint/claude" ? .executable : .missing },
            now: { clock }
        )
        _ = await hinted.locate()
        #expect(await hinted.recentDiagnosticEvents() == [
            CLIExecutableDiagnosticEvent(category: .persistedHintValidated, observedAt: clock),
        ])

        let timedOut = makeLocator(shellResult: .timedOut)
        _ = await timedOut.locate()
        #expect(await timedOut.recentDiagnosticEvents().last?.category == .shellTimeout)

        let absent = makeLocator(shellResult: .completed(candidates: []))
        _ = await absent.locate()
        #expect(await absent.recentDiagnosticEvents().last?.category == .supportedLocationMiss)
    }

    private func makeLocator(
        shellResult: CLIExecutableShellResult,
        fallbackPaths: [String] = [],
        validation: [String: CLIExecutableCandidateStatus] = [:]
    ) -> CLIExecutableLocator {
        CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: fallbackPaths,
            hintStore: TestExecutableHintStore(),
            shellSearch: { shellResult },
            validate: { validation[$0] ?? .missing }
        )
    }
}

private final class TestExecutableHintStore: CLIExecutableHintStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var hints: [String: String]

    init(_ hints: [String: String] = [:]) { self.hints = hints }

    func hint(for executableName: String) -> String? {
        lock.withLock { hints[executableName] }
    }

    func setHint(_ path: String?, for executableName: String) {
        lock.withLock { hints[executableName] = path }
    }
}

private actor ShellSearchRecorder {
    private(set) var count = 0
    private var result: CLIExecutableShellResult

    init(result: CLIExecutableShellResult) { self.result = result }

    func search() -> CLIExecutableShellResult {
        count += 1
        return result
    }

    func setResult(_ result: CLIExecutableShellResult) { self.result = result }
}

private actor SuspendedShellSearch {
    private(set) var count = 0
    private var continuation: CheckedContinuation<CLIExecutableShellResult, Never>?

    func search() async -> CLIExecutableShellResult {
        count += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume(with result: CLIExecutableShellResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor InvalidationRaceShellSearch {
    private(set) var count = 0
    private var staleContinuation: CheckedContinuation<CLIExecutableShellResult, Never>?

    func search() async -> CLIExecutableShellResult {
        count += 1
        switch count {
        case 1:
            return .completed(candidates: ["/old/claude"])
        case 2:
            return await withCheckedContinuation { staleContinuation = $0 }
        default:
            return .completed(candidates: ["/new/claude"])
        }
    }

    func resumeStaleSearch() {
        staleContinuation?.resume(returning: .completed(candidates: ["/old/claude"]))
        staleContinuation = nil
    }
}

private actor ForceRaceShellSearch {
    private(set) var count = 0
    private var staleContinuation: CheckedContinuation<CLIExecutableShellResult, Never>?

    func search() async -> CLIExecutableShellResult {
        count += 1
        if count == 1 {
            return await withCheckedContinuation { staleContinuation = $0 }
        }
        return .completed(candidates: ["/new/claude"])
    }

    func resumeStaleSearch() {
        staleContinuation?.resume(returning: .completed(candidates: []))
        staleContinuation = nil
    }
}

private actor CrossGenerationForceRaceShellSearch {
    private(set) var count = 0
    private var continuations: [Int: CheckedContinuation<CLIExecutableShellResult, Never>] = [:]

    func search() async -> CLIExecutableShellResult {
        count += 1
        let search = count
        return await withCheckedContinuation { continuations[search] = $0 }
    }

    func resumeSearch(_ search: Int, with result: CLIExecutableShellResult) {
        continuations.removeValue(forKey: search)?.resume(returning: result)
    }
}

private actor LaunchRaceStraddleShellSearch {
    private(set) var count = 0
    private var continuations: [Int: CheckedContinuation<CLIExecutableShellResult, Never>] = [:]

    func search() async -> CLIExecutableShellResult {
        count += 1
        switch count {
        case 1:
            return .completed(candidates: ["/old/claude"])
        case 2:
            return .completed(candidates: [])
        case 3:
            return await withCheckedContinuation { continuations[3] = $0 }
        default:
            return .completed(candidates: [])
        }
    }

    func resumeSearch(_ search: Int) {
        continuations.removeValue(forKey: search)?.resume(returning: .completed(candidates: []))
    }
}

private final class MutableLocatorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    var now: Date { lock.withLock { value } }

    func advance(by interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

private final class CandidateValidationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let statuses: [String: CLIExecutableCandidateStatus]
    private var recordedPaths: [String] = []

    init(statuses: [String: CLIExecutableCandidateStatus]) { self.statuses = statuses }

    var paths: [String] { lock.withLock { recordedPaths } }

    func status(for path: String) -> CLIExecutableCandidateStatus {
        lock.withLock {
            recordedPaths.append(path)
            return statuses[path] ?? .missing
        }
    }
}
