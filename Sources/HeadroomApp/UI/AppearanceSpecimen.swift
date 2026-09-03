import SwiftUI
import HeadroomCore

/// Live specimen at the top of Settings › Appearance (R6, KD4). The whole point is that
/// it is not a mock: it is the *real* `ProviderCardView` and the *real* `MenuBarLabel`
/// renderer, fed a fixture snapshot, so a meter style can never preview as something the
/// popover doesn't draw.
///
/// KTD4 makes it inert in three ways at once:
/// - `.allowsHitTesting(false)` — the card's own buttons and rows can't be pressed.
/// - `.accessibilityElement(children: .ignore)` + one label — VoiceOver reads a single
///   "preview" element, never the fixture account, plan pill, or reset times.
/// - `announcesAccessibilityEvents: false` on the card — `SetupSessions` dedupes
///   capability announcements *per provider*, so a preview on a synthetic account id
///   would still clear the real Claude entry and make the popover re-announce it.
///
/// The card follows Theme (via the window's color scheme), meter style, and Percentages.
/// The menu bar strip follows Percentages only: the menu bar projection deliberately
/// carries no meter style, so pretending otherwise here would be a lie.
struct AppearanceSpecimen: View {
    let meterStyle: MeterStyle
    let percentageMode: UsagePercentageMode

    @Environment(\.colorScheme) private var colorScheme

    /// One fixture entry, rebuilt per render so the card's `now`-driven reset text stays
    /// honest without a timeline tick (Settings is not a live-data surface).
    private var entry: ProviderAccountEntry {
        ProviderAccountEntry(
            account: DemoFixture.settingsSpecimenAccount,
            snapshot: DemoFixture.settingsSpecimenSnapshot
        )
    }

    /// The menu bar's own summary shape, built from the same fixture window the strip
    /// would show in production (weekly is the default preferred menu-bar window), so
    /// flipping Percentages flips the strip's numeral the way it does in the bar.
    private var menuBarMeters: [MenuBarMeter] {
        let snapshot = DemoFixture.settingsSpecimenSnapshot
        guard let weekly = snapshot.windows.first(where: { $0.kind == .weekly }) else {
            return [MenuBarMeter(summary: .neutral, fill: nil)]
        }
        return [
            MenuBarMeter(
                summary: MenuBarSummary(
                    text: "\(percentageMode.roundedPercentage(for: weekly))%",
                    providerID: .claude,
                    detail: "\(ProviderID.claude.displayName) \(WindowKind.weekly.shortLabel.lowercased())",
                    isNeutral: false,
                    percentageMode: percentageMode,
                    severity: weekly.severity
                ),
                fill: percentageMode.fraction(for: weekly)
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ProviderCardView(
                providerID: .claude,
                displayName: ProviderID.claude.displayName,
                entries: [entry],
                capabilityStatus: nil,
                percentageMode: percentageMode,
                meterStyle: meterStyle,
                anyProviderMultiAccount: false,
                now: Date(),
                onRetrySetup: {},
                onRetryAccount: { _ in },
                announcesAccessibilityEvents: false
            )

            HStack(spacing: 10) {
                // The label renderer pins its palette dark (white ink + dark severity
                // colors) because that's what the Tahoe menu bar shows. On a light well
                // that ink would be invisible, so the strip keeps its own dark plate —
                // the same one the Menu Bar tile uses.
                MenuBarLabel(meters: menuBarMeters, showsPercentage: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Color(white: 0.15),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                Text("Follows the choices below.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ClaudeSetupStyle.wellBackground(dark: colorScheme == .dark),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of a provider card in the selected style")
    }
}
