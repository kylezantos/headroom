import Foundation

public enum ClaudeCLIVersionBand: String, Sendable, Equatable, CaseIterable {
    case printSupported
    case ptyFallback
    case unknown
}

public enum ClaudeCapabilityDiagnosticAccount: String, Sendable, Equatable, CaseIterable {
    case builtIn
    case extra
}

public enum ClaudeCapabilityDiagnosticOutcome: String, Sendable, Equatable, CaseIterable {
    case available
    case loginRequired
    case trustRequired
    case confirmedAbsent
    case discoveryInconclusive
    case captureFailed
    case unknownSurface
}

/// How the print-mode (`claude -p "/usage"`) attempt ended. Every value except
/// `report` and `signedOut` sends the probe on to the PTY fallback.
public enum ClaudePrintStage: String, Sendable, Equatable, CaseIterable {
    case report
    case signedOut
    /// `--version` failed to run or hit its deadline.
    case versionUnavailable
    /// `--version` printed no x.y.z version.
    case versionUnreadable
    /// Readable version below the 2.1.217 print floor.
    case versionBelowFloor
    case timedOut
    case launchFailed
    /// Print ran but its output parsed into no usage window.
    case unparseable
}

/// How the PTY fallback's boot screen was classified.
public enum ClaudePTYBootStage: String, Sendable, Equatable, CaseIterable {
    case ready
    case loginRequired
    case trustRequired
    /// The only producer of "Claude opened an unrecognized setup screen".
    case unrecognized
    case noOutput
    case spawnFailed
}

/// Redaction-safe description of a boot screen the classifier did not recognize
/// (Brief 02). Counts, marker booleans and a truncated hash only, so two reports can be
/// compared without either carrying the screen's text.
public struct ClaudeBootFingerprint: Sendable, Equatable {
    public let byteCount: Int
    public let hasPromptMarker: Bool
    public let hasTryPlaceholder: Bool
    public let hasBanner: Bool
    public let hasRemoteControlText: Bool
    /// First 8 hex digits of the SHA-256 of the first line that holds a word, with its
    /// whitespace collapsed. Nil when no line has one. Leading lines of terminal-mode
    /// residue ("[<u [>1u") are skipped so the hash describes the screen, not the
    /// escape preamble every boot shares.
    public let firstLineDigest: String?

    public init(rawByteCount: Int, strippedText: String) {
        byteCount = rawByteCount
        hasPromptMarker = strippedText.contains("❯")
        hasTryPlaceholder = strippedText.localizedCaseInsensitiveContains("Try \"")
        hasBanner = strippedText.localizedCaseInsensitiveContains("Claude Code")
        hasRemoteControlText = strippedText.localizedCaseInsensitiveContains("Remote Control")
            || strippedText.contains("/rc")
        let firstLine = strippedText
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { $0.contains(/\p{L}{3}/) }
        firstLineDigest = firstLine.map { line in
            String(CompanionSyncCodec.digest(Data(line.utf8)).prefix(8))
        }
    }
}

/// Which stages a Claude capture went through and how each ended. Built by
/// `ClaudeUsageCLIProbe.captureWithTrace()`; closed enums plus a fingerprint, never
/// CLI output.
public struct ClaudeCaptureTrace: Sendable, Equatable {
    public var print: ClaudePrintStage?
    /// Set only when the first print run timed out and was retried.
    public var printRetry: ClaudePrintStage?
    /// Whether the PTY launch carried the Remote Control opt-out. Nil when the PTY
    /// fallback did not run.
    public var ptyRemoteControlOptOut: Bool?
    public var ptyBoot: ClaudePTYBootStage?
    public var ptyBootFingerprint: ClaudeBootFingerprint?

    public init(
        print: ClaudePrintStage? = nil,
        printRetry: ClaudePrintStage? = nil,
        ptyRemoteControlOptOut: Bool? = nil,
        ptyBoot: ClaudePTYBootStage? = nil,
        ptyBootFingerprint: ClaudeBootFingerprint? = nil
    ) {
        self.print = print
        self.printRetry = printRetry
        self.ptyRemoteControlOptOut = ptyRemoteControlOptOut
        self.ptyBoot = ptyBoot
        self.ptyBootFingerprint = ptyBootFingerprint
    }

    /// The stage that decided a failed capture, e.g. `print-timedOut` or
    /// `pty-boot-unrecognized`. Nil when nothing ran (CLI discovery failed first).
    public var failedStage: String? {
        if let ptyBoot {
            return ptyBoot == .ready ? "pty-panel" : "pty-boot-\(ptyBoot.rawValue)"
        }
        guard let stage = printRetry ?? print else { return nil }
        return "print-\(stage.rawValue)"
    }
}

/// Redaction-safe Claude incident output. Its inputs are closed enums and timestamps,
/// so executable/config paths, identities, provider output, and caught errors cannot
/// cross this boundary accidentally.
///
/// R16/R17 (2026-09-19 sign-in plan) extend that boundary to the sign-out record: a
/// `SignOutEvent` carries only an account key Headroom itself minted and a detection
/// time, so it crosses here for the same reason the closed enums above do.
public enum ClaudeCapabilityDiagnostic {
    public static func lines(
        account: ClaudeCapabilityDiagnosticAccount,
        versionBand: ClaudeCLIVersionBand,
        outcome: ClaudeCapabilityDiagnosticOutcome,
        events: [CLIExecutableDiagnosticEvent],
        trace: ClaudeCaptureTrace? = nil,
        signOutEvents: [SignOutEvent] = [],
        now: Date = Date()
    ) -> [String] {
        var lines = [
            "account-category=\(account.rawValue)",
            "cli-version-band=\(versionBand.rawValue)",
            "capability-outcome=\(outcome.rawValue)",
        ]
        if let trace {
            lines += traceLines(trace, outcome: outcome)
        }
        lines += events.suffix(8).map { event in
            let age = max(0, Int(now.timeIntervalSince(event.observedAt)))
            return "capability-event=\(event.category.rawValue) age-seconds=\(age)"
        }
        lines += signOutLines(signOutEvents)
        return lines
    }

    private static func traceLines(
        _ trace: ClaudeCaptureTrace,
        outcome: ClaudeCapabilityDiagnosticOutcome
    ) -> [String] {
        var lines: [String] = []
        if let stage = trace.print { lines.append("print-stage=\(stage.rawValue)") }
        if let stage = trace.printRetry { lines.append("print-retry-stage=\(stage.rawValue)") }
        if let optOut = trace.ptyRemoteControlOptOut {
            lines.append("pty-remote-control-opt-out=\(optOut ? "applied" : "omitted")")
        }
        if let boot = trace.ptyBoot { lines.append("pty-boot=\(boot.rawValue)") }
        if let fingerprint = trace.ptyBootFingerprint {
            lines.append(
                "pty-boot-fingerprint bytes=\(fingerprint.byteCount)"
                    + " prompt-marker=\(presence(fingerprint.hasPromptMarker))"
                    + " try-placeholder=\(presence(fingerprint.hasTryPlaceholder))"
                    + " banner=\(presence(fingerprint.hasBanner))"
                    + " remote-control-text=\(presence(fingerprint.hasRemoteControlText))"
                    + " first-line-sha256=\(fingerprint.firstLineDigest ?? "none")"
            )
        }
        if outcome != .available, let failed = trace.failedStage {
            lines.append("failed-stage=\(failed)")
        }
        return lines
    }

    private static func presence(_ value: Bool) -> String { value ? "present" : "absent" }

    /// The count and the detection timestamps, grouped per account key. The count is
    /// always printed so an empty record reads as "none observed" rather than as a
    /// section that failed to run.
    private static func signOutLines(_ events: [SignOutEvent]) -> [String] {
        var lines = ["sign-out-events=\(events.count)"]
        var order: [AccountKey] = []
        var grouped: [AccountKey: [Date]] = [:]
        for event in events {
            if grouped[event.account] == nil { order.append(event.account) }
            grouped[event.account, default: []].append(event.detectedAt)
        }
        let formatter = ISO8601DateFormatter()
        for account in order {
            let detections = grouped[account] ?? []
            lines.append("sign-out-account=\(account.description) count=\(detections.count)")
            lines += detections.map { "sign-out-detected-at=\(formatter.string(from: $0))" }
        }
        return lines
    }
}
