// headroom-kit.js — reusable, seek-safe Headroom pieces for HyperFrames films.
//
// Extracted from films/2026-10-headroom-1.5-release/assets/film.js. Everything here is a pure
// function of film time t (no clocks, no randomness), so any frame renders on its own.
// Load after gsap.min.js and kit/product/site-demo/site-lib.js (window.HRSite: the site's own
// vessel, slosh, halftone and severity math, bundled from headroom.zantos.co's source).
//
// The kit is the TRUTH layer (how Headroom's UI and loading language actually look and behave).
// A film's LOOK (palette, type scale, framing, transitions) belongs in that film's frame.md and
// its own film.js. Restyle the look freely; never restyle the product.
(() => {
  const S = window.HRSite;
  if (!S) throw new Error("headroom-kit: load site-lib.js (window.HRSite) first");
  const P = "demo-hero-module__fDc4qW__"; // the site's CSS-module prefix for the stage DOM
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const c = (n) => "." + P + n;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, k) => a + (b - a) * k;
  const easeOut = (x) => 1 - Math.pow(1 - clamp(x), 3);
  const easeInOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);

  // ---------- loading-language timing (HeadroomCore LoadingMotion via the site) ----------
  const GHOST = S.halftone.GHOST; // ink of a ghost dot
  const WIPE = S.halftone.WIPE_MS / 1000; // ghost wipe, top → down
  const PRINT = S.halftone.PRINT_MS / 1000; // fresh print, bottom → up
  const phaseAt = (t) => Math.floor(t * 10 + 1e-6) % 10; // slosh: 10 frames at 100 ms
  const waveWrap = (t) => Math.floor(t) + 1; // a wave finishes on the next whole second
  /** Ink function for a fresh reading printing in from `land` (bottom → up). */
  const printInk = (t, land) => { const k = (t - land) / PRINT; return k >= 1 ? () => 1 : (y) => (y >= 1 - k ? 1 : GHOST); };
  /** Ink function for an old reading ghosting out from `start` (top → down). */
  const wipeInk = (t, start) => { const k = (t - start) / WIPE; return k >= 1 ? () => GHOST : (y) => (y < k ? GHOST : 1); };

  // ---------- the vessel glyph (vessel.tsx: 11×18, stroke 1.6, liquid inset 2.2) ----------
  const VW = 11, VH = 18, STROKE = 1.6, INSET = 2.2;
  const INNER = { x: INSET, y: INSET, w: VW - 2 * INSET, h: VH - 2 * INSET };
  /** Menu-bar vessel SVG markup (inner content for an `<svg viewBox="0 0 11 18">`). */
  function vesselSVG(id, fill, color, stroke, phase) {
    const liquid = phase !== null && phase !== undefined && fill > 0
      ? `<path clip-path="url(#${id})" fill="${color}" d="${S.slosh.liquidPath(INNER, fill, phase)}"/>`
      : `<rect clip-path="url(#${id})" fill="${color}" x="0" y="${INNER.y + INNER.h * (1 - fill)}" width="${VW}" height="${VH}"/>`;
    return `<defs><clipPath id="${id}"><rect x="${INNER.x}" y="${INNER.y}" width="${INNER.w}" height="${INNER.h}" rx="${INNER.w / 2}"/></clipPath></defs>` +
      `<rect x="${STROKE / 2}" y="${STROKE / 2}" width="${VW - STROKE}" height="${VH - STROKE}" rx="${(VW - STROKE) / 2}" fill="none" stroke="${stroke ?? "currentColor"}" stroke-width="${STROKE}"/>` + liquid;
  }
  /** A pill's colours for a percentage left, dark theme (severity.ts). */
  const pillColors = (v) => S.severity.pillColors(v, "dark");

  // ---------- the big halftone vessel (same capsule + halftone model, on a canvas) ----------
  function rrect(ctx, x, y, w, h, r) {
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }
  /**
   * Draw the vessel at any size. state = { pose: {cx, cy, u}, level 0–1, phase|null, ink(y)→0–1,
   * color, alpha, outline? (default "#f5f5f7"), cols? (6), rows? (12) }. `u` = px per glyph unit
   * (u = 28 → 308×504 px). Clears the canvas and hides it when nothing is drawn.
   */
  function drawVessel(ctx, st, size = { w: ctx.canvas.width, h: ctx.canvas.height }) {
    ctx.clearRect(0, 0, size.w, size.h);
    const on = !!st && st.alpha > 0;
    ctx.canvas.style.display = on ? "" : "none";
    if (!on) return;
    const cols = st.cols ?? 6, rows = st.rows ?? 12;
    const dots = S.halftone.capsuleDots(INNER, cols, rows);
    const pitch = INNER.w / cols;
    const { cx, cy, u } = st.pose;
    const ox = cx - (VW * u) / 2, oy = cy - (VH * u) / 2;
    ctx.save();
    ctx.globalAlpha = clamp(st.alpha);
    rrect(ctx, ox + (STROKE / 2) * u, oy + (STROKE / 2) * u, (VW - STROKE) * u, (VH - STROKE) * u, ((VW - STROKE) / 2) * u);
    ctx.lineWidth = STROKE * u; ctx.strokeStyle = st.outline ?? "#f5f5f7"; ctx.stroke();
    ctx.save();
    rrect(ctx, ox + INNER.x * u, oy + INNER.y * u, INNER.w * u, INNER.h * u, (INNER.w / 2) * u);
    ctx.clip();
    ctx.fillStyle = st.color;
    for (const d of dots) {
      const { r, opacity } = S.halftone.dotInk(d, pitch, rows, S.halftone.surfaceAt(d.x, st.level, st.phase ?? null), st.ink(d.y));
      ctx.globalAlpha = clamp(st.alpha) * opacity;
      ctx.beginPath(); ctx.arc(ox + d.cx * u, oy + d.cy * u, r * u, 0, Math.PI * 2); ctx.fill();
    }
    ctx.restore(); ctx.restore();
  }

  // ---------- Reprint row (reprint-row.tsx: 44×16, three 10×16 pills, 4×8 dots) ----------
  const ROW_W = 44, ROW_H = 16, PILL_W = 10, PILL_GAP = 7, RI = 2;
  const R_INNER = { x: RI, y: RI, w: PILL_W - 2 * RI, h: ROW_H - 2 * RI };
  const R_DOTS = S.halftone.capsuleDots(R_INNER, 4, 8);
  /**
   * SVG markup for the Refresh button's Reprint row (viewBox 0 0 44 16, currentColor ink).
   * levels = { claude: 38, codex: 64, grok: 56 } (three pills, in order). run = null for a
   * settled row, or { start, land: {p: t}, probeEnd: {p: t} } to ghost, slosh and print.
   */
  function reprintSVG(t, levels, run, clipId = "hrk-reprint") {
    const provs = Object.keys(levels).slice(0, 3);
    const x0 = (ROW_W - (3 * PILL_W + 2 * PILL_GAP)) / 2;
    let out = `<defs><clipPath id="${clipId}"><rect x="${RI}" y="${RI}" width="${R_INNER.w}" height="${R_INNER.h}" rx="${R_INNER.w / 2}"/></clipPath></defs>`;
    provs.forEach((p, i) => {
      let ink = () => 1, phase = null;
      if (run) {
        ink = t >= run.land[p] ? printInk(t, run.land[p]) : wipeInk(t, run.start);
        phase = t >= run.start && t < waveWrap(run.probeEnd[p]) ? phaseAt(t) : null;
      }
      out += `<g transform="translate(${x0 + i * (PILL_W + PILL_GAP)} 0)"><rect x="0.6" y="0.6" width="${PILL_W - 1.2}" height="${ROW_H - 1.2}" rx="${(PILL_W - 1.2) / 2}" fill="none" stroke="currentColor" stroke-width="1.2"/><g clip-path="url(#${clipId})">`;
      for (const d of R_DOTS) {
        const { r, opacity } = S.halftone.dotInk(d, R_INNER.w / 4, 8, S.halftone.surfaceAt(d.x, levels[p] / 100, phase), ink(d.y));
        out += `<circle cx="${d.cx}" cy="${d.cy}" r="${r.toFixed(3)}" fill="currentColor" opacity="${opacity.toFixed(3)}"/>`;
      }
      out += "</g></g>";
    });
    return out;
  }

  // ---------- print-in: any element resolves from halftone dots (CSS mask) ----------
  /** Create a print-in registry. add(el|selector, t0, dur?, pitch?); apply(t) each frame. */
  function printIns() {
    const list = [];
    return {
      add(sel, t0, dur = 0.42, pitch = 9) { const el = typeof sel === "string" ? $(sel) : sel; if (el) list.push({ el, t0, dur, pitch, state: null }); },
      apply(t) {
        for (const p of list) {
          const k = clamp((t - p.t0) / p.dur);
          if (k <= 0) { p.el.style.opacity = "0"; p.state = -1; continue; }
          if (k >= 1) { if (p.state !== 1) { p.el.style.webkitMaskImage = p.el.style.maskImage = "none"; p.el.style.transform = ""; p.el.style.opacity = ""; p.state = 1; } continue; }
          p.el.style.opacity = "";
          const e = easeOut(k), R = p.pitch * 0.75 * e;
          const m = `radial-gradient(circle at 50% 50%, #000 ${R.toFixed(2)}px, transparent ${(R + 0.7).toFixed(2)}px)`;
          p.el.style.webkitMaskImage = p.el.style.maskImage = m;
          p.el.style.webkitMaskSize = p.el.style.maskSize = `${p.pitch}px ${p.pitch}px`;
          p.el.style.transform = `translateY(${(10 * (1 - e)).toFixed(2)}px)`;
          p.state = 0;
        }
      },
    };
  }

  // ---------- halftone wipe: ghost dots sweep down, the next scene prints up ----------
  /**
   * Draw a wipe on a full-frame canvas. starts = [t, …] cover starts (the cut sits `cover` s
   * later). opts: { cover 0.35, reveal 0.4, pitch 27, band 260, skyTop [3,4,11], skyBottom
   * [9,17,45], ghost "rgba(235,235,245,0.3)" }. The dark fill follows a vertical sky gradient so
   * full coverage matches a sky background; pass your film's background colours.
   */
  function drawWipe(ctx, t, starts, opts = {}) {
    const W = ctx.canvas.width, H = ctx.canvas.height;
    const cover = opts.cover ?? 0.35, reveal = opts.reveal ?? 0.4, WP = opts.pitch ?? 27, band = opts.band ?? 260;
    const top = opts.skyTop ?? [3, 4, 11], bot = opts.skyBottom ?? [9, 17, 45], ghostInk = opts.ghost ?? "rgba(235,235,245,0.3)";
    ctx.clearRect(0, 0, W, H);
    const w = starts.find((s) => t >= s && t < s + cover + reveal);
    ctx.canvas.style.display = w === undefined ? "none" : "";
    if (w === undefined) return;
    const kc = clamp((t - w) / cover), kr = clamp((t - w - cover) / reveal);
    for (let row = 0; row * WP < H + WP; row++) {
      const y = row * WP + WP / 2;
      const p = t < w + cover ? clamp((Math.pow(kc, 1.6) * (H + band) - y) / band) : clamp(((1 - easeOut(kr)) * (H + band) - (H - y)) / band);
      if (p <= 0) continue;
      const k = y / H;
      const col = `rgb(${top.map((v, i) => Math.round(v + (bot[i] - v) * k)).join(",")})`;
      const dark = WP * 0.75 * clamp((p - 0.25) / 0.75), ghost = WP * 0.3 * Math.sin(Math.PI * p);
      for (let ci = 0; ci * WP < W + WP; ci++) {
        const x = ci * WP + WP / 2;
        if (dark > 0) { ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x, y, dark, 0, Math.PI * 2); ctx.fill(); }
        if (ghost > 0.5 && p < 1) { ctx.fillStyle = ghostInk; ctx.beginPath(); ctx.arc(x, y, ghost, 0, Math.PI * 2); ctx.fill(); }
      }
    }
  }

  // ---------- the site's popover / menu bar DOM (kit/product/site-demo/stage-fragment.html) ----------
  /** Fill the single popover's 10 window rows: rows = [[countdown, percent], …] in DOM order. */
  function fillPopoverRows(pop, rows) {
    $$(c("wrow"), pop).forEach((row, i) => {
      if (!rows[i]) return;
      const [cd, v] = rows[i];
      const wc = $(c("wc"), row);
      wc.innerHTML = `<span aria-hidden="true">${cd}</span>`;
      wc.className = P + "wc" + (S.severity.sevOf(v) === "c" ? " " + P + "wcCrit" : "");
      S.severity.meterCells(v, "dark").forEach((cell, k) => { const ci = $$(c("seg5") + " i", row)[k]; ci.style.background = cell.background; ci.style.opacity = cell.opacity; });
      const n = $(c("num"), row);
      n.style.color = S.severity.numeralColor(v, "dark") ?? "";
      $("span", n).textContent = v + "%";
    });
  }
  /** Set a menu-bar pill: el = the `.pm[data-provider]` node; phase null = flat. */
  function setPill(pm, id, v, phase = null) {
    const col = pillColors(v);
    $("svg", pm).innerHTML = vesselSVG(`hrk-v-${id}`, v / 100, col.fill, col.stroke, phase);
    const txt = $(c("pct") + " > span:last-child", pm);
    txt.textContent = v + "%";
    txt.style.color = col.text ?? "";
  }
  /**
   * Clone the popover into a multi-account popover. accounts = { claude: [[name, plan,
   * [[label, countdown, pct], …]], …], codex: […] } (the first two cards). maxHeight caps the
   * card list (the app caps at 640 pt). Returns the clone, inserted after the original.
   */
  function buildMultiPopover(pop, accounts, maxHeight = 640) {
    const multi = pop.cloneNode(true);
    multi.removeAttribute("id");
    const cards = $(c("cards"), multi);
    const cardEls = $$(c("card"), cards);
    const template = $(c("acct"), cardEls[0]);
    Object.keys(accounts).forEach((provider, idx) => {
      const card = cardEls[idx];
      const mark = $(c("mslot"), card);
      card.innerHTML = "";
      for (const [name, plan, rows] of accounts[provider]) {
        const acct = template.cloneNode(true);
        $(c("ttl"), acct).textContent = name;
        const planEl = $(c("plan"), acct); planEl.className = P + "plan"; planEl.textContent = plan;
        if (mark) $(c("mslot"), acct).replaceWith(mark.cloneNode(true));
        const wrows = $(c("wrows"), acct), rowTpl = $(c("wrow"), wrows);
        wrows.innerHTML = "";
        for (const [label, cd, v] of rows) {
          const r = rowTpl.cloneNode(true);
          $(c("wl"), r).textContent = label;
          wrows.appendChild(r);
          const wc = $(c("wc"), r); wc.innerHTML = `<span aria-hidden="true">${cd}</span>`;
          wc.className = P + "wc" + (S.severity.sevOf(v) === "c" ? " " + P + "wcCrit" : "");
          S.severity.meterCells(v, "dark").forEach((cell, k) => { const ci = $$(c("seg5") + " i", r)[k]; ci.style.background = cell.background; ci.style.opacity = cell.opacity; });
          const n = $(c("num"), r); n.style.color = S.severity.numeralColor(v, "dark") ?? ""; $("span", n).textContent = v + "%";
        }
        card.appendChild(acct);
      }
    });
    const inner = document.createElement("div");
    inner.className = "hrk-multi-scroll";
    inner.style.cssText = `display:flex;flex-direction:column;gap:${getComputedStyle($(c("cards"), pop)).rowGap}`;
    while (cards.firstChild) inner.appendChild(cards.firstChild);
    const spend = cards.nextElementSibling;
    if (spend && spend.classList.contains(P + "card")) inner.appendChild(spend); // API spend scrolls with accounts
    cards.appendChild(inner);
    cards.style.overflow = "hidden";
    cards.style.maxHeight = maxHeight + "px";
    pop.after(multi);
    return multi;
  }
  /** Footer receipt line markup (RefreshReceiptPresentation): { checked, text, count? } or a stamp string. */
  function receiptHTML(line) {
    if (typeof line === "string") return `<span class="${P}stamp"><span aria-hidden="true">${line}</span></span>`;
    return (line.checked ? `<svg class="${P}rcptCheck" width="9" height="9" viewBox="0 0 10 10" aria-hidden="true"><path d="M1.6 5.3 4 7.7 8.6 2.4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>` : "") +
      `<span class="${P}rcptName">${line.text}</span>` + (line.count ? `<span class="${P}rcptCount">${line.count}</span>` : "");
  }

  // ---------- macOS notification banner (macOS 26), real NotificationContent strings ----------
  /** Builds a banner element; style it with the `.nb` rules in kit/engine/headroom-kit.css. */
  function banner(title, body, icon = "assets/kit/brand/images/app-icon-squircle.png") {
    const b = document.createElement("div");
    b.className = "nb";
    b.innerHTML = `<img src="${icon}" alt=""><div class="bx"><div class="bt">${title}</div><div class="bb">${body}</div></div><span class="now">now</span>`;
    return b;
  }

  // ---------- camera helper ----------
  /** Transform for a world wrapper (transform-origin 0 0) that puts world point (tx, ty) at screen (sx, sy) at scale k. */
  const cam = (k, tx, ty, sx, sy) => ({ x: sx - k * tx, y: sy - k * ty, scale: k });

  window.HRKit = {
    P, c, clamp, lerp, easeOut, easeInOut,
    loading: { GHOST, WIPE, PRINT, phaseAt, waveWrap, printInk, wipeInk },
    vessel: { VW, VH, INNER, svg: vesselSVG, draw: drawVessel, pillColors },
    reprintSVG, printIns, drawWipe,
    site: { fillPopoverRows, setPill, buildMultiPopover, receiptHTML },
    banner, cam,
  };
})();
