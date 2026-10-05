#if DEBUG
import SwiftUI
import WidgetKit

/// U4 candidate-only controls. A user action starts every app sample; opening Settings,
/// previews and reports do not read an identity or write probe state. The candidate switch
/// chooses the token (failed P5) or the KVS scope marker; the widget samples whichever the
/// app last selected. Only enum verdicts are shown; never a token or marker value.
struct IdentityProbeDiagnosticsSection: View {
    let isDemoMode: Bool
    @State private var step = CompanionIdentityProbeStep.baseline
    @State private var candidate = CompanionIdentityProbeCandidate.token
    @State private var latest: CompanionIdentityProbeRecord?
    @State private var markerWrite: CompanionScopeMarkerWriteResult?
    @State private var report = CompanionIdentityProbeReport(records: [], coordination: .unavailable)
    @State private var isRunning = false
    private var probe: CompanionIdentityProbe { CompanionIdentityProbe.appGroup(candidate: candidate) }

    var body: some View {
        Section("Identity Candidate Probe · DEBUG") {
            Text("Local identity comparability only. This does not change or validate the usage cache.")
                .font(.footnote)
            // A user choice persists the candidate; restoring it on open writes nothing.
            Picker("Candidate", selection: Binding(get: { candidate }, set: { select($0) })) {
                Text("Identity token").tag(CompanionIdentityProbeCandidate.token)
                Text("KVS marker").tag(CompanionIdentityProbeCandidate.kvsMarker)
            }
            .accessibilityIdentifier("headroom.identity-probe.candidate")
            if candidate == .kvsMarker {
                Text("Arm writes the marker only if iCloud has none, then records it. Each candidate keeps its own baseline and rows.")
                    .font(.footnote)
            }
            Picker("Test step", selection: $step) {
                ForEach(CompanionIdentityProbeStep.allCases.filter { $0 != .reset }) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            Button("Arm baseline") { run(.arm) }
                .accessibilityIdentifier("headroom.identity-probe.arm")
            Text("Arm compares an existing baseline. Use Reset before replacing it.")
                .font(.footnote)
            Button("Sample app and request widget sample") { run(.sample) }
                .accessibilityIdentifier("headroom.identity-probe.sample")
            Button("Read bounded report") { run(.report) }
                .accessibilityIdentifier("headroom.identity-probe.report")
            Button("Reset probe only") { run(.reset) }
                .accessibilityIdentifier("headroom.identity-probe.reset")
            if let latest {
                Text("\(latest.role.rawValue) #\(latest.ordinal) · \(latest.step.rawValue)")
                Text("\(candidateLabel): \(latest.availability.rawValue) · Comparison: \(latest.equality.rawValue)")
                    .font(.footnote)
                Text("Archive: \(latest.archive.rawValue) · Coordination: \(latest.coordination.rawValue)")
                    .font(.footnote)
                Text(latest.time, format: .dateTime.hour().minute().second())
                    .font(.footnote.monospacedDigit())
            }
            if candidate == .kvsMarker, let markerWrite {
                Text("Marker write: \(markerWrite.rawValue)")
                    .font(.footnote)
            }
            Text("Report coordination: \(report.coordination.rawValue)")
                .font(.footnote)
            Text(report.exportText)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            ShareLink("Share enum-only report", item: report.exportText)
            Text("Add the separate Identity Probe widget. A reload request is not proof of an invocation: verify its time and ordinal changed after each test step.")
                .font(.footnote)
            if isDemoMode {
                Text("Exit Demo to run this diagnostic.")
                    .font(.footnote)
            }
        }
        .disabled(isRunning || isDemoMode)
        .tint(.primary)
        .task {
            // Reads only the selected candidate name, never an identity.
            let stored = await Task.detached { CompanionIdentityProbe.appGroup().storedCandidate() }.value
            if stored != candidate { candidate = stored }
        }
    }

    private var candidateLabel: String {
        candidate == .kvsMarker ? "Marker" : "Token"
    }

    private func select(_ value: CompanionIdentityProbeCandidate) {
        guard value != candidate else { return }
        candidate = value
        latest = nil
        markerWrite = nil
        report = CompanionIdentityProbeReport(records: [], coordination: .unavailable, candidate: value)
        Task {
            _ = await Task.detached { CompanionIdentityProbe.appGroup().storeCandidate(value) }.value
            WidgetCenter.shared.reloadTimelines(ofKind: CompanionIdentityProbe.widgetKind)
        }
    }

    private enum Action: Sendable { case arm, sample, reset, report }

    private func run(_ action: Action) {
        guard !isRunning, !isDemoMode else { return }
        isRunning = true
        let selectedStep = step
        let probe = probe
        let previousAction = latest
        let ensuresMarker = action == .arm && probe.candidate == .kvsMarker
        Task {
            let result = await Task.detached {
                // The app is the marker's only writer: Arm creates it only when iCloud has none.
                let write = ensuresMarker
                    ? CompanionKVSScopeMarkerWriter(store: UbiquitousKeyValueSyncStore()).ensureMarker() : nil
                let record: CompanionIdentityProbeRecord? = switch action {
                case .arm: probe.arm(role: .app, step: selectedStep)
                case .sample: probe.sample(role: .app, step: selectedStep)
                case .reset: probe.reset(role: .app)
                case .report: nil
                }
                let stored = probe.report()
                // Rereading cannot erase an action that failed before its state committed.
                let report = stored.retainingFailedAction(record ?? previousAction)
                return (record, report, write)
            }.value
            if let record = result.0 { latest = record }
            if let write = result.2 { markerWrite = write }
            report = result.1
            isRunning = false
            if action != .report {
                WidgetCenter.shared.reloadTimelines(ofKind: CompanionIdentityProbe.widgetKind)
            }
        }
    }
}
#endif
