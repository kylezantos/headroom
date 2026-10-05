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

    /// U3/KTD6.2: the auto-open decision reads normalized severity. 15.04% remaining (raw
    /// binary 15.040000000000006, Low) now opens because it normalizes to 15.0, as the phone
    /// sees it; the decimal tie at 15.05% normalizes to 15.1 and stays shut.
    @Test(arguments: [(84.96, true), (84.95, false), (85.0, true), (84.0, false), (100.0, true), (50.04, false)])
    func criticalGateUsesTheNormalizedValue(utilization: Double, opens: Bool) {
        for kind in [WindowKind.fiveHour, .weekly] {
            let window = UsageWindow(kind: kind, utilization: utilization, resetsAt: .distantFuture)
            #expect(snapshot(freshness: .live, windows: [window]).hasLiveCriticalResettableWindow == opens)
        }
    }

    /// The freshness and kind gates are the ones the capsule always had, at the boundary too.
    @Test func normalizedCriticalKeepsTheLiveResettableGates() {
        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        let critical = UsageWindow(kind: .fiveHour, utilization: 84.96, resetsAt: .distantFuture)
        #expect(!snapshot(freshness: .live, windows: [critical.withFreshness(.stale(observedAt: observed))]).hasLiveCriticalResettableWindow)
        #expect(!snapshot(freshness: .live, windows: [critical.withFreshness(.unavailable(since: observed))]).hasLiveCriticalResettableWindow)
        #expect(!snapshot(freshness: .stale(.transient("offline")), windows: [critical]).hasLiveCriticalResettableWindow)
        #expect(!snapshot(freshness: .pending, windows: [critical]).hasLiveCriticalResettableWindow)
        let spark = UsageWindow(kind: .other("Spark"), utilization: 84.96, resetsAt: .distantFuture)
        let period = UsageWindow(kind: .billingPeriod(label: "Included", duration: 2_592_000), utilization: 99, resetsAt: .distantFuture)
        #expect(!snapshot(freshness: .live, windows: [spark, period]).hasLiveCriticalResettableWindow)
    }

    /// The phone asks the same question of synced readings.
    @Test func phoneReadingsTakeTheSameDecision() {
        func row(_ remaining: Double, _ freshness: WidgetWindowFreshness = .live) -> UsageMeterReading {
            UsageMeterReading(widgetSummary: WidgetWindowSummary(
                kind: .weekly, label: "Weekly", percentRemaining: remaining,
                resetSchedule: .scheduled(.distantFuture), resetLabel: nil,
                severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: remaining)), freshness: freshness
            ))
        }
        #expect(PlanCapsulePresentation.hasLiveCriticalResettableWindow(snapshotIsLive: true, readings: [row(15.04)]))
        #expect(!PlanCapsulePresentation.hasLiveCriticalResettableWindow(snapshotIsLive: true, readings: [row(15.05)]))
        #expect(!PlanCapsulePresentation.hasLiveCriticalResettableWindow(snapshotIsLive: false, readings: [row(10)]))
        #expect(!PlanCapsulePresentation.hasLiveCriticalResettableWindow(
            snapshotIsLive: true, readings: [row(10, .stale(observedAt: Date(timeIntervalSince1970: 0)))]
        ))
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
