# Pre-ship craft audit fixes (2026-09-08)

Source: `design/preship-craft-audit-options.html` (Kyle's answers, pasted 2026-09-08) built from
`.context/qc/preship-audit/report.html`, a `better-interface` audit of `0737dc4e..origin/main`.
Decision anchors (`PA1`…`PB13`) are the WHY citations for code comments. Denied items are listed
so nobody "fixes" them later.

## Decisions

| Anchor | Decision |
| --- | --- |
| PA1 | **Light neutral meter greys become black-alpha over the card**, mirroring the dark branch's white-alpha, so `neutral < low < critical` in |Lc| holds in both schemes. Start at body ≈ black @ 0.24, cap ≈ black @ 0.36 (`glassA`/`tickGlass`, `glassB`/`tickGlassCap`); amber untouched. Add a `BrandColorValuesTests` assertion of that ordering against the card in both schemes. |
| PA2 | **Delete the engineering-status sentences** from the API Spend admin-key guidance (`SettingsPanes.swift:638` "known request-format issue", `:644` "isn't live-verified yet"). Nothing replaces them. |
| PA3 | **No "Add Key" on pending or retryable spend rows**: `pendingStatus` and `.retryable` get `callToAction: nil`. `"Fix Key"` becomes `"Replace Key"` (the pane has Replace and Remove, no Fix). |
| PA4 | **Release notes rewritten in the 1.3.0-31 voice** and **this release is 1.4.0 (32)**: the public appcast already serves 1.3.0, and Kyle's rule is "1.3.0 build 32 only if the last public build was 1.2.x". Notes file renamed `Headroom-1.4.0-32.html`; the version bump itself happens in the release runbook's prepare step, not here. |
| PA5 | **Swatches preview against the live selection**: Format/Shape/Fill/Percentages swatches take the current `meterStyle` for the two axes they do not vary; only the fixed 0.62/0.38 fractions and severities stay literal. |
| PA6 | **Micro row stays centre-aligned, and centres optically** (Kyle: "center aligned with each other, not the bottom baseline"). Keep `HStack(alignment: .center)`; add a `VerticalAlignment.center` guide on each text element that aligns **cap-height centres** (label 13 semibold, countdown 11, numeral 18 semibold, "left" 11) with each other and with the gauge's geometric centre, measured from the real `NSFont` like `OpticalLeading` does. Test the offset math; do not switch to `.firstTextBaseline`. |
| PA7 | **One capsule label role** inside `identityCapsule`: 10.5 medium, kerning 0.2, 18pt tall. Per-recipe ink and fill stay. Applies to plan pill, period chip, Stale tag, Low chip, spend state tag, Connected chip. |
| PA8 | **Stale rows dim the numeral** to `.secondary` (critical ink still wins) and ride the existing `settleCrossfade` on `landedTone`, so the M3A′ comment becomes true. |
| PA9 | **Brand marks equalised by ink mass, not box**: `massCorrection` starts at Claude 1.05, Codex 0.92, Grok 1.10, Cursor 0.94. Kyle: "make sure they all appear optically the same size" — Fable re-shoots `multi-4` in both appearances and tunes. |
| PA10 | **Header status derives from the card's own action**: `.connect` → "Connect Codex to begin", `.reconnect` → "Reconnect Codex", `.showPrivacyGuidance` → "Codex needs file access", `.resolveStorage` → "Codex sign-in needs relocating". All "Watching for …" strings become "Waiting for …" to match the cards. |
| PA11 | **One label for `.checkNow`: "Check Now"** in every slot (`ProviderSetup.swift`, `ProviderCapabilityPresentation.swift`). Footer keeps "Refresh" for the whole-app poll. |
| PA11b | **Text-labelled buttons get a resting container everywhere (supersedes B3H).** Kyle: "we do need the resting container for all our buttons". Apple HIG (Buttons, macOS): push buttons carry a visible border, every custom button needs a press state, and borderless buttons belong in toolbars/status bars. So: `SetupChipButtonStyle` default chrome becomes `.resting` at every popover site (card foot, account rows, spend CTA); the footer Refresh/Quit move from `HoverButtonStyle` to the regular resting chip; hover lifts the fill one step and pressed goes `pressScale` + one step darker. **Glyph-only controls** (gear, `+`, `…`, copy, trash, reset) stay borderless with the hover pill, which is the HIG toolbar convention. Light-scheme chip fills become subtractive (black @ ~0.06 rest / ~0.10 hover) so the container actually renders on white tiles (was B6). |
| PA12 | **A freshly added account shows the typed copy**: the untyped preset reuses `ProviderSetupOutcome.claudeLoginRequired`'s message and recovery ("Sign in with the official Claude CLI" + Open Claude Setup / Check Now). **No ellipsis on "Sign In"** on either surface (Kyle picked B); "Add Account…" and "Check for Updates…" keep theirs (B3A). |
| PA13 | **Dark muted text re-derived by |Lc|, not ratio**: `accountTitle(dark:)` → ≈ `#9AA2AC`, `countdownInk(dark:)` → ≈ 0.66, `tertiaryText(dark:)` → ≈ 0.68, plan pill gets its own token instead of system `.tertiary`. Re-measure both schemes; update the `accountTitle` comment. |
| PA14 | **Denied.** The spend card foot may still cross the 640pt cap. BUGS.md entry stays. |
| PA15 | **`BrandIconImage` caches** per (provider, scheme), same shape as `VesselGlyph.cache`. |
| PB1 | **Curly apostrophes** (`’`) in every user-facing string under `Sources/`; leave `/usage`, shell commands, identifiers. |
| PB2 | **Pane title up one step**: 17 semibold, kerning −0.2 (Kyle picked A). Tile titles stay 15 semibold. Fix the stale "16pt card titles" comment (`SettingsRows.swift:99-101`); they are 15. |
| PB3 | **Segmented pickers pinned** to `SettingsMetrics.segmentedMaxWidth` with `.frame(width:)`, not `maxWidth`. |
| PB4 | **Tile grouping**: `SettingsTile` VStack spacing 10 → 18; the Spark-counter checkbox nests inside the "Share data with widgets" group; "Period" reads as its own group. |
| PB5 | **Menu bar attention dot never clips**: the 3pt overhang joins the measured image width (or the dot insets to `x + vesselWidth − 5`). |
| PB7 | **Fill row gets one help line**: "Solid is always coloured. Color as event stays neutral until usage runs low. Hue ramp shifts colour as it empties. Glass and Ghost add a bright end cap." Menu Bar help says "level", not "fill". |
| PB8 | **The widget rule is stated once**: Menu Bar — "Sets the menu-bar number and the first two widget tiles. Auto picks whichever provider is closest to its limit." Widgets — "Widgets follow the priority providers you choose in Menu Bar." with "Menu Bar" a link to that pane. |
| PB9 | "Sync snapshot to iPhone" → **"Sync usage to iPhone"**; Settings "Another Claude login is open" → **"sign-in"**; drop trailing periods on single-sentence tooltips (`AccountsSettingsInteractions.swift:224`, `SettingsPanes.swift:374`). |
| PB10 | **Denied.** Reconnect-card indent, `•••` column, Refresh/Quit pad stay. |
| PB11 | Typography LOWs: `.lineSpacing(2)` on wrapping popover prose (setup body, `StatusSentence`, spend sentence); `.caption`/`.caption2` holdouts in `ProviderCardView` → 11.5 medium / 11 monospaced; `OpticalLeading` rounds set adds `a d g q`; "Last known N min ago" gets `.monospacedDigit()`; title gets `.layoutPriority(2)` over the email and joins `rowHelp` when truncated. |
| PB12 | UI LOWs: spend `+` → 13 semibold on the numerals' optical centre; `HeadroomMotion.pressScale = 0.96` used by all four button styles; the custom tooltip fades on `quickSettle` with `.transition(.opacity)`; sidebar Appearance symbol → `circle.lefthalf.striped.horizontal`. |
| PB13 | Colors LOWs: delete dead `ClaudeSetupStyle.accentText`; Codex CTA gradient moves into a local `CodexSetupStyle` mirroring Claude's (no Core token, keeps streams decoupled); one shared `selectionChrome(isSelected:)` modifier for the three pickers; `staleGrey` and the quarter-mark tint move into `HeadroomMeterColorValues`; Settings "Connected" (`AccountsSettingsTile.swift:758`) adopts the `SettingsRows` green-check treatment; the Settings menu-bar previews follow `MenuBarAppearanceMonitor.shared.isDarkMenuBar` and swap their plate (keep `.pinnedDark` as the `MenuBarLabel` default so signatures don't change). |
| D2–D6 | Unanswered. No action. |

## Workstreams (file-owned, run in parallel, disjoint)

Each stream builds and tests in its own worktree, commits on its own branch, and never edits a file
another stream owns. Public signatures shared across streams do not change (add, don't rename).

**WS-1 core-and-marks** — owns `Sources/HeadroomCore/**`, `Sources/HeadroomApp/UI/MenuBarLabel.swift`,
`MeterGauge.swift`, `VesselGlyph.swift`, `ProviderLogoView.swift`, `ProviderStyle.swift`,
`Tests/HeadroomCoreTests/**`. Items: PA1, PA3, PA9, PA11, PA13, PA15, PB1 (Core strings), PB5,
PB11 (nothing here), PB13 (`staleGrey`/quarter tint tokens only).

**WS-2 popover** — owns `PopoverView.swift`, `ProviderCardView.swift`, `ProviderCardIdentityRows.swift`,
`UsageBarView.swift`, `APISpendSectionView.swift`, `ClaudeSetupViews.swift`, `CodexSetupViews.swift`,
`SetupSessions.swift`, `HoverButtonStyle.swift`, `HeadroomMotion.swift`, `OpticalLeading.swift`,
`Tests/HeadroomAppTests/**`. Items: PA6, PA7, PA8, PA10, PA11b, PA12 (popover half), PB1, PB11,
PB12 (all but the sidebar icon), PB13 (dead token, `CodexSetupStyle`).

**WS-3 settings** — owns `SettingsView.swift`, `SettingsPanes.swift`, `SettingsRows.swift`,
`SettingsSidebar.swift`, `MeterStyleTile.swift`, `InAppDisplayTile.swift`, `ThemeThumbnailPicker.swift`,
`AppearanceSpecimen.swift`, `AccountsSettingsTile.swift`, `AccountsSettingsInteractions.swift`,
`WidgetSettingsSection.swift`, `WidgetPreviewStrip.swift`. Items: PA2, PA5, PA12 (Settings "Sign In"),
PB1, PB2, PB3, PB4, PB7, PB8, PB9, PB12 (sidebar icon), PB13 (selection chrome, Connected ink,
menu-bar preview plate).

**WS-4 release notes** — Fable: PA4.

## Verification

Per stream: `swift build`, `swift test`, new or adjusted tests for every Core/behaviour change (PA1
ordering, PA3 CTA gating, PA6 offset math, PA7 role, PA10 header mapping, PA11 labels, PB5 width).
Fable after merge: live `--demo multi-4` / `multi-mixed` / `spend-states` captures in both appearances
via `.context/qc/preship-audit/capture.sh`, tune PA9 masses, Settings harness renders for PA5/PB2–PB4.
