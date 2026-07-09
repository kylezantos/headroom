---
target: Headroom Settings window (SettingsView.swift)
total_score: 21
p0_count: 1
p1_count: 4
timestamp: 2026-07-09T06-53-25Z
slug: sources-headroomapp-ui-settingsview-swift
---
Method: dual-agent (A: design-director review · B: make-interfaces-feel-better craft audit)

# Headroom Settings window — combined critique (2026-07-08)

Full plan with rendered "after" mockup: `.context/settings-audit/settings-ui-improvement-plan.html`

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Saved-key state invisible; credentialMessage far from row, never clears |
| 2 | Match System / Real World | 2 | "Window", "Fill tracks", "drains" — internal vocabulary |
| 3 | User Control and Freedom | 2 | Remove unguarded; Save wipes field even on failure (SettingsView.swift:369-372) |
| 4 | Consistency and Standards | 1 | Mixed materials (4 flat sections + 2 tiles at 2 widths + orphan toggle); 3 segmented widths; 2 help-text sizes; 2 button vocabularies; ... vs … |
| 5 | Error Prevention | 2 | Save enabled on empty field; no key sanity check |
| 6 | Recognition Rather Than Recall | 2 | Key state must be remembered; near-twin Spark toggles 2 sections apart |
| 7 | Flexibility and Efficiency | 2 | 5→30 min = 25 stepper clicks, no text entry |
| 8 | Aesthetic and Minimalist Design | 3 | Quiet tone; dimmed-field noise, mixed materials |
| 9 | Error Recovery | 2 | Typed reasons but unassociated, unannounced messaging |
| 10 | Help and Documentation | 3 | Help placed well; copy quality mixed |
| **Total** | | **21/40** | Acceptable — functionally sound, structurally inconsistent |

## Priority Issues

- **[P0] One window, three material systems** — 4 flat sections vs 2 raised tiles (at 2 widths) vs orphan "Launch at login". Fix: settingsPanel() on every section, maxWidth .infinity, padding 12→13, delete scroll insetHairline()s, VStack spacing 14.
- **[P1] Hierarchy collapses** — 13pt semibold headers vs 13pt regular labels; weight-only. Fix: headers inside tiles + kerning(-0.2); help unified 11pt secondary.
- **[P1] Four alignment grammars / three segmented widths** — Theme 280 / Window 200 / Period unconstrained; Fill tracks left-inline. Fix: one responsiveControlRow rule, shared maxWidth 220, switches for masters.
- **[P1] Credential state invisible + Save eats key on failure** — Fix: "Key saved" chip (Connected-chip recipe), Save→Update, Remove-with-confirm, success-only clear, transition + 4s auto-dismiss + a11y announcement.
- **[P1] IA drift** — Launch at login → General; parallel Spark toggle rows; Period after provider toggles.
- **[P2] Two button vocabularies** — Save/Remove HoverButtonStyle vs native footer. Fix: .bordered .small for field-adjacent commits.
- **[P2] A11y** — Picker("Appearance") announced for visible "Theme" label (SettingsView.swift:129); .secondary under opacity(0.4) sub-floor contrast; silent saves.
- **[P2] "Check for Updates..."** — ASCII ellipsis; permanently disabled by default. Fix: "…" + hide when unavailable.

## Craft audit (make-interfaces-feel-better)

Fails: tabular nums (Stepper :115 lacks monospacedDigit), hit-area overlap (Save/Remove 8pt apart, 7pt extensions; ≈38pt tall), credentialMessage hard pop (no transition), doubled separation (hairline between two tiles :213), hairline asymmetry (leading 6/trailing 2), help text 11pt vs 10pt .caption split, "Minimum 2 min." orphan.
Keeps: header icon outline exact-spec, apiSpendPeriodSwap motion, HoverButtonStyle 0.96 press mechanics, no entrance choreography, RaisedTile, privacy instincts.

## Persona Red Flags

**Alex:** 25 clicks for 5→30 min; "Window" decode pause; re-pastes key "just in case" (no saved state); hunts for launch-at-login.
**Sam:** VoiceOver "Appearance"≠"Theme"; sub-floor contrast on dimmed cluster; silent save; hover-only affordance on Save/Remove.

## Direction

"The popover, but editable" — every section a RaisedTile(.opaque) 13/10, headers inside, one row grammar, credential state chips, menu-bar live preview, provider logos, version stamp in header.
