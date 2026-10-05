import Foundation
import Testing

@testable import HeadroomCore

@Suite
struct CompanionSyncModelsTests {
    private let capture = CompanionWireDate(epochSeconds: 1000)!
    private let original = CompanionWireDate(epochSeconds: 900)!
    private func window(
        kind: CompanionWindowKind = .fiveHour, name: String? = nil, duration: Double? = nil,
        remaining: Double = 15.05, utilization: Double? = 84.951234,
        freshness: CompanionWindowFreshness = .live, observation: CompanionWireDate? = nil,
        since: CompanionWireDate? = nil
    ) throws -> CompanionSlimWindow {
        try CompanionSlimWindow(
            kind: kind, kindName: name, billingPeriodDuration: duration,
            percentRemaining: remaining, utilization: utilization,
            resetKind: .unresolved, resetReason: .absent, freshness: freshness,
            observedAtOverride: observation, unavailableSince: since)
    }
    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try #require(
            JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }
    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    private func roundtrip<T: Codable & Equatable>(_ value: T) throws {
        #expect(try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func compactLiveWindowUsesSharedNormalizationAndRetainsOptionalSource() throws {
        let value = try window()
        #expect(value.percentRemaining == 15.1)
        #expect(value.utilization == 84.951234)
        let json = try object(value)
        #expect(Set(json.keys) == Set(["k", "p", "u", "r", "e"]))
        #expect(json["r"] as? String == "unresolved")
        try roundtrip(value)
        let lifted = try #require(value.widgetSummary(accountCapturedAt: capture))
        #expect(lifted.kind == .fiveHour && lifted.label == "5h" && lifted.id == "fiveHour")
        #expect(lifted.severity == .low && lifted.observedAt == capture.date)
        #expect(lifted.utilization == value.utilization)
        #expect(lifted.resetLabel == nil && lifted.resetTimeZoneIdentifier == nil)
        let legacy = try window(remaining: 100, utilization: nil)
        #expect(legacy.widgetSummary(accountCapturedAt: capture)?.utilization == nil)
    }
    @Test func knownKindsPreserveAssociatedNamesAndFractionalBillingDuration() throws {
        for (kind, name, duration, expectedKind, label) in [
            (
                CompanionWindowKind.weekly, nil as String?, nil as Double?, WidgetWindowKind.weekly,
                "Weekly"
            ),
            (.other, "", nil, .other(""), ""),
            (.billingPeriod, "", 0.5, .other(""), ""),
        ] {
            let value = try window(kind: kind, name: name, duration: duration)
            try roundtrip(value)
            let lifted = try #require(value.widgetSummary(accountCapturedAt: capture))
            #expect(lifted.kind == expectedKind && lifted.label == label)
            #expect(lifted.billingPeriodDuration == duration)
            if name == "" { #expect(lifted.id == "other:" && lifted.widgetDisplayLabel == "Usage") }
        }
        #expect(throws: (any Error).self) { try window(kind: .other) }
        #expect(throws: (any Error).self) { try window(kind: .billingPeriod, duration: 0.5) }
    }
    @Test func invalidFiniteBillingAndUnknownKindsSkipWithoutInventingPeriods() throws {
        for duration in [nil, 0, -1] as [Double?] {
            let value = try window(kind: .billingPeriod, name: "Monthly", duration: duration)
            #expect(value.kind == .unknown)
            #expect(value.widgetSummary(accountCapturedAt: capture) == nil)
            var json = try object(try window(kind: .billingPeriod, name: "Monthly", duration: 0.5))
            json["d"] = duration
            #expect(try decode(CompanionSlimWindow.self, json).kind == .unknown)
        }
        var unknown = try object(try window())
        unknown["k"] = "futurePool"
        #expect(
            try decode(CompanionSlimWindow.self, unknown).widgetSummary(accountCapturedAt: capture)
                == nil
        )
        var wrong = try object(try window(kind: .billingPeriod, name: "Monthly", duration: 0.5))
        wrong["d"] = "0.5"
        #expect(throws: (any Error).self) { try decode(CompanionSlimWindow.self, wrong) }
    }
    @Test func retainedAndUnavailableProvenanceDoesNotBorrowFreshCapture() throws {
        let stale = try window(freshness: .stale, observation: original)
        #expect(
            stale.widgetSummary(accountCapturedAt: capture)?.freshness
                == .stale(observedAt: original.date))
        #expect(stale.widgetSummary(accountCapturedAt: capture)?.observedAt == original.date)
        #expect(try window(freshness: .stale).widgetSummary(accountCapturedAt: capture) == nil)
        let unavailable = try window(
            remaining: 72.34, utilization: 27.654321, freshness: .unavailable,
            observation: original,
            since: capture)
        try roundtrip(unavailable)
        let lifted = try #require(unavailable.widgetSummary(accountCapturedAt: capture))
        #expect(lifted.percentRemaining == 72.3 && lifted.utilization == 27.654321)
        #expect(
            lifted.observedAt == original.date
                && lifted.freshness == .unavailable(since: capture.date))
        #expect(lifted.severity == .healthy && lifted.displayPercentRemaining == nil)
        let fallback = try window(freshness: .unavailable, observation: original)
        #expect(
            fallback.widgetSummary(accountCapturedAt: capture)?.freshness
                == .unavailable(since: original.date))
        #expect(throws: (any Error).self) { try window(freshness: .unavailable) }
        var unknown = try object(stale)
        unknown["f"] = "futureFreshness"
        #expect(
            try decode(CompanionSlimWindow.self, unknown).widgetSummary(accountCapturedAt: capture)?
                .displayPercentRemaining == nil)
    }
    @Test func resetPairsValidateAndUnknownResetNeverInfersDeadline() throws {
        let scheduled = try CompanionSlimWindow(
            kind: .weekly, percentRemaining: 50, resetKind: .scheduled, resetDeadline: capture)
        try roundtrip(scheduled)
        #expect(
            scheduled.widgetSummary(accountCapturedAt: capture)?.resetSchedule
                == .scheduled(capture.date)
        )
        #expect(throws: (any Error).self) {
            try CompanionSlimWindow(kind: .weekly, percentRemaining: 50, resetKind: .scheduled)
        }
        #expect(throws: (any Error).self) {
            try CompanionSlimWindow(
                kind: .weekly, percentRemaining: 50, resetKind: .scheduled, resetDeadline: capture,
                resetReason: .absent)
        }
        #expect(throws: (any Error).self) {
            try CompanionSlimWindow(
                kind: .weekly, percentRemaining: 50, resetKind: .unresolved, resetDeadline: capture,
                resetReason: .absent)
        }
        var contradictory = try object(scheduled)
        contradictory["e"] = "absent"
        #expect(throws: (any Error).self) { try decode(CompanionSlimWindow.self, contradictory) }
        var unknown = try object(scheduled)
        unknown["r"] = "futureReset"
        #expect(
            try decode(CompanionSlimWindow.self, unknown).widgetSummary(accountCapturedAt: capture)?
                .resetSchedule == .unresolved(.legacyUnknown))
        var reason = try object(try window())
        reason["e"] = "futureReason"
        #expect(try decode(CompanionSlimWindow.self, reason).resetReason == .legacyUnknown)
        #expect(
            try CompanionSlimWindow(
                kind: .weekly, percentRemaining: 50, resetKind: .unknown, resetDeadline: capture
            ).resetReason == .legacyUnknown)
    }
    @Test func malformedRequiredWindowFieldsAndNonfiniteConstructorInputsReject() throws {
        let valid = try object(try window())
        for key in ["k", "p", "r", "e"] {
            var json = valid
            json.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(CompanionSlimWindow.self, json) }
        }
        for (key, wrong) in [("p", "15" as Any), ("u", "84"), ("k", 123), ("o", "900"), ("s", 1)] {
            var json = valid
            json[key] = wrong
            #expect(throws: (any Error).self) { try decode(CompanionSlimWindow.self, json) }
        }
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) { try window(remaining: value) }
            #expect(throws: (any Error).self) { try window(utilization: value) }
            #expect(throws: (any Error).self) {
                try window(kind: .billingPeriod, name: "Period", duration: value)
            }
        }
    }
    @Test func accountCompactJSONCapturesOnceAndRetainsZeroVersusNilBanked() throws {
        let account = try CompanionAccountSummary(
            id: "primary", title: "", capturedAt: capture, bankedResets: 0, windows: [window()])
        try roundtrip(account)
        let json = try object(account)
        #expect(Set(json.keys) == Set(["i", "t", "c", "b", "w"]))
        #expect(account.displayTitle == "Account")
        #expect(account.widgetWindows.first?.observedAt == capture.date)
        let without = try CompanionAccountSummary(
            id: "primary", title: "Main", capturedAt: capture, windows: [])
        #expect(try object(without)["b"] == nil)
        let pending = try CompanionAccountSummary(
            id: "extra", title: "Extra", freshness: .pending, windows: [])
        #expect(pending.capturedAt == nil && pending.widgetFreshness == .pending)
        #expect((try object(pending)["w"] as? [Any])?.isEmpty == true)
    }
    @Test func staleAccountRequiresExplicitPermanenceEvenFalseAndNoFabricatedCapture() throws {
        let stale = try CompanionAccountSummary(
            id: "primary", title: "Main", freshness: .stale, attention: .finishingSignIn,
            needsAttention: false, windows: [])
        try roundtrip(stale)
        #expect(try object(stale)["h"] as? Bool == false)
        #expect(
            stale.widgetFreshness
                == .stale(message: "Finishing sign-in on your Mac", needsAttention: false))
        #expect(stale.capturedAt == nil)
        #expect(throws: (any Error).self) {
            try CompanionAccountSummary(
                id: "primary", title: "Main", freshness: .stale, windows: [])
        }
        #expect(throws: (any Error).self) {
            try CompanionAccountSummary(id: "primary", title: "Main", windows: [])
        }
        #expect(throws: (any Error).self) {
            try CompanionAccountSummary(
                id: "primary", title: "Main", freshness: .stale, needsAttention: true,
                windows: [window()])
        }
        var missing = try object(stale)
        missing.removeValue(forKey: "h")
        #expect(throws: (any Error).self) { try decode(CompanionAccountSummary.self, missing) }
        var wrong = try object(stale)
        wrong["h"] = "false"
        #expect(throws: (any Error).self) { try decode(CompanionAccountSummary.self, wrong) }
    }
    @Test func unknownAccountFreshnessHidesWindowsAndUsesGenericNonpermanentCopy() throws {
        let account = try CompanionAccountSummary(
            id: "primary", title: "Main", capturedAt: capture, windows: [window()])
        var json = try object(account)
        json["f"] = "futureFreshness"
        json.removeValue(forKey: "c")
        let unknown = try decode(CompanionAccountSummary.self, json)
        #expect(unknown.widgetWindows.isEmpty)
        #expect(
            unknown.widgetFreshness
                == .stale(message: CompanionAttentionCopy.generic, needsAttention: false))
        #expect(unknown.capturedAt == nil)
        #expect(
            try CompanionAccountSummary(
                id: "primary", title: "Main", freshness: .unknown, windows: [window()]
            ).widgetWindows.isEmpty)
        json["f"] = 123
        #expect(throws: (any Error).self) { try decode(CompanionAccountSummary.self, json) }
    }
    @Test func requiredAccountIdentityWindowsAndBankedValidationAgreeWithDecoder() throws {
        let valid = try object(
            try CompanionAccountSummary(
                id: "primary", title: "Main", capturedAt: capture, windows: []))
        for key in ["i", "t", "w", "c"] {
            var json = valid
            json.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(CompanionAccountSummary.self, json) }
        }
        for (key, wrong) in [("i", "" as Any), ("b", -1), ("w", "windows"), ("c", "1000")] {
            var json = valid
            json[key] = wrong
            #expect(throws: (any Error).self) { try decode(CompanionAccountSummary.self, json) }
        }
        #expect(throws: (any Error).self) {
            try CompanionAccountSummary(id: "", title: "Main", capturedAt: capture, windows: [])
        }
        #expect(throws: (any Error).self) {
            try CompanionAccountSummary(
                id: "primary", title: "Main", capturedAt: capture, bankedResets: -1, windows: [])
        }
    }
    @Test func standaloneLiveLiftRequiresLegitimateObservation() throws {
        #expect(try window().widgetSummary(accountCapturedAt: nil) == nil)
        #expect(
            try window(observation: original).widgetSummary(accountCapturedAt: nil)?.observedAt
                == original.date)
        let unknown = try CompanionAccountSummary(
            id: "primary", title: "Main", freshness: .unknown,
            needsAttention: true, windows: [])
        #expect(unknown.needsAttention == nil)
        try roundtrip(unknown)
    }
    @Test func spendPreservesSignedAmountsIdentityAndOptionalCurrency() throws {
        for kind in [CompanionSpendKind.periodSpend, .balance] {
            let value = try CompanionSpendSummary(
                id: "api-provider", displayName: "Provider", amount: -0.125,
                kind: kind, capturedAt: capture)
            try roundtrip(value)
            let json = try object(value)
            #expect(Set(json.keys) == Set(["i", "n", "a", "p", "k", "t"]))
            #expect(value.widgetSummary.amount == -0.125)
            #expect(value.widgetSummary.currency == nil)
            #expect(value.widgetSummary.capturedAt == capture.date)
            #expect(value.widgetSummary.id == "api-provider")
            #expect(value.widgetSummary.kind == (kind == .balance ? .balance : .periodSpend))
        }
        let pending = try CompanionSpendSummary(
            id: "api-provider", displayName: "Provider", freshness: .pending)
        #expect(pending.widgetSummary.amount == nil && pending.widgetSummary.capturedAt == nil)
        #expect(pending.widgetSummary.freshness == .pending)
        var legacy = try object(pending)
        legacy.removeValue(forKey: "k")
        legacy.removeValue(forKey: "p")
        #expect(try decode(CompanionSpendSummary.self, legacy).kind == .periodSpend)
        #expect(try decode(CompanionSpendSummary.self, legacy).periodLabel == "Period")
    }
    @Test func spendStaleCopyAndSourcePermanenceAreIndependent() throws {
        for attention in CompanionSpendAttention.allCases {
            let stale = try CompanionSpendSummary(
                id: "api-provider", displayName: "Provider", amount: 4.25,
                capturedAt: original, freshness: .stale,
                attention: attention, needsAttention: false)
            try roundtrip(stale)
            #expect(try object(stale)["h"] as? Bool == false)
            #expect(
                stale.widgetSummary.freshness
                    == .stale(
                        message: CompanionAttentionCopy.spend(attention), needsAttention: false))
            #expect(stale.widgetSummary.attention == attention.apiSpendAttention)
            #expect(stale.widgetSummary.capturedAt == original.date)
        }
        let empty = try CompanionSpendSummary(
            id: "api-provider", displayName: "Provider", freshness: .stale, needsAttention: true)
        #expect(
            empty.widgetSummary.freshness
                == .stale(message: CompanionAttentionCopy.generic, needsAttention: true))
        #expect(empty.widgetSummary.capturedAt == nil)
        #expect(throws: (any Error).self) {
            try CompanionSpendSummary(
                id: "api-provider", displayName: "Provider", freshness: .stale)
        }
        #expect(throws: (any Error).self) {
            try CompanionSpendSummary(id: "api-provider", displayName: "Provider", amount: 1)
        }
        #expect(throws: (any Error).self) {
            try CompanionSpendSummary(
                id: "api-provider", displayName: "Provider", amount: 1, freshness: .stale,
                needsAttention: false)
        }
    }
    @Test func spendUnknownStringsHideClaimsButWrongPrimitivesReject() throws {
        let value = try CompanionSpendSummary(
            id: "api-provider", displayName: "Provider", amount: 42, capturedAt: capture)
        var unknownKind = try object(value)
        unknownKind["k"] = "futureAmount"
        let kind = try decode(CompanionSpendSummary.self, unknownKind)
        #expect(kind.widgetSummary.kind == nil && kind.widgetSummary.amount == nil)
        #expect(
            try CompanionSpendSummary(
                id: "api-provider", displayName: "Provider", amount: 42, kind: .unknown
            ).widgetSummary.amount == nil)
        var unknownFreshness = try object(value)
        unknownFreshness["f"] = "futureFreshness"
        unknownFreshness.removeValue(forKey: "t")
        unknownFreshness["h"] = true
        let fresh = try decode(CompanionSpendSummary.self, unknownFreshness)
        #expect(fresh.widgetSummary.amount == nil && fresh.widgetSummary.capturedAt == nil)
        #expect(fresh.needsAttention == nil)
        #expect(
            fresh.widgetSummary.freshness
                == .stale(message: CompanionAttentionCopy.generic, needsAttention: false))
        try roundtrip(fresh)
        var unknownAttention = try object(value)
        unknownAttention["f"] = "stale"
        unknownAttention["h"] = false
        unknownAttention["e"] = "futureAttention"
        #expect(
            try decode(CompanionSpendSummary.self, unknownAttention).widgetSummary.attention == nil)
        for (key, wrong) in [
            ("k", 1 as Any), ("f", false), ("e", 1), ("a", "42"), ("h", "false"), ("t", "1000"),
            ("c", 1),
            ("p", false),
        ] {
            var json = try object(value)
            json[key] = wrong
            #expect(throws: (any Error).self) { try decode(CompanionSpendSummary.self, json) }
        }
    }
    @Test func spendConstructorAndDecoderRejectMalformedRequiredAndNonfiniteValues() throws {
        let value = try CompanionSpendSummary(
            id: "api-provider", displayName: "Provider", amount: 1, capturedAt: capture)
        for key in ["i", "n", "t"] {
            var json = try object(value)
            json.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(CompanionSpendSummary.self, json) }
        }
        #expect(throws: (any Error).self) {
            try CompanionSpendSummary(id: "", displayName: "Provider")
        }
        for number in [Double.nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) {
                try CompanionSpendSummary(
                    id: "api-provider", displayName: "Provider", amount: number, capturedAt: capture
                )
            }
        }
        var stale = try object(value)
        stale["f"] = "stale"
        #expect(throws: (any Error).self) { try decode(CompanionSpendSummary.self, stale) }
    }
    @Test func displayUsesExistingParsersAndPreservesStoredFullTubeChoice() throws {
        let defaults = try decode(CompanionDisplayBlock.self, [:])
        #expect(defaults.meterStyle == .default && defaults.percentageMode == .remaining)
        #expect(defaults.accountTitleInk == .neutral && !defaults.appSparkEnabled)
        let fallback = try decode(
            CompanionDisplayBlock.self, ["m": "futureStyle", "p": "futureMode", "i": "futureInk"])
        #expect(fallback == defaults)
        let full = try decode(
            CompanionDisplayBlock.self,
            ["m": "full.tube.ghost", "p": "used", "i": "brand", "s": true])
        #expect(full.meterStyle.shape == .tube && full.meterStyle.resolvedShape == .chip)
        #expect(
            full.percentageMode == .used && full.accountTitleInk == .brand && full.appSparkEnabled)
        try roundtrip(full)
        #expect(try object(full)["m"] as? String == "full.tube.ghost")
        #expect(try object(defaults)["s"] == nil)
        for key in ["m", "p", "i", "s"] {
            #expect(throws: (any Error).self) { try decode(CompanionDisplayBlock.self, [key: 1]) }
        }
    }
    @Test func reminderBoundsAndLossySummaryNeverSubstituteRules() throws {
        for (unit, maxAmount) in [(CompanionReminderUnit.hours, 48), (.days, 30)] {
            for amount in [1, maxAmount] {
                for threshold in [1, 100] {
                    try roundtrip(
                        try CompanionReminderRuleSummary(
                            amount: amount, unit: unit, threshold: threshold))
                }
            }
            for amount in [0, maxAmount + 1] {
                #expect(throws: (any Error).self) {
                    try CompanionReminderRuleSummary(amount: amount, unit: unit, threshold: 50)
                }
                #expect(throws: (any Error).self) {
                    try decode(
                        CompanionReminderRuleSummary.self,
                        ["a": amount, "u": unit.rawValue, "t": 50])
                }
            }
        }
        for threshold in [0, 101] {
            #expect(throws: (any Error).self) {
                try CompanionReminderRuleSummary(amount: 1, unit: .hours, threshold: threshold)
            }
        }
        let summary = try decode(
            CompanionReminderSummary.self,
            [
                "m": true, "b": true, "p": true,
                "r": [
                    ["a": 2, "u": "hours", "t": 60], ["a": 31, "u": "days", "t": 70],
                    ["a": 2, "u": "future", "t": 50], ["a": "2", "u": "hours", "t": 50],
                ],
                "s": ["weekly", "future", "billingPeriod", "fiveHour"],
            ])
        #expect(
            summary.macUseItUpEnabled && summary.macBankedResetEnabled
                && summary.phoneChannelEnabled)
        #expect(
            summary.rules == [
                try CompanionReminderRuleSummary(amount: 2, unit: .hours, threshold: 60)
            ])
        #expect(summary.scope == [.weekly, .billingPeriod, .fiveHour])
        try roundtrip(summary)
        #expect(Set(try object(summary).keys) == Set(["m", "b", "p", "r", "s"]))
        let defaults = try decode(CompanionReminderSummary.self, [:])
        #expect(
            !defaults.macUseItUpEnabled && !defaults.macBankedResetEnabled
                && !defaults.phoneChannelEnabled)
        #expect(defaults.rules.isEmpty && defaults.scope.isEmpty)
        for key in ["m", "b", "p", "r", "s"] {
            #expect(throws: (any Error).self) {
                try decode(CompanionReminderSummary.self, [key: "wrong"])
            }
        }
        #expect(throws: (any Error).self) { try decode(CompanionReminderSummary.self, ["s": [1]]) }
    }
    @Test func everyResetReasonAndHiddenUnavailableFieldSurvivesCanonicalRoundtrip() throws {
        for reason in ResetUnresolvedReason.allCases {
            let value = try CompanionSlimWindow(
                kind: .weekly, percentRemaining: 0, utilization: nil,
                resetKind: .unresolved, resetReason: reason,
                freshness: .unavailable, observedAtOverride: original,
                unavailableSince: capture, isSpark: true)
            try roundtrip(value)
            let projected = try #require(value.widgetSummary(accountCapturedAt: nil))
            #expect(projected.resetSchedule == .unresolved(reason))
            #expect(projected.percentRemaining == 0 && projected.severity == .critical)
            #expect(projected.utilization == nil && projected.displayPercentRemaining == nil)
            #expect(projected.observedAt == original.date)
            #expect(projected.resetLabel == nil && projected.resetTimeZoneIdentifier == nil)
            #expect(try object(value)["s"] as? Bool == true)
        }
    }
    @Test func leafNormalizationIsIdempotentAndSeverityUsesNormalizedRemaining() throws {
        for (input, expected, severity) in [
            (15.04, 15.0, WidgetUsageSeverity.critical),
            (15.05, 15.1, .low), (50.04, 50.0, .low),
            (50.05, 50.1, .healthy), (-1, 0, .critical), (101, 100, .healthy),
        ] {
            let value = try window(remaining: input, utilization: nil)
            #expect(value.percentRemaining == expected)
            #expect(value.widgetSummary(accountCapturedAt: capture)?.severity == severity)
            try roundtrip(value)
        }
    }
    @Test func unknownAttentionUsesCanonicalCopyAndMalformedOptionalFieldsStayCorrupt() throws {
        let account = try CompanionAccountSummary(
            id: "primary", title: "Custom", freshness: .stale,
            attention: .unknown, needsAttention: true, windows: [])
        #expect(
            account.widgetFreshness
                == .stale(message: CompanionAttentionCopy.generic, needsAttention: true))
        var unknown = try object(account)
        unknown["a"] = "futureAttention"
        #expect(try decode(CompanionAccountSummary.self, unknown).attention == .unknown)
        for (key, wrong) in [
            ("a", 1 as Any), ("p", ["object": true]), ("b", 0.5), ("t", false), ("w", NSNull()),
        ] {
            var json = try object(account)
            json[key] = wrong
            #expect(throws: (any Error).self) { try decode(CompanionAccountSummary.self, json) }
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for marker in ["Infinity", "-Infinity", "NaN"] {
            var json = try object(try window())
            json["u"] = marker
            let bytes = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: (any Error).self) {
                try decoder.decode(CompanionSlimWindow.self, from: bytes)
            }
            var spend = try object(
                try CompanionSpendSummary(
                    id: "api-provider", displayName: "Provider", capturedAt: capture))
            spend["a"] = marker
            let spendBytes = try JSONSerialization.data(withJSONObject: spend)
            #expect(throws: (any Error).self) {
                try decoder.decode(CompanionSpendSummary.self, from: spendBytes)
            }
        }
    }

    @Test func unknownSpendAttentionProjectsGenericCopyWithoutChangingSourceFields() throws {
        for freshness in [CompanionContentFreshness.live, .pending, .stale] {
            for permanence in freshness == .stale ? [false, true] : [false] {
                let value = try CompanionSpendSummary(
                    id: "api-provider", displayName: "Provider",
                    amount: freshness == .pending ? nil : -2.5,
                    capturedAt: freshness == .pending ? nil : original, freshness: freshness,
                    attention: .unknown,
                    needsAttention: freshness == .stale ? permanence : nil)
                #expect(
                    value.widgetSummary.freshness
                        == .stale(
                            message: CompanionAttentionCopy.generic, needsAttention: permanence))
                #expect(value.widgetSummary.attention == nil)
                #expect(
                    value.widgetSummary.amount == value.amount
                        && value.widgetSummary.capturedAt == value.capturedAt?.date)
                #expect(value.freshness == freshness && value.attention == .unknown)
                var json = try object(value)
                json["e"] = "futureAttention"
                #expect(
                    try decode(CompanionSpendSummary.self, json).widgetSummary
                        == value.widgetSummary)
                try roundtrip(value)
            }
        }
    }

    @Test func pendingContentRejectsCaptureAndRetainedValuesThroughBothEntryPoints() throws {
        let account = try CompanionAccountSummary(
            id: "extra", title: "Extra", freshness: .pending, windows: [])
        let spend = try CompanionSpendSummary(
            id: "api-provider", displayName: "Provider", freshness: .pending)
        try roundtrip(account)
        try roundtrip(spend)
        #expect(throws: CompanionLeafValidationError.capture) {
            try CompanionAccountSummary(
                id: "extra", title: "Extra", freshness: .pending,
                capturedAt: capture, windows: [])
        }
        #expect(throws: CompanionLeafValidationError.capture) {
            try CompanionAccountSummary(
                id: "extra", title: "Extra", freshness: .pending,
                capturedAt: capture, windows: [window()])
        }
        #expect(throws: CompanionLeafValidationError.capture) {
            try CompanionAccountSummary(
                id: "extra", title: "Extra", freshness: .pending,
                windows: [window(observation: original)])
        }
        for (key, value) in [
            ("c", 1000 as Any), ("w", [try object(try window(observation: original))]),
        ] {
            var json = try object(account)
            json[key] = value
            #expect(throws: CompanionLeafValidationError.capture) {
                try decode(CompanionAccountSummary.self, json)
            }
        }
        for kind in [CompanionSpendKind.periodSpend, .balance, .unknown] {
            #expect(throws: CompanionLeafValidationError.capture) {
                try CompanionSpendSummary(
                    id: "api-provider", displayName: "Provider", amount: 0,
                    kind: kind, freshness: .pending)
            }
            #expect(throws: CompanionLeafValidationError.capture) {
                try CompanionSpendSummary(
                    id: "api-provider", displayName: "Provider", kind: kind,
                    capturedAt: capture, freshness: .pending)
            }
        }
        for (key, value) in [("a", 0), ("t", 1000)] {
            var json = try object(spend)
            json[key] = value
            #expect(throws: CompanionLeafValidationError.capture) {
                try decode(CompanionSpendSummary.self, json)
            }
        }
    }

    private func expectNullRejected<T: Decodable>(
        _ type: T.Type, object: [String: Any], keys: [String]
    ) throws {
        for key in keys {
            var json = object
            json[key] = NSNull()
            #expect(throws: (any Error).self) { try decode(type, json) }
        }
    }

    @Test func explicitNullNeverDefaultsWindowAccountOrSpendNonnullableFields() throws {
        let row = try object(try window())
        try expectNullRejected(CompanionSlimWindow.self, object: row, keys: ["f", "s"])
        let account = try object(
            try CompanionAccountSummary(
                id: "primary", title: "Main", capturedAt: capture, windows: []))
        try expectNullRejected(CompanionAccountSummary.self, object: account, keys: ["f"])
        let spend = try object(
            try CompanionSpendSummary(
                id: "api-provider", displayName: "Provider", amount: -1, capturedAt: capture))
        try expectNullRejected(CompanionSpendSummary.self, object: spend, keys: ["f", "k", "p"])
        #expect(try decode(CompanionSlimWindow.self, row).freshness == .live)
        #expect(try decode(CompanionAccountSummary.self, account).freshness == .live)
        #expect(try decode(CompanionSpendSummary.self, spend).freshness == .live)
    }

    @Test func explicitNullNeverDefaultsDisplayOrReminderNonnullableFields() throws {
        try expectNullRejected(CompanionDisplayBlock.self, object: [:], keys: ["m", "p", "i", "s"])
        try expectNullRejected(
            CompanionReminderSummary.self, object: [:], keys: ["m", "b", "p", "r", "s"])
        #expect(try decode(CompanionDisplayBlock.self, [:]) == CompanionDisplayBlock())
        #expect(try decode(CompanionReminderSummary.self, [:]) == CompanionReminderSummary())
    }

    @Test func trulyOptionalNullValuesRemainNilAndKeepValidFallbacks() throws {
        var row = try object(try window(utilization: nil))
        for key in ["n", "d", "u", "t", "o", "z"] { row[key] = NSNull() }
        #expect(try decode(CompanionSlimWindow.self, row) == window(utilization: nil))
        var account = try object(
            try CompanionAccountSummary(
                id: "extra", title: "Extra", freshness: .pending, windows: []))
        for key in ["p", "c", "a", "h", "b"] { account[key] = NSNull() }
        let decodedAccount = try decode(CompanionAccountSummary.self, account)
        #expect(
            decodedAccount.capturedAt == nil && decodedAccount.planName == nil
                && decodedAccount.attention == nil)
        var spend = try object(
            try CompanionSpendSummary(
                id: "api-provider", displayName: "Provider", freshness: .pending))
        for key in ["a", "c", "t", "e", "h"] { spend[key] = NSNull() }
        #expect(try decode(CompanionSpendSummary.self, spend).amount == nil)
        let future = try decode(
            CompanionDisplayBlock.self, ["m": "future", "p": "future", "i": "future"])
        #expect(future == CompanionDisplayBlock())
    }

}
