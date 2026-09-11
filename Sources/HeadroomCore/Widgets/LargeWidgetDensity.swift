import Foundation

/// WCL1: density tier for the large widget family.
///
/// The tile is fixed-size but its content is not — one provider with two windows and four
/// providers' worth of meters have to live in the same box — so the bar height, the grouping
/// gaps and the type step step down as the row count grows.
///
/// Three tiers, because only three are reachable. The row arithmetic is `providers +
/// rendered meters`; the audit's three real content mixes land on 4 (one provider, three
/// meters), 6 (two providers, four meters) and 8 (two providers, six meters), and the
/// envelope's two-provider cap puts the whole reachable range at 2…9 rows. The retired
/// four-tier ladder had an `ultraCompact` step no shipping envelope could reach and spent its
/// tuning on it.
///
/// The **spend strip is not counted**: it is one horizontal row outside the meter stack, and
/// counting it pushed an ordinary two-provider tile a whole tier tighter than it needed to be.
///
/// Fill-aware tier selection (choosing the tier from measured height, not row count) is the
/// recorded follow-up — see `BUGS.md`.
public enum LargeWidgetDensity: Equatable, Sendable {
    case roomy
    case regular
    case compact

    /// Rows = one header per provider + one row per rendered meter. Subscription meters
    /// (weekly, 5-hour, billing period) plus model-specific weekly sub-limits like Fable.
    public init(providerCount: Int, meterCount: Int) {
        let rows = max(0, providerCount) + max(0, meterCount)
        if rows <= 4 {
            self = .roomy
        } else if rows <= 6 {
            self = .regular
        } else {
            self = .compact
        }
    }

    public init(envelope: WidgetSnapshotEnvelope) {
        let providers = envelope.widgetProviders
        self.init(
            providerCount: providers.count,
            meterCount: providers.reduce(0) { total, provider in
                // A provider with no subscription windows still draws one placeholder meter,
                // and its extra weekly rows (Fable, Spark) draw after it. Count what is
                // rendered, not what is stored.
                total + max(1, provider.subscriptionWindows.count) + provider.extraWeeklyWindows.count
            }
        )
    }

    /// WCF1: the type ladder step this tier reads. Only the tightest tier gives up type.
    public var typeStep: WidgetTypeStep {
        switch self {
        case .roomy, .regular: .standard
        case .compact: .dense
        }
    }

    public var barHeight: Double {
        switch self {
        case .roomy: 8
        case .regular: 7
        case .compact: 6
        }
    }

    /// Provider header → first meter (WCL2's grouping ratio, tightened only at compact).
    public var headerSpacing: Double {
        switch self {
        case .roomy, .regular: 6
        case .compact: 5
        }
    }

    /// Meter → meter within one provider.
    public var meterSpacing: Double {
        switch self {
        case .roomy, .regular: 12
        case .compact: 9
        }
    }

    /// WCL1: the minimum gap between two provider sections. The gap itself is flexible — the
    /// tile distributes its slack there rather than at a fixed spacer — but it never closes
    /// below this, because the inter-provider hairline is gone and the gap is now the only
    /// thing separating two providers.
    public var providerGapFloor: Double { 16 }

    /// WCL1: the top and bottom edge spacers are weighted at this fraction of the provider
    /// gap. Equal weighting made the tile's outer air read as wide as the space between two
    /// providers, which flattened the grouping; under-weighting the edges keeps the stack
    /// reading as a stack.
    public var edgeGapWeight: Double { 0.6 }

    /// WCW9: the plan pill ("Max", "Pro") after the provider name. At compact the row height
    /// is already paying for the meters; the pill is context, so it is the first thing to go.
    public var showsPlanPill: Bool {
        switch self {
        case .roomy, .regular: true
        case .compact: false
        }
    }
}
