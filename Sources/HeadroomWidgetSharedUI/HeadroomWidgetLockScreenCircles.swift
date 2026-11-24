#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// R2: one circle design per style — Nested Badge (11A), Vessel Badge (01), Tightest Gauge
/// (03) and Liquid Dial (04). Keep readable content inside the circular mask, including
/// the smaller content proposals used by the Lock Screen picker.
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

/// 11A: mark, number and the nested bars. The design has no caption line. A slot with no
/// reading (R7/R8 off, waiting, sign in) prints its word in place of the empty bars; demo data
/// (R10) keeps only the parent bar and prints "Demo" under it. iOS draws Lock Screen text about
/// a fifth larger than the macOS harness, so the stack never grows past the approved height.
struct HeadroomWidgetLockScreenNestedBadge: View {
    let slot: LockScreenProviderSlot
    let isDemo: Bool
    let art: HeadroomWidgetLockScreenArt

    private var hasNoReading: Bool { [.off, .pending, .signIn].contains(slot.primary.state) }

    var body: some View {
        ZStack {
            art.accessoryBackground()
            VStack(spacing: 0) {
                HeadroomWidgetLockScreenSlotMark(slot: slot, size: LockScreenWidgetTokens.badgeMark, art: art)
                Spacer().frame(height: 2)
                HeadroomWidgetLockScreenNumeral(slot.primary, size: slot.primary.numberText == "100%" ? 17 : LockScreenWidgetTokens.nestedNumeral)
                if hasNoReading {
                    HeadroomWidgetLockScreenFittingCaption(recipe: slot.primary, size: 8.5)
                        .padding(.top, 3)
                } else if isDemo {
                    Spacer().frame(height: 4)
                    HeadroomWidgetLockScreenNestedBars(LockScreenProviderSlot.parentOnly(slot))
                    HeadroomWidgetLockScreenFittingCaption(recipe: slot.primary, size: 8.5)
                        .padding(.top, 2)
                } else {
                    Spacer().frame(height: 3)
                    HeadroomWidgetLockScreenNestedBars(slot)
                }
            }
            .padding(.vertical, 4)
            .padding(.bottom, 2)
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
                HeadroomWidgetLockScreenHero(recipe: slot.primary, numeralSize: slot.primary.numberText == "100%" ? 14 : LockScreenWidgetTokens.vesselNumeral)
                HeadroomWidgetLockScreenFittingCaption(recipe: slot.primary)
                    .frame(maxWidth: 38)
            }
            .padding(.bottom, 4)
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
                HeadroomWidgetLockScreenFittingCaption(recipe: slot.primary, size: 8.5)
                    .frame(maxWidth: 36)
                HeadroomWidgetLockScreenNumeral(slot.primary, size: LockScreenWidgetTokens.tightestNumeral)
            }
            // R3: the mark sits in the arc's gap and clears the number at iOS text metrics,
            // which run about a fifth larger than the macOS harness.
            .padding(.bottom, 9)
            HeadroomWidgetLockScreenSlotMark(slot: slot, size: LockScreenWidgetTokens.tightestMark, art: art)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 04: the liquid wash fills the dial to the reading; no bright surface line (R3).
struct HeadroomWidgetLockScreenLiquidDial: View {
    let slot: LockScreenProviderSlot
    let art: HeadroomWidgetLockScreenArt

    // Explicit fit steps preserve the caption and the low-reading capsule at narrow chords.
    private var numeralSize: Double {
        if slot.primary.usesKnockout { return 16 }
        return slot.primary.numberText == "100%" ? 17 : LockScreenWidgetTokens.liquidNumeral
    }

    var body: some View {
        ZStack {
            art.accessoryBackground()
            HeadroomWidgetLockScreenWash(slot.primary)
            VStack(spacing: 0) {
                HeadroomWidgetLockScreenSlotMark(slot: slot, size: LockScreenWidgetTokens.liquidMark, art: art)
                HeadroomWidgetLockScreenNumeral(slot.primary, size: numeralSize)
                HeadroomWidgetLockScreenFittingCaption(recipe: slot.primary)
                    .frame(maxWidth: 38)
            }
            // The lower chord narrows faster than the top mark; lift the stack slightly.
            .padding(.bottom, 6)
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
        .padding(.bottom, 4)
    }
}
