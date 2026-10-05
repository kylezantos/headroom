import Foundation

@testable import HeadroomCore

/// U7 doubles for the demo replay: a fixed, advanceable clock and a sleep that records its
/// pacing and advances that clock instead of waiting. Their own file per the stream rule.
final class DemoReplayClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var slept: [TimeInterval] = []

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }
    var sleeps: [TimeInterval] { lock.withLock { slept } }

    func sleep(_ seconds: TimeInterval) {
        lock.withLock {
            slept.append(seconds)
            current = current.addingTimeInterval(seconds)
        }
    }
}

/// Collects replayed steps in order.
actor DemoStepRecorder {
    private(set) var steps: [CompanionDemoCheckNowStep] = []

    func record(_ step: CompanionDemoCheckNowStep) { steps.append(step) }
}
