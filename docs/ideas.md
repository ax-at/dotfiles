# Ideas & backlog

Deferred features worth building when higher-priority work clears. Each entry
records the idea, the reasoning already worked out, and the intended approach so
it can be picked up without re-deriving the context.

## Post-provision macOS permission helper

**Status:** deferred — low priority.

**Idea:** After chezmoi/Homebrew provisioning, guide the user through the
one-time macOS permission grants that GUI casks need — Accessibility, Screen
Recording, Full Disk Access, Input Monitoring, Automation.

**Why not just force-launch the apps.** Opening an app does **not** grant
[TCC](https://developer.apple.com/documentation/devicemanagement/privacypreferencespolicycontrol)
permissions — at most it surfaces a prompt the user must still approve. And most
prompts are **lazy**: they fire on first _use_ of the capability, not on launch,
so a cold `open` frequently surfaces nothing. Mass-launching also steals focus,
registers unwanted login items / menu-bar agents, and triggers system-extension
approvals all at once. The only true pre-grant path is a **signed PPPC
configuration profile via MDM** — overkill for personal dotfiles — and direct
`TCC.db` editing is blocked by SIP.

**Intended approach.**

1. Emit a post-provision **checklist** of which casks need which permissions,
   with `x-apple.systempreferences:` deep links to the right System Settings
   panes.
2. Optionally an **interactive** one-app-at-a-time opener (press-enter-for-next)
   instead of a mass launch.
3. Pre-seed what genuinely **can** be scripted (`defaults` / plist app prefs,
   login-item choices), leaving only the human-required TCC toggles.

Likely a `run_onchange` script driven off the cask list in
[`registry.toml`](../home/.chezmoidata/registry.toml).

## `brew services` support in the registry

**Status:** deferred — waiting on a second consumer.

**Idea:** A per-package `start_service = true` flag that reconciles Homebrew's
`brew services` state, so a formula shipping a launchd/systemd unit (e.g.
[herdr](https://herdr.dev)'s background server) is running and restarts at login.

**Why deferred.** herdr is currently the only candidate in the registry —
`cloudflared` is the one other installed formula with a plist, and it sits at
`status: none` on purpose. Building a general mechanism for a single consumer is
premature, and herdr does not need it: its server auto-spawns on the first
`herdr` invocation, so the flag only buys "already running at login". The natural
trigger to build this is the **second** formula that wants a service.

**Why it is cheaper than login items.** [`run_onchange_after_75-login-items.sh.tmpl`](../home/.chezmoiscripts/run_onchange_after_75-login-items.sh.tmpl)
is the closest analogue, but most of its bulk solves problems this does not have:
four `osascript` heredocs, the TCC/Automation consent probe (error `-1743`), and
`resolve_bundle` guessing between `/Applications` and `~/Applications`. Homebrew
offers a machine-readable oracle instead — `brew services list --json` yields
`[{"name","status","file","exit_code"}]`, and `jq` is already in the registry.
No sudo either: these are per-user LaunchAgents.

**Intended approach.** Same reconcile model as login items — a
`services.applied` state manifest so a stop is only ever issued for a service
**we** started, never one the user or another tool registered.

| Piece                                           | File                                                                                                       | Est.           |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | -------------- |
| `start_service` field + validation              | [`test/lib/registry.schema.json`](../test/lib/registry.schema.json)                                        | ~12 lines      |
| Invariant: flag legal only on `method = "brew"` | [`test/lib/check-crossrefs.sh`](../test/lib/check-crossrefs.sh)                                            | ~8 lines       |
| Reconcile script                                | `run_onchange_after_76-brew-services.sh.tmpl` (new)                                                        | ~110–130 lines |
| Test suite                                      | `test/brew_services.bats` (new)                                                                            | ~150–180 lines |
| Stop-before-uninstall hook                      | [`run_onchange_after_20-packages.sh.tmpl`](../home/.chezmoiscripts/run_onchange_after_20-packages.sh.tmpl) | ~10 lines      |

The script follows the house pattern: a templated `service_desired_rows`, the
manifest, `svc_list` / `svc_start` / `svc_stop` as separate backend functions so
tests can stub them, soft-fail on error, and the `BASH_SOURCE` guard so the
rendered script can be sourced without side effects.
`test/rendered_shellcheck.bats` and `script_tmpl()` both glob
`$SCRIPTS_DIR/*.tmpl`, so a new script needs no wiring to be linted and loaded.

**The one non-boilerplate problem: ordering.** `remove_stale` in 20-packages runs
`brew uninstall --formula` on a disabled entry, and Homebrew does **not** stop a
running service first. That leaves a loaded
`~/Library/LaunchAgents/homebrew.mxcl.<name>.plist` pointing at a deleted Cellar
path — launchd retries it forever, and `brew services list` no longer reports it,
so a later services script cannot clean it up. Numbering the new script _before_
20 does not help: the start-pass would then run before the formula is installed.
The fix is the stop-before-uninstall hook in the table above, which couples the
two scripts and so needs its own test.

**Two scope calls to make up front.**

1. **macOS-only first**, matching login items. `brew services` on Linux needs
   systemd, which neither the CI runners nor the linux path exercise — gate it in
   the `uname` guard rather than shipping untestable surface.
2. **Keep `start_service` a bare boolean.** Resist an object form
   (`{ sudo = true }`) until something actually needs it: no chezmoiscript in
   this repo runs sudo (an apply must never block on a password prompt), and
   system-wide services would break that rule.
