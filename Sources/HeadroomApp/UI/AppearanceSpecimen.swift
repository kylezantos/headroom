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
    /// honest without a timeline tick (Settings is not a live-data surface). The fixture is
    /// in provider order (5-hour first); `fiveHourFirst()` is what `UsageStore.appDisplaySnapshot`
    /// applies before the popover draws, so the specimen and the popover agree on the same
    /// screen (pre-ship craft audit, 2026-09-08 — the specimen was the surface that drifted).
    private var entry: ProviderAccountEntry {
        ProviderAccountEntry(
            account: DemoFixture.settingsSpecimenAccount,
            snapshot: DemoFixture.settingsSpecimenSnapshot.fiveHourFirst()
        )
    }

    /// M5A: the specimen dissolves old recipe → new recipe instead of hard-cutting, the
    /// Menu Bar preview's `.id` + `.transition(.opacity)` pattern
    /// (the Menu Bar pane's `preview` strip, MS2). Its invisible-twin trick needs one change here:
    /// Full and Micro are genuinely different heights (Full stacks the label over a
    /// full-width gauge, Micro is one line), so a twin pinned at the *widest* state would
    /// leave a permanent Full-sized gap under a Micro card. This twin **tracks** the
    /// current style and is the only copy that sizes the well, so the height travels on
    /// `settle` as `.movement` (instant under Reduce Motion) while the two cards cross-fade
    /// on `settle` as `.crossfade` (always animated) in an overlay that doesn't affect
    /// layout. A plain `ZStack` would hold the taller card's height for the whole fade and
    /// then snap the pane below it.
    var body: some View {
        // CMM13 (Kyle, 2026-09-10): the card sits left-aligned on the pane's own axis —
        // centred it "looked goofy" against the left-aligned tiles below. CMM14: the
        // menu-bar pill is gone from this well; nothing below it changes the menu bar, only
        // the card, so the pill was previewing a choice this pane doesn't make.
        cardPreview
            // CMM15 (Kyle, 2026-09-10): the well hugs the card — 346 + 16/16 — and sits on
            // the pane's leading axis. Spanning the detail column left ~160pt of empty tray
            // beside the card; the well is a picture frame, not a tile.
            .fixedSize(horizontal: true, vertical: false)
            .settingsPreviewWell(
                dark: colorScheme == .dark,
                verticalPadding: 14,
                horizontalPadding: 16,
                cornerRadius: 16
            )
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of a provider card in the selected style")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardPreview: some View {
        specimen
            // R2C20: at the popover's true card width, not stretched to the detail column.
            // CMM15: the twin sizes the well, so it no longer claims the column's width.
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
    private var recipeKey: String { MeterRecipeKey.key(for: meterStyle) }

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
            // CMM14: the menu-bar pill and its caption left this well — see `body`.
        }
        .frame(width: PopoverCardMetrics.cardWidth, alignment: .leading)
    }
}
