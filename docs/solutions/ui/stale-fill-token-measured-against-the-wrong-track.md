---
title: "A colour token tuned against one track is not portable to another: the widget stale fill failed on the popover"
date: 2026-11-14
category: ui
module: HeadroomCore/Models/BrandColorValues
problem_type: design_pattern
component: frontend
symptoms:
  - "Under Only when low, a stale healthy popover meter was the only green bar on its card, while every live healthy meter beside it was neutral grey"
  - "The obvious fix, reusing the widget's stale-healthy token, measured 1.1:1 against the popover's dark track (the bar vanishes) and 2.3:1 against the light track (louder than the live bar it is meant to sit under)"
root_cause: wrong_assumption
resolution_type: code_fix
severity: medium
related_components:
  - HeadroomMeterColorValues
  - HeadroomWidgetColorValues
  - MeterRecipe
  - MeterGauge
tags: [color, contrast, stale, meter, track, tokens, widgets, popover]
---

# A colour token tuned against one track is not portable to another

## Context

Craft round 2's R2C16 paints a stale meter in its severity hue at 35% chroma, so a stale
critical still reads as critical. Under "Only when low" (`colorAsEvent`) a live healthy meter has
no hue at all: it is the neutral grey (`HeadroomMeterColorValues.glassA` / `glassB`). Scaling the
chroma of nothing returns the healthy green, so a stale healthy row became the one green bar on
a card of grey ones. The craft audit (CA-P1) set out to fix that.

The widgets had already solved the same problem (WCM3): a stale healthy widget bar takes
`HeadroomWidgetColorValues.staleNeutralFill`, an opaque grey picked to sit between the widget
track and the widget's live neutral. Reusing it in the popover looked like a one-line change.

## What went wrong

Measured against the popover's own track (the track tint composited over the raised tile's
fill), the widget token did not do its job in either scheme (plan KTD5):

| Candidate | Dark vs track | Light vs track | Reads as |
|---|---|---|---|
| Widget `staleNeutralFill` | 1.1:1 | 2.3:1 | Gone in dark; louder than live in light |
| Live neutral at half alpha | 1.24:1 | 1.39:1 | Dimmer than live, still a shape, both schemes |

The widget token is an opaque colour chosen against the widget's track and live fill. The
popover's track, card fill and live neutral are different numbers, so the same grey lands below
the track's own lightness in dark and above the live fill's in light.

## Fix

Derive the stale value from the live value it must sit under, instead of picking a second
absolute colour. `HeadroomMeterColorValues.staleNeutralScale` is 0.5, and `staleGlassA`,
`staleGlassB` and `staleTickGlass` are the live neutrals at half their alpha, same ink. Because
the stale value is a ratio of the live one, a later retune of the live fill carries the stale
fill with it: CA-P10 raised the dark neutral stops from 0.22 / 0.11 to 0.36 / 0.24 in the same
round, and stale followed without a second edit.

The rule is narrow on purpose. `MeterRecipe.livePaintsHealthyNeutral(fill:)` is true only for
`colorAsEvent`; Low and Critical keep R2C16's hedge, and fills whose live healthy meter is
coloured are unchanged. The widgets keep `staleNeutralFill`, which is right for their track.

## How to check

`BrandColorValuesTests.staleHealthyNeutralIsDimmerThanLiveAndStillVisibleOnTheTrack` measures
each stop the way it renders, an alpha over the track over each raised-tile fill, in both
schemes, and asserts the stale ratio is above 1.2:1 and below the live ratio, with the ink
unchanged. `darkNeutralGaugeReadsAsClearlyAsLight` holds the live gauge's middle at 2:1 or more
in dark and at least as clear as light. Add the assertion before changing a value, so a retune
cannot slip under the track unnoticed.

## Takeaway

A contrast-tuned colour is a pair: the token and the surface it was measured on. Before reusing
a token on another surface, measure it against that surface's track and its live neighbour.
When a value has to sit between two others, express it relative to one of them so it moves with
it.
