import Foundation
import Testing
@testable import HeadroomCore

/// Parsing-only coverage for the bounded login-shell search output. No real shell, npm,
/// or filesystem participates (KTD2).
struct CLIExecutableResolverSupplementalTests {
    private let executableMarker = "__HEADROOM_EXECUTABLE__"
    private let npmPrefixMarker = "__HEADROOM_NPM_PREFIX__"
    private let npmAbsentMarker = "__HEADROOM_NPM_ABSENT__"

    @Test func missingMarkerIsInvalidOutput() {
        #expect(parse("some startup noise") == .invalidOutput)
    }

    @Test func directHitLeavesNpmUnreadRatherThanConfirmedAbsent() {
        // A non-empty direct section means the shell skipped the npm query, so npm was
        // never consulted — unresolved, not a negative answer from npm (R3).
        let output = """
        startup noise
        \(executableMarker)
        /opt/homebrew/bin/claude
        """
        #expect(parse(output) == .completed(
            candidates: ["/opt/homebrew/bin/claude"],
            supplemental: .unresolved
        ))
    }

    @Test func noneStrategyNeverAttemptsSupplementalDiscovery() {
        let output = "\(executableMarker)\n"
        #expect(parse(output, supplemental: .none) == .completed(
            candidates: [],
            supplemental: .notAttempted
        ))
    }

    @Test func npmAbsentMarkerReportsSourceUnavailable() {
        let output = """
        \(executableMarker)

        \(npmAbsentMarker)
        """
        #expect(parse(output) == .completed(candidates: [], supplemental: .sourceUnavailable))
    }

    @Test func validPrefixDerivesDocumentedBinLauncher() {
        let output = """
        \(executableMarker)

        \(npmPrefixMarker)
        /Users/Neil/.npm-global
        """
        #expect(parse(output) == .completed(
            candidates: [],
            supplemental: .candidate("/Users/Neil/.npm-global/bin/claude")
        ))
    }

    @Test func prefixIsNormalizedBeforeDerivation() {
        for prefix in [
            "/Users/Neil/.npm-global/",
            "/Users/Neil/tools/../.npm-global",
            "  /Users/Neil/.npm-global  ",
        ] {
            let output = "\(executableMarker)\n\n\(npmPrefixMarker)\n\(prefix)\n"
            #expect(parse(output) == .completed(
                candidates: [],
                supplemental: .candidate("/Users/Neil/.npm-global/bin/claude")
            ))
        }
    }

    @Test func malformedPrefixResponsesStayUnresolved() {
        let malformed = [
            "",
            "   ",
            ".npm-global",
            "npm-global/bin",
            "~/.npm-global",
            "npm warn config global deprecated\n/Users/Neil/.npm-global",
            "/Users/Neil/.npm-global\n/Users/Neil/.npm-global",
            "/Users/Neil/.npm\u{1B}[0m-global",
        ]
        for response in malformed {
            let output = "\(executableMarker)\n\n\(npmPrefixMarker)\n\(response)\n"
            #expect(
                parse(output) == .completed(candidates: [], supplemental: .unresolved),
                "Expected unresolved supplemental for \(response.debugDescription)"
            )
        }
    }

    @Test func brokenMarkerProtocolAfterDirectMissStaysUnresolved() {
        // The shell emits one npm marker whenever the direct lookup misses, so neither
        // marker after an empty direct section means the protocol broke.
        #expect(parse("\(executableMarker)\n") == .completed(
            candidates: [],
            supplemental: .unresolved
        ))
    }

    @Test func nonEmptyDirectSectionLeavesTheSkippedNpmQueryUnresolved() {
        let output = """
        \(executableMarker)
        claude not found but printed anyway
        """
        #expect(parse(output) == .completed(
            candidates: ["claude not found but printed anyway"],
            supplemental: .unresolved
        ))
    }

    @Test func noneStrategyKeepsNotAttemptedForANonEmptyDirectSection() {
        // R5: Codex/Grok/Cursor never query npm, so their supplemental provenance is
        // "not attempted" regardless of what the direct section printed.
        let output = """
        \(executableMarker)
        codex: aliased to /Users/Neil/bin/codex
        """
        #expect(parse(output, supplemental: .none) == .completed(
            candidates: ["codex: aliased to /Users/Neil/bin/codex"],
            supplemental: .notAttempted
        ))
    }

    @Test func aliasDefinitionIsCarriedAsOpaqueTextNeverParsedIntoAPath() {
        let output = """
        \(executableMarker)
        claude: aliased to /Users/Neil/.claude/local/claude
        """
        #expect(parse(output) == .completed(
            candidates: ["claude: aliased to /Users/Neil/.claude/local/claude"],
            supplemental: .unresolved
        ))
    }

    @Test func markerTextEmbeddedInAPrefixDoesNotResectionTheOutput() {
        let output = """
        \(executableMarker)

        \(npmPrefixMarker)
        /Users/test/\(executableMarker)/.npm-global
        """
        #expect(parse(output) == .completed(
            candidates: [],
            supplemental: .candidate("/Users/test/\(executableMarker)/.npm-global/bin/claude")
        ))
    }

    @Test func noiseLinesContainingMarkerTextAreDataNotProtocol() {
        let output = """
        npm warn ignoring \(npmPrefixMarker) in config
        \(executableMarker)
        /opt/homebrew/bin/claude \(npmAbsentMarker) leftover
        """
        #expect(parse(output) == .completed(
            candidates: ["/opt/homebrew/bin/claude \(npmAbsentMarker) leftover"],
            supplemental: .unresolved
        ))
    }

    @Test func npmQueryRunsInsideTheSameBoundedShellOperationAfterADirectMiss() {
        let command = CLIExecutableResolver.searchCommand(
            named: "claude",
            supplemental: .npmGlobalPrefix,
            shellPath: "/bin/zsh"
        )
        #expect(command.contains(executableMarker))
        #expect(command.contains(npmPrefixMarker))
        #expect(command.contains(npmAbsentMarker))
        #expect(command.contains("command -v -- claude"))
        #expect(command.contains("npm prefix -g"))
        // KTD1a: npm is queried only after a direct miss, inside one shell invocation.
        #expect(command.contains("if [ -z \"$__headroom_found\" ]"))
        #expect(CLIExecutableResolver.loginShellTimeout == 5)

        let direct = CLIExecutableResolver.searchCommand(
            named: "codex",
            supplemental: .none,
            shellPath: "/bin/zsh"
        )
        #expect(!direct.contains("npm"))
    }

    @Test func fishLoginShellsGetFishSyntaxWithTheSameMarkerProtocol() {
        let fish = CLIExecutableResolver.searchCommand(
            named: "claude",
            supplemental: .npmGlobalPrefix,
            shellPath: "/opt/homebrew/bin/fish"
        )
        #expect(fish.contains("set __headroom_found (command -v -- claude)"))
        #expect(fish.contains("if test -z \"$__headroom_found\""))
        #expect(fish.contains("else; printf"))
        #expect(fish.hasSuffix("end; end"))
        #expect(fish.contains("npm prefix -g"))
        // POSIX-only syntax aborts fish before any marker is printed.
        #expect(!fish.contains("__headroom_found=$("))
        #expect(!fish.contains("; then "))
        #expect(!fish.contains("; fi"))
        for marker in [executableMarker, npmPrefixMarker, npmAbsentMarker] {
            #expect(fish.contains(marker))
        }

        // The direct-only command is dialect-neutral and stays byte-identical.
        #expect(
            CLIExecutableResolver.searchCommand(
                named: "codex",
                supplemental: .none,
                shellPath: "/opt/homebrew/bin/fish"
            ) == CLIExecutableResolver.searchCommand(
                named: "codex",
                supplemental: .none,
                shellPath: "/bin/zsh"
            )
        )
    }

    @Test func parsingIsDialectAgnostic() {
        // Both dialects print the same marker records, so one parser reads both.
        let output = """
        \(executableMarker)

        \(npmPrefixMarker)
        /Users/Neil/.npm-global
        """
        #expect(parse(output) == .completed(
            candidates: [],
            supplemental: .candidate("/Users/Neil/.npm-global/bin/claude")
        ))
        for shellPath in ["/bin/zsh", "/opt/homebrew/bin/fish"] {
            let command = CLIExecutableResolver.searchCommand(
                named: "claude",
                supplemental: .npmGlobalPrefix,
                shellPath: shellPath
            )
            for marker in [executableMarker, npmPrefixMarker, npmAbsentMarker] {
                #expect(command.contains("printf '\\n\(marker)\\n'"))
            }
        }
    }

    private func parse(
        _ output: String,
        supplemental: CLIExecutableSupplementalStrategy = .npmGlobalPrefix
    ) -> CLIExecutableShellResult {
        CLIExecutableResolver.parseSearchOutput(
            output,
            executableName: "claude",
            supplemental: supplemental
        )
    }
}

@Suite struct ProviderExecutableResolutionCharacterizationTests {
    private let executableMarker = "__HEADROOM_EXECUTABLE__"

    @Test func fixedFallbacksMatchTheSupportedInstallerLocationsInPriorityOrder() {
        #expect(CursorUsageCLIProbe.fallbackPaths == [
            "\(NSHomeDirectory())/.local/bin/cursor-agent",
            "/opt/homebrew/bin/cursor-agent",
            "/usr/local/bin/cursor-agent",
        ])
        #expect(GrokACPUsageSource.fallbackPaths == [
            "\(NSHomeDirectory())/.local/bin/grok",
            "\(NSHomeDirectory())/.grok/bin/grok",
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok",
        ])
    }

    @Test func versionManagerShellCandidateBeatsEveryFixedFallback() {
        for (name, fallbackPaths) in [
            ("cursor-agent", CursorUsageCLIProbe.fallbackPaths),
            ("grok", GrokACPUsageSource.fallbackPaths),
        ] {
            let shim = "/Users/test/.mise/shims/\(name)"
            let resolved = CLIExecutableResolver.selectExecutable(
                loginShellOutput: "\(executableMarker)\n\(shim)\n",
                fallbackPaths: fallbackPaths,
                isExecutable: { $0 == shim || fallbackPaths.contains($0) }
            )
            #expect(resolved == shim)
        }
    }

    @Test func nativeUserLocalCandidateWinsWhenMultipleFixedFallbacksAreExecutable() {
        #expect(CLIExecutableResolver.selectExecutable(
            loginShellOutput: nil,
            fallbackPaths: CursorUsageCLIProbe.fallbackPaths,
            isExecutable: { CursorUsageCLIProbe.fallbackPaths.contains($0) }
        ) == CursorUsageCLIProbe.fallbackPaths.first)
        #expect(CLIExecutableResolver.selectExecutable(
            loginShellOutput: nil,
            fallbackPaths: GrokACPUsageSource.fallbackPaths,
            isExecutable: { GrokACPUsageSource.fallbackPaths.contains($0) }
        ) == GrokACPUsageSource.fallbackPaths.first)
    }

    @Test func homebrewCandidateRecoversAfterLoginShellMiss() {
        for (homebrew, fallbackPaths) in [
            ("/opt/homebrew/bin/cursor-agent", CursorUsageCLIProbe.fallbackPaths),
            ("/opt/homebrew/bin/grok", GrokACPUsageSource.fallbackPaths),
        ] {
            #expect(CLIExecutableResolver.selectExecutable(
                loginShellOutput: "\(executableMarker)\n",
                fallbackPaths: fallbackPaths,
                isExecutable: { $0 == homebrew }
            ) == homebrew)
        }
    }

    @Test func missingAndNonExecutableCandidatesBothFailClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-provider-resolver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("missing").path
        let nonExecutable = root.appendingPathComponent("non-executable")
        #expect(FileManager.default.createFile(
            atPath: nonExecutable.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        ))

        #expect(CLIExecutableResolver.selectExecutable(
            loginShellOutput: nil,
            fallbackPaths: [missing],
            isExecutable: FileManager.default.isExecutableFile(atPath:)
        ) == nil)
        #expect(CLIExecutableResolver.selectExecutable(
            loginShellOutput: nil,
            fallbackPaths: [nonExecutable.path],
            isExecutable: FileManager.default.isExecutableFile(atPath:)
        ) == nil)
    }
}
