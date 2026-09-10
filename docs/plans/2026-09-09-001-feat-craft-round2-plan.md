# Craft round 2 fixes (2026-09-09)

Source: `design/craft-round2-options.html` (Kyle's answers, pasted 2026-09-09) built from
`.context/qc/craft-round2/report.md`, a five-reviewer audit of `origin/main @ e98b2ad7` (PR #114).
Work lands on top of `bcc5c9ad` (#115). Decision anchors (`R2M1`…`R2B4`) are the WHY citations
for code comments. Denied and deferred items are listed so nobody "fixes" them later.

Standing motion rules still apply (S2A, M-series): nothing loops or pulses, nothing exceeds
300ms, one cause one motion, Reduce Motion keeps crossfade timing and snaps movement. **No new
motion token in this round** — every motion item reuses `settle`, `quickSettle`, `pressDown`,
`hoverIn`/`hoverOut`, `valueSpring`, `reorder`, `pressScale`, always through
`HeadroomMotion.resolved(_:_:reduceMotion:)`.

## Decisions

| Anchor | Decision |
| --- | --- |
| R2M1 | **Setup-session state changes animate.** Second animation scope in the card keyed on a session key from `SetupSessions.state(for:)`: `.crossfade`/`settle` on the body, `.movement`/`valueSpring` on the tile, `.transition(.opacity)` on the single-account Group and the Stop Waiting row. Same two-scope split M4A uses. If the NSWindow height step looks wrong live, keep the crossfade and drop the height to `settle`. |
| R2M2 | **The popover freshens on open, but only when the timer was about to fire anyway.** On popover appear call `refreshNow()` only if the oldest live capture is older than the poll interval, then re-phase the cadence so the next tick is a full interval later. At most one extra poll per interval. Fix the `refreshNow()` doc comment so code and comment agree. |
| R2M3 | **The reset moment is answered, not missed.** (a) When any tracked window's `.scheduled` deadline falls inside the current interval, the next poll wakes at `deadline + 30s` instead of the fixed tick (same poll, moved). (b) `Countdown` never blanks: past the deadline it holds "now" until a fresh capture lands. Widgets read the same helper. |
| R2M4 | **Deferred (Discuss).** Kyle: a signed-in account never shows a Check Now chip. Correct — the chip exists only on setup/recovery rows (`ProviderCardIdentityRows.swift:527, 572`, `ProviderCardView.swift:366`). The per-account "Checking…" capsule half of M4 stands on its own; answered in the session summary, nothing built. |
| R2M5 | **The header status slot never goes silent.** Newest stale `observedAt` → "Last checked N min ago"; nothing ever → "Not checked yet"; refresh in flight with nothing live → "Checking…". Same 11pt tertiary treatment; digits keep the `numericText` roll. Phrase↔stamp changes are a view replacement (`.id` on "has minutes") inside a `.crossfade` scope on `settle`, beside the existing `.movement` scope. |
| R2M6 | **Settings swatches get hover and press.** One `SettingsSwatchButtonStyle` beside `selectionChrome`: hover fill `primary.opacity(0.05)` + hairline `primary.opacity(0.14)` (selected swatch deepens the accent fill 0.08 → 0.12 instead), `hoverIn`/`hoverOut`; press `pressScale` on `pressDown`/`settle`; no hover scale; disabled Tube opts out. The selection ring animates on `settle`, not `pressDown` (folds R2B4's second row). Reduce Motion: fills keep timing, scale drops. |
| R2M7 | **Every animation site goes through `HeadroomMotion.resolved`.** The nine `reduceMotion ? nil : token` sites route through the resolver; the two mixed sites split into `.movement` (chevron + height) and `.crossfade` (revealed block); `SettingsPanes.swift:71` moves to `pressDown` and `numericText(value:reduceMotion:)`. |
| R2M8 | **Keyboard: ⌘, opens Settings, ⌘R refreshes, the sidebar focuses on open.** `keyboardShortcut` on the gear and on Refresh; `@FocusState` on the sidebar list. Leave ⌘Q/Esc alone until verified on device. Keyboard-initiated actions do not animate. |
| R2M9 | **Copy → check.** Glyph `doc.on.doc` → `checkmark` inside the fixed 22×22 slot, crossfade on `settle`, hold 1.2s, crossfade back, via `withAnimation` + a sleeping `Task` (never `asyncAfter`). Only after a successful pasteboard write; accessibility label carries the state. All three sites (Claude setup, Codex setup, card copy button). |
| R2M10 | **The rename field's hover fill animates** on `hoverIn`/`hoverOut` as `.crossfade`. |
| R2M11 | **Denied.** The menu bar dot keeps its permanent-failure trigger only. |
| R2M12 | **The waiting header carries a clock.** While a setup card is the header's source, the slot reads "Waiting 45s" (elapsed, rolling on `numericText`) instead of echoing the card title; other live providers keep "Updated N min ago". |
| R2M13 | **One tooltip chrome (Proposed A).** Delete `delayedHelp`; the spend `+` uses `.help(_:)`. |
| R2C1 | **Dark cards lit from above (Proposed B).** Dark only: rim gradient ends in `Color.black.opacity(0.22)` (top stays `white 0.20`); shadow becomes `black.opacity(0.6), radius 10, y 3`. Light unchanged. |
| R2C2 | **Identity → first meter gap set in ink.** `spacing: 6 → 2` in both formats (≈10 vs 17.5pt ink Micro, 9.5 vs 15 Full); the 26pt account gap stays. Prefer an `OpticalStacking.gap` helper beside `OpticalCentering` if the measured value can be derived; a literal with the ink measurement in the comment is acceptable. |
| R2C3 | **Denied**, then partly forced by R2C8: the `"$0,000.00"` reservation had to become a measured width once the suffix landed (see R2C8). Alignment to the percentage column falls out of the shared suffix slot. |
| R2C4a | **Light Low fill above healthy.** `lowFill(dark:false)` → `oklch(0.660 0.166 58.3)` = `rgb(0.856, 0.450, 0.000)`. Test asserts low > healthy in |Lc| in light. |
| R2C4b | **Dark cap below critical.** `tickGlassCap(dark:)` 0.52 → 0.42; `criticalFill(dark:)` → `oklch(0.740 0.190 28.1)` = `rgb(1.00, 0.448, 0.389)`. The test exemption becomes an assertion: dark body < cap < critical < healthy < low. |
| R2C5 | **The sign-in sentence is neutral.** `StatusSentenceSeverity.attention` → `ProviderStyle.meterLabelInk`; `.critical` keeps `criticalText`. Both the identity-row sentence and the spend sentence. |
| R2C6 | **One verb: sign in.** Status sentences: "Sign in with the official Claude CLI" / "…Codex CLI" / "…Grok Build CLI" / "…Cursor Agent CLI"; re-auth "Sign in again with the official Codex CLI". Buttons: **Sign In** first-time, **Sign In Again** re-auth; retire Connect Codex/Grok/Cursor, Reconnect *, Connect with Codex, Connect Claude. Header: "Sign in to Claude to begin" / "Sign in to Codex to begin" / "Sign in to Codex again". Settings row status = the popover sentence, not "Needs sign-in". Setup card title "Sign in to Claude" in both branches. |
| R2C7 | **Capability copy states the cause; the button names the act.** "Headroom can’t find the Claude Code CLI on this Mac" / "Codex CLI isn’t installed on this Mac" / Grok / Cursor. With retained data on screen: "… — showing the last reading." |
| R2C8 | **Spend amounts carry their direction as a meter-style suffix (Kyle's Discuss direction).** "$58.90 **used**" / "$58.90 **left**" — Kyle (2026-09-09): "used", not "spent", so API rows match the meters — with the suffix rendered exactly like the meters' suffix (same font, ink, suffix column); the period capsule stays. Surface the existing `"left"` term on macOS instead of dropping it. **Post-merge (Fable):** the fixed `"$0,000.00"` reservation plus the suffix truncated every spend title in the live capture, so the amount column now measures the widest total the card shows (floor `"$0.00"`); amounts keep one right edge. This is the half of C3 the truncation forced, flagged for Kyle. **Open, not built:** moving the `+` to the left of the amount / hover-only — S5A's gutter stays until Kyle decides. |
| R2C9 | **Preview well radius is a parameter.** 16 for the Appearance specimen, 20 for the widget strip, 14 for the menu-bar strips. |
| R2C10 | **Denied.** A multi-account card stays account-label-only; the mark carries the provider. |
| R2C11 | **Popover grouping denied; action row alignment approved (Kyle).** Each account keeps its own sentence and buttons. The account action-button row is **leading-aligned to the account title's text axis**, and the row's max width runs to the trailing edge of the usage rows, so the buttons sit inside the same left/right bounds as the meters. Settings: the status stays pinned in the trailing column whether there are one or two buttons; only the buttons drop to the second line. |
| R2C12 | **Fill names, spelling, ramp.** Labels: Solid → **Always colored**; Color as event → **Only when low**; Hue ramp → **Fade**; Glass + cap → **Glass**; Ghost + cap → **Ghost** (raw values unchanged). Help: "Only when low keeps meters neutral until usage runs low. Glass and Ghost add a bright end cap." American spelling. `rampStops` interpolates in OKLCH at fixed hue (light amber start `oklch(0.775 0.124 58.3)`, midpoint `oklch(0.738 0.145 58.3)`). |
| R2C13 | **Monochrome marks capped at ~86% ink.** `grok-*`/`cursor-*` render at dark ≈ `#C9CDD4`, light ≈ `#3A3D42`. `massCorrection` untouched. |
| R2C14 | **Critical countdown steps up.** At `.critical` and live only, the countdown uses `.secondary`-strength ink; size, position, digits unchanged. |
| R2C15 | **Critical track is tinted.** At `.critical` only, `barTrack` → light `oklch(0.905 0.045 28.1)` = `rgb(0.990, 0.836, 0.812)`, dark `oklch(0.391 0.055 28.1)` = `rgb(0.374, 0.226, 0.206)`. Rides the existing `valueCrossfade`. |
| R2C16 | **Stale hedges severity.** `.stale` fills keep their severity hue at `C × 0.35` (light Low → `rgb(0.731, 0.588, 0.482)`, dark critical → `rgb(0.759, 0.534, 0.502)`); `.unavailable` keeps full grey. Numeral dim unchanged. |
| R2C17 | **Two capsule families.** Metadata capsules (plan, period, measure) drop the fill, ink `planLabelInk`. State chips (Connected, Stale, Rejected) keep a kind-tinted fill; Stale gets a 1px `strokeBorder` at `secondary.opacity(0.35)` and `.secondary` ink. The 0.18 stale fill becomes one named constant shared by the card and spend views. |
| R2C18 | **Brand ramps in one place.** `BrandColorValues.swift` holds two constant-hue OKLCH ramps at the artwork's hues (Claude H 38.8°: accent 0.672, textAccent light 0.556 / dark 0.734, CTA light 0.575→0.530, dark 0.560→0.515; Codex H 271.5° likewise, dark top 0.611→0.565). `connectedInk` is a documented L-offset from `healthy`. `flatSeverityColor`'s 0.85/0.95 dims sit beside `segmentBodyAttenuation`. Settings tile wells stop reading `ClaudeSetupStyle.wellBackground`. White-on-CTA ≥ 4.5:1, asserted. |
| R2C19 | **Settings spacing scale.** `SettingsMetrics.headerToContent = 10`, `groupToGroup = 20`, `tileToTile = 28`, `labelToControl` stays 4/6; `MeterStyleTile` and `InAppDisplayTile` fold onto `SettingsTile`. |
| R2C20 | **Specimen at true width, centred.** The Appearance specimen card is `.frame(width:)` derived from `PopoverView`'s width/padding constants (346 today) and **centred** in the well (Kyle leaned centred; leading-aligned is a one-line swap if it reads wrong). |
| R2C21 | **One control language in Accounts.** `.menuIndicator(.hidden)`, ellipsis at `.regular`, and the Menu label wrapped in the same 8pt hit padding + hover pill the glyph buttons use. |
| R2C22 | **Capability card stamps the mark once.** `showsMark: Bool = true` on `IdentityRow`, `false` for nested account rows (slot reserved); nest as `VStack(spacing: 26) { VStack(spacing: 10) { identityRow; recoveryView }; accountsStack }`. |
| R2C23 | **Shorter, non-linear scroll feather.** 14pt with stops 1.0 → 0.55 → 0.0; top feather stays symmetric (L3A). |
| R2B1 | Writing nits, all rows: tile titles Meter Style / In-App Display via `SettingsTile`; "… Check Now, or reopen the official CLI."; one shared constant for "Not fetched while this provider is off"; "Continue…" → "Continue Setup"; "Waiting for Claude Code" → "Waiting for Claude Code…"; sidebar section Preferences → **App**; Remove Account gets `role: .destructive`; nbsp around em dashes across the whole `ProviderSetup` set; `qualified(_:for:)` → two explicit templates; release notes curly apostrophes, "Color account names" → "…titles", "Color as event" → "Only when low", and a curly-quote check in the release runbook; first run defaults `settingsPane` to `.accounts` when no account is signed in. |
| R2B2 | Layout/typography LOWs, all rows: `ProviderSetupRecoveryCard` status gets `.lineSpacing(2)`; Connect card `padding(.top)` → 6/12/12/20/12, body 12.5 regular lead + steps, 11 tertiary note, one 15/semibold kerning; Widgets help → one `SettingsHelpText`; sidebar identity block `padding(.horizontal, 12 → 10)` after reading live List metrics; Settings default height opens on a group boundary (~740–760, measure); `.unavailable` rows reserve the "left" suffix column with a fixture; sub-group header → `.textCase(.uppercase)` + 0.3 tracking; API Spend group children on the header's text axis. |
| R2B3 | UI LOWs, all rows: glyph hover pills 26×26 r8 (or `radius = min(w,h) × 0.30`); Connected chip check 9pt semibold; selection ring r11; sidebar glyph ink and `person`/`key` optical size checked live; spend `+` → `plus.circle` at the same size. |
| R2B4 | Motion LOWs: `land()` guards its completion with a generation counter (or reads the live value); `SettingsSelectionChrome` animates `isSelected` on `settle` (with R2M6). |
| D1–D13 | Unanswered; all are in the report's Decided table. No action. |

## Workstreams (file-owned, run in parallel)

Each stream builds and tests in its own worktree, commits on its own branch, and never edits a
file another stream owns except in the explicitly shared regions below. Public signatures shared
across streams do not change (add, don't rename). Anchors go in WHY comments.

**WS-A popover-cards** — owns `PopoverView.swift`, `ProviderCardView.swift` (all but the copy
button at ~1004–1018), `ProviderCardIdentityRows.swift`, `SetupSessions.swift`, `HeadroomApp.swift` (gear button
region only). Items: R2M1, R2M5, R2M8 (popover ⌘, ⌘R), R2M12, R2C2, R2C5 (identity sentence),
R2C11 (popover action row), R2C17 (both call sites incl. the two `APISpendSectionView` capsule
lines), R2C22, R2C23, R2B1 (`ProviderCardIdentityRows.swift:502`, `SetupSessions.swift:249`),
R2B2 (recovery card `lineSpacing`), R2B3 (Connected chip weight).

**WS-A2 meters-and-spend** — owns `UsageBarView.swift`, `APISpendSectionView.swift` (all but the
two R2C17 capsule lines), `HoverButtonStyle.swift`, `APISpendPresentation.swift`, `DemoFixture.swift`. Items: R2M13, R2C8, R2C14, R2C5 (spend
sentence), R2B2 (`.unavailable` suffix column + fixture), R2B3 (hover pill radius, spend `+`),
R2B4 (`land()` generation counter).

**WS-B core-engine** — owns `Sources/HeadroomCore/Engine/**`, `Countdown.swift`, the popover
`.task`/open region of `HeadroomApp.swift`, `Tests/HeadroomCoreTests/**` for those. Items: R2M2,
R2M3.

**WS-C settings** — owns `SettingsView.swift`, `SettingsPanes.swift`, `SettingsRows.swift`,
`SettingsSidebar.swift`, `MeterStyleTile.swift`, `InAppDisplayTile.swift`, `ThemeThumbnailPicker.swift`,
`AppearanceSpecimen.swift`, `AccountsSettingsTile.swift`, `AccountsSettingsInteractions.swift`,
`WidgetSettingsSection.swift`, `WidgetPreviewStrip.swift`, `SettingsPane.swift`, `Preferences.swift`,
`MeterStyle.swift` (display names / help only). Items: R2M6, R2M7 (Settings sites), R2M8 (sidebar
focus), R2M10, R2C6 (Settings rows, using the vocabulary above), R2C9, R2C11 (Settings silhouette),
R2C12 (labels, help, spelling), R2C19, R2C20, R2C21, R2B1 (Settings rows), R2B2 (Settings rows),
R2B3 (selection ring, sidebar glyphs), R2B4 (selection chrome).

**WS-D copy-and-setup** — owns `ClaudeSetupViews.swift` and `CodexSetupViews.swift` (all but the
brand-colour literal regions), `ProviderSetup.swift`, `ProviderCapabilityPresentation.swift`,
the copy button region of `ProviderCardView.swift`, `docs/release/**`.
Items: R2M7 (setup-view sites), R2M9, R2C6 (Core vocabulary + setup cards), R2C7, R2B1
(ProviderSetup, `qualified`, release notes + runbook), R2B2 (Connect card rows).

**WS-E colour-tokens** — owns `BrandColorValues.swift`, `UsageSeverityColorValues.swift`,
`ProviderStyle.swift`, `MeterGauge.swift`, `RaisedTile.swift`, `ProviderLogoView.swift`,
`Resources/BrandIcons/**`, `MeterStyle.swift` (`rampStops` region), the brand-colour literal
regions of the two setup views, `Tests/HeadroomCoreTests/BrandColorValuesTests.swift`. Items:
R2C1, R2C4a, R2C4b, R2C12 (OKLCH ramp), R2C13, R2C15, R2C16, R2C18.

## Verification

Per stream: `swift build`, `swift test`, new or adjusted tests for every Core/behaviour change
(R2M2 gating and re-phase, R2M3 wake time and "now", R2C4 ordering, R2C6 strings, R2C7 strings,
R2C8 suffix term, R2C12 ramp hue, R2C18 contrast, R2B2 unavailable fixture). Fable after merge:
`swift test`, live `--demo multi-4` / `multi-mixed` / `spend-states` / `capability-failure` in both
appearances, Settings harness renders, and a Reduce Motion pass left to Kyle.

## Addendum (2026-09-09, same session)

| Anchor | Decision |
| --- | --- |
| CMM1 | **Text chips take the CleanMyMac popover chrome** Kyle sent (`.context/attachments/07ExyT/…`): dark fill a step brighter (white 0.14 rest / 0.18 hover / 0.22 pressed), a top-lit 1px rim (white 0.42 → 0.28 → 0.06 top-to-bottom; light mirrors it subtractively 0.04 → 0.10 → 0.18), full-neutral dark label, squarer corners (r7 regular / r6 small, ≈0.27 × height) and 10/8pt side padding. One style, `SetupChipButtonStyle`, so every text button in the popover and Settings account rows changes together. |
| CMM2 | **Chip boxes align to the title axis.** Kyle: "the edge should be left aligned with the account title." `CardActionRow` insets by `labelInset` itself (no padding subtraction), so the chip's box edge, not its label, sits on the text axis; the trailing bound is likewise box-to-edge. Supersedes B3X's label-alignment overhang. |
| CMM3 | **Restrained chip chrome (supersedes CMM1's rim).** Kyle: "all the buttons are a bit too bright now … more restrained in a James McDonald way." Four quiet layers: fill white 0.07/0.11/0.15 (light black 0.04/0.07/0.10), a 1pt inset top highlight (white 0.12 dark / 0.70 light) masked to the top lip, a faint edge ring (white 0.08 / black 0.09), and a 1pt shadow (black 0.35 / 0.08). Dark label at 0.94 neutral. Radius and padding from CMM1 stay. |
| CMM4 | **Spacing ladder (Kyle, 2026-09-10, from `design/popover-spacing-pass.html` A′).** Supersedes R2C2. Identity row → meters `4` (≈14pt ink), identity row → sign-in sentence `6` (≈12.5pt ink), meter → meter stays `10` (≈19pt ink; the mock's "12" was Fable's error — the code was already 10), sentence → chip row `8` (≈11pt ink), account → account `26` unchanged. Title → plan label stays 6 (measured 6 live; the mock's "2" was a run-detection error). |
| CMM5 | **Spend rows share the meter rows' trailing columns.** The `+` sits 7pt to the *left* of the amount; amount on the numeral column, "used"/"left" in the suffix slot, the 21pt gutter empty. No slot reserved when a provider has no billing page. The period label is the three-letter month ("Sep"). Closes R2C8's open `+` question. |
| CMM6 | **Chip box outdent 1pt.** `CardActionRow` hangs the first chip's box 1pt outside the text axis: mechanically aligned within 0.5pt, a filled ringed box reads heavier than a glyph edge. |


| CMM7 | **The spend card takes the usage cards' rhythm** (Kyle, 2026-09-10: "match the usage cards on all of its spacing, margins, and padding"): rows 26 apart like accounts, same 13pt card padding, same identity-row recipe, same figure / suffix / gutter columns. |
| CMM8 | **Hover-only top-up glyph.** The bare "+" (PB12) reserves no width; it sits in an overlay 7pt off the amount's first digit and reveals only while the pointer is over the figure — scale 0.6 → 1 and a 6pt slide on `hoverIn`/`hoverOut` as `.movement`, fade as `.crossfade` (S2A). Hidden glyph takes no clicks. Supersedes CMM5's always-visible placement. |
| CMM9 | **Plan and period back in their own pill, Stale inline.** `identityMetadataLabel` is a filled capsule again (`secondary 0.12`, no ring); state chips keep fill + hairline. Stale / Connected sit right after the plan pill, leading-aligned, instead of at the row's trailing edge. |

| CMM10 | **Spend title = account title, verbatim** (size, kerning `−0.15`, `accountTitleInk`); the setup-card kerning had leaked in. The top-up glyph's hit frame is 22pt so its hover pill is whole; the hover area carries the standard `.help` tooltip ("Opens X billing to add API funds") so the reveal explains itself after the system delay. |

| CMM11 | ~~Suffix column sized to the terms on screen.~~ Superseded by CMM12 the same hour. Kyle: content rows are inset 34 on both sides, mark at 13 — the code already did that via the 21pt trailing gutter; the leak was the suffix column fixed to "used" while rows said "left". `PopoverView` injects `meterSuffixColumnWidth` from the percentage-mode term plus the visible spend rows' direction terms; other surfaces keep the widest-of-all default. |

| CMM12 | **No suffix column at all.** Kyle: "why can't the meter rows just be evenly gapped from the left edge and the right edge." The suffix takes its natural width and the row is trailing-aligned, so every row's last glyph lands on the 34pt axis. Rows printing the same word share a numeral edge (all meter rows, via the one percentage mode); a "used" spend row beside "left" meters has its numerals 8pt left of theirs, which Kyle prefers over a ragged right edge. |

| CMM13 | ~~Appearance specimen is a scene.~~ The strip lasted an hour — see CMM14. Left alignment stays. Kyle: left-align the preview with the tiles below, and put the pill "on a macOS menu bar". A 24pt strip in the live menu-bar tint bleeds to the well's top edge with the real `MenuBarLabel` at its leading inset; the popover card hangs 14pt beneath, leading-aligned at the well's 16pt padding. The "Follows the choices below." caption is gone. Supersedes R2C20's centring. |

| CMM14 | **No menu-bar pill in the Appearance well.** Kyle: "the stuff below only affects the card itself." The well holds the left-aligned popover card and nothing else; the Menu Bar pane keeps its own live strip. |
\n
| CMM15 | **The Appearance well hugs the card.** Kyle: "hug the card." The well is card width plus its 16pt padding, leading-aligned on the pane; the tiles below keep the full column. |

