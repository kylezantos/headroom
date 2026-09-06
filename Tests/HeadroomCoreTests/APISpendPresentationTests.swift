import Foundation
import Testing
@testable import HeadroomCore

struct APISpendPresentationTests {
    private let now = Date(timeIntervalSince1970: 2_000)

    @Test func usdAmountFormatsWithTwoDecimals() {
        #expect(APISpendPresentation.amountText(amount: 12.3, currency: "usd") == "$12.30")
    }

    @Test func unknownCurrencyFormatsWithCodeFallback() {
        let text = APISpendPresentation.amountText(amount: 12.3, currency: "xyz")

        #expect(text?.contains("XYZ") == true)
        #expect(text?.contains("12.30") == true)
    }

    @Test func missingAmountReturnsNil() {
        #expect(APISpendPresentation.amountText(amount: nil, currency: "usd") == nil)
        #expect(APISpendPresentation.amountText(amount: 12.3, currency: nil) == nil)
    }

    @Test func addCreditsURLTargetsProviderBillingPages() {
        #expect(APISpendPresentation.addCreditsURL(for: .claude)?.absoluteString == "https://platform.claude.com/settings/billing")
        #expect(APISpendPresentation.addCreditsURL(for: .codex)?.absoluteString == "https://platform.openai.com/settings/organization/billing/overview")
        #expect(APISpendPresentation.addCreditsURL(for: .grok)?.absoluteString == "https://console.x.ai")
        #expect(APISpendPresentation.addCreditsURL(for: ProviderID("someday")) == nil)
    }

    @Test func balancePresentationReadsAsRemainingWithoutChangingSpendCopy() {
        let balance = WidgetAPISpendSummary(
            id: ProviderID.grok.raw,
            displayName: "xAI API",
            amount: 42.1,
            currency: "usd",
            periodLabel: "Prepaid balance",
            kind: .balance,
            capturedAt: now,
            freshness: .live
        )
        let spend = WidgetAPISpendSummary(
            id: ProviderID.codex.raw,
            displayName: "OpenAI API",
            amount: 12.3,
            currency: "usd",
            periodLabel: "Current month",
            capturedAt: now,
            freshness: .live
        )

        #expect(APISpendPresentation.amountText(balance) == "$42.10 left")
        #expect(APISpendPresentation.contextLabel(kind: .balance, periodLabel: balance.periodLabel) == "Remaining balance")
        #expect(APISpendPresentation.amountText(spend) == "$12.30")
        #expect(APISpendPresentation.contextLabel(kind: .periodSpend, periodLabel: spend.periodLabel) == "Current month")
    }

    @Test func statusTextUsesFreshness() {
        #expect(APISpendPresentation.statusText(freshness: WidgetProviderFreshness.pending, capturedAt: nil, now: now) == "Waiting for cost data")
        #expect(APISpendPresentation.statusText(freshness: WidgetProviderFreshness.live, capturedAt: now.addingTimeInterval(-60), now: now) == "Updated 1 min ago")
        #expect(APISpendPresentation.statusText(
            freshness: WidgetProviderFreshness.stale(message: "Add API key", needsAttention: true),
            capturedAt: now,
            now: now
        ) == "Set up on Mac")
        #expect(APISpendPresentation.statusText(
            freshness: WidgetProviderFreshness.stale(message: "Temporary issue", needsAttention: false),
            capturedAt: now.addingTimeInterval(-120),
            now: now
        ) == "Updated 2 min ago")
        #expect(APISpendPresentation.statusText(
            freshness: WidgetProviderFreshness.stale(message: "Temporary issue", needsAttention: false),
            capturedAt: nil,
            now: now
        ) == "Not updated")
    }

    @Test func companionStatusMatchesCurrentMacRows() {
        #expect(APISpendPresentation.companionStatusText(freshness: .pending) == "Waiting for cost data")
        #expect(APISpendPresentation.companionStatusText(freshness: .live) == nil)
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Add API key", needsAttention: true)
        ) == "Needs setup")
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Temporary issue", needsAttention: false)
        ) == "Stale")
    }

    // MARK: - Row status

    @Test func vendorNameDropsTheAPISuffix() {
        #expect(APISpendPresentation.vendorName(from: "Anthropic API") == "Anthropic")
        #expect(APISpendPresentation.vendorName(from: "OpenAI API") == "OpenAI")
        #expect(APISpendPresentation.vendorName(from: "xAI API") == "xAI")
        #expect(APISpendPresentation.vendorName(from: "Someday") == "Someday")
        #expect(APISpendPresentation.vendorName(from: " API") == "API")
    }

    @Test func missingKeyAsksForOne() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.notLoggedIn("Add an admin key in Settings")),
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Needs setup")
        #expect(status.tone == .warning)
        #expect(status.message == "Add an admin key to see Anthropic spend")
        #expect(status.callToAction == "Add key")
        #expect(status.remoteHint == "Set up on Mac")
    }

    /// Each vendor's endpoints take a different credential, so the ask has to name the one
    /// the Settings pane's field asks for — not Anthropic's noun for all three.
    @Test func missingKeyNamesEachProvidersOwnCredential() {
        let expected: [(ProviderID, String, String)] = [
            (.claude, "Anthropic API", "Add an admin key to see Anthropic spend"),
            (.codex, "OpenAI API", "Add an admin key to see OpenAI spend"),
            (.grok, "xAI API", "Add a management key to see xAI spend"),
        ]

        for (providerID, displayName, message) in expected {
            #expect(APISpendPresentation.rowStatus(
                freshness: .stale(.notLoggedIn("Add a key in Settings")),
                providerID: providerID,
                displayName: displayName
            ).message == message)
        }
    }

    /// A spend provider we haven't declared a credential for reads plainly rather than
    /// inheriting Anthropic's "admin key".
    @Test func unknownSpendProviderFallsBackToAPlainAPIKey() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.notLoggedIn("Add a key in Settings")),
            providerID: ProviderID("someday"),
            displayName: "Someday API"
        )

        #expect(status.message == "Add an API key to see Someday spend")
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("no access")),
            providerID: ProviderID("someday"),
            displayName: "Someday API"
        ).message == "Key can't read cost data")
    }

    /// The article belongs to the credential, never to the vendor: "a xAI"/"an xAI" is the
    /// shape of the bug this copy is built to make impossible.
    @Test func noSpendCopyGluesAnArticleToAVendorName() {
        let providers: [(ProviderID, String)] = [
            (.claude, "Anthropic API"),
            (.codex, "OpenAI API"),
            (.grok, "xAI API"),
            (ProviderID("someday"), "Someday API"),
        ]
        let reasons: [FailureReason] = [
            .notLoggedIn("Add a key in Settings"),
            .needsReauth("key rejected"),
            .scopeDenied("key lacks access"),
        ]

        for (providerID, displayName) in providers {
            let vendor = APISpendPresentation.vendorName(from: displayName)
            for reason in reasons {
                let status = APISpendPresentation.rowStatus(
                    freshness: .stale(reason),
                    providerID: providerID,
                    displayName: displayName
                )
                let lines = [status.message, status.badge, status.callToAction, status.remoteHint]
                    .compactMap { $0 }

                for line in lines {
                    #expect(!line.contains("a \(vendor)"))
                    #expect(!line.contains("an \(vendor)"))
                }
            }
        }
    }

    /// The reported contradiction: a saved key the provider rejected was badged
    /// "Needs setup" next to an "Add key" button. Badge, message and CTA must all agree.
    @Test func rejectedKeyReadsAsRejectedNotAsMissing() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("Anthropic admin key rejected")),
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Key rejected")
        #expect(status.tone == .critical)
        #expect(status.message == "Anthropic didn't accept the saved admin key")
        #expect(status.callToAction == "Replace key")
    }

    @Test func rejectedKeyCopyNamesEachProvider() {
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("OpenAI admin key rejected")),
            providerID: .codex,
            displayName: "OpenAI API"
        ).message == "OpenAI didn't accept the saved admin key")
        // xAI's endpoints never saw an admin key — the pane asks for a management key.
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("xAI management key rejected")),
            providerID: .grok,
            displayName: "xAI API"
        ).message == "xAI didn't accept the saved management key")
    }

    @Test func scopeDeniedKeyReadsAsAnAccessProblem() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("Anthropic key lacks cost report access")),
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Key lacks access")
        #expect(status.tone == .warning)
        #expect(status.message == "Key can't read the cost report")
        #expect(status.callToAction == "Fix key")
    }

    /// The 403 line names the surface each vendor actually refused.
    @Test func scopeDeniedNamesEachProvidersReport() {
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("OpenAI key lacks organization cost access")),
            providerID: .codex,
            displayName: "OpenAI API"
        ).message == "Key can't read organization costs")
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("xAI key lacks billing read access")),
            providerID: .grok,
            displayName: "xAI API"
        ).message == "Key can't read team billing")
    }

    @Test func transientFailureKeepsTheStaleBehaviour() {
        for reason in [FailureReason.transient("Network unavailable"), .decode("Couldn't read Anthropic cost response")] {
            let status = APISpendPresentation.rowStatus(
                freshness: .stale(reason),
                providerID: .claude,
                displayName: "Anthropic API"
            )

            #expect(status.badge == "Stale")
            #expect(status.tone == .neutral)
            #expect(status.message == reason.message)
            // Transient staleness is not a Mac-only fix — the next poll may clear it.
            #expect(status.remoteHint == nil)
        }
    }

    @Test func pendingAndLiveRowsCarryNoBadge() {
        let pending = APISpendPresentation.rowStatus(
            freshness: .pending,
            providerID: .claude,
            displayName: "Anthropic API"
        )
        #expect(pending.badge == nil)
        #expect(pending.message == "Waiting for cost data")
        #expect(pending.tone == .quiet)

        let live = APISpendPresentation.rowStatus(
            freshness: .live,
            providerID: .claude,
            displayName: "Anthropic API"
        )
        #expect(live.badge == nil)
        #expect(live.message == nil)
        #expect(live.callToAction == nil)
    }

    // MARK: - When the action shows

    /// Continuity keeps the last total on the row after the key stops working. The card
    /// used to hang its button off "there is no amount", so that row showed a stale number
    /// beside a "Key rejected" badge and no way to fix it.
    @Test func keyProblemsKeepTheirActionEvenWithARetainedAmount() {
        let keyProblems: [FailureReason] = [
            .notLoggedIn("Add an admin key in Settings"),
            .needsReauth("Anthropic admin key rejected"),
            .scopeDenied("Anthropic key lacks cost report access"),
        ]

        for reason in keyProblems {
            let status = APISpendPresentation.rowStatus(
                freshness: .stale(reason),
                providerID: .claude,
                displayName: "Anthropic API"
            )

            #expect(status.keyNeedsAttention)
            #expect(status.showsCTA(hasAmount: true))
            #expect(status.showsCTA(hasAmount: false))
        }
    }

    /// Retryable staleness keeps the old rule: the next poll may clear it, so a row that
    /// still has a number stays a plain number.
    @Test func retryableStalenessOnlyOffersTheActionWithoutAnAmount() {
        for reason in [FailureReason.transient("Network unavailable"), .decode("Couldn't read Anthropic cost response")] {
            let status = APISpendPresentation.rowStatus(
                freshness: .stale(reason),
                providerID: .claude,
                displayName: "Anthropic API"
            )

            #expect(!status.keyNeedsAttention)
            #expect(!status.showsCTA(hasAmount: true))
            #expect(status.showsCTA(hasAmount: false))
        }
    }

    /// A permanent failure that isn't about a key keeps the source's own copy, so it also
    /// keeps the old amount-driven rule rather than nagging over a retained total.
    @Test func genericSetupFailureKeepsTheAmountDrivenRule() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.providerSetup(.claudeCLIMissing)),
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(!status.keyNeedsAttention)
        #expect(!status.showsCTA(hasAmount: true))
        #expect(status.showsCTA(hasAmount: false))
    }

    @Test func liveRowsNeverShowTheAction() {
        let live = APISpendPresentation.rowStatus(
            freshness: .live,
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(!live.showsCTA(hasAmount: true))
        #expect(!live.showsCTA(hasAmount: false))
    }

    @Test func companionRowsShareTheSameActionRule() {
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(message: "Anthropic admin key rejected", needsAttention: true),
            attention: .keyRejected,
            providerID: .claude,
            displayName: "Anthropic API"
        ).showsCTA(hasAmount: true))
        #expect(!APISpendPresentation.rowStatus(
            freshness: .stale(message: "Temporary issue", needsAttention: false),
            attention: .retryable,
            providerID: .claude,
            displayName: "Anthropic API"
        ).showsCTA(hasAmount: true))
    }

    @Test func onlyKeyAttentionsCountAsAKeyProblem() {
        #expect(APISpendAttention.missingKey.isKeyProblem)
        #expect(APISpendAttention.keyRejected.isKeyProblem)
        #expect(APISpendAttention.keyLacksAccess.isKeyProblem)
        #expect(!APISpendAttention.setupRequired.isKeyProblem)
        #expect(!APISpendAttention.retryable.isKeyProblem)
    }

    @Test func attentionIsDerivedFromTheTypedReason() {
        #expect(APISpendAttention(reason: .notLoggedIn("x")) == .missingKey)
        #expect(APISpendAttention(reason: .needsReauth("x")) == .keyRejected)
        #expect(APISpendAttention(reason: .scopeDenied("x")) == .keyLacksAccess)
        #expect(APISpendAttention(reason: .transient("x")) == .retryable)
        #expect(APISpendAttention(reason: .decode("x")) == .retryable)
    }

    @Test func companionMirrorsTheMacBadgeWhenAttentionIsPresent() {
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Anthropic admin key rejected", needsAttention: true),
            attention: .keyRejected
        ) == "Key rejected")
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Anthropic key lacks cost report access", needsAttention: true),
            attention: .keyLacksAccess
        ) == "Key lacks access")
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Add API key", needsAttention: true),
            attention: .missingKey
        ) == "Needs setup")
    }

    @Test func companionFallsBackToThePermanenceSplitForOlderPayloads() {
        // An envelope written before the additive `attention` field carries none.
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Add API key", needsAttention: true),
            attention: nil
        ) == "Needs setup")
        #expect(APISpendPresentation.rowStatus(
            freshness: WidgetProviderFreshness.stale(message: "Add API key", needsAttention: true)
        ).message == "Add API key")
    }

    @Test func widgetStatusTextNamesTheMacOnlyFix() {
        #expect(APISpendPresentation.statusText(
            freshness: .stale(message: "Anthropic admin key rejected", needsAttention: true),
            attention: .keyRejected,
            capturedAt: now,
            now: now
        ) == "Replace key on Mac")
        #expect(APISpendPresentation.statusText(
            freshness: .stale(message: "Anthropic key lacks cost report access", needsAttention: true),
            attention: .keyLacksAccess,
            capturedAt: now,
            now: now
        ) == "Fix key on Mac")
    }
}
