# Widget configuration upgrade spike (U10) — 2026-10-03

Plan: `docs/plans/2026-10-02-1247-feat-widget-styles-plan.md` (U10, KTD1).

**Question:** when a user updates Headroom, do widgets they already placed keep rendering after
the widget changes from a fixed widget to an editable one (Edit Widget → Style, Color)? Apple
documents no supported path, and developers report placed iPhone widgets freezing on a
placeholder until a reboot.

**What changed in the spike:** only the widget configuration. The layout is today's. A pass
means: placed widgets show their normal content (or their normal status card) with **no
reboot**, and Edit Widget shows **Style** and **Color**. Changing Style does nothing visible
yet — that is expected in the spike.

Nothing here publishes a build. Both artifacts are local, Apple Development–signed.

## macOS

Before: `/Applications/Headroom.app` is the public release 1.4.1 (33).
Spike build: `Headroom.app` at the root of this worktree (built from commit `13912d7a`).

1. Make sure at least one Headroom widget is on the desktop (small, medium and large if you
   can). Note what each shows.
2. Quit Headroom (menu bar icon → Quit).
3. Replace `/Applications/Headroom.app` with the spike build from this worktree.
4. Unregister the worktree copy so WidgetKit uses only the installed one:
   `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <worktree>/Headroom.app`
5. Open `/Applications/Headroom.app` once.
6. Without rebooting, check each placed widget: does it render normally within a minute or two?
7. Right-click a widget → **Edit "Headroom"**. Are **Style** and **Color** there, with Nested
   Meter and Always colored selected?
8. Afterwards, reinstall the public release from headroom.zantos.co if you want your normal app
   back (the spike build has no iCloud entitlement).

## iPhone

Spike build: `.xcode-derived-ios-device/Build/Products/Release-iphoneos/HeadroomIOS.app`
(built from commit `13912d7a`).

1. With the version of Headroom already on the phone, place a Headroom widget on the Home Screen
   (any size) and note what it shows.
2. Unlock the phone and keep it connected, then install the spike over it:
   `xcrun devicectl device install app --device 00008140-00094CD00A0B001C .xcode-derived-ios-device/Build/Products/Release-iphoneos/HeadroomIOS.app`
3. Without rebooting, check the placed widget: does it render normally, or does it stick on a
   placeholder or go blank?
4. Long-press the widget → **Edit Widget**. Are **Style** and **Color** there?
5. If it froze, reboot the phone and note whether it recovers.

## Result

| Platform | Placed widgets render without reboot? | Edit Widget shows Style and Color? | Notes |
|---|---|---|---|
| macOS | | | |
| iPhone | | | |

A failure on either platform stops the style work at U5 until Kyle chooses between the
release-notes fallback (remove and re-add the widget) and blocking the release.
