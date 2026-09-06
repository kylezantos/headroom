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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// M5A: the specimen dissolves old recipe → new recipe instead of hard-cutting, the
    /// Menu Bar preview's `.id` + `.transition(.opacity)` pattern
    /// (`SettingsPanes.swift:209-217`). Its invisible-twin trick needs one change here:
    /// Full and Micro are genuinely different heights (Full stacks the label over a
    /// full-width gauge, Micro is one line), so a twin pinned at the *widest* state would
    /// leave a permanent Full-sized gap under a Micro card. This twin **tracks** the
    /// current style and is the only copy that sizes the well, so the height travels on
    /// `settle` as `.movement` (instant under Reduce Motion) while the two cards cross-fade
    /// on `settle` as `.crossfade` (always animated) in an overlay that doesn't affect
    /// layout. A plain `ZStack` would hold the taller card's height for the whole fade and
    /// then snap the pane below it.
    var body: some View {
        specimen
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
                value: recipeKey
            )
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    specimen
                        .id(recipeKey)
                        .transition(.opacity)
                }
                // The outgoing and incoming cards keep their own natural heights and
                // overflow the contracting box rather than fighting it for the well's size.
                .fixedSize(horizontal: false, vertical: true)
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                    value: recipeKey
                )
            }
            .clipped()
            .settingsPreviewWell(dark: colorScheme == .dark, verticalPadding: 8)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of a provider card in the selected style")
    }

    /// `MeterStyle` is `Equatable`, not `Hashable`, so the swap keys on the drawn recipe.
    /// `resolvedShape` rather than `shape` is deliberate: Tube stays *stored* while Full is
    /// selected but renders as Chip, so keying on the raw shape would cross-fade a card
    /// into an identical copy of itself.
    private var recipeKey: String {
        "\(meterStyle.format.rawValue).\(meterStyle.resolvedShape.rawValue).\(meterStyle.fill.rawValue)"
    }

    private var specimen: some View {
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
                // colors) because that's what the Tahoe menu bar shows; the shared plate
                // keeps it legible on a light well.
                MenuBarPreviewPill(meters: menuBarMeters, showsPercentage: true)
                Text("Follows the choices below.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
    }
}
