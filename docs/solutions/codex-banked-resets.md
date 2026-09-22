# Codex banked resets are read-only metadata on `wham/usage`

**Date:** 2026-09-22 · **Area:** `CodexProvider` / plan capsule

## Contract

ChatGPT Codex can bank spare rate-limit resets. The count arrives on the usage poll Headroom
already makes, `GET chatgpt.com/backend-api/wham/usage`, as
`rate_limit_reset_credits.available_count`. No second endpoint is called, and nothing in the
app redeems a credit.

- A missing `rate_limit_reset_credits` key is not reported (`bankedResets == nil`).
- A present JSON `null` is reported zero, the same way this endpoint encodes an absent
  `secondary_window`.
- `available_count: 0` is also reported zero. A negative, fractional, or otherwise unusable
  present value is not reported.
- The shipping field is `available_count`. `applicable_available_count` is not read and is
  not printed by `--probe-codex`.

The macOS plan capsule shows `Plan •` at rest and `Plan · N reset(s)` on hover. It opens on
its own only while a live 5-hour or weekly window is Critical (≤15% remaining). Low does not
open it. The first live show of a higher count opens once, for four seconds, and that
acknowledgement is stored per account. A failed poll keeps the last known count. Widgets,
the menu bar, iPhone projection, and Settings specimens ignore the count.

## Live observation (2026-09-22)

`swift run Headroom --probe-codex` on the signed-in account printed `banked resets: 1`
(plan `prolite`, one weekly window). An integer on the shipping path verifies the field
name. This account was not at zero credits, so the zero encoding (`null` versus
`{"available_count": 0}`) is still unobserved. `applicable_available_count` was not printed;
the probe intentionally omits unread fields.

If a later zero-credit capture returns `null` while the account still holds credits, the
null-as-zero reading has to be revisited before relying on it. A body that returns
`{"available_count": 0}` needs no change: reported zero stays zero.
