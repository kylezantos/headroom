import Foundation
import Testing
@testable import HeadroomCore

struct FeedbackEmailTests {
    private func macDiagnostics(accounts: [FeedbackDiagnostics.Account]? = nil) -> FeedbackDiagnostics {
        FeedbackDiagnostics(
            appVersion: "1.5.3 (53)",
            operatingSystem: "macOS 26.1",
            architecture: "arm64",
            cliVersions: [
                .init(providerID: .claude, version: .version("2.1.317")),
                .init(providerID: .codex, version: .version("0.155.1")),
                .init(providerID: .copilot, version: .notInstalled),
            ],
            providersOff: [.grok, .cursor],
            accounts: accounts ?? [
                .init(providerID: .claude, position: 1, status: .live),
                .init(providerID: .claude, position: 2, status: .stale("notLoggedIn")),
                .init(providerID: .codex, position: 1, status: .waiting),
            ]
        )
    }

    private func decodedQuery(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Diagnostics lines

    @Test func macBlockListsVersionsProvidersOffAndAccountsByPosition() {
        #expect(macDiagnostics().lines == [
            "Headroom 1.5.3 (53) · macOS 26.1 · arm64",
            "CLIs: Claude 2.1.317 · Codex 0.155.1 · Copilot not installed",
            "Off: Grok, Cursor",
            "Claude #1: live",
            "Claude #2: stale (notLoggedIn)",
            "Codex #1: waiting",
        ])
    }

    @Test func phoneBlockCarriesSyncStatusAndNoCLIOrAccountLines() {
        let phone = FeedbackDiagnostics(appVersion: "1.5.3 (53)", operatingSystem: "iOS 26.1", syncStatus: "On")
        #expect(phone.lines == ["Headroom 1.5.3 (53) · iOS 26.1", "Sync: On"])
    }

    @Test func accountStatusUsesTheCaseNameNeverTheMessage() {
        let status = FeedbackAccountStatus(freshness: .stale(.notLoggedIn("Signed in as kyle@example.com")))
        #expect(status == .stale("notLoggedIn"))
        let text = FeedbackDiagnostics(
            appVersion: nil, operatingSystem: "macOS 26.1",
            accounts: [.init(providerID: .claude, position: 1, status: status)]
        ).lines.joined(separator: "\n")
        #expect(!text.contains("kyle@example.com"))
        #expect(!text.contains("Signed in"))
    }

    @Test func setupOutcomesReadAsPrefixedCaseNames() {
        #expect(FeedbackAccountStatus(freshness: .stale(.providerSetup(.copilotLogsUnreadable)))
            == .stale("setup.copilotLogsUnreadable"))
        #expect(FeedbackAccountStatus(freshness: .pending) == .waiting)
        #expect(FeedbackAccountStatus(freshness: .live) == .live)
    }

    // MARK: CLI versions

    @Test(arguments: [
        ("2.1.317 (Claude Code)", "2.1.317"),
        ("codex-cli 0.155.1", "0.155.1"),
        ("grok 1.0.70 (f50904eaee6c) [stable]", "1.0.70"),
        ("2026.10.18-ea085cb", "2026.10.18-ea085cb"),
        ("GitHub Copilot CLI 1.0.105.\nRun 'copilot update' to check.", "1.0.105"),
        ("v3.2.1", "3.2.1"),
    ])
    func versionShapesKeepOnlyTheVersion(output: String, expected: String) {
        #expect(FeedbackCLIVersion(versionOutput: output) == .version(expected))
    }

    @Test(arguments: [
        "/Users/kyle/.local/bin/claude 2.1.300",
        "C:\\Users\\kyle\\claude 2.1.300",
        "command not found",
        "",
    ])
    func outputWithAPathOrNoVersionIsUnknown(output: String) {
        #expect(FeedbackCLIVersion(versionOutput: output) == .unknown)
    }

    @Test func noOutputIsUnknown() {
        #expect(FeedbackCLIVersion(versionOutput: nil) == .unknown)
    }

    // MARK: The email

    @Test func subjectCarriesTheSourceTag() {
        #expect(FeedbackEmail(source: .mac, diagnostics: nil).subject == "[Headroom Mac] Feedback")
        #expect(FeedbackEmail(source: .iPhone, diagnostics: nil).subject == "[Headroom iPhone] Feedback")
    }

    @Test func mailtoAddressesSupportAndRoundTripsSubjectAndBody() {
        let email = FeedbackEmail(source: .mac, diagnostics: macDiagnostics())
        #expect(email.mailtoURL.scheme == "mailto")
        #expect(email.mailtoURL.absoluteString.hasPrefix("mailto:support@zantos.co?"))
        let query = decodedQuery(email.mailtoURL)
        #expect(query["subject"] == email.subject)
        #expect(query["body"] == email.body)
    }

    @Test func plusSignsArePercentEncoded() {
        let diagnostics = FeedbackDiagnostics(
            appVersion: "1.5.3+beta", operatingSystem: "macOS 26.1"
        )
        let url = FeedbackEmail(source: .mac, diagnostics: diagnostics).mailtoURL.absoluteString
        #expect(!url.contains("+"))
        #expect(url.contains("%2B"))
    }

    @Test func bodyHasPromptsThenTheDiagnosticsBlock() {
        let email = FeedbackEmail(source: .mac, diagnostics: macDiagnostics())
        #expect(email.body.hasPrefix("What happened?"))
        #expect(email.body.contains("What did you expect instead?"))
        let block = email.body.components(separatedBy: FeedbackEmail.diagnosticsHeading + "\n").last ?? ""
        #expect(block == macDiagnostics().lines.joined(separator: "\n") + "\n")
    }

    @Test func diagnosticsOffLeavesOnlyThePrompts() {
        let email = FeedbackEmail(source: .mac, diagnostics: nil)
        #expect(!email.body.contains(FeedbackEmail.diagnosticsHeading))
        #expect(!email.body.contains("Headroom "))
    }

    @Test func longDiagnosticsTrimTheURLButNotTheCopyText() {
        let accounts = (1...20).flatMap { position in
            [ProviderID.claude, .codex, .grok].map {
                FeedbackDiagnostics.Account(providerID: $0, position: position, status: .stale("setup.claudeTransientCapture"))
            }
        }
        let email = FeedbackEmail(source: .mac, diagnostics: macDiagnostics(accounts: accounts))
        #expect(email.mailtoURL.absoluteString.count <= FeedbackEmail.maximumURLLength)
        let sentBody = decodedQuery(email.mailtoURL)["body"] ?? ""
        #expect(sentBody.contains(FeedbackEmail.trimmedNote))
        #expect(sentBody.contains("Headroom 1.5.3 (53) · macOS 26.1 · arm64"))
        // Lines are dropped whole, from the end.
        #expect(!sentBody.contains("Grok #20"))
        #expect(email.body.contains("Grok #20: stale (setup.claudeTransientCapture)"))
        #expect(!email.body.contains(FeedbackEmail.trimmedNote))
        #expect(email.clipboardText.contains("Grok #20"))
    }

    @Test func shortDiagnosticsAreNotTrimmed() {
        let email = FeedbackEmail(source: .mac, diagnostics: macDiagnostics())
        #expect(decodedQuery(email.mailtoURL)["body"] == email.body)
        #expect(!email.body.contains(FeedbackEmail.trimmedNote))
    }

    @Test func clipboardTextNamesTheAddressAndSubject() {
        let email = FeedbackEmail(source: .iPhone, diagnostics: nil)
        #expect(email.clipboardText.hasPrefix("To: support@zantos.co\nSubject: [Headroom iPhone] Feedback\n\n"))
        #expect(email.clipboardText.hasSuffix(email.body))
    }

    @Test func addressIsPinned() {
        #expect(FeedbackEmail.address == "support@zantos.co")
    }
}
