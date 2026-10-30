import Foundation
import Testing
@testable import HeadroomCore

struct ClaudeCapabilityDiagnosticTests {
    @Test func reportUsesOnlyAllowlistedCategoriesAndEventAge() {
        let now = Date(timeIntervalSince1970: 10_000)
        let events = CLIExecutableDiagnosticCategory.allCases.enumerated().map { offset, category in
            CLIExecutableDiagnosticEvent(
                category: category,
                observedAt: now.addingTimeInterval(TimeInterval(-offset))
            )
        }

        for account in ClaudeCapabilityDiagnosticAccount.allCases {
            for band in ClaudeCLIVersionBand.allCases {
                for outcome in ClaudeCapabilityDiagnosticOutcome.allCases {
                    let output = ClaudeCapabilityDiagnostic.lines(
                        account: account,
                        versionBand: band,
                        outcome: outcome,
                        events: events,
                        now: now
                    ).joined(separator: "\n")

                    #expect(output.contains("account-category=\(account.rawValue)"))
                    #expect(output.contains("cli-version-band=\(band.rawValue)"))
                    #expect(output.contains("capability-outcome=\(outcome.rawValue)"))
                    #expect(output.contains("age-seconds="))
                }
            }
        }
    }

    @Test func reportCannotContainPathIdentityProviderOutputCredentialsOrRawErrors() {
        let output = ClaudeCapabilityDiagnostic.lines(
            account: .extra,
            versionBand: .printSupported,
            outcome: .trustRequired,
            events: [
                CLIExecutableDiagnosticEvent(
                    category: .hintInvalidated,
                    observedAt: Date(timeIntervalSince1970: 1)
                ),
            ],
            now: Date(timeIntervalSince1970: 2)
        ).joined(separator: "\n")

        for forbidden in [
            "/Users/example/.local/bin/claude",
            "/Users/example/.claude-extra",
            "example@example.com",
            "Personal Account",
            "sk-ant-secret",
            "oauthAccessToken",
            "Current week (all models)",
            "permission denied at /private/path",
        ] {
            #expect(!output.contains(forbidden))
        }
    }

    @Test func traceRendersEveryStageAsAClosedEnumLine() {
        for stage in ClaudePrintStage.allCases {
            let output = ClaudeCapabilityDiagnostic.lines(
                account: .builtIn, versionBand: .printSupported, outcome: .captureFailed,
                events: [], trace: ClaudeCaptureTrace(print: stage)
            )
            #expect(output.contains("print-stage=\(stage.rawValue)"))
            let readUsage = stage == .report || stage == .timedOutAfterReport
            #expect(output.contains("failed-stage=print-\(stage.rawValue)") == !readUsage)
        }
        for boot in ClaudePTYBootStage.allCases {
            let output = ClaudeCapabilityDiagnostic.lines(
                account: .extra, versionBand: .ptyFallback, outcome: .unknownSurface,
                events: [],
                trace: ClaudeCaptureTrace(print: .versionBelowFloor, ptyRemoteControlOptOut: true, ptyBoot: boot)
            )
            #expect(output.contains("pty-boot=\(boot.rawValue)"))
            #expect(output.contains("pty-remote-control-opt-out=applied"))
            #expect(output.contains(boot == .ready ? "failed-stage=pty-panel" : "failed-stage=pty-boot-\(boot.rawValue)"))
        }
    }

    /// The Chrome onboarding question is named as its own boot stage and outcome, never
    /// folded into the unrecognized-screen stage or fingerprinted.
    @Test func aStartupQuestionIsItsOwnBootStage() {
        let output = ClaudeCapabilityDiagnostic.lines(
            account: .builtIn, versionBand: .printSupported, outcome: .startupQuestion, events: [],
            trace: ClaudeCaptureTrace(print: .unparseable, ptyRemoteControlOptOut: true, ptyBoot: .startupQuestion)
        )
        #expect(output.contains("capability-outcome=startupQuestion"))
        #expect(output.contains("pty-boot=startupQuestion"))
        #expect(output.contains("failed-stage=pty-boot-startupQuestion"))
        #expect(!output.contains { $0.hasPrefix("pty-boot-fingerprint") })
        #expect(ClaudeCaptureTrace(ptyBoot: .startupQuestion).failedStage == "pty-boot-startupQuestion")
    }

    @Test func unparseablePTYPanelIsNamedEvenWhenTheResultCountsAsAvailable() {
        for panel in ClaudePTYPanelStage.allCases {
            let output = ClaudeCapabilityDiagnostic.lines(
                account: .builtIn, versionBand: .ptyFallback, outcome: .available, events: [],
                trace: ClaudeCaptureTrace(print: .versionBelowFloor, ptyBoot: .ready, ptyPanel: panel)
            )
            #expect(output.contains("pty-panel=\(panel.rawValue)"))
            #expect(output.contains("failed-stage=pty-panel-\(panel.rawValue)") == (panel != .parsed))
            #expect(output.contains { $0.hasPrefix("failed-stage=") } == (panel != .parsed))
        }
    }

    @Test func retriedPrintReportsBothRunsAndASuccessHasNoFailedStage() {
        let output = ClaudeCapabilityDiagnostic.lines(
            account: .builtIn, versionBand: .printSupported, outcome: .available,
            events: [], trace: ClaudeCaptureTrace(print: .timedOut, printRetry: .report)
        )
        #expect(output.contains("print-stage=timedOut"))
        #expect(output.contains("print-retry-stage=report"))
        #expect(!output.contains { $0.hasPrefix("failed-stage=") })
    }

    @Test func bootFingerprintCarriesMarkersAndAHashButNoText() {
        let screen = """
         [<u [>1u [>4;2m
        ╭──────────────────────────────────────╮
        │ ✻ Welcome back, Person Example!      │
        ╰──────────────────────────────────────╯
        Claude Code v2.1.400 · Fable 5 · Person Example
        Signed in as person@example.com
        ~/Library/Application Support/Headroom/ClaudeProbe
        Something new: sign the 2026 terms /rc
        ❯ Accept
        """
        let fingerprint = ClaudeBootFingerprint(rawByteCount: 512, strippedText: screen)
        #expect(fingerprint.byteCount == 512)
        #expect(fingerprint.hasPromptMarker)
        #expect(!fingerprint.hasTryPlaceholder)
        #expect(fingerprint.hasBanner)
        #expect(fingerprint.hasRemoteControlText)
        // Residue, borders, the welcome line, the banner, the email line and the path line
        // are all skipped: the hash is of the first line that describes the screen.
        let expected = String(CompanionSyncCodec.digest(Data("Something new: sign the 2026 terms /rc".utf8)).prefix(8))
        #expect(fingerprint.firstLineDigest == expected)
        // The same screen repainted with other spacing hashes the same.
        let repainted = ClaudeBootFingerprint(
            rawByteCount: 512,
            strippedText: "Claude Code v2.1.400\rSomething   new: sign the 2026\tterms /rc\r❯ Accept"
        )
        #expect(fingerprint.firstLineDigest == repainted.firstLineDigest)
        #expect(ClaudeBootFingerprint(rawByteCount: 3, strippedText: "  \n [>1u \n╭────╮").firstLineDigest == nil)
        #expect(ClaudeBootFingerprint(
            rawByteCount: 3, strippedText: "Welcome to Claude Code\nperson@example.com"
        ).firstLineDigest == nil)

        let output = ClaudeCapabilityDiagnostic.lines(
            account: .builtIn, versionBand: .printSupported, outcome: .unknownSurface, events: [],
            trace: ClaudeCaptureTrace(print: .timedOut, printRetry: .timedOut, ptyBoot: .unrecognized,
                                      ptyBootFingerprint: fingerprint)
        ).joined(separator: "\n")
        #expect(output.contains(
            "pty-boot-fingerprint bytes=512 prompt-marker=present try-placeholder=absent banner=present"
                + " remote-control-text=present first-line-sha256=\(fingerprint.firstLineDigest ?? "")"
        ))
        #expect(output.contains("failed-stage=pty-boot-unrecognized"))
        for forbidden in ["Something", "terms", "person@example.com", "Person Example", "Accept", "v2.1.400"] {
            #expect(!output.contains(forbidden))
        }
    }

    @Test func remoteControlMarkerIgnoresPathSegments() {
        for text in ["/rc connecting…", "status: /rc", "Remote Control is on"] {
            #expect(ClaudeBootFingerprint(rawByteCount: 1, strippedText: text).hasRemoteControlText)
        }
        for text in ["~/src/rc/config", "/etc/rc.local", "open /rcfile", "Claude Code"] {
            #expect(!ClaudeBootFingerprint(rawByteCount: 1, strippedText: text).hasRemoteControlText)
        }
    }

    @Test func CLIOutputsMapToSafeVersionBands() {
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("2.1.217 (Claude Code)") == .printSupported)
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("2.1.216 (Claude Code)") == .ptyFallback)
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("unexpected output") == .unknown)
    }
}
