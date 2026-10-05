import SwiftUI

/// KTD11 (R21): the display choices the phone's cards render with — meter style, percentage
/// mode, account-name ink and whether Spark rows show.
struct PhoneDisplayChoices: Equatable, Sendable {
    var meterStyle: MeterStyle
    var percentageMode: UsagePercentageMode
    var accountTitleInk: AccountTitleInk
    var showsSparkRows: Bool

    /// "Match my Mac": the manifest's display block, else the app defaults. A v3-only Mac
    /// carries no block, so its Spark rows default off (KTD11).
    static func matchingMac(_ block: CompanionDisplayBlock?) -> Self {
        let block = block ?? CompanionDisplayBlock()
        return Self(
            meterStyle: block.meterStyle,
            percentageMode: block.percentageMode,
            accountTitleInk: block.accountTitleInk,
            showsSparkRows: block.appSparkEnabled
        )
    }
}

/// U8 → U12 seam: how the cards turn the Mac's display block into choices. U8 ships the
/// default ("Match my Mac", always on); U12 owns the phone preference — the switch and its
/// remembered override — and plugs it in at the root with
/// `.environment(\.phoneDisplayResolver, PhoneDisplayResolver { block in … })`, without the
/// cards knowing where the choice came from.
struct PhoneDisplayResolver: Sendable {
    let resolve: @Sendable (CompanionDisplayBlock?) -> PhoneDisplayChoices

    static let matchingMac = PhoneDisplayResolver(resolve: PhoneDisplayChoices.matchingMac)
}

extension EnvironmentValues {
    @Entry var phoneDisplayResolver: PhoneDisplayResolver = .matchingMac
}
