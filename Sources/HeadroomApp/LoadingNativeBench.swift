#if HEADROOM_BENCH
import Foundation
import Darwin
import HeadroomCore

/// Diagnostic-only: identical on both builds, with no sampling during the CPU interval.
@MainActor
enum LoadingNativeBench {
    private static func mainThreadID() -> UInt64? {
        guard Thread.isMainThread else { return nil }
        var id: UInt64 = 0
        return pthread_threadid_np(nil, &id) == 0 && id != 0 ? id : nil
    }

    static var reportURL: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--loading-native-bench"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1])
    }

    static func run(store: UsageStore, preferences: Preferences, reportURL: URL) async {
        var report: [String: Any] = ["status": "unavailable", "pid": getpid(), "pollIntervalMinutes": 30,
            "bodyCountersAvailable": BenchCounters.isCompiledIn, "sequenceRecording": false,
            "cpuUnit": "nanoseconds", "cpuClock": "CLOCK_THREAD_CPUTIME_ID", "tailSeconds": 2]
        defer {
            BenchCounters.enabled = false
            BenchCounters.recordSequence = false
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: reportURL, options: .atomic)
            } catch { print("Loading benchmark report failed") }
        }
        do {
            guard DemoFixture.isEnabled else { report["reason"] = "requires isolated demo"; return }
            guard !FileManager.default.fileExists(atPath: reportURL.appendingPathExtension("arm").path),
                  !FileManager.default.fileExists(atPath: reportURL.appendingPathExtension("ready").path) else {
                report["reason"] = "stale handshake files"; return
            }
            preferences.pollIntervalMinutes = 30
            await store.start()
            let keys = store.providerOrder.flatMap { store.accounts(for: $0).map(\.key) }
            guard keys.count == 61, !store.isRefreshing, store.probingAccounts.isEmpty,
                  keys.allSatisfy({ store.snapshot(for: $0).freshness != .pending }) else {
                report["reason"] = "multi-20 warm readiness failed"; return
            }
            try await Task.sleep(for: .seconds(2))
            guard let threadID = mainThreadID() else {
                report["reason"] = "thread identity unavailable"; return
            }
            report["mainThreadID"] = threadID
            report["accountCount"] = keys.count
            let readyURL = reportURL.appendingPathExtension("ready")
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: readyURL, options: .atomic)
            // READY permits the approved operator to mount the same native surface on both builds.
            let armURL = reportURL.appendingPathExtension("arm")
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while !FileManager.default.fileExists(atPath: armURL.path) {
                guard ContinuousClock.now < deadline else { report["reason"] = "not armed"; return }
                try await Task.sleep(for: .milliseconds(200))
            }
            guard !store.isRefreshing, store.probingAccounts.isEmpty else { report["reason"] = "warm work resumed"; return }
            BenchCounters.reset()
            BenchCounters.recordSequence = false
            BenchCounters.enabled = true
            let wallStart = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            await store.refreshAll()
            let wallAction = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            let cpuAction = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            try await Task.sleep(for: .seconds(2))
            let wallEnd = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            let cpuEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            guard mainThreadID() == threadID, cpuStart > 0, cpuAction >= cpuStart, cpuEnd >= cpuAction,
                  wallStart > 0, wallAction > wallStart, wallEnd > wallAction,
                  !store.isRefreshing, store.probingAccounts.isEmpty else {
                report["reason"] = "invalid counters or contaminated tail"; return
            }
            report["status"] = "complete"
            report["actionWallNs"] = wallAction - wallStart
            report["actionMainCPUTimeNs"] = cpuAction - cpuStart
            report["totalWallNs"] = wallEnd - wallStart
            report["totalMainCPUTimeNs"] = cpuEnd - cpuStart
            report["mainCPUPercent"] = 100 * Double(cpuEnd - cpuStart) / Double(wallEnd - wallStart)
            report["bodyCounts"] = BenchCounters.counts
            report["bodyCount"] = BenchCounters.total
        } catch {
            report["reason"] = error is CancellationError ? "cancelled" : "diagnostic setup failed"
        }
    }
}
#endif
