---
title: "Measure snappiness offscreen, frame by frame — the perf-audit bench recipe and a SwiftUI hot-spot checklist"
date: 2026-10-04
category: ui
module: HeadroomApp/UI
problem_type: developer_experience
component: frontend
severity: medium
applies_when:
  - "A popover, Settings, or menu bar change feels sluggish or janky but looks correct in still renders"
  - "Adding or reviewing an implicit animation, a per-frame @State write, or an observable read in a scene closure in HeadroomApp views"
  - "Seeding a default @State and correcting it in onAppear, or doing formatter or row-invariant work inside a per-row body"
  - "Claiming a SwiftUI performance win, which needs a back-to-back before and after on main-thread CPU rather than wall clock"
symptoms:
  - "The popover open and Settings open and navigation did not feel snappy while the render harness showed a correct final layout"
  - "`--render-popover` captures stills about one second after hosting (arrivalDelay + 650ms), so it cannot show frame-by-frame motion or how many view bodies re-ran"
  - "Wall-clock and CPU numbers drifted between sessions (the pre-fix tree measured 116ms of single-account post-open CPU in one session and 68ms in another)"
  - "Static review produced hypotheses with no cost attached, and the app's own largest hot spot (a per-row DateFormatter, 540ms of trace samples) surfaced only under a profiler"
related_components:
  - PopoverView
  - SettingsView
  - HeadroomApp
  - UsageBarView
  - APISpendPeriod
  - PopoverRenderHarness
tags: [swiftui, performance, measurement, offscreen-benchmark, body-counts, time-profiler, signposts, checklist]
---

# Measure snappiness offscreen, frame by frame — the perf-audit bench recipe and a SwiftUI hot-spot checklist

## Context

On 2026-10-03 the user reported that opening the popover, and opening and moving around Settings,
still did not feel snappy. Settings had already had two motion passes (#136, #143). Nothing looked
broken, and every existing check passed:

- `--render-popover` hosts the popover, waits `HeadroomMotion.arrivalDelay + 650ms`, then captures
  one still (`Sources/HeadroomApp/PopoverRenderHarness.swift:293`). A still shows the settled
  layout. It cannot show what moved on the way there, how many view bodies ran, or what a scroll
  step cost.
- `--render-widgets` is a sweep of stills too: every widget style, family and fixture, checked for
  overflow.
- The unit suites test Core recipes and decisions. None of them counts how often SwiftUI re-runs a
  body.

Every problem the audit found was a cost of motion or of invalidation (SwiftUI deciding a view is out
of date and running its body again). None of them changed the final pixels: an entrance grow that
read as the window opening (FA1), the whole popover re-rendering on every scroll frame (SC1),
Settings re-rendering on every probe (ML1), Settings building the wrong pane first (LP1), and a date
formatter built for every row on every pass. Each one cost time the eye could feel.

The user does not allow agents to drive their desktop for measurement: no live clicks, no
on-screen capture. So the audit
measured offscreen. A static review (the swiftui-pro skill and a motion lens) produced hypotheses.
A benchmark harness then hosted the real `PopoverView` and `SettingsView` offscreen and measured
each one. That harness is now the hidden `--bench-ui` diagnostic; Guidance §1 says how to run it
and how it measures.

## Guidance

### 1. The measurement recipe

**Run it.** The harness is the hidden `--bench-ui` diagnostic
(`Sources/HeadroomApp/UIBenchHarness.swift`), dispatched from `Entry.main()` next to
`--render-popover` and listed in `AppComposition.usesInertNotificationClient` (KTD9). Build a
release binary with the body counter compiled in, copy it under a unique name, and run one section
per process, in the foreground, with a time limit (macOS has no `timeout`):

```bash
swift build -c release -Xswiftc -DHEADROOM_BENCH
cp .build/release/Headroom .build/release/HRBenchUI
perl -e 'alarm 900; exec @ARGV' .build/release/HRBenchUI --bench-ui popover --scenario multi5 --runs 12 \
  --json bench/popover-multi5.json > bench/popover-multi5.stdout 2>&1
```

| Section | What it measures |
| --- | --- |
| `popover` | One open per run, timed phase by phase (build, fit, window, layout, display, flush, re-fit, resize), then 600ms of driven frames: post-open CPU, bodies, and frames that re-ran the popover root. Then one untimed open printed frame by frame: `fittingSize`, scroll viewport, geometry reports, bodies. |
| `scroll` | Ten 60pt steps through the card list per sweep (`--runs` sweeps): CPU and bodies per step, then the indicator's hide. |
| `settings` | Settings opened on each stored pane in turn (or `--pane`): wall time, CPU, bodies, and whether General was built (LP1). |
| `switch` | Instant switches over every ordered pair of panes (`--runs` passes), then each pane from General and back, animated. |
| `counts` | Bodies and CPU per interaction: Settings opening, a change only the menu bar reads, refreshes with changed and unchanged data, saved-key presence, and the popover's first-open arrival, refreshes and idle. |
| `scene` | ML1's stand-in for `HeadroomApp.body` against a direct Settings host. |
| `all` | All of the above in one process, for a trace. |

`--scenario` picks the store fixture (`multi5` by default, `multi20` for `scroll` and `scene`).
Stdout is a human-readable table; `--json` also writes cold, warm median and p90, CPU and body
counts per scenario, so two builds can be diffed. Run 0 in each process is the cold open.

**The body counter compiles out of shipping builds.** `BenchCounters`
(`Sources/HeadroomApp/BenchCounters.swift`) is live only under `-DHEADROOM_BENCH`. Without the
flag, `hit` and `mark` are inlined no-ops, so the `let _ = BenchCounters.hit("Name")` line at the
top of each instrumented body costs nothing. Timings still run, body counts print as unavailable,
and `switch` can't run, because the pane seam is compiled out too. The instrumented bodies are the
ones this checklist relies on: the popover root and its `TimelineView` closure, the cards, account
sections, meter rows and gauges, the scroll chrome, the spend card, `MenuBarStatusLabel`, and the
Settings root, sidebar, scaffold, each pane, the specimen and `ClaudeDuplicateLoginScan`. Add a
line when a new view joins that list. `PopoverView` also marks each `onScrollGeometryChange`
report and `cardsHeight` write; that marker is the frame-by-frame viewport readout that exposed
FA1's grow.

**How it hosts.** Every window is parked the way `PopoverRenderHarness` parks its windows: on
screen for the window server but below the wallpaper, never key, with the app never activated
(`makeWindow`). A popover open models an assumed version of what `MenuBarExtra(.window)` does: ask
the content for its size (124pt before any layout, because `cardsHeight` starts at 0), make the
window, lay out, draw, flush, ask again, and resize once if the answer changed. `clock.now` is read
between every step and `CLOCK_THREAD_CPUTIME_ID` around the whole, so each phase gets its own
wall time and the open gets main-thread CPU.

**It drives frames itself.** The parked window is occluded and nothing drove its display cycle:
animations and post-open geometry updates rendered only when the bench ran a pass (observed, not a
documented AppKit guarantee). So it runs 60Hz passes that do work only when something is dirty
(`Host.framePass`), the way AppKit treats a visible window. Walking a clean 20-account tree on every
frame would add about 4ms of harness-only cost. Steps that wait until quiet (Settings opening, a
pane switch) loop a 1ms sleep plus a full render pass until a turn runs no view bodies.

**Every scenario is signposted** (subsystem `co.zantos.headroom.bench`, `.pointsOfInterest`), with
the scenario, pane or switch in the label, so a Time Profiler trace can be sliced by scenario.

**Seams.** Settings' pane selection is private `@State`, so `HEADROOM_BENCH` builds compile in a
`BenchSettingsSeam` notification that `SettingsView` applies the way a sidebar click does
(`paneSwitchIsInstant`, then `sidebarSelection`). LP1's first selection still comes from
`loadPreferences`. `App.body` can't be hosted in a view, so `BenchSceneStandIn` builds the label and
Settings the way `HeadroomApp.body` does today. If the scene body changes shape, change the
stand-in to match.

**Fixtures and hygiene.**

- Stores come from `DemoFixture`: the single-account snapshots, `multiFixture(for: .multiThree)`
  and `(for: .multiFive)`, and the `multi-20` account list without its simulated 4-second probes, so
  `refreshAll()` lands every row before timing starts. Settings gets in-memory key stores and
  `ClaudeDuplicateLoginDetector(readAccountUUID: { _ in nil })`, so the bench never touches the
  Keychain or the user's `.claude.json`.
- Every run gets fresh `UserDefaults` suites (`co.zantos.headroom.bench.<UUID>` and
  `co.zantos.headroom.bench.accounts.<UUID>`) and deletes them before exit, plist included.
  `removePersistentDomain(forName:)` alone left the files behind (eleven after the audit). Deleting
  the file straight away doesn't work either: cfprefsd writes the emptied domain about 10 seconds
  later, or when the process exits, and re-creates it. So the harness runs a read-only
  `defaults read <suite>` first, which makes cfprefsd write immediately, and then deletes the file.
- Measure release builds only. A debug build runs unoptimized generic SwiftUI code and distorts
  every number.
- The unique binary name (`HRBenchUI` above, or `Headroom-before` and `Headroom-after`) keeps the
  trace, `ps`, and Instruments' per-binary attribution unambiguous when `/Applications/Headroom.app`
  is installed and running. Frozen copies also let you re-run the old build after the tree has moved
  on. `--bench-ui` is dispatched before the single-instance check, so it runs beside the real app.

**Time Profiler, sliced by signposts.**

```bash
xcrun xctrace record --template 'Time Profiler' --instrument 'Points of Interest' \
  --output bench.trace --launch -- .build/release/HRBenchUI --bench-ui all --runs 8
Scripts/bench-trace-summary.py bench.trace
```

The script exports the trace's time-profile and signpost tables into `bench.trace.export/`. It keeps
main-thread samples, assigns each to the bench interval that contains it, and prints, per scenario,
the share of samples under known cost buckets (layout `sizeThatFits`, CoreText and text layout,
`DateFormatter`/`udat_`, accessibility, AppKit controls and CoreUI, glass and material, geometry
actions) and the nearest frame from the app's own binary. That second view is how
`APISpendPeriod.displayLabel` surfaced. A full-suite trace exports to about 170MB of XML, so the
parsed samples are cached next to the export.

**Caveats.** Everything is offscreen; the real `MenuBarExtra` and `Window` scenes are never driven.
120Hz, GPU and Liquid Glass compositing are not measured, and thread CPU time counts only the
app's main thread, not WindowServer. The audit's machine had Xcode 27 / Swift 6.4 (AGENTS.md names
26.6 / 6.3.3) on macOS 26.6.2, so the SwiftUI runtime was the OS's.

### 2. What to measure

- **Cold and warm, separately.** Run 0 in a fresh process pays first-use costs (type metadata,
  fonts, images). In the baseline suite the single-account popover's synchronous open took 101ms
  cold against 38ms warm, and 397ms against 308ms at 20 accounts. Prime what the real app would
  already have drawn: the bench renders `MenuBarStatusLabel` first, because the status item renders
  at launch, and opens the popover before timing Settings, because Settings opens from the popover.
  Compare warm medians of 12 runs, and report cold on its own.
- **Body counts for each interaction:** the open, one scroll step, a pane switch, one account
  refresh, a change only the menu bar reads, and idle. Each has an expected count, and for the
  popover root it is usually zero. 230 bodies for one scroll step is a finding before any timing.
- **Geometry frame by frame after the open.** Print the scroll viewport height (and `fittingSize`)
  after every 16ms frame for the first ~500ms. A healthy open goes from 0 to its final value once.
  Anything in between is motion that someone may never have chosen (FA1).
- **Main-thread CPU for each step:** the open (the synchronous part and the 600ms after), each scroll
  step, each pane switch, each store change. Compare against the 16.7ms frame at 60Hz.
- **Time Profiler sliced by signposts**, to explain the numbers: how much is layout, text,
  formatters or accessibility, and which of your own frames sit closest to the cost.

### 3. Discipline

- **Re-run "before" back to back with "after".** The pre-fix tree measured 116ms of post-open CPU
  (single account) in one session and 68ms in another (the harness also changed between the two). Compare only pairs run minutes apart, on the
  same machine state. Keeping the old binary as a renamed copy makes this free.
- **Compare main-thread CPU when wall-clock time is noisy.** Wall time includes sleeps, scheduling
  and other processes. `CLOCK_THREAD_CPUTIME_ID` counts only the work the main thread did.
- **Release builds only.**
- **Never accept a still render as evidence about motion or cost.** `--render-popover` proves the
  settled layout. AGENTS.md already says meter visual acceptance needs the live window, and the same
  goes for anything that moves or re-renders.
- **Measure at the account counts people run.** Several of these costs grew with accounts and looked
  fine at one. Run single, 5 and 20 (the `multi-20` fixture has 4 provider cards and 60 account
  sections).

### 4. Snappiness checklist

Check these first in any SwiftUI view that opens, scrolls, or stays on screen while data changes.

1. **An implicit `.animation(_:value:)` around a measured or self-sizing container.** It animates
   every size change in its subtree that lands in the same update, including the first layout. Put
   it on the smallest view, or use `animation(_:body:)` for a property-only change. See
   `docs/solutions/ui/popover-feather-animation-scope-grew-card-list.md` (FA1).
2. **A per-frame source written into `@State` that a large body reads** (scroll geometry, geometry
   during motion, timers, a drag's `onChanged`). Every frame re-runs the whole body. Route it through
   an `@Observable` model that only leaf views read. See
   `docs/solutions/ui/popover-scroll-geometry-state-rerendered-whole-popover.md` (SC1).
3. **Observable reads in `App.body` or in scene closures, and objects built there.** `MenuBarExtra`
   and `Window` run their closures inside `App.body`, so a store read there re-runs the whole scene,
   and a new instance on every pass makes the views that receive it unequal. The same shape one level
   down: a `.task(id:)` on a root view, keyed on store data, re-runs the root. Move it into a small
   child view, as DL1 did with `ClaudeDuplicateLoginScan` (`Sources/HeadroomApp/UI/SettingsView.swift:538`).
   See `docs/solutions/ui/menubarextra-window-closures-run-in-app-body.md` (ML1).
4. **Seeding `@State` with a default, then correcting it in `onAppear`.** SwiftUI builds the
   default's subtree first (twice, in Settings' case), then plays the correction as an animated
   change. Start at nil, render nothing until the real value arrives, and make that arrival
   non-animated (LP1, Example 3).
5. **A formatter built on every call inside a label that runs per row, per pass.** `DateFormatter()`
   plus `setLocalizedDateFormatFromTemplate` opens a new ICU formatter each time. Use
   `Date.FormatStyle`, and compute values that are the same for every row once per pass (Examples 1
   and 2).
6. **A computed property, read inside each row, that re-derives every row.** The old spend card's
   `amountColumnWidth` rebuilt every row's model from inside each row: N + N² formatter builds and N²
   string measurements on every pass. Compute it once in `body` and pass it down (Example 2).
7. **Child views that take fresh closures, or a `Date()` built in the body.** SwiftUI can't prove
   those inputs unchanged, so the child re-runs on every parent pass (SC1 records a probe showing
   it). `ProviderCardView` still takes fresh closures (open in BUGS.md), and `AppearanceSpecimen`
   passes `now: Date()` (`Sources/HeadroomApp/UI/AppearanceSpecimen.swift:124`).
8. **`ViewThatFits` in a repeated row.** It evaluates its candidates in order and uses the first
   whose ideal size fits, so a row that falls to a later rung pays for measuring the earlier ones.
   The meter rows have two rungs (full, `Sources/HeadroomApp/UI/UsageBarView.swift:362`) and three
   (micro, `:403`), and the cost repeats for every row on every pass. `ViewThatFits` frames sat under
   about 2.6% of popover-open main-thread samples in the trace.
9. **Alignment guides that read text metrics.** `capHeightCentered`
   (`Sources/HeadroomApp/UI/OpticalLeading.swift:210-218`) reads `dimensions[.firstTextBaseline]`,
   which forces text layout during alignment (about 0.9% of popover-open samples).
10. **One async write per item into observed state.** Each `await` followed by a write is its own
    update, and can be its own root pass. Collect the results and write once, behind a change check,
    as `refreshSavedKeyPresence` now does (`SettingsView.swift:471-479`). The trade-off: the write
    lands at the end of the sweep, so a change made during the sweep can be overwritten (the
    low-severity residual noted in #157's description).

**What the trace says is SwiftUI's own cost, not Headroom's to fix first.** Generic SwiftUI layout
and text measurement dominate. Layout frames sat under about 49% of the popover's synchronous-open
samples and about 82% of the pane switch's runloop-driven samples (the buckets overlap, so these
percentages don't add up to 100). After that come accessibility graph construction, AppKit control
metrics (CoreUI measuring the steppers, switches and segmented controls in Settings), and Liquid Glass
at about 1.5%. The leverage is doing that work fewer times (fewer bodies, fewer passes, fewer rows
built), not making a single pass cheaper.

## Why This Matters

Before #157, measured on the bench (warm medians of synchronous-open wall time, release build), the
popover's build took 38, 53, 68 and 308ms at 1, 3, 5 and 20 accounts. That build is still the same.
What #157 removed is the work that came after it. The pairs below were run back to back; the
millisecond figures in the first six rows are also in #157's description, and the last row compares
two full-suite traces recorded in separate sessions:

| Interaction | Before | After |
| --- | --- | --- |
| Popover, work in the 600ms after open (1 / 5 / 20 accounts) | 68 / 117 / 402ms | 16 / 33 / 270ms |
| Popover root re-runs after open | 4–12 | 0 |
| One scroll step, 20 accounts | 230 bodies, 41ms | 1 body, 5.5ms |
| Change only the menu bar reads, Settings on Accounts, 20 accounts | 7 bodies, 47ms | 0 bodies, 0.3ms |
| Refresh with unchanged data, same setup | 14 bodies, 100ms | 0 bodies, 1ms |
| Settings open, per pane, 5 accounts | baseline | 8–25% less CPU (Appearance 119 → 104ms) |
| General pane built when Settings opens on another pane | 2 | 0 |
| Month-label `DateFormatter`/ICU time, summed over every popover open in one full-suite trace | 540ms (`udat_open` alone 201ms) | 8ms |

Still slow and still open: a pane switch builds the new pane in the click's frame (about 24–68ms at
5 accounts, the heavy panes 60–70ms; about 259ms into Accounts at 20) before its 200ms blur-in
starts, and after #157 Settings still opens in about 56–118ms of main-thread CPU per pane at 5
accounts and about 418ms on Accounts at 20.

The cost grows with accounts. The tested envelope is 20 accounts per provider
(`AccountRegistry.testedEnvelope`, `Sources/HeadroomCore/Settings/AccountRegistry.swift:22`). At 20,
one popover build is 308ms, about 18 frames at 60Hz, so anything that makes it run again (a scroll
frame, a probe, a store change) lands hardest on the people with the most accounts. Every one of these
problems looked fine with a single account.

No correctness check would have failed, because the output was always right. FA1's grow shipped in
July 2026 and SC1's per-frame write in September, and both lasted until #157 (still unmerged as of this writing). Without body counts and
frame-by-frame probes, the next regression like them will ship silently too.

## When to Apply

- Someone says the app "doesn't feel snappy" or "feels slow", and nothing looks broken.
- Before and after any change to the popover, Settings, or the scene body that adds an animation, a
  geometry reader, a scroll callback, a timer, or a store property that changes often (the slosh's
  `probingAccounts` changes twice per probe).
- When adding a view or a formatter that runs once per account row.
- When adding work that runs at open: an `onAppear` correction, a `.task` that writes state, a staged
  arrival.
- When reviewing a diff that adds `.animation(_:value:)`, `onScrollGeometryChange`,
  `onGeometryChange`, `ViewThatFits`, a custom alignment guide, or `DateFormatter()` or
  `NumberFormatter()` inside a body.
- Before claiming a performance fix. Measure it as a back-to-back pair.

## Examples

**1. A formatter on every call becomes a format style.**

Before (main as of #156, `Sources/HeadroomCore/Models/UsageModels.swift:750-765`):

```swift
case .currentMonth:
    var calendar = calendar
    calendar.timeZone = .current
    let formatter = DateFormatter()            // a new ICU formatter on every call
    formatter.calendar = calendar
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMM")
    return formatter.string(from: now)
```

After (`UsageModels.swift:752-760`):

```swift
case .currentMonth:
    let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: .current, calendar: calendar, timeZone: .current)
        .month(.abbreviated)
    return now.formatted(style)
```

The output matched the old formatter for all 12 months in 17 locales, checked once during the audit
with a throwaway comparison script.
`currentMonthDisplayLabelMatchesLocalizedAbbreviatedMonth`
(`Tests/HeadroomCoreTests/APISpendPresentationTests.swift:11-25`) pins it against the old formatter
in the test machine's locale. In the after trace, `udat_open` is gone from popover opens, and what
little ICU time is left includes Foundation's `ICUDateFormatter` pattern cache. That fits format
styles reusing their formatter rather than opening a new one per call.

**2. Work that is the same for every row runs once per pass.**

Before (main as of #156, `Sources/HeadroomApp/UI/APISpendSectionView.swift:35-37`, `:50`, `:101-107`,
`:302`):

```swift
private var amountColumnWidth: CGFloat {     // read inside every row's amount column
    Self.amountColumnWidth(for: store.apiSpendProviderOrder.compactMap { rowModel(for: $0).amount })
}

var body: some View {
    let models = store.apiSpendProviderOrder.map(rowModel(for:))
    // …
}

private func rowModel(for id: ProviderID) -> SpendRowModel {
    // …
    periodLabel: store.apiSpendPeriod.displayLabel(now: now)   // one DateFormatter per call
}

// In amountColumn(_:), once per row:
.frame(width: amountColumnWidth, alignment: .trailing)
```

After (`APISpendSectionView.swift:44-48`, `:100-105`):

```swift
var body: some View {
    let models = rowModels()
    if !models.isEmpty {
        // Measured once per pass, not once per row.
        let amountWidth = Self.amountColumnWidth(for: models.compactMap(\.amount))
        // … spendRow(model, amountWidth: amountWidth) …
    }
}

private func rowModels() -> [SpendRowModel] {
    let order = store.apiSpendProviderOrder
    guard !order.isEmpty else { return [] }
    let periodLabel = store.apiSpendPeriod.displayLabel(now: now)
    return order.map { rowModel(for: $0, periodLabel: periodLabel) }
}
```

With N spend rows, the old shape built N + N² formatters and measured about N² (N·(N+1)) amount strings
(`NSString.size(withAttributes:)`, `:27-33`) on every popover pass. The new shape builds one label
and measures N strings.

**3. Start state at nil, and make the first value arrive without animation (LP1).**

Before (main as of #156, `Sources/HeadroomApp/UI/SettingsView.swift:37`, `:232-238`, `:459`):

```swift
@State private var sidebarSelection: SettingsPane? = .general

ZStack(alignment: .topLeading) {
    detail
        .id(selectedPane)
        .transition(paneSwitchIsInstant ? .identity : .settingsPane(reduceMotion: reduceMotion))
}

// In loadPreferences(), called from .onAppear:
sidebarSelection = storedPane
```

After (`SettingsView.swift:42`, `:236-242`, `:449-451`):

```swift
@State private var sidebarSelection: SettingsPane?

ZStack(alignment: .topLeading) {
    if sidebarSelection != nil {
        detail
            .id(selectedPane)
            .transition(paneSwitchIsInstant ? .identity : .settingsPane(reduceMotion: reduceMotion))
    }
}

// In loadPreferences(), called from .onAppear:
paneSwitchIsInstant = true    // the opening pane arrives with the window, not as a switch
sidebarSelection = storedPane
```

Before, opening Settings on any pane other than General built `GeneralSettingsPane` twice in the
first layout, then built the real pane and played the pane transition inside the window's fade-in.
After, General isn't built at all. Together with the other Settings fixes in #157 (the batched
saved-key write, DL1, ML1), Settings opens with 8–25% less CPU per pane at 5 accounts.
Don't move the seed into `init` instead: `Window` content is built inside `App.body`, so a value
seeded there can be stale when the window reopens (see "The flip side" in the ML1 doc).

## Related

- `docs/solutions/ui/popover-feather-animation-scope-grew-card-list.md`: FA1, the open-time grow
  that the frame-by-frame viewport probe found.
- `docs/solutions/ui/popover-scroll-geometry-state-rerendered-whole-popover.md`: SC1, found by body
  counts per scroll step.
- `docs/solutions/ui/menubarextra-window-closures-run-in-app-body.md`: ML1, found by body counts on
  a stand-in for the scene body. Its "flip side" section explains why LP1 doesn't seed in `init`.
- `docs/solutions/popover-scrollview-zero-height.md`: why `PopoverView` measures `cardsHeight`, which
  is why the pre-layout `fittingSize` is 124pt.
- AGENTS.md › Gotchas › "Meter visual acceptance must use the live `MenuBarExtra` window": the same
  rule about stills, from the visual side.
- #157 (open, unmerged as of 2026-10-04): every fix above and the paired numbers. #136 and #143: the
  earlier Settings motion passes.
- `BUGS.md` › "Popover & Settings snappiness residuals (2026-10-03 perf audit)". Still open:
  - A pane switch builds the new pane in the click's frame, then blurs it in (~24–68ms at 5 accounts, the
    heavy panes ~60–70ms; ~259ms into Accounts at 20).
  - Every `ProviderCardView` re-renders on any store change (after #157, ~240ms CPU per refresh at 20 accounts,
    ~140ms at 5),
    and `PopoverView` calls `appDisplaySnapshot` about 3× per account.
  - The first open per launch (the M9A arrival) pegs the main thread for ~740ms at 20 accounts
    after #157:
    three state writes per meter row.
  - The duplicate-login scan reruns on every Claude capture while Settings is open, and overlapping
    detached scans can stack.
  - The saved-key presence check reads the secret, where an attributes-only query would do.
  - `--render-popover`'s multi-account path never draws the spend card.
- Also open: a macOS 15 (Sequoia) runtime check. The Tahoe live check is done: on 2026-10-04 the
  `--demo multi-5` popover's `MenuBarExtra` window first appeared at its final 384×764pt and never
  resized (sampled with `CGWindowListCopyWindowInfo` every ~1.5ms), and the same window was reused
  on reopen. So `MenuBarExtra` sizes after the first layout, not from the 124pt pre-layout answer.
