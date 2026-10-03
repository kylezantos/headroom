# Widget styles acceptance (U9) — 2026-10-03

Plan: `docs/plans/2026-10-02-1247-feat-widget-styles-plan.md`. Run on a signed build after the
upgrade spike (`docs/qa/2026-10-03-widget-config-upgrade-spike.md`) has passed. Headless renders
cover layout and overflow (`swift run Headroom --render-widgets <dir>`); this list covers what
only WidgetKit on a device can show.

## Edit Widget (R7)

- [ ] macOS: right-click a widget → Edit. **Style** lists Nested Meter, Vessel Hero, Tightest
      First, Liquid Level; **Color** lists Always colored, Only when low. Defaults are Nested
      Meter and Always colored.
- [ ] iPhone: long-press → Edit Widget shows the same two options.
- [ ] Switching Style re-renders that widget only; a second widget keeps its own style.
- [ ] Only when low turns healthy bars, vessels and the liquid neutral; low and critical stay
      amber and red.

## Each style, each size (R1, R2)

For small, medium and large on Mac and iPhone, with your real accounts:

- [ ] Nested Meter
- [ ] Vessel Hero — the vessel's top and bottom line up with the digits
- [ ] Tightest First — the headline is the lowest limit; large lists tightest to roomiest
- [ ] Liquid Level — each provider's column fills to its level

## Rendering modes (R12)

- [ ] iOS 26 Tinted and Clear Home Screen: every style legible; Liquid Level's wash is a faint
      tint with a bright top edge, never a solid white slab.
- [ ] macOS Tahoe desktop with a window in front (widgets go monochrome): every style legible.
- [ ] iPhone StandBy: every style legible.

## Text size (R10)

- [ ] iPhone 6.1″ at the largest text size the widgets allow (xxLarge): nothing overlaps or is
      cut off; extra rows and countdowns drop before names truncate.

## Settings (R16)

- [ ] Settings › Widgets & iPhone: the four thumbnails switch the preview; nothing changes on the
      placed widgets.

## Result

| Area | Pass / fail | Notes |
|---|---|---|
| Edit Widget | | |
| Styles | | |
| Rendering modes | | |
| Text size | | |
| Settings | | |
