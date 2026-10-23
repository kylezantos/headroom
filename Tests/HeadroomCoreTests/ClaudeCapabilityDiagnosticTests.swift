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
            #expect(output.contains("failed-stage=print-\(stage.rawValue)"))
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
        Something new: sign the 2026 terms, account person@example.com
        Claude Code v2.1.400 · /rc
        ❯ Accept
        """
        let fingerprint = ClaudeBootFingerprint(rawByteCount: 512, strippedText: screen)
        #expect(fingerprint.byteCount == 512)
        #expect(fingerprint.hasPromptMarker)
        #expect(!fingerprint.hasTryPlaceholder)
        #expect(fingerprint.hasBanner)
        #expect(fingerprint.hasRemoteControlText)
        // The escape residue line holds no word, so the hash describes the real first line,
        // and the same screen repainted with other spacing hashes the same.
        let repainted = ClaudeBootFingerprint(
            rawByteCount: 512,
            strippedText: "Something   new: sign the 2026 terms,\taccount person@example.com\r❯ Accept"
        )
        #expect(fingerprint.firstLineDigest == repainted.firstLineDigest)
        #expect(fingerprint.firstLineDigest?.count == 8)
        #expect(ClaudeBootFingerprint(rawByteCount: 3, strippedText: "  \n [>1u ").firstLineDigest == nil)

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
        for forbidden in ["Something", "terms", "person@example.com", "Accept", "v2.1.400"] {
            #expect(!output.contains(forbidden))
        }
    }

    @Test func CLIOutputsMapToSafeVersionBands() {
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("2.1.217 (Claude Code)") == .printSupported)
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("2.1.216 (Claude Code)") == .ptyFallback)
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("unexpected output") == .unknown)
    }
}
