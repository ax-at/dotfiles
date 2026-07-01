# 🧩 Editor Extensions — Proposed Additions (VS Code + Cursor)

> **Status:** proposal / backlog. Not yet applied.
> **Applies to:** `home/.chezmoiscripts/run_onchange_after_50-editor-extensions.sh.tmpl`
> (shared install list for both VS Code and Cursor).

This document captures recommended extension additions derived from the tools in
[`TOOLS.md`](../TOOLS.md), cross-referenced against denysdovhan's dotfiles. Pick up
later and fold approved entries into the `EXTENSIONS=( … )` array in the script.

## Ground rules (already true in the repo)

- **Lint/format = Oxc** (`oxc.oxc-vscode`, oxlint + oxfmt via Ultracite).
  Do **NOT** add ESLint, Prettier, or Biome — they conflict with the Oxc stack.
- **AI** is handled by Cursor natively / Claude Code in VS Code.
  Do **NOT** add Copilot/Continue-style extensions.
- Bruno is a standalone app; no editor extension needed.

## Already installed (baseline — keep)

```
oxc.oxc-vscode
expo.vscode-expo-tools
msjsdiag.vscode-react-native
bradlc.vscode-tailwindcss
eamodio.gitlens
usernamehw.errorlens
editorconfig.editorconfig
christian-kohler.npm-intellisense
yoavbls.pretty-ts-errors
yzane.markdown-pdf
tamasfe.even-better-toml
timonwong.shellcheck
foxundermoon.shell-format
redhat.vscode-yaml
github.vscode-github-actions
yzhang.markdown-all-in-one
```

## Essential additions (clear tool gap)

| Extension ID                           | Serves (TOOLS.md)                                                      |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `ms-azuretools.vscode-docker`          | OrbStack / Docker — Dockerfile + compose, container view               |
| `amazonwebservices.aws-toolkit-vscode` | awscli — profiles, Lambda, S3, CloudWatch logs                         |
| `mtxr.sqltools`                        | libpq/psql + mysql-client — in-editor SQL client (needs drivers below) |
| `mtxr.sqltools-driver-pg`              | Postgres driver for SQLTools                                           |
| `mtxr.sqltools-driver-mysql`           | MySQL driver for SQLTools                                              |
| `github.vscode-pull-request-github`    | gh — review/create PRs & issues in-editor                              |
| `christian-kohler.path-intellisense`   | path autocomplete (complements npm-intellisense)                       |
| `mikestead.dotenv`                     | `.env` syntax highlight (Expo/EAS/Vercel projects)                     |

## Recommended (strong DX, RN/TS-focused)

| Extension ID                            | Serves                                    |
| --------------------------------------- | ----------------------------------------- |
| `dsznajder.es7-react-js-snippets`       | RN/React snippets                         |
| `wix.vscode-import-cost`                | inline import bundle cost — useful for RN |
| `orta.vscode-jest`                      | Jest is RN's default test runner          |
| `streetsidesoftware.code-spell-checker` | typo catcher for code + docs              |

## Optional (polish)

| Extension ID                | Note                                        |
| --------------------------- | ------------------------------------------- |
| `pkief.material-icon-theme` | file icons; pairs with Nerd Font            |
| `naumovs.color-highlight`   | inline color swatches (Tailwind/RN styling) |
| `gruntfuggly.todo-tree`     | surfaces TODO/FIXME                         |

## ⚠️ Cursor caveat (must verify before wiring into the shared script)

Cursor installs from the **Open VSX** registry, not the Microsoft Marketplace.
Most of the above are on Open VSX, but Microsoft/Amazon-published ones can lag or
be absent. `cursor --install-extension` will **silently `--force`-fail** on a
missing ID while VS Code succeeds — so the shared list can drift.

Verify on Open VSX before adding to the shared array:

- `ms-azuretools.vscode-docker`
- `amazonwebservices.aws-toolkit-vscode`

(`msjsdiag.vscode-react-native` is confirmed on Open VSX.)

If either is unavailable, split the script into a shared list + a per-editor
supplemental list (VS Code-only) rather than forcing it into both.
