#if DEBUG
import Foundation
import Testing
@testable import HeadroomCore

/// The probe's KVS-marker mode for the device check (U4b). Token mode stays covered, unchanged,
/// by `CompanionIdentityProbeTests`.
@Suite
struct CompanionIdentityProbeMarkerTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("headroom-identity-marker-tests-\(UUID().uuidString)")
    private let coordinator = MarkerProbeCoordinator()

    private func markerProbe(_ source: MarkerProbeSource) -> CompanionIdentityProbe {
        CompanionIdentityProbe(
            marker: { source.read() }, now: { Date(timeIntervalSince1970: 1234) },
            container: { directory }, coordinator: coordinator)
    }

    private func tokenProbe(_ value: String?) -> CompanionIdentityProbe {
        CompanionIdentityProbe(
            token: { value.map { $0 as NSString } }, now: { Date(timeIntervalSince1970: 1234) },
            container: { directory }, coordinator: coordinator)
    }

    @Test func armSampleAndAccountSwitchUseByteEquality() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = MarkerProbeSource("marker-a")
        let app = markerProbe(source)
        #expect(app.candidate == .kvsMarker)
        let arm = app.arm(role: .app)
        #expect((arm.availability, arm.equality, arm.archive) == (.available, .equal, .written))
        let widget = markerProbe(source).sample(role: .widget, step: .driveOff)
        #expect((widget.availability, widget.equality, widget.archive) == (.available, .equal, .readable))
        #expect(widget.ordinal == arm.ordinal + 1)

        // Another account's store: a different marker reads as different, never equal.
        source.set("marker-b")
        #expect(markerProbe(source).sample(role: .widget, step: .accountChanged).equality == .different)
        // Signed out or an empty Apple ID: no marker is unavailable, the baseline never stands in.
        source.set(nil)
        let absent = markerProbe(source).sample(role: .widget, step: .emptyAccount)
        #expect((absent.availability, absent.equality, absent.archive) == (.unavailable, .notCompared, .notChecked))
        // Arm never replaces an existing baseline.
        source.set("marker-b")
        #expect(app.arm(role: .app).archive == .readable)
        source.set("marker-a")
        #expect(app.sample(role: .app, step: .returnAccount).equality == .equal)
    }

    @Test func candidatesKeepSeparateBaselinesAndRows() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = tokenProbe("token-a").arm(role: .app)
        let tokenState = directory.appendingPathComponent("companion-identity-probe/probe-state.json")
        let tokenBytes = try Data(contentsOf: tokenState)

        let marker = markerProbe(MarkerProbeSource("marker-a"))
        #expect(marker.sample(role: .widget).equality == .noBaseline)
        _ = marker.arm(role: .app)
        _ = marker.reset(role: .app)
        #expect(try Data(contentsOf: tokenState) == tokenBytes)
        #expect(tokenProbe("token-a").sample(role: .widget).equality == .equal)
        #expect(marker.report().records.map(\.ordinal) == [1])
        #expect(tokenProbe("token-a").report().records.map(\.ordinal) == [1, 2])
    }

    @Test func markerReportIsEnumOnlyAndNamesItsCandidate() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = markerProbe(MarkerProbeSource("MARKER_VALUE_MUST_NOT_EXPORT"))
        _ = probe.arm(role: .app)
        let text = probe.report().exportText
        #expect(!text.contains("MARKER_VALUE_MUST_NOT_EXPORT"))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(Set(envelope.keys) == Set(["coordination", "records", "candidate"]))
        #expect(envelope["candidate"] as? String == "kvsMarker")
        let rows = try #require(envelope["records"] as? [[String: Any]])
        #expect(Set(rows[0].keys) == Set(["role", "step", "ordinal", "time", "availability", "equality", "archive", "coordination"]))
        // A retained failed action keeps the candidate label.
        let failed = CompanionIdentityProbeRecord(
            role: .app, step: .baseline, ordinal: 0, time: .distantPast, availability: .notSampled,
            equality: .notCompared, archive: .failed, coordination: .failed)
        #expect(probe.report().retainingFailedAction(failed).candidate == .kvsMarker)
        // The token report keeps its exact allowlist.
        let token = CompanionIdentityProbeReport(records: [], coordination: .coordinated, candidate: .token)
        #expect(token.candidate == nil)
        #expect(!token.exportText.contains("candidate"))
    }

    @Test func candidateSelectionIsSharedAndDefaultsToToken() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = tokenProbe("token-a")
        let widgetSide = markerProbe(MarkerProbeSource("marker-a"))
        #expect(widgetSide.storedCandidate() == .token)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(app.storeCandidate(.kvsMarker) == .coordinated)
        #expect(widgetSide.storedCandidate() == .kvsMarker)
        #expect(app.storeCandidate(.token) == .coordinated)
        #expect(widgetSide.storedCandidate() == .token)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("companion-identity-probe/probe-candidate.json"))
        #expect(widgetSide.storedCandidate() == .token)
        // Selecting never touches either baseline.
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("companion-identity-probe/probe-marker-state.json").path))
    }

    @Test func missingContainerSelectsTokenAndReportsUnavailable() {
        let probe = CompanionIdentityProbe(marker: { Data("m".utf8) }, container: { nil })
        #expect(probe.storedCandidate() == .token)
        #expect(probe.storeCandidate(.kvsMarker) == .unavailable)
        #expect(probe.report().coordination == .unavailable)
        #expect(probe.report().candidate == .kvsMarker)
    }
}

private final class MarkerProbeSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    init(_ value: String?) { self.value = value }
    func set(_ value: String?) { lock.withLock { self.value = value } }
    func read() -> Data? { lock.withLock { value.map { Data($0.utf8) } } }
}

private final class MarkerProbeCoordinator: CompanionIdentityProbeCoordinating, @unchecked Sendable {
    private let lock = NSLock()
    func coordinate(anchor: URL, operation: () -> Void) -> CompanionIdentityProbeCoordination {
        lock.withLock { operation() }
        return .coordinated
    }
}
#endif
