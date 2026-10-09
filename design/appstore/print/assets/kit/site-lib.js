var HRSite = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

  // entry.ts
  var entry_exports = {};
  __export(entry_exports, {
    format: () => format_exports,
    halftone: () => halftone_exports,
    severity: () => severity_exports,
    sky: () => sky_exports,
    slosh: () => slosh_exports
  });

  // lib/headroom-demo/halftone.ts
  var halftone_exports = {};
  __export(halftone_exports, {
    GHOST: () => GHOST,
    PRINT_MS: () => PRINT_MS,
    SLOSH: () => SLOSH,
    WIPE_MS: () => WIPE_MS,
    capsuleDots: () => capsuleDots,
    dotInk: () => dotInk,
    printInk: () => printInk,
    reprintAt: () => reprintAt,
    surfaceAt: () => surfaceAt
  });

  // lib/headroom-demo/slosh.ts
  var slosh_exports = {};
  __export(slosh_exports, {
    FRAME_COUNT: () => FRAME_COUNT,
    FRAME_MS: () => FRAME_MS,
    SloshClock: () => SloshClock,
    WAVE_AMPLITUDE: () => WAVE_AMPLITUDE,
    liquidPath: () => liquidPath,
    sloshPhase: () => sloshPhase,
    waveWrap: () => waveWrap
  });

  // lib/headroom-demo/usage-model.ts
  var MIN = 6e4;
  var HOUR = 60 * MIN;
  var DAY = 24 * HOUR;
  var STEP = 15 * MIN;
  function act(ms) {
    const d = new Date(ms);
    const day = d.getDay();
    const h = d.getHours() + d.getMinutes() / 60;
    if (day >= 1 && day <= 5) {
      if (h >= 9 && h < 12.5) return 1;
      if (h >= 12.5 && h < 13.5) return 0.15;
      if (h >= 13.5 && h < 15) return 1;
      if (h >= 15 && h < 17) return 1.45;
      if (h >= 17 && h < 18.25) return 0.8;
      if (day <= 4 && h >= 20.5 && h < 22.5) return 0.55;
      return 0;
    }
    if (h >= 10.5 && h < 12) return 0.4;
    if (h >= 15 && h < 16.5) return 0.35;
    return 0;
  }
  function perSlot(fn) {
    const cache = /* @__PURE__ */ new Map();
    return (ms) => {
      if (ms % STEP !== 0) return fn(ms);
      let v = cache.get(ms);
      if (v === void 0) {
        v = fn(ms);
        cache.set(ms, v);
      }
      return v;
    };
  }
  var RAW_W = {
    claude: (ms) => {
      const a = act(ms);
      if (!a) return 0;
      return a * (new Date(ms).getHours() >= 14 ? 1.25 : 0.85);
    },
    claudeWork: (ms) => {
      const a = act(ms);
      if (!a) return 0;
      const day = new Date(ms).getDay();
      return day >= 1 && day <= 5 ? a * 1.05 : 0;
    },
    codex: (ms) => {
      const a = act(ms);
      if (!a) return 0;
      return a * (new Date(ms).getHours() < 13 ? 1.25 : 0.55);
    },
    cursor: (ms) => act(ms) * 0.8,
    grok: (ms) => {
      const a = act(ms);
      if (!a) return 0;
      return a * (new Date(ms).getHours() >= 20 ? 1.4 : 0.35);
    }
  };
  var W = {
    claude: perSlot(RAW_W.claude),
    claudeWork: perSlot(RAW_W.claudeWork),
    codex: perSlot(RAW_W.codex),
    cursor: perSlot(RAW_W.cursor),
    grok: perSlot(RAW_W.grok)
  };
  function sum(fn, from, to, rate) {
    let u = 0;
    for (let s = Math.floor(from / STEP) * STEP; s < to; s += STEP) {
      const w = fn(s);
      if (w) u += w * rate * (Math.min(to, s + STEP) - Math.max(from, s)) / STEP;
    }
    return u;
  }
  function lastWeekly(ms, dow, hh, mm) {
    const d = new Date(ms);
    d.setHours(hh, mm, 0, 0);
    d.setDate(d.getDate() - (d.getDay() - dow + 7) % 7);
    if (d.getTime() > ms) d.setDate(d.getDate() - 7);
    return d.getTime();
  }
  function lastMonthly(ms, dom) {
    const d = new Date(ms);
    let r = new Date(d.getFullYear(), d.getMonth(), dom);
    if (r.getTime() > ms) r = new Date(d.getFullYear(), d.getMonth() - 1, dom);
    return r.getTime();
  }
  function nextMonthly(start) {
    const d = new Date(start);
    return new Date(d.getFullYear(), d.getMonth() + 1, d.getDate()).getTime();
  }
  function weekly(fn, rate, ms, dow, hh, mm) {
    const start = lastWeekly(ms, dow, hh, mm);
    return { left: Math.max(0, 100 - sum(fn, start, ms, rate)), reset: start + 7 * DAY };
  }
  function monthly(fn, rate, ms, dom) {
    const start = lastMonthly(ms, dom);
    return { left: Math.max(0, 100 - sum(fn, start, ms, rate)), reset: nextMonthly(start) };
  }
  function fiveHour(fn, rate, ms) {
    let start = null;
    let used = 0;
    for (let s = Math.floor((ms - 30 * HOUR) / STEP) * STEP; s < ms; s += STEP) {
      const w = fn(s);
      if (start !== null && s >= start + 5 * HOUR) {
        start = null;
        used = 0;
      }
      if (!w) continue;
      if (start === null) {
        start = s;
        used = 0;
      }
      used = Math.min(100, used + w * rate * (Math.min(ms, s + STEP) - s) / STEP);
    }
    if (start !== null && ms < start + 5 * HOUR) return { left: 100 - used, reset: start + 5 * HOUR };
    return { left: 100, reset: null };
  }
  var ACCOUNTS = [
    {
      key: "claude-personal",
      provider: "claude",
      name: "Personal",
      plan: "Max",
      main: true,
      receiptTitle: "Claude Personal",
      windows: [
        { label: "5-hour", compute: (ms) => fiveHour(W.claude, 5.2, ms) },
        { label: "Weekly", compute: (ms) => weekly(W.claude, 0.42, ms, 4, 10, 0) },
        { label: "Fable", compute: (ms) => weekly(W.claude, 0.17, ms, 4, 10, 0) }
      ]
    },
    {
      key: "claude-work",
      provider: "claude",
      name: "Work",
      plan: "Team",
      main: false,
      receiptTitle: "Claude Work",
      windows: [
        { label: "5-hour", compute: (ms) => fiveHour(W.claudeWork, 4.4, ms) },
        { label: "Weekly", compute: (ms) => weekly(W.claudeWork, 0.36, ms, 3, 4, 53) }
      ]
    },
    {
      key: "codex",
      provider: "codex",
      name: "Codex",
      plan: "Pro",
      banked: 3,
      main: true,
      receiptTitle: "Codex",
      windows: [
        { label: "5-hour", compute: (ms) => fiveHour(W.codex, 3.4, ms) },
        { label: "Weekly", compute: (ms) => weekly(W.codex, 0.36, ms, 1, 20, 14) }
      ]
    },
    {
      key: "grok",
      provider: "grok",
      name: "Grok",
      plan: "SuperGrok",
      main: true,
      receiptTitle: "Grok",
      windows: [{ label: "Monthly", compute: (ms) => monthly(W.grok, 0.14, ms, 9) }]
    },
    {
      key: "cursor",
      provider: "cursor",
      name: "Cursor",
      plan: "Pro",
      main: true,
      receiptTitle: "Cursor",
      windows: [
        { label: "Cursor models", compute: (ms) => monthly(W.cursor, 0.055, ms, 14) },
        { label: "Other models", compute: (ms) => monthly(W.cursor, 0.018, ms, 14) }
      ]
    }
  ];
  var ACCOUNT_BY_KEY = Object.fromEntries(ACCOUNTS.map((a) => [a.key, a]));
  var SPEND_ROWS = [
    { key: "anthropic", title: "Anthropic API", mark: "claude", weight: W.claude, rate: 0.29, opening: 24.6 },
    { key: "openai", title: "OpenAI API", mark: "codex", weight: W.codex, rate: 0.16, opening: 11.3 }
  ];

  // lib/headroom-demo/check-scheduler.ts
  var browserTimers = {
    setTimeout: (fn, ms) => globalThis.setTimeout(fn, ms),
    clearTimeout: (h) => globalThis.clearTimeout(h)
  };

  // lib/headroom-demo/slosh.ts
  var FRAME_COUNT = 10;
  var FRAME_MS = 100;
  var WAVE_AMPLITUDE = 0.7;
  var sloshPhase = (ms) => Math.floor(ms / FRAME_MS) % FRAME_COUNT;
  var waveWrap = (endMs) => Math.floor(endMs / 1e3) * 1e3 + 1e3;
  var SloshClock = class {
    /** `timers: null` lets tests step frames with `advance()` instead of a timer. */
    constructor(timers = browserTimers, now = () => Date.now()) {
      this.timers = timers;
      this.now = now;
      __publicField(this, "phase", 0);
      __publicField(this, "sloshing", /* @__PURE__ */ new Set());
      __publicField(this, "requested", /* @__PURE__ */ new Set());
      __publicField(this, "ticker", null);
      /** The wall-clock second the wave is in; crossing into the next one wraps it. */
      __publicField(this, "second", 0);
      __publicField(this, "listeners", /* @__PURE__ */ new Set());
      __publicField(this, "snapshot", { phase: 0, sloshing: this.sloshing });
      __publicField(this, "subscribe", (fn) => {
        this.listeners.add(fn);
        return () => this.listeners.delete(fn);
      });
      __publicField(this, "getSnapshot", () => this.snapshot);
    }
    /** The wave phase for a provider, or null when its pill is flat. */
    phaseOf(provider) {
      return this.sloshing.has(provider) ? this.phase : null;
    }
    update(updating, reduceMotion) {
      if (reduceMotion) {
        this.requested = /* @__PURE__ */ new Set();
        this.sloshing = /* @__PURE__ */ new Set();
        this.stop();
        this.emit();
        return;
      }
      this.requested = updating;
      const next = /* @__PURE__ */ new Set([...this.sloshing, ...updating]);
      if (!this.sloshing.size && next.size) {
        const t = this.now();
        this.phase = sloshPhase(t);
        this.second = Math.floor(t / 1e3);
      }
      if (next.size !== this.sloshing.size) this.sloshing = next;
      if (this.sloshing.size && this.timers && this.ticker === null) this.schedule();
      this.emit();
    }
    /** One frame. Pills no longer being checked drop out only as the wave wraps (a whole second). */
    advance() {
      const t = this.now();
      const second = Math.floor(t / 1e3);
      this.phase = sloshPhase(t);
      if (second > this.second) {
        this.second = second;
        const kept = new Set([...this.sloshing].filter((p) => this.requested.has(p)));
        if (kept.size !== this.sloshing.size) this.sloshing = kept;
      }
      if (!this.sloshing.size) this.stop();
      this.emit();
    }
    dispose() {
      this.stop();
      this.listeners.clear();
    }
    schedule() {
      if (!this.timers) return;
      this.ticker = this.timers.setTimeout(() => {
        this.ticker = null;
        this.advance();
        if (this.sloshing.size) this.schedule();
      }, FRAME_MS - this.now() % FRAME_MS + 1);
    }
    stop() {
      if (this.ticker !== null && this.timers) this.timers.clearTimeout(this.ticker);
      this.ticker = null;
      this.phase = 0;
    }
    /** Publishes only when the phase or the set of moving pills changed. */
    emit() {
      if (this.snapshot.phase === this.phase && this.snapshot.sloshing === this.sloshing) return;
      this.snapshot = { phase: this.phase, sloshing: this.sloshing };
      for (const fn of this.listeners) fn();
    }
  };
  function liquidPath(inner, fill, phase) {
    const level = inner.y + inner.h * (1 - fill);
    const bottom = inner.y + inner.h;
    const shift = phase / FRAME_COUNT;
    const steps = 24;
    let d = `M${inner.x},${bottom}`;
    for (let i = 0; i <= steps; i++) {
      const t = i / steps;
      const y = level - WAVE_AMPLITUDE * Math.sin(2 * Math.PI * (t - shift));
      d += `L${(inner.x + inner.w * t).toFixed(3)},${y.toFixed(3)}`;
    }
    return `${d}L${inner.x + inner.w},${bottom}Z`;
  }

  // lib/headroom-demo/halftone.ts
  var GHOST = 0.45;
  var WIPE_MS = 200;
  var PRINT_MS = 350;
  var SLOSH = 0.055;
  function capsuleDots(inner, cols, rows) {
    const pitch = inner.w / cols;
    const r = inner.w / 2;
    const dots = [];
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const cx = inner.x + (col + 0.5) * pitch;
        const cy = inner.y + (row + 0.5) * (inner.h / rows);
        const ly = Math.min(Math.max(cy, inner.y + r), inner.y + inner.h - r);
        if (Math.hypot(cx - (inner.x + r), cy - ly) > r) continue;
        dots.push({ cx, cy, x: (cx - inner.x) / inner.w, y: (cy - inner.y) / inner.h });
      }
    }
    return dots;
  }
  var surfaceAt = (x, level, wave) => 1 - level + (wave === null ? 0 : SLOSH * Math.sin(2 * Math.PI * (x - wave / FRAME_COUNT)));
  function dotInk(dot, pitch, rows, surface, ink) {
    const wet = Math.max(0, Math.min(1, (dot.y - surface) * rows + 0.5));
    const c = 0.08 + 0.92 * wet * ink;
    return { r: pitch * 0.42 * (0.32 + 0.68 * c), opacity: 0.14 + 0.86 * c };
  }
  var printInk = (y, p) => y >= 1 - p ? 1 : GHOST;
  function reprintAt(now, start, checkMs) {
    const land = start + checkMs;
    const end = Math.max(land + PRINT_MS, waveWrap(land));
    return {
      p: Math.max(0, Math.min(1, (now - land) / PRINT_MS)),
      wave: now >= start && now < waveWrap(land) ? sloshPhase(now) : null,
      done: now >= end
    };
  }

  // lib/headroom-demo/severity.ts
  var severity_exports = {};
  __export(severity_exports, {
    FILL: () => FILL,
    TXT: () => TXT,
    meterCells: () => meterCells,
    numeralColor: () => numeralColor,
    pillColors: () => pillColors,
    scaleHex: () => scaleHex,
    sevFill: () => sevFill,
    sevOf: () => sevOf
  });
  var sevOf = (p) => p <= 15 ? "c" : p <= 50 ? "l" : "h";
  var FILL = {
    light: { h: "#29A84C", l: "#DA7300", c: "#E63833" },
    dark: { h: "#33C759", l: "#FF9E0A", c: "#FF7263" }
  };
  var TXT = {
    light: { l: "#B26900", c: "#D92921", num: "#D1241C" },
    dark: { l: "#FF9E0A", c: "#FF5749", num: "#FF6659" }
  };
  function scaleHex(hx, k) {
    return "#" + [1, 3, 5].map(
      (i) => Math.round(parseInt(hx.slice(i, i + 2), 16) * k).toString(16).padStart(2, "0")
    ).join("");
  }
  function sevFill(sv, theme) {
    const c = FILL[theme][sv];
    return theme === "dark" ? scaleHex(c, sv === "c" ? 0.95 : 0.85) : c;
  }
  function meterCells(p, theme) {
    const col = sevFill(sevOf(p), theme);
    const lit = Math.max(1, Math.round(p / 100 * 5));
    const off = theme === "dark" ? "rgba(255,255,255,.09)" : "rgba(0,0,0,.08)";
    return Array.from(
      { length: 5 },
      (_, i) => i >= lit ? { background: off, opacity: 1 } : { background: col, opacity: i < lit - 1 ? 0.7 : 1 }
    );
  }
  function pillColors(p, theme) {
    const sv = sevOf(p);
    return {
      fill: FILL[theme][sv],
      stroke: sv === "c" ? FILL[theme].c : null,
      text: sv === "h" ? null : TXT[theme][sv]
    };
  }
  var numeralColor = (p, theme) => sevOf(p) === "c" ? TXT[theme].num : null;

  // lib/headroom-demo/format.ts
  var format_exports = {};
  __export(format_exports, {
    fmtAmount: () => fmtAmount,
    fmtClock: () => fmtClock,
    fmtClockSpoken: () => fmtClockSpoken,
    fmtCountdown: () => fmtCountdown,
    fmtShift: () => fmtShift,
    fmtStamp: () => fmtStamp,
    monthAbbr: () => monthAbbr
  });
  function fmtCountdown(reset, now) {
    if (reset == null) return "5h";
    const s = (reset - now) / 1e3;
    if (s <= 60) return "now";
    const d = Math.floor(s / 86400);
    const h = Math.floor(s % 86400 / 3600);
    const m = Math.floor(s % 3600 / 60);
    if (d) return h ? `${d}d ${h}h` : `${d}d`;
    if (h) return m ? `${h}h ${m}m` : `${h}h`;
    return m ? `${m}m` : "<1m";
  }
  function fmtClock(ms) {
    return `${WEEKDAY.format(ms)}\xA0\xA0${TIME.format(ms)}`;
  }
  function fmtShift(ms) {
    const total = Math.round(Math.abs(ms) / MIN);
    const h = Math.floor(total / 60);
    const m = total % 60;
    const body = h ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
    return total === 0 ? body : `${ms > 0 ? "+" : "\u2212"}${body}`;
  }
  function fmtClockSpoken(ms) {
    return SPOKEN.format(ms);
  }
  var WEEKDAY = new Intl.DateTimeFormat("en-US", { weekday: "short" });
  var TIME = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" });
  var SPOKEN = new Intl.DateTimeFormat("en-US", { weekday: "long", hour: "numeric", minute: "2-digit" });
  function fmtStamp(ageMs) {
    const minutes = Math.floor(Math.max(0, ageMs) / MIN);
    if (minutes < 1) return "Just now";
    if (minutes < 60) return minutes === 1 ? "1 min ago" : `${minutes} min ago`;
    const hours = Math.floor(minutes / 60);
    return hours === 1 ? "1 hr ago" : `${hours} hr ago`;
  }
  function fmtAmount(amount) {
    return `$${amount.toFixed(2)}`;
  }
  var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  function monthAbbr(month) {
    return MONTHS[month];
  }

  // lib/headroom-demo/sky.ts
  var sky_exports = {};
  __export(sky_exports, {
    BASE: () => BASE,
    INK: () => INK,
    INK_FLOOR: () => INK_FLOOR,
    SKY: () => SKY,
    contrast: () => contrast,
    copyInk: () => copyInk,
    hourOf: () => hourOf,
    isDark: () => isDark,
    lightness: () => lightness,
    luminance: () => luminance,
    mix: () => mix,
    moonPhase: () => moonPhase,
    orbAt: () => orbAt,
    pathAt: () => pathAt,
    rgb: () => rgb,
    skyAt: () => skyAt,
    skyGradient: () => skyGradient,
    skyStops: () => skyStops,
    starOpacity: () => starOpacity,
    themeAt: () => themeAt
  });
  function isDark(ms) {
    const h = new Date(ms).getHours();
    return h < 7 || h >= 19;
  }
  var themeAt = (ms) => isDark(ms) ? "dark" : "light";
  var SKY = [
    [0, "#010208", "#081130"],
    [4.6, "#02040c", "#0c1638"],
    [5.9, "#241f3e", "#63485c"],
    [7, "#d99a74", "#7186b8"],
    [9, "#a9cdee", "#eef3f8"],
    [13, "#8fc0ec", "#e7f0f8"],
    [17, "#f2bd78", "#8fa2cf"],
    [18.8, "#b86656", "#383b68"],
    [20, "#0c1130", "#16205a"],
    [21.6, "#02040c", "#0a1436"],
    [24, "#010208", "#081130"]
  ];
  var hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  var mix = (a, b, k) => a.map((v, i) => Math.round(v + (b[i] - v) * k));
  var rgb = (c) => `rgb(${c.join(",")})`;
  function skyAt(h) {
    let i = 0;
    while (h > SKY[i + 1][0]) i++;
    const [h0, a0, b0] = SKY[i];
    const [h1, a1, b1] = SKY[i + 1];
    const k = (h - h0) / (h1 - h0);
    return [mix(hex(a0), hex(a1), k), mix(hex(b0), hex(b1), k)];
  }
  var BASE = { dark: [5, 6, 11], light: [238, 238, 236] };
  var hourOf = (ms) => {
    const d = new Date(ms);
    return d.getHours() + d.getMinutes() / 60;
  };
  var smoothstep = (x) => {
    const t = Math.min(1, Math.max(0, x));
    return t * t * (3 - 2 * t);
  };
  function lightness(ms) {
    const h = hourOf(ms);
    return smoothstep((h - 6) / 2) * (1 - smoothstep((h - 18) / 2));
  }
  function skyStops(ms) {
    const w = lightness(ms);
    return skyAt(hourOf(ms)).map((c) => mix(mix(c, BASE.dark, 0.2), mix(c, BASE.light, 0.6), w));
  }
  function skyGradient(ms) {
    const [top, bot] = skyStops(ms);
    return `linear-gradient(180deg,${rgb(top)},${rgb(bot)})`;
  }
  var INK = {
    dark: { fg: [245, 245, 247], fg2: [161, 161, 166], fg3: [138, 138, 144] },
    light: { fg: [29, 29, 31], fg2: [110, 110, 115], fg3: [116, 116, 122] }
  };
  var INK_FLOOR = { fg: 4.5, fg2: 5, fg3: 4.5 };
  var channel = (v) => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  var luminance = ([r, g, b]) => 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
  function contrast(a, b) {
    const la = luminance(a);
    const lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }
  function copyInk(ms, band, stops = skyStops(ms)) {
    const [top, bot] = stops;
    const samples = [band[0], (band[0] + band[1]) / 2, band[1]].map((y) => mix(top, bot, Math.min(1, Math.max(0, y))));
    const worstOn = (ink2, shade2, s) => Math.min(...samples.map((b) => contrast(ink2, mix(b, shade2, s))));
    const white = [255, 255, 255];
    const black = [0, 0, 0];
    const theme = worstOn(white, BASE.dark, 0) >= worstOn(black, BASE.light, 0) ? "dark" : "light";
    const toward = theme === "dark" ? white : black;
    const shade = BASE[theme];
    const worst = (ink2, s) => worstOn(ink2, shade, s);
    let scrim = 0;
    while (scrim < 0.6 && worst(toward, scrim) < INK_FLOOR.fg2) scrim = Math.round((scrim + 0.02) * 100) / 100;
    const tone = (base, floor) => {
      if (worst(base, scrim) >= floor) return rgb(base);
      let lo = 0;
      let hi = 1;
      for (let i = 0; i < 12; i++) {
        const m = (lo + hi) / 2;
        if (worst(mix(base, toward, m), scrim) >= floor) hi = m;
        else lo = m;
      }
      return rgb(mix(base, toward, hi));
    };
    const ink = INK[theme];
    return {
      fg: tone(ink.fg, INK_FLOOR.fg),
      fg2: tone(ink.fg2, INK_FLOOR.fg2),
      fg3: tone(ink.fg3, INK_FLOOR.fg3),
      scrim,
      scrimRgb: shade.join(" ")
    };
  }
  var moonPhase = (ms) => ((ms - Date.UTC(2e3, 0, 6, 18, 14)) / 864e5 / 29.530588853 % 1 + 1) % 1;
  function orbAt(ms) {
    const h = hourOf(ms);
    const day = h >= 6 && h < 20;
    return { kind: day ? "sun" : "moon", u: day ? (h - 6) / 14 : (h + 24 - 20) % 24 / 10 };
  }
  var pathAt = (w, h, u, peak) => [
    w * (0.06 + 0.88 * u),
    h + 24 - (h + 24 - peak) * Math.sin(Math.PI * u)
  ];
  function starOpacity(ms) {
    if (!isDark(ms)) return 0;
    const h = hourOf(ms);
    return h >= 21 || h < 4.5 ? 1 : h >= 19.5 ? (h - 19.5) / 1.5 : h < 6 ? (6 - h) / 1.5 : 0;
  }
  return __toCommonJS(entry_exports);
})();
