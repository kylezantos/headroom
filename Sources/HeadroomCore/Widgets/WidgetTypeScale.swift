import Foundation

/// The widget size families Headroom draws.
///
/// WidgetKit ships a `WidgetFamily` of its own, so any view file that imports both this
/// module and WidgetKit must disambiguate — use `HeadroomWidgetFamily` (the alias below) or
/// spell it `HeadroomCore.WidgetFamily`. The unqualified name stays because the layout
/// contract in `docs/plans/2026-09-11-001-feat-widget-craft-plan.md` is written against it.
public enum WidgetFamily: Sendable, Equatable, CaseIterable {
    case small
    case medium
    case large
}

/// Collision-free spelling of `WidgetFamily` for files that also import WidgetKit.
public typealias HeadroomWidgetFamily = WidgetFamily

/// WCL1: the large family's two type steps. `.dense` exists only for the `compact` density
/// tier; the small and medium families ignore the step entirely (they have one ladder each).
public enum WidgetTypeStep: Sendable, Equatable, CaseIterable {
    case standard
    case dense
}

/// WCF1: one type ladder, in points, identical on macOS and iOS.
///
/// Every widget body used to reach for semantic `Font` styles (`.caption`, `.headline`, …),
/// which resolve to different point sizes on the two platforms — that is why a Mac medium
/// tile and an iPhone medium tile could not be compared side by side. These are absolute
/// point sizes; the views read them through `@ScaledMetric(relativeTo:)` so iPhone keeps
/// Dynamic Type (capped at `xxLarge` at the root) while macOS, which does not scale, gets the
/// literal value.
///
/// Numerals are `.semibold`, never `.bold` (WCF1): bold numerals at 18pt on a 6pt bar read as
/// a second alarm level the data never asked for.
public struct WidgetTypeScale: Sendable, Equatable {
    /// Small's "Weekly left" header caption. 11 medium.
    public let header: Double
    /// Provider / account name. Semibold.
    public let name: Double
    /// Optical tracking for `name`; the SF text faces run loose at these sizes.
    public let nameKerning: Double
    /// Meter label ("Weekly", "5-hour", "Fable"). Medium.
    public let label: Double
    /// Countdown and window-state text. Monospaced.
    public let countdown: Double
    /// Percentage numeral. Semibold monospaced digits.
    public let numeral: Double
    /// The "left" suffix beside the numeral.
    public let suffix: Double
    /// API spend amount. Semibold monospaced digits.
    public let spendAmount: Double
    /// The "used" / "left" word after a spend amount.
    public let spendSuffix: Double
    /// "Updated N ago" / "From Mac · N ago". Medium, monospaced digits.
    public let footer: Double
    /// Status-card title. Semibold.
    public let statusTitle: Double
    /// Status-card message. Medium.
    public let statusMessage: Double
    /// WCW9: plan pill label. Medium, kerned 0.2.
    public let pillLabel: Double
    /// WCW9: plan pill capsule height.
    public let pillHeight: Double

    public init(
        header: Double,
        name: Double,
        nameKerning: Double,
        label: Double,
        countdown: Double,
        numeral: Double,
        suffix: Double,
        spendAmount: Double,
        spendSuffix: Double,
        footer: Double,
        statusTitle: Double,
        statusMessage: Double,
        pillLabel: Double,
        pillHeight: Double
    ) {
        self.header = header
        self.name = name
        self.nameKerning = nameKerning
        self.label = label
        self.countdown = countdown
        self.numeral = numeral
        self.suffix = suffix
        self.spendAmount = spendAmount
        self.spendSuffix = spendSuffix
        self.footer = footer
        self.statusTitle = statusTitle
        self.statusMessage = statusMessage
        self.pillLabel = pillLabel
        self.pillHeight = pillHeight
    }

    /// The ladder for one family. `step` is honoured on `.large` only — the small and medium
    /// tiles have a single content mix each, so there is nothing for a dense step to buy
    /// there (WCL1 chooses the step from the large tier's row count).
    public static func scale(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> WidgetTypeScale {
        switch (family, step) {
        case (.small, _):
            // Small draws a header, a name and a numeral; `label`, `countdown` and `suffix`
            // carry the medium values so a shared row view can read them without optionals,
            // but the `.glance` configuration never lays them out (WCF5).
            WidgetTypeScale(
                header: 11,
                name: 14,
                nameKerning: -0.15,
                label: 12,
                countdown: 11,
                numeral: 18,
                suffix: 11,
                spendAmount: 13,
                spendSuffix: 11,
                footer: 11,
                statusTitle: 14,
                statusMessage: 11.5,
                pillLabel: 9.5,
                pillHeight: 15
            )
        case (.medium, _):
            // Medium's numeral steps down to 16 because two columns have to hold
            // `label + countdown + numeral + suffix` inside one half of the tile (WCL7).
            WidgetTypeScale(
                header: 11,
                name: 14,
                nameKerning: -0.15,
                label: 12,
                countdown: 11,
                numeral: 16,
                suffix: 11,
                spendAmount: 13,
                spendSuffix: 11,
                footer: 11,
                statusTitle: 14,
                statusMessage: 11.5,
                pillLabel: 9.5,
                pillHeight: 15
            )
        case (.large, .standard):
            WidgetTypeScale(
                header: 11,
                name: 15,
                nameKerning: -0.15,
                label: 13,
                countdown: 11,
                numeral: 18,
                suffix: 11,
                spendAmount: 13,
                spendSuffix: 11,
                footer: 11,
                statusTitle: 14,
                statusMessage: 11.5,
                pillLabel: 9.5,
                pillHeight: 15
            )
        case (.large, .dense):
            // The dense step is the only place fractional sizes appear: at 8+ rows the
            // countdown and suffix give up half a point rather than being dropped.
            WidgetTypeScale(
                header: 11,
                name: 14,
                nameKerning: -0.15,
                label: 12,
                countdown: 10.5,
                numeral: 16,
                suffix: 10.5,
                spendAmount: 13,
                spendSuffix: 11,
                footer: 11,
                statusTitle: 14,
                statusMessage: 11.5,
                pillLabel: 9.5,
                pillHeight: 15
            )
        }
    }

    /// WCF2: the reserved numeral column for this ladder's numeral size.
    public var numeralColumnWidth: Double {
        Self.numeralColumnWidth(forNumeralSize: numeral)
    }

    /// WCF2: the width the percentage column reserves, so "7%" and "100%" put their bars and
    /// their names in the same place on every row of every tile.
    ///
    /// The table is the widest string the column can hold — "100%" — in SF semibold
    /// monospaced digits. Core cannot link AppKit, so the numbers are measured once and
    /// stored: `NSFont.monospacedDigitSystemFont(ofSize:weight: .semibold)` renders "100%" at
    /// 40.89 / 46.17 / 51.42 pt for 14 / 16 / 18, and the shipped column rounds each up to
    /// **42 / 47.5 / 52** so the glyphs never touch the suffix. (Measured with
    /// `.context/qc/widgets/measure.swift`, the widget audit's sizing harness.)
    ///
    /// Sizes between the stops interpolate linearly; sizes outside them extrapolate along the
    /// nearest segment, so a future ladder size still gets a sane column instead of a clamp.
    public static func numeralColumnWidth(forNumeralSize size: Double) -> Double {
        let stops: [(size: Double, width: Double)] = [(14, 42), (16, 47.5), (18, 52)]
        func interpolate(_ lower: (size: Double, width: Double), _ upper: (size: Double, width: Double)) -> Double {
            let progress = (size - lower.size) / (upper.size - lower.size)
            return lower.width + (upper.width - lower.width) * progress
        }
        if size <= stops[0].size {
            return max(0, interpolate(stops[0], stops[1]))
        }
        for (lower, upper) in zip(stops, stops.dropFirst()) where size <= upper.size {
            return interpolate(lower, upper)
        }
        return interpolate(stops[stops.count - 2], stops[stops.count - 1])
    }
}
