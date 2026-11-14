import Foundation
import Testing
@testable import HeadroomCore

@Suite
struct CompanionAttentionCopyTests {
    private static let accounts: [(CompanionAttention, String)] = [
        (.signInRequired, "Sign in on your Mac"),
        (.signInAgain, "Sign in again on your Mac"),
        (.finishingSignIn, "Finishing sign-in on your Mac"),
        (.setupInProgress, "Finish setup on your Mac"),
        // CA-P9: the CLI asks about a folder.
        (.workspaceApproval, "Approve Headroom’s folder on your Mac"),
        (.cliMissing, "Install the official CLI on your Mac"),
        (.cliUpdateRequired, "Update the official CLI on your Mac"),
        (.allowSignInFile, "Allow Headroom to read sign-in data on your Mac"),
        (.signInFileUnreadable, "Sign-in data is unreadable on your Mac"),
        (.signInStorageMismatch, "Review where sign-in data is stored on your Mac"),
        (.externalToolsApproval, "Review the CLI’s external tools on your Mac"),
        (.retrying, "Couldn’t read usage. Your Mac will try again."),
        (.cliDiscoveryRetrying, "Your Mac couldn’t find the official CLI. It will try again."),
        (.setupScreenUnknown, "Review the official CLI’s setup screen on your Mac"),
        (.neverOnboarded, "Sign in to this account on your Mac"),
        (.accessDenied, "Review this account’s access on your Mac"),
        (.setupFailed, "Setup needs attention on your Mac"),
        (.setupBlocked, "Another account is being set up on your Mac"),
        (.unknown, "Needs attention on your Mac")
    ]
    private static let spending: [(CompanionSpendAttention, String)] = [
        (.missingKey, "Set up API spend on your Mac"),
        (.keyRejected, "Replace the rejected key on your Mac"),
        (.keyLacksAccess, "Review the API key’s access on your Mac"),
        (.setupRequired, "Set up API spend on your Mac"),
        (.retryable, "Couldn’t read the amount. Your Mac will try again."),
        (.unknown, "Needs attention on your Mac")
    ]

    @Test(arguments: accounts)
    func everyAccountAttentionHasExactCanonicalCopyAndStringCodable(attention: CompanionAttention, expected: String) throws {
        #expect(CompanionAttentionCopy.account(attention) == expected)
        let data = try JSONEncoder().encode(attention)
        #expect(try JSONDecoder().decode(String.self, from: data) == attention.rawValue)
        #expect(try JSONDecoder().decode(CompanionAttention.self, from: data) == attention)
    }

    @Test(arguments: spending)
    func everySpendAttentionHasExactCanonicalCopyAndStringCodable(attention: CompanionSpendAttention, expected: String) throws {
        #expect(CompanionAttentionCopy.spend(attention) == expected)
        let data = try JSONEncoder().encode(attention)
        #expect(try JSONDecoder().decode(String.self, from: data) == attention.rawValue)
        #expect(try JSONDecoder().decode(CompanionSpendAttention.self, from: data) == attention)
    }

    @Test func approvedTablesCoverAllValuesAndSourceSpendCategories() {
        #expect(Set(Self.accounts.map { $0.0.rawValue }) == Set(CompanionAttention.allCases.map(\.rawValue)))
        #expect(Self.accounts.count == CompanionAttention.allCases.count)
        #expect(Set(Self.spending.map { $0.0.rawValue }) == Set(CompanionSpendAttention.allCases.map(\.rawValue)))
        for source in APISpendAttention.allCases {
            let wire = CompanionSpendAttention(source)
            #expect(wire.rawValue == source.rawValue)
            #expect(wire.apiSpendAttention == source)
            #expect(CompanionAttentionCopy.spend(apiSpendAttention: source) == CompanionAttentionCopy.spend(wire))
        }
        #expect(CompanionSpendAttention.unknown.apiSpendAttention == nil)
    }

    @Test func unknownStringsFallbackWithoutRetainingSourceTextAndNilStaleIsGeneric() throws {
        let data = Data("\"UNTRUSTED_UNKNOWN_SOURCE_SENTINEL\"".utf8)
        let account = try JSONDecoder().decode(CompanionAttention.self, from: data)
        let spend = try JSONDecoder().decode(CompanionSpendAttention.self, from: data)
        #expect(account == .unknown)
        #expect(spend == .unknown)
        #expect(CompanionAttentionCopy.account(account) == "Needs attention on your Mac")
        #expect(CompanionAttentionCopy.spend(spend) == "Needs attention on your Mac")
        #expect(CompanionAttentionCopy.account(nil) == "Needs attention on your Mac")
        #expect(CompanionAttentionCopy.spend(nil) == "Needs attention on your Mac")
        #expect(CompanionAttentionCopy.spend(apiSpendAttention: nil) == "Needs attention on your Mac")
        #expect(!String(decoding: try JSONEncoder().encode(account), as: UTF8.self).contains("SENTINEL"))
        #expect(!String(decoding: try JSONEncoder().encode(spend), as: UTF8.self).contains("SENTINEL"))
    }

    /// U8/V12: the phone card names the account in the sign-in family only; every other
    /// category keeps its canonical sentence, and no title keeps the untitled form.
    @Test func titledCopyNamesTheAccountOnlyForSignIn() {
        #expect(CompanionAttentionCopy.account(.neverOnboarded, title: "Account 2") == "Sign in to Account 2 on your Mac")
        #expect(CompanionAttentionCopy.account(.signInRequired, title: "Work · 2") == "Sign in to Work · 2 on your Mac")
        #expect(CompanionAttentionCopy.account(.signInAgain, title: "Work") == "Sign in to Work again on your Mac")
        #expect(CompanionAttentionCopy.account(.signInRequired, title: nil) == "Sign in on your Mac")
        #expect(CompanionAttentionCopy.account(.signInRequired, title: "") == "Sign in on your Mac")
        for (attention, expected) in Self.accounts
        where ![.signInRequired, .signInAgain, .neverOnboarded].contains(attention) {
            #expect(CompanionAttentionCopy.account(attention, title: "Work") == expected)
        }
        #expect(CompanionAttentionCopy.account(nil, title: "Work") == "Needs attention on your Mac")
    }

    @Test(arguments: ["123", "1.5", "false", "null", "[]", "{}"])
    func wrongPrimitivesAreNotUnknownStringFallbacks(json: String) {
        let data = Data(json.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CompanionAttention.self, from: data) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CompanionSpendAttention.self, from: data) }
    }

    @Test func typographyAndSignInVerbsRemainCanonicalAndSpendRetryIsDistinct() {
        for text in Self.accounts.map(\.1) + Self.spending.map(\.1) {
            #expect(!text.contains("'"))
            #expect(!text.localizedCaseInsensitiveContains("connect"))
            #expect(!text.localizedCaseInsensitiveContains("sign up"))
            #expect(!text.localizedCaseInsensitiveContains("signup"))
            #expect(!text.contains("\\u00a0"))
            let characters = Array(text)
            for index in characters.indices where characters[index] == "—" {
                #expect(index > 0 && characters[index - 1] == "\u{00A0}")
                #expect(index + 1 < characters.count && characters[index + 1] == "\u{00A0}")
            }
        }
        #expect(CompanionAttentionCopy.spend(.retryable) != CompanionAttentionCopy.account(.retrying))
    }
}
