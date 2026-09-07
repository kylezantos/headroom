# Round 3 — state blocks, buttons, spend rows

Source: Kyle's picks on `design/round3-state-blocks-buttons-spend-options.html` (built against
`b62e060a`, 2026-09-06), pasted back from the doc's "Copy answers" export. Decision anchors
(`G1A`, `S2B`, `B3`, `R4A`, `X5`, `C6A`) are the WHY citations for code comments. Inventory with
file:line cites: `.context/round3-inventory.md` (not committed).

## Decisions

| Anchor | Item | Decision |
|---|---|---|
| G1A | Title grey | `accountTitle` token → dark **#7B838D**, light **#5F6771** (light derived). Kyle's notes: **weight back to semibold** (T1A's medium lost the row's anchor on a recessive grey); and **the brand tint becomes a user choice** — a new `AccountTitleInk { neutral, brand }` preference (UserDefaults `accountTitleInk`, default neutral) mirrored on `UsageStore`, exposed as "Account names: Neutral / Brand" in Settings → Appearance → In-app display, previewed by `AppearanceSpecimen`, delivered to the popover through an environment value. `.brand` is `ProviderStyle.textAccent`, the tint the widget headers already use. Popover-only, like `MeterStyle`. |
| S2B | The status line | Colour does the work. All five status glyphs go (`terminal` ×2, `person.crop.circle.badge.exclamationmark`, `exclamationmark.triangle.fill` ×3). Every status line is one `StatusSentence`: 11.5 medium, on the 34pt content axis, trailing inset 0, wraps freely (no `lineLimit`). Ink from one `StatusSentenceSeverity` table — attention → `severityColor(.low)`, critical (provider/OS refusals, failed handoff) → `criticalText`, progress (waiting rows) → `.secondary`. The waiting spinner takes the 15pt mark slot. The identity-line `Stale` tag survives only because a transient-stale row renders dimmed meters with no sentence. |
| B3 | Buttons | Kyle picked no option: **"left aligned with the icons."** So: `CardActionRow` is leading-aligned at the mark column (13pt from the card edge), primary chip first, 8pt between chips, wrapping to a second leading line via `ActionChipFlow` (chips never shrink, labels never truncate). Everything else from the brief stands — every popover chip `.small`, no icons inside chips, sentence case for Core labels ("Check now", "Open Claude setup", …), `ProviderSetupRecoveryCard` drops `.borderedProminent`. |
| R4A | Vertical rhythm | 6 / 12 / 13 — title → sentence 6, sentence → action row 12 (`CardActionRow.topPadding` default), action row → card bottom 13 (the card's own padding, no exception). Exactly the 2× grouping rule. |
| X5 | The stale spend row | Kyle picked no option ("none of this looks good") but asked for **the rejected pill in line with the service title** and asked whether the empty space was real. It is: with `amount == nil` the 91pt column + 3pt gap + 18pt slot were reserved and empty. Built: the state tag replaces the period chip beside the title (short forms in Core — "Rejected", "Setup", "Denied", "Stale"; full `badge` strings unchanged for widgets/phone); a nil amount **collapses** the column and slot; a retained amount keeps the column in `.secondary` and withholds the `+` on key problems; the sentence follows S2B ink at 34 → 13; the action row is `CardActionRow` with `.small` chips; "Cursor on-demand" renders as "Cursor" + "On-demand" chip (popover only, `popoverIdentity`). `spend-states` now poses the nil-amount row; `spend-retained` poses the retained-figure shapes. |
| C6A | Capsule height | Everything 18pt, exactly — one `identityCapsule(fill:horizontalPadding:)` modifier (`fixedSize` + `frame(height: IdentityRowMetrics.capsuleHeight)`) on the plan pill, period chip, state tags, Stale tag, Low chip and Connected chip. Vertical padding was not tuned per font because SwiftUI line boxes differ from the doc's browser maths. |

## Workstreams (parallel, file-owned)

- **A · G1** — `BrandColorValues.swift`, `UsageModels.swift`, `Preferences.swift`,
  `UsageStore.swift`, `ProviderStyle.swift`, `PopoverView.swift`, `AppearanceSpecimen.swift`,
  `SettingsPanes.swift`, `SettingsView.swift`, the `titleText` view in
  `ProviderCardIdentityRows.swift`, `PreferencesTests`, `UsageStoreTests`.
- **B · State blocks** — `ProviderCardIdentityRows.swift`, `ProviderCardView.swift`,
  `UsageBarView.swift`, `ClaudeSetupViews.swift`, `CodexSetupViews.swift`, `ProviderSetup.swift`,
  `ProviderCapabilityPresentation.swift`, the `multi-mixed` fixture ("Studio" row poses
  `.claudeLoginRequired` for the two-chip foot), label tests.
- **C · X5** — `APISpendSectionView.swift`, `APISpendPresentation.swift`, the spend fixtures and
  the `spend-retained` scenario, `APISpendPresentationTests`.

## Acceptance

- `swift build` and `swift test` clean (721 tests).
- Live `MenuBarExtra` popover captured in both appearances for `multi-mixed`, `spend-states`
  and `spend-retained` (`.context/qc/round3-app/`, not committed).
- `AccountTitleInk.brand` accepted on code and tests only — see BUGS.md "Round-3 residuals".
