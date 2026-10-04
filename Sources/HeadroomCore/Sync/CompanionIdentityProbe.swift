#if DEBUG
import Darwin
import Foundation

/// U4 candidate gate only. No production loader consumes these verdicts or files.
public enum CompanionIdentityProbeRole: String, Codable, Sendable {
    case app, widget
}

public enum CompanionIdentityProbeStep: String, Codable, CaseIterable, Identifiable, Sendable {
    case baseline, driveOff, relaunch, offline, accountChanged, emptyAccount, returnAccount, transition, reset
    public var id: String { rawValue }
}

public enum CompanionIdentityProbeAvailability: String, Codable, Sendable {
    case available, unavailable, notSampled
}

public enum CompanionIdentityProbeEquality: String, Codable, Sendable {
    case equal, different, noBaseline, notCompared
}

public enum CompanionIdentityProbeArchive: String, Codable, Sendable {
    case written, readable, missing, corrupt, failed, notChecked
}

public enum CompanionIdentityProbeCoordination: String, Codable, Sendable {
    case coordinated, unavailable, failed
}

/// The complete export allowlist. The opaque object and its archive cannot enter this type.
public struct CompanionIdentityProbeRecord: Codable, Equatable, Sendable {
    public let role: CompanionIdentityProbeRole
    public let step: CompanionIdentityProbeStep
    public let ordinal: Int
    public let time: Date
    public let availability: CompanionIdentityProbeAvailability
    public let equality: CompanionIdentityProbeEquality
    public let archive: CompanionIdentityProbeArchive
    public let coordination: CompanionIdentityProbeCoordination
}

public struct CompanionIdentityProbeReport: Encodable, Sendable {
    public let records: [CompanionIdentityProbeRecord]
    public let coordination: CompanionIdentityProbeCoordination

    public init(records: [CompanionIdentityProbeRecord], coordination: CompanionIdentityProbeCoordination) {
        self.records = Array(records.suffix(CompanionIdentityProbe.recordLimit))
        self.coordination = coordination
    }

    /// Preserve a failed app action across rereads, including independent widget commits.
    /// The caller clears it only after a subsequent app action commits or Reset succeeds.
    public func retainingFailedAction(_ latest: CompanionIdentityProbeRecord?) -> Self {
        guard let latest, latest.ordinal == 0 else { return self }
        return Self(records: records.filter { $0 != latest } + [latest], coordination: coordination)
    }

    public var exportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{\"coordination\":\"failed\",\"records\":[]}"
        }
        return text
    }
}

public protocol CompanionIdentityProbeCoordinating: Sendable {
    func coordinate(anchor: URL, operation: () -> Void) -> CompanionIdentityProbeCoordination
}

public struct CompanionIdentityProbeFileCoordinator: CompanionIdentityProbeCoordinating {
    public init() {}

    public func coordinate(anchor: URL, operation: () -> Void) -> CompanionIdentityProbeCoordination {
        var error: NSError?
        var entered = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: anchor, options: [], error: &error) { _ in
            entered = true
            operation()
        }
        return entered && error == nil ? .coordinated : .failed
    }
}

/// A successful write commits all probe state; a thrown write must leave the old file intact.
public protocol CompanionIdentityProbeStoring: Sendable {
    func read(from url: URL, maximumBytes: Int) throws -> Data?
    func write(_ data: Data, to url: URL) throws
}

public struct CompanionIdentityProbeFileStorage: CompanionIdentityProbeStoring {
    private let stageWrite: @Sendable (Data, URL) throws -> Void
    private let prepare: @Sendable (URL) throws -> Void
    private let commit: @Sendable (URL, URL) throws -> Void

    public init() {
        self.init(stageWrite: Self.stageWrite, prepare: Self.prepare, commit: Self.commit)
    }

    // Narrow fault seams exercise the real staged-file order without changing the destination.
    init(
        stageWrite: @escaping @Sendable (Data, URL) throws -> Void = Self.stageWrite,
        prepare: @escaping @Sendable (URL) throws -> Void = Self.prepare,
        commit: @escaping @Sendable (URL, URL) throws -> Void = Self.commit
    ) {
        self.stageWrite = stageWrite
        self.prepare = prepare
        self.commit = commit
    }

    public func read(from url: URL, maximumBytes: Int) throws -> Data? {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, size <= maximumBytes else { throw StorageFailure.invalid }
            let data = try Data(contentsOf: url)
            guard data.count <= maximumBytes else { throw StorageFailure.invalid }
            return data
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func write(_ data: Data, to url: URL) throws {
        let staged = url.deletingLastPathComponent().appendingPathComponent(".probe-stage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staged) }
        try stageWrite(data, staged)
        try prepare(staged)
        // No fallible metadata operation follows the atomic commit.
        try commit(staged, url)
    }

    private enum StorageFailure: Error { case invalid }
    private static func stageWrite(_ data: Data, _ url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
    }
    private static func prepare(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: url.path)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func commit(_ staged: URL, _ destination: URL) throws {
        guard rename(staged.path, destination.path) == 0 else { throw StorageFailure.invalid }
    }
}

/// Synchronous accessors keep the entire probe transaction inside one process-coordinated
/// anchor. Injectable closures are Sendable; opaque objects never cross an async boundary.
public struct CompanionIdentityProbe: Sendable {
    public typealias Token = any NSObjectProtocol & NSCoding
    public static let widgetKind = "HeadroomIdentityProbe"
    public static let recordLimit = 32

    private let token: @Sendable () -> Token?
    private let now: @Sendable () -> Date
    private let container: @Sendable () -> URL?
    private let coordinator: any CompanionIdentityProbeCoordinating
    private let storage: any CompanionIdentityProbeStoring
    private static let directoryName = "companion-identity-probe"
    private static let stateName = "probe-state.json"
    private static let anchorName = "transaction.anchor"
    // The candidate is a tiny opaque token; refuse unexpectedly large local archives.
    private static let archiveLimit = 64 * 1024
    private static let stateLimit = 128 * 1024

    public init(
        token: @escaping @Sendable () -> Token?,
        now: @escaping @Sendable () -> Date = Date.init,
        container: @escaping @Sendable () -> URL?,
        coordinator: any CompanionIdentityProbeCoordinating = CompanionIdentityProbeFileCoordinator(),
        storage: any CompanionIdentityProbeStoring = CompanionIdentityProbeFileStorage()
    ) {
        self.token = token
        self.now = now
        self.container = container
        self.coordinator = coordinator
        self.storage = storage
    }

    public static func appGroup() -> Self {
        Self(
            token: { FileManager.default.ubiquityIdentityToken },
            container: {
                FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: WidgetSnapshotCache.appGroupSuiteName
                )
            }
        )
    }

    public func arm(role: CompanionIdentityProbeRole, step: CompanionIdentityProbeStep = .baseline) -> CompanionIdentityProbeRecord {
        transact(role: role, step: step, action: .arm)
    }

    public func sample(role: CompanionIdentityProbeRole, step: CompanionIdentityProbeStep? = nil) -> CompanionIdentityProbeRecord {
        transact(role: role, step: step, action: .sample)
    }

    public func reset(role: CompanionIdentityProbeRole) -> CompanionIdentityProbeRecord {
        transact(role: role, step: .reset, action: .reset)
    }

    public func report() -> CompanionIdentityProbeReport {
        guard let directory = preparedDirectory() else {
            return CompanionIdentityProbeReport(records: [], coordination: .unavailable)
        }
        var records: [CompanionIdentityProbeRecord] = []
        var readable = false
        let verdict = coordinator.coordinate(anchor: directory.appendingPathComponent(Self.anchorName)) {
            if let state = try? readState(directory) {
                records = state.records
                readable = true
            }
        }
        guard verdict == .coordinated, readable else {
            return CompanionIdentityProbeReport(records: [], coordination: verdict == .coordinated ? .failed : verdict)
        }
        return CompanionIdentityProbeReport(records: records, coordination: .coordinated)
    }

    private enum Action { case arm, sample, reset }
    private struct State: Codable {
        var version = 2
        var baselineArchive: Data?
        var step = CompanionIdentityProbeStep.baseline
        var ordinal = 0
        var records: [CompanionIdentityProbeRecord] = []
    }
    private enum ProbeFailure: Error { case invalid, corrupt }

    private func transact(role: CompanionIdentityProbeRole, step: CompanionIdentityProbeStep?, action: Action) -> CompanionIdentityProbeRecord {
        let time = now()
        func failure(_ coordination: CompanionIdentityProbeCoordination, archive: CompanionIdentityProbeArchive = .failed) -> CompanionIdentityProbeRecord {
            makeRecord(role: role, step: step ?? .baseline, ordinal: 0, time: time,
                       availability: .notSampled, equality: .notCompared, archive: archive, coordination: coordination)
        }
        guard let directory = preparedDirectory() else { return failure(.unavailable) }
        var result = failure(.failed)
        let verdict = coordinator.coordinate(anchor: directory.appendingPathComponent(Self.anchorName)) {
            do {
                var state = action == .reset ? State() : try readState(directory)
                if let step { state.step = step }
                guard state.ordinal < Int.max else { throw ProbeFailure.invalid }
                state.ordinal += 1
                let availability: CompanionIdentityProbeAvailability
                let equality: CompanionIdentityProbeEquality
                let archive: CompanionIdentityProbeArchive
                if action == .reset {
                    availability = .notSampled
                    equality = .notCompared
                    archive = .missing
                } else if let current = token() {
                    availability = .available
                    if let data = state.baselineArchive {
                        do {
                            if let restored = try unarchive(data) {
                                equality = current.isEqual(restored) ? .equal : .different
                                archive = .readable
                            } else {
                                equality = .notCompared
                                archive = .corrupt
                            }
                        } catch {
                            equality = .notCompared
                            archive = .corrupt
                        }
                    } else if action == .arm {
                        let data = try NSKeyedArchiver.archivedData(withRootObject: current, requiringSecureCoding: false)
                        guard data.count <= Self.archiveLimit, let restored = try unarchive(data) else { throw ProbeFailure.invalid }
                        equality = current.isEqual(restored) ? .equal : .different
                        archive = .written
                        state.baselineArchive = data
                    } else {
                        equality = .noBaseline
                        archive = .missing
                    }
                } else {
                    // A prior baseline never turns a currently nil candidate into availability.
                    availability = .unavailable
                    equality = .notCompared
                    archive = .notChecked
                }
                let record = makeRecord(role: role, step: state.step, ordinal: state.ordinal, time: time,
                                        availability: availability, equality: equality, archive: archive, coordination: .coordinated)
                state.records.append(record)
                state.records = Array(state.records.suffix(Self.recordLimit))
                let data = try JSONEncoder().encode(state)
                guard data.count <= Self.stateLimit else { throw ProbeFailure.invalid }
                try storage.write(data, to: directory.appendingPathComponent(Self.stateName))
                result = record
            } catch ProbeFailure.corrupt {
                result = failure(.coordinated, archive: .corrupt)
            } catch {
                result = failure(.coordinated)
            }
        }
        return verdict == .coordinated ? result : failure(verdict)
    }

    private func readState(_ directory: URL) throws -> State {
        let file = directory.appendingPathComponent(Self.stateName)
        // Read/protection/I/O errors stay failures; only successfully read undecodable
        // bytes are classified as corruption.
        guard let data = try storage.read(from: file, maximumBytes: Self.stateLimit) else { return State() }
        do {
            let state = try JSONDecoder().decode(State.self, from: data)
            guard state.version == 2, state.ordinal >= 0, state.records.count <= Self.recordLimit,
                  (state.baselineArchive?.count ?? 0) <= Self.archiveLimit,
                  state.records.allSatisfy({ $0.ordinal > 0 && $0.ordinal <= state.ordinal }) else {
                throw ProbeFailure.corrupt
            }
            return state
        } catch {
            throw ProbeFailure.corrupt
        }
    }

    private func unarchive(_ data: Data) throws -> Token? {
        guard data.count <= Self.archiveLimit else { throw ProbeFailure.invalid }
        let reader = try NSKeyedUnarchiver(forReadingFrom: data)
        // Apple promises NSCoding, not NSSecureCoding, for ubiquityIdentityToken.
        reader.requiresSecureCoding = false
        reader.decodingFailurePolicy = .setErrorAndReturn
        let value = reader.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? Token
        reader.finishDecoding()
        guard reader.error == nil else { throw ProbeFailure.invalid }
        return value
    }

    private func preparedDirectory() -> URL? {
        guard let container = container() else { return nil }
        let directory = container.appendingPathComponent(Self.directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                 ofItemAtPath: directory.path)
            #endif
            let anchor = directory.appendingPathComponent(Self.anchorName)
            // O_EXCL creates the stable anchor once; later roles never replace its inode.
            let descriptor = open(anchor.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            if descriptor >= 0 { close(descriptor) }
            else if errno != EEXIST { return nil }
            let attributes = try FileManager.default.attributesOfItem(atPath: anchor.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
            return directory
        } catch {
            return nil
        }
    }

    private func makeRecord(
        role: CompanionIdentityProbeRole, step: CompanionIdentityProbeStep, ordinal: Int, time: Date,
        availability: CompanionIdentityProbeAvailability, equality: CompanionIdentityProbeEquality,
        archive: CompanionIdentityProbeArchive, coordination: CompanionIdentityProbeCoordination
    ) -> CompanionIdentityProbeRecord {
        CompanionIdentityProbeRecord(role: role, step: step, ordinal: ordinal, time: time,
                                     availability: availability, equality: equality, archive: archive, coordination: coordination)
    }
}
#endif
