import HeadroomCore
import SwiftUI
import Testing
@testable import Headroom

/// PA12: a just-added account carried an untyped preset, so two never-signed-in rows in one
/// card described the same state as two different problems with two different fixes. These
/// pin the substitution — and pin that it is *only* the add-account preset that borrows.
@Suite
struct PresentedSetupOutcomeTests {
    @Test func theAddAccountPresetBorrowsItsProvidersNeverSignedInOutcome() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        #expect(presentedSetupOutcome(for: preset, providerID: .claude) == .claudeLoginRequired)
        #expect(presentedSetupOutcome(for: preset, providerID: .codex) == .codexAuthAbsent)
        #expect(presentedSetupOutcome(for: preset, providerID: .grok) == .grokAuthAbsent)
        #expect(presentedSetupOutcome(for: preset, providerID: .cursor) == .cursorAuthAbsent)
    }

    /// Every borrowed outcome is one Core already calls "never signed in", so the row cannot
    /// end up offering a recovery for a state it is not in.
    @Test func everyBorrowedOutcomeIsANeverSignedInOne() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        for providerID in [ProviderID.claude, .codex, .grok, .cursor] {
            let outcome = presentedSetupOutcome(for: preset, providerID: providerID)
            #expect(outcome?.isNeverSignedIn == true)
        }
    }

    /// The borrowed outcome carries both halves the audit found missing: the typed sentence
    /// and a two-action recovery, instead of "Finish sign-in to add this account" + a lone
    /// "Sign In".
    @Test func theBorrowedOutcomeSuppliesBothSentenceAndRecovery() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        let outcome = presentedSetupOutcome(for: preset, providerID: .claude)
        #expect(outcome?.message == ProviderSetupOutcome.claudeLoginRequired.message)
        #expect(outcome?.message != UsageStore.finishSignInMessage)
        let recovery = outcome?.recoveryPresentation
        #expect(recovery?.primaryLabel == "Open Claude Setup")
        #expect(recovery?.secondaryLabel == "Check Now")
    }

    /// PA12 unifies one preset, not every untyped failure. A real `notLoggedIn` from a probe
    /// keeps its own message and gets no invented recovery.
    @Test func anUnrelatedUntypedFailureIsLeftAlone() {
        let other = FailureReason.notLoggedIn("Not logged in")
        #expect(presentedSetupOutcome(for: other, providerID: .claude) == nil)
        #expect(presentedSetupOutcome(for: .transient("Timed out"), providerID: .claude) == nil)
    }

    /// Anything Core already typed passes straight through — the substitution never
    /// overwrites a diagnosis.
    @Test func typedOutcomesPassThroughUntouched() {
        let typed = FailureReason.providerSetup(.codexRejectedAuth)
        #expect(presentedSetupOutcome(for: typed, providerID: .codex) == .codexRejectedAuth)
        // Even when the provider disagrees with the outcome's own family.
        #expect(presentedSetupOutcome(for: typed, providerID: .claude) == .codexRejectedAuth)
    }

    /// An unknown provider gets nothing rather than a Claude-flavoured guess.
    @Test func anUnknownProviderBorrowsNothing() {
        let preset = FailureReason.notLoggedIn(UsageStore.finishSignInMessage)
        #expect(presentedSetupOutcome(for: preset, providerID: ProviderID("gemini")) == nil)
    }
}

/// PA7 + PB11 on the identity row itself.
@Suite
struct IdentityRowMetricsTests {
    /// PA7: C6A unified the six capsules' height but left 9.5 medium / 10 semibold / 10.5
    /// semibold / 11 semibold inside them. One label role, stated once, applied by
    /// `identityCapsule` — so a call site cannot re-introduce a tier by declaring its own
    /// font.
    @Test func theCapsuleCarriesOneLabelRole() {
        #expect(IdentityRowMetrics.capsuleLabelSize == 10.5)
        #expect(IdentityRowMetrics.capsuleLabelWeight == Font.Weight.medium)
        #expect(IdentityRowMetrics.capsuleLabelKerning == 0.2)
        #expect(IdentityRowMetrics.capsuleHeight == 18)
    }

    /// PB11: the title tooltip needs a truthful truncation signal. A row wide enough for the
    /// string is not truncated; a narrower one is.
    @Test func truncationIsMeasuredAgainstTheStringsOwnWidth() {
        let intrinsic = IdentityRow.titleIntrinsicWidth("Personal")
        #expect(intrinsic > 0)
        #expect(IdentityRow.titleIsTruncated("Personal", renderedWidth: intrinsic + 10) == false)
        #expect(IdentityRow.titleIsTruncated("Personal", renderedWidth: intrinsic) == false)
        #expect(IdentityRow.titleIsTruncated("Personal", renderedWidth: intrinsic - 12) == true)
    }

    /// Sub-pixel layout rounding must not claim a truncation that never happened.
    @Test func aQuarterPointShortOfIdealIsNotTruncation() {
        let intrinsic = IdentityRow.titleIntrinsicWidth("Work")
        #expect(IdentityRow.titleIsTruncated("Work", renderedWidth: intrinsic - 0.25) == false)
    }

    /// The pre-layout pass reports zero, which is not a truncation — otherwise every row
    /// would flash a redundant tooltip on its first frame.
    @Test func aZeroWidthIsThePreLayoutPassNotATruncation() {
        #expect(IdentityRow.titleIsTruncated("A very long account label", renderedWidth: 0) == false)
    }

    /// A longer string needs more room, so it truncates at a width the shorter one survives.
    @Test func alongerTitleTruncatesSooner() {
        let short = IdentityRow.titleIntrinsicWidth("Work")
        let long = IdentityRow.titleIntrinsicWidth("Work — long-lived research account")
        #expect(long > short)
        #expect(IdentityRow.titleIsTruncated("Work", renderedWidth: short + 4) == false)
        #expect(IdentityRow.titleIsTruncated("Work — long-lived research account",
                                             renderedWidth: short + 4) == true)
    }
}
