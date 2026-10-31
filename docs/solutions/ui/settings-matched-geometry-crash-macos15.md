---
title: "A matchedGeometryEffect selection plate terminated the Settings window on macOS 15; frame the plate from a layout anchor instead"
date: 2026-10-30
category: ui
module: HeadroomApp/UI/SettingsRows
problem_type: ui_bug
component: frontend
symptoms:
  - "On macOS 15.7.7, clicking Theme, Shape, Fill, Left/Used or Pills only/Pills + percentages in Settings terminated the app (1st click for most, about the 3rd for Shape); the new value was saved first"
  - "Format (Full/Micro) never crashed; nothing crashed on macOS 26"
  - "Unified log: AppKit 'The window has been marked as needing another Update Constraints in Window pass, but it has already had more Update Constraints in Window passes than there are views in the window. <SwiftUI.AppKitWindow> {800, 770}'"
  - "Exception backtrace: -[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints] <- NSHostingView.setNeedsUpdate <- NSHostingView.cancelAsyncRendering <- NSHostingView._willUpdateConstraintsForSubtree, under NSDisplayCycleFlush"
  - "The .ips carries only -[NSApplication _crashOnException:] (EXC_BREAKPOINT); the reason is only in the unified log"
root_cause: platform_bug
resolution_type: code_fix
severity: critical
framework_version: "SwiftUI on macOS 15.7.7 (24G720), app built with Xcode 27 / Swift 6.4; not reproducible on macOS 26"
related_components:
  - SettingsSelectionGroup
  - SettingsSelectionChrome
  - ThemeThumbnailPicker
  - MeterStyleTile
  - InAppDisplayTile
  - MenuBarSettingsPane
  - WidgetStyleGalleryPicker
tags: [swiftui, appkit, macos-15, matchedgeometryeffect, nshostingview, update-constraints, crash, settings, vm-qa]
---

# A `matchedGeometryEffect` selection plate terminated the Settings window on macOS 15

## Problem

A user reported (Oct 14, 2026) that Headroom "dies every time" they changed Pills + percentages ↔
Pills only, Format/Shape/Fill, or Left ↔ Used in Settings. It never reproduced on macOS 26. In a
macOS 15.7.7 VM (`macos-vm-qa` skill, master `macos15-master`) it reproduced on 1.5.1 and `main`,
at the default 800×770, at the 720×628 minimum and with the pane scrolled, with and without
`--demo multi-5`:

| Trigger | Result on macOS 15 |
| --- | --- |
| Pills + percentages ↔ Pills only | crash, 1st click |
| Percentages Left ↔ Used | crash, 1st click |
| Fill | crash, 1st–2nd click |
| Shape | crash, about the 3rd click |
| Theme | crash, 1st click |
| Widget style gallery (not reported) | crash, 1st click |
| Format Full ↔ Micro | never crashed |

The exception is AppKit's update-constraints loop guard, thrown during a display-cycle flush for
the **Settings** window (`SwiftUI.AppKitWindow`, roughly 150 views). The window's root `NSHostingView`
re-marked itself as needing constraints from `cancelAsyncRendering` on every Update Constraints
pass, until the pass count exceeded the view count.

## Root cause

Every crashing control is a swatch row whose selection plate slid between swatches with
`matchedGeometryEffect` (`SettingsSelectionGroup` / `SettingsSelectionChrome`, SM1). The bisect,
each step a runtime switch in one diagnostic build, run in the VM (`--demo multi-5`, Theme,
Shape and Fill clicks; evidence in `.context/vm-repro/macos15/fix/bisect.log`):

| Variant | Result |
| --- | --- |
| Shipping code | crash on 1st click |
| All Settings animations off (root `.transaction`) | 15 clicks, alive |
| Plate removed (the Reduce Motion in-place ring, which still cross-fades colours) | 15 clicks plus 10 Pills toggles, alive |
| `.windowResizability(.contentMinSize)` or `.automatic` instead of `.contentSize` | crash on 1st click |
| Theme without the `NSApp.appearance` writes | crash on 1st click |
| Matched plate plus an `anchorPreference` on each swatch | crash |
| Matched plate plus a `backgroundPreferenceValue` reader on the row | crash |
| Matched plate plus both (the row's layout depends on the selected swatch's geometry) | 13 clicks, alive |
| Plate framed from the selected swatch's anchor, no `matchedGeometryEffect` | 17 clicks, alive |

So the trigger is a `matchedGeometryEffect` animation, not window sizing, the process appearance
or the status item. Cross-fades alone (colour, opacity) never crashed.

**Our reading of the mechanism (inferred from the backtrace, not from SwiftUI source):** on macOS
15 SwiftUI can render a `matchedGeometryEffect` animation asynchronously, off the main thread's
layout pass. While that is in flight, any Update Constraints pass in the window reaches
`NSHostingView._willUpdateConstraintsForSubtree`, which cancels the async render and calls
`setNeedsUpdate`, which marks the hosting view's constraints dirty again, so the flush loops until
AppKit throws. macOS 26's SwiftUI does not loop.

**Why Format was immune:** a Format change resizes the specimen (Full is taller than Micro), and the
pane animates that height in the same transaction (MS1). A layout animation must run in a
main-thread layout pass every frame, so the plate's frames never took the asynchronous path. The
"matched plate plus a geometry-preference reader" row above is the same effect produced on
purpose: once the row's layout reads the selected swatch's geometry, the plate cannot be rendered
asynchronously and the crash goes away.

## Fix

`SettingsSelectionGroup` draws **one plate per row** in `backgroundPreferenceValue`, framed and
offset from the selected swatch's `Anchor<CGRect>` (`SettingsSelectionPlateKey`). The row's
existing `.animation(selectionTravel, value:)` animates that frame, so the plate still slides on
the same spring. Because its frame is resolved from a layout anchor, every frame is a main-thread
layout pass. The selected swatch's own layer goes clear (fill and hairline), so the plate's 2pt
ring isn't cut by a hairline drawn above it; hover still deepens the plate (the anchor carries the
selected swatch's hover flag), and the anchor sits inside the button label, so the plate keeps
the 0.96 press scale. Reduce Motion is unchanged: no plate, the ring cross-fades in place.

Settled pixels are unchanged: all 73 `--render-popover` captures, Settings panes included, were
pixel-identical before and after. `--bench-ui settings` (8 runs, back to back) showed the same body
counts and CPU within run-to-run noise.

## Verification

In a fresh `macos15-master` clone with the `./Scripts/build-app.sh` build, unquarantined:

- **Before** (the same tree with the old plate): Theme, Pills, Left/Used, Fill and the widget style
  gallery crashed on the 1st click, Shape on the 3rd. Format survived 10 toggles.
- **After:** zero crashes and no "Update Constraints" error in the unified log across plain launch
  and `--demo multi-5`, each at 800×770 and at the 720×628 minimum, unscrolled and scrolled.
  That covered 12 Theme clicks, 10 Format toggles, 12 Shape clicks (every swatch), 10 Fill clicks
  (every swatch), 10 Left/Used toggles and 12 Pills toggles per configuration, plus 4 Account names
  toggles and 12 widget style clicks.
- A temporary 10× slow-motion build captured the plate mid-slide between Segmented and Tube.

Evidence lives in `.context/vm-repro/macos15/fix/` of the fixing worktree (git-ignored).

## Prevention

- `SettingsSelectionPlateTests` (HeadroomAppTests) checks that the plate is drawn on the selected
  swatch (it fails if the anchor stops reaching the row) and fails if any Settings source file
  calls `.matchedGeometryEffect(`.
- A host on macOS 26 cannot reproduce this. Any new Settings motion that moves geometry without a
  layout change (matched geometry, or a pure geometry effect across views) needs the macOS 15 VM
  matrix above before it ships.
- The `.ips` for these crashes has no exception reason; read the unified log
  (`/usr/bin/log show --predicate 'process == "Headroom" AND messageType == error'`).
