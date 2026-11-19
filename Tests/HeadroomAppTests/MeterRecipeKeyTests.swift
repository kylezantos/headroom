import Testing
import HeadroomCore
@testable import Headroom

/// M5A: the popover's card list and the Appearance specimen crossfade on the same drawn
/// recipe. These pin the two properties that make that swap correct — it fires exactly when
/// the *rendered* meter changes, and never when it doesn't.
@MainActor
@Suite(.sharedAppState)
struct MeterRecipeKeyTests {
    @Test func everyRenderedDifferenceGetsItsOwnKey() {
        let base = MeterStyle(format: .full, shape: .chip, fill: .solid)
        let shape = MeterStyle(format: .full, shape: .segmented, fill: .solid)
        let fill = MeterStyle(format: .full, shape: .chip, fill: .ghost)
        let format = MeterStyle(format: .micro, shape: .chip, fill: .solid)

        #expect(MeterRecipeKey.key(for: base) != MeterRecipeKey.key(for: shape))
        #expect(MeterRecipeKey.key(for: base) != MeterRecipeKey.key(for: fill))
        #expect(MeterRecipeKey.key(for: base) != MeterRecipeKey.key(for: format))
    }

    /// Tube stays *stored* while Full is selected but renders as Chip, so keying on the raw
    /// shape would dissolve a card into an identical copy of itself.
    @Test func aStoredShapeThatFullDoesNotDrawSharesTheChipKey() {
        let tube = MeterStyle(format: .full, shape: .tube, fill: .solid)
        let chip = MeterStyle(format: .full, shape: .chip, fill: .solid)
        #expect(tube.resolvedShape == chip.resolvedShape)
        #expect(MeterRecipeKey.key(for: tube) == MeterRecipeKey.key(for: chip))

        // Micro is where Tube is actually drawn, so there it keys apart from Chip.
        let microTube = MeterStyle(format: .micro, shape: .tube, fill: .solid)
        let microChip = MeterStyle(format: .micro, shape: .chip, fill: .solid)
        #expect(MeterRecipeKey.key(for: microTube) != MeterRecipeKey.key(for: microChip))
    }
}

/// CA-P2: the popover card's dark edge is drawn from `HeadroomTuning`, and DialKit can move
/// it. The shipped defaults have to be Core's rule-8 values (asserted ≤ 0.15 in
/// `BrandColorValuesTests`), and R2C1's bright gradient stroke must not come back by default.
@Suite
struct RaisedTileDarkEdgeTests {
    @Test func theShippedDarkCardEdgeIsCoresRingAndLip() {
        let tuning = HeadroomTuning()
        #expect(tuning.darkRing == HeadroomTileEdgeValues.darkGlassRingOpacity)
        #expect(tuning.darkRimTop == HeadroomTileEdgeValues.darkGlassLipOpacity)
        for opacity in [tuning.darkRing, tuning.darkRimTop] {
            #expect(!(opacity > HeadroomTileEdgeValues.darkRimCeiling))
        }
        // Two tight shadows, not R2C1's one diffuse 0.6 @ r10 y3.
        #expect(tuning.darkShadowOpacity == 0.40 && tuning.darkShadowRadius == 0.5 && tuning.darkShadowY == 1)
        #expect(tuning.darkAmbientShadowOpacity == 0.30 && tuning.darkAmbientShadowRadius == 4 && tuning.darkAmbientShadowY == 2)
    }
}
