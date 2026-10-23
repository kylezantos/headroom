import Foundation
import Testing
@testable import HeadroomCore

/// Brief 03 (Remote Control opt-out on the PTY fallback) and Brief 02 (which stage
/// produced a failure). Every CLI here is a fake zsh script in a temp directory.
struct ClaudeUsageCLIProbeTests {
    // MARK: argv

    @Test func interactiveLaunchCarriesTheRemoteControlOptOut() throws {
        for version in ["2.1.303 (Claude Code)", "2.1.216 (Claude Code)", "1.0.90 (Claude Code)"] as [String?]
            + [nil, "unexpected output"] {
            let argv = ClaudeUsageCLIProbe.interactiveArguments(claudePath: "/bin/claude", versionOutput: version)
            #expect(argv.count == 3)
            #expect(argv.first == "/bin/claude")
            #expect(argv[1] == "--settings")
            let object = try JSONSerialization.jsonObject(with: Data(argv[2].utf8)) as? [String: Any]
            #expect(object?["disableRemoteControl"] as? Bool == true)
            #expect(object?["remoteControlAtStartup"] as? Bool == false)
            #expect(object?.count == 2)
        }
    }

    @Test func cliOlderThanTheSettingsFlagLaunchesBare() {
        // 1.0.50 has no `--settings`; passing it would make the CLI exit on startup.
        #expect(ClaudeUsageCLIProbe.interactiveArguments(
            claudePath: "/bin/claude", versionOutput: "1.0.50 (Claude Code)"
        ) == ["/bin/claude"])
        #expect(ClaudeUsageCLIProbe.interactiveArguments(
            claudePath: "/bin/claude", versionOutput: "1.0.89 (Claude Code)"
        ) == ["/bin/claude"])
    }

    @Test func printInvocationIsUnchanged() {
        #expect(ClaudeUsageCLIProbe.printUsageArguments == ["-p", "/usage", "--no-session-persistence"])
    }

    // MARK: boot classification

    @Test func remoteControlNoticesBesideAReadyPromptStillClassifyReady() {
        for notice in [
            "Remote Control is disabled by your organization's policy (managed setting `disableRemoteControl`).",
            "Remote Control was turned off by your organization's policy.",
            "/rc connecting…",
        ] {
            #expect(ClaudeUsageCLIProbe.classifyBootText("""
            Claude Code v2.1.303
            Fable 5 with high effort · Claude Max
            ⚠ \(notice)
            ────────────────────────────────────────────────
            ❯ Try "fix lint errors"
            ────────────────────────────────────────────────
            ⏸ manual mode on
            """) == .ready)
        }
        // A notice with no prompt is not a ready screen.
        #expect(ClaudeUsageCLIProbe.classifyBootText("""
        Claude Code v2.1.303
        Remote Control was turned off by your organization's policy.
        """) == .unknown)
    }

    // MARK: fake CLI integration

    @Test func ptyFallbackLaunchesWithTheOptOutAndSkipsPromptHistory() async throws {
        let fixture = try FakeClaude(script: """
        #!/bin/zsh
        print -r -- "argv:$*" >> "$HEADROOM_FIXTURE_TRACE"
        if [[ "$1" == "--version" ]]; then
          print '2.1.216 (Claude Code)'
          exit 0
        fi
        print -r -- "history:${CLAUDE_CODE_SKIP_PROMPT_HISTORY:-unset}" >> "$HEADROOM_FIXTURE_TRACE"
        print 'Claude Code v2.1.216'
        print 'Remote Control was turned off by your organization'"'"'s policy.'
        print '❯ Try "fix lint errors"'
        if read -r -t 8 captured; then
          print 'Current session'
          print '12% used'
          print 'Current week (all models)'
          print '34% used'
        fi
        """)
        defer { fixture.remove() }

        let (result, trace) = await fixture.probe().captureWithTrace()

        guard case .panel(let text, _) = result else {
            Issue.record("expected the PTY panel, got \(result)"); return
        }
        #expect(ClaudeUsageParser.parse(text).count == 2)
        #expect(trace.print == .versionBelowFloor)
        #expect(trace.ptyRemoteControlOptOut == true)
        #expect(trace.ptyBoot == .ready)
        #expect(trace.ptyBootFingerprint == nil)
        let lines = try fixture.traceLines()
        #expect(lines.contains("argv:--settings \(ClaudeUsageCLIProbe.remoteControlOptOutSettings)"))
        #expect(lines.contains("history:1"))
        #expect(!lines.contains { $0.hasPrefix("argv:-p") })
    }

    @Test func unknownBootScreenIsFingerprintedWithoutItsText() async throws {
        let fixture = try FakeClaude(script: """
        #!/bin/zsh
        print -r -- "argv:$*" >> "$HEADROOM_FIXTURE_TRACE"
        if [[ "$1" == "--version" ]]; then
          print '2.1.302 (Claude Code)'
          exit 0
        fi
        if [[ "$1" == "-p" ]]; then
          print 'A report shape this parser has never seen'
          exit 0
        fi
        print 'Welcome to the brand new announcement screen'
        print 'Claude Code'
        print '1. Remind me later'
        if read -r -t 8 captured; then
          print -r -- "input:$captured" >> "$HEADROOM_FIXTURE_TRACE"
        fi
        """)
        defer { fixture.remove() }

        let (result, trace) = await fixture.probe().captureWithTrace()

        #expect(result == .unknownUI)
        #expect(trace.print == .unparseable)
        #expect(trace.printRetry == nil)
        #expect(trace.ptyBoot == .unrecognized)
        #expect(trace.failedStage == "pty-boot-unrecognized")
        let fingerprint = try #require(trace.ptyBootFingerprint)
        #expect(fingerprint.byteCount > 0)
        #expect(fingerprint.hasBanner)
        #expect(!fingerprint.hasPromptMarker)
        #expect(!fingerprint.hasTryPlaceholder)
        let digest = try #require(fingerprint.firstLineDigest)
        #expect(digest.count == 8)
        #expect(digest.allSatisfy { $0.isHexDigit })

        let lines = try fixture.traceLines()
        // Unparseable print output is not retried, and nothing was typed into the screen.
        #expect(lines.filter { $0.hasPrefix("argv:-p") }.count == 1)
        #expect(!lines.contains { $0.hasPrefix("input:") })

        let report = ClaudeCapabilityDiagnostic.lines(
            account: .builtIn, versionBand: .printSupported, outcome: .unknownSurface,
            events: [], trace: trace
        ).joined(separator: "\n")
        #expect(report.contains("print-stage=unparseable"))
        #expect(report.contains("pty-boot=unrecognized"))
        #expect(report.contains("failed-stage=pty-boot-unrecognized"))
        #expect(report.contains("first-line-sha256=\(digest)"))
        for forbidden in ["Welcome", "announcement", "Remind me", "report shape"] {
            #expect(!report.contains(forbidden))
        }
    }

    @Test func timedOutPrintRunIsRetriedOnceBeforeThePTY() async throws {
        let fixture = try FakeClaude(script: """
        #!/bin/zsh
        print -r -- "argv:$*" >> "$HEADROOM_FIXTURE_TRACE"
        if [[ "$1" == "--version" ]]; then
          print '2.1.302 (Claude Code)'
          exit 0
        fi
        if [[ "$1" == "-p" ]]; then
          if [[ ! -e "$HEADROOM_FIXTURE_TRACE.slow" ]]; then
            : > "$HEADROOM_FIXTURE_TRACE.slow"
            sleep 3
          fi
          print 'Current session: 10% used'
          print 'Current week (all models): 20% used'
          exit 0
        fi
        print 'unexpected interactive launch'
        """)
        defer { fixture.remove() }

        let (result, trace) = await fixture.probe(printTimeout: 1, printRetryTimeout: 10).captureWithTrace()

        guard case .panel(let text, _) = result else {
            Issue.record("expected the retried print report, got \(result)"); return
        }
        #expect(ClaudeUsageParser.parse(text).count == 2)
        #expect(trace.print == .timedOut)
        #expect(trace.printRetry == .report)
        #expect(trace.ptyBoot == nil)
        #expect(trace.ptyRemoteControlOptOut == nil)
        let lines = try fixture.traceLines()
        #expect(lines.filter { $0 == "argv:-p /usage --no-session-persistence" }.count == 2)
        #expect(!lines.contains { $0.hasPrefix("argv:--settings") || $0 == "argv:" })
    }
}

/// A fake `claude` executable plus a trace file it appends to.
private struct FakeClaude {
    let directory: URL
    let executable: URL
    let trace: URL

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("claude")
        trace = directory.appendingPathComponent("trace")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func probe(printTimeout: TimeInterval = 20, printRetryTimeout: TimeInterval = 40) -> ClaudeUsageCLIProbe {
        let locator = CLIExecutableLocator(
            executableName: "claude", fallbackPaths: [executable.path],
            hintStore: FakeClaudeHintStore(), shellSearch: { [executable] in .completed(candidates: [executable.path]) },
            validate: { _ in .executable }
        )
        return ClaudeUsageCLIProbe(
            locator: locator,
            workingDirectory: directory.path,
            environmentOverrides: ["HEADROOM_FIXTURE_TRACE": trace.path],
            bootTimeout: 4,
            panelTimeout: 4,
            printTimeout: printTimeout,
            printRetryTimeout: printRetryTimeout
        )
    }

    func traceLines() throws -> [String] {
        try String(contentsOf: trace, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class FakeClaudeHintStore: CLIExecutableHintStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func hint(for executableName: String) -> String? { lock.withLock { value } }
    func setHint(_ path: String?, for executableName: String) { lock.withLock { value = path } }
}
