---
title: "Keep observable reads out of `App.body` — the menu bar label re-rendered Settings and the popover on every probe"
date: 2026-10-04
category: ui
module: HeadroomApp/HeadroomApp
problem_type: performance_issue
component: frontend
symptoms:
  - "With Settings open, every probe start, probe end and merge re-rendered the open pane, including panes that showed nothing that had changed"
  - "An open popover most likely rebuilt its whole card list on each of those changes (inferred; the stand-in did not host it)"
  - "At 20 accounts with Accounts showing, a store change only the menu bar label reads cost 7 view bodies and 47ms on an offscreen stand-in for the scene"
  - "Nothing looked wrong: Settings felt fine whenever no probe was running, and no check in the repo counts scene passes"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
framework_version: "swiftui macos 26.6.2 (Xcode 27 / Swift 6.4 toolchain, MenuBarExtra .window)"
related_components:
  - MenuBarExtra
  - Window
  - MenuBarStatusLabel
  - SettingsView
  - AppComposition
  - CredentialStore
tags: [swiftui, app-body, scene, menubarextra, window, observable, state-invalidation, performance]
---

# Keep observable reads out of `App.body` — the menu bar label re-rendered Settings and the popover on every probe

## Problem

`MenuBarExtra`'s label closure and `Window`'s content closure run inside `App.body`. Headroom's
label closure read three `UsageStore` properties (`menuBarMeters`, `showMenuBarPercentage`,
`menuBarUpdatingProviders`), so all three became dependencies of the whole scene body (ML1). Every
probe start, probe end and merge re-ran `App.body` (as modelled by an offscreen stand-in), which
built a new `PopoverView` and a new `SettingsView`. SwiftUI could skip neither: the popover takes a
closure, and Settings was handed a freshly built `CredentialStore` on every pass. So the open
Settings pane re-rendered on every timer probe, whatever it showed, and by the same mechanism an
open popover would have too.

This was measured offscreen on a stand-in for the scene body. The real `MenuBarExtra` scene was
not driven, and a live check of the label in the real menu bar was still pending when this was
written.

The label has read the store inside the scene body since July 2026, when that cost one scene
pass per merge. The menu-bar slosh (#152, merged 2026-10-02) added `menuBarUpdatingProviders`,
whose underlying dependency (`probingAccounts`) changes at every probe start and every probe end,
timer probes included. From then until
#157, each probe could cost up to three scene passes (start, end, and the merge), depending on how
SwiftUI coalesced them.

## Symptoms

- On the offscreen bench's stand-in (`multi-20`, Settings showing Accounts), a store change that
  only the label reads cost 7 view bodies and 47ms. A refresh whose data did not change cost 14
  bodies and 100ms; a refresh with changed data, 14 bodies and 123ms. Full table under Solution.
- Probes of accounts that never slosh a pill still invalidated the scene. `probingAccounts` changes
  twice per probe for every account (`Sources/HeadroomCore/Engine/UsageStore.swift:1309-1315`),
  and Observation tracks that stored property, not the computed `menuBarUpdatingProviders` set
  built from it (`:711-715`). `menuBarMeters` works the same way: it reads the `snapshots`
  dictionary (`:108`), so a snapshot write for any account invalidated every reader.
- The cost grew with accounts twice over: more probes per interval, and a bigger open pane
  (Accounts at 20 accounts per provider) to rebuild each time.
- Nobody reported it as such. The audit found it while measuring the user's report that Settings
  did not feel snappy.

## What Didn't Work

1. **Scene passes are invisible.** In the SDK, `_printChanges()` and `_logChanges()` are declared
   only on `View` and `ViewModifier` (`SwiftUI.swiftinterface:16366-16376` and `SwiftUICore.swiftinterface:18868`, Xcode 27.0), so the
   usual debug hook cannot go in `App.body`. Nothing in the repo counts scene passes, and
   `--render-popover` captures stills with no scene at all. The bench caught it only because its
   body counters showed Settings bodies running when nothing in Settings had changed.
2. **The scene code looks cheap.** `MenuBarExtra { … } label: { … }` and
   `Window { SettingsView(…) }` read like declarations, and building those structs costs almost
   nothing. The cost comes after: SwiftUI compares the new `PopoverView` and `SettingsView` values
   with the old ones and re-runs any body whose inputs differ. A closure literal
   (`PopoverView(store:) { openSettings() }`) and a new actor instance always differ. The SC1 doc
   records a probe showing a closure-taking child re-running on every parent pass.
3. **The reads were in the natural place.** Passing store values into `MenuBarLabel` as arguments
   is the normal way to feed a value-driven view, and `MenuBarLabel` must stay value-driven because
   the Settings specimens pass it their own meters (`Sources/HeadroomApp/UI/SettingsRows.swift:560`).
   Inside a `View`'s body, that pattern costs only that view. Inside a scene closure, the "parent
   body" is the whole app.
4. **It got much worse quietly.** Before #152 the label's reads changed on merges. The slosh added
   a read that changes on every probe start and end. #152 was a motion feature that did not touch
   Settings, so nobody re-measured Settings.
5. **Settings looked fine whenever nothing was probing.** The extra passes arrive only while
   probes run. Opening Settings and clicking around between polls showed nothing. With many
   accounts the lanes spend a large share of each interval probing, which is when it hurt.

## Solution

The fix is in #157 (open, unmerged as of 2026-10-04). It makes two changes to the scene body and
none to `UsageStore`.

Before (main as of #156, `Sources/HeadroomApp/HeadroomApp.swift:487-561`, abbreviated):

```swift
var body: some Scene {
    MenuBarExtra {
        PopoverView(store: store) { openSettings() }
            // …
    } label: {
        MenuBarLabel(
            meters: store.menuBarMeters,                      // read by App.body
            showsPercentage: store.showMenuBarPercentage,     // read by App.body
            appearance: .menuBar,
            updatingProviders: store.menuBarUpdatingProviders // reads probingAccounts
        )
        .preferredColorScheme(resolvedScheme)
        // … tasks and theme observers
    }
    .menuBarExtraStyle(.window)

    Window("Headroom Settings", id: "settings") {
        SettingsView(
            store: store,
            // …
            credentialStore: DemoFixture.isEnabled
                ? CredentialStore(apiKeyStore: DemoAPIKeyStore())
                : CredentialStore(),                          // a new actor every scene pass
            notificationClient: AppComposition.notificationClient
        )
    }
}
```

After (`HeadroomApp.swift:511-549`, `MenuBarStatusLabel` at
`Sources/HeadroomApp/UI/MenuBarLabel.swift:73-91`, `AppComposition.settingsCredentialStore` at
`HeadroomApp.swift:1157-1162`):

```swift
} label: {
    MenuBarStatusLabel(store: store)
        .preferredColorScheme(resolvedScheme)
        // … tasks and theme observers, unchanged
}

Window("Headroom Settings", id: "settings") {
    SettingsView(
        // …
        credentialStore: AppComposition.settingsCredentialStore,
        notificationClient: AppComposition.notificationClient
    )
}

// MenuBarLabel.swift
struct MenuBarStatusLabel: View {
    let store: UsageStore

    var body: some View {
        MenuBarLabel(
            meters: store.menuBarMeters,
            showsPercentage: store.showMenuBarPercentage,
            appearance: .menuBar,
            updatingProviders: store.menuBarUpdatingProviders
        )
    }
}

// HeadroomApp.swift
enum AppComposition {
    /// The Settings window's key store, one per launch rather than one per scene-body pass.
    static let settingsCredentialStore: CredentialStore = DemoFixture.isEnabled
        ? CredentialStore(apiKeyStore: DemoAPIKeyStore())
        : CredentialStore()
}
```

- `MenuBarStatusLabel` takes the store and reads the three properties in its own body. The scene
  body only hands it the reference.
- `MenuBarLabel` (`MenuBarLabel.swift:19`) is unchanged and still value-driven, so
  `MenuBarPreviewPill` (`SettingsRows.swift:552-563`) keeps feeding it fixed meters.
- The label's modifiers (`store.start()`, the appearance monitor, the theme observers) stay on the
  label in the scene body (`HeadroomApp.swift:512-536`). They read the App's own `@State`, which
  changes only on theme switches.
- `settingsCredentialStore` is a `static let`, built once per launch, next to `notificationClient`
  (`:1166`). The demo-versus-Keychain choice moved with it unchanged.

Measured on the offscreen perf bench (then uncommitted; now `--bench-ui`), `multi-20`, Settings showing
Accounts. The bench cannot host the real `MenuBarExtra` scene, so it timed a stand-in view whose
body built the label and `SettingsView` the way the scene body does, with old and new builds run
back to back:

| Store change | Before | After |
| --- | --- | --- |
| Only the label reads it (such as a probe starting) | 7 bodies, 47ms | 0 bodies, 0.3ms |
| Refresh, data unchanged | 14 bodies, 100ms | 0 bodies, 1ms |
| Refresh, data changed | 14 bodies, 123ms | 1 body, 49ms |

The 1 body left on a data change is, by inference, Settings reacting through its own reads to
data it shows. That is the work the change calls for, not the scene's. Absolute bench numbers moved
with machine load (the FA1 doc records the pre-fix tree at 116ms in one session and 68ms in
another), so quote the paired before and after.

## Why This Works

A view's body is its own observation scope. SwiftUI records the observable properties a body reads
and, when one changes, re-runs only that body. The reads in `MenuBarStatusLabel.body` subscribe
`MenuBarStatusLabel`. `App.body` no longer reads them, so a probe no longer invalidates the scene.
Passing `store` registers nothing: it is App `@State` holding a reference, and handing a reference
to a child reads no property. That is also why SC1's popover root can hand its scroll model down.

The closures are part of `App.body` because SwiftUI's initializers do not let them escape. From
the Xcode 27.0 SDK (MacOSX27.0, `SwiftUI.framework/.../arm64e-apple-macos.swiftinterface`):

```swift
// MenuBarExtra, line 2094
nonisolated public init(@SwiftUICore.ContentBuilder content: () -> Content,
                        @SwiftUICore.ContentBuilder label: () -> Label)
// Window, line 32758 (the overload a string-literal title resolves to)
nonisolated public init(_ titleKey: SwiftUICore.LocalizedStringKey, id: Swift.String,
                        @SwiftUICore.ContentBuilder content: () -> Content)
// SwiftUICore.swiftinterface, line 8598
public typealias ContentBuilder = SwiftUICore::ViewBuilder
```

Neither closure is `@escaping`, so SwiftUI cannot keep it for later. These scenes store the built
views, so they run each closure inside the initializer. Those initializers are called in `HeadroomApp.body` (`HeadroomApp.swift:487`), so the
label view and `SettingsView` are built there, and every observable read inside them counts as a
read by `App.body`. For contrast, the same SDK gives `WindowGroup` an escaping
`init(id:makeContent:)` (line 31019, which forwards to an internal `lazyContent:` initializer on
macOS 14.5+) and deprecates the non-escaping `init(id:content:)` from macOS 15 (lines 2512, 2516),
so a trailing-closure `WindowGroup` on macOS 15 defers its content. `Window`, `MenuBarExtra`,
`Settings` and `UtilityWindow` have only the non-escaping form there. These signatures were read
from the Xcode 27 SDK, not the Xcode 26.6 SDK that AGENTS.md names; the shape is unlikely to
differ, but that was not checked.

Building the credential store once removes the input that made every new `SettingsView` unequal.
By inspection, `App.body` still runs on theme changes (`resolvedScheme` reads the App's
`appearancePreference` and `systemIsDark`). The `softwareUpdates` `@StateObject` would also trigger
a pass if it published, but today its only `@Published` property is set only in its `init`. Neither
was measured. `PopoverView` still takes a closure, so a theme switch still rebuilds an open popover. At that rate it doesn't
matter.

### The flip side: a window's view is built at the last scene pass

Because `Window`'s content closure runs during `App.body`, the `SettingsView` value a window opens
with is the one built at the last scene pass. Whether SwiftUI re-runs the scene body on
`openWindow` was not checked. Before the fix, that value was at most about one polling interval old. Now it can date
from launch or the last theme switch.

So anything a window's view computes in `init` from changing state is frozen at that moment.
`State(initialValue:)` takes its value eagerly (`public init(initialValue value: Value)`,
`SwiftUICore.swiftinterface:20009`; the lazy autoclosure form at `:20008` is `internal` and only
for `Observable` classes), and SwiftUI uses that value when it first creates the window's view.

LP1, in the same commit, is where this applied. Settings must open on the stored pane, so
`sidebarSelection` starts nil (`Sources/HeadroomApp/UI/SettingsView.swift:37-42`), and
`loadPreferences()`, called from `.onAppear` (`:160`), selects the pane (`:449-451`). Seeding it
from `preferences` in an initializer would freeze it at the last scene pass, unless SwiftUI re-runs
the scene body on open (not checked). A reopened window could then land on a stale pane instead of
the last one visited (R4). The LP1 comment
records both the double build it fixed and this reason.

## Prevention

- **No observable reads in a scene body or in a scene's content closures.** That means `App.body`
  and the closures of `MenuBarExtra` (content and label), `Window`, `Settings` and `UtilityWindow`
  (and `WindowGroup` too, conservatively, though its macOS 15 trailing-closure form defers), plus any computed property or helper on the `App` struct that they call. Wrap
  the reads in a small `View` that takes the model reference and reads in its own body, as
  `MenuBarStatusLabel` does. App-owned `@State` that changes only on a user action, such as the
  theme, is the acceptable exception.
- **Build per-launch objects once.** Never construct a class, actor or service inline in a scene
  closure. Make it a `static let` on `AppComposition` (as `settingsCredentialStore` and
  `notificationClient` are) or a stored `let` on the App. A new instance per scene pass makes the
  view that receives it unequal every time. Closure arguments have the same effect:
  `PopoverView`'s `{ openSettings() }` is tolerable only because the scene now rarely runs.
- **Don't seed a window's view state in `init` from anything that changes.** Read "now" in
  `.onAppear` or `.task`, as `loadPreferences()` does. The value passed to `State(initialValue:)`
  is whatever was true at the last scene pass.
- **A fast-changing store property is only as cheap as its widest reader.** Before adding one
  (the slosh's `probingAccounts` changes twice per probe), find every body that reads it, directly
  or through a computed property, and make sure none is a scene. Observation tracks the stored
  property, so a computed property that rarely changes its result still invalidates on every write
  underneath it.
- **How to check.** In a debug build, add `let _ = Self._printChanges()` to `SettingsView.body` and
  `MenuBarStatusLabel.body`. Run `swift run Headroom --demo multi-20`. Its Claude and Grok rows
  simulate 4-second probes (`Sources/HeadroomCore/DemoFixture.swift:327-332`), so the Claude and Grok
  lanes probe back to back for most of each 2-minute interval, and a pill sloshes for the 4 seconds
  its main account's probe runs. Open Settings on any pane
  and wait through a few probes. `MenuBarStatusLabel` should log at each probe start and end.
  `SettingsView` should log nothing between a probe's start and its result, because nothing in
  Settings reads probe state (`menuBarUpdatingProviders` has one reader in the app,
  `MenuBarLabel.swift:88`). `_printChanges()` can't go in `App.body`, so its children are the way
  to see a scene pass: if `SettingsView` logs at a probe start, something in the scene body is
  reading the store again. `_printChanges()` is an underscored debug API, so remove it before
  committing.

## Related Issues

- #157: this fix, together with the feather-scope fix (FA1), the scroll-chrome fix (SC1), Settings
  opening on its stored pane (LP1), the duplicate-login scan's move (DL1) and the spend-label fix
  from the same audit.
- #152: the menu-bar slosh, which added the per-probe read. AGENTS.md › "The menu bar's only
  motion is the slosh (Oct 2026)".
- `docs/solutions/ui/popover-scroll-geometry-state-rerendered-whole-popover.md`: SC1, the same
  "big body reads a fast-changing value" shape one level down, inside the popover. Its rule about
  giving large child views inputs SwiftUI can compare applies to the scene's children too.
- `docs/solutions/ui/popover-feather-animation-scope-grew-card-list.md`: FA1, from the same audit.
- Same commit, one level down: Settings' duplicate-login scan moved out of `SettingsView.body`
  into its own view, `ClaudeDuplicateLoginScan` (`SettingsView.swift:533-538`), so a Claude refresh
  re-runs that empty view instead of the Settings root (DL1).
- `BUGS.md` › "Popover & Settings snappiness residuals (2026-10-03 perf audit)". Still open: every
  `ProviderCardView` re-renders on any store change, so the popover's own data path stays
  expensive at 20 accounts even without scene passes.
