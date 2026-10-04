---
title: "Popover opened empty — ScrollView collapsed to zero height in MenuBarExtra(.window)"
date: 2026-07-16
last_updated: 2026-10-04
category: ui
module: HeadroomApp/PopoverView
problem_type: ui_bug
component: frontend
symptoms:
  - "The popover opened with only its header and footer and no provider cards"
  - "The live window measured 384 x 127pt (header, footer and padding) instead of about 429pt"
  - "The menu bar label was correct and live, so it looked like a store data bug"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [swiftui, scrollview, menubarextra, popover, self-sizing-window, layout]
---

# Popover opened empty — ScrollView collapsed to zero height in `MenuBarExtra(.window)`

**Anchor:** `#popover-scroll-height` · **Date:** 2026-07-16 · **Area:** `PopoverView`

## Symptom

The popover opened showing only its header ("Usage · Updated just now") and footer
("Refresh"/"Quit") with an empty gap between them — no provider cards at all. The menu bar
label was simultaneously correct and live ("99%", "77%"), which made it look like a data
bug in the store.

It was not a data bug. The menu bar item's own accessibility label read
`Claude weekly, 99% left; Codex weekly, 77% left`, proving `providerOrder` was populated.
Measuring the live window settled it:

| Build | Popover size | Cards |
| --- | --- | --- |
| 1.0.9 (pre-multi-account) | 384 × **429** | yes |
| `main` @ `f4ed4b54` (post-#71) | 384 × **127** | no |

127pt is exactly header + footer + 19pt padding: **the card area contributed zero height.**
The visible gap measured ~40pt — the two 20pt `VStack` spacings with nothing between them.

## Root cause

PR #71 (multi-account) wrapped the card stack to cap tall multi-account popovers:

```swift
ScrollView(.vertical) { VStack(spacing: 20) { cards } }
    .frame(maxHeight: 640)
```

`MenuBarExtra(.window)` sizes its NSWindow to the content's **ideal** height, and a
`ScrollView` has no ideal height of its own — it's designed to accept whatever height is
proposed. Nothing proposes one here, so it resolved to ~0. `maxHeight:` did not save it:
it only sets a ceiling, never a floor.

## Fix

Measure the stack and pin an explicit height, keeping the cap as an upper bound:

```swift
@State private var cardsHeight: CGFloat = 0

ScrollView(.vertical) {
    VStack(spacing: 20) { cards }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardsHeight = $0 }
}
.frame(height: min(cardsHeight, 640))
```

Scroll content is laid out at its ideal height independent of the ScrollView's own frame, so
the measurement is correct on the first pass even while the frame is still zero — no feedback
loop, and the height then tracks content (verified 370pt with a 3-window stack, 429pt with 4).

## Why the tests and the harness both missed it

**This is the part worth remembering.** In July 2026 `PopoverRenderHarness` rendered a *perfect*
popover, cards and all — because `ImageRenderer` proposes a concrete size, so the ScrollView sizes
fine there. The bug existed **only in a real, self-sizing window**. The 228-test suite covers logic,
not layout, so it was green too. (The harness has since moved to an `NSHostingView` in a parked
window captured with `screencapture -l`, `Sources/HeadroomApp/PopoverRenderHarness.swift:248-300`,
but it still captures one settled still after a delay: it shows final layout, not first-frame
sizing.)

Two green signals, one broken app. A layout regression in a self-sizing window is invisible to an
image renderer and to a unit test. The live window is the authoritative check, but driving it takes
over the user's screen, so keep it for final acceptance and ask first (DESIGN.md › "Verifying a UI
change"):

```bash
osascript -e 'tell application "System Events" to tell process "Headroom" \
  to click menu bar item 1 of menu bar 2'
osascript -e 'tell application "System Events" to tell process "Headroom" \
  to get {position, size} of window 1'
```

A popover measuring about header-plus-footer height (127pt in July 2026) is this bug; a healthy
one tracks its content (≈370–640pt).

For a cheaper first signal that needs no screen, host `PopoverView` in an `NSHostingView` inside a
parked window and read `fittingSize` after the first layout pass, as
`docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md` describes.
With the October 2026 header, the pre-layout answer (before `cardsHeight` is measured) is 124pt and
the post-layout one tracks the cards. That check was not run against this exact regression.

## Related

- `docs/solutions/ui/popover-feather-animation-scope-grew-card-list.md` — because the popover is
  rebuilt on every open, this measured frame starts at 0 each time; an implicit animation scope
  around it animated that change into a grow-in on every open (fixed in #157).
- `docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md` — offscreen
  measurement and the hot-spot checklist.
