import Foundation
import HeadroomCore
#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif

#if HEADROOM_BENCH
/// View-body counter for the `--bench-ui` diagnostic. Compiled in only with
/// `-Xswiftc -DHEADROOM_BENCH`; shipping builds get the no-op twin below, so the
/// `let _ = BenchCounters.hit("Name")` line at the top of an instrumented body costs nothing.
/// Counting is the measurement that found SC1 and ML1: a body that re-runs when nothing it
/// shows changed is invisible in a still render (see the snappiness solution doc).
@MainActor
enum BenchCounters {
    static let isCompiledIn = true
    static var enabled = false {
        // Shared-module views (MeterGauge) count through this sink.
        didSet {
            if enabled {
                let forward: @MainActor (String) -> Void = { name in BenchCounters.hit(name) }
                SharedBenchCounters.sink = forward
            } else {
                SharedBenchCounters.sink = nil
            }
        }
    }
    /// When on, `sequence` keeps body names and `mark` notes in order, for frame-by-frame reads.
    static var recordSequence = false
    private(set) static var counts: [String: Int] = [:]
    private(set) static var total = 0
    private(set) static var sequence: [String] = []

    static func hit(_ name: String) {
        guard enabled else { return }
        total += 1
        counts[name, default: 0] += 1
        if recordSequence { sequence.append(name) }
    }

    /// A note that is not a body (a geometry report, a state write), kept in `sequence` only.
    static func mark(_ note: @autoclosure () -> String) {
        guard enabled, recordSequence else { return }
        sequence.append("·" + note())
    }

    static func reset() {
        counts = [:]
        total = 0
        sequence = []
    }

    static func drainSequence() -> [String] {
        defer { sequence = [] }
        return sequence
    }
}

/// The bench's supported Settings pane seam. `SettingsView` observes this notification only in
/// `HEADROOM_BENCH` builds and applies the request in the same update, the way a sidebar click
/// does: `paneSwitchIsInstant` first, then the selection (KB1).
@MainActor
enum BenchSettingsSeam {
    static let selectPane = Notification.Name("co.zantos.headroom.bench.selectSettingsPane")

    struct Request {
        let pane: SettingsPane
        let instant: Bool
    }

    static func request(_ pane: SettingsPane, instant: Bool) {
        NotificationCenter.default.post(name: selectPane, object: Request(pane: pane, instant: instant))
    }
}
#else
/// Shipping twin of the bench counter: every member is an inlined no-op or a constant.
enum BenchCounters {
    static let isCompiledIn = false
    @inline(__always) static func hit(_ name: String) {}
    @inline(__always) static func mark(_ note: @autoclosure () -> String) {}
    @inline(__always) static func reset() {}
    @inline(__always) static func drainSequence() -> [String] { [] }
    static var enabled: Bool {
        get { false }
        set {}
    }
    static var recordSequence: Bool {
        get { false }
        set {}
    }
    static var counts: [String: Int] { [:] }
    static var total: Int { 0 }
    static var sequence: [String] { [] }
}
#endif
