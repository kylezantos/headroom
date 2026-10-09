#!/usr/bin/env python3
"""Verify the icon positions Finder saved in a DMG volume's .DS_Store.

Usage: dmg-layout-check.py <.DS_Store> <name>=<x>,<y> ... [--offscreen <name> ...]

Finder's saved layout has silently come out wrong (1.5 build 41 shipped with default
positions), so the release fails here instead of publishing a broken install window.
Stdlib-only reader for the Bud1 B-tree; only the 'Iloc' records are decoded.
"""
import struct
import sys

# Anything at or beyond this is outside the 680x440 install window, even if a user resizes it a bit.
OFFSCREEN_MIN = 1000


def read_iloc(path):
    with open(path, "rb") as fh:
        data = fh.read()[4:]  # 4-byte alignment prefix
    magic, root_off, root_size, _ = struct.unpack_from(">4sIII", data, 0)
    if magic != b"Bud1":
        raise ValueError("not a .DS_Store (missing Bud1 header)")

    def block(address):
        offset = address & ~0x1F
        size = 1 << (address & 0x1F)
        return data[offset:offset + size]

    root = data[root_off:root_off + root_size]
    count, = struct.unpack_from(">I", root, 0)
    pos = 8
    addresses = []
    for _ in range(count):
        addresses.append(struct.unpack_from(">I", root, pos)[0])
        pos += 4
    pos += ((count + 255) // 256 * 256 - count) * 4  # table is padded to 256 entries
    toc_count, = struct.unpack_from(">I", root, pos)
    pos += 4
    toc = {}
    for _ in range(toc_count):
        name_len = root[pos]
        name = root[pos + 1:pos + 1 + name_len].decode("ascii")
        pos += 1 + name_len
        toc[name] = struct.unpack_from(">I", root, pos)[0]
        pos += 4
    dsdb = block(addresses[toc["DSDB"]])
    top_node, = struct.unpack_from(">I", dsdb, 0)

    positions = {}

    def read_record(buf, pos):
        name_len, = struct.unpack_from(">I", buf, pos)
        pos += 4
        name = buf[pos:pos + name_len * 2].decode("utf-16-be")
        pos += name_len * 2
        code, kind = struct.unpack_from(">4s4s", buf, pos)
        pos += 8
        if kind == b"blob":
            length, = struct.unpack_from(">I", buf, pos)
            value = buf[pos + 4:pos + 4 + length]
            pos += 4 + length
            if code == b"Iloc":
                positions[name] = struct.unpack_from(">ii", value, 0)
        elif kind in (b"long", b"shor", b"type"):
            pos += 4
        elif kind == b"bool":
            pos += 1
        elif kind in (b"comp", b"dutc"):
            pos += 8
        elif kind == b"ustr":
            length, = struct.unpack_from(">I", buf, pos)
            pos += 4 + length * 2
        else:
            raise ValueError(f"unknown record type {kind!r}")
        return pos

    def walk(node_id):
        buf = block(addresses[node_id])
        next_node, count = struct.unpack_from(">II", buf, 0)
        pos = 8
        for _ in range(count):
            if next_node:
                child, = struct.unpack_from(">I", buf, pos)
                pos += 4
                walk(child)
            pos = read_record(buf, pos)
        if next_node:
            walk(next_node)

    walk(top_node)
    return positions


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 64
    positions = read_iloc(argv[1])
    failures = []
    offscreen = False
    for arg in argv[2:]:
        if arg == "--offscreen":
            offscreen = True
            continue
        if offscreen:
            got = positions.get(arg)
            if got is None or min(got) < OFFSCREEN_MIN:
                failures.append(f"{arg}: expected off-window (>= {OFFSCREEN_MIN}), saved {got}")
            continue
        name, coords = arg.split("=", 1)
        want = tuple(int(v) for v in coords.split(","))
        got = positions.get(name)
        if got != want:
            failures.append(f"{name}: expected {want}, saved {got}")
    for line in failures:
        print(f"  ✗ DMG layout: {line}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
