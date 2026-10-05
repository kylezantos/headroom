#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import HeadroomCore

/// U12: `MeterStyleTile` moved to `HeadroomSharedUI` so the phone draws the same swatches. The
/// Mac keeps its call site (`MeterStyleTile(meterStyle:onChange:)` in `SettingsPanes`) and its
/// look: this chrome passes the Settings window's own vocabulary back in, and its container
/// still puts the rows in a `SettingsTile` titled "Meter Style" (R2C19/R2B1: one container,
/// one title policy).
struct MacSettingsMeterStyleChrome: MeterStyleTileChrome {
    /// The numbers the tile always drew: five 76pt columns on 8pt gaps (L12B), a 26pt well over
    /// an 11pt label inside 5pt of padding, and the tile's groups `groupToGroup` apart.
    var metrics: MeterStyleTileMetrics {
        MeterStyleTileMetrics(
            rowSpacing: SettingsMetrics.groupToGroup,
            captionSpacing: SettingsMetrics.labelToStackedControl,
            swatchWidth: 76,
            swatchSpacing: 8,
            swatchPadding: 5,
            wellHeight: 26,
            wellCornerRadius: 6,
            labelSpacing: 5,
            labelFont: SettingsType.swatchLabel,
            twoLineLabelHeight: 28,
            labelMinimumScaleFactor: 0.8,
            fragmentWidth: 60
        )
    }

    func caption(_ text: String) -> some View {
        SettingsGroupLabel(text)
    }

    func help(_ text: String) -> some View {
        SettingsHelpText(text: text)
    }

    func selection(isSelected: Bool) -> MacSwatchSelection {
        MacSwatchSelection(isSelected: isSelected)
    }

    func selectionGroup(value: AnyHashable) -> MacSwatchSelectionGroup {
        MacSwatchSelectionGroup(value: value)
    }

    var swatchStyle: SettingsSwatchButtonStyle { SettingsSwatchButtonStyle() }

    func container() -> MacMeterStyleTileContainer { MacMeterStyleTileContainer() }
}

extension MeterStyleTile where Chrome == MacSettingsMeterStyleChrome {
    /// The Mac's call site, unchanged by the move.
    init(meterStyle: MeterStyle, onChange: @escaping (MeterStyle) -> Void) {
        self.init(meterStyle: meterStyle, chrome: MacSettingsMeterStyleChrome(), onChange: onChange)
    }
}

/// The tile's container: the Settings window's titled tile. The shared rows are one stack
/// spaced `groupToGroup`, the same rhythm `SettingsTile` gave the three rows as its own
/// children.
struct MacMeterStyleTileContainer: ViewModifier {
    func body(content: Content) -> some View {
        SettingsTile("Meter Style") { content }
    }
}

/// PB13: the Settings selection ring, as a named modifier the shared tile can hold.
struct MacSwatchSelection: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.selectionChrome(isSelected: isSelected)
    }
}

/// SM1: one swatch row's travelling selection plate.
struct MacSwatchSelectionGroup: ViewModifier {
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.settingsSelectionGroup(value: value)
    }
}
