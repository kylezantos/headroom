import Testing
@testable import HeadroomCore

struct ActiveLoginCollapseTests {
    private let builtIn = ProviderAccount.builtIn(for: .claude)
    private let gmail = ProviderAccount(id: AccountID("gmail"), providerID: .claude, label: "Gmail")
    private let work = ProviderAccount(id: AccountID("work"), providerID: .claude, label: "Work")

    @Test func switcherMovesTheBuiltInOntoAnExtraRow() {
        // ccswap flipped the default login to gmail: the built-in row now reads gmail.
        let result = ActiveLoginCollapse.resolve(
            accounts: [builtIn, gmail, work],
            emailsByKey: [
                builtIn.key: "person@gmail.com",
                gmail.key: "person@gmail.com",
                work.key: "person@work.example",
            ]
        )
        #expect(result.accounts == [gmail, work])
        #expect(result.activeKey == gmail.key)
        #expect(result.hiddenKey == builtIn.key)
    }

    @Test func markerFollowsTheNextSwitch() {
        let result = ActiveLoginCollapse.resolve(
            accounts: [builtIn, gmail, work],
            emailsByKey: [
                builtIn.key: " Person@Work.Example ",
                gmail.key: "person@gmail.com",
                work.key: "person@work.example",
            ]
        )
        #expect(result.accounts == [gmail, work])
        #expect(result.activeKey == work.key)
    }

    @Test func aLoginNoExtraRowTracksKeepsTheBuiltInRow() {
        let result = ActiveLoginCollapse.resolve(
            accounts: [builtIn, gmail],
            emailsByKey: [builtIn.key: "person@work.example", gmail.key: "person@gmail.com"]
        )
        #expect(result.accounts == [builtIn, gmail])
        #expect(result.activeKey == nil)
        #expect(result.hiddenKey == nil)
    }

    @Test func missingEmailsNeverCollapse() {
        for emails: [AccountKey: String] in [
            [:],
            [gmail.key: "person@gmail.com"],
            [builtIn.key: "person@gmail.com"],
            [builtIn.key: "   ", gmail.key: "   "],
        ] {
            let result = ActiveLoginCollapse.resolve(accounts: [builtIn, gmail], emailsByKey: emails)
            #expect(result.accounts == [builtIn, gmail])
            #expect(result.activeKey == nil)
        }
    }

    @Test func twoExtraRowsOnTheSameEmailAreAmbiguous() {
        let result = ActiveLoginCollapse.resolve(
            accounts: [builtIn, gmail, work],
            emailsByKey: [
                builtIn.key: "person@gmail.com",
                gmail.key: "person@gmail.com",
                work.key: "person@gmail.com",
            ]
        )
        #expect(result.accounts == [builtIn, gmail, work])
        #expect(result.activeKey == nil)
    }

    @Test func differentPlansOnOneEmailAreDifferentSubscriptions() {
        let result = ActiveLoginCollapse.resolve(
            accounts: [builtIn, gmail, work],
            emailsByKey: [builtIn.key: "person@gmail.com", gmail.key: "person@gmail.com"],
            planLabelsByKey: [builtIn.key: "Team", gmail.key: "Max"]
        )
        #expect(result.accounts == [builtIn, gmail, work])
        #expect(result.activeKey == nil)
    }

    @Test func matchingOrMissingPlansStillCollapse() {
        for plans: [AccountKey: String] in [
            [builtIn.key: "Max", gmail.key: "max"],
            [builtIn.key: "Max"],
            [:],
        ] {
            let result = ActiveLoginCollapse.resolve(
                accounts: [builtIn, gmail, work],
                emailsByKey: [builtIn.key: "person@gmail.com", gmail.key: "person@gmail.com"],
                planLabelsByKey: plans
            )
            #expect(result.accounts == [gmail, work])
            #expect(result.activeKey == gmail.key)
        }
    }

    @Test func neverFoldsDownToASingleAccountCard() {
        let result = ActiveLoginCollapse.resolve(
            accounts: [builtIn, gmail],
            emailsByKey: [builtIn.key: "person@gmail.com", gmail.key: "person@gmail.com"]
        )
        #expect(result.accounts == [builtIn, gmail])
        #expect(result.activeKey == nil)
    }

    @Test func extraRowsAloneAreNeverCollapsed() {
        // Built-in stop-tracked: two extras on one login stay as they are (Settings badges them).
        let result = ActiveLoginCollapse.resolve(
            accounts: [gmail, work],
            emailsByKey: [gmail.key: "person@gmail.com", work.key: "person@gmail.com"]
        )
        #expect(result.accounts == [gmail, work])
        #expect(result.activeKey == nil)
    }

    @Test func otherProvidersWithTheSameEmailAreNotMatched() {
        let codex = ProviderAccount(id: AccountID("codex-2"), providerID: .codex, label: "Codex 2")
        let result = ActiveLoginCollapse.resolve(
            accounts: [builtIn, work, codex],
            emailsByKey: [builtIn.key: "person@gmail.com", codex.key: "person@gmail.com"]
        )
        #expect(result.accounts == [builtIn, work, codex])
        #expect(result.activeKey == nil)
    }
}
