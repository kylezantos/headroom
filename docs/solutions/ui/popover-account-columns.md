---
title: "Popover columns: plan on close, fit the window yourself, measure inside layout"
date: 2026-10-11
category: ui
module: HeadroomApp/PopoverView
problem_type: design_pattern
component: frontend
symptoms:
  - "A 750pt MenuBarExtra popover never shrinks back to 384pt: the content draws centred in the old width with stray shadow edges"
  - "A width chosen when the popover opens shows the previous width for about 116ms first"
  - "A geometry reader on every account section cost about 90ms per open at the 20-account envelope"
root_cause: framework_behavior
resolution_type: code_fix
severity: medium
framework_version: "swiftui macos 26 (Xcode 27 / Swift 6.4 toolchain, MenuBarExtra .window)"
related_components:
  - MenuBarExtra
  - AccountColumnsPlanner
  - PopoverPlanModel
tags: [swiftui, menubarextra, window-sizing, layout, measurement, popover, columns]
---

# Popover columns: plan on close, fit the window yourself, measure inside layout

## Context

The popover account layout plan (`docs/plans/2026-10-10-0836-feat-popover-account-layout-plan.md`)
lets the popover add a second column (384pt → 750pt) once one column of provider cards would pass
the 640pt cap. The column count must not change while the popover is open because data loaded
(R6). A throwaway spike (U1, 2026-10-11) drove the real `MenuBarExtra` window with an env-gated
width and sampled its frame every 8ms with `CGWindowListCopyWindowInfo`.

## What the spike found

1. **Anchoring.** The window's left edge sits on the status item's left edge and the window grows
   rightward. When it cannot fit to the right, AppKit right-aligns it to the status item's right
   edge instead.
2. **Growing works, shrinking doesn't.** 384 → 750 resizes the window in place. 750 → 384 never
   does: the content shrinks and draws centred in a 750pt window, with the old shadow showing at
   both sides, and the wide window survives close and reopen.
3. **The view outlives a close.** The same `@State` and the same `NSWindow` come back on every
   open; `onAppear`/`onDisappear` fire per open and close.
4. **A width set on open is late.** Setting it on the next runloop turn after `onAppear` showed
   the old width for ~116ms first.

## What the popover does

- **Plan when the popover closes.** `PopoverPlanModel.popoverDidClose()` bumps the generation and
  replans from the heights just drawn, so the next open already has the right width. A first open
  after launch, an account-set change, and a layout change still plan after one measuring pass.
- **Fit a narrower window explicitly.** `PopoverView.fitPopoverWindow(columns:)` sets the window
  frame's width (left edge kept, shadow invalidated) when the plan narrows — on close, while the
  window is hidden, and on a narrowing while open. Widening is left to `MenuBarExtra`.
- **Measure inside layout, not with geometry readers.** Account heights come from
  `ColumnItemsStack`, a leading `VStack` replacement that reports each subview's height as it
  places it. Those sizes are already computed, so the report is free; an `onGeometryChange` per
  account section cost ~90ms per open at multi-20. Whole single-account cards and the spend card
  (a handful) still use `onGeometryChange`.
- **A layout change keeps the heights.** It opens a new generation instead. Clearing them
  stranded the plan: `onGeometryChange` views report only when their height changes, so the
  unchanged spend card never reported again and the replan waited forever (code review #1).
- **Keep heights out of observation.** The model stores heights in `@ObservationIgnored`
  properties and publishes only the `Equatable` plan, only when it changes. A replan completed by
  a height reported from inside layout runs on the next main turn, never during the pass.
- **Carry the plan across an account-set change.** `AccountColumnsPlanner.carried(_:to:)` keeps
  two columns (column 1 starting at its first surviving item) while new accounts wait to be
  measured. It is drawn, never stored: it carries the old generation under new IDs and would pass
  for an already-made plan.

## Measuring it

`--bench-ui popover` builds a fresh hosting view for every open, so each of its warm opens takes
the first-open path (one column, measure, then two columns). At multi-20 that path adds a root
pass and ~100ms of post-open CPU over a one-column popover; in the app, where the view survives
reopening, it happens once per launch. Open (sync) CPU is at or below the one-column baseline.

## Related

- `docs/solutions/ui/menubarextra-window-closures-run-in-app-body.md` — keep the plan and the
  preference reads in `PopoverView`, never `HeadroomApp.body`.
- `docs/solutions/ui/popover-feather-animation-scope-grew-card-list.md` — no implicit animation on
  the container whose width or height is pinned.
- `docs/solutions/ui/popover-scroll-geometry-state-rerendered-whole-popover.md` — why per-item
  geometry must not reach root `@State`.
