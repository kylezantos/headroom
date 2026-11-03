import Darwin
import Foundation
import Testing
@testable import HeadroomCore

struct StdioChildProcessTests {
    @Test func aWorkerThatIgnoresTermIsKilledAfterItsLeaderHasExited() async throws {
        let script = """
        sh -c 'trap "" TERM; echo $$; while :; do sleep 1; done' &
        sleep 0.2
        exit 0
        """
        let process = try #require(StdioChildProcess.spawn(
            path: "/bin/sh",
            arguments: ["sh", "-c", script],
            environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: NSTemporaryDirectory()
        ))

        var output = Data()
        let deadline = Date().addingTimeInterval(3)
        while !output.contains(UInt8(ascii: "\n")), Date() < deadline {
            guard process.readOutput(into: &output, deadline: deadline) else { break }
        }
        let line = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let worker = try #require(pid_t(line))
        // Let the leader exit first, leaving only the worker in the group.
        try await Task.sleep(for: .milliseconds(500))

        process.terminate()

        #expect(await hasExited(worker))
    }

    @Test func exitCodeReportsTheLeadersStatusAndNilWhileItRuns() throws {
        func spawn(_ script: String) throws -> StdioChildProcess {
            try #require(StdioChildProcess.spawn(
                path: "/bin/sh", arguments: ["sh", "-c", script],
                environment: ["PATH": "/usr/bin:/bin"], workingDirectory: NSTemporaryDirectory()
            ))
        }
        let ok = try spawn("exit 0")
        defer { ok.terminate() }
        #expect(ok.exitCode(within: 3) == 0)

        let failing = try spawn("exit 3")
        defer { failing.terminate() }
        #expect(failing.exitCode(within: 3) == 3)

        let running = try spawn("sleep 5")
        defer { running.terminate() }
        #expect(running.exitCode(within: 0.2) == nil)
    }

    private func hasExited(_ pid: pid_t) async -> Bool {
        for _ in 0..<150 {
            if kill(pid, 0) == -1 && errno == ESRCH { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
