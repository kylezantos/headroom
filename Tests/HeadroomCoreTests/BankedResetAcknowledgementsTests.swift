import Foundation
import Testing
@testable import HeadroomCore

struct BankedResetAcknowledgementsTests {
    private let builtIn = AccountKey(providerID: .codex, accountID: .primary)
    private let extra = AccountKey(providerID: .codex, accountID: AccountID("extra"))

    private func freshRecord() -> BankedResetAcknowledgements {
        let suite = "headroom.banked-resets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return BankedResetAcknowledgements(defaults: defaults)
    }

    @Test func claimRaisesFromNothingAndThenStaysQuiet() {
        let record = freshRecord()
        #expect(record.claimReveal(for: builtIn, currentCount: 2))
        #expect(record.acknowledgedCount(for: builtIn) == 2)
        #expect(!record.claimReveal(for: builtIn, currentCount: 2))
        #expect(record.acknowledgedCount(for: builtIn) == 2)
    }

    @Test func claimLowersWithoutRevealing() {
        let record = freshRecord()
        #expect(record.claimReveal(for: builtIn, currentCount: 2))
        #expect(!record.claimReveal(for: builtIn, currentCount: 1))
        #expect(record.acknowledgedCount(for: builtIn) == 1)
        #expect(!record.claimReveal(for: builtIn, currentCount: 0))
        #expect(record.acknowledgedCount(for: builtIn) == 0)
    }

    @Test func nilCountDoesNotTouchTheRecord() {
        let record = freshRecord()
        #expect(record.claimReveal(for: builtIn, currentCount: 2))
        #expect(!record.claimReveal(for: builtIn, currentCount: nil))
        #expect(record.acknowledgedCount(for: builtIn) == 2)
        #expect(!record.claimReveal(for: extra, currentCount: nil))
        #expect(record.acknowledgedCount(for: extra) == nil)
    }

    @Test func flickerThroughNilDoesNotReannounce() {
        let record = freshRecord()
        #expect(record.claimReveal(for: builtIn, currentCount: 2))
        #expect(!record.claimReveal(for: builtIn, currentCount: 2))
        #expect(!record.claimReveal(for: builtIn, currentCount: nil))
        #expect(!record.claimReveal(for: builtIn, currentCount: 2))
        #expect(record.acknowledgedCount(for: builtIn) == 2)
    }

    @Test func lowerOnlyShrinksAStoredCount() {
        let record = freshRecord()
        record.lower(for: builtIn, currentCount: 0)
        #expect(record.acknowledgedCount(for: builtIn) == nil)

        #expect(record.claimReveal(for: builtIn, currentCount: 2))
        record.lower(for: builtIn, currentCount: 3)
        #expect(record.acknowledgedCount(for: builtIn) == 2)
        record.lower(for: builtIn, currentCount: 0)
        #expect(record.acknowledgedCount(for: builtIn) == 0)
        record.lower(for: builtIn, currentCount: nil)
        #expect(record.acknowledgedCount(for: builtIn) == 0)
    }

    @Test func accountsStayIndependent() {
        let record = freshRecord()
        #expect(record.claimReveal(for: builtIn, currentCount: 1))
        #expect(record.claimReveal(for: extra, currentCount: 4))
        #expect(record.acknowledgedCount(for: builtIn) == 1)
        #expect(record.acknowledgedCount(for: extra) == 4)
    }

    @Test func handWrittenEnvelopeDecodes() throws {
        let suite = "headroom.banked-resets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let json = """
        {"entries":[
          {"account":{"providerID":{"raw":"codex"},"accountID":{"raw":"primary"}},"count":2},
          {"account":{"providerID":{"raw":"codex"},"accountID":{"raw":"extra"}},"count":1}
        ]}
        """
        defaults.set(Data(json.utf8), forKey: "bankedResetAcknowledgements.v1")
        let record = BankedResetAcknowledgements(defaults: defaults)
        #expect(record.acknowledgedCount(for: builtIn) == 2)
        #expect(record.acknowledgedCount(for: extra) == 1)
    }

    @Test func corruptPayloadReadsEmptyAndTheNextWriteReplacesIt() {
        let suite = "headroom.banked-resets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(Data("not-json".utf8), forKey: "bankedResetAcknowledgements.v1")
        let record = BankedResetAcknowledgements(defaults: defaults)
        #expect(record.acknowledgedCount(for: builtIn) == nil)
        #expect(record.claimReveal(for: builtIn, currentCount: 1))
        let reloaded = BankedResetAcknowledgements(defaults: defaults)
        #expect(reloaded.acknowledgedCount(for: builtIn) == 1)
    }

    @Test func capKeepsTheTestedEnvelopeAndDropsTheOldest() {
        let record = freshRecord()
        let kept = AccountRegistry.testedEnvelope * 3 + 1
        for index in 0..<kept {
            #expect(record.claimReveal(for: AccountKey(providerID: .codex, accountID: AccountID("a\(index)")), currentCount: 1))
        }
        #expect(record.acknowledgedCount(for: AccountKey(providerID: .codex, accountID: AccountID("a0"))) == 1)
        #expect(record.claimReveal(for: AccountKey(providerID: .codex, accountID: AccountID("overflow")), currentCount: 1))
        #expect(record.acknowledgedCount(for: AccountKey(providerID: .codex, accountID: AccountID("a0"))) == nil)
        #expect(record.acknowledgedCount(for: AccountKey(providerID: .codex, accountID: AccountID("a1"))) == 1)
        #expect(record.acknowledgedCount(for: AccountKey(providerID: .codex, accountID: AccountID("overflow"))) == 1)
    }

    @Test func purgeRemovesOnlyThatAccount() {
        let record = freshRecord()
        #expect(record.claimReveal(for: builtIn, currentCount: 2))
        #expect(record.claimReveal(for: extra, currentCount: 1))
        record.purge(for: extra)
        #expect(record.acknowledgedCount(for: extra) == nil)
        #expect(record.acknowledgedCount(for: builtIn) == 2)
    }
}
