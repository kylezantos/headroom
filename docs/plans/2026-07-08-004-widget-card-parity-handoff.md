# Handoff — Widget Card Parity (STUCK) + Sync Fix (DONE)

**For:** the next agent (Fable) picking this up fresh.
**Date:** 2026-07-08. **Branch merged to `main`.** Author: prior session (Opus 4.8).

---

## TL;DR

Two separate problems were worked this session:

1. **iPhone/widget stale sync — SOLVED.** Root cause was the Mac app missing the iCloud
   Key-Value-Store entitlement, so it never published snapshots. Fixed by building the Mac app
   via Xcode automatic provisioning. The widget now shows live data ("from Mac · just now").
2. **Large-widget provider cards look different from each other — NOT SOLVED.** The two cards
   (Claude top, Codex bottom) read as different shades. We proved the *cards are pixel-identical*
   and the difference comes from the *background*, flattened the background in code, rebuilt,
   reinstalled, and cleaned up a huge pile of stale app copies — **and it still renders the old
   look.** The installed binary provably has the new code, yet the render is unchanged. That is
   the mystery to solve. See **"Where we're stuck."**

There is also an open **TestFlight** request (blocked on an App Store Connect API key).

---

## Problem 2 (the open one): the two cards look different

**Goal (user's words):** the widget should match the dark-mode iOS companion app — same
background, same card color — and the two provider cards should look identical to each other.

### What is PROVEN (with pixel measurements from the user's screenshots)

- **The two card fills are byte-for-byte identical.** Sampled blank card-fill regions across
  four different screenshots: always `(44–45, 47–48, 53–54)` for *both* Claude and Codex. The
  cards are not actually different colors, and they are fully opaque. This is **not** an opacity
  problem (the user asked — it isn't).
- **The difference is the BACKGROUND behind each card:**
  - Behind Claude (top): bright — `(58,60,66)` … `(64,67,82)` across screenshots. *Brighter than
    the card fill.*
  - Behind Codex (bottom): dark — `(12,14,19)` … `(19,21,28)`.
  - Same opaque card on a light surround (top) vs a dark surround (bottom) → simultaneous
    contrast makes identical cards read as different (top looks recessed/washed, bottom looks
    bright/raised).
- **It happens on BOTH the iOS and macOS widgets** (shared background code), which is why it felt
  "bizarre."
- **The companion app looks correct** because its background gradient + glow is spread over a
  tall full screen, so both cards sit on a consistent dark surround. The widget crushes that same
  gradient into a small tile, concentrating the bright top glow behind the top card.

### The code (both widgets read from the same shared values)

- Card fill/ring/shadow: `HeadroomWidgetColorValues.tile*` — identical for both providers, applied
  by a single card modifier with no per-provider branching (`IOSLargeProviderCardModifier` in
  `Sources/HeadroomIOSWidgets/Views/HeadroomIOSWidgetView.swift`, and the equivalent in
  `Sources/HeadroomWidgets/Views/HeadroomLargeWidgetView.swift`).
- Background: `HeadroomWidgetContainerBackground` (one file per widget target).
- Companion equivalents: `HeadroomTheme.tileFill` / `HeadroomTheme.backgroundView` in
  `Sources/HeadroomIOS/DesignSystem/HeadroomTheme.swift`. Same underlying `HeadroomWidgetColorValues`.

### The fix we applied (in this branch)

Flattened the widget container background so the surround is uniform and always darker than the
cards: removed the concentrated `RadialGradient` glow and reduced the gradient to a subtle
`containerBackgroundTop → containerBackgroundMiddle`, in **both**
`Sources/HeadroomIOSWidgets/Views/HeadroomWidgetContainerBackground.swift` and
`Sources/HeadroomWidgets/Views/HeadroomWidgetContainerBackground.swift`. Companion untouched.

Confirmed correct via an **offscreen `ImageRenderer`** comparison (before/after): the AFTER shows
both cards uniform. So the code change does what it should — *in an offscreen render.*

## Where we're stuck (READ THIS)

After the fix, we rebuilt + reinstalled the Mac app (v7), bumped build numbers (iOS 6→7→8,
macOS 6→7 to bust WidgetKit's cache), restarted `chronod`, and the user removed/re-added the
widget many times. **The live widget still renders the old bright-top background.** Then:

- `nm -u /Applications/Headroom.app/Contents/PlugIns/HeadroomWidgets.appex/Contents/MacOS/HeadroomWidgets`
  shows **no `RadialGradient`** → the installed binary IS the new flattened code.
- Installed appex `CFBundleVersion` = 7; binary mtime = **Jul 8 07:07** (rebuilt that morning).
- Yet the rendered background above Claude is still `(58,60,66)` — **brighter than the cards**,
  which the new opaque flat background (all ~16–21) **cannot** produce.

**Conclusion: the rendered brightness is NOT coming from our container-background code.** The
new code is installed but the render is unchanged. Two live hypotheses:

- **(A) WidgetKit snapshot cache** is serving a pre-update render that survived `chronod` restart,
  version bumps, and remove/re-add.
- **(B) System compositing / translucency.** Several of the user's screenshots show the macOS
  widget in an edit/Notification-Center context (a "−" remove button is visible). In Notification
  Center / edit mode, macOS composites widgets on a translucent, blurred panel — a bright backdrop
  could bleed through the top *regardless of our opaque background color*. If so, our code fix is
  aimed at the wrong layer, and the widget may look fine on the **desktop** (opaque context).

### Suggested next steps for Fable (in priority order)

1. **Find out WHERE the user views the widget.** Desktop (opaque) vs Notification Center / edit
   mode (translucent). Ask, or have them screenshot the widget sitting on the actual desktop. If
   it looks fine on the desktop and only bright in NC/edit, this is a system-context effect, not
   our bug — reset expectations accordingly.
2. **Force a brand-new widget identity to rule out cache.** Temporarily change the widget `kind`
   string (defined near `StaticConfiguration(kind:…)` in `Sources/HeadroomIOSWidgets/HeadroomIOSWidgets.swift`
   and `Sources/HeadroomWidgets/HeadroomWidgets.swift`) to something new, rebuild, reinstall,
   add the widget fresh. New kind = no cached snapshot. If it renders flat → it was a cache.
3. **Isolate cache vs translucency with a garish test background.** Temporarily set the container
   background to solid pure red. Reinstall. If the widget shows solid red → our background IS what
   renders (so it was a cache; the flatten will work once the cache clears). If it shows red only
   at the bottom and bright/tinted at the top → the top brightness is system translucency, not us.
4. **Last-resort cache clears:** reboot the Mac; or delete the app entirely (not just reinstall)
   before installing fresh.
5. The color fix itself (flatten background) is done and offscreen-verified; the blocker is purely
   getting the *rendered* widget to reflect the installed code.

### iOS side status

- Build 8 (with the flattened background) was installed to the physical iPhone via
  `xcrun devicectl device install app` earlier. It was **never visually re-confirmed** after the
  flatten, because the user pivoted to wanting TestFlight delivery instead.

---

## Problem 1 (SOLVED): stale sync — root cause & fix, for reference

- **Root cause:** the installed standalone `Headroom.app` publishes phone snapshots via
  `NSUbiquitousKeyValueStore`, which is inert without the `com.apple.developer.ubiquity-kvstore-identifier`
  entitlement. `Scripts/build-app.sh` **strips** that entitlement unless
  `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1`, AND that entitlement is *provisioning-gated*: a locally
  codesigned build with it gets **SIGKILLed at launch** (verified, exit 137) without an embedded
  provisioning profile. So the Mac silently never published; the phone froze on the last snapshot
  that propagated back when an Xcode-provisioned build was running.
- **Fix that works:** build the Mac app with Xcode automatic provisioning, which embeds a managed
  profile so the entitlement is honored:
  ```
  xcodebuild -project Headroom.xcodeproj -scheme Headroom -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .xcode-derived \
    -allowProvisioningUpdates HEADROOM_APP_GROUP_IDENTIFIER=group.com.kylezantos.headroom build
  ```
  Then install that `.app` to `/Applications`. Verify with (run from the SIGNED app, not `swift run`):
  `/Applications/Headroom.app/Contents/MacOS/Headroom --dump-phone-sync` → should show
  `syncToIPhoneEnabled: true` and a fresh `publishedAt`. Confirmed working (widget shows "just now").
- **Do NOT** reinstall a plain `./Scripts/build-app.sh` build over it — the default strips the
  entitlement and sync silently dies again. `build-app.sh` now takes
  `HEADROOM_PROVISIONING_PROFILE=…` to embed a profile, and warns when the entitlement is on
  without one. Full write-up is in `BUGS.md` → "iPhone sync — Mac needs the iCloud-KVS entitlement".

---

## LaunchServices stale-copy cleanup (important environmental hazard)

The Mac had **30+ registered copies** of `com.kylezantos.headroom(.widgets)` — old builds across
`~/.codex/worktrees/*`, other `conductor/workspaces/*`, a mounted DMG (`/Volumes/Headroom`), temp
dirs, and this session's reinstall backups. WidgetKit can serve the widget from any of them, which
made "reinstall + re-add" unreliable. We unregistered all but `/Applications/Headroom.app` (via
`lsregister -u <path>`, files untouched), ejected the DMG, and deleted our backups.

**Hazard for multi-session work:** every `xcodebuild`/`build-app.sh` in any worktree re-registers
its build product. If several sessions build in parallel, stale copies pile back up. The installed
appex was rebuilt at **07:07** by someone other than this session — coordinate so multiple agents
aren't fighting over `/Applications/Headroom.app`. To list copies:
```
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"$LSREG" -dump | sed -n 's/^[[:space:]]*path:[[:space:]]*\(.*Headroom\.app\) (0x[0-9a-f]*)$/\1/p' | sort -u
```

---

## TestFlight (open request — blocked on credentials)

The user wants the iOS build delivered via TestFlight (they'll delete the phone app and install
from there). **Blocked:** the machine has **no Apple Distribution certificate, no App Store Connect
API key, and no upload credentials** (only "Apple Development" + "Developer ID Application" certs).

To proceed, get from the user an **App Store Connect API key**: App Store Connect → Users and
Access → Integrations → App Store Connect API → Team Keys → generate (role: App Manager) →
download `AuthKey_XXXX.p8` to `~/.appstoreconnect/private_keys/`, plus the **Key ID** and
**Issuer ID**. Then: create the ASC app record for `com.kylezantos.headroom.ios` if needed,
archive for app-store distribution (`-allowProvisioningUpdates` can mint the distribution cert +
profile), set `ITSAppUsesNonExemptEncryption = NO` in the iOS Info.plist to skip the export-
compliance prompt, and upload via `xcrun altool --upload-app --apiKey <KEYID> --apiIssuer <ISSUER>`.
Team ID is `8D42S4MS38`.

---

## What's in this branch / PR (all changed files)

Sync + diagnostics + tooling (Problem 1) and the widget background flatten (Problem 2):

- `Sources/HeadroomCore/Sync/IOSWidgetTimelineMapping.swift` — newest-snapshot-wins resolution
  + `resolve()` returning content origin (cache vs sync); `+ tests`.
- `Sources/HeadroomIOS/Views/IOSCompanionView.swift` — adopt remote into cache only when newer;
  build `IOSSyncDiagnostics`.
- `Sources/HeadroomIOS/Views/SettingsSheetView.swift` — DEBUG-only sync diagnostics section +
  `IOSSyncDiagnostics` model.
- `Sources/HeadroomIOS/Views/MirrorView.swift` — thread diagnostics through.
- `Sources/HeadroomIOSWidgets/HeadroomIOSTimelineProvider.swift` — adopt-when-newer cache write.
- `Sources/HeadroomApp/HeadroomApp.swift` — `--dump-phone-sync` diagnostic CLI (prints bundle id
  so a bare `swift run` reading isn't mistaken for the app's real state).
- `Sources/HeadroomIOSWidgets/Views/HeadroomWidgetContainerBackground.swift` — **flattened bg.**
- `Sources/HeadroomWidgets/Views/HeadroomWidgetContainerBackground.swift` — **flattened bg.**
- `Scripts/build-app.sh` — `HEADROOM_PROVISIONING_PROFILE` support + SIGKILL warning.
- `project.yml` / `Headroom.xcodeproj/project.pbxproj` — build bumps (iOS→8, macOS→7).
- `BUGS.md` — iCloud-KVS entitlement root-cause note.
- `Tests/HeadroomCoreTests/IOSWidgetTimelineMappingTests.swift` — resolution tests.

`swift build` + `swift test` (155 tests) pass; both iOS xcodebuilds succeed.
