# Troubleshooting

Something not showing up, or showing the wrong thing? Find the message Headroom shows below. If
you're still stuck, email **support@zantos.co**.

The `swift run Headroom --probe-…` diagnostics need a source checkout (see
[Development](development.md)). They print redacted classifications and parsed usage, never
credentials.

## Provider setup

Headroom delegates subscription sign-in to each provider's official CLI. For extra
accounts, start the flow from **Settings → Accounts** so Headroom supplies the correct
isolated home; running a plain command yourself targets the built-in account.

| Provider | Official CLI and login | Extra-account isolation | Diagnostic |
|---|---|---|---|
| Claude | [Install Claude Code](https://code.claude.com/docs/en/installation). Run `claude`, then `/login` when needed. There is no device-code flow. | `CLAUDE_CONFIG_DIR` | `swift run Headroom --probe-claude` |
| Codex | [Install Codex CLI](https://developers.openai.com/codex/cli/). Standard: `codex login`. Device code: `codex -c cli_auth_credentials_store=file login --device-auth` (Headroom also uses file-backed CLI auth for standard sign-in). | `CODEX_HOME` | `swift run Headroom --probe-codex` |
| Grok | [Install Grok Build](https://x.ai/news/grok-build). Standard: `grok login`. Device code: `grok login --device-auth`. | `GROK_HOME` | `swift run Headroom --probe-grok` |
| Cursor | [Install Cursor Agent](https://docs.cursor.com/en/cli/installation). Run `cursor-agent login`. Device-code and additional-account flows are unavailable. | None; one account only | `swift run Headroom --probe-cursor` |
| Antigravity | Use the official `agy` CLI 1.5.9 or newer. Turn it on in Settings → Accounts; Headroom hands sign-in to `agy acp --login` in Terminal. If `agy` is signed out, Headroom shows it without opening a sign-in page; after you sign in, Refresh or the row’s Try Again picks it up. A paused-client message means a check could not prove it used no model turn; contact support. | None; one account only | `swift run Headroom --probe-antigravity` |
| Copilot | [Install Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli). Run `copilot login`; Headroom's Terminal handoff clears `COPILOT_HOME`, `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` and `GITHUB_TOKEN` first so it signs in to the default home it reads. "Couldn't read Copilot session logs" retries on its own; choose Check Now after fixing file access. A row with no number means no usage is recorded yet this month: run the CLI once. | None; one account only | `swift run Headroom --probe-copilot` |
| OpenCode | [Install OpenCode](https://opencode.ai/docs/) 2.2 or newer (Homebrew's `opencode` and npm's `@opencode/cli` are 2.x; the `opencode.ai/install` script and npm's `opencode-ai` are still 1.x). Upgrade a 1.x install with `opencode upgrade --major`. Sign in with `opencode auth login opencode --method device`; for the built-in account Headroom asks first, because this adds a Console login to your own OpenCode and makes it the active one. "Go usage needs OpenCode 2.2 or newer" while a 2.x is installed means an older `opencode` comes first on your login shell's `PATH`. "Sign in to OpenCode Console to see Go usage" means only an API key is connected. Headroom ignores `OPENCODE_*` variables, including `OPENCODE_API_KEY`, and XDG settings from your shell profile. | `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME` | `swift run Headroom --probe-opencode` (reads your default OpenCode home with the CLI on your `PATH`; on a 1.x home a 2.x CLI upgrades its data one way) |

### Where Headroom looks for the Claude CLI

Headroom finds `claude` through your login shell first, then the fixed native and Homebrew
locations — including the legacy `~/.claude/local` install. If none of those match, it asks
npm for the active global prefix (`npm prefix -g`) and checks for a launcher there, so a
custom `.npmrc` prefix that never reaches Headroom's inherited `PATH` now works. Anthropic
recommends the native or Homebrew installer for new installs; an existing usable npm-global
launcher stays supported. After moving or reinstalling the CLI, choose **Check Again** —
Headroom rediscovers it without a relaunch or a new sign-in.

The setup and recovery messages map to these actions:

| What Headroom says | What to do |
|---|---|
| CLI not found, location unconfirmed, or waiting for the CLI | Use the provider's install action or link and finish installation. If Headroom shows **Check Again** or an account-level **Check Now**, use it afterward. For Claude, provider-level Check Again bypasses the held negative discovery result, searches again, and refreshes the built-in account without sweeping every account. |
| Not logged in, expired, malformed, or unsafe sign-in | Use **Connect**, **Reconnect**, or **Open Setup** for that account. Codex and Grok also offer **Use Device Code**. Claude may instead ask you to approve Headroom's CLI workspace. |
| Couldn't prepare the handoff / Terminal didn't open | Try again. If Headroom copied the official CLI command, open Terminal and paste it; if copying also failed, retry from Headroom. |
| Setup window still open | Close the Terminal/setup window, then retry. Headroom refuses the action with “Close setup, then retry” instead of silently opening a competing handoff. |
| Privacy denial / sign-in file cannot be read | Choose **Privacy & Security Help**, allow Headroom access in macOS System Settings, then choose **Check Now**. Codex can also offer **Resolve Storage** when its CLI saved credentials somewhere Headroom cannot read. |
| Couldn't read usage / unrecognized CLI screen | Choose **Check Again**. If it persists, run that provider's probe above; probes print redacted classifications and parsed usage, not credentials. |
| Sign-in wasn't confirmed / verification timed out | Choose **Check Now** or reopen setup. Verification has a bounded stop-loss (four minutes, covering one in-flight probe plus the check's own worst case), so it settles to a typed failure instead of spinning forever. |

## API spend

Subscription login cannot authorize organization spend. Add a separate reporting key in
Settings; use a dedicated key with the narrowest access the provider console offers so it
can be revoked independently.

| Spend provider | Required key and where to get it | Known limitation |
|---|---|---|
| Anthropic | [Anthropic admin key](https://platform.claude.com/settings/admin-keys) | The live request currently returns HTTP 400, likely because of the request date format. |
| OpenAI | [OpenAI organization admin key](https://platform.openai.com/settings/organization/admin-keys) | The spend request has not yet been live-verified with a real admin key. |
| xAI | [xAI management key](https://console.x.ai/team/default/settings/management-keys) with only the required ACLs | Validated for one team; multi-team/multi-organization reporting is not supported. |

Headroom stores one key per provider in the macOS Keychain; multiple organizations or keys
per provider are not supported. Diagnose a configured path with
`swift run Headroom --probe-spend <openai|anthropic|xai> [--key-file <path>]`.
