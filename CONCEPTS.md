# Concepts

> Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Menu bar

### Pill
One compact usage meter in the menu bar: a small vessel showing how much of one provider's limit is left, optionally with its percentage beside it.

The menu bar carries either separate pills (one per chosen provider, in the user's order) or one automatic summary. Each provider's pill reads that provider's main account. Removing a pill hides it from the menu bar only; the provider's account stays connected and keeps being fetched.

### Automatic summary
The menu bar mode that shows a single pill following whichever provider is closest to its limit.
*Avoid:* auto pill

Each provider's pill value still decides which of its limits competes for the summary. Adding any provider's pill leaves this mode for separate pills.

### Pill value
Which of a provider's limits its pill follows: one named limit the provider reports, or Closest to limit.
*Avoid:* window choice, usage window

When the chosen limit is missing from the latest usage, the pill shows the lowest remaining limit instead and keeps the choice, returning to it when the limit is reported again.

### Closest to limit
The pill value that follows whichever of the provider's limits has the least remaining right now, re-evaluated on every refresh.

### Shelf
The Settings row holding every provider that has no pill in the menu bar, including providers that are switched off. A card is moved between the shelf and the menu bar row to add or remove its pill.
*Avoid:* available pills, not-shown list

## Notifications

### Use-it-up reminder
An opt-in Mac notification that a limit is close to resetting while at least a chosen share of it is still unused. Each reminder is a user-defined rule: a lead time before the reset and a "% or more left" threshold.
*Avoid:* expiry alert, burn reminder

A reminder fires at most once per limit per reset, only from a fresh reading, and only for limit kinds ticked in Applies to.

### Banked-reset notice
An opt-in Mac notification that Codex banked a new spare reset for an account. It fires only when a fresh reading shows the count rising above the last count Headroom saw; the first count seen for an account never fires.
