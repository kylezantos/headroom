#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// WCW3: the widget footer stamp (large only since the widget-styles plan, R14). The platform difference is the prefix
/// the host passes in; the stamp itself is monospaced-digit so it stops reflowing once a
/// minute, and takes `secondaryText` rather than the tertiary tier it used to.
struct HeadroomWidgetFooterStamp: View {
    let text: String
    let capturedAt: Date?
    let now: Date
    let size: Double

    @Environment(\.colorScheme) private var scheme
    // WCF1: medium and large both hand the stamp a raw ladder size, so the scaling happens
    // here rather than twice at the call sites.
    @HeadroomWidgetTypeUnit private var typeUnit

    var body: some View {
        if let stamp = HeadroomWidgetCopy.footerText(prefix: text, capturedAt: capturedAt, now: now) {
            Text(stamp)
                .font(.system(size: size * typeUnit, weight: .medium).monospacedDigit())
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Strings the family bodies share with both hosts. Window labels and the small header
/// live in Core (WCW2/WCW7); these three are host-composition, not data.
public enum HeadroomWidgetCopy {
    /// WCW7: "Usage" at every fallback site — a pending Grok or Cursor row must not claim a
    /// weekly limit it does not have.
    public static let fallbackWindowLabel = WidgetWindowSummary.fallbackLabel
    /// WCW3: the sentence is true on the Mac and false on the phone, which is the one place
    /// the mirror rule licenses a split.
    public static let macFooterPrefix = "Updated "
    public static let iosFooterPrefix = "From Mac · "

    public static func footerText(prefix: String, capturedAt: Date?, now: Date) -> String? {
        guard let updated = Countdown.updatedLabel(capturedAt: capturedAt, now: now) else { return nil }
        return prefix + updated
    }
}
