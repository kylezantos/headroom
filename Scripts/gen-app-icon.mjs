#!/usr/bin/env node
// Headroom macOS app-icon generator — the single source of truth for the app icon.
//
// WHY this exists (and replaces the old `design/vessel-icon.html` full-bleed export):
// a PNG `AppIcon.appiconset` on macOS is drawn AS-IS — macOS does NOT apply a rounded-rect
// mask the way iOS does. The earlier master assumed "the system rounds it," which shipped a
// hard-cornered square that reads as a non-native tile in the Dock. So we bake the shape in:
// the artwork is clipped to a true squircle (superellipse) inset inside a transparent margin,
// exactly matching the macOS icon grid (icon body ≈ 824 of 1024, ~100px transparent padding).
//
// Renders the master SVG at every size required by AppIcon.appiconset via `npx sharp-cli`
// (rasterizes the SVG natively at each target size for crisp small icons).

import { writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repo = join(__dirname, "..");
const iconset = join(repo, "Sources/HeadroomApp/Resources/Assets.xcassets/AppIcon.appiconset");
const designDir = join(repo, "design");

const S = 1024; // master canvas

// --- macOS icon grid: rounded body inset from the canvas, transparent outside -------------
const bodyInset = 100;               // transparent margin (matches Apple's ~80.5% body ratio)
const half = (S - bodyInset * 2) / 2; // 412 → body is 824×824 centered
const C = S / 2;                      // 512
const n = 5;                          // superellipse exponent ≈ Apple's continuous corner

// Sample the superellipse |x/a|^n + |y/a|^n = 1 into a smooth closed path (the squircle).
function squirclePath(cx, cy, a, exponent, steps = 160) {
  const pts = [];
  for (let i = 0; i < steps; i++) {
    const t = (i / steps) * 2 * Math.PI;
    const ct = Math.cos(t), st = Math.sin(t);
    const x = cx + a * Math.sign(ct) * Math.pow(Math.abs(ct), 2 / exponent);
    const y = cy + a * Math.sign(st) * Math.pow(Math.abs(st), 2 / exponent);
    pts.push([x, y]);
  }
  return "M" + pts.map(([x, y]) => `${x.toFixed(2)} ${y.toFixed(2)}`).join(" L") + " Z";
}
const squircle = squirclePath(C, C, half, n);

// --- vessel geometry (mirrors design/vessel-icon.html, scaled to sit in the 824 body) -----
const cap = { x: 352, y: 214, w: 320, h: 596, rx: 160, sw: 22 };
const inset = 30;
const inX = cap.x + inset, inW = cap.w - inset * 2, r = inW / 2;
const inTop = cap.y + inset, inBot = cap.y + cap.h - inset;
const fill = 0.46;
const liquidTop = inBot - (inBot - inTop) * fill;
const arcStartY = inBot - r;
const liquid = `M${inX} ${liquidTop} H${inX + inW} V${arcStartY} A${r} ${r} 0 0 1 ${inX} ${arcStartY} Z`;

const svg = `<svg width="${S}" height="${S}" viewBox="0 0 ${S} ${S}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="tile"><path d="${squircle}"/></clipPath>
    <linearGradient id="bg" x1="0.1" y1="0" x2="0.92" y2="1">
      <stop offset="0" stop-color="#33404f"/>
      <stop offset="0.5" stop-color="#1a2330"/>
      <stop offset="1" stop-color="#0b111a"/>
    </linearGradient>
    <linearGradient id="liquid" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#93ffc6"/>
      <stop offset="0.5" stop-color="#4bdd97"/>
      <stop offset="1" stop-color="#1fac70"/>
    </linearGradient>
    <linearGradient id="topHi" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="0.42" stop-color="#ffffff" stop-opacity="0.02"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="wall" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.98"/>
      <stop offset="0.5" stop-color="#dfe8e6" stop-opacity="0.86"/>
      <stop offset="1" stop-color="#b7c4c2" stop-opacity="0.82"/>
    </linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.28"/>
      <stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="vig" cx="0.5" cy="0.95" r="0.85">
      <stop offset="0.5" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.30"/>
    </radialGradient>
    <filter id="glow" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="18" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>

  <!-- Everything is clipped to the squircle; corners of the canvas stay transparent. -->
  <g clip-path="url(#tile)">
    <rect x="0" y="0" width="${S}" height="${S}" fill="url(#bg)"/>
    <rect x="0" y="0" width="${S}" height="${S}" fill="url(#topHi)"/>

    <g filter="url(#glow)"><path d="${liquid}" fill="url(#liquid)"/></g>
    <rect x="${inX}" y="${liquidTop - 7}" width="${inW}" height="13" rx="6.5" fill="#eafff4" opacity="0.42"/>
    <rect x="${cap.x + 50}" y="${cap.y + 60}" width="26" height="178" rx="13" fill="#ffffff" opacity="0.13"/>
    <rect x="${cap.x}" y="${cap.y}" width="${cap.w}" height="${cap.h}" rx="${cap.rx}"
          fill="none" stroke="url(#wall)" stroke-width="${cap.sw}"/>
    <rect x="0" y="0" width="${S}" height="${S}" fill="url(#vig)"/>
  </g>

  <!-- Subtle top rim highlight on the tile edge (the Tahoe glass-tile sheen). -->
  <path d="${squircle}" fill="none" stroke="url(#rim)" stroke-width="2"/>
</svg>`;

const masterPath = join(designDir, "vessel-app-icon.svg");
writeFileSync(masterPath, svg);
console.log("wrote", masterPath);

const sizes = [
  16, 20, 29, 32, 40, 58, 60, 64, 76, 80, 87, 120,
  128, 152, 167, 180, 256, 512, 1024
];
for (const px of sizes) {
  const out = join(iconset, `icon_${px}.png`);
  execFileSync("npx", ["--yes", "sharp-cli", "--input", masterPath, "--output", out, "resize", String(px), String(px)],
    { stdio: ["ignore", "ignore", "inherit"] });
  console.log("rendered", `icon_${px}.png`);
}

// Refreshed 1024 preview alongside the master for the design/ folder.
execFileSync("npx", ["--yes", "sharp-cli", "--input", masterPath, "--output", join(designDir, "vessel-app-icon-1024.png"),
  "resize", "1024", "1024"], { stdio: ["ignore", "ignore", "inherit"] });
console.log("done");
