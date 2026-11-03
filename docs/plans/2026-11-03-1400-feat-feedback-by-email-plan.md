---
title: Feedback by Email into Linear - Plan
type: feat
date: 2026-11-03
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
supersedes: auckland workspace draft 2026-10-15-1128-feat-feedback-to-linear-plan.md (never committed)
---

# Feedback by Email into Linear - Plan

## Goal Capsule

- **Objective:** Anyone using Headroom can report a bug or ask for a feature from the Mac app, the iPhone app or the website, and every report lands in Kyle's Linear Triage with enough context to act on.
- **Means:** Every surface opens a pre-filled email to `support@zantos.co`. Google Workspace forwards that address to Linear's team email intake, which turns each email into a Triage issue. Headroom itself sends nothing to any server.
- **Authority:** Kyle's decisions in the Key Decisions below win on behaviour. AGENTS.md wins on conventions.
- **Execution profile:** Kyle (with his own agent) does the Linear and Google Workspace setup. The implementer does U1–U5 in this repo and U6 in `headroom-site`. Nothing here depends on the setup being finished except the live check in the Verification Contract.
- **Stop conditions:** Stop and ask if the email body cannot carry the diagnostics block in the major Mac mail clients, or if any diagnostics field would need data R4 forbids.

---

## Product Contract

### Summary

A "Send Feedback…" action on the Mac, a "Send Feedback" row on the iPhone and a feedback link on the website. Each opens an email to `support@zantos.co` with a short template and, on the apps, an optional diagnostics block the user can read and edit before sending. Linear's email intake files every email into Triage. AI triage and coding agents work on the Linear side, after the issue exists, and only Kyle starts a fix.

### Problem Frame

Reports arrive scattered across X DMs and email, with no record and no diagnostics. Headroom's bugs depend on the user's setup (which CLIs, which versions, which accounts), so every report starts with a round of questions. Headroom also promises that nothing reaches a developer server. An email the user writes and sends themselves keeps that promise: the user sees every byte, and their own mail account sends it.

### Requirements

**Entry points**
- R1. The Mac app offers "Send Feedback…" in Settings › General › About, in the Support group above the tip jar.
- R2. The iPhone app offers "Send Feedback" in its About section.
- R3. The website footer links to the same address, and `headroom.zantos.co/feedback` redirects to a `mailto:` with the template (the link Kyle sends in reply to X DMs).

**The email**
- R4. Diagnostics hold only: app version and build, OS version, CPU architecture, the version of each installed provider CLI (Claude, Codex, Grok, Cursor, Copilot), which providers are on, and each account's typed status named by provider and position ("Claude #2: notLoggedIn"). Never tokens, emails, account names or IDs, plan names, file paths or raw CLI output.
- R5. The subject starts with a tag Linear can sort on: `[Headroom Mac]`, `[Headroom iPhone]` or `[Headroom Web]`. The body has short prompts ("What happened?", "What did you expect?") above the diagnostics block.
- R6. On the Mac, the action first shows a small sheet with the exact email text, an "Include diagnostics" switch (default on), and two buttons: Open in Mail and Copy. Copy puts the subject, body and address on the clipboard, for people who use webmail. The sheet names the address in plain text.
- R7. The iPhone row opens the email directly (Mail compose through `mailto:`), with app version, iOS version and sync status; no CLI data exists on the phone. If no mail app can open it, the row copies the address and says so.
- R8. Demo mode and the render and bench harnesses open nothing and copy nothing real; the demo sheet shows fixture diagnostics.

**Privacy**
- R9. The privacy policy and App Store listing copy say: Headroom sends nothing itself; if you email feedback, Kyle receives what you send, it is stored in Linear, and AI tools may help sort it. Deletion: email the same address.

### Key Decisions

- **Email, not an in-app sender.** (user-approved 2026-11-03 — chosen over the Oct 15 draft's server endpoint, Anthropic triage call, rate limiting and Turnstile: too much code and privacy surface for a solo app.) Keeps "nothing leaves your Mac" true. Governs R1–R9.
- **No bot on the inbox.** Linear's email intake creates the issues. Tidying, duplicate detection and coding agents run in Linear afterwards. (user-approved 2026-11-03.)
- **A person starts every fix.** Reports are untrusted text written by strangers; an agent that turns them into code changes without Kyle assigning the issue would let a report steer the repo. Agents may label and comment on their own.
- **Linear Free plan.** 250 active issues; archive or upgrade when it nears that.

### Scope Boundaries

- No server, endpoint, API key or analytics in Headroom or `headroom-site` for this feature.
- No crash reporting, screenshots or log attachments.
- No reading of X DMs.
- The in-app troubleshooting sheet in `BUGS.md` stays deferred.

---

## Planning Contract

### Setup owned by Kyle (outside this repo)

1. Linear team (for example `HEA`) with Triage on. Labels: `Bug`, `Feature`, `Source: Mac`, `Source: iPhone`, `Source: Web`, `Source: Email`, `Claude`, `Codex`, `Grok`, `Cursor`, `Copilot`, `Widgets`, `iPhone sync`, `Menu bar`, `Settings`, `Needs info`, `Possible duplicate`.
2. Confirm "Create issues by email" exists on the Free plan (Settings › Teams › team › General). If it does not, use a free Gmail-to-Linear connector instead.
3. `support@zantos.co` in Google Workspace (a Google Group with external posting on, or an alias), forwarding to the Linear intake address. The intake address stays private.
4. Optional: Linear's Cursor (or Codex) integration, so assigning an issue starts an agent.

### Key Technical Decisions

- KTD1. **One pure Core recipe builds every email.** `FeedbackEmail` in `Sources/HeadroomCore/Settings/` takes a value-type input of closed enums and version strings and returns subject, body and a `mailto:` URL. It never takes a `UsageSnapshot`, so forbidden fields cannot reach it. Both iOS targets compile it under the whole-folder rule.
- KTD2. **The `mailto:` URL stays under 1,800 characters.** Long bodies get cut at a line boundary with "(diagnostics trimmed; use Copy for the full report)". Copy always carries the full text.
- KTD3. **CLI versions are read when the sheet opens, off the main actor,** through `CLIExecutableResolver` with a 5-second deadline. Claude reuses the version read the probe already does. A version passes a shape allow-list (digits, dots, short suffix) or becomes "unknown"; a missing CLI is "not installed".
- KTD4. **The address and URLs live in `AboutLinks`,** pinned by `AboutLinksTests` like the other literals.
- KTD5. **The Mac sheet is its own small `Window` scene,** opened like Settings, because the popover closes when focus moves.

---

## Implementation Units

### U1. Core email recipe
- Files: `Sources/HeadroomCore/Settings/FeedbackEmail.swift`, `Sources/HeadroomCore/Settings/AboutLinks.swift`, `Tests/HeadroomCoreTests/FeedbackEmailTests.swift`.
- Tests: accounts list as "Claude #1…" with case names only; a `FailureReason` whose message holds an email yields a line without it; `/Users/x/.local/bin/claude 2.1.300` → "unknown", `2.1.300 (Claude Code)` → "2.1.300"; subject tags per source; percent-encoding round-trips; the 1,800-character cap trims at a line and adds the note; diagnostics off drops the block entirely; the address is pinned.

### U2. Mac diagnostics collector and CLI version reader
- Files: `Sources/HeadroomCore/Engine/FeedbackDiagnosticsCollector.swift`, `Sources/HeadroomCore/Providers/CLIVersionReader.swift`, tests beside them.
- Tests: a fixture with sentinel email, plan and account-title values never surfaces them; missing CLI → "not installed"; timeout → "unknown"; every provider, Copilot included, appears.

### U3. Mac feedback sheet and entry point
- Files: `Sources/HeadroomApp/UI/FeedbackView.swift`, `Sources/HeadroomApp/HeadroomApp.swift` (`Window(id: "feedback")`), `Sources/HeadroomApp/UI/SettingsPanes.swift` (Support group row), `Tests/HeadroomAppTests/FeedbackViewTests.swift`.
- Behaviour: preview text, diagnostics switch, Open in Mail, Copy with a "Copied" confirmation. Kyle approves all copy (`better-writing`, DESIGN.md).
- Tests: the preview equals the email body; turning diagnostics off removes the block from both; demo mode opens nothing.

### U4. iPhone row
- Files: `Sources/HeadroomIOS/Views/Settings/AboutSection.swift` (and the sheet that passes sync status in).
- Tests in U1 cover the iPhone variant (no CLI block, sync status word, no account titles). Verify in the simulator that the row opens a compose sheet.

### U5. Privacy and listing copy
- Files: `docs/release/privacy-policy.md`, `docs/release/appstore-listing.md`.
- Kyle approves the wording; `headroom-site` publishes the same text (U6) before a release that ships U3.

### U6. headroom-site
- Footer "Feedback" link; `/feedback` redirect to the `mailto:` with `[Headroom Web]`; privacy page section from U5.
- The site's AGENTS.md asks for explicit approval to change the footer; approving this plan gives it.

### U7. Docs
- `AGENTS.md`: a short "Feedback (Nov 2026)" note (email only, the never-include fields, no sender).
- `BUGS.md`: deferred items (troubleshooting sheet overlap, daily triage routine).

---

## Verification Contract

| Gate | When |
|---|---|
| `swift build`, `swift test` | U1–U3 |
| `xcodebuild … -scheme HeadroomIOS … build` | U1, U4 |
| `./Scripts/build-app.sh --deps-only && xcodebuild … -scheme HeadroomAppTests … test` | U3 |
| `--render-popover` / Settings render of the About tile, both appearances | U3 |
| Live: Kyle sends one report from a built Mac app and one from the website; both appear in Linear Triage with no R4-forbidden data | Before release |

## Follow-up (not this round)

- A daily scheduled triage routine (labels, duplicate flags, missing-info comments; never closes or merges) once report volume justifies it.
