import Foundation

/// KTD21: a `--demo` screenshot launch may pin the meter style with the Mac's own
/// `--meter-style <format>.<shape>.<fill>` token, so one fixture can be shot in every style
/// (U8's capture sweep, U18's screenshots). It sits on top of whatever the display store
/// resolved; outside a demo launch, or with a malformed token, the display is unchanged.
enum PhoneDemoMeterStyle {
    static let flag = "--meter-style"

    static func applied(
        to display: ResolvedPhoneDisplay, arguments: [String] = CommandLine.arguments
    ) -> ResolvedPhoneDisplay {
        guard arguments.contains(CompanionDemoLaunchOptions.demoFlag),
              let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1),
              let style = MeterStyle(launchToken: arguments[index + 1])
        else { return display }
        return ResolvedPhoneDisplay(
            meterStyle: style, percentageMode: display.percentageMode,
            accountTitleInk: display.accountTitleInk, showsSparkRows: display.showsSparkRows,
            source: display.source)
    }
}
