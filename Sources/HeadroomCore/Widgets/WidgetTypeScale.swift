import Foundation

/// The widget size families Headroom draws.
///
/// WidgetKit ships a `WidgetFamily` of its own, so any view file that imports both this
/// module and WidgetKit must disambiguate — use `HeadroomWidgetFamily` (the alias below) or
/// spell it `HeadroomCore.WidgetFamily`. The unqualified name stays because the layout
/// contract of the widget craft plan is written against it.
public enum WidgetFamily: Sendable, Equatable, CaseIterable {
    case small
    case medium
    case large
}

/// Collision-free spelling of `WidgetFamily` for files that also import WidgetKit.
public typealias HeadroomWidgetFamily = WidgetFamily

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
        self.spendAmount = spendAmount
        self.spendSuffix = spendSuffix
        self.footer = footer
        self.statusTitle = statusTitle
        self.statusMessage = statusMessage
        self.pillLabel = pillLabel
        self.pillHeight = pillHeight
    }

    /// The ladder for one family.
    public static func scale(for family: WidgetFamily) -> WidgetTypeScale {
        switch family {
        case .small:
            // Small draws a header, a name and a numeral; `label` and `countdown` carry the
            // medium values so a shared row view can read them without optionals,
            // but the `.glance` configuration never lays them out (WCF5).
            WidgetTypeScale(
                header: 11,
                name: 14,
                nameKerning: -0.15,
                label: 12,
                countdown: 11,
                spendAmount: 13,
                spendSuffix: 11,
                footer: 11,
                statusTitle: 14,
                statusMessage: 11.5,
                pillLabel: 9.5,
                pillHeight: 15
            )
        case .medium:
            WidgetTypeScale(
                header: 11,
                name: 14,
                nameKerning: -0.15,
                label: 12,
                countdown: 11,
                spendAmount: 13,
                spendSuffix: 11,
                footer: 11,
                statusTitle: 14,
                statusMessage: 11.5,
                pillLabel: 9.5,
                pillHeight: 15
            )
        case .large:
            WidgetTypeScale(
                header: 11,
                name: 15,
                nameKerning: -0.15,
                label: 13,
                countdown: 11,
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
}
