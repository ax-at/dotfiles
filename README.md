# dotfiles

One-command setup for a **highly opinionated** Mac (and, later, Linux) development machine — web (React/Next/Vite) and native (React Native/Expo). It ships a curated stack with the **decisions already made**; [chezmoi](https://www.chezmoi.io) is the single orchestrator that installs everything, applies configs, and is safe to re-run on a fresh **or** existing machine.

- **What gets installed:** see [TOOLS.md](./TOOLS.md) (auto-generated from the registry) and [SKILLS.md](./SKILLS.md) (global [agent skills](#-agent-skills)).
- **Source of truth:** [`home/.chezmoidata/registry.toml`](./home/.chezmoidata/registry.toml) — one block per tool, toggle with `enabled = true/false`.

---

## 🚀 Quickstart (fresh machine) — one command

On a brand-new Mac with **nothing** installed (no git, no Homebrew), paste this single line:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/GauravSharma23/dotfiles/main/install)"
```

It installs [chezmoi](https://www.chezmoi.io) if it's missing (a self-contained static binary — no git/brew required), then clones this repo and applies it.

<details>
<summary>What that one line runs</summary>

The URL serves [`install`](./install), which:

1. installs chezmoi to `~/.local/bin` via `get.chezmoi.io` (only if not already present), then
2. runs `chezmoi init --apply --use-builtin-git=true GauravSharma23` — chezmoi's **built-in git** clones `https://github.com/GauravSharma23/dotfiles.git` and applies everything.

> ⚠️ **`--use-builtin-git=true` is load-bearing on macOS — don't drop it.** chezmoi's `useBuiltinGit` default is `"auto"`, which means _"use the builtin git only if `git` is absent from `$PATH`"_. On macOS `/usr/bin/git` **always** exists as an Xcode stub, so `auto` picks the stub, the stub pops the _"install command line developer tools?"_ dialog, and chezmoi aborts with:
>
> ```
> xcode-select: note: No developer tools were found, requesting install.
> chezmoi: git: exit status 1
> ```
>
> That happens at **clone** time — before `run_once_before_10-prerequisites` (the script that installs the CLT and Homebrew) has any chance to run. Forcing the builtin git for the clone is what makes the bare-Mac bootstrap actually self-contained.

Prefer to skip the wrapper? Run `sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply --use-builtin-git=true GauravSharma23` directly, or — with Homebrew + git already installed — `brew install chezmoi && chezmoi init --apply GauravSharma23`.

</details>

chezmoi will then:

1. install **Rosetta 2** (Apple Silicon) + **Homebrew** (which pulls in the Xcode Command Line Tools),
2. `brew bundle` every enabled package from the registry,
3. install runtimes via **mise** (Node LTS, pnpm, Ruby, Zulu-17 JDK, Python) + npm CLIs,
4. run the official installers for AI tools / `fallow` / `pass-cli`,
5. install editor extensions, generate SSH keys + `gh` login, and apply macOS defaults,
6. drop all dotfiles (zsh, starship, ghostty, git, nano, karabiner, linearmouse).

You'll be **prompted once** for your git identity (work + personal) and a few module toggles.

> 💡 If the Command Line Tools GUI dialog ever blocks the run, finish it and re-run `chezmoi apply`.

> ℹ️ **How to tell it worked.** chezmoi is silent on success — there's no completion banner. A normal shell prompt with no `Error:` line means it finished; confirm with `echo $?` (`0` = success, non-zero = it aborted). A few steps continue on _non-fatal_ errors instead of aborting, so scan the log for stray `HTTP`/`error`/`failed` lines. The known one: registering the SSH **signing** key needs `gh`'s `admin:ssh_signing_key` scope — if it's missing you'll see a `404` there, but the run still completes and everything else is applied.

---

## 🩺 Existing machine (non-destructive) — do this first

chezmoi **overwrites** files it manages. Before the first apply on a machine you care about, install chezmoi **without** applying, then review:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --use-builtin-git=true GauravSharma23   # install + clone, DON'T apply
chezmoi diff                                                   # review every change
chezmoi apply --dry-run --verbose                             # see what scripts would run
# happy? then:
chezmoi apply
```

(Drop the `--apply` and it clones only. If chezmoi is already installed, just `chezmoi init GauravSharma23`.)

Back up any existing `~/.zshrc`, `~/.gitconfig`, etc. that you want to keep.

---

## 🔐 Secrets (Proton Pass)

Secrets are **never committed** and **never written to disk**. The repo only ever holds
`pass://vault/item/field` **reference locators** (not secrets). At the point a tool runs, `pass-cli`
resolves those references and injects the real values into that tool's process environment only —
masked in logs, gone when the process exits:

```sh
# A committed reference (safe to publish):
export SOME_TOKEN="pass://Personal/some-service/password"

# Resolved into the child's env at invocation, nothing persisted:
pass-cli run -- some-tool
```

On a new machine, `pass-cli` installs automatically; authenticate once:

```sh
pass-cli login          # one-time interactive auth
pass-cli info           # verify the session
proton-pass-doctor      # health-check the whole pipeline end to end
```

`proton-pass-doctor` is a `brew doctor`-style diagnostic: it checks that `pass-cli` is installed, a
session is active, and a `pass://` reference actually resolves to a real value — exiting non-zero
with a specific message for whichever step is wrong.

Degrades gracefully: before you log in, references simply stay unresolved and tools fall back to
their own auth — nothing breaks. No secret is wired in this repo yet; each real secret is added as a
per-tool `pass-cli run` wrapper when needed.

---

## ✅ Manual steps (can't be automated)

Tracked here because Apple/vendor flows require a human:

- [ ] Sign in to **Apple ID** (System Settings) — required for the App Store.
- [ ] **Xcode** (iOS builds): install from the **App Store** (or `mas install 497799835`), launch once to accept the license, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- [ ] **Android Studio** first-run: install the SDK + an emulator (AVD). `ANDROID_HOME` is already exported in `.zshrc`.
- [ ] `pass-cli login` (see Secrets).
- [ ] Grant **Karabiner-Elements** and **LinearMouse** their permissions (Input Monitoring / Accessibility) when prompted.
- [ ] **Karabiner**: open it → Complex Modifications → "Add Predefined Rule" → enable all "Windows Shortcuts" rules.
- [ ] **VS Code / Cursor**: turn **off** the built-in Settings Sync (chezmoi manages `settings.json`).
- [ ] **AI-client plugins**: authenticate **PostHog**, **Vercel**, and **Supabase** once per client (browser OAuth). Cursor is auto-imported from Claude — no manual add — see [docs/ai-plugins.md](./docs/ai-plugins.md).
- [ ] **nanoclaw onboarding** (only if `modules.nanoclaw` is enabled): if you deferred it during `chezmoi apply`, finish it with `cd ~/nanoclaw-v2 && bash nanoclaw.sh`.
- [ ] **alphaclaw setup** (only if `modules.alphaclaw` is enabled): start the dashboard with `alphaclaw start`. It needs `SETUP_PASSWORD`, `GITHUB_TOKEN`, and `GITHUB_WORKSPACE_REPO` in the environment; it installs and manages OpenClaw itself.
- [ ] **Log out / back in** so fast key-repeat + modifier changes fully apply.

---

## 🧩 Customizing

Everything is driven by the registry and module toggles.

- **Add a tool:** append a `[[packages]]` block to `home/.chezmoidata/registry.toml`.
- **Remove a tool:** set `enabled = false` (stays documented, won't install).
- **Toggle a whole group:** edit `[modules]` in the registry (or answer the init prompts).
- **Switch an install method** (e.g. AI tool from `brew` → official installer): change the `method` for that entry.
- **Start an app at login (macOS):** add `start_at_login = true` to a `[[packages]]` block. [`75-login-items`](./home/.chezmoiscripts/run_onchange_after_75-login-items.sh.tmpl) reconciles the macOS “Open at Login” list against every flagged app — adding what you flag, removing what you un-flag (scoped by `~/.local/state/dotfiles/login-items.applied`, so hand-added login items are never touched). `true` uses `<name>.app` and starts hidden; use `start_at_login = "Bundle.app"` for a different bundle name, or `start_at_login = { bundle = "Ghostty.app", hidden = false }` to override the bundle and/or launch visible. **First apply needs a one-time macOS Automation consent** — approve the “control System Events” dialog (once per terminal app); a headless run without it is skipped with a warning rather than failing.
- **Regenerate the catalog:** `make update-golden` (CI enforces it stays current).

After editing, apply with `chezmoi apply`. Provisioning scripts re-run automatically when their content changes.

---

## 🧠 Agent skills

A curated set of [agent skills](https://skills.sh) is installed **globally** (available in every project) via [`npx skills`](https://github.com/vercel-labs/skills) for five agents: `universal` (the shared `.agents/skills` dir many tools read), `claude-code`, `openclaw`, `hermes-agent`, and `pi`. The full catalog is in [SKILLS.md](./SKILLS.md).

> **All 71 skills are currently disabled** (every `[[repos]]` block carries `enabled = false`), so the desired set is empty and the next `chezmoi apply` uninstalls the lot. The catalog stays in the file — flip one flag to bring a block back.

- **Source of truth:** [`home/.chezmoidata/skills.toml`](./home/.chezmoidata/skills.toml) — one `[[repos]]` block per source repo: `repo` + a `skills = [...]` list, an optional per-repo `agents` override (omitted → all agents in the top-level `agents` list), and an optional `enabled` flag (omitted → enabled). Each repo installs in a single batched `npx skills add` (one clone, symlinked into every target agent).
- **Agent granularity is per repo, not per skill:** every skill in a `[[repos]]` block shares that block's agent set. If one skill needs a different set, give it its own `[[repos]]` block (as the `ax-at/better-auth-skills` fork does).
- **Add / remove / disable a skill:** add or delete it from a block — or set the block's `enabled = false`, which means _uninstall_, not _ignore_ — then `chezmoi apply`. The script **reconciles** against on-disk reality (`skills list -g --json`): it installs whatever's missing and **uninstalls** anything it previously installed that you've dropped from the file. It reads a manifest at `~/.local/state/dotfiles/skills.applied` only to scope removals, so **skills you add by hand are never removed** — and because reconcile trusts reality, it self-heals if the manifest drifts. (Identity is the skill _name_: hand-adding a skill whose name collides with a curated one makes it look "ours.")
- **Pin a skill:** the CLI has no `@tag` syntax, but `repo` accepts any git source, so point it at a branch URL to pin (e.g. our fork `ax-at/better-auth-skills` for the security skill).
- **Note:** five Matt Pocock skills (`grilling`, `grill-me`, `code-review`, `resolving-merge-conflicts`) plus `shadcn/improve`'s `improve` share names with Claude Code built-ins and **deliberately override** them.
- **Regenerate the catalog:** `make update-skills` (CI enforces it stays current).

Runs after `gh` login (step 65, below), so clones are GitHub-authenticated and dodge anonymous rate limits — without exporting any token to the third-party skills the CLI runs. Installs are best-effort: a broken upstream skill logs a warning and is skipped — it never blocks `chezmoi apply`.

---

## 🔌 AI-client plugins

Plugins installed **into** the agent CLIs (Claude Code, Codex, Cursor, Herdr), as opposed to the CLIs themselves. One plugin is declared once and fanned out across every supported client. Full details in [docs/ai-plugins.md](./docs/ai-plugins.md).

- **Source of truth:** [`home/.chezmoidata/ai-plugins.toml`](./home/.chezmoidata/ai-plugins.toml) — one `[[plugins]]` block per upstream plugin. Two backend families read it: **native per-client** sub-tables (`claude` / `codex` / `cursor` / `herdr`) installed by each client's own CLI, and an **`open`** sub-table installed by the universal [`npx plugins`](https://github.com/vercel-labs/plugins) CLI (a sibling of `npx skills`, needs node + bun). Adding a **new plugin is data-only**.
- **Reconciles like skills:** [`66-ai-plugins`](./home/.chezmoiscripts/run_onchange_after_66-ai-plugins.sh.tmpl) (native) and [`67-open-plugins`](./home/.chezmoiscripts/run_onchange_after_67-open-plugins.sh.tmpl) (`open`) each install what's declared and **uninstall** what you drop — scoped by a per-script manifest (`ai-plugins.applied` / `open-plugins.applied`), so a plugin you added by hand is never touched. Each backend runs only if its CLI (or node+bun) is present.
- **Ships today:** the [PostHog ai-plugin](https://github.com/PostHog/ai-plugin) (27+ tools + 30+ skills) via the native backend, and the [Vercel plugin](https://github.com/vercel/vercel-plugin) (30 skills, 5 commands, 3 agents, MCP) via a **hybrid** backend — `open` for Claude Code, native for Codex (from Codex's built-in `openai-curated` marketplace, since the official repo won't install natively there) — **tool/skill access only**; PostHog session telemetry is left unconfigured and Vercel telemetry is turned off in `.zshrc`. Also the [Supabase plugin](https://github.com/supabase-community/supabase-plugin) (MCP + 2 skills) via the native backend, **Claude Code only** — Codex has no installable package upstream. And [herdr-annotate](https://github.com/plannotator/herdr-annotate) via the native backend, **Herdr only** — it puts [Plannotator](https://github.com/backnotprop/plannotator) plan/diff review in a Herdr pane, and needs the `plannotator` binary the registry installs at step 40.
- **Cursor is off by default:** it auto-imports Claude-installed plugins (shown as _imported_), so no manual step runs — flip an entry's `enabled = true` to opt into an explicit Cursor install.
- **Auth is manual:** installing a plugin doesn't authenticate it — each client needs a one-time browser OAuth ([steps](./docs/ai-plugins.md#one-time-authentication-per-client)).

---

## 🧪 Testing (contributors)

A [bats](https://github.com/bats-core/bats-core) suite covers template rendering, registry integrity, and the provisioning scripts' shell-function logic. It's **offline-first** — no installs, no machine changes. The one network-aware check (zsh plugin validation) **prefers live GitHub** when it's reachable and **falls back to a pinned snapshot** otherwise, so the suite stays green — and never flakes — anywhere. Run it against live GitHub on demand with `make check-plugins`. On a machine provisioned by this repo, `chezmoi` and `bats` are already on PATH (both are in the registry), so there's nothing to set up:

```sh
make test                    # whole suite
make test FILE=templates     # one suite  → test/templates.bats
make test FILTER=oxc         # one test   → regex over test names (bats -f)
make lint                    # shellcheck + shfmt + actionlint
```

The first run fetches pinned `bats` into `test/lib/` (gitignored); the same suite gates every push via [CI](./.github/workflows/ci.yml). Not yet bootstrapped and `chezmoi` isn't on PATH? Point at it once: `make test CHEZMOI_BIN=~/.local/bin/chezmoi`.

---

## 🔁 Day-2 maintenance

```sh
update-all     # brew upgrade + mise upgrade + chezmoi update   (alias in .zshrc)
```

---

## 🗂️ Repository layout

```
dotfiles/
├── install                   # one-line bootstrap (curl'd from raw.githubusercontent.com)
├── .nojekyll                 # serve Pages as static files (don't run Jekyll/Liquid)
├── README.md                 # this guide
├── TOOLS.md                  # generated tool catalog
├── SKILLS.md                 # generated agent-skills catalog
├── .chezmoiroot              # → "home" (keeps repo meta out of $HOME)
├── scripts/                  # maintenance helpers (wired to `make` targets)
│   ├── gen-tools.sh          #   regenerate TOOLS.md from the registry
│   ├── gen-skills.sh         #   regenerate SKILLS.md from skills.toml
│   ├── gen-ghostty-themes.sh #   snapshot Ghostty's built-in themes for tests
│   └── check-plugins-live.sh #   validate zsh plugin refs against live GitHub
├── .github/workflows/ci.yml  # template lint + TOOLS.md freshness + shellcheck
└── home/                     # ← chezmoi source root
    ├── .chezmoi.toml.tmpl    # init prompts (identity + module toggles)
    ├── .chezmoidata/registry.toml  # SINGLE SOURCE OF TRUTH (tools)
    ├── .chezmoidata/skills.toml     # curated global agent skills
    ├── .chezmoidata/ai-plugins.toml # AI-client plugins (PostHog/Supabase/herdr-annotate native; Vercel hybrid: `npx plugins` + native)
    ├── .chezmoiexternal.toml        # fetches Karabiner ruleset
    ├── .chezmoiscripts/             # ordered provisioning steps
    ├── dot_zshrc.tmpl  dot_zsh_plugins.txt  dot_gitconfig.tmpl  dot_nanorc
    └── dot_config/{starship,ghostty,linearmouse,mise}/
        └── mise/conf.d/10-registry-npm.toml.tmpl # GENERATED npm: rows from registry.toml
```

### Provisioning order (`.chezmoiscripts/`)

| Script                                    | Does                                            |
| ----------------------------------------- | ----------------------------------------------- |
| `run_once_before_10-prerequisites`        | Rosetta + Homebrew (+ CLT)                      |
| `run_onchange_after_20-packages`          | generate Brewfile from registry → `brew bundle` |
| `run_onchange_after_30-mise`              | runtimes + registry npm CLIs, via mise          |
| `run_onchange_after_40-ai-tools`          | official `script` installers                    |
| `run_onchange_after_50-editor-extensions` | VS Code + Cursor extensions                     |
| `run_once_after_60-ssh-github`            | SSH key + `gh` auth + signing key               |
| `run_onchange_after_65-agent-skills`      | reconcile global agent skills via `npx skills`  |
| `run_onchange_after_66-ai-plugins`        | reconcile AI-client plugins into the agent CLIs |
| `run_onchange_after_70-macos-defaults`    | dev defaults + Ubuntu-feel tweaks               |
| `run_onchange_after_75-login-items`       | reconcile macOS “start at login” apps           |
| `run_once_after_90-nanoclaw-onboarding`   | prompt to onboard nanoclaw now/later (opt-in)   |

---

## 🐧 Linux (later)

The registry schema already supports `linux` (and per-distro `apt`/`dnf`) install methods, and chezmoi branches on `{{ .chezmoi.os }}` / `{{ .chezmoi.osRelease.id }}`. The Linux GUI-app story (flatpak/snap) and per-distro overrides are intentionally **not built yet**.

---

## ⌨️ Ubuntu-feel notes (Mac mini + Windows keyboard)

- **Karabiner** ships Windows/Linux shortcuts (`Ctrl+C/V/X/Z/A`, `Ctrl+←/→` word-jump, `Home/End`) and **excludes terminals**, so shell `Ctrl+C`/readline stay correct.
- **LinearMouse** disables pointer acceleration (flat, Linux-like movement) and natural scrolling.
- Modifier keys stay at default (Win→⌘, Alt→⌥); Karabiner does the shortcut work — don't also swap ⌘↔⌥.
