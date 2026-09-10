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
/// The card follows Theme (via the window's color scheme), meter style, Percentages, and
/// the account-name ink.
/// The menu bar strip follows Percentages only: the menu bar projection deliberately
/// carries no meter style, so pretending otherwise here would be a lie.
struct AppearanceSpecimen: View {
    let meterStyle: MeterStyle
    let percentageMode: UsagePercentageMode
    let accountTitleInk: AccountTitleInk

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
        // CMM13 (Kyle, 2026-09-10): the preview is a scene — a menu-bar strip bleeding to
        // the well's top edge with the live status item at its leading inset, and the
        // popover card hanging beneath it, left-aligned with the tiles below. Centred, the
        // card "looked goofy" against a left-aligned pane; the strip gives the pill the
        // context it previews instead of a caption.
        VStack(alignment: .leading, spacing: 14) {
            menuBarStrip
                .padding(.horizontal, -16)
                .padding(.top, -14)
            cardPreview
        }
        .settingsPreviewWell(
            dark: colorScheme == .dark,
            verticalPadding: 14,
            horizontalPadding: 16,
            cornerRadius: 16
        )
        // The strip overflows the well's padding on purpose; the well's own radius clips it.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the menu bar item and a provider card in the selected style")
    }

    /// CMM13: a 24pt bar in the live menu bar's tint (PB13's plate colours) with the real
    /// `MenuBarLabel` sitting where a status item sits.
    private var menuBarStrip: some View {
        let darkMenuBar = MenuBarAppearanceMonitor.shared.isDarkMenuBar
        return HStack(spacing: 0) {
            MenuBarLabel(meters: menuBarMeters, showsPercentage: true, appearance: .menuBar)
                .padding(.leading, 16)
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(darkMenuBar ? Color(white: 0.15) : Color(white: 0.93))
    }

    private var cardPreview: some View {
        specimen
            // R2C20: at the popover's true card width, not stretched to the detail column.
            // CMM13: leading-aligned, on the pane's own left axis.
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
                value: recipeKey
            )
            // CMM13: `.topLeading` on both, or the fading cards centre themselves over
            // the leading-aligned twin.
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
    }

    /// `MeterStyle` is `Equatable`, not `Hashable`, so the swap keys on the drawn recipe.
    /// `resolvedShape` rather than `shape` is deliberate: Tube stays *stored* while Full is
    /// selected but renders as Chip, so keying on the raw shape would cross-fade a card
    /// into an identical copy of itself.
    private var recipeKey: String {
        "\(meterStyle.format.rawValue).\(meterStyle.resolvedShape.rawValue).\(meterStyle.fill.rawValue)"
    }

    /// R2C20: the specimen is drawn at the popover's own card width. Stretched to the detail
    /// column it measured 506pt against the real card's 346 — 1.46× — which put ~260pt
    /// between a Micro row's label and its gauge where the popover puts ~100, so Micro
    /// previewed airy here and tight there and `ViewThatFits` could pick a branch the popover
    /// never draws. R6/KD4 says a meter style can never preview as something the popover
    /// doesn't draw, and width is part of what it draws.
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
            // G1A: the specimen is the popover's card, so it reads the ink from the
            // environment the same way — set here because Settings is not the popover.
            .environment(\.accountTitleInk, accountTitleInk)
            // CMM13: the menu-bar pill moved up into `menuBarStrip`; the caption went with
            // it — a status item sitting in a bar explains itself.
        }
        .frame(width: PopoverCardMetrics.cardWidth, alignment: .leading)
    }
}
