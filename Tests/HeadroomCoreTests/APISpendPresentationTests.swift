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
            freshness: .stale(.notLoggedIn("Add a Anthropic admin API key in Settings")),
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Needs setup")
        #expect(status.tone == .warning)
        #expect(status.message == "Add an admin key to see Anthropic spend")
        #expect(status.callToAction == "Add key…")
        #expect(status.remoteHint == "Set up on Mac")
    }

    /// The reported contradiction: a saved key the provider rejected was badged
    /// "Needs setup" next to an "Add key" button. Badge, message and CTA must all agree.
    @Test func rejectedKeyReadsAsRejectedNotAsMissing() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("Anthropic admin key rejected")),
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Key rejected")
        #expect(status.tone == .critical)
        #expect(status.message == "Anthropic didn't accept the saved admin key")
        #expect(status.callToAction == "Replace key…")
    }

    @Test func rejectedKeyCopyNamesEachProvider() {
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("OpenAI admin key rejected")),
            displayName: "OpenAI API"
        ).message == "OpenAI didn't accept the saved admin key")
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("xAI management key rejected")),
            displayName: "xAI API"
        ).message == "xAI didn't accept the saved admin key")
    }

    @Test func scopeDeniedKeyReadsAsAnAccessProblem() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("Anthropic key lacks cost report access")),
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Key lacks access")
        #expect(status.tone == .warning)
        #expect(status.message == "Key can't read the cost report")
        #expect(status.callToAction == "Fix key…")
    }

    @Test func transientFailureKeepsTheStaleBehaviour() {
        for reason in [FailureReason.transient("Network unavailable"), .decode("Couldn't read Anthropic cost response")] {
            let status = APISpendPresentation.rowStatus(freshness: .stale(reason), displayName: "Anthropic API")

            #expect(status.badge == "Stale")
            #expect(status.tone == .neutral)
            #expect(status.message == reason.message)
            // Transient staleness is not a Mac-only fix — the next poll may clear it.
            #expect(status.remoteHint == nil)
        }
    }

    @Test func pendingAndLiveRowsCarryNoBadge() {
        let pending = APISpendPresentation.rowStatus(freshness: .pending, displayName: "Anthropic API")
        #expect(pending.badge == nil)
        #expect(pending.message == "Waiting for cost data")
        #expect(pending.tone == .quiet)

        let live = APISpendPresentation.rowStatus(freshness: .live, displayName: "Anthropic API")
        #expect(live.badge == nil)
        #expect(live.message == nil)
        #expect(live.callToAction == nil)
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
