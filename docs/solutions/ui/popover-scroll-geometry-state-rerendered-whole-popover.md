---
title: "Keep per-frame scroll geometry out of a big view's `@State` — the scroll chrome re-rendered the whole popover every frame"
date: 2026-10-04
category: ui
module: HeadroomApp/PopoverView
problem_type: performance_issue
component: frontend
symptoms:
  - "Every scroll step re-ran the whole popover body, about 230 view bodies per step at 20 accounts (4 cards, 60 account sections)"
  - "Each scroll step cost about 41ms of main-thread CPU at 20 accounts, well over a 16.7ms frame at 60Hz"
  - "The scroll indicator's 900ms auto-hide re-rendered the entire popover a second time (another 230 bodies)"
  - "No visible glitch: the waste showed only in body counters and a Time Profiler trace from an offscreen host, never in a render-harness still"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
framework_version: "swiftui macos 26.6.2 (Xcode 27 / Swift 6.4 toolchain, MenuBarExtra .window)"
related_components:
  - PopoverScrollModel
  - PopoverScrollFeather
  - PopoverScrollIndicator
  - ProviderCardView
tags: [swiftui, observable, state-invalidation, onscrollgeometrychange, scrollview, popover, body-counts, performance]
---

# Keep per-frame scroll geometry out of a big view's `@State` — the scroll chrome re-rendered the whole popover every frame

## Problem

The popover's scroll chrome, the bottom feather (R2C23) and the bespoke gutter indicator (L2A),
kept its live scroll geometry in four `@State` properties on `PopoverView`. `PopoverView`'s body
builds every card, and it read three of those properties, so every scroll frame re-ran the whole
popover and rebuilt every card in order to move a 3pt capsule (SC1). At 20 accounts the offscreen
perf bench counted 230 view bodies and about 41ms of main-thread CPU per scroll step. This was
measured on an offscreen host of the real `PopoverView`; the live `MenuBarExtra` window was not
driven.

The feather's gate had lived in `PopoverView` `@State` since July 2026. The per-frame write came
with L2A's indicator in #110 (Sep 2026), which needs the scroll offset on every frame. From then
until #157, every scroll frame re-ran the popover root.

## Symptoms

- Per the bench, each scroll step on the `multi-20` fixture (4 provider cards, 60 account
  sections; Cursor's single account has no section) ran 230 view bodies and about 41ms of main-thread CPU. A 60Hz frame is 16.7ms, so one
  step cost more than two frames of main-thread time.
- The indicator's hide, 900ms after scrolling stopped, was another full 230-body re-render, all
  for a fade on one capsule.
- During the open, each frame of the card-list grow described in the FA1 doc also changed the
  scroll geometry, and these writes turned each of those frames into a root pass (FA1's 4–12 root
  passes after open).
- Nobody reported scroll jank on its own. The audit found it while measuring the user's report
  that the popover did not feel snappy.

## What Didn't Work

1. **Nothing in the test kit can see body counts.** `--render-popover` captures one still after
   motion settles (see the FA1 doc), and a still never scrolls. Unit tests cover Core recipes, not
   how often SwiftUI re-runs a body. Every existing check passed because the output was right.
   Only the cost was wrong.
2. **The cost only shows up with many accounts.** The list scrolls only once the cards pass the
   640pt cap (`PopoverView.swift:191`; `.scrollBounceBehavior(.basedOnSize)` at `:167`), so a
   popover whose cards fit never scrolls, and the callback fires only on layout changes. Past the
   cap, each frame cost "rebuild every card", so the cost grew with each account. The people with
   the most accounts got the slowest scroll, and short-list testing looked fine.
3. **SwiftUI could not skip the cards.** Re-running a parent's body is cheap when SwiftUI can see
   that a child's inputs are unchanged and skip the child. `PopoverView` builds each
   `ProviderCardView` with new closure literals on every pass (`onRetrySetup`, `onRetryAccount`,
   `claimBankedResetReveal`, `PopoverView.swift:115-117`). SwiftUI treats a view that takes
   capturing closure literals as changed on every parent pass (a grounding probe on macOS 26.6.2:
   10 parent passes re-ran a closure-taking child 10 times and a value-taking child 0 times), so
   every root pass ran every card's body. BUGS.md
   also lists `now` as fresh on each pass. So there was never such a thing as a cheap re-render of
   the root.
4. **The pattern looked idiomatic.** Writing `onScrollGeometryChange` output into `@State` is the
   textbook shape, and for a small view it costs nothing. Here the view that owned the state was
   the biggest one in the popover. The indicator also looked self-contained in source:
   `scrollIndicator` was a computed property on `PopoverView`, so its reads counted as reads by the
   root body.

## Solution

The fix is in #157 (open, unmerged as of 2026-10-04). The scroll state moved into a small
`@Observable` model that only two leaf views read.

Before (main as of #156, `PopoverView.swift:25-32`, `:181-210`, `:265-328`):

```swift
@State private var scrollContinuesBelow = false
@State private var scrollMetrics = PopoverScrollMetrics()
@State private var scrollIndicatorVisible = false
@State private var scrollIndicatorHideTask: Task<Void, Never>?

// In body, inside the TimelineView closure that also builds every card:
.onScrollGeometryChange(for: PopoverScrollMetrics.self) { geometry in
    PopoverScrollMetrics(
        offset: geometry.contentOffset.y,
        viewport: geometry.containerSize.height,
        content: geometry.contentSize.height
    )
} action: { _, metrics in
    scrollMetrics = metrics                       // every scroll frame
    scrollContinuesBelow = metrics.continuesBelow
    flashScrollIndicator(overflows: metrics.overflows)
}
.mask { /* gradient built from scrollContinuesBelow */ }
// A computed property on PopoverView: reads scrollMetrics and scrollIndicatorVisible.
.overlay(alignment: .topTrailing) { scrollIndicator }

private func flashScrollIndicator(overflows: Bool) {
    scrollIndicatorHideTask?.cancel()
    guard overflows else {
        scrollIndicatorVisible = false
        return
    }
    scrollIndicatorVisible = true
    scrollIndicatorHideTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        scrollIndicatorVisible = false            // the hide: another full root pass
    }
}
```

After (`PopoverView.swift:28`, `:177-190`, `PopoverScrollModel` at `:819-854`):

```swift
@State private var scroll = PopoverScrollModel()

.onScrollGeometryChange(for: PopoverScrollMetrics.self) { geometry in
    PopoverScrollMetrics(
        offset: geometry.contentOffset.y,
        viewport: geometry.containerSize.height,
        content: geometry.contentSize.height
    )
} action: { _, metrics in
    scroll.update(metrics)
}
.mask { PopoverScrollFeather(model: scroll) }
.overlay(alignment: .topTrailing) { PopoverScrollIndicator(model: scroll) }

@MainActor
@Observable
private final class PopoverScrollModel {
    private(set) var metrics = PopoverScrollMetrics()
    private(set) var continuesBelow = false
    private(set) var indicatorVisible = false
    @ObservationIgnored private var indicatorHideTask: Task<Void, Never>?

    /// Called only when the metrics changed (`onScrollGeometryChange` compares them).
    func update(_ metrics: PopoverScrollMetrics) {
        self.metrics = metrics
        if continuesBelow != metrics.continuesBelow { continuesBelow = metrics.continuesBelow }
        flashIndicator(overflows: metrics.overflows)
    }

    private func flashIndicator(overflows: Bool) {
        indicatorHideTask?.cancel()
        guard overflows else {
            if indicatorVisible { indicatorVisible = false }
            return
        }
        if !indicatorVisible { indicatorVisible = true }
        indicatorHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.indicatorVisible = false
        }
    }
}
```

- `PopoverScrollIndicator` (`:905-955`) reads `metrics` and `indicatorVisible` (`:911`, `:919`).
  `PopoverScrollFeather` (`:863-899`) reads `continuesBelow` (`:882`). `PopoverView.body` reads
  none of them. It only hands the model reference down.
- The hide task is `@ObservationIgnored` (`:830`). No view draws it, so replacing it on every
  frame must not notify anyone.
- `continuesBelow` and `indicatorVisible` are written only when their value changes (`:835`,
  `:844`, `:847`), so a scroll step in the middle of the list touches `metrics` alone. `metrics`
  needs no guard, because `onScrollGeometryChange` runs the action only when the `Equatable`
  `PopoverScrollMetrics` (`:810`) changes. The hide task's write always follows a show, so it is
  always a real change.
- The indicator's look, its timing (900ms hold, `quickSettle` in, `settle` out) and its S2A
  behaviour are unchanged. Only where the state lives moved.

Measured on the offscreen perf bench (then uncommitted; now `--bench-ui`), `multi-20`, with the old and new
builds run back to back in the same session:

| | Before | After |
| --- | --- | --- |
| View bodies per scroll step | 230 | 1 (`PopoverScrollIndicator`) |
| Main-thread CPU per scroll step | 41.2ms | 5.5ms |
| View bodies for the indicator's hide | 230 | 1 |

Absolute bench numbers moved with machine load (the FA1 doc records the pre-fix tree at 116ms in
one session and 68ms in another), so quote the paired before/after, not either absolute.

## Why This Works

SwiftUI re-runs a view's body when something that body read has changed. A `@State` dependency
belongs to the view that declares it. Here that was `PopoverView`, whose body builds the header,
every card, the spend tile and the footer inside one `TimelineView` closure (`PopoverView.swift:44`).
Writing scroll geometry there on every frame told SwiftUI the whole popover was out of date on
every frame.

`@Observable` tracks dependencies by property. While a body runs, Observation records which
properties of which objects it read, and later it invalidates only the bodies that read a property
that changed. So the dependency now sits where the read happens:

- A scroll step changes `metrics`. The only body that read `metrics` is `PopoverScrollIndicator`,
  so that one small body runs.
- `continuesBelow` flips only at the bottom of the list, and only the feather read it.
- `PopoverView` passes the model reference to its children. Passing a reference reads no
  property, so the root never subscribes to anything in the model.

Because the card list no longer re-runs during a scroll, the closure-equality problem above never
comes into play while scrolling. Holding the model in `@State` keeps one instance for the
popover's lifetime, so the reference the leaves receive is the same on every root pass.

The change-only guards keep the leaves quiet too. The model writes a property only when its value
changes, rather than counting on the framework to drop same-value writes, so the feather and the
capsule's opacity are not re-evaluated on every frame.

## Prevention

- **Never write a per-frame source into `@State` that a large body reads.** Per-frame sources
  include `onScrollGeometryChange`, `onGeometryChange` during motion, timers and `TimelineView`
  ticks finer than the content needs, a drag gesture's `onChanged`, and animation-progress
  callbacks. Route them through a small `@Observable` model, and let only the leaf views that draw
  them read it. Keep the large view's body free of reads of that model, including reads through
  computed properties and `@ViewBuilder` helpers on the large view, which count as its body.
- **A large body may own geometry it really lays out with, if that geometry changes rarely.**
  `cardsHeight` (`PopoverView.swift:34`, written by `onGeometryChange` at `:159`) stays `@State` on
  `PopoverView` because the root's `.frame` (`:191`) uses it, and it changes only when the stack's
  height does.
- **Write observed properties only on change.** Guard with `if value != new { value = new }`. Mark
  bookkeeping that no view draws (`Task` handles, timestamps) `@ObservationIgnored`. Make the
  transformed value `Equatable`, so `onScrollGeometryChange` and `onGeometryChange` skip unchanged
  values.
- **Give large child views inputs SwiftUI can compare.** A child that takes closure literals runs
  again on every parent pass. Prefer plain values, or let the child call the store itself. This
  matters most for views repeated per account. `ProviderCardView` still takes fresh closures today
  (see the open item below).
- **Keep the initializer of a class held in `@State` trivial**, as `PopoverScrollModel`'s is.
  Whether `@State private var x = Model()` runs `Model.init` on every init of the owning struct
  (keeping only the first instance) depends on the toolchain and how the value is declared; two
  probes on Xcode 27 disagreed. Assume it may run every time.
- **Check with body counts, not stills.** In a debug build, add `let _ = Self._printChanges()` to
  `PopoverView.body` and `PopoverScrollIndicator.body`, run `swift run Headroom --demo multi-20`,
  open the popover and scroll. The root should log nothing, and the indicator should log once per
  frame. `_printChanges()` is an underscored debug API, so remove it before committing. For totals
  per scroll step, put a counter line in each body with `BenchCounters.hit(_:)`, which
  `--bench-ui` builds compile in with `-DHEADROOM_BENCH` (a no-op otherwise). The offscreen check sketched in the FA1 doc would catch this too if it also
  drove scroll steps and failed on any root pass.
- **Still open:** every `ProviderCardView` re-renders on any store change (fresh closures, plus
  `now` per BUGS.md), so one account refresh re-runs all cards. BUGS.md puts that at about 240ms of
  CPU per refresh at 20 accounts after #157 (about 360ms before). SC1 took scrolling off that path; it did not fix the path. Tracked in
  `BUGS.md` › "Popover & Settings snappiness residuals (2026-10-03 perf audit)".

## Related Issues

- #157: this fix, together with the feather-scope fix (FA1) and the app-shell, Settings and
  spend-label fixes from the same audit.
- `docs/solutions/ui/popover-feather-animation-scope-grew-card-list.md`: FA1, from the same
  commit. Its open-time grow wrote scroll geometry on every frame, which is how SC1 also hit the
  open.
- #110: L2A, the bespoke indicator that started the per-frame write
  (`docs/plans/2026-09-04-001-feat-loom-refinements-plan.md`).
- `docs/plans/2026-09-09-001-feat-craft-round2-plan.md`: R2C23, the feather.
- `docs/solutions/popover-scrollview-zero-height.md`: why `cardsHeight` is measured and stays on
  the root.
- `docs/solutions/ui/menubarextra-window-closures-run-in-app-body.md` — same audit (#157): `MenuBarExtra`'s label closure (and `Window`'s content closure) are evaluated
  inside `App.body`, so the store reads in the label re-ran the whole scene, popover and Settings
  content included, on every probe (`MenuBarLabel.swift:73-76`). That is the same "big body reads a
  fast-changing value" shape one level up. The fix moved those reads into a small
  `MenuBarStatusLabel` view (`Sources/HeadroomApp/UI/MenuBarLabel.swift:77`). Settings'
  duplicate-login scan moved into a child view, `ClaudeDuplicateLoginScan`
  (`Sources/HeadroomApp/UI/SettingsView.swift:538`), for the same reason.
