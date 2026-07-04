# AI-client plugins

Plugins installed **into** the agent CLIs (as opposed to the CLIs themselves,
which live in [`registry.toml`](../home/.chezmoidata/registry.toml)). One plugin
is declared once in [`ai-plugins.toml`](../home/.chezmoidata/ai-plugins.toml) and
fanned out across every supported client by
[`run_onchange_after_66-ai-plugins`](../home/.chezmoiscripts/run_onchange_after_66-ai-plugins.sh.tmpl).

## Model

Each `[[plugins]]` entry names one upstream plugin plus a per-client sub-table.
The reconcile script owns the per-CLI verbs; the data file owns only
identifiers. **Adding a new plugin is data-only** (new rows, no script change);
adding a new _client_ is one new backend `case` branch.

| Client      | Install (automated)                                          | Detected via                      | Auth  |
| ----------- | ------------------------------------------------------------ | --------------------------------- | ----- |
| Claude Code | `claude plugin install <slug>`                               | `claude plugin list --json` `.id` | OAuth |
| Gemini CLI  | `gemini extensions install <url> --consent --skip-settings`  | `gemini extensions list`          | OAuth |
| Codex       | `codex plugin marketplace add <repo>` + `codex plugin add …` | `codex plugin list --json`        | OAuth |
| Cursor      | **manual** — no headless plugin CLI                          | `~/.cursor/plugins` probe         | OAuth |

The script installs only what's automatable and **reconciles**: dropping a
plugin from the toml uninstalls it, but only from clients where this repo
installed it (tracked in `~/.local/state/dotfiles/ai-plugins.applied`) — a
plugin you added by hand is never touched.

## What ships today: PostHog

The [PostHog ai-plugin](https://github.com/PostHog/ai-plugin) gives the agent
27+ PostHog tools (analytics, feature flags, experiments, dashboards, error
tracking, LLM analytics) and 30+ on-demand skills. We install **tool/skill
access only** — session telemetry to PostHog LLM Analytics (the plugin's
optional `POSTHOG_*` env-var feature) is intentionally **not** configured.

### One-time authentication (per client)

Installing a plugin does **not** authenticate it. Do this once per client:

- **Claude Code** — run `claude`, then `/mcp`, select `plugin:posthog:posthog`,
  and follow the browser prompt to log into PostHog.
- **Gemini CLI** — invoke any PostHog tool in `gemini`; follow the browser OAuth
  prompt on first use.
- **Codex** — invoke any PostHog tool in `codex`; follow the browser OAuth
  prompt on first use.

### Cursor (manual)

Cursor has no headless plugin CLI, so `chezmoi apply` prints a reminder instead
of installing. In Cursor, add **PostHog** from the
[Cursor Marketplace](https://cursor.com/marketplace) (or **Settings → Plugins**),
or run `/add-plugin posthog` in a Cursor chat, then complete the OAuth prompt.
To remove it, use **Settings → Plugins**.

## Notes

- Gemini's `--skip-settings` is required so a headless apply doesn't hang on the
  extension's interactive "PostHog MCP URL" prompt; the endpoint defaults to
  `https://mcp.posthog.com/mcp`. Self-hosted PostHog: set `POSTHOG_MCP_URL`.
- Claude resolves `posthog` from its official marketplace, so no
  `marketplace add` step is needed there (Codex does need one).
