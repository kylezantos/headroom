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
        #expect(PlanLabelPresentation.displayName(DemoFixture.codexSnapshot.planLabel, provider: .codex) == "Pro Lite")
    }

    /// Every Codex `plan_type` OpenAI's client knows (codex-rs `PlanType`), aliases included.
    @Test(arguments: [
        ("free", "Free"), ("go", "Go"), ("plus", "Plus"),
        // DECISION D1
        ("pro", "Pro"), ("prolite", "Pro Lite"), ("promax", "Pro Max"),
        // DECISION D2
        ("team", "Business"), ("business", "Business"),
        // DECISION D3
        ("self_serve_business_prolite", "Business"), ("self_serve_business_usage_based", "Business"),
        ("enterprise", "Enterprise"), ("hc", "Enterprise"), ("ent26", "Enterprise"),
        ("enterprise_cbp_usage_based", "Enterprise"), ("enterprise_cbp_automation", "Enterprise"),
        ("edu", "Edu"), ("education", "Edu"), ("edu_plus", "Edu Plus"), ("edu_pro", "Edu Pro"),
        ("free_workspace", "Free"), ("guest", "Guest"), ("k12", "K-12"),
        ("unknown", nil), ("quorum", nil),
    ] as [(String, String?)])
    func mapsEveryCodexPlanType(_ raw: String, _ expected: String?) {
        #expect(PlanLabelPresentation.displayName(raw, provider: .codex) == expected)
    }

    /// The reported pill, and the same id with no provider: still readable, never raw.
    @Test func selfServeBusinessReadsAsBusiness() {
        #expect(PlanLabelPresentation.displayName("self_serve_business_prolite", provider: .codex) == "Business")
        #expect(PlanLabelPresentation.displayName("Self_serve_business_prolite", provider: .codex) == "Business")
        #expect(PlanLabelPresentation.displayName("self_serve_business_prolite") == "Business Pro Lite")
    }

    /// DECISION D2 is Codex-only: Claude also sells a Team plan, and the other providers
    /// keep the generic path.
    @Test func teamStaysTeamOutsideCodex() {
        #expect(PlanLabelPresentation.displayName("Team", provider: .claude) == "Team")
        #expect(PlanLabelPresentation.displayName("team", provider: .claude) == "Team")
        #expect(PlanLabelPresentation.displayName("Max 20x", provider: .claude) == "Max 20x")
        #expect(PlanLabelPresentation.displayName("Pro+", provider: .cursor) == "Pro+")
        #expect(PlanLabelPresentation.displayName("Start", provider: .cursor) == "Start")
        #expect(PlanLabelPresentation.displayName("Business", provider: .cursor) == "Business")
        #expect(PlanLabelPresentation.displayName("SuperGrok", provider: .grok) == "SuperGrok")
        #expect(PlanLabelPresentation.displayName("supergrokheavy", provider: .grok) == "SuperGrok Heavy")
    }

    @Test func humanizesUnknownIdentifiers() {
        #expect(PlanLabelPresentation.displayName("SUPER_GROK_HEAVY") == "SuperGrok Heavy")
        #expect(PlanLabelPresentation.displayName("x_premium_plus") == "X Premium Plus")
        #expect(PlanLabelPresentation.displayName("X_PREMIUM_PLUS") == "X Premium Plus")
        #expect(PlanLabelPresentation.displayName("ULTRA") == "Ultra")
        #expect(PlanLabelPresentation.displayName("new_tier_k12", provider: .codex) == "New K-12")
        #expect(PlanLabelPresentation.displayName("self_serve") == nil)
        #expect(PlanLabelPresentation.displayName("_") == nil)
    }

    /// Invariant: no input, for any provider, yields a pill containing `_`.
    @Test func neverReturnsAnUnderscore() {
        var generator = SplitMix64(seed: 0x5EED_0414)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_ -")
        let providers: [ProviderID?] = [nil, .claude, .codex, .grok, .cursor]
        for _ in 0..<500 {
            let length = Int.random(in: 1...24, using: &generator)
            let raw = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            for provider in providers {
                let shown = PlanLabelPresentation.displayName(raw, provider: provider)
                #expect(shown?.contains("_") != true, "\(raw) → \(shown ?? "nil")")
            }
        }
    }
}

/// Deterministic generator so the property test replays the same 500 inputs every run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
