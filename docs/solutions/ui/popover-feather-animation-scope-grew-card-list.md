---
title: "Keep an implicit animation off a measured ScrollView — the feather's fade grew the card list on every open"
date: 2026-10-04
category: ui
module: HeadroomApp/PopoverView
problem_type: ui_bug
component: frontend
symptoms:
  - "The popover's card list grew open over about 12 frames on every open (single account 25.7pt to 319pt, multi-20 139pt to 640pt), which read as the window opening"
  - "Entrance motion that M9C had deliberately removed was back, and nobody noticed because it looked like the window opening"
  - "Every grow frame wrote scroll-metrics @State and re-ran the whole popover body (4 to 12 root re-runs after open)"
  - "Post-open 600ms main-thread CPU was 68ms single, 117ms multi-5 and 402ms multi-20"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
framework_version: "swiftui macos 26.6.2 (Xcode 27 / Swift 6.4 toolchain, MenuBarExtra .window)"
related_components:
  - MenuBarExtra
  - HeadroomMotion
tags: [swiftui, implicit-animation, animation-scope, popover, menubarextra, scrollview, mask, frame-by-frame-measurement]
---

# Keep an implicit animation off a measured ScrollView — the feather's fade grew the card list on every open

## Problem

The popover's bottom scroll feather (R2C23) animated its fade with `.animation(_:value:)` on the
whole `ScrollView`. On every open, the feather's gate flipped in the same update that pinned the
scroll frame from 0 to its measured height, so that scope animated the frame change too. The card
list grew open over about 10–12 frames (about 5 slower ones at 20 accounts): the entrance motion
M9C had removed, back under another name and re-rendering the popover on each frame. This was
measured on an offscreen host of the real `PopoverView`; a live check in the `MenuBarExtra` window
was still pending when this was written.

Both halves landed on 2026-07-16: the feather's scope in an accounts polish pass, and the measured
scroll frame in the zero-height fix (`docs/solutions/popover-scrollview-zero-height.md`). From then
until #157, every open that rebuilt the popover's content grew the list.

## Symptoms

- On every open the card list's viewport grew from near zero to full height. The offscreen perf
  bench's frame-by-frame probe read (samples, abbreviated) 25.7 → 109 → 197 → 244 → 279 → 296 → 307 → 316 → 318 → 319pt
  for one account, and 139 → 580 → 632 → 639 → 640pt over about 5 slow frames at 20 accounts.
- The popover did not feel snappy at open (the user's report that started the audit), even though M9C (Sep 2026) had set "no entrance motion at
  all, not even on the first open" (`docs/plans/2026-09-04-002-feat-subtle-motion-system-plan.md:28`).
- Each grow frame changed the scroll geometry, wrote scroll `@State`, and re-ran the whole popover
  body: the bench counted 4–12 popover root passes after an open that should need none.
- At 20 accounts the scroll indicator stayed lit longer after open. Each grow frame was a
  geometry change, and each change restarted its 900ms hold.
- Reduce Motion did not stop the grow. The scope resolved as `.crossfade`, and
  `HeadroomMotion.resolved` keeps a crossfade's timing under Reduce Motion
  (`Sources/HeadroomApp/UI/HeadroomMotion.swift:153-155`), so a resize played where S2A says
  movement should be instant.

## What Didn't Work

1. **The render harness could not show it.** `--render-popover` hosts the popover, waits
   `HeadroomMotion.arrivalDelay + 650ms`, then captures one still
   (`Sources/HeadroomApp/PopoverRenderHarness.swift:293`). The grow was over long before the
   capture, so every still showed a correct, settled popover. The marketing hero path passes
   `forcedCardsHeight: 482` (`PopoverRenderHarness.swift:345`), so the 0 → measured change never
   happens there at all.
2. **M9C was taken as settled.** M9C removed the entrance fade, its session gate, and the
   harness's `forceVisible` escape hatch, so nobody went looking for entrance motion. The grow came
   from the feather, a different decision. Most likely it read as the window itself opening, so
   nobody reported it as an animation.
3. **The comments described what the scope was meant to do, not what it reached.** The old scope
   carried "S2A: the feather is pure mask opacity". It was not. It wrapped the ScrollView, its mask,
   and every size change inside them. The M7A note above the card stack
   (`Sources/HeadroomApp/UI/PopoverView.swift:142-146`) is right that the stack's own scopes leave
   the scroll frame alone. Those scopes sit inside the ScrollView's content. The feather's scope
   sat outside the ScrollView, where the frame change lands.
4. **Moving `.animation(_:value:)` onto the gradient inside the mask (rejected — reasoned, not
   tried).** This is the obvious narrowing, and it is still value-keyed. In the update where the gate flips, the 14pt
   band is also being placed at the bottom of a viewport growing from 0. A value-keyed scope
   animates its content's placement as well as its properties, so the band would have slid down
   the growing list as a wipe.

## Solution

Fix in #157 (unmerged as of this writing). The mask is now a child view, and its animation reaches
only one opacity.

Before (main as of #156, `PopoverView.swift:192-211`):

```swift
.mask {
    VStack(spacing: 0) {
        Rectangle().fill(.black)
        LinearGradient(
            stops: Self.featherStops(fadesOut: scrollContinuesBelow),
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: Self.featherHeight)
    }
}
// S2A: the feather is pure mask opacity, so Reduce Motion keeps the
// 200ms softening rather than hard-cutting the card edge.
.animation(
    HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
    value: scrollContinuesBelow
)
.overlay(alignment: .topTrailing) { scrollIndicator }
.frame(height: forcedCardsHeight ?? min(cardsHeight, 640))
```

After (`PopoverView.swift:186-191` and `PopoverScrollFeather`, `:863-899`):

```swift
// FA1: the feather animates its own opacity only (see `PopoverScrollFeather`).
.mask { PopoverScrollFeather(model: scroll) }
.overlay(alignment: .topTrailing) { PopoverScrollIndicator(model: scroll) }
.frame(height: forcedCardsHeight ?? min(cardsHeight, 640))

private struct PopoverScrollFeather: View {
    let model: PopoverScrollModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fadesOut = model.continuesBelow
        VStack(spacing: 0) {
            Rectangle().fill(.black)
            ZStack {
                LinearGradient(stops: Self.featherStops, startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.black)
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)
                    ) { $0.opacity(fadesOut ? 0 : 1) }
            }
            .frame(height: Self.featherHeight)
        }
    }
}
```

- The gradient always carries the fade stops. The gated "crisp last card" case is now an opaque
  black band over it, and the fade is that band's opacity going 1 → 0.
- That opacity is the only thing animated. `animation(_:body:)` (macOS 14+, inside the app's
  macOS 15 floor) applies the animation only to the modifiers inside its closure.
- The ScrollView-wide `.animation(_:value: scrollContinuesBelow)` is gone, so nothing animates the
  scroll frame. The viewport now reports 0 → 319pt (or 640pt) inside the first layout pass and
  never moves again.
- The fade is still opacity only, so Reduce Motion keeps its 200ms (S2A). Now that is true.

The same commit moved the gate into `PopoverScrollModel` (`PopoverView.swift:824-854`), which only
the feather and the indicator read, so a scroll step no longer re-runs `PopoverView.body` (SC1).

Measured on the offscreen perf bench, with the old build re-run back to back in the same session:

| Scenario | Main-thread CPU, 600ms after open |
| --- | --- |
| 1 account | 68 → 16ms |
| 5 accounts | 117 → 33ms |
| 20 accounts | 402 → 270ms |

Popover root passes after open went from 4–12 to 0. Absolute numbers moved with machine load. The pre-fix tree measured 116ms in one session and 68ms
in another (the harness also changed between sessions), which is why the before and after runs were paired. The bench hosted `PopoverView`
offscreen and never drove the real `MenuBarExtra`.

**Side effect, not a regression:** the scroll indicator now hides about 900ms after open. A
render-harness capture that used to catch it visible at 20 accounts no longer does. The indicator
still works; this was checked by temporarily lengthening the hold.

## Why This Works

`.animation(_:value:)` does not animate a value. In any update where `value` changed, it puts the
animation in the transaction for its whole subtree, and every animatable change rendered in that
subtree during that update animates with it. That includes size and position changes pushed in
from outside, such as a new height proposed by an outer `.frame` — observed here on macOS 26.6.2,
where removing this one scope stopped the grow.

The open is the one moment those collide. `MenuBarExtra` rebuilds the popover's SwiftUI content on
each open (per the comments at `PopoverView.swift:216-217` and `UsageBarView.swift:6-7`; the
`NSWindow` itself may be reused), so `cardsHeight` starts at 0 (`:34`). The stack's `onGeometryChange`
(`:159`) measures it on the first pass, the outer frame (`:191`) jumps to the measured height, and
`continuesBelow` (`offset + viewport < content - 4`, `:816`) flips while the viewport is still 0.
A gate derived from scroll geometry changes in the same update as the layout it measures. Put an
implicit scope keyed on that gate around the ScrollView, and the first layout becomes an animation.

`animation(_:body:)` has no "everything in this subtree" reach. It animates the modifiers written
inside its closure, here one `.opacity`. The band's frame and its place in the VStack come from
outside the closure, so they take their final values at once.

## Prevention

- Put `.animation(_:value:)` on the smallest view that owns the animated property. Never put it
  around a ScrollView, a measured container, or anything whose frame comes from a measurement
  (`cardsHeight`, `onGeometryChange`, `onScrollGeometryChange`).
- Treat a value-keyed scope whose key comes from geometry as a bug until shown otherwise. The key
  flips in the same update as the layout it reads, and on first layout every size starts at 0.
- For property-only motion (opacity, colour), prefer `animation(_:body:)`. Write the state as a
  modifier property, like an overlay's opacity, rather than swapping gradient stops or content, so
  the body-scoped form can reach it.
- A `.crossfade` resolution is a claim that the scope only fades. Before writing "pure opacity"
  in an S2A comment, check what the scope wraps. HeadroomMotion's RM1 note
  (`HeadroomMotion.swift:157-165`) records the same trap from the Reduce Motion side.
- Check open and entrance motion from frames, not stills. Two cheap checks in a debug build:
  log `metrics.viewport` in `PopoverScrollModel.update` for the first second after open (a healthy
  open goes 0 → final once and stops), and drop `let _ = Self._printChanges()` into
  `PopoverView.body` to count root passes after open (should be none). A still from
  `--render-popover` proves the settled layout and nothing else.
- Harness idea, not built: an offscreen check that hosts `PopoverView` for each `--demo` fixture,
  drives frames for 600ms after attach, and fails if the scroll viewport height takes more than one
  non-zero value or the root body runs again. The audit's bench did this by hand in an uncommitted
  worktree.

## Related Issues

- #157 — this fix, with the scroll-chrome (SC1), app-shell, Settings and spend-label fixes from the
  same audit.
- `docs/solutions/popover-scrollview-zero-height.md` — why `PopoverView` measures `cardsHeight` and
  pins the scroll frame, which is the frame change this scope caught.
- `docs/solutions/ui/swiftui-layout-owned-drag-position.md` — another case of SwiftUI animating
  everything in a transaction, not just the thing you meant.
- `docs/plans/2026-09-04-002-feat-subtle-motion-system-plan.md` — M9C and S2A.
- `docs/plans/2026-09-09-001-feat-craft-round2-plan.md` — R2C23, the feather.
- `BUGS.md` › "Popover & Settings snappiness residuals (2026-10-03 perf audit)". Still open: before
  its first layout the popover reports 124pt because `cardsHeight` starts at 0, and whether
  `MenuBarExtra` sizes the window from that is unmeasured.
- `docs/solutions/ui/popover-scroll-geometry-state-rerendered-whole-popover.md` — SC1, same commit:
  the per-frame scroll-geometry writes that turned each grow frame into a full popover re-render.
- `docs/solutions/ui/menubarextra-window-closures-run-in-app-body.md` — same audit (#157): `MenuBarExtra`
  and `Window` closures run inside `App.body`, so store reads there re-rendered Settings and the popover.
