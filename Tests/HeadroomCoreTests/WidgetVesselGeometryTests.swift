import Foundation
import Testing
@testable import HeadroomCore

struct WidgetVesselGeometryTests {
    typealias F = StyleFixture

    @Test func keepsTheMenuBarVesselProportion() {
        #expect(abs(WidgetVesselGeometry.aspect - 11.0 / 18.0) < 0.0001)
        let g = WidgetVesselGeometry(height: 26)
        #expect(abs(g.width - 16) <= 0.5)
    }

    @Test func heroStrokeIsClampedBetweenOneAndAHalfAndTwoPointOne() {
        #expect(WidgetVesselGeometry(width: 13.5, height: 22).stroke >= 1.5)
        #expect(WidgetVesselGeometry(width: 13.5, height: 22).stroke <= 2.1)
        #expect(WidgetVesselGeometry(width: 40, height: 66).stroke == 2.1)
    }

    @Test func insetIsStrokePlusAClearance() {
        let g = WidgetVesselGeometry(width: 16, height: 26)
        #expect(abs(g.inset - (g.stroke + max(0.6, 16 * 0.055))) < 0.0001)
        #expect(abs(g.innerWidth - (16 - 2 * g.inset)) < 0.0001)
    }

    @Test func liquidHasNoHeightWithoutAValueOrAtZero() {
        let g = WidgetVesselGeometry(height: 30)
        #expect(g.liquidHeight(fraction: nil) == 0)
        #expect(g.liquidHeight(fraction: 0) == 0)
    }

    @Test func liquidHeightFollowsTheInnerHeightWithAFloor() {
        let g = WidgetVesselGeometry(height: 30)
        #expect(abs(g.liquidHeight(fraction: 1) - g.innerHeight) < 0.0001)
        #expect(abs(g.liquidHeight(fraction: 0.01) - g.innerWidth * 0.5) < 0.0001)
    }

    @Test func wallTurnsCriticalOnlyForALiveCriticalWindow() {
        #expect(WidgetVesselGeometry.wallIsCritical(F.window(.weekly, label: "Weekly", percent: 9)))
        #expect(WidgetVesselGeometry.wallIsCritical(F.window(.weekly, label: "Weekly", percent: 9, freshness: .stale(observedAt: F.now))) == false)
        #expect(WidgetVesselGeometry.wallIsCritical(F.window(.weekly, label: "Weekly", percent: 40)) == false)
        #expect(WidgetVesselGeometry.wallIsCritical(nil) == false)
    }
}

struct WidgetStyleColorTests {
    typealias F = StyleFixture

    private func fill(_ window: WidgetWindowSummary, _ mode: WidgetColorMode, dark: Bool = true) -> HeadroomTint? {
        WidgetStyleColors.fill(for: window, colorMode: mode, dark: dark, increasedContrast: false)
    }

    @Test func liveHealthyIsGreenWhenAlwaysColoredAndNeutralWhenOnlyLow() {
        let healthy = F.window(.weekly, label: "Weekly", percent: 80)
        #expect(fill(healthy, .solid)?.color == HeadroomSeverityColorValues.healthyFill(dark: true, increasedContrast: false))
        #expect(fill(healthy, .event) == HeadroomWidgetColorValues.neutralFill(dark: true))
    }

    @Test func staleHealthyDiffersBetweenTheTwoModes() {
        let stale = F.window(.weekly, label: "Weekly", percent: 80, freshness: .stale(observedAt: F.now))
        let solid = fill(stale, .solid)
        let event = fill(stale, .event)
        #expect(solid?.color == HeadroomMeterColorValues.staleFill(for: UsageSeverity.healthy, dark: true, increasedContrast: false))
        #expect(event?.color == HeadroomWidgetColorValues.staleNeutralFill(dark: true))
        #expect(solid != event)
    }

    @Test func lowAndCriticalAreTheSameInBothModes() {
        for percent in [40.0, 9.0] {
            let w = F.window(.weekly, label: "Weekly", percent: percent)
            #expect(fill(w, .solid) == fill(w, .event))
            let stale = F.window(.weekly, label: "Weekly", percent: percent, freshness: .stale(observedAt: F.now))
            #expect(fill(stale, .solid) == fill(stale, .event))
        }
    }

    /// KTD5: each severity maps to its own token, with `dark` and `increasedContrast` passed
    /// through — comparing the two modes alone would miss a swapped low/critical fill.
    @Test func lowAndCriticalTakeTheirOwnSeverityTokens() {
        let low = F.window(.weekly, label: "Weekly", percent: 40)
        let critical = F.window(.weekly, label: "Weekly", percent: 9)
        let staleLow = F.window(.weekly, label: "Weekly", percent: 40, freshness: .stale(observedAt: F.now))
        let staleCritical = F.window(.weekly, label: "Weekly", percent: 9, freshness: .stale(observedAt: F.now))
        #expect(low.severity == .low)
        #expect(critical.severity == .critical)
        for dark in [true, false] {
            for increasedContrast in [true, false] {
                let label = "dark \(dark), increased contrast \(increasedContrast)"
                func fill(_ window: WidgetWindowSummary) -> HeadroomTint? {
                    WidgetStyleColors.fill(for: window, colorMode: .solid, dark: dark, increasedContrast: increasedContrast)
                }
                let opaque = { (color: HeadroomRGBColor) in HeadroomTint(color: color, opacity: 1) }
                #expect(fill(low) == opaque(HeadroomSeverityColorValues.lowFill(dark: dark, increasedContrast: increasedContrast)), "\(label)")
                #expect(fill(critical) == opaque(HeadroomSeverityColorValues.criticalFill(dark: dark, increasedContrast: increasedContrast)), "\(label)")
                #expect(fill(low) != fill(critical), "\(label)")
                #expect(fill(staleLow) == opaque(HeadroomMeterColorValues.staleFill(for: UsageSeverity.low, dark: dark, increasedContrast: increasedContrast)), "\(label)")
                #expect(fill(staleCritical) == opaque(HeadroomMeterColorValues.staleFill(for: UsageSeverity.critical, dark: dark, increasedContrast: increasedContrast)), "\(label)")
                #expect(fill(staleLow) != fill(staleCritical), "\(label)")
            }
        }
    }

    @Test func unavailableHasNoFill() {
        let w = F.window(.weekly, label: "Weekly", percent: 40, freshness: .unavailable(since: F.now))
        #expect(fill(w, .solid) == nil)
    }
}
