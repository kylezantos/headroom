# iOS parity v4 sync field contract

Plan: [iOS parity round](2026-10-04-0923-feat-ios-parity-round-plan.md), U4 and KTD5–15/KTD19/KTD22.

Reviewed against existing models/projectors by the U4 preflight agent and the implementation coordinator. This records implementation decisions; tests and physical acceptance are still pending. All streams consume this table. Cache-loader adoption requires the signed app/widget identity gate; this document supplies no device-pass evidence.

## Contract conventions

- JSON object coding keys below are exact wire names. Logical properties use descriptive Swift names. Encode sorted object keys; preserve explicitly ordered arrays. Dates are signed integer Unix seconds (floor, shared by both phone exports), generations nonnegative `Int64`, counts nonnegative `Int`, UUIDs canonical lowercase strings, finite percentages normalized to one decimal using nearest-or-away-from-zero after clamping to 0–100. Reject wrong primitive types and nonfinite numbers; do not coerce strings to numbers.
- Unknown fields are ignored. Missing required structural fields make that object unusable, never generate a fabricated account ID, generation or date. Structural corruption may fall back to a checked same-scope cache/v3 under resolver rules; unknown presentation enums use the explicit fallback below. Preserve raw provider bytes for SHA-256; never hash a re-encoding.
- Known provider IDs are `claude`, `codex`, `grok`, `cursor`, `copilot` (Copilot added 2026-11-02; a phone build that predates it skips the key as unknown). Unknown provider IDs may remain in the manifest's ordering metadata but are skipped by this reader. Account IDs are Headroom local IDs (`primary` or registry-generated IDs), never upstream IDs. Account title is the name the Mac shows (KTD9, amended 2026-11-10): the label or default name, or the captured email when the Mac's "Use email as account name" setting is on and that account has one, then made unique with " · N".
- A main account carries its complete window set; extra accounts use the same compact window shape and may lose model rows only through KTD7's ladder. “Full windows” means the full set, not `WidgetWindowSummary`'s verbose JSON layout. No repeated main account inside extras, no encoded window ID/severity/label/resetLabel/resetTimeZoneIdentifier. `kindName` is the semantic name associated with `.other` or `.billingPeriod`, from which the label and ID derive.
- Preserve exact canonical utilization in a separate optional field: rounded remaining is insufficient to reconstruct it. Source `UsageWindow` precision and reset provenance remain intact. U5 canonicalizes non-visible `resetLabel` and `resetTimeZoneIdentifier` to nil in both v3 and v4-derived projections, with full-envelope parity tests. Main/extra derived labels must still equal `WindowKind.shortLabel`; verify that with all demo variants.
- No account scope/token, host/device name, config path, credential, source raw error, raw CLI output or API response can enter these types. An email enters only as an account title, and only when it is the Mac's displayed name (the user typed it as a label or turned on "Use email as account name"); it is never its own field and never part of an ID. Privacy copy says so: “If you use an email address as an account name, that address syncs as the name.” (Amended 2026-11-10; the earlier rule kept every captured email off the phone.)

## Key table

| Exact key | Value/type | Missing/unknown behavior | Consumer KTD |
|---|---|---|---|
| `headroom.syncedWidgetSnapshot` | Existing `SyncedWidgetSnapshotEnvelope` JSON; inner schema 3 | Preserve existing header-first decoder; unreadable v3 never overrides readable v4 | 5, 6.5–7, 13 |
| `headroom.sync.v4.manifest` | `Manifest` JSON bytes | Checked current-scope cache or readable v3; otherwise waiting; disabled tombstone always wins | 5, 6, 12, 22 |
| `headroom.sync.v4.provider.<providerID>` | `ProviderPayload` JSON bytes | Same-source checked last complete copy, then matching v3 main, then skeleton; no joining partial accounts | 6.2–4, 7, 13 |
| `headroom.sync.v4.request.<deviceUUID>` | `Request` JSON bytes | No request; unknown UUID suffix rejected | 5, 14 |
| `headroom.sync.v4.receipt` | `Receipt` JSON bytes | No acknowledgement; never complete by clock comparison | 5, 14 |

Each emitted key must pass a UTF-8 length assertion ≤64 bytes. The canonical 36-character request UUID yields 61 bytes (25-byte prefix + 36). Future provider IDs must pass the same limit. Request key suffix is per-install random device UUID shared through the App Group. Each provider value ≤15 KB; whole v4 set ≤64 KB at the 20-per-provider envelope with Spark rows. The complete observed v4 namespace includes request and receipt values. Limits are exactly 15,000 bytes per provider and 64,000 bytes for the observed set; overflow stops the write after the permitted ladder. See the budget decision and its cross-device limitation below.

## Manifest

| Logical field / coding key | Type | Unknown or missing fallback | Consumer KTD |
|---|---|---|---|
| schemaVersion / `v` | Int, initial 4 | Active missing/invalid: corrupt. Higher version accepted if met minimumReaderVersion | 5, 6.6 |
| minimumReaderVersion / `r` | Int, initial 1 | Active missing/invalid: corrupt; greater than reader: readable v3 + phone-update line | 6.6 |
| sourceID / `i` | random Mac UUID String | Required even for tombstone; malformed: unusable, no foreign cache | 6.4, 12, 22 |
| generation / `g` | Int64 | Required active; no default or reset within same lineage; unavailable in disabled tombstone | 6.3–5, 8, 14 |
| generatedAt / `t` | epoch seconds Int64 | Required active; no `Date.now` substitute; absent tombstone has no freshness timestamp | 5, 6.4–5, 15 |
| macAppVersion / `a` | String | Absent/unknown version displays no fabricated version; compatibility is reader minimum, not version parsing | 6.6, 11 |
| status / `s` | String enum `enabled`, `disabled` | Required; unknown: unsupported state, no active account content (may show update state) | 6.5, 22 |
| providerOrder / `o` | [providerID String] | Active required; dedupe in first-occurrence order, unknown IDs skip; explicit [] means no subscriptions | 6.1, 13 |
| providers / `p` | [providerID: ManifestProviderEntry] | Active required; references without entry yield skeleton, keys not referenced ignored | 6.2–4, 12 |
| spendOrder / `j` | [providerID String] | [] if absent; provider can occur here with no subscription card | 6.1, 13 |
| chosenIntervalSeconds / `c` | positive finite integer seconds | Required active; invalid cadence does not invent a healthy interval; use conservative freshness/update state | 6.1, 8, 15 |
| display / `d` | Display? | nil means defaults, Spark off, and old-Mac appearance note where appropriate | 6.7, 11 |
| widgetProviderSelection / `w` | [providerID String]? | Preserve nil versus []; both visibly choose first two; dedupe/filter known available IDs without changing optional shape | 6.1, 13 |
| widgetSparkEnabled / `k` | Bool | false | 6.1, 13 |
| reminderSummary / `n` | ReminderSummary? | Absent → unknown/not configured, no claim phone reminders are available | 6.1, 19 |
| answeredRequests / `q` | [AnsweredRequest], at most 8 | [] if absent; unknown outcome cannot falsely complete | 6.1, 14 |
| dropLadderLevel / `l` | Int, known 0=full, 1=model rows dropped, 2=account cap | Active required; future level → conservative generic Mac-only-details note, not claim full content | 6.1, 7 |
| entry.payloadGeneration / `g` | Int64 | Required; broken entry unavailable | 6.2–3 |
| entry.digest / `h` | lowercase SHA-256 hex String, 64 characters | Required; invalid/absent equality digest rejects exact-generation key | 6.2–3 |
| entry.effectiveIntervalSeconds / `e` | positive finite Double seconds | Required; invalid entry cannot be treated as healthy at an invented cadence | 6.1, 15 |

**Disabled routing:** encode exactly `{ "i": <sourceID>, "s": "disabled" }`. Decode source/status before the active version header; a valid disabled tombstone wins before reader compatibility checks. Every active manifest requires `v` and `r`. Never fabricate enabled status, dates or generations.

## Display and reminder summary

| Logical field / coding key | Type | Unknown or missing fallback | Consumer KTD |
|---|---|---|---|
| display.meterStyle / `m` | launch-token String (`micro.chip.event` default) | `MeterStyle.default`; valid Full+Tube resolves to Chip while stored token stays Tube | 6.2, 11 |
| display.percentageMode / `p` | `remaining`, `used` String | `remaining`; widget/Siri always remaining independent of field | 11, 13, 18 |
| display.accountTitleInk / `i` | `neutral`, `brand` String | `neutral` | 11 |
| display.appSparkEnabled / `s` | Bool | false | 11, 13 |
| reminder.macUseItUpEnabled / `m` | Bool | false/unknown summary until present | 19 |
| reminder.macBankedResetEnabled / `b` | Bool | false | 19 |
| reminder.phoneChannelEnabled / `p` | Bool | false | 19 |
| reminder.rules / `r` | [ReminderRuleSummary] | [] | 19 |
| reminder.scope / `s` | [`weekly`, `billingPeriod`, `fiveHour`] Strings | [] if absent; unknown entries skip (read-only summary) | 19 |
| rule.amount / `a` | Int, 1...48 hours or 1...30 days | Invalid rule skips, never substitutes a rule that might misstate the Mac | 19 |
| rule.unit / `u` | `hours`, `days` String | Unknown rule skips | 19 |
| rule.threshold / `t` | Int 1...100 | Invalid rule skips | 19 |

Rule summary carries no rule UUID or firing key, because phone Settings only renders it and cannot edit/evaluate. The Mac channel has two switches today, so carrying only one Boolean would lose visible banked-reminder state. Phone delivery remains U15/U16-gated; this summary never proves CloudKit subscription readiness.

## Provider payload, accounts, windows and API spend

| Logical field / coding key | Type | Unknown or missing fallback | Consumer KTD |
|---|---|---|---|
| payload.schemaVersion / `v` | Int, initial 4 | Required; compatible future schema accepted with minimum met | 6.6 |
| payload.minimumReaderVersion / `r` | Int, initial 1 | Required; too high → unusable key, matching v3/skeleton + update note | 6.6 |
| payload.sourceID / `i` | Mac UUID String | Required; mismatch with manifest ignored | 6.3–4, 12 |
| payload.providerID / `p` | providerID String | Required; must match key suffix; unknown provider skipped | 6.3, 12 |
| payload.payloadGeneration / `g` | Int64 | Required; compare with manifest entry; equality digest must match | 6.3 |
| payload.mode / `m` | `subscription`, `spendOnly` String | Required; unknown mode unusable, never fabricate account card | 6.1 |
| payload.capabilityAttention / `c` | Attention String? | nil = no capability line; unknown string → generic needs-attention line | 6.1, 10 |
| payload.mainAccount / `a` | Account? | Required for subscription; nil for spendOnly; missing subscription main → unusable provider | 6.3, 9, 13 |
| payload.accounts / `x` | [Account], extras in main-first registry order after main removed | [] if absent; duplicate IDs or repeated main reject provider (no ambiguous order) | 6.3, 7, 9 |
| payload.omittedAccountCount / `o` | Int | 0; negative invalid; may be positive only over envelope at cap step | 7 |
| payload.apiSpend / `s` | Spend? | nil → no spend row | 6.1, 13 |
| account.id / `i` | Headroom account ID String | Required; no fabricated default for missing IDs | 6.3, 9, 14 |
| account.title / `t` | String: the Mac's displayed name (label, default name, or captured email when "Use email as account name" is on), Mac-disambiguated | Required; empty title uses provider-safe generic account noun; a captured email only as the displayed name | 9, 10, 22 |
| account.planName / `p` | String? | nil; render no plan claim | 6.1, 22 |
| account.freshness / `f` | omitted/live, `pending`, `stale` String | Omitted = live only for structurally complete captured account; unknown → unavailable | 6.7, 10, 15 |
| account.capturedAt / `c` | epoch seconds Int64? | nil for pending or stale without a retained successful reading; required for live/retained content; no invented stamp | 6.2, 8, 15 |
| account.attention / `a` | Attention String? | nil = no attention; unknown string → generic needs-attention | 10 |
| account.needsAttention / `h` | Bool, stale only | Required for stale; preserves source permanence independently from current session overlay | 6.7, 10, 13 |
| account.bankedResets / `b` | Int? | nil not reported; 0 reported zero; negative invalid/missing; only Codex consumes | 6.1, 22; R5 |
| account.windows / `w` | [SlimWindow] | Required; explicit [] permitted pending/attention account, missing array corrupt | 6.3, 6.7, 7 |
| account.isRemembered / `k` | Bool, written only when true (added 2026-11-10, default-login plan KTD14) | Absent, false or malformed → an ordinary account. True marks a last-known row for an account the Mac's default login left: always an extra after the engine rows, `stale` with `h` false and no `a`, its windows stale at their original read time or unavailable since their reset. Its `i` is a random Headroom local ID, never derived from an identity digest. A phone that knows the key shows "Last read …" and "Reset … · not read since" and hides each window at its reset; it never counts the row as main, as a check-now miss or as Siri's tighter account. A flag on a main account is ignored. A phone that predates the key reads a stale extra: dimmed rows, the Stale chip and its "waiting for your Mac" wording, numbers still hidden once unavailable. No schema version changes; a Mac with no remembered rows writes byte-identical keys | default-login R7, R8, R12, R17, R21 |
| window.kind / `k` | `fiveHour`, `weekly`, `other`, `billingPeriod` String | Unknown → unrecognized unavailable row/skip; never reinterpret as a known billing pool | 6.7, 13 |
| window.kindName / `n` | String? associated semantic name for other/billingPeriod | Required for other/pool; nil for known 5h/weekly; preserve empty associated name/ID/label, with Usage as visible fallback only | 6.7 |
| window.billingPeriodDuration / `d` | positive finite Double seconds? | Required for billingPeriod; invalid → unresolved/unavailable kind, never assign a fake period | 6.7, 13 |
| window.remaining / `p` | finite Double, one normalized decimal | Required for every emitted window, including unavailable; no fabricated zero; freshness gates numeric visibility | 6.2, 13, 15 |
| window.utilization / `u` | finite source-precision Double? | nil → no live-zero “Available” inference (legacy behavior); never derive exact value from rounded remaining | 6.2, 6.7, 13 |
| window.resetKind / `r` | `scheduled`, `unresolved` String | Unknown → unresolved `.legacyUnknown`; no deadline inference | 6.7, 15 |
| window.resetDeadline / `t` | epoch seconds Int64? | Required iff scheduled; contradictory kind/deadline pair corrupt window/provider | 6.7, 15 |
| window.resetReason / `e` | existing `ResetUnresolvedReason` String? | Required iff unresolved; unknown string → `.legacyUnknown`; nil scheduled | 6.7, 15 |
| window.freshness / `f` | omitted/live, `stale`, `unavailable` String | Omitted = live; unknown = unavailable (hide percentage) | 6.7, 15 |
| window.observedAtOverride / `o` | epoch seconds Int64? | Inherit account capturedAt only for fresh rows; retained stale must carry original time or become unavailable | 6.2, 8, 15 |
| window.unavailableSince / `z` | epoch seconds Int64? | Required when unavailable, or inherit validated original observation as conservative fallback; never stamp fresh time | 6.7, 15 |
| window.isSpark / `s` | Bool | false; Mac projector flags Spark explicitly, no label-string heuristics on phone | 7, 11, 13 |
| spend.id / `i` | API-spend providerID String | Required; no random/default ID; preserve existing API spend identity for projection parity | 6.1, 13 |
| spend.displayName / `n` | safe provider display name String | Required/known provider fallback; no source error or account identity | 6.1, 22 |
| spend.amount / `a` | finite Double?; preserve source sign | nil → no numeric amount; never fabricate zero | 6.1, 13 |
| spend.currency / `c` | ISO currency String? | nil → unknown currency, no invented USD | 6.1 |
| spend.periodLabel / `p` | String | Absent → neutral period label, no fabricated date range | 6.1 |
| spend.kind / `k` | `periodSpend`, `balance` String | Missing → periodSpend for legacy lift; unknown v4 → unknown/no numeric semantic claim | 6.7, 13 |
| spend.capturedAt / `t` | epoch seconds Int64? | nil → no age claim; required for live numeric spend | 8, 15 |
| spend.freshness / `f` | omitted/live, `pending`, `stale` String | Missing live only with complete capture; unknown → unavailable | 6.7, 15 |
| spend.attention / `e` | safe typed `missingKey`, `keyRejected`, `keyLacksAccess`, `setupRequired`, `retryable`, `unknown` String? | Unknown → generic Mac attention; nil = no problem; never raw error | 10, 22 |
| spend.needsAttention / `h` | Bool, stale only | Required for stale; source permanence, no guessed value | 6.7, 10, 13 |

No payload digest field: digest exists only in manifest entry. Provider-generation > expected is used without equality-digest comparison; provider-generation < expected retains checked complete provider, labels its rows Last known after max(120s, heartbeat interval). Need an implementation-safe distinction between newly read lagging bytes and **previously checked** older bytes: manifest only retains the newest digest. Keep old checked cache entries and do not describe a newly encountered older key as digest-verified without the older manifest's digest.

Attention values, exhaustive source mapping and canonical copy are pinned in the review decisions below. Unknown attention uses exactly “Needs attention on your Mac”; associated source strings never enter v4.

## Check-now request and receipt

| Logical field / coding key | Type | Unknown or missing fallback | Consumer KTD |
|---|---|---|---|
| request.schemaVersion / `v` | Int, initial 4 | Required; incompatible request ignored | 14 |
| request.minimumReaderVersion / `r` | Int, initial 1 | Required; higher reader minimum ignored | 14 |
| request.requestID / `q` | random UUID String | Required; no guessed ID | 14.1–3, 14.7 |
| request.requestedAt / `t` | epoch seconds Int64 | Required for launch age backstop; no device-clock progress matching | 14.1–3 |
| request.sourceID / `i` | manifest Mac UUID String | Required; requests only from v4 winner, wrong destination ignored | 14.1–2 |
| receipt.schemaVersion / `v` | Int, initial 4 | Required; incompatible ignored | 14 |
| receipt.minimumReaderVersion / `r` | Int, initial 1 | Required; higher minimum ignored | 14 |
| receipt.sourceID / `i` | Mac UUID String | Required; ignore foreign lineage even though receipt has one global key | 12, 14 |
| receipt.state / `s` | `accepted`, `running`, `finished`, `cooldown` String | Unknown → no progress/finish inference | 14.6–7 |
| receipt.requestIDs / `q` | [UUID String] actively joined request IDs | [] → receipt cannot acknowledge this phone's request; never match clock alone | 14.4, 14.7 |
| receipt.answeredRequests / `a` | [AnsweredRequest], ≤8 | [] if absent | 14.3, 14.6 |
| receipt.startedAt / `t` | epoch seconds Int64? | nil = no display time, never timeout base by Mac clock | 14.6–7 |
| receipt.finishedAt / `f` | epoch seconds Int64? | nil = no finish time claim | 14.6–7 |
| receipt.checkedAt / `c` | epoch seconds Int64? | Required for cooldown presentation only; no completion by clock | 14.4, 14.6 |
| receipt.total / `n` | Int | Required nonnegative when running; invalid receipt ignored | 14.6 |
| receipt.completed / `d` | Int 0...total | Required when running; presentation monotonic max for same own request; invalid ignored | 14.6–7 |
| receipt.lastLanded / `l` | LastLanded? | nil = no title receipt yet | 14.6 |
| receipt.finishedGeneration / `g` | Int64? | Required for finished/cooldown; absent cannot show Just now | 14.5–7 |
| lastLanded.providerID / `p` | providerID String | Unknown → omit landed row | 14.6 |
| lastLanded.accountID / `a` | Headroom account ID String | Missing/unresolvable → omit title rather than fabricate | 14.6, 22 |
| lastLanded.live / `l` | Bool | Required; absent/unknown omits landed status, never defaults true | 14.6 |
| answered.requestID / `q` | UUID String | Invalid item ignored | 14.3, 14.7 |
| answered.outcome / `o` | `finished`, `cooldown`, `failed` String | Unknown → no success claim | 14.3, 14.6 |
| answered.finishedGeneration / `g` | Int64? | Required finished/cooldown; no completion claim until assembled generation reached | 14.7 |

KTD14 needs an explicit field that matches accepted/running receipts to the requesting phone; answered IDs alone are only terminal history. `receipt.requestIDs` handles requests joined to one full refresh. Active receipt requestIDs are required for own-request membership; never match global progress by clocks or source ID alone. No device ID field is repeated inside request (key suffix identifies it); answered IDs need no title. Define generation assembly as every expected provider meeting the manifest requirement (or a documented terminal unavailability), so one newer provider cannot prematurely satisfy finishedGeneration.

## Existing v3 additive fields and store seam

| Field/seam | Type | Unknown or missing fallback | Consumer KTD |
|---|---|---|---|
| wrapper.companionSourceID | String? Mac UUID | nil = older Mac/no declared lineage; malformed ignored with diagnostic category only | 5, 6.4–5 |
| wrapper.companionGeneration | Int64? | nil = older lineage metadata absent; pair must agree before treating as mirror | 5, 6.5 |
| wrapper.sourceID | existing String | Keep existing human-display semantics, never replace by random UUID | 5 |
| wrapper/payload existing fields | unchanged existing v3 contract | frozen build-33 decoder remains authoritative; optional reset provenance nil, renewalDate nil | 5, 6.7, 13 |
| KVS.data(forKey:) | Data? | nil = key missing (not evidence of account absence) | 6, 14 |
| KVS.set(_:forKey:) | local-write result Bool | Reports local acceptance only, never remote delivery | 8, 22 |
| KVS.remove(key:) | local mutation | Idempotent missing-key no-op; verify deletion from phone key counts | 8, 22 |
| KVS.keys()/key enumeration | [String] filtered by known prefix | No payload logging; use launch scan/prefix deletion | 14, 22 |
| KVS.synchronize() | Bool | Never proof of identity or server delivery | 14, 22 |
| changedKeys + changeReason event | [String], typed server/initial/account/quota/unknown | Unknown reason → conservative re-read; account → invalidate independently | 8, 14, 22 |
| quota event | typed event/time only | Diagnostics; force one next ladder step if measured bytes under budget | 7, 22 |


## Reviewed implementation decisions

## Decision 1: a literal two-field disabled tombstone

**Contract:** disabled manifest encodes exactly the short-key source/status pair: `{ "i": <Mac source UUID>, "s": "disabled" }`. Do not attach account/provider fields, display settings, generation or a fabricated timestamp. The disabled form is a deliberate alternate manifest case, not a damaged active manifest.

Decode one minimal routing header (`sourceID`, `status`, optional `schemaVersion`, optional `minimumReaderVersion`) before decoding the active tree. A valid source plus `disabled` returns `.disabled(sourceID)` immediately, before reader-minimum or missing active-field checks. Only the `enabled` branch requires both version fields and all required active fields; it then uses KTD6.6's compatibility/fallback rules. Do not decode the entire active tree before checking status.

This follows the more specific KTD22 “status and source only” instruction and KTD6.5 “status before anything else,” while retaining KTD6.1's header-first active decode pattern. A future writer can be recognized as disabled without understanding its active schema. The field table should explicitly identify “active-only required” fields and make disabled a separate Swift enum case. A corrupt/missing source or unknown status is **not** a valid disabled tombstone; no invented source is assigned.

Once a scoped resolver recognizes disabled, it invalidates v4 provider entries and account-bearing v3 compatibility content through the common transaction and preserves only paused metadata. No older enabled v3/key/cache wins over this explicit disabled form. Identity gate still precedes any KVS read; nil local identity is unavailable, not permission to read a tombstone first.

Required eventual proof: minimal tombstone with no version/generation/date resolves paused; extra unknown tombstone fields are ignored; readable v3 plus disabled v4 is paused; future active reader-minimum still falls back as specified; disabled after race-held captured active write cannot restore accounts; malformed tombstone cannot be mistaken for enabled.

## Decision 2: explicit own-request membership throughout each refresh

**Contract:** retain separate active-run membership and bounded terminal history:

| Field | Meaning | Consumer |
|---|---|---|
| `receipt.requestIDs` / `q`: [request UUID] | Every request accepted into this exact full refresh/cooldown answer; sorted deterministically; retained through that run's finished receipt | Own-request acknowledgement and progress |
| `receipt.answeredRequests` / `a`: [AnsweredRequest], last 8 | Recent terminal answers across runs | Late arrival/relaunch/matching after subsequent runs |
| `manifest.answeredRequests` / `q`: same last-8 terminal representation | Identical request ID/outcome/finished-generation evidence published with the finished snapshot | Snapshot-first completion |
| `AnsweredRequest.requestID` / `q` | The request UUID, not the device UUID or a start time | Exact equality only |
| `AnsweredRequest.outcome` / `o` | finished/cooldown/failed; unknown never means success | Terminal presentation |
| `AnsweredRequest.finishedGeneration` / `g` | Generation of the forced post-refresh flush or cooldown's latest forced flush | Completion waits for assembly |

The Mac adds a joined request's ID to that run's membership before emitting accepted/running progress. It can immediately acknowledge intake; frequent running progress updates still obey KTD8's 15-second spacing. Two requests during one full refresh share counts/probes but retain their own membership. Mac-started launch/popover refresh begins with no phone request IDs; intake adds the ID when a phone actually joins it. Single-account/setup/spend-only work never adds membership or emits a full-refresh answer.

The phone accepts `accepted`/`running` receipt progress only when source matches its requested Mac **and** its own request ID is in the active list. It persists its own pending ID in the App Group, so app/widget/control callers coalesce to one outstanding request per phone install. It cannot infer acknowledgement from an unrelated globally running receipt, later start time, device clocks or generation newer than its request's starting generation.

Finished/cooldown success requires both matching ID evidence and the resolver assembling `finishedGeneration` or later for that source. If the manifest arrives before the receipt, the manifest's matching `AnsweredRequest.finishedGeneration` supplies that proof and completion can happen immediately. A newer heartbeat without its own answered ID is **not** a completed request. “At or above finishedGeneration” cannot be checked until that generation is known from a matching receipt or manifest answer. Terminal receipt keeps the just-finished active IDs even if >8 joined simultaneously; bounded last-eight history is separate, so it does not arbitrarily drop a just-completed joined phone.

Keep one local request state machine shared through App Group state; count maxima and acknowledgement receipt time are phone-local. A late receipt from an earlier request cannot move a new request forward. A different run's larger progress is ignored unless that run explicitly names the current own ID. Active membership consumes measured protocol budget (Decision 3), never expands account payloads.

Required eventual proof: iPhone+iPad join one refresh and both acknowledge/finish; >8 simultaneous members all see terminal own-ID membership without unbounding history; another phone's accepted/running receipt has no effect; Mac-started full refresh joins correctly; unrelated later heartbeat cannot complete; manifest matching answer completes before receipt; per-ID cooldown finishes only on its flush generation; replay after Mac relaunch is deduped by the existing per-device last-handled record.

## Decision 3: measure the complete v4 namespace; never hide request accumulation

**Contract:** the 64 KB measure covers **every existing/proposed value under `headroom.sync.v4.`**, including manifest, retained provider keys, receipt, and current request keys. The v3 key remains outside the v4-set budget. Each provider limit applies to its encoded Data only. Count UTF-8 key names separately for the independent ≤64-byte key requirement; report their total separately if useful. Limits are exactly 15,000 and 64,000 bytes, which conservatively fit both decimal and binary interpretations of the plan’s KB budgets.

One request key exists **per install**, not per pull. All subsequent pulls replace that key's small value, so 30 days of use by one phone creates one retained request record. Last-eight answered IDs replace one bounded array; they do not create additional keys. This resolves accumulation from normal repeated use. It does **not** prove a bound for unlimited installed/reinstalled phones: each fresh install UUID can leave one request key until 30-day pruning.

Publisher computes the measured pre-write set by enumerating existing namespace keys, applying its planned replacements/removals in memory and summing exact encoded bytes. It applies only KTD7's existing ladder; at ≤20 accounts/provider it must retain all accounts. Protocol types use compact sorted encoding; request/receipt writes are measured too, not excluded because they bypass the main coalescer. Quota events remain diagnostic and request deletion stays exactly KTD14.8: sync-off or older-than-30-day pruning only. Never early-delete inactive devices, use one shared request key, drop old terminal evidence early, or add a phone-count limit without authority.

If retained protocol keys exhaust the remaining budget even after permitted model trimming, **stop/report the over-budget write with typed size diagnostics rather than cap accounts inside the envelope or pretend the “set” means providers only**. Leave last valid published content intact. Retry after permitted prune/sync-off recovery. This is the plan's budget stop condition, applied honestly to protocol overhead. Do not auto-delete recent request keys to recover room.

Important limit to record: the Mac cannot enforce an absolute global namespace cap against arbitrarily many independently writing phone installs or atomically measure a KVS cross-device snapshot. The plan gives no finite device envelope and explicitly forbids recent-key pruning. A guarantee for unlimited devices would require a Product/KTD amendment; the implementation can enforce observed pre-write budget, size each local phone request before write, test named phone-count fixtures, and report actual key count/bytes. Do not silently weaken the contract or invent that amendment. The parent can adopt this measured fail/stop behavior now; any demand for an unconditional bound needs plan repair.

Required eventual proof: multi-20 + Spark + manifest + receipt + realistic request keys all measured under limit; 100 pulls by one install leave one key; multiple/reinstalled install keys are included; 30-day prune excludes recent keys; protocol-only overflow reports failure without capping ≤20 accounts; deleted-provider keys cease counting only after the planned removal; concurrent foreign request arrivals are visible on next measurement; no “remote delivered” claim from local set success.

## Decision 4: lagging keys are structurally checked, not fictitiously digest-verified

**Contract:** follow KTD6.3 literally: a same-source, same-provider, structurally valid key below expected generation may be shown even if newly encountered. The newest manifest's digest only applies at **equal** payloadGeneration. Do not compare that digest to a different generation and reject every lagging key; do not invent an older expected digest, put one inside payload, or hash re-encoded content.

Keep local validation evidence separate from wire fields:

| Candidate relation to manifest entry | Acceptance/evidence | Presentation/completion |
|---|---|---|
| Equal generation | SHA-256 of exact raw bytes must equal manifest digest; valid schema/source/provider/body | Normal window provenance; eligible to meet that provider's finished-generation requirement |
| Ahead generation | Structurally checked same-source/provider body; future key uses its own generation; cannot claim checked against an older digest | Used per KTD6.3; later matching manifest must verify raw bytes |
| Behind generation | Use highest usable complete candidate for this source/provider; structural validation is sufficient under explicit lag rule when no matching historical digest is available | Keep original window observation times; Last known after max(120 seconds, chosen heartbeat interval); does not satisfy expected generation |
| Checked cached same-generation payload already exists | Raw bytes/previous checked evidence wins; differing new bytes at that same source/provider/generation violate immutable-generation contract | Reject mutation, retain original complete payload and record category only |
| Wrong source/provider, corrupt body, unsupported reader minimum, invalid digest at equal generation | Unusable | Matching scoped v3 main if available, otherwise skeleton; never merge selected accounts/windows from the bad key |

“Checked cache” means checked required structure/source/provider and, when applicable, checked the manifest digest. Persist raw bytes plus an evidence discriminator (`structural`, `manifestDigestMatched`) and the observed digest value/generation in local cache metadata; hash the actual raw cache bytes to detect local file mutation if needed, but a locally computed hash does not authenticate against a manifest. Never present structural evidence as `digestVerified` in diagnostic code or tests.

Cache keeps one highest accepted candidate per source/provider plus needed bounded prior candidate during reconciliation, not an unbounded history of all generations. Old checked payloads can retain their historical validation evidence. Re-reading an older remote key cannot downgrade a newer local complete provider. A new source clears foreign lineages, and identity scope clears every source's cached data independent of missing remote keys.

Lag first-seen belongs to the unresolved **expected provider payload generation**, created once in the common coordinated transaction. Heartbeat manifest generations that keep that same required payload generation do not restart its grace. When expected provider payload generation actually advances, lag expectation changes; account/window observedAt remains original. An unavailable/past-reset window still hides its percentage regardless of grace. Unknown extra JSON fields remain in raw bytes so the later equal-generation digest is computed over the original payload.

This is an integrity consistency check, not cryptographic authenticity of an Apple account. Signed P5 scope verification is mandatory before production loader reads of any such candidate; a payload source UUID does not replace Apple account scope.

Required eventual proof: cold phone encountering manifest12/key11 shows the complete key with structural evidence then Last known after grace; equal-generation mismatch rejects; ahead key accepted then exact digest verified when manifest catches up; same-generation mutation cannot replace previously checked bytes; highest same-source cached key wins over lower remote; unknown raw fields survive digest verification; unchanged payload generation across five heartbeats does not restart lag grace; account list/order/title/banked data always come from one provider body.

## Decision 5: explicit attention mapping, with typed session overlays

Correction to first preflight: `ProviderSetupOutcome` has **28** current cases, not 27. This was verified by read-only case counting, not a unit test. The mapping below covers all current cases. Wire attention is string-backed; every unrecognized string decodes to `.unknown`, whose line is exactly “Needs attention on your Mac”. No associated source error string is serialized or parsed for mapping.

### Wire values and phone copy

| Raw value | Core phone copy |
|---|---|
| `signInRequired` | Sign in on your Mac |
| `signInAgain` | Sign in again on your Mac |
| `finishingSignIn` | Finishing sign-in on your Mac |
| `setupInProgress` | Finish setup on your Mac |
| `workspaceApproval` | Approve Headroom’s workspace on your Mac |
| `cliMissing` | Install the official CLI on your Mac |
| `cliUpdateRequired` | Update the official CLI on your Mac |
| `allowSignInFile` | Allow Headroom to read sign-in data on your Mac |
| `signInFileUnreadable` | Sign-in data is unreadable on your Mac |
| `signInStorageMismatch` | Review where sign-in data is stored on your Mac |
| `externalToolsApproval` | Review the CLI’s external tools on your Mac |
| `retrying` | Couldn’t read usage\u00a0—\u00a0your Mac will retry |
| `cliDiscoveryRetrying` | Couldn’t confirm the official CLI on your Mac\u00a0—\u00a0will retry |
| `setupScreenUnknown` | Review the official CLI’s setup screen on your Mac |
| `neverOnboarded` | Sign in to this account on your Mac |
| `accessDenied` | Review this account’s access on your Mac |
| `setupFailed` | Setup needs attention on your Mac |
| `setupBlocked` | Another account is being set up on your Mac |
| `unknown` | Needs attention on your Mac |

The table writes NBSP as `\u00a0` visibly to specify exact Swift text escaping in implementation; rendered copy must contain actual NBSP before/after the em dash. Provider-specific naming can use a known provider parameter and `ProviderSignInCopy.cliName/cliProductName` on Mac-owned derivation, but no raw source string substitutes for these sentences. Update-required comes from typed setup failure, not from finding “update” in an error. `cliMissing` copy may be phrased as “Headroom can’t find the official CLI on your Mac” if matching current Mac's calibrated discovery wording; it must not say a merely inconclusive search proved installation absent.

### All 28 ProviderSetupOutcome cases

| Current source case | Base attention |
|---|---|
| claudeCLIMissing | cliMissing |
| claudeLoginRequired | signInRequired |
| claudeTrustRequired | workspaceApproval |
| claudeUnknownUI | setupScreenUnknown |
| claudeTransientCapture | retrying |
| codexCLIMissing | cliMissing |
| codexAuthAbsent | signInRequired |
| codexPermissionDenied | allowSignInFile |
| codexUnsafePermissions | signInAgain |
| codexMalformedAuth | signInFileUnreadable |
| codexCredentialIO | retrying |
| codexRejectedAuth | signInAgain |
| codexStorageMismatch | signInStorageMismatch |
| codexCallbackIncomplete | setupFailed |
| grokCLIMissing | cliMissing |
| grokAuthAbsent | signInRequired |
| grokPermissionDenied | allowSignInFile |
| grokUnsafePermissions | signInAgain |
| grokMalformedAuth | signInFileUnreadable |
| grokCredentialIO | retrying |
| grokRejectedAuth | signInAgain |
| grokTransientCapture | retrying |
| cursorCLIMissing | cliMissing |
| cursorAuthAbsent | signInRequired |
| cursorTrustRequired | workspaceApproval |
| cursorMCPApprovalRequired | externalToolsApproval |
| cursorUnknownUI | setupScreenUnknown |
| cursorTransientCapture | retrying |
| copilotCLIMissing | cliMissing |
| copilotSignedOut | signInRequired |
| copilotLogsUnreadable | retrying |

`UnsafePermissions` maps to sign-in-again recovery, matching current source recovery; do not export permission bits/path. Malformed data remains a separate typed unreadable category. Credential IO is retryable, never proof credentials are rejected. CallbackIncomplete maps setupFailed, not falsely “currently finishing sign-in” without an active typed session.

### Every FailureReason and ProviderCapabilityState case

| Source enum/case | Attention | Scope |
|---|---|---|
| FailureReason.transient(_) | retrying | Account |
| FailureReason.needsReauth(_) | signInAgain | Account |
| FailureReason.scopeDenied(_) | accessDenied | Account |
| FailureReason.decode(_) | retrying | Account |
| FailureReason.notLoggedIn(_) | signInRequired | Account |
| FailureReason.providerSetup(outcome) | Delegate to complete table above | Account |
| ProviderCapabilityState.unknown | nil (pending state remains pending) | Provider |
| ProviderCapabilityState.discovering | nil (do not claim absence) | Provider |
| ProviderCapabilityState.available | nil | Provider |
| ProviderCapabilityState.inconclusive(issue) | cliDiscoveryRetrying | Provider |
| ProviderCapabilityState.confirmedAbsent | cliMissing | Provider |

The capability variant has its own **`cliDiscoveryRetrying`** value rather than sending `retrying` with caller-customized copy: wire → Core copy remains one fixed typed mapping. All seven current `CLIExecutableDiscoveryIssue` cases (shellTimeout, shellSpawnFailure, invalidShellOutput, inaccessibleCandidate, invalidatedHint, launchRace, npmPrefixUnresolved) map to this single value. No issue detail/path crosses the wire. Unknown future issues can retain that generic inconclusive category. Provider capability lines stay on the provider; they are never inserted into every account or converted into account-login state.

### Typed setup-session inputs required for the cases outside snapshots

Current `SetupSessionFailure.updateRequired` lives in `Engine/SetupSessionCoordinator.swift`, not `ProviderSetupOutcome`/`FailureReason`. `SetupWaitingPhase` also lives in Engine intentionally because it uses Mac-only coordinator types. U4's Mac-only `Engine/CompanionAttentionMapping.swift` consumes these types; a closure from AppComposition exports only the safe attention result into the wire projector. **Do not move the coordinator/session types into Sync or include Engine in iOS folders to make mapping compile.**

| Current source state/input | Overlay |
|---|---|
| SetupSessionState.idle | No overlay; use base snapshot attention |
| preparing / SetupWaitingPhase.openingTerminal | setupInProgress (purpose-neutral) |
| waiting or verifying, trust purpose/workspace prompt | workspaceApproval |
| waiting or verifying, approval purpose/Cursor tools approval | externalToolsApproval |
| waiting or verifying, signIn/signInNeedsLoginCommand/deviceCode prompt | finishingSignIn |
| blockedByOpenHandoff | setupBlocked; no fabricated completion |
| blockedByProviderLogin(providerID, active) | setupBlocked; never serialize active account's title/ID as blocker |
| connected | No overlay; use new live snapshot when available |
| failed(failure) | Map complete failure table below |
| cancelled | No active overlay; use base snapshot state |
| removing | No active login overlay; account removal lifecycle controls row export |
| ClaudeInteractiveLaunchReason.versionUnreadable | No cliUpdateRequired inference; current setup prompt controls finishingSignIn |
| ClaudeInteractiveLaunchReason.neverOnboardedExtraAccount | neverOnboarded before a real session begins; active typed session owns waiting/finishing copy |
| extra account + typed outcome.isNeverSignedIn | neverOnboarded when no active session overrides; display copy avoids making an unverified historical claim |

Do not infer never-onboarded from nil `capturedAt` alone, and do not treat `AccountID.primary` as the current main: the registry's chosen main may be an extra. Current type `ProviderSetupOutcome.isNeverSignedIn` covers exactly claudeLoginRequired/codexAuthAbsent/grokAuthAbsent/cursorAuthAbsent; use that existing semantic classifier plus `!account.isBuiltIn`, not an email/auth-file read. The “neverOnboarded” phone line intentionally asks sign-in without claiming that this login has literally never existed. The Mac's typed staging reason can prove the stronger interactive-launch case when present.

| Every SetupSessionFailure case | Overlay |
|---|---|
| executableMissing | cliMissing |
| updateRequired | cliUpdateRequired |
| stagingFailed | setupFailed |
| terminalRejected | setupFailed |
| pasteboardFailed | setupFailed |
| retryExhausted | setupFailed |
| waitingTimedOut | setupFailed; never falsely say success or imply an active check |
| closedBeforeSignIn | signInRequired |
| provider(outcome) | Complete ProviderSetupOutcome mapping |
| providerCapability(state) | Complete provider capability mapping, written at provider scope; missing attention for unknown/discovering/available leaves account base state |

Precedence: first compute separate provider capability and per-account attention. For an account, current typed session overlay wins over old stale snapshot text; no active session → base typed snapshot result, with never-onboarded-extra specialization. Confirmed provider absence must remain visible at provider level even while a session retains its own waiting state; do not overwrite snapshots to achieve it. Readings retain freshness/provenance independently of attention (a stale row is not refreshed by a new sentence).

Required eventual proof: exhaustive Swift switches (no permissive default for current closed enums), table cases for all 28+6+5 source cases, seven discovery issues, all ten SetupSessionState cases and ten SetupSessionFailure cases, explicit session-purpose overlays, unknown string fallback, no source associated strings in encoded payload, R2C6 copy validation, update-required sourced from typed refusal, and never-onboarded classification unaffected by Make Main.

## Additional narrow projection-parity findings

Review identified three further seams in the actual `WidgetSnapshotProjector` contract. These are contract-adoption requirements, not reasons to weaken U4/KTD13's full-envelope comparison. Use one pure canonical **phone-sync projection** on both sides: Mac's schema-3 phone export is canonicalized by that contract, and the v4 resolver's `primaryProjection()` produces the same tree. Keep richer source snapshots unchanged. If local Mac widget export needs its existing source-derived copy, give the projector an explicit context/adapter instead of silently applying phone-only copy to every caller; the paired v3 comparator remains the actual schema-3 phone payload emitted by that Mac publish.

### Date precision

v4's integer Unix seconds cannot reconstruct the subsecond dates currently retained in v3. Use one shared `CompanionWireDate` conversion: `floor(date.timeIntervalSince1970)` to bounded Int64, and reconstruction from that integer. Apply it to **every exported date**, including envelope generatedAt and wrapper publishedAt, scheduled reset deadlines, account capturedAt, retained window observedAt, stale-observedAt, unavailable-since, API spend capturedAt, request/receipt/answered timestamps where present. v3 dates retain their existing Codable representation but the underlying `Date` values are already whole Unix seconds before encoding. Provider source snapshots and real source precision stay untouched. Use exactly this conversion when producing both exports, not `Int(date.timeIntervalSince1970)` in one path (that differs for negative fixture dates) and floor in the other.

Canonicalization must be idempotent and representable without overflow; invalid/nonfinite/unrepresentable dates reject the export rather than manufacture now/epoch. v3 renewal dates are nil by plan. This affects actual projection values, never the test's comparison predicate. Future proof: fixtures with fractional generated/captured/reset/stale/unavailable/spend timestamps compare **entire emitted and reconstructed envelopes** exactly; include an explicit pre-epoch fixture to pin conversion semantics and confirm source values retain fractions after projection.

### Stale copy and permanence

Current v3 provider/spend freshness contains `.stale(message: reason.message, needsAttention: reason.isPermanent)`. A many-to-one typed v4 attention cannot reproduce arbitrary reason.message. The paired schema-3 phone export must use the same safe **Core canonical copy function** that the v4 projection uses, based only on typed companion attention (and known provider context where specified), never source associated strings. Existing schema-3/build-33 accepts any String here; changing the value does not change its schema. This canonicalization requires tests to compare the actual Mac's emitted payload, not uncanonicalized historical source copy.

Preserve permanence independently from session overlay: add `account.needsAttention` / compact `h`, Bool, required when account freshness is stale and omitted otherwise; add the analogous spend `needsAttention` / `h` for stale API spend. Populate it from the **source snapshot** `FailureReason.isPermanent`, not from whichever current account attention overlay happens to be shown. This makes `.stale` reconstructable without making sign-in-progress overwrite an older permanent failure flag or making a generic unknown fallback declare a retryable source permanent. No raw error is needed. Stale copy uses the typed current category from the same canonical capture; explicit Bool preserves original attention semantics. A missing Bool in a new stale v4 object is structural incompatibility/corruption, not a guessed true/false. Known live/pending states have no stale message/flag.

For spend, use the same fixed Core copy mapping from its typed APISpendAttention/category on both paired exports; the amount, currency, period and capturedAt remain separate unchanged semantic values. If a category is unknown, both canonical projections use the generic Mac-attention line while preserving the exported Bool. Main provider freshness should derive from the main account's snapshot freshness; provider capability attention remains separate and must not convert a live snapshot to stale. A current session overlay changes typed copy only, never window/source timestamps or provider capability scope.

Future proof: two different safe source messages mapping to one typed category produce identical canonical v3/v4 freshness; all permanent and retryable source cases retain their true Bool; a stale needs-reauth account under finishing-sign-in overlay reconstructs identical stale freshness; unknown category returns identical generic text without changing its Bool; every API-spend typed state matches; frozen build-33 decoder accepts emitted strings/Bool; source reason.message is unchanged. None of these compare just selected fields or strip the stale message from assertions.

### Unavailable hidden numeric metadata

Current unavailable `WidgetWindowSummary` still stores percentRemaining, optional exact utilization and derived severity; view accessors hide its percentage through freshness. A nullable remaining field cannot losslessly reconstruct that tree. **Contract:** `window.remaining` / `p` is a required finite normalized Double for every emitted window, including unavailable; optional source-precision `utilization` / `u` is retained whenever source provides it. Normalize the hidden remaining value exactly as for live windows and derive severity from it in both projections. Do not encode severity or window ID merely to repair this mismatch; both remain derivable.

Unavailable freshness (and past-reset projection treatment) stays the sole gate for numeric visibility. Hidden numeric metadata must never enter a label/VoiceOver/Siri/control answer, meter fill, Liquid Level wash or visible ranking as an available number. `displayPercentRemaining` remains nil and unavailable windows rank last even though their stored numeric value survives for canonical parity. If the original source has no retained window value, omit that window or use the existing explicit no-reading window representation rather than invent zero to satisfy the required field.

Future proof: unavailable fixture retaining nonzero percent/utilization round-trips to full-envelope equality; original observedAt/unavailableSince are whole-second canonical values; primaryProjection reconstructs exact hidden fields and normalized severity; views and pure widget recipes still show no numeral/fill/wash and rank unavailable last; a past-reset window retains compatible hidden metadata while its percentage is hidden. Phone rendering, Siri and small accessory/control surfaces must consume the visibility accessor/freshness rule, never the raw stored Double.

These rules apply to the actual paired phone exports. Pure contracts may be implemented before P5; production cache-loader adoption remains gated on signed physical identity checks. The actual full paired envelope comparison remains strict; changing the test to ignore dates/copy/hidden values is not an acceptable fix.

## Canonical copy and forward fallbacks

Current producers emit account/spend freshness only as pending, live (omitted), or stale. “Unavailable” for an unknown freshness string is a resolved presentation state, not a new build-33 enum case. Unknown account freshness hides all its window numerals; its primary projection has no windows and uses known `.stale(message: genericAttention, needsAttention: false)`. Unknown spend freshness hides amount and capturedAt, uses the same known generic stale case, and carries no unsupported enum into schema 3. A missing required stale `h` is corrupt; an unknown freshness does not guess permanence from an absent flag.

Unknown spend kind hides its amount and projects `kind: nil`; schema-3’s default period-spend behavior therefore cannot mislabel a numeric balance. Unknown spend attention projects `attention: nil` with generic canonical stale copy. Known attention projects to the existing identical APISpendAttention case. Nil attention on a known stale account/spend is permitted and uses the generic line while retaining its required `h` flag. These are forward fallbacks only; current emitted canonical fixtures preserve every known field in full-envelope equality.

| Spend attention | Canonical phone-sync stale message |
|---|---|
| missingKey | Set up API spend on your Mac |
| keyRejected | Replace the rejected key on your Mac |
| keyLacksAccess | Review the API key’s access on your Mac |
| setupRequired | Set up API spend on your Mac |
| retryable | Couldn’t read the amount\u00a0—\u00a0your Mac will retry |
| unknown or nil while stale | Needs attention on your Mac |

The API-spend label/amount/currency/kind remain independent semantic fields; canonical copy never parses them or source error text. The same Core copy function supplies both actual schema-3 phone exports and v4 primaryProjection. Account nil/unknown attention uses the same generic line. Literal `\u00a0` above specifies actual non-breaking spaces in the resulting Swift string.

Rounding tests must construct actual UsageWindow utilization → remaining → shared row/capsule and both exports, including nominal 15.05% remaining from 84.95 utilization. Binary subtraction can fall below the decimal tie; direct-literal-only tests are insufficient. Implement the documented deterministic nearest-away decimal tie, with idempotence and source-precision preservation; do not introduce a consumer-specific epsilon. Integer epoch dates and measured durations are separate contracts: dates floor; billing duration and LaneSchedule effective intervals retain finite positive Doubles. Amounts preserve finite source values; provider parsing owns any sign constraints.

## Gate and ownership

The first signed probe uses the current KVS/App Group entitlements and a separate DEBUG-only local probe file. Both processes independently sample the current opaque identity and compare archived tokens using isEqual. No token, description, hash or archive is exported. Drive-off, empty-account and same-identity offline behavior must pass on physical hardware before cached loading is adopted. Siri/control integration receives its own final acceptance later. Apple documents the candidate for [iCloud Drive Documents](https://developer.apple.com/documentation/foundation/filemanager/ubiquityidentitytoken); KVS-only suitability is unproven. The probe never adds Documents entitlements to force a result.

Source snapshots retain exact dates, reset provenance and source messages. Phone-sync canonicalization affects only paired exports; local Mac widget exports keep their existing context unless explicitly verified. Review/test evidence lives in `.context/ios-parity-work/`; release acceptance belongs in durable QA records.
