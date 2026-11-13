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

## Accounts

### Default login
The account a provider's CLI is signed in to in its own default config home. The built-in row reads it, so the built-in row is whichever account that is right now.
*Avoid:* active account, current account

An account switcher, a plain sign-in or another app can change it without Headroom being involved.

### Remembered account
An account that used to be the default login and no longer is. Headroom keeps its name, its last reading and its reminder state, and gives them back if it becomes the default login again.
*Avoid:* inactive account, cached account

It is not read while it is away, so its numbers are a last reading, never a live one. It shows as a dimmed row that says when it was last read, and once a limit's reset has passed the row says so and shows no number.

### Merged row
The one row shown when the default login and an added account are the same account. The added account's row stands for both, and both are still read.
*Avoid:* duplicate, linked account

Only a strong identity merges (Claude and Codex). Nothing is stored or removed: when the default login changes again, the two rows come back.

### Engine list
The accounts Headroom reads for a provider: the ones the user signed in to, with the main account first.

### Display list
The rows a surface shows for a provider: the engine list, then any remembered accounts. A remembered account is in the display list and never in the engine list.

## Loading

### Slosh
The travelling liquid surface a vessel shows while Headroom is fetching for it. It moves only while that work is in flight.

### Drip
A single drop falling into an empty vessel, shown while Headroom is waiting on the user (finishing sign-in in Terminal or the browser), so a wait on the user never looks like the app is busy.

### Ghost
A vessel drawn in faint halftone dots: its number is old, or there is no reading yet. It becomes solid when a fresh live reading prints in.
*Avoid:* stale pill (stale is a freshness state with its own treatment)

### Reprint
The Refresh button's loading state: a row of pills mirroring the menu bar, where each pill being re-read turns to a ghost and prints back in at its fresh level when its account lands.
