import Foundation

public enum CLIExecutableLocationSource: String, Sendable, Equatable {
    case memoryHint
    case persistedHint
    case loginShell
    case fallback
}

public enum CLIExecutableDiscoveryIssue: String, Sendable, Equatable {
    case shellTimeout
    case shellSpawnFailure
    case invalidShellOutput
    case inaccessibleCandidate
    case invalidatedHint
    case launchRace
}

public enum CLIExecutableLocation: Sendable, Equatable {
    case available(path: String, source: CLIExecutableLocationSource)
    case confirmedAbsent
    case inconclusive(CLIExecutableDiscoveryIssue)

    public var path: String? {
        guard case .available(let path, _) = self else { return nil }
        return path
    }
}

public enum CLIExecutableShellResult: Sendable, Equatable {
    case completed(candidates: [String])
    case timedOut
    case spawnFailed
    case invalidOutput
}

public enum CLIExecutableCandidateStatus: Sendable, Equatable {
    case executable
    case missing
    case inaccessible
}

public enum CLIExecutableInvalidationReason: Sendable, Equatable {
    case nonExecutable
    case launchNotFound
}

public enum CLIExecutableDiagnosticCategory: String, Sendable, Equatable, CaseIterable {
    case memoryHintValidated
    case persistedHintValidated
    case hintInvalidated
    case launchRace
    case loginShellResolved
    case fallbackResolved
    case supportedLocationMiss
    case shellTimeout
    case shellSpawnFailure
    case invalidShellOutput
    case inaccessibleCandidate
}

public struct CLIExecutableDiagnosticEvent: Sendable, Equatable {
    public let category: CLIExecutableDiagnosticCategory
    public let observedAt: Date

    public init(category: CLIExecutableDiagnosticCategory, observedAt: Date) {
        self.category = category
        self.observedAt = observedAt
    }
}

public protocol CLIExecutableHintStoring: Sendable {
    func hint(for executableName: String) -> String?
    func setHint(_ path: String?, for executableName: String)
}

public final class UserDefaultsCLIExecutableHintStore: CLIExecutableHintStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "cliExecutableHint.v1") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func hint(for executableName: String) -> String? {
        defaults.string(forKey: key(for: executableName))
    }

    public func setHint(_ path: String?, for executableName: String) {
        let key = key(for: executableName)
        if let path {
            defaults.set(path, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for executableName: String) -> String {
        "\(keyPrefix).\(executableName)"
    }
}

public protocol CLIExecutableLocating: Sendable {
    func locate(forceRefresh: Bool) async -> CLIExecutableLocation
    func invalidate(path: String, reason: CLIExecutableInvalidationReason) async
    func recentDiagnosticEvents() async -> [CLIExecutableDiagnosticEvent]
}

public extension CLIExecutableLocating {
    func locate() async -> CLIExecutableLocation { await locate(forceRefresh: false) }
    func recentDiagnosticEvents() async -> [CLIExecutableDiagnosticEvent] { [] }
}

/// Identifies one store-owned polling cycle without adding refresh parameters to every
/// provider. All Claude probes in the serial lane inherit the same value, so a negative
/// discovery is reused exactly within that cycle and nowhere else.
public enum CLIExecutableRefreshContext {
    @TaskLocal public static var generation: UUID?
}

/// Provider-scoped executable discovery. Paths are hints, not identity: every cached
/// value is revalidated, launch failures invalidate it, and later cycles can discover
/// a replacement without relaunching Headroom.
public actor CLIExecutableLocator: CLIExecutableLocating {
    public typealias ShellSearch = @Sendable () async -> CLIExecutableShellResult
    public typealias Validate = @Sendable (String) -> CLIExecutableCandidateStatus
    public typealias Now = @Sendable () -> Date

    private struct InFlight: Sendable {
        let id: UUID
        let epoch: UInt64
        let refreshGeneration: UUID?
        let task: Task<CLIExecutableLocation, Never>
    }

    private struct NegativeMemo: Sendable {
        let epoch: UInt64
        let refreshGeneration: UUID?
        let result: CLIExecutableLocation
    }

    private let executableName: String
    private let fallbackPaths: [String]
    private let hintStore: any CLIExecutableHintStoring
    private let shellSearch: ShellSearch
    private let validate: Validate
    private let now: Now
    private var cachedPath: String?
    private var inFlight: InFlight?
    private var epoch: UInt64 = 0
    private var observedRefreshGeneration: UUID?
    private var hasObservedRefreshGeneration = false
    private var negativeMemo: NegativeMemo?
    private var pendingInvalidation: CLIExecutableDiscoveryIssue?
    private var invalidationRefreshGeneration: UUID?
    private var diagnosticEvents: [CLIExecutableDiagnosticEvent] = []

    public init(
        executableName: String,
        fallbackPaths: [String],
        hintStore: any CLIExecutableHintStoring = UserDefaultsCLIExecutableHintStore(),
        shellSearch: ShellSearch? = nil,
        validate: Validate? = nil,
        now: @escaping Now = Date.init
    ) {
        self.executableName = executableName
        self.fallbackPaths = fallbackPaths
        self.hintStore = hintStore
        self.shellSearch = shellSearch ?? { await CLIExecutableResolver.searchExecutable(named: executableName) }
        self.validate = validate ?? { path in
            if FileManager.default.isExecutableFile(atPath: path) { return .executable }
            return FileManager.default.fileExists(atPath: path) ? .inaccessible : .missing
        }
        self.now = now
    }

    public func locate(forceRefresh: Bool = false) async -> CLIExecutableLocation {
        let refreshGeneration = CLIExecutableRefreshContext.generation
        observe(refreshGeneration: refreshGeneration)
        if forceRefresh {
            advanceEpoch()
            pendingInvalidation = nil
            invalidationRefreshGeneration = nil
        }

        if !forceRefresh {
            if let cachedPath, validate(cachedPath) == .executable {
                record(.memoryHintValidated)
                return .available(path: cachedPath, source: .memoryHint)
            }
            if cachedPath != nil { invalidateHintLocally(issue: .invalidatedHint) }

            if let persistedPath = hintStore.hint(for: executableName) {
                if validate(persistedPath) == .executable {
                    cachedPath = persistedPath
                    record(.persistedHintValidated)
                    return .available(path: persistedPath, source: .persistedHint)
                }
                invalidateHintLocally(issue: .invalidatedHint)
            }

            if let negativeMemo,
               negativeMemo.epoch == epoch,
               negativeMemo.refreshGeneration == refreshGeneration {
                return negativeMemo.result
            }
        }

        if let inFlight { return await finish(inFlight) }

        let id = UUID()
        let discoveryEpoch = epoch
        let shellSearch = self.shellSearch
        let fallbackPaths = self.fallbackPaths
        let validate = self.validate
        let invalidation = invalidationRefreshGeneration == refreshGeneration
            ? pendingInvalidation
            : nil
        let task = Task.detached(priority: .utility) {
            let shell = await shellSearch()
            return Self.discover(
                shell: shell,
                fallbackPaths: fallbackPaths,
                validate: validate,
                priorInvalidation: invalidation
            )
        }
        let flight = InFlight(
            id: id,
            epoch: discoveryEpoch,
            refreshGeneration: refreshGeneration,
            task: task
        )
        inFlight = flight
        return await finish(flight)
    }

    public func invalidate(path: String, reason: CLIExecutableInvalidationReason) async {
        let persistedPath = hintStore.hint(for: executableName)
        guard cachedPath == path || persistedPath == path else { return }
        advanceEpoch()
        cachedPath = nil
        hintStore.setHint(nil, for: executableName)
        pendingInvalidation = reason == .launchNotFound ? .launchRace : .invalidatedHint
        invalidationRefreshGeneration = CLIExecutableRefreshContext.generation
        record(reason == .launchNotFound ? .launchRace : .hintInvalidated)
    }

    public func recentDiagnosticEvents() async -> [CLIExecutableDiagnosticEvent] {
        diagnosticEvents
    }

    private func finish(_ flight: InFlight) async -> CLIExecutableLocation {
        let result = await flight.task.value
        guard epoch == flight.epoch else {
            return await locate(forceRefresh: false)
        }
        let ownsCompletion = inFlight?.id == flight.id
        if ownsCompletion { inFlight = nil }
        if ownsCompletion {
            switch result {
            case .available(let path, _):
                cachedPath = path
                hintStore.setHint(path, for: executableName)
                negativeMemo = nil
                pendingInvalidation = nil
                invalidationRefreshGeneration = nil
            case .inconclusive(.launchRace):
                // Every search started in this invalidation generation remains
                // inconclusive, and launch-race verdicts are never memoized.
                break
            default:
                if flight.refreshGeneration != nil {
                    negativeMemo = NegativeMemo(
                        epoch: flight.epoch,
                        refreshGeneration: flight.refreshGeneration,
                        result: result
                    )
                }
            }
        }
        if ownsCompletion { record(result.diagnosticCategory) }
        return result
    }

    private func invalidateHintLocally(issue: CLIExecutableDiscoveryIssue) {
        advanceEpoch()
        cachedPath = nil
        hintStore.setHint(nil, for: executableName)
        pendingInvalidation = issue
        invalidationRefreshGeneration = CLIExecutableRefreshContext.generation
        record(.hintInvalidated)
    }

    private func observe(refreshGeneration: UUID?) {
        guard !hasObservedRefreshGeneration || observedRefreshGeneration != refreshGeneration else { return }
        hasObservedRefreshGeneration = true
        observedRefreshGeneration = refreshGeneration
        negativeMemo = nil
        // A search already in flight keeps its start-generation verdict for its
        // original callers, while the newly started generation gets its own search.
        inFlight = nil
        if invalidationRefreshGeneration != refreshGeneration {
            pendingInvalidation = nil
            invalidationRefreshGeneration = nil
        }
    }

    private func advanceEpoch() {
        epoch &+= 1
        negativeMemo = nil
        inFlight = nil
    }

    private func record(_ category: CLIExecutableDiagnosticCategory) {
        let event = CLIExecutableDiagnosticEvent(category: category, observedAt: now())
        if diagnosticEvents.last?.category == category {
            diagnosticEvents[diagnosticEvents.count - 1] = event
            return
        }
        diagnosticEvents.append(event)
        if diagnosticEvents.count > 8 { diagnosticEvents.removeFirst(diagnosticEvents.count - 8) }
    }

    private static func discover(
        shell: CLIExecutableShellResult,
        fallbackPaths: [String],
        validate: Validate,
        priorInvalidation: CLIExecutableDiscoveryIssue?
    ) -> CLIExecutableLocation {
        var shellHadInaccessibleCandidate = false
        switch shell {
        case .completed(let candidates):
            for path in candidates.reversed() {
                switch validate(path) {
                case .executable:
                    return .available(path: path, source: .loginShell)
                case .inaccessible:
                    shellHadInaccessibleCandidate = true
                case .missing:
                    break
                }
            }
        case .timedOut, .spawnFailed, .invalidOutput:
            break
        }

        var fallbackHadInaccessibleCandidate = false
        for path in fallbackPaths {
            switch validate(path) {
            case .executable:
                return .available(path: path, source: .fallback)
            case .inaccessible:
                fallbackHadInaccessibleCandidate = true
            case .missing:
                break
            }
        }

        if shellHadInaccessibleCandidate || fallbackHadInaccessibleCandidate {
            return .inconclusive(.inaccessibleCandidate)
        }
        switch shell {
        case .timedOut: return .inconclusive(.shellTimeout)
        case .spawnFailed: return .inconclusive(.shellSpawnFailure)
        case .invalidOutput: return .inconclusive(.invalidShellOutput)
        case .completed:
            return priorInvalidation.map(CLIExecutableLocation.inconclusive) ?? .confirmedAbsent
        }
    }
}

private extension CLIExecutableLocation {
    var diagnosticCategory: CLIExecutableDiagnosticCategory {
        switch self {
        case .available(_, let source):
            switch source {
            case .memoryHint: .memoryHintValidated
            case .persistedHint: .persistedHintValidated
            case .loginShell: .loginShellResolved
            case .fallback: .fallbackResolved
            }
        case .confirmedAbsent:
            .supportedLocationMiss
        case .inconclusive(let issue):
            switch issue {
            case .shellTimeout: .shellTimeout
            case .shellSpawnFailure: .shellSpawnFailure
            case .invalidShellOutput: .invalidShellOutput
            case .inaccessibleCandidate: .inaccessibleCandidate
            case .invalidatedHint: .hintInvalidated
            case .launchRace: .launchRace
            }
        }
    }
}

public extension CLIExecutableLocator {
    static func claude(
        hintStore: any CLIExecutableHintStoring = UserDefaultsCLIExecutableHintStore()
    ) -> CLIExecutableLocator {
        CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                "\(NSHomeDirectory())/.local/bin/claude",
            ],
            hintStore: hintStore
        )
    }
}
