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
