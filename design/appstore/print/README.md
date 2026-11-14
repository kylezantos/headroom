# App Store screenshots · Print

The iPhone and iPad App Store set chosen on 2026-10-09: six frames per device in the voice of
the 1.5 release film. Each frame has a big TX-02 question or statement, and the product
answers it. The halftone vessel opens the set, and the widget styles you didn't pick are
printed as halftone ghosts.

- `compose.html`: every frame, for both devices. Open it to review. `?device=iphone|ipad&frame=N`
  shows one frame at the page origin for export.
- `../../../Scripts/export-appstore-print.sh`: renders all twelve frames to `dist/appstore/print/`,
  converts them to sRGB, strips alpha and verifies with `sips`.
- Maintainer listing order and copy: `headroom-site/docs/release/appstore-listing.md`
  in the private website repository.

## Local fonts

The exports use the maintainer's locally installed TX-02 Regular and Medium fonts. Install
your licensed copies in macOS before previewing or exporting this set. The compositor resolves
them by their installed names; no font files are distributed in this repository. The export
script stops with an installation message if either face is unavailable.

## What's in `assets/`

| Folder | What | Source |
|---|---|---|
| `captures/` | Simulator captures: Usage (multi-account), check-now receipt, widget styles wall, per device | "AppStore iPhone 17 Pro Max" and "AppStore iPad Pro 13" simulators, status bar 9:41 on 2026-01-13 |
| `renders/` | Lock Screen inline, circle and rectangle widgets (Liquid Level, Claude/Codex) | `swift run Headroom --render-widgets <dir> --widget-family lock --widget-transparent`, via headroom-videos `kit/product/renders/lock` |
| `brand/` | App icon, star field | headroom-videos `kit/brand` |
| `kit/` | `site-lib.js` (the site's halftone model), `headroom-kit.js` (draws the vessel), GSAP | headroom-videos `kit` |

## Refreshing captures

Build and install once with `Scripts/capture-appstore-shots.sh --frames I4,P1 --device all --keep-booted`
(it creates both simulators, sets the 9:41 status bar and installs the Debug build). Then, per
simulator, launch with `xcrun simctl launch <udid> com.kylezantos.headroom.ios <args>`:

| Capture | Launch arguments | Notes |
|---|---|---|
| `*-usage.png` | `--demo --demo-variant multiAccount --demo-screen usage` | dark appearance |
| `*-widget-styles.png` | `--demo --demo-variant fourProviders --demo-screen widgets --widget-wall styles` | pass `--widget-wall` and `styles` as two arguments (zsh won't split an unquoted expansion) |
| `*-check-now.png` | `--demo --demo-variant multiAccount --demo-screen usage`, then trigger check-now | Explore Demo replays a real receipt. iPhone: `axe swipe --start-x 220 --start-y 300 --end-x 220 --end-y 760 --duration 1.6`. iPad: `axe key-combo --modifiers 227 --key 21` (⌘R). Screenshot about 2 s later and keep a frame where a single receipt line ("✓ Claude Studio 3 of 5") has settled. |

`axe` must be 1.8.0 or newer for Xcode 27, which moved SimulatorKit to `SharedFrameworks`.
If a widget tile moves after a layout change, re-measure its box in `TILES` in `compose.html`.
