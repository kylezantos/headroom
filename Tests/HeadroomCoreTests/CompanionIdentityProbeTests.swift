#if DEBUG
import Foundation
import Testing
@testable import HeadroomCore

@Suite
struct CompanionIdentityProbeTests {
    @Test func nilCurrentTokenCannotBorrowAnArchivedIdentity() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ProbeTokenSource(ProbeCodingToken("private-fixture"))
        let probe = makeProbe(directory, source: source)
        #expect(probe.arm(role: .app).equality == .equal)
        source.set(nil)
        let record = probe.sample(role: .widget, step: .driveOff)
        #expect(record.availability == .unavailable)
        #expect(record.equality == .notCompared)
        #expect(record.archive == .notChecked)
    }

    @Test func independentRolesCompareAnNSCodingOnlyArchiveAfterRelaunch() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = ProbeSerialCoordinator()
        let first = makeProbe(directory, source: ProbeTokenSource(ProbeCodingToken("same")), coordinator: coordinator)
        let arm = first.arm(role: .app)
        #expect(arm.archive == .written)
        let second = makeProbe(directory, source: ProbeTokenSource(ProbeCodingToken("same")), coordinator: coordinator)
        let sample = second.sample(role: .widget, step: .relaunch)
        #expect(sample.equality == .equal)
        #expect(sample.archive == .readable)
        #expect(sample.ordinal == arm.ordinal + 1)
        #expect(sample.role == .widget)
        #expect(sample.time == Date(timeIntervalSince1970: 1234))
        #expect(second.report().records.count == 2)
        #expect(Set(coordinator.anchors).count == 1)
    }

    @Test func changedCandidateDoesNotOverwriteTheBaseline() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ProbeTokenSource(ProbeCodingToken("first"))
        let probe = makeProbe(directory, source: source)
        _ = probe.arm(role: .app)
        source.set(ProbeCodingToken("second"))
        #expect(probe.sample(role: .widget, step: .accountChanged).equality == .different)
        let rearm = probe.arm(role: .app)
        #expect(rearm.equality == .different)
        #expect(rearm.archive == .readable)
        source.set(ProbeCodingToken("first"))
        #expect(probe.sample(role: .app, step: .returnAccount).equality == .equal)
        _ = probe.reset(role: .app)
        source.set(ProbeCodingToken("second"))
        #expect(probe.arm(role: .app).archive == .written)
        source.set(ProbeCodingToken("first"))
        #expect(probe.sample(role: .widget).equality == .different)
    }

    @Test func missingAndCorruptArchivesAreNeverEqualityEvidence() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = makeProbe(directory, source: ProbeTokenSource(ProbeCodingToken("first")))
        let missing = probe.sample(role: .widget)
        #expect(missing.archive == .missing)
        #expect(missing.equality == .noBaseline)
        _ = probe.arm(role: .app)
        let stateURL = directory.appendingPathComponent("companion-identity-probe/probe-state.json")
        var state = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any])
        state["baselineArchive"] = Data([1, 2, 3]).base64EncodedString()
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
        let corrupt = probe.sample(role: .widget)
        #expect(corrupt.archive == .corrupt)
        #expect(corrupt.equality == .notCompared)
    }

    @Test func failedCoordinationDoesNotSampleOrFallbackToDisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ProbeTokenSource(ProbeCodingToken("private"))
        let failed = CompanionIdentityProbe(token: { source.get() }, container: { directory }, coordinator: ProbeRejectingCoordinator())
        let sample = failed.sample(role: .widget)
        #expect(sample.coordination == .failed)
        #expect(sample.ordinal == 0)
        #expect(source.reads == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("companion-identity-probe/probe-state.json").path))
        let report = try #require(JSONSerialization.jsonObject(with: Data(failed.report().exportText.utf8)) as? [String: Any])
        #expect(report["coordination"] as? String == "failed")
        #expect((report["records"] as? [Any])?.isEmpty == true)
    }

    @Test func missingContainerFailsWithoutReadingTheToken() {
        let source = ProbeTokenSource(ProbeCodingToken("private"))
        let probe = CompanionIdentityProbe(token: { source.get() }, container: { nil })
        #expect(probe.sample(role: .widget).coordination == .unavailable)
        #expect(source.reads == 0)
        #expect(probe.report().exportText.contains("\"unavailable\""))
    }

    @Test func rolesShareASequencedBoundedReportUnderCoordinatedConcurrentAccess() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = ProbeSerialCoordinator()
        let source = ProbeTokenSource(ProbeCodingToken("same"))
        let app = makeProbe(directory, source: source, coordinator: coordinator)
        let widget = makeProbe(directory, source: source, coordinator: coordinator)
        _ = app.arm(role: .app)
        let records = await withTaskGroup(of: CompanionIdentityProbeRecord.self, returning: [CompanionIdentityProbeRecord].self) { group in
            for index in 0..<40 {
                group.addTask {
                    index.isMultiple(of: 2) ? app.sample(role: .app) : widget.sample(role: .widget)
                }
            }
            var results: [CompanionIdentityProbeRecord] = []
            for await record in group { results.append(record) }
            return results
        }
        #expect(Set(records.map(\.ordinal)) == Set(2...41))
        #expect(records.allSatisfy { $0.equality == .equal && $0.coordination == .coordinated })
        #expect(app.report().records.map(\.ordinal) == Array(10...41))
        #expect(app.report().records.count == CompanionIdentityProbe.recordLimit)
        #expect(Set(coordinator.anchors).count == 1)
    }

    @Test func exportContainsOnlyTheAllowlistAndResetTouchesOnlyProbeFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unrelated = directory.appendingPathComponent("widget-snapshot.json")
        let unchanged = Data("production-fixture".utf8)
        try unchanged.write(to: unrelated)
        let source = ProbeTokenSource(ProbeCodingToken("OPAQUE_FIXTURE_MUST_NOT_EXPORT"))
        let probe = makeProbe(directory, source: source)
        _ = probe.arm(role: .app)
        let report = probe.report().exportText
        #expect(!report.contains("OPAQUE_FIXTURE_MUST_NOT_EXPORT"))
        #expect(!report.contains("baseline.archive"))
        #expect(!report.contains("baselineArchive"))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
        #expect(Set(envelope.keys) == Set(["coordination", "records"]))
        let rows = try #require(envelope["records"] as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(Set(rows[0].keys) == Set(["role", "step", "ordinal", "time", "availability", "equality", "archive", "coordination"]))
        #expect(probe.reset(role: .app).archive == .missing)
        #expect(probe.sample(role: .widget).equality == .noBaseline)
        #expect(try Data(contentsOf: unrelated) == unchanged)
    }

    @Test(arguments: ProbeWriteFailureStage.allCases)
    func failedWriteProtectionOrRenameLeavesTheEntirePriorStateIntact(stage: ProbeWriteFailureStage) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = ProbeSerialCoordinator()
        let source = ProbeTokenSource(ProbeCodingToken("first"))
        let healthy = makeProbe(directory, source: source, coordinator: coordinator)
        _ = healthy.arm(role: .app)
        let stateURL = directory.appendingPathComponent("companion-identity-probe/probe-state.json")
        let priorFile = try Data(contentsOf: stateURL)
        let failing = makeProbe(directory, source: source, coordinator: coordinator, storage: stage.storage)
        for operation in [failing.sample(role: .app, step: .offline), failing.reset(role: .app)] {
            #expect(operation.ordinal == 0)
            #expect(operation.archive == .failed)
            #expect(operation.equality == .notCompared)
            #expect(try Data(contentsOf: stateURL) == priorFile)
        }
        #expect(healthy.sample(role: .widget).equality == .equal)
        #expect(healthy.report().records.map(\.ordinal) == [1, 2])
        #expect(try FileManager.default.contentsOfDirectory(atPath: stateURL.deletingLastPathComponent().path)
            .allSatisfy { !$0.hasPrefix(".probe-stage-") })
    }

    @Test(arguments: ProbeWriteFailureStage.allCases)
    func failedFirstArmDoesNotCreateAnUnreportedBaseline(stage: ProbeWriteFailureStage) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = ProbeSerialCoordinator()
        let source = ProbeTokenSource(ProbeCodingToken("first"))
        let failing = makeProbe(directory, source: source, coordinator: coordinator, storage: stage.storage)
        #expect(failing.arm(role: .app).ordinal == 0)
        let healthy = makeProbe(directory, source: source, coordinator: coordinator)
        let sample = healthy.sample(role: .widget)
        #expect(sample.ordinal == 1)
        #expect(sample.archive == .missing)
        #expect(sample.equality == .noBaseline)
        #expect(healthy.report().records.count == 1)
    }

    @Test func readFailuresAreFailedAndSuccessfullyReadUndecodableStateIsCorrupt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ProbeTokenSource(ProbeCodingToken("first"))
        let healthy = makeProbe(directory, source: source)
        _ = healthy.arm(role: .app)
        let readFailure = makeProbe(directory, source: source, storage: ProbeReadFailingStorage())
        let unavailable = readFailure.sample(role: .widget)
        #expect(unavailable.archive == .failed)
        #expect(unavailable.ordinal == 0)
        #expect(readFailure.report().coordination == .failed)
        #expect(healthy.sample(role: .widget).equality == .equal)
        let stateURL = directory.appendingPathComponent("companion-identity-probe/probe-state.json")
        try Data([1, 2, 3]).write(to: stateURL)
        let corrupt = healthy.sample(role: .app)
        #expect(corrupt.archive == .corrupt)
        #expect(corrupt.ordinal == 0)
        #expect(healthy.reset(role: .app).ordinal == 1)
    }

    @Test func reportRereadsPreserveFailedActionUntilAnotherActionCommits() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ProbeTokenSource(ProbeCodingToken("private"))
        let healthy = makeProbe(directory, source: source)
        _ = healthy.arm(role: .app)
        let failed = makeProbe(directory, source: source, storage: ProbeWriteFailureStage.protection.storage).reset(role: .app)
        let reread = healthy.report().retainingFailedAction(failed)
        #expect(reread.records.last == failed)
        #expect(reread.exportText.contains("\"failed\""))
        #expect(reread.retainingFailedAction(failed).records.count == 2)
        _ = healthy.sample(role: .widget)
        let afterWidget = healthy.report().retainingFailedAction(failed)
        #expect(afterWidget.records.last == failed)
        #expect(afterWidget.records.contains { $0.role == .widget && $0.ordinal > 0 })
        let success = healthy.sample(role: .app)
        #expect(healthy.report().retainingFailedAction(success).records.allSatisfy { $0.ordinal > 0 })
        let reset = healthy.reset(role: .app)
        #expect(healthy.report().retainingFailedAction(reset).records.map(\.ordinal) == [1])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("headroom-identity-probe-tests-\(UUID().uuidString)")
    }

    private func makeProbe(
        _ directory: URL, source: ProbeTokenSource,
        coordinator: any CompanionIdentityProbeCoordinating = ProbeSerialCoordinator(),
        storage: any CompanionIdentityProbeStoring = CompanionIdentityProbeFileStorage()
    ) -> CompanionIdentityProbe {
        CompanionIdentityProbe(token: { source.get() }, now: { Date(timeIntervalSince1970: 1234) },
                               container: { directory }, coordinator: coordinator, storage: storage)
    }
}

/// NSCoding intentionally does not promise NSSecureCoding, matching Apple's candidate contract.
@objc(HeadroomIdentityProbeCodingFixture)
private final class ProbeCodingToken: NSObject, NSCoding, @unchecked Sendable {
    private let value: String
    init(_ value: String) { self.value = value }
    required init?(coder: NSCoder) {
        guard let value = coder.decodeObject(forKey: "value") as? String else { return nil }
        self.value = value
    }
    func encode(with coder: NSCoder) { coder.encode(value, forKey: "value") }
    override func isEqual(_ object: Any?) -> Bool { (object as? ProbeCodingToken)?.value == value }
}

private final class ProbeTokenSource: @unchecked Sendable {
    private let lock = NSLock()
    private var token: ProbeCodingToken?
    private var readCount = 0
    init(_ token: ProbeCodingToken?) { self.token = token }
    var reads: Int { lock.lock(); defer { lock.unlock() }; return readCount }
    func set(_ token: ProbeCodingToken?) { lock.lock(); defer { lock.unlock() }; self.token = token }
    func get() -> ProbeCodingToken? {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        return token
    }
}

private final class ProbeSerialCoordinator: CompanionIdentityProbeCoordinating, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedAnchors: [URL] = []
    var anchors: [URL] { lock.lock(); defer { lock.unlock() }; return recordedAnchors }
    func coordinate(anchor: URL, operation: () -> Void) -> CompanionIdentityProbeCoordination {
        lock.lock(); defer { lock.unlock() }
        recordedAnchors.append(anchor)
        operation()
        return .coordinated
    }
}

private struct ProbeRejectingCoordinator: CompanionIdentityProbeCoordinating {
    func coordinate(anchor: URL, operation: () -> Void) -> CompanionIdentityProbeCoordination { .failed }
}

private enum ProbeInjectedStorageFailure: Error { case injected }

enum ProbeWriteFailureStage: CaseIterable, Sendable {
    case write, protection, rename
    var storage: CompanionIdentityProbeFileStorage {
        switch self {
        case .write: CompanionIdentityProbeFileStorage(stageWrite: { _, _ in throw ProbeInjectedStorageFailure.injected })
        case .protection: CompanionIdentityProbeFileStorage(prepare: { _ in throw ProbeInjectedStorageFailure.injected })
        case .rename: CompanionIdentityProbeFileStorage(commit: { _, _ in throw ProbeInjectedStorageFailure.injected })
        }
    }
}

private struct ProbeReadFailingStorage: CompanionIdentityProbeStoring {
    func read(from url: URL, maximumBytes: Int) throws -> Data? { throw ProbeInjectedStorageFailure.injected }
    func write(_ data: Data, to url: URL) throws { throw ProbeInjectedStorageFailure.injected }
}
#endif
