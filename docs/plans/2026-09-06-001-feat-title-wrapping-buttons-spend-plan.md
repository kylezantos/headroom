# Round 2 — account title, text wrapping, quiet buttons, action placement, API spend card

Source: Kyle's picks on `design/round2-title-wrapping-buttons-spend-options.html` (built against
`cd596717`, 2026-09-06), pasted back from the doc's "Copy answers" export, plus Kyle's Paper
mock of the account title (`.context/attachments/vfZtLz/…`, measured at 1 Paper unit = 1pt).
Decision anchors (`T1A`, `W2A`, `B3A`, `P4C`, `S5A`) are the WHY citations for code comments.
Inventories with file:line cites: `.context/round2-inventory.md`, `.context/motion-inventory.md`
(not committed).

## Decisions

| Anchor | Item | Decision |
|---|---|---|
| T1A | Account title | Kyle's Paper: title stays 15pt, weight **semibold → medium**, kerning −0.15 kept, ink → the new `accountTitle` token (dark #68707A measured, light #6B7280 derived); plan pill vertical padding **1 → 3** (≈16pt tall); account sections **22 → 26**. Kyle's note: **tighten the spacing between meter rows "just a bit"** inside each account — Micro row spacing **12 → 10** (`ProviderCardView.swift:651`); Full stays 9; identity → meters stays 7. Everything else unchanged. |
| W2A | Text wrapping | Measure + glue + trim. (1) `SettingsHelpText` gets `.frame(maxWidth: 460, alignment: .leading)` so a help line holds ~75 characters and the 640 cap can't stretch it into an orphan. (2) Fixed strings with a two-word tail get `\u{00A0}` glue (precedent `SettingsPanes.swift:73-74`). (3) The ten offenders are rewritten (exact strings below). There is no balanced-wrap API on macOS; do not add an `NSTextView` bridge or touch `avoidsOrphans`. |
| B3A | Quiet buttons | `SetupChipButtonStyle` is the one secondary button for every text-labelled action inside a card or tile: `.regular` (12.5 semibold, h13/v6, r8) at a card foot, `.small` (11.5 semibold, h10/v4, r7) inside account rows and Settings rows. `HoverButtonStyle` remains only for glyph controls (gear, copy, `+`, trash, reset, `…`) and the footer Refresh/Quit. Native `.bordered` stays for Settings-row primaries. Kyle's note: **no ellipsis in the key CTAs** — `Add key`, `Replace key`, `Fix key` in both the popover and Settings (`SettingsPanes.swift:625`). Leave `Add Account…` and `Check for Updates…` alone. |
| P4C | Where actions sit | Card foot, trailing. Every action a card offers collects in **one trailing-aligned row at the bottom of the card** (single-account) or at the bottom of the account section (multi-account), 8pt above it, 8pt between chips, primary chip last (trailing-most). Messages keep their own line and may wrap; nothing sits at the trailing end of a sentence line any more. The popover footer (Refresh/Quit) is unchanged. |
| S5A | API spend card | Same language as the provider cards: every spend row is an identity row — 15pt mark on the content axis (13 / 34 / 34), name 15 medium in `accountTitleInk`, period as a plan-style capsule chip ("September" / "Remaining balance"), amount 18 semibold monospaced in a **reserved column** sized to "$0,000.00" with the `numericText` roll, state tags as capsules (Stale-tag recipe; warning/critical use the Low-chip recipe with the tone's text ink @0.16), message wraps (no `lineLimit(1)`), CTA is a regular chip at the card foot (P4C), rows separated by the 22pt account gap, no divider, no eyebrow. Kyle's notes: **the xAI balance row's amount aligns in the same column as every other amount** (one line, never a second line); **drop the "remaining" word on macOS** (the "Remaining balance" chip already says it; the string stays in Core for widgets and iPhone); **the `+` top-up glyph sits to the right of the amount and the amounts still align** — so the `+` lives in the 21pt trailing inset gutter (`IdentityRowMetrics.contentTrailingInset`), reserved as an 18pt slot on every row and drawn only where `addCreditsURL` exists. Card gets `.transition(.settingsReveal)` and the M1A/M4A motion (amount roll on `valueSpring`, freshness crossfades). |

### W2A rewritten strings (exact)

| # | Ships today | Rewritten |
|---|---|---|
| 1 | `Sends only the widget-safe usage snapshot through your iCloud account. No provider credentials are synced.` (`WidgetSettingsSection.swift:26`) | `Sends only your usage numbers through iCloud. Sign-ins are never synced.` |
| 2 | `In the Terminal that just opened, choose the option below — Headroom connects the moment you approve.` (`ClaudeSetupViews.swift:386`) | `Choose the option below in Terminal. Headroom connects as soon as you approve.` |
| 3 | `Finish signing in, then approve the workspace if asked` (`ClaudeSetupViews.swift:341`) | `Sign in, then approve the workspace if asked` |
| 4 | `Come back — your usage appears here automatically` (`ClaudeSetupViews.swift:343`) | `Come back — usage appears here automatically` |
| 5 | `Claude Code location couldn't be confirmed — usage will retry` (`ProviderCapabilityPresentation.swift:8`) | `Couldn't confirm where Claude Code is — will retry` |
| 6 | `Codex sign-in data is not stored privately — reconnect` / `Grok …` (`ProviderSetup.swift:43`, `:52`) | `Codex sign-in isn't stored privately — reconnect` / `Grok sign-in isn't stored privately — reconnect`, tail glued `privately\u{00A0}—\u{00A0}reconnect` |
| 7 | `Controls the menu-bar number and widget tiles. Auto uses the tightest menu-bar limit; widgets use the first 2 enabled providers.` (`SettingsPanes.swift:235`) | `Sets the menu-bar number and widget tiles. Auto picks the tightest limit; widgets show the first two enabled providers.` |
| 8 | `Approve Headroom's Claude workspace in the official CLI` (`ProviderSetup.swift:37`) | `Approve Headroom's workspace in the Claude CLI` |
| 9 | `Codex stored this login somewhere Headroom cannot read` (`ProviderSetup.swift:47`) | `Codex saved this login where Headroom can't read it` |
| 10 | `Sign in through the official Claude CLI to show this account's usage.` (`ClaudeSetupViews.swift:300`) | `Sign in with the Claude CLI to show this account's usage.` — and add the missing `fixedSize(horizontal: false, vertical: true)` |

Core strings (5, 6, 8, 9) are shared with the iPhone mirror and widgets; the rewrites keep
meaning, so the shared surfaces simply get the shorter copy. Tests that assert the old literal
text are updated to the new literal, never loosened.

## Contract (already on the branch)

- `SetupChipButtonStyle(size: .regular | .small)` in `ClaudeSetupViews.swift` — the B3A chip.
- `HeadroomWidgetColorValues.accountTitle(dark:)` and `ProviderStyle.accountTitleInk(scheme:)` —
  the T1A ink. No other new colours; no new motion tokens (use `HeadroomMotion` as is).

## Workstreams (parallel, file-owned)

- **R2 Wrapping** — `SettingsRows.swift` (the 460 measure on `SettingsHelpText`),
  `WidgetSettingsSection.swift`, `SettingsPanes.swift` (**only** the `:235` help string and the
  `:625` `Replace key…` → `Replace key` label), `ProviderSetup.swift`,
  `ProviderCapabilityPresentation.swift`, and any Core/App tests asserting those strings: W2A
  rows 1, 5, 6, 7, 8, 9; B3A's ellipsis note for Settings.
- **R3 Cards** — `ProviderCardIdentityRows.swift`, `ProviderCardView.swift`,
  `ClaudeSetupViews.swift` (everything except the chip contract already there),
  `CodexSetupViews.swift`, `AccountsSettingsTile.swift` (secondary recovery + "Show CLI Account"
  → small chip): T1A (title, pill, section gap, Micro row spacing), B3A + P4C across every card
  and account section, W2A rows 2, 3, 4, 10.
- **R4 Spend card** — `APISpendSectionView.swift`, `APISpendPresentation.swift` (drop the
  ellipsis from `Add key…` / `Replace key…` / `Fix key…`; keep `remaining` in Core), `PopoverView.swift`
  (**only** the spend card's `.transition(.settingsReveal)` at `:97`): S5A with all three of
  Kyle's notes, using the B3A regular chip at the card foot (P4C).

R2 and R4 both touch `SettingsPanes.swift` / `APISpendPresentation.swift` regions that don't
overlap (`:235` vs `:625` are R2's; the CTA strings are R4's) — keep hunks apart. R3 owns the
chip style file but must not change the contract's API.

Out of scope: widgets and iOS layout (strings flow through unchanged), the Settings API Spend
pane beyond the ellipsis, `HoverButtonStyle` itself.

## Acceptance

`swift build`, `swift test`, and the `HeadroomAppTests` xcodebuild scheme pass on the merged
branch. Visual acceptance in the live `MenuBarExtra` window: `swift run Headroom --demo multi-2`
(T1A, S5A live rows), `--demo multi-mixed` (P4C action rows on stale accounts), `--demo
capability-failure` (P4C on the recovery card), both appearances. The stale and balance spend
rows have no fixture; review them against the doc's mock. Settings › Widgets & iPhone and
General at both the default window and past 1080pt wide for W2A.
