import Foundation
import Testing
@testable import HeadroomCore

struct CCSwapAccountsTests {
    @Test func accountIDsRoundTripTheNormalizedEmail() {
        let id = CCSwapAccounts.accountID(email: " Person@Work.Example ")
        #expect(id?.raw == "ccswap-person@work.example")
        #expect(id.flatMap(CCSwapAccounts.email(for:)) == "person@work.example")
        #expect(CCSwapAccounts.accountID(email: "  ") == nil)
        #expect(CCSwapAccounts.email(for: .primary) == nil)
        #expect(CCSwapAccounts.email(for: AccountID("0b0e6c9e-5d1f-4c8a-9d63-1f7c2c0a9e11")) == nil)
    }

    @Test func launchPrefixRunsTheOfficialCLIAsThatAccount() {
        #expect(CCSwapAccounts.launchPrefix(email: "person@work.example") == ["run", "person@work.example", "--"])
    }

    @Test func listingYieldsEmailsInSlotOrderAndIgnoresUsage() throws {
        // The shape of `ccswap list --json --provider claude` (schema 1), usage included.
        let json = """
        {"schemaVersion": 1, "activeAccountNumber": 1, "accounts": [
          {"number": 2, "email": "Person@Work.Example", "active": false,
           "usage": {"sevenDay": {"pct": 90.0}}},
          {"number": 1, "email": "person@gmail.example", "active": true,
           "usage": {"sevenDay": {"pct": 69.0}}},
          {"number": 3, "email": "setup-token-3@token.local"},
          {"number": 4, "email": "person@gmail.example"},
          {"number": 5}
        ]}
        """
        #expect(CCSwapAccounts.emails(inListJSON: Data(json.utf8))
            == ["person@gmail.example", "person@work.example"])
    }

    @Test func unknownSchemasAndGarbageYieldNothing() {
        #expect(CCSwapAccounts.emails(inListJSON: Data(#"{"schemaVersion": 2, "accounts": [{"email": "a@b.c"}]}"#.utf8)).isEmpty)
        #expect(CCSwapAccounts.emails(inListJSON: Data("not json".utf8)).isEmpty)
        #expect(CCSwapAccounts.emails(inListJSON: Data()).isEmpty)
    }

    @Test func fixedEmailReaderReportsTheSlotEmail() {
        #expect(FixedClaudeAccountEmail("person@work.example").readAccountEmail() == "person@work.example")
    }
}
