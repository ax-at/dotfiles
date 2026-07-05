# AI-client plugins

Plugins installed **into** the agent CLIs (as opposed to the CLIs themselves,
which live in [`registry.toml`](../home/.chezmoidata/registry.toml)). One plugin
is declared once in [`ai-plugins.toml`](../home/.chezmoidata/ai-plugins.toml).
Two backend **families** read that file, each in its own reconcile script.

## Model

Each `[[plugins]]` entry names one upstream plugin. The reconcile scripts own the
verbs; the data file owns only identifiers. **Adding a new plugin is data-only.**

### Native per-client CLIs — [`run_onchange_after_66-ai-plugins`](../home/.chezmoiscripts/run_onchange_after_66-ai-plugins.sh.tmpl)

A per-client sub-table (`claude` / `gemini` / `codex` / `cursor`) installed by
that client's own plugin CLI. Adding a new _client_ is one new backend `case`.

| Client      | Install (automated)                                          | Detected via                      | Auth  |
| ----------- | ------------------------------------------------------------ | --------------------------------- | ----- |
| Claude Code | `claude plugin install <slug>`                               | `claude plugin list --json` `.id` | OAuth |
| Gemini CLI  | `gemini extensions install <url> --consent --skip-settings`  | `gemini extensions list`          | OAuth |
| Codex       | `codex plugin marketplace add <repo>` + `codex plugin add …` | `codex plugin list --json`        | OAuth |
| Cursor      | **manual**, and **off by default** (see below)               | `~/.cursor/plugins` probe         | OAuth |

### Open plugins (`npx plugins`) — [`run_onchange_after_67-open-plugins`](../home/.chezmoiscripts/run_onchange_after_67-open-plugins.sh.tmpl)

An `open` sub-table installs via the universal
[`plugins` CLI](https://github.com/vercel-labs/plugins) (a sibling of
`npx skills`). Requires **node** (mise) + **bun**. The CLI is **install-only**
(no `list`/`remove`): `plugins add -t <target>` lands the plugin in the target's
**native store** (for `claude-code` it runs `claude plugin install
vercel@claude-plugins-official`), so verify/remove happen there —
`claude-code` reconciles fully; other targets fall back to the manifest and a
printed manual-removal step. Adding a new `open` vendor is new rows only.

```toml
[plugins.open]
repo = "vercel/vercel-plugin"     # what `plugins add` clones
[[plugins.open.targets]]
target = "claude-code"            # id defaults to the plugin name
```

Both scripts **reconcile**: dropping a plugin from the toml uninstalls it, but
only where this repo installed it (tracked per-script in
`~/.local/state/dotfiles/ai-plugins.applied` / `open-plugins.applied`) — a
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

## What ships (hybrid backend): Vercel

The [Vercel plugin](https://github.com/vercel/vercel-plugin) gives the agent the
Vercel ecosystem knowledge graph — **30 skills** (Next.js, AI SDK, deploy,
storage, Turborepo, …), **5 commands**, **3 agents**, and a bundled **MCP
server** (`https://mcp.vercel.com`). One plugin, declared once, but it reaches
different clients through **two** backends:

| Client      | Backend         | How                                                                                          |
| ----------- | --------------- | -------------------------------------------------------------------------------------------- |
| Claude Code | `open`          | `npx plugins add -t claude-code` → `vercel@claude-plugins-official` in Claude's native store |
| Codex       | **native (66)** | `codex plugin add vercel@openai-curated` (built-in marketplace)                              |
| Cursor      | —               | auto-imported from the Claude Code install (see below)                                       |

**Why Codex uses `openai-curated`, not the official repo.** Neither `open`-style
path works on Codex: `npx plugins -t codex` writes a config entry Codex can't
resolve (its ad-hoc `plugins-cli` marketplace roots at `$HOME`) — a "not
installed" phantom — and adding `vercel/vercel-plugin` as a standalone Codex
marketplace fails because the repo's plugin manifest is named `vercel` while
Codex derives `vercel-plugin` from the repo and rejects the mismatch. OpenAI's
built-in [`openai-curated`](https://github.com/openai/plugins) marketplace ships
the **same upstream vercel/vercel-plugin content** repackaged with a Codex-valid
name (`vercel`), so it installs cleanly and reconciles fully (`codex plugin
list` / `remove`). It's bundled with Codex — no marketplace to provision.

- **Prerequisites:** node (mise) + bun (for the `open` backend / Claude Code);
  both are provisioned by this repo.
- **Auth:** the bundled MCP server authenticates on first use, once per client —
  Claude Code: run `claude`, `/mcp`, authorize the `vercel` server; Codex: invoke
  a Vercel tool and follow the browser OAuth prompt. Read-only in the initial
  release (search docs, list projects/deployments, inspect logs).
- **Telemetry:** the plugin's telemetry is **on by default**; we opt out with
  `export VERCEL_PLUGIN_TELEMETRY=off` in [`.zshrc`](../home/dot_zshrc.tmpl),
  matching the no-telemetry posture we keep for PostHog.
- The README's "upstream skill sync" is a **maintainer** build step for the
  vercel-plugin repo — consumers receive the pre-built skills in the versioned
  plugin, so there is nothing to run here.

### Cursor (off by default — auto-imported)

Cursor **auto-imports** plugins installed into Claude Code (they appear in
Cursor's plugin list as _imported_), so installing into `claude-code` covers
Cursor too. Both plugins therefore set Cursor to `enabled = false` — no manual
step runs. To force an explicit Cursor-native install instead, set the Cursor
entry's `enabled = true`; `chezmoi apply` then prints the in-app step (Cursor has
no headless plugin CLI). Complete the OAuth prompt on first use either way.

## Notes

- Gemini's `--skip-settings` is required so a headless apply doesn't hang on the
  extension's interactive "PostHog MCP URL" prompt; the endpoint defaults to
  `https://mcp.posthog.com/mcp`. Self-hosted PostHog: set `POSTHOG_MCP_URL`.
- Claude resolves `posthog` from its official marketplace, so no
  `marketplace add` step is needed there (Codex does need one).
