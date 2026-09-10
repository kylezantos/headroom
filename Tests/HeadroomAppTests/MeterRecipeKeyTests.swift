import Testing
import HeadroomCore
@testable import Headroom

/// M5A: the popover's card list and the Appearance specimen crossfade on the same drawn
/// recipe. These pin the two properties that make that swap correct — it fires exactly when
/// the *rendered* meter changes, and never when it doesn't.
@MainActor
@Suite
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
