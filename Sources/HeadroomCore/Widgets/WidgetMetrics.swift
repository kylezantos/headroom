import Foundation

/// WCF3 / WCF4 / WCL2 / WCL5: the widget layout constants, shared by both hosts.
///
/// These were per-file literals in four view bodies, which is how the Mac medium tile and the
/// iPhone medium tile ended up with different margins, different gutters and different
/// label-to-bar gaps while claiming to be the same design. Every number here is a decision
/// from `docs/plans/2026-09-11-001-feat-widget-craft-plan.md`; the views own only how they
/// are spent.
public enum WidgetMetrics {
    // MARK: - Margins (WCF4)

    /// The residual margin a widget body adds on top of the system content margin, on every
    /// family and both hosts. One rule: effective margin = system content margin + 2.
    public static let residualMargin: Double = 2

    /// WCF4: iPhone reclaims 4pt of the system content margin on the small and large
    /// families, where the payload is tight and the system inset is generous. Documented
    /// rather than silent — it is the one place the two hosts' effective margins differ.
    public static let iOSMarginReclaim: Double = 4

    /// WCL4: iPhone medium does **not** take the reclaim. Its centre rule is confined to the
    /// meter band, so the outer margin is what keeps the two columns off the tile edge.
    public static let iOSMediumMargin: Double = 16

    // MARK: - The content axis (WCF3)

    /// Mark slot → content axis. The brand mark hangs in the leading gutter; everything the
    /// eye reads down the tile — header caption, provider name, meter labels **and bars** —
    /// starts on the axis.
    public static let markGap: Double = 6

    /// WCL3: the brand mark's slot, sized from the name's cap height (`round(1.43 × cap
    /// height)`) so the mark and the word beside it carry the same visual weight.
    public static func markSlot(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> Double {
        switch (family, step) {
        case (.small, _): 15
        case (.medium, _): 16
        case (.large, .standard): 20
        case (.large, .dense): 18
        }
    }

    /// WCF3: the leading content axis — `markSlot + markGap`. 21 / 22 / 26 / 24.
    ///
    /// Leading side only. There is deliberately no trailing mirror of the gutter: a widget
    /// has no card padding to mirror, so bars run to the content edge and the tile reads as
    /// full-bleed instead of as a card that lost its frame.
    public static func contentAxis(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> Double {
        markSlot(for: family, step: step) + markGap
    }

    // MARK: - Grouping (WCL2)

    /// Meter label → its bar, on every family. The label and the bar are one object; this gap
    /// is smaller than any gap between meters so the pairing reads before the list does.
    public static let labelToBar: Double = 7

    // MARK: - Small (WCL5)

    /// Small's header caption → the first row.
    public static let smallHeaderToRows: Double = 22
    /// Small row → row.
    public static let smallRowToRow: Double = 12
    /// WCL5: small spends its slack on the payload — the widest bar of any family.
    public static let smallBarHeight: Double = 8

    // MARK: - Medium (WCL2 / WCL4)

    /// Provider header → first meter.
    public static let mediumHeaderToMeter: Double = 6
    /// Meter → meter within one provider.
    public static let mediumMeterToMeter: Double = 10
    public static let mediumBarHeight: Double = 6
    /// WCL4: the gutter between medium's two columns. The centre rule is one device pixel
    /// centred in it, so each bar ends 14pt clear of the rule.
    public static let mediumGutter: Double = 28
    /// WCL4: medium has no spend hairline. A flexible spacer with this floor separates the
    /// spend row from the meter band instead.
    public static let mediumSpendAirFloor: Double = 14

    // MARK: - Spend strip (WCW6)

    /// Gap between two spend clusters.
    public static let spendItemGap: Double = 10
    /// Large's spend rule → the spend row.
    public static let spendRuleToRow: Double = 9
    /// Numeral → its "left" / "used" suffix.
    public static let suffixGap: Double = 5

    // MARK: - Rules (WCL4)

    /// WCL4: every widget rule is a true hairline. This is the numerator — the view divides
    /// it by `displayScale` so the rule is one device pixel at @2x and @3x rather than a 1pt
    /// line that reads as a border.
    public static let hairline: Double = 1
}
