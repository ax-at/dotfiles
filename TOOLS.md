# 🧰 Tool Catalog

> Auto-generated from `home/.chezmoidata/registry.toml` by `scripts/gen-tools.sh`.
> Do not edit by hand. ✅ = enabled · ⬜ = present but disabled.

## core

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **git** | Distributed version control system | free | GPL-2.0 | [repo](https://github.com/git/git) |
| ✅ | **hunk** | Interactive TUI diff/review viewer (git diff replacement) | free | MIT | [repo](https://github.com/modem-dev/hunk) |
| ✅ | **gh** | GitHub CLI | free | MIT | [repo](https://github.com/cli/cli) |
| ✅ | **chezmoi** | Dotfiles manager that orchestrates this whole setup | free | MIT | [repo](https://github.com/twpayne/chezmoi) |
| ✅ | **mise** | Polyglot runtime manager (node, ruby, java, pnpm, ...) | free | MIT | [repo](https://github.com/jdx/mise) |
| ✅ | **starship** | Cross-shell prompt | free | ISC | [repo](https://github.com/starship/starship) |
| ✅ | **antidote** | Fast zsh plugin manager | free | MIT | [repo](https://github.com/mattmc3/antidote) |
| ✅ | **fzf** | Command-line fuzzy finder | free | MIT | [repo](https://github.com/junegunn/fzf) |
| ✅ | **zoxide** | Smarter cd that learns your habits | free | MIT | [repo](https://github.com/ajeetdsouza/zoxide) |
| ✅ | **ripgrep** | Fast recursive grep (rg) | free | MIT | [repo](https://github.com/BurntSushi/ripgrep) |
| ✅ | **fd** | Fast, user-friendly alternative to find | free | MIT | [repo](https://github.com/sharkdp/fd) |
| ✅ | **bat** | cat clone with syntax highlighting | free | MIT | [repo](https://github.com/sharkdp/bat) |
| ✅ | **eza** | Modern ls replacement with icons | free | MIT | [repo](https://github.com/eza-community/eza) |
| ✅ | **jq** | Command-line JSON processor | free | MIT | [repo](https://github.com/jqlang/jq) |
| ✅ | **yq** | Command-line YAML/JSON/XML processor | free | MIT | [repo](https://github.com/mikefarah/yq) |
| ✅ | **tree** | Recursive directory listing as a tree | free | GPL-2.0 | — |
| ✅ | **wget** | Internet file retriever | free | GPL-3.0 | — |
| ✅ | **btop** | Resource monitor (htop successor) | free | Apache-2.0 | [repo](https://github.com/aristocratos/btop) |
| ✅ | **tealdeer** | Fast tldr client (simplified man pages) | free | MIT | [repo](https://github.com/tealdeer-rs/tealdeer) |
| ✅ | **pv** | Pipe viewer: progress of data through a pipeline | free | Artistic-2.0 | [repo](https://github.com/a-j-wood/pv) |
| ✅ | **pre-commit** | Framework for managing git pre-commit hooks (used by Ultracite) | free | MIT | [repo](https://github.com/pre-commit/pre-commit) |
| ✅ | **shellcheck** | Static analysis linter for shell scripts (used by the test suite) | free | GPL-3.0 | [repo](https://github.com/koalaman/shellcheck) |
| ✅ | **shfmt** | Shell script formatter (used by make lint) | free | BSD-3-Clause | [repo](https://github.com/mvdan/sh) |
| ✅ | **oxfmt** | Formatter for JS/JSON/YAML/HTML/CSS/Markdown (used by make lint; TOML is taplo's) | free | MIT | [repo](https://github.com/oxc-project/oxc) |
| ✅ | **taplo** | TOML toolkit: formatter + JSON-Schema validator (validates registry.toml) | free | MIT | [repo](https://github.com/tamasfe/taplo) |
| ✅ | **actionlint** | Static checker for GitHub Actions workflow files | free | MIT | [repo](https://github.com/rhysd/actionlint) |
| ✅ | **bats-core** | Bash Automated Testing System (shell test runner, used across projects) | free | MIT | [repo](https://github.com/bats-core/bats-core) |
| ✅ | **mas** | Mac App Store command-line interface | free | MIT | [repo](https://github.com/mas-cli/mas) |
| ✅ | **neovim** | Hyperextensible Vim-based text editor (minimal config) | free | Apache-2.0 | [repo](https://github.com/neovim/neovim) |
| ✅ | **tmux** | Terminal multiplexer | free | ISC | [repo](https://github.com/tmux/tmux) |
| ✅ | **ghostty** | Fast, native, GPU-accelerated terminal emulator | free | MIT | [repo](https://github.com/ghostty-org/ghostty) |
| ✅ | **pass-cli** | Proton Pass CLI (chezmoi pulls secrets via this) | free | GPL-3.0 | [repo](https://github.com/protonpass/pass-cli) |
| ⬜ | **findutils** | GNU find/xargs/locate (BSD xargs ships with macOS already) | free | GPL-3.0 | — |

## fonts

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **JetBrains Mono Nerd Font** | Patched monospace font with icons (required for starship/eza/ghostty) | free | OFL-1.1 | [repo](https://github.com/ryanoasis/nerd-fonts) |

## editors

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **Visual Studio Code** | Primary editor (settings are the source of truth) | free | MIT | [repo](https://github.com/microsoft/vscode) |
| ✅ | **Cursor** | AI-native VS Code fork | freemium | proprietary | — |
| ✅ | **Antigravity IDE** | AI Coding Agent IDE | free | proprietary | — |
| ✅ | **Sublime Text** | Fast text editor for quick edits | paid | proprietary | — |

## web

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **eas-cli** | Expo Application Services CLI (cloud builds/submits/updates) | free | MIT | [repo](https://github.com/expo/eas-cli) |
| ✅ | **vercel** | Vercel CLI | free | Apache-2.0 | [repo](https://github.com/vercel/vercel) |
| ✅ | **cloudflared** | Cloudflare Tunnel client | free | Apache-2.0 | [repo](https://github.com/cloudflare/cloudflared) |
| ✅ | **fallow** | Rust-native codebase intelligence for TS/JS (dead code, deps, complexity) | freemium | proprietary | [repo](https://github.com/fallow-rs/fallow) |
| ✅ | **bun** | All-in-one JS runtime & toolkit | free | MIT | [repo](https://github.com/oven-sh/bun) |
| ⬜ | **deno** | Secure runtime for JavaScript and TypeScript | free | MIT | [repo](https://github.com/denoland/deno) |

## databases

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **mysql-client** | MySQL client tools (no server) | free | GPL-2.0 | [repo](https://github.com/mysql/mysql-server) |
| ✅ | **libpq** | PostgreSQL client library + psql | free | PostgreSQL | [repo](https://github.com/postgres/postgres) |

## cloud

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **awscli** | AWS Command Line Interface v2 | free | Apache-2.0 | [repo](https://github.com/aws/aws-cli) |

## react-native

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **watchman** | File-watching service (legacy; required only for Expo SDK <= 55) | free | MIT | [repo](https://github.com/facebook/watchman) |
| ✅ | **cocoapods** | iOS dependency manager (prebuild runs pod install for you) | free | MIT | [repo](https://github.com/CocoaPods/CocoaPods) |
| ✅ | **Android Studio** | Android IDE + SDK + emulator manager | free | Apache-2.0 | — |
| ✅ | **Expo Orbit** | Menu-bar app to manage simulators/emulators/devices and builds | free | MIT | [repo](https://github.com/expo/orbit) |
| ⬜ | **applesimutils** | Apple simulator utilities (used by Detox/RN tooling) | free | MIT | [repo](https://github.com/wix/AppleSimulatorUtils) |

## ai-tools

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **Claude Code** | Anthropic's agentic coding CLI | freemium | proprietary | [repo](https://github.com/anthropics/claude-code) |
| ✅ | **Codex CLI** | OpenAI Codex agentic coding CLI | freemium | Apache-2.0 | [repo](https://github.com/openai/codex) |
| ✅ | **Antigravity CLI** | Google Antigravity agentic coding CLI | free | Apache-2.0 | [repo](https://github.com/google-antigravity/antigravity-cli) |
| ✅ | **opencode** | SST's open-source terminal AI agent | free | MIT | [repo](https://github.com/sst/opencode) |
| ✅ | **Context7 CLI** | Fetches up-to-date library docs (Upstash Context7) | freemium | MIT | [repo](https://github.com/upstash/context7) |
| ✅ | **Context Hub CLI** | Semantic code/context search CLI (Andrew Ng) | free | MIT | [repo](https://github.com/andrewyng/context-hub) |
| ✅ | **Pencil CLI** | Design-to-code CLI (Pencil.dev: canvas designs → code) | freemium | proprietary | — |
| ✅ | **Claude Desktop** | Anthropic Claude desktop app (NOT the CLI) | freemium | proprietary | — |
| ✅ | **ChatGPT Desktop** | OpenAI ChatGPT desktop app | freemium | proprietary | — |
| ✅ | **Codex Desktop** | OpenAI Codex desktop app | freemium | proprietary | — |
| ✅ | **Antigravity** | Agent orchestration platform | free | proprietary | — |
| ✅ | **opencode-desktop** | SST opencode desktop app (beta) | free | MIT | [repo](https://github.com/sst/opencode) |
| ✅ | **Superset** | Desktop orchestrator running multiple agents in parallel worktrees | freemium | proprietary | — |
| ✅ | **Pencil Desktop** | Design-to-code canvas desktop app (Pencil.dev) — GUI, not the CLI | freemium | proprietary | — |

## nanoclaw

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **nanoclaw** | Self-hosted AI agent host — Claude agents in isolated containers, paired to messaging channels | free | MIT | [repo](https://github.com/nanocoai/nanoclaw) |

## openclaw

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **openclaw** | Self-hosted personal AI assistant — autonomous agent paired to chat platforms (WhatsApp, Telegram, Discord) | free | MIT | [repo](https://github.com/openclaw/openclaw) |

## ai-assistants

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **screenpipe** | Local, always-on screen + audio capture with AI search and MCP server (CLI) | freemium | proprietary | [repo](https://github.com/screenpipe/screenpipe) |
| ✅ | **Dayflow** | Automatic work journal — privately turns your screen activity into a daily timeline | freemium | MIT | [repo](https://github.com/JerryZLiu/Dayflow) |

## ai-productivity-tools

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **FluidVoice** | Open-source on-device voice-to-text dictation with AI enhancement for macOS | free | GPL-3.0 | [repo](https://github.com/altic-dev/FluidVoice) |

## productivity

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **Raycast** | Launcher, clipboard history, window management, extensions | freemium | proprietary | — |
| ✅ | **Proton Pass** | Password manager (secret source for this setup) | freemium | GPL-3.0 | [repo](https://github.com/protonpass) |
| ✅ | **Google Chrome** | Web browser | free | proprietary | — |
| ✅ | **OrbStack** | Fast, light Docker & Linux VMs (Docker Desktop alternative) | freemium | proprietary | — |
| ✅ | **Bruno** | Offline, git-friendly API client | free | MIT | [repo](https://github.com/usebruno/bruno) |
| ✅ | **Obsidian** | Markdown knowledge base / notes | freemium | proprietary | — |
| ✅ | **Slack** | Team chat | freemium | proprietary | — |
| ✅ | **Discord** | Voice, video, and text chat for communities | freemium | proprietary | — |
| ✅ | **Rectangle** | Keyboard-driven window snapping (Linux-like) | free | MIT | [repo](https://github.com/rxhanson/Rectangle) |
| ✅ | **Stats** | Menu-bar system monitor | free | MIT | [repo](https://github.com/exelban/stats) |
| ✅ | **VLC** | Media player | free | GPL-2.0 | [repo](https://github.com/videolan/vlc) |
| ✅ | **Shottr** | Free screenshots + annotation + scrolling capture | free | proprietary | — |
| ✅ | **Kap** | Free open-source screen recorder (video/GIF) | free | MIT | [repo](https://github.com/wulkano/Kap) |
| ⬜ | **CleanShot X** | Paid all-in-one screenshot + screencast + annotation upgrade | paid | proprietary | — |
| ⬜ | **Figma** | Design tool (kept in registry, not installed) | freemium | proprietary | — |
| ⬜ | **dockutil** | Script the macOS Dock contents (nicety, off by default) | free | Apache-2.0 | [repo](https://github.com/kcrawford/dockutil) |
| ⬜ | **Syntax Highlight (QuickLook)** | Source-code preview in Finder QuickLook (nicety, off by default) | free | GPL-3.0 | [repo](https://github.com/sbarex/SourceCodeSyntaxHighlight) |
| ⬜ | **QLMarkdown (QuickLook)** | Markdown preview in Finder QuickLook (nicety, off by default) | free | GPL-3.0 | [repo](https://github.com/sbarex/QLMarkdown) |

## linux-feel

| | Tool | Description | Cost | License | Source |
|---|------|-------------|------|---------|--------|
| ✅ | **Karabiner-Elements** | Keyboard remapper (ships Windows/Linux-style shortcuts, terminal-excluded) | free | Unlicense | [repo](https://github.com/pqrs-org/Karabiner-Elements) |
| ✅ | **LinearMouse** | Flat/linear pointer (no acceleration) + scroll control | free | MIT | [repo](https://github.com/linearmouse/linearmouse) |
| ⬜ | **Mac Mouse Fix** | Paid alternative mouse customizer (off by default) | paid | proprietary | [repo](https://github.com/noah-nuebling/mac-mouse-fix) |
