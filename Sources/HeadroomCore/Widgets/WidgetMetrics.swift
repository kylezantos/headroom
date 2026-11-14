import Foundation

/// WCF3 / WCF4: the widget layout constants shared by both hosts. Each style's own tokens are
/// `WidgetStyleMetrics`.
///
/// These were per-file literals in four view bodies, which is how the Mac medium tile and the
/// iPhone medium tile ended up with different margins, different gutters and different
/// label-to-bar gaps while claiming to be the same design. Every number here is a decision
/// from the widget craft plan; the views own only how they
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
    public static func markSlot(for family: WidgetFamily) -> Double {
        switch family {
        case .small: 15
        case .medium: 16
        case .large: 20
        }
    }

    // MARK: - Spend strip (WCW6)

    /// Gap between two spend clusters.
    public static let spendItemGap: Double = 10
    /// Large's spend rule → the spend row.
    public static let spendRuleToRow: Double = 9

    // MARK: - Rules (WCL4)

    /// WCL4: every widget rule is a true hairline. This is the numerator — the view divides
    /// it by `displayScale` so the rule is one device pixel at @2x and @3x rather than a 1pt
    /// line that reads as a border.
    public static let hairline: Double = 1
}
