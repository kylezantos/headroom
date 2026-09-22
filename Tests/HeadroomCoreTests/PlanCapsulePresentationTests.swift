import Foundation
import Testing
@testable import HeadroomCore

struct PlanCapsulePresentationTests {
    @Test func beadAtRestAndOpenCopyOnHover() {
        let rest = PlanCapsulePresentation.resolve(
            planDisplayName: "Plus", bankedResets: 2, isHovering: false, isCritical: false, isRevealing: false
        )
        #expect(rest.state == .bead)
        #expect(rest.visibleLabel == "Plus")
        #expect(rest.showsBead)

        let hovered = PlanCapsulePresentation.resolve(
            planDisplayName: "Plus", bankedResets: 2, isHovering: true, isCritical: false, isRevealing: false
        )
        #expect(hovered.state == .open)
        #expect(hovered.visibleLabel == "Plus · 2 resets")
        #expect(hovered.motionCause == .hover)

        let one = PlanCapsulePresentation.resolve(
            planDisplayName: "Plus", bankedResets: 1, isHovering: true, isCritical: false, isRevealing: false
        )
        #expect(one.visibleLabel == "Plus · 1 reset")
    }

    @Test func missingPlanShowsTheBeadAloneAndTheCountWhenOpen() {
        let rest = PlanCapsulePresentation.resolve(
            planDisplayName: nil, bankedResets: 2, isHovering: false, isCritical: false, isRevealing: false
        )
        #expect(rest.state == .bead)
        #expect(rest.visibleLabel == "")
        let open = PlanCapsulePresentation.resolve(
            planDisplayName: nil, bankedResets: 2, isHovering: true, isCritical: false, isRevealing: false
        )
        #expect(open.visibleLabel == "2 resets")
    }

    @Test func zeroAndNilStayPlain() {
        for count in [Int?.none, 0] {
            let presentation = PlanCapsulePresentation.resolve(
                planDisplayName: "Plus", bankedResets: count, isHovering: true, isCritical: true, isRevealing: true
            )
            #expect(presentation.state == .plain)
            #expect(presentation.visibleLabel == "Plus")
            #expect(presentation.helpLine == nil)
            #expect(presentation.accessibilityPhrase == nil)
        }
    }

    @Test func criticalAndRevealOpenWithoutHover() {
        let critical = PlanCapsulePresentation.resolve(
            planDisplayName: "Plus", bankedResets: 2, isHovering: false, isCritical: true, isRevealing: false
        )
        #expect(critical.state == .open)
        #expect(critical.motionCause == .attention)
        let revealing = PlanCapsulePresentation.resolve(
            planDisplayName: "Plus", bankedResets: 2, isHovering: false, isCritical: false, isRevealing: true
        )
        #expect(revealing.state == .open)
        let both = PlanCapsulePresentation.resolve(
            planDisplayName: "Plus", bankedResets: 2, isHovering: false, isCritical: true, isRevealing: true
        )
        #expect(both.state == .open)
    }

    @Test func criticalGateMatchesOnlyLiveResettableWindows() {
        let critical = snapshot(freshness: .live, windows: [window(.fiveHour, remaining: 12)])
        #expect(critical.hasLiveCriticalResettableWindow)
        #expect(!snapshot(freshness: .live, windows: [window(.fiveHour, remaining: 12, freshness: .stale(observedAt: Date()))]).hasLiveCriticalResettableWindow)
        #expect(!snapshot(freshness: .live, windows: [window(.fiveHour, remaining: 12, freshness: .unavailable(since: Date()))]).hasLiveCriticalResettableWindow)
        #expect(!snapshot(freshness: .live, windows: [window(.fiveHour, remaining: 16)]).hasLiveCriticalResettableWindow)
        #expect(snapshot(freshness: .live, windows: [window(.weekly, remaining: 12)]).hasLiveCriticalResettableWindow)
        let sparkOnly = snapshot(freshness: .live, windows: [
            window(.fiveHour, remaining: 80),
            window(.weekly, remaining: 70),
            window(.other("Spark"), remaining: 10),
        ])
        #expect(!sparkOnly.hasLiveCriticalResettableWindow)
        #expect(!critical.markedStale(.transient("offline")).hasLiveCriticalResettableWindow)
    }

    @Test func helpAndVoiceOverNameTheSpare() {
        #expect(PlanCapsulePresentation.helpLine(count: 2) == "2 banked resets — a full reset refreshes the 5-hour and weekly windows")
        #expect(PlanCapsulePresentation.helpLine(count: 1) == "1 banked reset — a full reset refreshes the 5-hour and weekly windows")
        #expect(PlanCapsulePresentation.helpLine(count: nil) == nil)
        #expect(PlanCapsulePresentation.helpLine(count: 0) == nil)
        #expect(PlanCapsulePresentation.accessibilityPhrase(count: 2) == "2 banked resets available — a full reset refreshes the 5-hour and weekly windows")
        #expect(PlanCapsulePresentation.accessibilityPhrase(count: 1) == "1 banked reset available — a full reset refreshes the 5-hour and weekly windows")
        #expect(PlanCapsulePresentation.accessibilityPhrase(count: nil) == nil)
        #expect(PlanCapsulePresentation.accessibilityPhrase(count: 0) == nil)
    }

    private func window(
        _ kind: WindowKind,
        remaining: Double,
        freshness: UsageWindowFreshness = .live
    ) -> UsageWindow {
        UsageWindow(kind: kind, utilization: 100 - remaining, resetsAt: .distantFuture, freshness: freshness)
    }

    private func snapshot(freshness: Freshness, windows: [UsageWindow]) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .codex,
            windows: windows,
            planLabel: "plus",
            capturedAt: Date(),
            freshness: freshness
        )
    }
}
