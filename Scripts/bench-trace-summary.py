#!/usr/bin/env python3
"""Summarize a Time Profiler trace of `Headroom --bench-ui` by bench signpost interval.

For every signpost interval group (signpost name plus its label, with the run suffix "#N"
dropped and pane switches grouped by target), prints the main-thread time sampled inside it,
the share that falls in a few known cost buckets (layout, text, formatters, accessibility, ...),
and the app's own frames nearest the leaf: which Headroom function sits closest to the cost.
Recipe and background: docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md

Record (copy the binary under a unique name first so the trace attributes it unambiguously):
  cp .build/release/Headroom .build/release/HRBenchUI
  xcrun xctrace record --template 'Time Profiler' --instrument 'Points of Interest' \\
      --output bench.trace --launch -- .build/release/HRBenchUI --bench-ui all --runs 8

Summarize:
  Scripts/bench-trace-summary.py bench.trace          # exports into bench.trace.export/ first
  Scripts/bench-trace-summary.py bench.trace.export   # a directory holding the exports
  Scripts/bench-trace-summary.py --time-profile tp.xml --signposts sp.xml

Python 3 standard library only. A full-suite trace exports to ~170MB of XML; the parsed
main-thread samples are cached next to the time-profile export (time-profile.xml.pkl), so
later queries skip the parse. Delete the cache if the export changes.
"""
import argparse
import bisect
import collections
import os
import pickle
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SUBSYSTEM = "co.zantos.headroom.bench"
TIME_PROFILE_XPATH = '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'
SIGNPOSTS_XPATH = '/trace-toc/run[@number="1"]/data/table[@schema="OSSignpostIntervals"]'

# Frame-name patterns. A sample counts once per bucket if any frame in its stack matches, so
# buckets overlap and their shares don't sum to 100%.
BUCKETS = [
    ("layout (sizeThatFits/placement)", r"sizeThatFits|placeChildren|placeSubviews|LayoutComputer|LayoutEngine"),
    ("ViewThatFits", r"ViewThatFits"),
    ("text layout (CoreText, StyledText)", r"CoreText|^CT[A-Z]|TTypesetter|NSStringDrawing|StyledText|Text\.Layout|NSAttributedString"),
    ("DateFormatter / ICU", r"DateFormatter|udat_|icu::|CFDateFormatter"),
    ("accessibility", r"[Aa]ccessibility|^AX"),
    ("AppKit controls / CoreUI", r"NSButton|NSSwitch|NSPopUpButton|NSSegmented|NSStepper|NSTextField|NSControl|NSCell|CUICopyMeasurements|CoreUI"),
    ("glass / material", r"[Gg]lass|Material|VisualEffect|Backdrop"),
    ("geometry actions", r"GeometryAction|onGeometryChange|ScrollGeometry"),
    ("images / SVG", r"CoreSVG|NSImage|ImageIO|CGImageSource"),
    ("CA commit", r"CA::Transaction::commit|CA::Context::commit|CA::Layer::layout_and_display"),
]
# The harness's own frames, and the async and closure trampolines under every stack, say where
# the bench waited, not where the app spent the time.
HARNESS = re.compile(r"UIBenchHarness|BenchCounters|Entry\.\$?main|^main$|thunk for|assumeIsolated|deduplicated_symbol")


def export_trace(trace, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for name, args in [
        ("toc.xml", ["--toc"]),
        ("time-profile.xml", ["--xpath", TIME_PROFILE_XPATH]),
        ("signposts.xml", ["--xpath", SIGNPOSTS_XPATH]),
    ]:
        path = os.path.join(out_dir, name)
        # Reuse an export only if it is newer than the trace, so re-recording under the same name
        # re-exports; write to a temp file first so an interrupted export never looks complete.
        if os.path.exists(path) and os.path.getmtime(path) >= os.path.getmtime(trace):
            continue
        tmp = path + ".tmp"
        with open(tmp, "wb") as out:
            subprocess.run(["xcrun", "xctrace", "export", "--input", trace, *args], stdout=out, check=True)
        os.replace(tmp, path)


def target_binary(toc_path):
    if not toc_path or not os.path.exists(toc_path):
        return None
    for _, el in ET.iterparse(toc_path):
        if el.tag == "process" and el.get("name") and el.get("type") == "launched":
            return el.get("name")
    return None


def resolve(el, ids):
    """Exports write each value once with id="N"; later rows point back with ref="N"."""
    ref = el.get("ref")
    if ref is not None:
        return ids[ref]
    if el.get("id") is not None:
        ids[el.get("id")] = el
    return el


def load_intervals(path):
    intervals = []
    ids = {}
    for _, el in ET.iterparse(path):
        if el.tag != "row":
            continue
        values = {}
        for child in el:
            node = resolve(child, ids)
            values.setdefault(child.tag, node)  # the first os-log-metadata is the start message
        subsystem = values.get("subsystem")
        if subsystem is not None and (subsystem.text or "") != SUBSYSTEM:
            continue
        start = int(values["start-time"].text)
        name = values["signpost-name"].text or ""
        message = values.get("os-log-metadata")
        label = message.get("fmt", "") if message is not None else ""
        intervals.append((start, start + int(values["duration"].text), name, label))
    intervals.sort()
    return intervals


def compact(el, ids):
    """Like resolve, but keeps only the value: (name, binary) for a frame, else fmt or text."""
    ref = el.get("ref")
    if ref is not None:
        return ids[ref]
    if el.tag == "frame":
        binary = el.find("binary")
        value = (el.get("name", "?"), compact(binary, ids) if binary is not None else "?")
    elif el.tag == "binary":
        value = el.get("name", "?")
    elif el.tag == "thread":
        value = el.get("fmt", "")
    else:
        value = el.text
    if el.get("id") is not None:
        ids[el.get("id")] = value
    return value


def load_samples(path):
    """Main-thread samples as (time, weight ms, ((frame, binary), ...) leaf first)."""
    cache = path + ".pkl"
    if os.path.exists(cache) and os.path.getmtime(cache) >= os.path.getmtime(path):
        with open(cache, "rb") as f:
            return pickle.load(f)
    ids = {}
    samples = []
    process = None
    for _, el in ET.iterparse(path):
        if el.tag != "row":
            continue
        time = int(compact(el.find("sample-time"), ids))
        thread = compact(el.find("thread"), ids)
        weight_el = el.find("weight")
        weight = int(compact(weight_el, ids)) / 1e6 if weight_el is not None else 1.0
        bt = el.find("tagged-backtrace")
        if bt is None:
            bt = el.find("backtrace")
        stack = ()
        if bt is not None:
            if bt.get("ref") is not None:
                stack = ids[bt.get("ref")]
            else:
                stack = tuple(compact(fr, ids) for fr in bt.findall("frame"))
                ids[bt.get("id")] = stack
        if process is None:
            match = re.search(r"\(([^,()]+), pid:", thread)
            process = match.group(1) if match else None
        if thread.startswith("Main Thread"):
            samples.append((time, weight, stack))
        el.clear()
    result = (samples, process)
    with open(cache, "wb") as f:
        pickle.dump(result, f)
    return result


def group_label(name, label):
    """"multi5 general#3" -> "multi5 general"; "multi5 about->accounts instant=true" -> "multi5 ->accounts instant=true"."""
    label = re.sub(r"#[\d.]+$", "", label)
    switch = re.match(r"^(\S+ )?\w+->(\w+)(.*)$", label)
    if switch:
        label = (switch.group(1) or "") + "->" + switch.group(2) + switch.group(3)
    return f"{name}: {label}" if label else name


def summarize(samples, intervals, binary, top):
    starts = [iv[0] for iv in intervals]
    buckets = [(name, re.compile(pattern)) for name, pattern in BUCKETS]
    total = collections.Counter()
    seen = collections.defaultdict(set)
    bucket_ms = collections.defaultdict(collections.Counter)
    nearest = collections.defaultdict(collections.Counter)
    for time, ms, stack in samples:
        i = bisect.bisect_right(starts, time) - 1
        if i < 0 or not (intervals[i][0] <= time <= intervals[i][1]):
            continue
        group = group_label(intervals[i][2], intervals[i][3])
        total[group] += ms
        seen[group].add(intervals[i][0])
        for name, rx in buckets:
            if any(rx.search(frame) for frame, _ in stack):
                bucket_ms[group][name] += ms
        own = next((frame for frame, b in stack if b == binary and not HARNESS.search(frame)), None)
        nearest[group][own or "(no app frame)"] += ms
    for group in sorted(total, key=lambda g: (g.split(":")[0], -total[g])):
        t = total[group]
        n = len(seen[group])
        print(f"\n== {group}: {t:.0f} ms main-thread samples over {n} interval(s), {t / n:.1f} ms each")
        for name, _ in BUCKETS:
            v = bucket_ms[group][name]
            if v / t >= 0.005:
                print(f"   {100 * v / t:5.1f}%  {name}")
        print(f"   nearest {binary} frames:")
        for frame, v in nearest[group].most_common(top):
            print(f"   {100 * v / t:5.1f}%  {v / n:7.1f} ms each  {frame[:160]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("input", nargs="?", help="a .trace bundle or a directory of exports")
    parser.add_argument("--time-profile", help="time-profile table export")
    parser.add_argument("--signposts", help="OSSignpostIntervals table export")
    parser.add_argument("--binary", help="the app binary's name in the trace (default: the launched process)")
    parser.add_argument("--top", type=int, default=12, help="app frames listed per group (default 12)")
    args = parser.parse_args()

    toc = None
    if args.input:
        directory = args.input.rstrip("/")
        if directory.endswith(".trace"):
            export_dir = directory + ".export"
            export_trace(directory, export_dir)
            directory = export_dir
        tp = args.time_profile or os.path.join(directory, "time-profile.xml")
        sp = args.signposts or os.path.join(directory, "signposts.xml")
        toc = os.path.join(directory, "toc.xml")
    elif args.time_profile and args.signposts:
        tp, sp = args.time_profile, args.signposts
    else:
        parser.error("pass a .trace bundle or export directory, or --time-profile and --signposts")

    intervals = load_intervals(sp)
    if not intervals:
        sys.exit(f"no {SUBSYSTEM} signpost intervals in {sp}")
    samples, process = load_samples(tp)
    binary = args.binary or target_binary(toc) or process
    print(f"{len(samples)} main-thread samples, {len(intervals)} intervals, app binary {binary}")
    summarize(samples, intervals, binary, args.top)


if __name__ == "__main__":
    main()
