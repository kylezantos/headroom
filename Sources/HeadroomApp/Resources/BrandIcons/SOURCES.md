# Brand Icon Sources

These source SVGs are bundled for provider identity in Headroom's UI.

- `claude-color.svg`: LobeHub static SVG icon package, `claude-color` icon. LobeHub lists the official site as `https://claude.ai`.
- `codex-color.svg`: LobeHub static SVG icon package, `codex-color` icon. LobeHub lists the official site as `https://openai.com/codex`.
- `grok-light.svg` / `grok-dark.svg`: LobeHub static SVG icon package, monochrome `grok` icon (`fill="currentColor"`), rendered here with an explicit near-black fill for light surfaces and near-white for dark. LobeHub lists the official site as `https://x.ai`.
- `cursor-light.svg` / `cursor-dark.svg`: LobeHub static SVG icon package, monochrome `cursor` icon (`fill="currentColor"`), rendered here with an explicit near-black fill for light surfaces and near-white for dark. LobeHub lists the official site as `https://cursor.com`.
- `copilot-light.svg` / `copilot-dark.svg`: GitHub Primer Octicons 19.15.1 (MIT license, `https://github.com/primer/octicons`), `copilot-24` icon, paths unchanged, rendered with the same explicit light and dark fills as Grok and Cursor and trimmed to a `0 1.985 24 20.03` viewBox. The official site is `https://github.com/features/copilot`.

OA2 (Sep 2026): every file's `viewBox` (and `width`/`height`) is trimmed so the path's tight
ink bounding box *is* the viewBox — no art was scaled or re-pathed, only the frame around it.
That makes "how big is this mark" a property of the artwork, which is what `HeadroomBrandMark`'s
one sizing rule (larger ink dimension = 13/15 of the slot, centred in it) stands on. Grok,
Cursor and Copilot trim to non-square boxes and are deliberately *not* padded back to square. `BrandMarkInkTests`
re-measures the shipped SVGs, so re-importing an untrimmed icon from LobeHub fails the suite.

The Grok, Cursor and Copilot marks are monochrome brands, so each ships as a light/dark pair (the macOS popover selects by `ColorScheme`; the `BrandIcons.xcassets` imagesets carry a `luminosity` dark appearance so iOS and the widgets adapt natively). This mirrors how Claude/Codex ship a single color mark that reads on both schemes.

OpenAI's brand guidelines say to use OpenAI marks only when directly related to OpenAI services, to follow their style guides and usage terms, and not to imply endorsement. Headroom uses each provider mark only to identify the user's own usage source for that provider, never to imply endorsement.
