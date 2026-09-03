import Testing
import Foundation
@testable import HeadroomCore

/// Pins the badge text for the raw plan ids each provider actually reports. The models
/// stay lenient (#709) — only the display mapping is opinionated.
struct PlanLabelPresentationTests {
    @Test func mapsKnownCodexPlanIDs() {
        #expect(PlanLabelPresentation.displayName("prolite") == "Pro Lite")
        #expect(PlanLabelPresentation.displayName("plus") == "Plus")
        #expect(PlanLabelPresentation.displayName("pro") == "Pro")
        #expect(PlanLabelPresentation.displayName("max") == "Max")
        #expect(PlanLabelPresentation.displayName("team") == "Team")
        #expect(PlanLabelPresentation.displayName("enterprise") == "Enterprise")
        #expect(PlanLabelPresentation.displayName("free") == "Free")
    }

    @Test func matchesKnownIDsCaseAndSeparatorInsensitively() {
        #expect(PlanLabelPresentation.displayName("Prolite") == "Pro Lite")
        #expect(PlanLabelPresentation.displayName("PROLITE") == "Pro Lite")
        #expect(PlanLabelPresentation.displayName("pro_lite") == "Pro Lite")
        #expect(PlanLabelPresentation.displayName("pro-lite") == "Pro Lite")
        #expect(PlanLabelPresentation.displayName("pro lite") == "Pro Lite")
        #expect(PlanLabelPresentation.displayName("  plus  ") == "Plus")
    }

    /// The old `.capitalized` badge flattened Grok's own casing to "Supergrok".
    @Test func preservesGrokTierCasing() {
        #expect(PlanLabelPresentation.displayName("SuperGrok") == "SuperGrok")
        #expect(PlanLabelPresentation.displayName("supergrok") == "SuperGrok")
        #expect(PlanLabelPresentation.displayName("supergrok heavy") == "SuperGrok Heavy")
    }

    /// Claude pre-formats its plan in the parser and Cursor reads its own header text;
    /// a value that already carries capitals is display text, not an id to re-case.
    @Test func leavesProviderFormattedLabelsAlone() {
        #expect(PlanLabelPresentation.displayName("Max 20x") == "Max 20x")
        #expect(PlanLabelPresentation.displayName("Pro+") == "Pro+")
        #expect(PlanLabelPresentation.displayName("ChatGPT Plus") == "ChatGPT Plus")
    }

    /// Unknown tiers still render (#709 leniency) rather than falling back to nothing.
    @Test func humanizesUnknownLowercaseIDs() {
        #expect(PlanLabelPresentation.displayName("business") == "Business")
        #expect(PlanLabelPresentation.displayName("edu") == "Edu")
        #expect(PlanLabelPresentation.displayName("ultra pro") == "Ultra Pro")
        #expect(PlanLabelPresentation.displayName("pro+") == "Pro+")
    }

    @Test func collapsesMissingAndBlankLabels() {
        #expect(PlanLabelPresentation.displayName(nil) == nil)
        #expect(PlanLabelPresentation.displayName("") == nil)
        #expect(PlanLabelPresentation.displayName("   ") == nil)
    }

    /// The provider keeps the verbatim id; only the badge is humanized.
    @Test func demoFixturesRenderHumanized() {
        #expect(DemoFixture.codexSnapshot.planLabel == "Prolite")
        #expect(PlanLabelPresentation.displayName(DemoFixture.codexSnapshot.planLabel) == "Pro Lite")
    }
}
