# Brand Icon Sources

These source SVGs are bundled for provider identity in Headroom's UI.

- `claude-color.svg`: LobeHub static SVG icon package, `claude-color` icon. LobeHub lists the official site as `https://claude.ai`.
- `codex-color.svg`: LobeHub static SVG icon package, `codex-color` icon. LobeHub lists the official site as `https://openai.com/codex`.
- `grok-light.svg` / `grok-dark.svg`: LobeHub static SVG icon package, monochrome `grok` icon (`fill="currentColor"`), rendered here with an explicit near-black fill for light surfaces and near-white for dark. LobeHub lists the official site as `https://x.ai`.
- `cursor-light.svg` / `cursor-dark.svg`: LobeHub static SVG icon package, monochrome `cursor` icon (`fill="currentColor"`), rendered here with an explicit near-black fill for light surfaces and near-white for dark. LobeHub lists the official site as `https://cursor.com`.
- `copilot-light.svg` / `copilot-dark.svg`: GitHub Primer Octicons 19.15.1 (MIT license, `https://github.com/primer/octicons`), `copilot-24` icon, paths unchanged, rendered with the same explicit light and dark fills as Grok and Cursor and trimmed to a `0 1.985 24 20.03` viewBox. The official site is `https://github.com/features/copilot`.
- `opencode-light.svg` / `opencode-dark.svg`: OpenCode's official brand files, `https://opencode.ai/brand/files/opencode-logo-transparent-light.svg` and `…-transparent-dark.svg` (linked from `https://opencode.ai/brand`; the same files are `services/site/public/brand/files/` in `https://github.com/anomalyco/opencode` at commit `85a043926abf98ca967a24b7c12c0aa6b7d81cd3`), retrieved 2026-11-12. Paths unchanged and already trimmed (the 240 × 300 artboard is all ink), rendered with the same explicit light and dark fills as Grok, Cursor and Copilot in place of OpenCode's `#1F1F1F` / `#EEEEEE`, and given a 19.2 × 24 intrinsic size. The inner block keeps OpenCode's own translucency (0.2 light, 0.28 dark), written as `opacity` rather than `fill-opacity` because AppKit's SVG renderer ignores `fill-opacity` and drew the block solid; for one unstroked path the two are the same.
- `antigravity-light.svg` / `antigravity-dark.svg`: LobeHub static SVG icon package `@lobehub/icons-static-svg` 1.102.0 (MIT license, `https://github.com/lobehub/lobe-icons`), monochrome `antigravity` icon (`https://unpkg.com/@lobehub/icons-static-svg@1.102.0/icons/antigravity.svg`, `fill="currentColor"`), retrieved 2026-11-16. Path unchanged, rendered with the same explicit light and dark fills as Grok, Cursor, Copilot and OpenCode, and trimmed to a `0 1 24 22.1087` viewBox. LobeHub also ships an `antigravity-color` icon, but its color comes from Gaussian-blurred shapes under a mask: AppKit's SVG renderer drops the blur and rasterizes the mask at the 24-unit artboard, which draws hard-edged color blobs with stepped edges, so the monochrome icon is the one that renders faithfully here.

OA2 (Sep 2026): every file's `viewBox` (and `width`/`height`) is trimmed so the path's tight
ink bounding box *is* the viewBox — no art was scaled or re-pathed, only the frame around it.
That makes "how big is this mark" a property of the artwork, which is what `HeadroomBrandMark`'s
one sizing rule (larger ink dimension = 13/15 of the slot, centred in it) stands on. Grok,
Cursor, Copilot, OpenCode and Antigravity trim to non-square boxes and are deliberately *not* padded back to square. `BrandMarkInkTests`
re-measures the shipped SVGs, so re-importing an untrimmed icon from LobeHub fails the suite.

The Grok, Cursor, Copilot and OpenCode marks are monochrome brands, and Antigravity ships its monochrome icon (above), so each ships as a light/dark pair (the macOS popover selects by `ColorScheme`; the `BrandIcons.xcassets` imagesets carry a `luminosity` dark appearance so iOS and the widgets adapt natively). This mirrors how Claude/Codex ship a single color mark that reads on both schemes.

OpenAI's brand guidelines say to use OpenAI marks only when directly related to OpenAI services, to follow their style guides and usage terms, and not to imply endorsement. Headroom uses each provider mark only to identify the user's own usage source for that provider, never to imply endorsement.
