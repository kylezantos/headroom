---
title: "macOS 15 popover header clipped: the host-chrome rounding masked the header's own views"
date: 2026-10-30
category: ui
module: HeadroomApp/PopoverView
problem_type: ui_bug
component: frontend
symptoms:
  - "On macOS 15 the popover title draws as \"Jsage\": the U's left and the e's right are cut"
  - "The header status line loses both ends; the gear draws as a ~5pt diamond"
  - "Card text, the footer and Settings render normally; macOS 26 is unaffected"
root_cause: framework_behavior
resolution_type: code_fix
severity: high
framework_version: "swiftui macos 15.7.7 (Xcode 27 / Swift 6.4 toolchain, MenuBarExtra .window)"
related_components:
  - MenuBarExtra
  - NSHostingView
  - PopoverHostChrome
tags: [swiftui, appkit, menubarextra, macos15, sequoia, corner-radius, masking, popover]
---

# macOS 15 popover header clipped by the host-chrome rounding

## Symptom

A macOS 15.0 user reported "The header 'Usage' is clipped". A macOS 15.7.7 VM (tart, headless)
showed it on 1.5.1 and on `main` after #195: the clipping was horizontal, not vertical. "Usage"
drew as "Jsage", the header status line ("Sign in to Codex to begin") lost both ends, and the gear
was a tiny diamond. It persisted across reopens and every account count. Evidence:
`.context/vm-repro/macos15/header-fix/` in the fixing worktree.

## Cause

PC1 in `PopoverView.configurePopoverWindow` rounds every leaf subview of the window's content view
to the shell's 22pt corner with `masksToBounds`, meant for full-window host backdrops that an
unbundled `swift run` leaves behind. On macOS 15 the `NSHostingView` keeps parts of the SwiftUI
content as its own direct, childless subviews: the title is a 60×21 `CGDrawingView`, the status
line a 133×14 `CGDrawingView`, the gear a 16×16 `_NSShapeHitTestingView`, plus a focus ring and
`KeyViewProxy` views. A 22pt continuous corner on a 21pt-tall view is a pill, which cuts the first
and last glyphs; on a 16pt square it is a near-circle that leaves a diamond of the symbol.

The `popover-window` hierarchy log showed it once it stopped truncating (the unified log cuts a
message at about 1 KB, which had hidden every view after the first few). On macOS 26 the content
view's small leaves are only `KeyViewProxy` views, which draw nothing, so the same rounding was
invisible there.

## Fix

`PopoverHostBackdrop.spansContent(_:bounds:cornerRadius:)` decides which leaves PC1 may round:
only those whose frame matches the content bounds within a point, and only once the content is
at least twice the radius in each direction. The full-size leaves (our material shell's backdrop
views on 15, the host backdrops under `swift run`) are still rounded; the header's views are not.
The hierarchy dump is now logged in chunks under 900 bytes.

## Verification

- macOS 15.7.7 VM, `./Scripts/build-app.sh` builds run unquarantined in fresh clones: `--demo`,
  `multi-3`, `multi-7` (two columns), a plain launch (header status line) and `multi-7` in Compact,
  each opened twice. Header, status line, gear and footer intact; 4x corner crops show one corner.
- macOS 26 host: `--render-popover` for default, multi-7 and multi-20 in Standard and Compact,
  light and dark, pixel-identical before and after (12/12).
- `PopoverHostBackdropTests` covers the decision with the frames the VM logged; a hosting test in
  `PopoverWindowHeightFitTests` hosts the popover as a window's content view and fails without the
  fix even on 26 (the `KeyViewProxy` leaves came back rounded).

## Lesson

Never apply a window-shaped mask to views picked by structure alone ("every leaf"). What an
`NSHostingView` keeps as direct subviews differs between OS releases; select by geometry (spans the
window) and log enough of the hierarchy, split under the 1 KB limit, to see what was selected.
