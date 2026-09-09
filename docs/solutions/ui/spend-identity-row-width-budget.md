# The spend identity row has no slack — every capsule change is a width change

**Symptom (2026-09-08, PA7):** unifying the identity capsules to 10.5 medium + 0.2 kerning made
"Anthropic API" render as "Anthropic A…" in every scenario with an amount, while the row *looked*
like it had ~36pt of room before the total.

**Why:** the apparent room is the reserved amount column (`amountColumnWidth` = "$0,000.00" at
18 semibold monospaced, 91pt) right-aligning a shorter total. The line is 299pt: mark 15 + amount
91 + capsule box + four 6pt spacings + spacer floor, and the title gets the remainder. Measured
with `NSString.size(withAttributes:)`: title 96.5pt, "September" capsule 51.8 → 58.5pt after PA7,
so the title's share fell from 101.2 to 94.5. Layout priorities cannot help — nothing in the row
is flexible except the title.

**Fix:** the spacer's `minLength: 6` double-counted the HStack's own 6pt spacing on each side of
it. Dropping the floor to 0 keeps a 12pt gap and returns 6pt to the title. Capsule kerning stays
on each capsule `Text` (a `View.kerning` on the capsule modifier measured identically; it was not
the mechanism, just the first thing bisected).

**How to check:** `swift /tmp/measure.swift`-style width sums beat screenshots here — the reserved
column hides the tightness. `--demo multi-4 --meter-style micro.chip.event` in light shows the
longest title beside the longest default period. "Last 30 days" still clips (BUGS.md).
