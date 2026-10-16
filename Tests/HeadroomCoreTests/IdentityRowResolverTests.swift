import Testing
@testable import HeadroomCore

struct IdentityRowResolverTests {
    @Test func emailNamesReplaceTitlesWithoutRepeatingTheEmail() {
        let identity = DesktopAccountIdentity(
            title: "Account 15", email: "person@example.com",
            showsPersistentEmail: true, usesEmailAsName: true
        )
        #expect(identity.title == "person@example.com")
        #expect(identity.email == nil)
        #expect(!identity.showsPersistentEmail)
        #expect(identity.isEmailTitle)
    }

    @Test func emailNamesFallBackAndRemainReversible() {
        for email: String? in [nil, "", "   "] {
            let identity = DesktopAccountIdentity(
                title: "Work", email: email,
                showsPersistentEmail: false, usesEmailAsName: true
            )
            #expect(identity.title == "Work")
            #expect(!identity.isEmailTitle)
        }
        let identity = DesktopAccountIdentity(
            title: "Work", email: "person@example.com",
            showsPersistentEmail: true, usesEmailAsName: false
        )
        #expect(identity.title == "Work")
        #expect(identity.email == "person@example.com")
        #expect(identity.showsPersistentEmail)
        #expect(!identity.isEmailTitle)
    }

    private func account(
        providerID: ProviderID = .claude,
        id: String,
        label: String,
        builtIn: Bool = false
    ) -> ProviderAccount {
        ProviderAccount(
            id: builtIn ? .primary : AccountID(id),
            providerID: providerID,
            label: label,
            isBuiltIn: builtIn
        )
    }

    @Test func surfaceUsesAccountRowsOnlyWhenAProviderHasMultipleVisibleAccounts() {
        let claude = account(id: "claude-main", label: "Main", builtIn: true)
        let codex = account(providerID: .codex, id: "codex-main", label: "Main", builtIn: true)
        let work = account(id: "work", label: "Work")

        #expect(!surfaceUsesAccountRows(accountsByProvider: [
            .claude: [claude],
            .codex: [codex],
        ]))
        #expect(surfaceUsesAccountRows(accountsByProvider: [
            .claude: [claude, work],
            .codex: [codex],
        ]))
    }

    @Test func loneDefaultLabelsUseProviderName() {
        let main = account(id: "main", label: "Main", builtIn: true)
        let survivingExtra = account(id: "second", label: "Account 2")

        #expect(rowTitle(for: main, in: [main], providerDisplayName: "Claude") == "Claude")
        #expect(rowTitle(for: survivingExtra, in: [survivingExtra], providerDisplayName: "Claude") == "Claude")
    }

    @Test func multiAccountProviderKeepsDefaultLabels() {
        let main = account(id: "main", label: "Main", builtIn: true)
        let second = account(id: "second", label: "Account 2")

        #expect(rowTitle(for: main, in: [main, second], providerDisplayName: "Claude") == "Main")
        #expect(rowTitle(for: second, in: [main, second], providerDisplayName: "Claude") == "Account 2")
    }

    @Test func renamedLoneAccountKeepsItsLabel() {
        let work = account(id: "work", label: "Work")
        let lowercaseMain = account(id: "renamed-main", label: "main")

        #expect(rowTitle(for: work, in: [work], providerDisplayName: "Claude") == "Work")
        #expect(rowTitle(for: lowercaseMain, in: [lowercaseMain], providerDisplayName: "Claude") == "main")
    }

    @Test func defaultLabelsAreEligibleWhenProviderHasMultipleAccounts() {
        let main = account(id: "main", label: "Main", builtIn: true)
        let second = account(id: "second", label: "Account 2")

        #expect(showsPersistentEmail(for: main, in: [main, second]))
        #expect(showsPersistentEmail(for: second, in: [main, second]))
    }

    @Test func distinctRenamedAccountsAreNotEligible() {
        let personal = account(id: "personal", label: "Personal", builtIn: true)
        let work = account(id: "work", label: "Work")

        #expect(!showsPersistentEmail(for: personal, in: [personal, work]))
        #expect(!showsPersistentEmail(for: work, in: [personal, work]))
    }

    @Test func caseInsensitiveDuplicateLabelsAreEligible() {
        let lowercase = account(id: "lowercase", label: "work", builtIn: true)
        let titlecase = account(id: "titlecase", label: "Work")

        #expect(showsPersistentEmail(for: lowercase, in: [lowercase, titlecase]))
        #expect(showsPersistentEmail(for: titlecase, in: [lowercase, titlecase]))
    }

    @Test func crossProviderDuplicateLabelsDoNotCount() {
        let claudeWork = account(id: "claude-work", label: "Work")
        let codexWork = account(providerID: .codex, id: "codex-work", label: "work")
        let claudeMain = account(id: "claude-main", label: "Main", builtIn: true)
        let codexMain = account(providerID: .codex, id: "codex-main", label: "Main", builtIn: true)

        #expect(!showsPersistentEmail(for: claudeWork, in: [claudeWork, codexWork]))
        #expect(!showsPersistentEmail(for: codexWork, in: [claudeWork, codexWork]))
        #expect(!showsPersistentEmail(for: claudeMain, in: [claudeMain, codexMain]))
        #expect(!showsPersistentEmail(for: codexMain, in: [claudeMain, codexMain]))
    }

    @Test func eligibilityDoesNotDependOnSnapshotEmailAvailability() {
        let first = account(id: "first", label: "Studio")
        let second = account(id: "second", label: "studio")
        let snapshotWithoutEmail = UsageSnapshot.pending(for: .claude)

        // The resolver receives account labels only. A view later suppresses the email
        // and tooltip when the matching snapshot has no email.
        #expect(snapshotWithoutEmail.accountEmail == nil)
        #expect(showsPersistentEmail(for: first, in: [first, second]))
    }
}
