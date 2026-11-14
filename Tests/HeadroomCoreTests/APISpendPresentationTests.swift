import Foundation
import Testing
@testable import HeadroomCore

struct APISpendPresentationTests {
    private let now = Date(timeIntervalSince1970: 2_000)

    /// The current-month tag is the localized three-letter month ("Sep") in the user's zone.
    /// Pinned against the `setLocalizedDateFormatFromTemplate("MMM")` formatter the label
    /// used to build per call, so the format-style replacement prints the same string.
    @Test func currentMonthDisplayLabelMatchesLocalizedAbbreviatedMonth() {
        let calendar = Calendar(identifier: .gregorian)
        var zoned = calendar
        zoned.timeZone = .current
        let reference = DateFormatter()
        reference.calendar = zoned
        reference.locale = .current
        reference.setLocalizedDateFormatFromTemplate("MMM")
        let dates = [0, 2_000, 1_700_000_000, 1_790_000_000, 1_767_225_599].map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }
        for date in dates {
            #expect(APISpendPeriod.currentMonth.displayLabel(now: date, calendar: calendar) == reference.string(from: date))
        }
    }

    @Test func rollingDisplayLabelKeepsTheDescriptivePhrase() {
        #expect(APISpendPeriod.rolling30Days.displayLabel(now: now) == APISpendPeriod.rolling30Days.label)
    }

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
        // S5A: Cursor has no billing page to open, which is what makes its spend row the
        // one that draws the reserved-empty top-up slot in `--demo spend-states`.
        #expect(APISpendPresentation.addCreditsURL(for: .cursor) == nil)
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
        // CA-S8: "Balance"; the amount already says "left".
        #expect(APISpendPresentation.contextLabel(kind: .balance, periodLabel: balance.periodLabel) == "Balance")
        #expect(APISpendPresentation.amountText(spend) == "$12.30")
        #expect(APISpendPresentation.contextLabel(kind: .periodSpend, periodLabel: spend.periodLabel) == "Current month")
    }

    /// R2C8: the two directions a spend figure can point, in the meters' own suffix
    /// vocabulary. "$58.90" alone reads identically on a period-spend row and a balance row,
    /// so the popover prints the term after the amount; the term itself lives in Core so the
    /// popover, the widgets and the phone mirror all spell it the same way.
    @Test func directionTermNamesWhichWayTheFigurePoints() {
        #expect(APISpendPresentation.directionTerm(kind: .periodSpend) == "used")
        #expect(APISpendPresentation.directionTerm(kind: .balance) == "left")
    }

    /// R2C8 surfaced the existing `"left"` term on macOS; it did not change what the widget
    /// and phone strings say, because those surfaces have no suffix column to set a term in.
    @Test func widgetAmountStringKeepsItsExistingShape() {
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
            amount: 58.9,
            currency: "usd",
            periodLabel: "Current month",
            capturedAt: now,
            freshness: .live
        )

        #expect(APISpendPresentation.amountText(balance) == "$42.10 left")
        #expect(APISpendPresentation.amountText(spend) == "$58.90")
    }

    @Test func companionStatusMatchesCurrentMacRows() {
        #expect(APISpendPresentation.companionStatusText(freshness: .pending) == "Waiting for cost data")
        #expect(APISpendPresentation.companionStatusText(freshness: .live) == nil)
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Add API key", needsAttention: true)
        ) == "Needs setup")
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Temporary issue", needsAttention: false)
        ) == "Not refreshed")
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
        #expect(status.callToAction == "Add Key")
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

    /// R2C8: a prepaid row's figure is money remaining, so the ask names a balance. xAI's
    /// row said "to see xAI spend" beside a chip reading "Remaining balance".
    @Test func missingKeyNamesTheFigureTheKeyWouldUnlock() {
        let reason = FailureReason.notLoggedIn("Add a key in Settings")

        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(reason),
            providerID: .grok,
            displayName: "xAI API",
            kind: .balance
        ).message == "Add a management key to see xAI balance")
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(reason),
            providerID: .claude,
            displayName: "Anthropic API",
            kind: .periodSpend
        ).message == "Add an admin key to see Anthropic spend")
        // The wire-format overload takes the same branch.
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(message: "Add a key in Settings", needsAttention: true),
            attention: .missingKey,
            providerID: .grok,
            displayName: "xAI API",
            kind: .balance
        ).message == "Add a management key to see xAI balance")
        // Period spend stays the default, so a caller that ships no kind is unchanged.
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(reason),
            providerID: .codex,
            displayName: "OpenAI API"
        ).message == "Add an admin key to see OpenAI spend")
    }

    /// Only the Mac can fix a key, so the companion/widget hint says where.
    @Test func widgetRowStatusNamesTheMacOnlyFix() {
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(message: "Anthropic admin key rejected", needsAttention: true),
            attention: .keyRejected
        ).remoteHint == "Replace key on Mac")
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(message: "Anthropic key lacks cost report access", needsAttention: true),
            attention: .keyLacksAccess
        ).remoteHint == "Replace key on Mac")
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(message: "Add API key", needsAttention: true),
            attention: .missingKey
        ).remoteHint == "Set up on Mac")
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
        ).message == "Key can’t read cost data")
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
    /// "Needs setup" next to an "Add Key" button. Badge, message and CTA must all agree.
    @Test func rejectedKeyReadsAsRejectedNotAsMissing() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("Anthropic admin key rejected")),
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Key rejected")
        #expect(status.tone == .critical)
        #expect(status.message == "Anthropic didn’t accept the saved admin key")
        #expect(status.callToAction == "Replace Key")
    }

    @Test func rejectedKeyCopyNamesEachProvider() {
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("OpenAI admin key rejected")),
            providerID: .codex,
            displayName: "OpenAI API"
        ).message == "OpenAI didn’t accept the saved admin key")
        // xAI's endpoints never saw an admin key — the pane asks for a management key.
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("xAI management key rejected")),
            providerID: .grok,
            displayName: "xAI API"
        ).message == "xAI didn’t accept the saved management key")
    }

    @Test func scopeDeniedKeyReadsAsAnAccessProblem() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("Anthropic key lacks cost report access")),
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Key lacks access")
        #expect(status.tone == .warning)
        #expect(status.message == "Key can’t read the cost report")
        // PA3: the pane has Replace and Remove, so "Fix Key" named a control that is not there.
        #expect(status.callToAction == "Replace Key")
    }

    /// The 403 line names the surface each vendor actually refused.
    @Test func scopeDeniedNamesEachProvidersReport() {
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("OpenAI key lacks organization cost access")),
            providerID: .codex,
            displayName: "OpenAI API"
        ).message == "Key can’t read organization costs")
        #expect(APISpendPresentation.rowStatus(
            freshness: .stale(.scopeDenied("xAI key lacks billing read access")),
            providerID: .grok,
            displayName: "xAI API"
        ).message == "Key can’t read team billing")
    }

    @Test func transientFailureKeepsTheStaleBehaviour() {
        for reason in [FailureReason.transient("Network unavailable"), .decode("Couldn’t read Anthropic cost response")] {
            let status = APISpendPresentation.rowStatus(
                freshness: .stale(reason),
                providerID: .claude,
                displayName: "Anthropic API"
            )

            // CA-P3: no capture time to date it, so it says so plainly.
            #expect(status.badge == "Not refreshed")
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
        // PA3: the first fetch after a key is saved has no retained amount, so a CTA here
        // would render — telling someone who just saved a key to add one.
        #expect(pending.callToAction == nil)
        #expect(!pending.showsCTA(hasAmount: false))

        let live = APISpendPresentation.rowStatus(
            freshness: .live,
            providerID: .claude,
            displayName: "Anthropic API"
        )
        #expect(live.badge == nil)
        #expect(live.message == nil)
        #expect(live.callToAction == nil)
    }

    // MARK: - Identity-line short forms (X5)

    /// X5 (Kyle): the popover's identity line puts the tag where the period chip stands, and
    /// the measured 320pt line cannot hold "Needs setup" (−15pt) or "Key lacks access". Each
    /// attention state therefore carries a short form alongside its full badge — and the full
    /// badge, which every other surface reads, must not move.
    @Test func everyAttentionCarriesAnIdentityLineShortForm() {
        let expected: [(reason: FailureReason, badge: String, shortBadge: String)] = [
            (.notLoggedIn("Add an admin key in Settings"), "Needs setup", "Setup"),
            (.needsReauth("Anthropic admin key rejected"), "Key rejected", "Rejected"),
            (.scopeDenied("Anthropic key lacks cost report access"), "Key lacks access", "Denied"),
            (.transient("Network unavailable"), "Not refreshed", "Not refreshed"),
        ]

        for copy in expected {
            let status = APISpendPresentation.rowStatus(
                freshness: .stale(copy.reason),
                providerID: .claude,
                displayName: "Anthropic API"
            )

            #expect(status.badge == copy.badge)
            #expect(status.shortBadge == copy.shortBadge)
        }
    }

    /// CA-P3: a retried figure's tag says how old it is, in the account rows' own phrase, and
    /// falls back to "Not refreshed" when nothing dates it. It never says "Stale".
    @Test func aRetriedFigureIsDatedLikeAnAccountRow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dated = APISpendPresentation.rowStatus(
            freshness: .stale(.transient("Network unavailable")), providerID: .claude,
            displayName: "Anthropic API", readAt: (now.addingTimeInterval(-14 * 60), now))
        #expect(dated.badge == "Last read 14 min ago")
        // The identity-line tag stands beside the figure, so it takes the compact age.
        #expect(dated.shortBadge == "14m ago")
        let undated = APISpendPresentation.rowStatus(
            freshness: .stale(.transient("Network unavailable")), providerID: .claude,
            displayName: "Anthropic API", readAt: (nil, now))
        #expect(undated.badge == "Not refreshed")
        let widget = APISpendPresentation.rowStatus(
            freshness: WidgetProviderFreshness.stale(message: "Temporary issue", needsAttention: false),
            readAt: (now.addingTimeInterval(-2 * 3600), now))
        #expect(widget.badge == "Last read 2 hr ago")
        #expect(widget.shortBadge == "2h ago")
        #expect(Countdown.compactReadAge(capturedAt: now.addingTimeInterval(-20), now: now) == "1m ago")
        #expect(Countdown.compactReadAge(capturedAt: now.addingTimeInterval(-3 * 86_400), now: now) == "3d ago")
        #expect(Countdown.compactReadAge(capturedAt: nil, now: now) == nil)
        // A key problem keeps its own tag; only the retried figure is dated.
        let rejected = APISpendPresentation.rowStatus(
            freshness: .stale(.needsReauth("rejected")), providerID: .claude,
            displayName: "Anthropic API", readAt: (now, now))
        #expect(rejected.badge == "Key rejected")
    }

    /// A permanent provider-setup failure is not a key condition, but it still needs a tag on
    /// the identity line.
    @Test func permanentSetupFailureShortensToSetup() {
        let status = APISpendPresentation.rowStatus(
            freshness: .stale(.providerSetup(.claudeCLIMissing)),
            providerID: .claude,
            displayName: "Anthropic API"
        )

        #expect(status.badge == "Needs setup")
        #expect(status.shortBadge == "Setup")
    }

    /// Live and pending rows keep the period chip, so they must not offer a tag to put in
    /// its place.
    @Test func liveAndPendingRowsCarryNoIdentityLineTag() {
        for freshness in [Freshness.live, .pending] {
            #expect(APISpendPresentation.rowStatus(
                freshness: freshness,
                providerID: .claude,
                displayName: "Anthropic API"
            ).shortBadge == nil)
        }
    }

    // MARK: - Popover identity split (X5)

    /// Core's "Cursor on-demand" measurably clips the identity line, so the popover renders
    /// the vendor as the title and hands the qualifier to the chip. `displayName` itself is
    /// what the widgets and the phone mirror read and is deliberately untouched.
    @Test func popoverIdentitySplitsATrailingQualifierIntoTheChip() {
        let cursor = APISpendPresentation.popoverIdentity(displayName: "Cursor on-demand")

        #expect(cursor.title == "Cursor")
        #expect(cursor.chipOverride == "On-demand")
    }

    /// An initialism is part of the name, not a qualifier — "Anthropic API" must survive
    /// whole, and so must a single-word name.
    @Test func popoverIdentityKeepsInitialismsAndSingleWordNames() {
        for name in ["Anthropic API", "OpenAI API", "xAI API", "Cursor"] {
            let identity = APISpendPresentation.popoverIdentity(displayName: name)

            #expect(identity.title == name)
            #expect(identity.chipOverride == nil)
        }
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

    /// PA3: retryable staleness is the app’s problem, not the key’s — the next poll may clear
    /// it on its own — so the row names no action at all, with or without a retained amount.
    /// It used to offer "Add Key" to a user who already had one saved.
    @Test func retryableStalenessOffersNoAction() {
        for reason in [FailureReason.transient("Network unavailable"), .decode("Couldn’t read Anthropic cost response")] {
            let status = APISpendPresentation.rowStatus(
                freshness: .stale(reason),
                providerID: .claude,
                displayName: "Anthropic API"
            )

            #expect(!status.keyNeedsAttention)
            #expect(status.callToAction == nil)
            #expect(!status.showsCTA(hasAmount: true))
            #expect(!status.showsCTA(hasAmount: false))
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

    /// CA-S8 (COPY-12): a card holding more than one vendor always names the key, so a lone
    /// "Replace Key" under the Cursor row never stands for Anthropic's rejected key.
    @Test func aMultiVendorCardNamesItsKey() {
        #expect(APISpendPresentation.cardCallToAction("Replace Key", vendor: "Anthropic", cardVendorCount: 2)
            == "Replace Anthropic Key")
        #expect(APISpendPresentation.cardCallToAction("Add Key", vendor: "xAI", cardVendorCount: 4) == "Add xAI Key")
        #expect(APISpendPresentation.cardCallToAction("Replace Key", vendor: "Anthropic", cardVendorCount: 1)
            == "Replace Key")
        #expect(APISpendPresentation.cardCallToAction("Top Up", vendor: "OpenAI", cardVendorCount: 2) == "Top Up (OpenAI)")
    }
}
