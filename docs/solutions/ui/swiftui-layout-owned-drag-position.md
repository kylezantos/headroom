---
title: Let a custom SwiftUI Layout own a dragged item's position — never hand over from .offset
date: 2026-09-24
category: ui
module: HeadroomApp/MenuBarPillArranger
problem_type: ui_bug
component: frontend
symptoms:
  - A dropped pill card restarted part-way back toward its origin, then sprang into its slot
  - A card dropped into the other row snapped back and a faded ghost appeared in the slot
  - After a two-step re-anchor, the card vanished for a frame and flew in from a far corner
  - The receiving row resized twice and its drop ring and empty-row message snapped at the commit
root_cause: async_timing
resolution_type: code_fix
severity: medium
tags: [swiftui, layout, drag-and-drop, animation, offset, transaction, menu-bar, settings, macos]
---

# Let a custom SwiftUI Layout own a dragged item's position — never hand over from .offset

## Problem

The Settings → Menu Bar pill shelf (PR #139) drags cards within and between two rows that one
custom `Layout` places. Every version that moved the dragged card with an `.offset` layered over
the layout's placement jumped on release, and each fix only changed the shape of the jump. It
took four attempts; the fix was to stop using an offset for the dragged card at all.

## Symptoms

- On release the card restarted part-way back toward where the drag began, worse the longer the
  drag, then sprang into the slot.
- Dropping into the other row: the card snapped back toward its origin while a faded copy
  appeared at the slot.
- With a re-anchor plus compensating offset: the card vanished for a frame, reappeared at a far
  corner (above-right going up, below-left going down), then dropped in.
- The receiving row grew then shrank, and the drop ring and "All providers shown." snapped.

## What Didn't Work

1. **Commit on release in one transaction (SM3).** The store reordered, so the layout moved the
   card's slot from origin to drop, while the pointer offset animated back to zero. The two were
   supposed to cancel along the whole path. In the live app they did not.
2. **Keep the offset, commit after landing, but swap view branches at the commit (PS5/PS6).** The
   shelf card and the menu-bar card were `if/else` branches, so the row change built a new view.
   SwiftUI gives an inserted view no "from" geometry: it appears at its final place while the
   removed one fades along a different path — the snap-back plus ghost.
3. **Re-anchor to the drop slot with a compensating offset, then start the flight in
   `DispatchQueue.main.async` (PS7).** The design needed one rendered frame between the two
   updates. SwiftUI coalesced both into one update, so the offset animated from the old pointer
   offset while the slot jumped: the card started at *drop slot + pointer offset*, a far corner.
4. **Fly, commit with animations disabled, then morph.** The commit put the old card form in the
   new row, so that row snapped to fit it and then animated back; the ring and row messages
   changed inside the disabled transaction and snapped.

## Solution

The layout places the dragged card itself, so its position has exactly one source.

- **While dragging,** the arranger passes `pointer: (id, offset)` into `PillShelfLayout`, which
  places that card at its origin slot plus the travel (`let travel = pointer?.id == id …` in
  `PillShelfLayout.frames`, `Sources/HeadroomApp/UI/MenuBarPillArranger.swift`). Pointer updates
  are plain state writes, so placement follows the pointer 1:1 without animating.
- **On release,** `land(_:at:commit:)` runs one `withAnimation(dragSettle, completionCriteria:
  .removed)` that clears the pointer and anchors the card at its drop slot
  (`PillShelfModel.slots(…, holdsOrigin: false)`). SwiftUI animates the subview from where it was
  last placed — the pointer position — to the slot. The card's form and both rows' heights change
  in the same transaction.
- **After it lands,** `commitLanding()` writes the store. The pending arrangement equals the
  committed one (pinned by `aLandingCardIsAnchoredWhereTheCommitPutsIt` in
  `Tests/HeadroomAppTests/MenuBarPillArrangerTests.swift`), so no card moves. The commit is
  dropped if the rows changed mid-landing (a +, ×, arrow, or mode change), and it runs on
  `cardMorph` rather than disabled, so mode-dependent chrome eases instead of snapping.
- **The card is one persistent view** (`pillCard(_:inMenuBar:)` in
  `Sources/HeadroomApp/UI/SettingsPanes.swift`). Its row-specific parts transition in and out
  around a pill and name that stay put; both surfaces are always present and trade opacity over
  an opaque base, because two translucent layers crossing at 50% let the background flash through.
- **Reduce Motion** commits immediately; there is no animation to wait on.

The release sequence is written as a storyboard comment on `land` in `MenuBarPillArranger.swift`.

## Why This Works

SwiftUI already animates a subview's *placement* change inside an animated transaction — that
is how neighbouring cards glide aside during a drag. Routing the dragged card through the same
mechanism means release is one continuous change of one value. Every failed version split the
card's position between placement and `.offset` and relied on a handover between them: two
animations cancelling, a view identity surviving a branch swap, or two state updates rendering
in separate frames. None of those is guaranteed; SwiftUI coalesces updates in the same run loop
and gives freshly inserted views their final geometry.

## Prevention

- In a custom `Layout`, give the dragged item's position to the layout (a pointer/translation
  input), not to an `.offset` on the subview. Release = change the layout inputs inside one
  `withAnimation`.
- Never depend on `DispatchQueue.main.async` (or `Task.yield`) to get a rendered frame between two
  SwiftUI state changes. If a design needs a frame boundary, redesign it.
- Keep an item that changes form one view: toggle its parts with transitions, crossfade surfaces
  with opacity, and never switch `if/else` branches for the whole item mid-motion.
- Commit to the model *after* the animation (`completionCriteria: .removed`), and make the
  pending arrangement provably equal to the committed one with a pure-model test.
- Diagnose motion bugs from frames, not descriptions: `ffmpeg -i clip.gif -vsync 0 f%03d.png`,
  then tile a crop with `-vf "crop=…,scale=500:-1,tile=3x4"`. Frames 20–23 of one recording
  showed exactly where the card vanished and where it reappeared.
- `swift run Headroom --demo multi-4` runs the same pane and arranger code as the real build with
  fixture data; a mismatch between them is not the explanation for a motion bug.

## Related Issues

- PR #139 (the shelf and this fix); PR #137 (the per-limit data model it builds on).
- `docs/solutions/popover-scrollview-zero-height.md` — the other SwiftUI-in-AppKit layout trap in
  this app (scroll views with no useful ideal height).
- `docs/plans/2026-09-04-002-feat-subtle-motion-system-plan.md` — the SM1–SM3 motion vocabulary
  the drag springs come from.
