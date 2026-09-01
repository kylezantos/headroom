---
title: Grok Build usage works through official CLI-owned authentication
date: 2026-08-31
category: provider-integration
tags: [grok, cli, usage, authentication, account-isolation]
---

# Grok Build usage feasibility

## Decision

Grok is feasible as a Headroom subscription provider without a paid plan. The official Grok
Build CLI owns login and credential storage. Headroom first asks the CLI's ACP
`x.ai/billing` method; when the installed CLI reports that method unavailable, Headroom reads
the official CLI-owned credential and calls the CLI billing HTTP surface as a transport
fallback. Neither path submits a model prompt.

The HTTP path is a transport fallback, not a private credential-minting flow: Headroom never
creates, refreshes, or rewrites the CLI credential and never logs the token, user identifier,
raw response, or account identity.

## Live verification

Verified on 2026-08-31 with Grok Build `1.0.13` and a free xAI account:

- `grok login --device-auth` wrote `~/.grok/auth.json` with mode `0600`.
- The file contained one first-party `https://auth.x.ai::…` OIDC record with the token and user
  identifier shapes expected by `GrokAuthBlob`; values were not printed or retained.
- `swift run Headroom --probe-grok` returned a live weekly window with zero usage and a genuine
  scheduled period end through the HTTP fallback.
- The same probe succeeded with `PATH=/usr/bin:/bin`, resolving the native user-local install at
  `~/.grok/bin/grok` from a Finder-like environment.
- Signing the same account into an explicit isolated `GROK_HOME` produced the same live window.
  After official `grok logout` removed that isolated credential, the isolated probe returned
  login-required instead of falling back to the built-in account.
- Standard `grok login` in a fresh isolated home wrote its mode-`0600` credential before the
  successful process exit and immediately produced the same live snapshot. Official logout
  removed only that isolated credential. Neither supported login flow reproduced a successful
  wrapper exit with no readable auth file.
- An Apple Development-signed Headroom bundle on macOS 26.5.1 returned the live weekly window
  under `PATH=/usr/bin:/bin`.
- The sanitized live response carried `currentPeriod`, `billingPeriodStart`,
  `billingPeriodEnd`, `isUnifiedBillingUser`, `onDemandCap`, `onDemandUsed`, and
  `prepaidBalance`. The three overage/balance values were all zero; there was no
  `subscriptionTier` value.

xAI currently advertises Grok Build on its free plan while hiding the CLI's visible `/usage`
command for free and X Basic accounts. The billing status surface nevertheless returned enough
scheduled weekly-period evidence for Headroom's meter:

- <https://x.ai/pricing>
- <https://x.ai/build/changelog>

## Remaining boundaries

This run does not validate active subscription overage semantics because the live account had
no on-demand cap, spend, or prepaid balance. Keep that UI unsurfaced until a genuine non-zero
capture establishes the units and product meaning.

The executable-locator migration also remains blocked. Runtime verification covers the native
`~/.grok/bin` install and a sparse `PATH` in both SwiftPM and a signed bundle. Deterministic tests
cover version-manager precedence, Homebrew fallback selection, missing and non-executable
candidates, and an executable disappearing before ACP spawn. Actual Homebrew/version-manager
installs and macOS 15 Sequoia still need runtime characterization.
