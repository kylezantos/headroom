---
title: Multi-account phone sync over iCloud key-value storage, beside a frozen v3 key
date: 2026-10-05
category: architecture-patterns
module: HeadroomCore/Sync
problem_type: architecture_pattern
component: service_object
severity: high
applies_when:
  - Adding a field, provider or account-level datum the phone must show
  - Changing what the Mac writes to iCloud key-value storage, or when
  - Touching the v3 key `headroom.syncedWidgetSnapshot` that build-33 phones read
  - Serving anything from the phone's App Group caches
  - Choosing how to tell whether a cache belongs to the current iCloud account
tags: [sync, icloud, kvs, ios, widgets, multi-account, digest, lineage, budget, account-scope]
---

# Multi-account phone sync over iCloud key-value storage, beside a frozen v3 key

## Context

Until Oct 2026 the Mac published one primary-only JSON envelope (schema 3) under
`headroom.syncedWidgetSnapshot`, and the phone showed each provider's main account. The iPhone
parity round (`docs/plans/2026-10-04-0923-feat-ios-parity-round-plan.md`) needed every account,
up to the tested envelope of 20 per provider, plus the Mac's display choices, typed attention and
a check-now round trip. Optional fields on the old key were rejected: build-33 TestFlight phones
read it, and a clean contract was wanted for the new data. The design keeps v3 exactly as it
was and adds a second format, v4, under its own keys. Every field and fallback is in
`docs/plans/2026-10-04-ios-parity-sync-field-contract.md`.

## Guidance

### One key per provider, a manifest that ties them together

iCloud key-value storage (KVS) caps the whole store at 1 MB and key names at 64 bytes, but
DTS's practical ceiling for reliable sync is "tens of KB", and no quota event fires below 1 MB. One giant key
also rewrites every account whenever one changes. So v4 splits by provider:

- `headroom.sync.v4.manifest`: lineage, generation, status, provider order, and for each
  provider `{payloadGeneration, digest, effectiveIntervalSeconds}`, plus the display block,
  widget selection, reminder summary, recent check-now answers and the ladder level.
- `headroom.sync.v4.provider.<id>`: that provider's accounts, self-describing (source ID,
  generation, body). All account-level data lives only here, so a provider is always internally
  consistent; the phone never joins accounts from two keys.
- `headroom.sync.v4.receipt` (one, store-wide) and `headroom.sync.v4.request.<deviceUUID>` (one
  per phone install, replaced on every pull, never one per pull).

Every key name stays under 64 UTF-8 bytes; the 36-character request UUID gives 61. Encoding is
compact on purpose: one-letter coding keys, sorted keys, integer epoch seconds, percentages
normalized to one decimal, no derivable fields (window ID, severity, labels), and the main account
never repeated inside the extras.

### Digest the bytes you stored, never a re-encoding

The manifest's per-provider digest is SHA-256 over the exact `Data` in that key
(`CompanionSyncCodec.digest`), computed by the Mac at write and by the phone over the raw bytes it
read. Decoding and re-encoding first would drop fields a newer Mac added, change the bytes and
fail every check on an older phone. Not Swift `Hasher` either: it is seeded per process.

The digest only applies at equal generation. A provider key behind the manifest is still shown,
structurally checked (never described as digest-verified), and its rows read "Last known" after
max(2 minutes, one heartbeat). A key ahead of the manifest is used, and verified when the
manifest catches up. A same-generation key whose bytes differ from an already-checked copy is
rejected: generations are immutable.

### Lineage and generation order the data

The Mac makes a random UUID once per install (`CompanionLineage`, never a host, serial or user
name) and a generation counter persisted before use, so a relaunch can never reissue one. Within
one lineage, data orders by generation; across lineages, by `generatedAt`. A manifest from a new
lineage makes the phone drop other lineages' cached payloads. The generation is stamped on the
main actor when state is captured, and one serial publisher actor writes in generation order and
drops superseded work, so a slow encode can never land an older state after a newer one.

### Keep v3 frozen, mark it as a mirror

The Mac writes v3 and v4 in one publish with one `generatedAt`. v3 gains two optional wrapper
fields, `companionSourceID` and `companionGeneration`, which build 33 ignores. The UUID never goes
into v3's existing `sourceID`, which build 33 displays as "<sourceID> on Mac". A golden test runs
the Mac's v3 output through a frozen copy of the build-33 decoder (`Build33DecoderGoldenTests`).

The resolver (`CompanionSnapshotResolver`) then applies these rules:

1. A disabled manifest tombstone (`{"i": <source>, "s": "disabled"}`) wins over everything.
2. A v3 that names the current manifest's lineage is a mirror. It never wins while the manifest is
   readable, unless it runs ahead by more than the dim threshold (the v4 channel looks stuck).
3. A v3 with no lineage that is newer than the manifest comes from an older or downgraded Mac. It
   wins, and the phone says "Update Headroom on your Mac to see every account".
4. Ties go to v4. An unreadable or future v4 never hides a readable v3, and vice versa, so v3 can
   later be retired by writing a higher inner schema without stranding 1.5 phones.

### Enforce the budget before every write

`CompanionPayloadBudget` measures the complete planned namespace (manifest, providers, receipt
and every request key) before each write: at most 15,000 bytes per provider key and 64,000 for
the set. The drop ladder is: level 0 full; level 1 drops extra accounts' model rows; level 2 caps
extra accounts, and only above 20 per provider ("N more on your Mac"). The level is recomputed
from current content on every publish and travels in the manifest. If nothing fits, the
publisher stops and keeps the last good content; it never caps accounts at or below the envelope.

Measured with the multi-20 fixture (20 Claude, 20 Codex with Spark rows, 20 Grok, 1 Cursor), a
manifest, a receipt and five request keys (`CompanionPayloadBudgetTests`):

| Key | Level 0 bytes | Level 1 bytes |
|---|---|---|
| manifest | 1,463 | 1,463 |
| provider.claude | 9,226 | 5,669 |
| provider.codex | 9,865 | 5,769 |
| provider.grok | 4,635 | 4,635 |
| provider.cursor | 498 | 498 |
| receipt | 1,251 | 1,251 |
| 5 × request | 570 | 570 |
| **Total** | **27,508** | **19,855** |

So the envelope fits at level 0 with room to spare, and the largest provider key uses about two
thirds of its limit. The Mac cannot bound request keys written by unlimited phone installs
(each fresh install leaves one key until the 30-day prune); it measures what exists and fails
honestly rather than deleting recent requests.

### Scope the phone's caches to the iCloud account, and know what failed

The phone caches resolved payloads in the App Group so widgets and offline launches have
something to show. A cache written under one Apple ID must never be served under another, even
with the app closed when the account changes. The plan named `FileManager.ubiquityIdentityToken`
as the scope signal. It failed:

- On a signed physical iPhone the app and its widget extension read **different** token values
  for the same account, 129 seconds apart, with identical iCloud entitlements. Apple only ever
  describes the token as "for your app", compared against that app's own earlier archive; nothing
  promises equality across executables. A per-process baseline does not close the gap: a widget
  running for the first time after an account switch would adopt the new token and serve the old
  account's cache.
- Apple's QA1935 and the header say the token is `nil` when iCloud Drive is off. KVS works with
  Drive off, and the plan requires that case.

The candidate replacement is a **KVS-resident scope marker**: a random UUID under
`headroom.scope.v1`, stored in the same key-value store every cached payload came from. Apple
documents that an Apple-account change replaces the whole store, so a different account shows a
different marker or none. Every loader reads the live local marker and compares it with the copy
saved in the cache sidecar, inside the same coordinated App Group transaction as the cache read;
a mismatch invalidates every cache, and no marker means serve nothing. Only the iPhone app writes
it, only when absent, never from memory. It lives outside `headroom.sync.v4.` so no sweep or scan
removes it. It carries no identity, but it does sync, which deviates from KTD22's "never syncs",
so it needs Kyle's sign-off and its own device check
(`docs/qa/2026-10-04-companion-identity-candidate-gate.md`). Until both pass,
`CompanionLoaderAdoption.isEnabled` stays `false` and phones load build 33's way.

## Why This Matters

- Hashing a re-encoding, or writing the Mac UUID into v3's `sourceID`, would each break deployed
  phones silently, with every unit test still green unless the golden and raw-byte tests exist.
- A size limit that is only checked in tests drifts; measuring the real namespace before each
  write turns "tens of KB" into a number the Mac enforces.
- An account-scope signal that looks right in one process can be wrong across two. Test the
  cross-process case on a signed device before trusting any identity API for cache isolation.

## When to Apply

- Adding a phone-visible field: put account data in the provider key, ordering and cadence in
  the manifest, bump `minimumReaderVersion` only for a breaking change, and re-run the budget test.
- Adding a phone-visible Mac setting: call `exportPhoneSyncSnapshot()` from its `UsageStore`
  setter and add a `PhoneExportTriggerTests` case.
- Any phone surface that reads synced data: go through `CompanionPhoneSnapshotSource`, never
  `iCloudSnapshotSync` or a cache directly.

## Examples

- Wire keys and limits: `Sources/HeadroomCore/Sync/CompanionSyncModels.swift`
  (`CompanionSyncKeys`, `CompanionSyncBudget`).
- Resolver rules: `Sources/HeadroomCore/Sync/CompanionSnapshotResolver.swift`.
- Publisher, coalescing and sync-off sweep: `Sources/HeadroomCore/Engine/CompanionPublisher.swift`.
- Ladder: `Sources/HeadroomCore/Sync/CompanionPayloadBudget.swift`.
- Scope marker: `Sources/HeadroomCore/Sync/CompanionKVSScopeMarker.swift`.
