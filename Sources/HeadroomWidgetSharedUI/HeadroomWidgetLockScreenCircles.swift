#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// R2: one circle design per style — Nested Badge (11A), Vessel Badge (01), Tightest Gauge
/// (03) and Liquid Dial (04). Sizes are the approved 72 pt reference values (R3); every
/// element is fixed-size and centred, so the 68 and 76 pt circles only move the margin.
struct HeadroomWidgetLockScreenCircle: View {
    let recipe: LockScreenWidgetRecipe
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        ZStack {
            if let status = recipe.status {
                art.accessoryBackground()
                HeadroomWidgetLockScreenStatusCircle(status: status)
            } else if let slot = recipe.slots.first {
                switch recipe.style {
                case .nestedMeter: HeadroomWidgetLockScreenNestedBadge(slot: slot, isDemo: recipe.isDemo, art: art)
                case .vesselHero: HeadroomWidgetLockScreenVesselBadge(slot: slot, art: art)
                case .tightestFirst: HeadroomWidgetLockScreenTightestGauge(slot: slot, art: art)
                case .liquidLevel: HeadroomWidgetLockScreenLiquidDial(slot: slot, art: art)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The system clips the accessory circle; clipping here keeps the harness honest.
        .clipShape(Circle())
    }
}

/// 11A: mark, number and the nested bars. The design has no caption line; a slot with no
/// reading (R7/R8 off, waiting, sign in) or demo data (R10) prints its word under the bars
/// with tighter gaps, because the bars alone cannot say it.
struct HeadroomWidgetLockScreenNestedBadge: View {
    let slot: LockScreenProviderSlot
    let isDemo: Bool
    let art: HeadroomWidgetLockScreenArt

    private var showsCaption: Bool {
        isDemo || [.off, .pending, .signIn].contains(slot.primary.state)
    }

    var body: some View {
        ZStack {
            art.accessoryBackground()
            VStack(spacing: 0) {
                HeadroomWidgetLockScreenSlotMark(slot: slot, size: LockScreenWidgetTokens.badgeMark, art: art)
                Spacer().frame(height: showsCaption ? 1 : 3)
                HeadroomWidgetLockScreenNumeral(slot.primary, size: LockScreenWidgetTokens.nestedNumeral)
                Spacer().frame(height: showsCaption ? 3 : 6)
                HeadroomWidgetLockScreenNestedBars(slot)
                if showsCaption {
                    HeadroomWidgetLockScreenCaption(slot.primary, compact: true, size: 8.5)
                        .padding(.top, 2)
                }
            }
        }
    }
}

/// 01: mark, the vessel hero on the numeral's baseline, caption.
struct HeadroomWidgetLockScreenVesselBadge: View {
    let slot: LockScreenProviderSlot
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        ZStack {
            art.accessoryBackground()
            VStack(spacing: 0) {
                HeadroomWidgetLockScreenSlotMark(slot: slot, size: LockScreenWidgetTokens.badgeMark, art: art)
                Spacer().frame(height: 4)
                HeadroomWidgetLockScreenHero(recipe: slot.primary, numeralSize: LockScreenWidgetTokens.vesselNumeral)
                Spacer().frame(height: 3)
                HeadroomWidgetLockScreenCaption(slot.primary, compact: true)
                    .frame(maxWidth: 52)
            }
        }
    }
}

/// 03: open arc with the caption above the number and the mark in the arc's gap (R3).
/// Gauge Pair (12A) reuses this view twice.
struct HeadroomWidgetLockScreenTightestGauge: View {
    let slot: LockScreenProviderSlot
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        ZStack {
            art.accessoryBackground()
            HeadroomWidgetLockScreenArc(slot.primary)
            VStack(spacing: 2) {
                HeadroomWidgetLockScreenCaption(slot.primary, compact: true)
                    .frame(maxWidth: 40)
                HeadroomWidgetLockScreenNumeral(slot.primary, size: LockScreenWidgetTokens.tightestNumeral)
            }
            .padding(.bottom, 3)
            HeadroomWidgetLockScreenSlotMark(slot: slot, size: LockScreenWidgetTokens.tightestMark, art: art)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 04: the liquid wash fills the dial to the reading; no bright surface line (R3).
struct HeadroomWidgetLockScreenLiquidDial: View {
    let slot: LockScreenProviderSlot
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        ZStack {
            art.accessoryBackground()
            HeadroomWidgetLockScreenWash(slot.primary)
            VStack(spacing: 0) {
                HeadroomWidgetLockScreenSlotMark(slot: slot, size: LockScreenWidgetTokens.liquidMark, art: art)
                Spacer().frame(height: 4)
                HeadroomWidgetLockScreenNumeral(slot.primary, size: LockScreenWidgetTokens.liquidNumeral)
                Spacer().frame(height: 3)
                HeadroomWidgetLockScreenCaption(slot.primary, compact: true)
                    .frame(maxWidth: 54)
            }
        }
        .clipShape(Circle())
    }
}

/// R9: the status vessel mark and one word. The mark's level is the status's own fill,
/// never a reading.
struct HeadroomWidgetLockScreenStatusCircle: View {
    let status: LockScreenWidgetStatusForm

    var body: some View {
        VStack(spacing: 4) {
            HeadroomWidgetLockScreenVessel(fraction: status.vesselFill, state: .live,
                                           geometry: WidgetVesselGeometry(height: 22))
            HeadroomWidgetLockScreenLabel(text: status.circleWord, size: LockScreenWidgetTokens.captionSize, weight: .semibold)
                .frame(maxWidth: 60)
        }
    }
}
