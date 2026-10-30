import Foundation
import Testing

@testable import HeadroomCore

/// Contract Decision 5: every ProviderSetupOutcome, FailureReason, ProviderCapabilityState,
/// discovery issue, SetupSessionState and SetupSessionFailure case maps through one table.
@Suite
struct CompanionAttentionMappingTests {
    /// Every current outcome and its reviewed base attention, written out literally.
    static let outcomes: [(ProviderSetupOutcome, CompanionAttention)] = [
        (.claudeCLIMissing, .cliMissing),
        (.claudeLoginRequired, .signInRequired),
        (.claudeTrustRequired, .workspaceApproval),
        (.claudeUnknownUI, .setupScreenUnknown),
        // No wire value names a startup question; the schema is unchanged.
        (.claudeStartupQuestion, .setupScreenUnknown),
        (.claudeTransientCapture, .retrying),
        (.codexCLIMissing, .cliMissing),
        (.codexAuthAbsent, .signInRequired),
        (.codexPermissionDenied, .allowSignInFile),
        (.codexUnsafePermissions, .signInAgain),
        (.codexMalformedAuth, .signInFileUnreadable),
        (.codexCredentialIO, .retrying),
        (.codexRejectedAuth, .signInAgain),
        (.codexSessionUnverified, .retrying),
        (.codexStorageMismatch, .signInStorageMismatch),
        (.codexCallbackIncomplete, .setupFailed),
        (.grokCLIMissing, .cliMissing),
        (.grokAuthAbsent, .signInRequired),
        (.grokPermissionDenied, .allowSignInFile),
        (.grokUnsafePermissions, .signInAgain),
        (.grokMalformedAuth, .signInFileUnreadable),
        (.grokCredentialIO, .retrying),
        (.grokRejectedAuth, .signInAgain),
        (.grokTransientCapture, .retrying),
        (.cursorCLIMissing, .cliMissing),
        (.cursorAuthAbsent, .signInRequired),
        (.cursorTrustRequired, .workspaceApproval),
        (.cursorMCPApprovalRequired, .externalToolsApproval),
        (.cursorUnknownUI, .setupScreenUnknown),
        (.cursorTransientCapture, .retrying),
    ]

    @Test func everyProviderSetupOutcomeMapsToItsReviewedAttention() {
        #expect(Self.outcomes.count == 30)
        #expect(Set(Self.outcomes.map(\.0)).count == 30)
        for (outcome, expected) in Self.outcomes {
            #expect(CompanionAttentionMapping.attention(for: outcome) == expected, "\(outcome)")
            #expect(CompanionAttentionMapping.attention(for: .providerSetup(outcome)) == expected)
            #expect(CompanionAttentionMapping.attention(for: SetupSessionFailure.provider(outcome)) == expected)
        }
    }

    @Test func everyFailureReasonIgnoresItsAssociatedText() {
        let secret = "/Users/someone/.codex/auth.json token=abc"
        let cases: [(FailureReason, CompanionAttention)] = [
            (.transient(secret), .retrying),
            (.needsReauth(secret), .signInAgain),
            (.scopeDenied(secret), .accessDenied),
            (.decode(secret), .retrying),
            (.notLoggedIn(secret), .signInRequired),
            (.providerSetup(.codexRejectedAuth), .signInAgain),
        ]
        for (reason, expected) in cases {
            #expect(CompanionAttentionMapping.attention(for: reason) == expected)
            #expect(CompanionAttentionMapping.attention(for: .transient("other text")) == .retrying)
        }
    }

    static let issues: [CLIExecutableDiscoveryIssue] = [
        .shellTimeout, .shellSpawnFailure, .invalidShellOutput, .inaccessibleCandidate,
        .invalidatedHint, .launchRace, .npmPrefixUnresolved,
    ]

    @Test func everyCapabilityStateAndDiscoveryIssueMapsAtProviderScope() {
        #expect(Self.issues.count == 7)
        for issue in Self.issues {
            #expect(CompanionAttentionMapping.attention(for: issue) == .cliDiscoveryRetrying)
            #expect(CompanionAttentionMapping.capabilityAttention(for: .inconclusive(issue)) == .cliDiscoveryRetrying)
        }
        #expect(CompanionAttentionMapping.capabilityAttention(for: .unknown) == nil)
        #expect(CompanionAttentionMapping.capabilityAttention(for: .discovering) == nil)
        #expect(CompanionAttentionMapping.capabilityAttention(for: .available) == nil)
        #expect(CompanionAttentionMapping.capabilityAttention(for: .confirmedAbsent) == .cliMissing)
    }

    @Test func everySetupSessionFailureMapsWithCapabilityKeptAtProviderScope() {
        let cases: [(SetupSessionFailure, CompanionAttention?)] = [
            (.executableMissing, .cliMissing),
            (.updateRequired, .cliUpdateRequired),
            (.stagingFailed, .setupFailed),
            (.terminalRejected, .setupFailed),
            (.pasteboardFailed, .setupFailed),
            (.retryExhausted, .setupFailed),
            (.waitingTimedOut, .setupFailed),
            (.closedBeforeSignIn, .signInRequired),
            (.provider(.cursorMCPApprovalRequired), .externalToolsApproval),
            (.providerCapability(.confirmedAbsent), nil),
        ]
        #expect(cases.count == 10)
        for (failure, expected) in cases {
            #expect(CompanionAttentionMapping.attention(for: failure) == expected, "\(failure)")
        }
        #expect(CompanionAttentionMapping.providerAttention(for: .providerCapability(.confirmedAbsent)) == .cliMissing)
        #expect(CompanionAttentionMapping.providerAttention(for: .providerCapability(.inconclusive(.launchRace))) == .cliDiscoveryRetrying)
        for state in [ProviderCapabilityState.unknown, .discovering, .available] {
            #expect(CompanionAttentionMapping.providerAttention(for: .providerCapability(state)) == nil)
        }
        #expect(CompanionAttentionMapping.providerAttention(for: .updateRequired) == nil)
    }

    @Test func everySessionStateHasAnExplicitOverlay() {
        let key = AccountKey(providerID: .claude, accountID: .primary)
        let cases: [(CompanionSessionInput, CompanionAttention?)] = [
            (.init(state: .idle), nil),
            (.init(state: .preparing, purpose: .setup), .setupInProgress),
            (.init(state: .preparing, purpose: .trust), .setupInProgress),
            (.init(state: .preparing, purpose: .setup, interactiveReason: .neverOnboardedExtraAccount), .neverOnboarded),
            (.init(state: .waiting(attempt: 1), purpose: .setup), .finishingSignIn),
            (.init(state: .waiting(attempt: 3), purpose: .reset), .finishingSignIn),
            (.init(state: .verifying, purpose: .setup, interactiveReason: .versionUnreadable), .finishingSignIn),
            (.init(state: .waiting(attempt: 1), purpose: .setup, interactiveReason: .neverOnboardedExtraAccount), .finishingSignIn),
            (.init(state: .waiting(attempt: 1), purpose: .trust), .workspaceApproval),
            (.init(state: .verifying, purpose: .trust), .workspaceApproval),
            // The startup question rides the `.trust` launch but is not an approval.
            (.init(state: .waiting(attempt: 1), purpose: .trust, interactiveReason: .startupQuestion), .setupScreenUnknown),
            (.init(state: .verifying, purpose: .trust, interactiveReason: .startupQuestion), .setupScreenUnknown),
            (.init(state: .preparing, purpose: .trust, interactiveReason: .startupQuestion), .setupInProgress),
            // The reason only reaches the overlay on the `.trust` launch.
            (.init(state: .waiting(attempt: 1), purpose: .setup, interactiveReason: .startupQuestion), .finishingSignIn),
            (.init(state: .waiting(attempt: 1), purpose: .approval), .externalToolsApproval),
            (.init(state: .verifying, purpose: .approval), .externalToolsApproval),
            (.init(state: .blockedByOpenHandoff), .setupBlocked),
            (.init(state: .blockedByProviderLogin(providerID: .claude, active: key)), .setupBlocked),
            (.init(state: .connected), nil),
            (.init(state: .failed(.updateRequired)), .cliUpdateRequired),
            (.init(state: .failed(.providerCapability(.confirmedAbsent))), nil),
            (.init(state: .cancelled), nil),
            (.init(state: .removing), nil),
            (.init(state: .removalFailed), nil),
            (.init(state: .removed), nil),
        ]
        for (input, expected) in cases {
            #expect(CompanionAttentionMapping.sessionOverlay(input) == expected, "\(input)")
        }
    }

    @Test func overlayWinsOverOldSnapshotTextAndPermanenceStaysFromTheSource() {
        let stale = Freshness.stale(.providerSetup(.codexRejectedAuth))
        let finishing = CompanionSessionInput(state: .waiting(attempt: 2), purpose: .setup)
        #expect(CompanionAttentionMapping.accountAttention(freshness: stale, isBuiltIn: true, session: finishing) == .finishingSignIn)
        #expect(CompanionAttentionMapping.accountAttention(freshness: stale, isBuiltIn: true, session: nil) == .signInAgain)
        #expect(CompanionAttentionMapping.accountAttention(freshness: stale, isBuiltIn: true, session: .init(state: .idle)) == .signInAgain)
        #expect(CompanionAttentionMapping.needsAttention(stale) == true)
        #expect(CompanionAttentionMapping.needsAttention(.stale(.transient("x"))) == false)
        #expect(CompanionAttentionMapping.needsAttention(.live) == nil)
        #expect(CompanionAttentionMapping.accountAttention(freshness: .live, isBuiltIn: true, session: nil) == nil)
        #expect(CompanionAttentionMapping.accountAttention(freshness: .pending, isBuiltIn: false, session: nil) == nil)
    }

    /// Never-onboarded uses `isNeverSignedIn` plus the built-in flag, so Make Main (which
    /// changes neither) cannot change it.
    @Test func neverOnboardedClassificationIgnoresWhichAccountIsMain() {
        for outcome in [ProviderSetupOutcome.claudeLoginRequired, .codexAuthAbsent, .grokAuthAbsent, .cursorAuthAbsent] {
            let stale = Freshness.stale(.providerSetup(outcome))
            #expect(CompanionAttentionMapping.baseAttention(freshness: stale, isBuiltIn: false) == .neverOnboarded)
            #expect(CompanionAttentionMapping.baseAttention(freshness: stale, isBuiltIn: true) == .signInRequired)
        }
        #expect(CompanionAttentionMapping.baseAttention(freshness: .stale(.notLoggedIn("x")), isBuiltIn: false) == .signInRequired)
        #expect(CompanionAttentionMapping.baseAttention(freshness: .stale(.providerSetup(.codexRejectedAuth)), isBuiltIn: false) == .signInAgain)
    }

    @Test func providerLineKeepsConfirmedAbsenceVisibleWhileSessionsWait() {
        let waiting = CompanionSessionInput(state: .waiting(attempt: 1), purpose: .setup)
        let capabilityFailed = CompanionSessionInput(state: .failed(.providerCapability(.confirmedAbsent)))
        #expect(CompanionAttentionMapping.providerAttention(capability: .confirmedAbsent, sessions: [waiting]) == .cliMissing)
        #expect(CompanionAttentionMapping.providerAttention(capability: .inconclusive(.shellTimeout), sessions: []) == .cliDiscoveryRetrying)
        #expect(CompanionAttentionMapping.providerAttention(capability: .available, sessions: [capabilityFailed]) == nil)
        #expect(CompanionAttentionMapping.providerAttention(capability: nil, sessions: [waiting, capabilityFailed]) == .cliMissing)
        #expect(CompanionAttentionMapping.providerAttention(capability: .unknown, sessions: [waiting]) == nil)
    }

    @MainActor
    @Test func injectedSessionClosureDrivesTheComposedMapper() {
        let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
        let mapper = CompanionAttentionMapper { key in
            key == work ? CompanionSessionInput(state: .verifying, purpose: .trust) : nil
        }
        let stale = Freshness.stale(.providerSetup(.claudeLoginRequired))
        #expect(mapper.accountAttention(for: work, freshness: stale, isBuiltIn: false) == .workspaceApproval)
        let other = AccountKey(providerID: .claude, accountID: .primary)
        #expect(mapper.accountAttention(for: other, freshness: stale, isBuiltIn: true) == .signInRequired)
        #expect(mapper.providerAttention(accounts: [work, other], capability: .confirmedAbsent) == .cliMissing)
    }

    /// Every attention the table can produce has canonical R2C6 copy, and no source text
    /// reaches the encoded payload.
    @Test func mappedCopyPassesR2C6AndEncodesNoSourceStrings() throws {
        let produced = Set(Self.outcomes.map(\.1))
            .union([.accessDenied, .cliDiscoveryRetrying, .cliUpdateRequired, .neverOnboarded,
                    .finishingSignIn, .setupInProgress, .setupBlocked])
        for attention in produced {
            let copy = CompanionAttentionCopy.account(attention)
            #expect(copy != CompanionAttentionCopy.generic)
            #expect(!copy.localizedCaseInsensitiveContains("connect"))
            #expect(!copy.contains("'"))
            if copy.contains("—") { #expect(copy.contains("\u{00A0}—\u{00A0}")) }
        }
        let secret = "secret-path-/Users/kyle/.claude"
        let account = try CompanionAccountSummary(
            id: "primary", title: "Main", freshness: .stale,
            attention: CompanionAttentionMapping.attention(for: .needsReauth(secret)),
            needsAttention: CompanionAttentionMapping.needsAttention(.stale(.needsReauth(secret))),
            windows: [])
        let encoded = String(decoding: try CompanionSyncCodec.encode(account), as: UTF8.self)
        #expect(!encoded.contains("secret") && encoded.contains(#""a":"signInAgain""#))
    }
}
