#!/usr/bin/env bats
# Uninstall/reconcile logic for the three install scripts:
#   20-packages (brew/cask) — registry-driven disable-path; manifest-scoped delete-path
#   30-mise     (npm)        — registry-driven disable-path; manifest-scoped delete-path
#   40-ai-tools (script)     — manifest-scoped removal (ownership + deleted recipe)
#
# Each script is rendered, sourced (main() skipped by the BASH_SOURCE guard), its
# row-emitting functions overridden and its backends stubbed to model installed
# reality in files — no real brew/npm/curl runs.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

# ======================================================================== brew
setup_brew() {
  render_to_file "$(script_tmpl 20-packages)" "$BATS_TEST_TMPDIR/b.sh" full.toml
  source "$BATS_TEST_TMPDIR/b.sh"
  CALLS="$BATS_TEST_TMPDIR/calls"; WORLD="$BATS_TEST_TMPDIR/world" # "type name" lines
  : >"$CALLS"; : >"$WORLD"
  brew_installed() { grep -qxF "$1 $2" "$WORLD"; }
  brew_remove() { echo "remove $1 $2" >>"$CALLS"; }
}

@test "brew: rendered removals are the disabled entries, never enabled tap formulae" {
  render_to_file "$(script_tmpl 20-packages)" "$BATS_TEST_TMPDIR/b.sh" full.toml
  source "$BATS_TEST_TMPDIR/b.sh"
  run removal_rows
  assert_success
  # deno is disabled but cross-platform, so it is a removal candidate everywhere.
  assert_line "brew|deno"
  # figma (cask) and applesimutils (tap formula) are macos-only: a removal
  # candidate only where it has an install table. removal_rows renders against
  # the native OS, so these appear on darwin and are absent on linux.
  if [ "$(uname)" = "Darwin" ]; then
    assert_line "cask|figma"
    assert_line "brew|wix/brew/applesimutils"
  fi
  # The footgun: enabled tap formulae must NEVER be removal candidates.
  refute_output --partial "hunk"
  refute_output --partial "oven-sh/bun"
  refute_output --partial "pencil-dev"
}

@test "brew: a disabled, installed entry is uninstalled (tap path -> basename)" {
  setup_brew
  removal_rows() { printf '%s\n' "brew|wix/brew/applesimutils" "cask|figma"; }
  printf '%s\n' "brew applesimutils" "cask figma" >"$WORLD"
  run remove_stale
  assert_success
  grep -qxF "remove brew applesimutils" "$CALLS"
  grep -qxF "remove cask figma" "$CALLS"
}

@test "brew: a candidate that is not installed is left alone" {
  setup_brew
  removal_rows() { printf '%s\n' "brew|deno"; }
  run remove_stale
  assert_success
  ! grep -q remove "$CALLS"
}

@test "brew: a failed uninstall (still a dependency) soft-fails, exit 0" {
  setup_brew
  removal_rows() { printf '%s\n' "brew|libfoo"; }
  printf '%s\n' "brew libfoo" >"$WORLD"
  brew_remove() { echo "remove $1 $2" >>"$CALLS"; return 1; }
  run remove_stale
  assert_success
  assert_output --partial "FAILED remove"
}

@test "brew: a mas candidate is logged, never auto-removed" {
  setup_brew
  removal_rows() { printf '%s\n' "mas|Some App"; }
  printf '%s\n' "mas Some App" >"$WORLD"
  run remove_stale
  assert_success
  assert_output --partial "remove manually"
  ! grep -q "remove mas" "$CALLS"
}

@test "brew: set -e safe on a total no-op (nothing stale)" {
  setup_brew
  removal_rows() { :; }
  strict() { set -euo pipefail; remove_stale; }
  run strict
  assert_success
}

# ------------------------------------------------ brew manifest / delete-path
setup_brew_manifest() {
  render_to_file "$(script_tmpl 20-packages)" "$BATS_TEST_TMPDIR/b.sh" full.toml
  source "$BATS_TEST_TMPDIR/b.sh"
  CALLS="$BATS_TEST_TMPDIR/calls"; MANIFEST="$BATS_TEST_TMPDIR/manifest"
  WORLD_F="$BATS_TEST_TMPDIR/wf"; WORLD_C="$BATS_TEST_TMPDIR/wc" # installed snapshots
  : >"$CALLS"; : >"$MANIFEST"; : >"$WORLD_F"; : >"$WORLD_C"
  TAB="$(printf '\t')"
  brew_remove() { echo "remove $1 $2" >>"$CALLS"; }
  list_installed_formulae() { cat "$WORLD_F"; }
  list_installed_casks() { cat "$WORLD_C"; }
}

@test "brew: RECORD adopts desired formulae and casks that are installed" {
  setup_brew_manifest
  brew_desired_rows() { printf '%s\n' "Ripgrep|brew|ripgrep" "Figma|cask|figma" "Deno|brew|deno"; }
  brew_registry_names() { printf '%s\n' "Ripgrep" "Figma" "Deno"; }
  brew_present_rows() { printf '%s\n' "brew|ripgrep" "cask|figma" "brew|deno"; }
  printf '%s\n' ripgrep >"$WORLD_F" # deno desired but NOT installed
  printf '%s\n' figma >"$WORLD_C"
  run reconcile_brew_manifest
  assert_success
  grep -qxF "Ripgrep${TAB}brew${TAB}ripgrep" "$MANIFEST"
  grep -qxF "Figma${TAB}cask${TAB}figma" "$MANIFEST"
  ! grep -q Deno "$MANIFEST" # desired-but-not-installed is never recorded
}

@test "brew: a tracked entry deleted from the registry is uninstalled via its stored pkg" {
  setup_brew_manifest
  brew_desired_rows() { :; }
  brew_registry_names() { :; }  # registry now empty -> the entry is a delete
  brew_present_rows() { :; }
  printf 'Applesim\tbrew\twix/brew/applesimutils\n' >"$MANIFEST" # full tap path stored
  printf '%s\n' applesimutils >"$WORLD_F"                        # installed as basename
  run reconcile_brew_manifest
  assert_success
  grep -qxF "remove brew applesimutils" "$CALLS" # normalized to basename to uninstall
  ! grep -q Applesim "$MANIFEST"                  # dropped after successful removal
}

@test "brew: delete-path skips (and drops) a basename a present entry still claims (collision guard)" {
  setup_brew_manifest
  # 'bun' deleted under an old name, but a live entry still installs oven-sh/bun/bun.
  brew_desired_rows() { printf '%s\n' "Bun|brew|oven-sh/bun/bun"; }
  brew_registry_names() { printf '%s\n' "Bun"; }
  brew_present_rows() { printf '%s\n' "brew|oven-sh/bun/bun"; }
  printf 'OldBun\tbrew\tsomeorg/tap/bun\n' >"$MANIFEST" # deleted entry, basename 'bun'
  printf '%s\n' bun >"$WORLD_F"                          # 'bun' is installed (the live one)
  run reconcile_brew_manifest
  assert_success
  ! grep -q remove "$CALLS"     # guard prevents uninstalling a wanted package
  ! grep -q OldBun "$MANIFEST"  # deleted row dropped; live 'Bun' now owns the basename
  grep -qxF "Bun${TAB}brew${TAB}oven-sh/bun/bun" "$MANIFEST"
}

@test "brew: the collision guard is type-scoped (a cask claim does not protect a formula delete)" {
  setup_brew_manifest
  # A present CASK named 'ghostty'; a deleted FORMULA 'ghostty' must still be removed.
  brew_desired_rows() { printf '%s\n' "GhosttyCask|cask|ghostty"; }
  brew_registry_names() { printf '%s\n' "GhosttyCask"; }
  brew_present_rows() { printf '%s\n' "cask|ghostty"; } # only a CASK claims 'ghostty'
  printf 'GhosttyFormula\tbrew\tghostty\n' >"$MANIFEST" # deleted FORMULA
  printf '%s\n' ghostty >"$WORLD_F"
  printf '%s\n' ghostty >"$WORLD_C"
  run reconcile_brew_manifest
  assert_success
  grep -qxF "remove brew ghostty" "$CALLS" # formula delete NOT blocked by the cask claim
}

@test "brew: an entry still in the registry is never delete-removed (disable-path owns it)" {
  setup_brew_manifest
  brew_desired_rows() { :; }                       # disabled -> not desired, not recorded
  brew_registry_names() { printf '%s\n' "Deno"; }  # still present in the registry
  brew_present_rows() { printf '%s\n' "brew|deno"; }
  printf 'Deno\tbrew\tdeno\n' >"$MANIFEST"         # was tracked
  printf '%s\n' deno >"$WORLD_F"                    # still installed
  run reconcile_brew_manifest
  assert_success
  ! grep -q remove "$CALLS"  # delete-path must NOT fire (name still in registry)
  ! grep -q Deno "$MANIFEST" # dropped; remove_stale (disable-path) uninstalls it separately
}

@test "brew: a failed delete-path uninstall is kept in the manifest for retry" {
  setup_brew_manifest
  brew_desired_rows() { :; }
  brew_registry_names() { :; }
  brew_present_rows() { :; }
  brew_remove() { echo "remove $1 $2" >>"$CALLS"; return 1; }
  printf 'Dep\tbrew\tdep\n' >"$MANIFEST"
  printf '%s\n' dep >"$WORLD_F"
  run reconcile_brew_manifest
  assert_success
  assert_output --partial "FAILED remove"
  grep -qxF "Dep${TAB}brew${TAB}dep" "$MANIFEST" # kept for a later re-fire
}

@test "brew: reconcile is set -e safe on a total no-op" {
  setup_brew_manifest
  brew_desired_rows() { :; }
  brew_registry_names() { :; }
  brew_present_rows() { :; }
  strict() { set -euo pipefail; reconcile_brew_manifest; }
  run strict
  assert_success
}

@test "brew: reconcile is set -e safe when a desired entry is not installed" {
  setup_brew_manifest
  brew_desired_rows() { printf '%s\n' "Notthere|brew|notthere"; }
  brew_registry_names() { printf '%s\n' "Notthere"; }
  brew_present_rows() { printf '%s\n' "brew|notthere"; }
  # WORLD_F empty -> the membership grep returns 1; must not abort under set -e.
  strict() { set -euo pipefail; reconcile_brew_manifest; }
  run strict
  assert_success
  ! grep -q . "$MANIFEST"
}

# ========================================================================= npm
setup_npm() {
  render_to_file "$(script_tmpl 30-mise)" "$BATS_TEST_TMPDIR/n.sh" full.toml
  source "$BATS_TEST_TMPDIR/n.sh"
  CALLS="$BATS_TEST_TMPDIR/calls"; WORLD="$BATS_TEST_TMPDIR/world"
  : >"$CALLS"; : >"$WORLD"
  npm_installed() { grep -qxF "$1" "$WORLD"; }
  npm_remove() { echo "remove $1" >>"$CALLS"; }
}

@test "npm: no npm entries are disabled today, so rendered removals are empty" {
  render_to_file "$(script_tmpl 30-mise)" "$BATS_TEST_TMPDIR/n.sh" full.toml
  source "$BATS_TEST_TMPDIR/n.sh"
  run npm_removal_rows
  assert_success
  refute_output --regexp '.'
}

@test "npm: a disabled, installed package is removed by package name" {
  setup_npm
  npm_removal_rows() { printf '%s\n' "left-pad"; }
  printf '%s\n' "left-pad" >"$WORLD"
  run remove_stale_npm
  assert_success
  grep -qxF "remove left-pad" "$CALLS"
}

@test "npm: a disabled package that isn't installed is left alone" {
  setup_npm
  npm_removal_rows() { printf '%s\n' "left-pad"; }
  run remove_stale_npm
  assert_success
  ! grep -q remove "$CALLS"
}

# ------------------------------------------------- npm manifest / delete-path
setup_npm_manifest() {
  render_to_file "$(script_tmpl 30-mise)" "$BATS_TEST_TMPDIR/n.sh" full.toml
  source "$BATS_TEST_TMPDIR/n.sh"
  CALLS="$BATS_TEST_TMPDIR/calls"; MANIFEST="$BATS_TEST_TMPDIR/manifest"; WORLD="$BATS_TEST_TMPDIR/world"
  : >"$CALLS"; : >"$MANIFEST"; : >"$WORLD"
  TAB="$(printf '\t')"
  npm_installed() { grep -qxF "$1" "$WORLD"; } # reality keyed on scoped package name
  npm_remove() { echo "remove $1" >>"$CALLS"; }
}

@test "npm: RECORD adopts desired packages that are installed, by scoped name" {
  setup_npm_manifest
  npm_desired_rows() { printf '%s\n' "Codex|@openai/codex" "Chub|@aisuite/chub"; }
  npm_registry_names() { printf '%s\n' "Codex" "Chub"; }
  printf '%s\n' "@openai/codex" >"$WORLD" # chub desired but NOT installed
  run reconcile_npm_manifest
  assert_success
  grep -qxF "Codex${TAB}@openai/codex" "$MANIFEST"
  ! grep -q Chub "$MANIFEST"
}

@test "npm: a tracked package deleted from the registry is uninstalled and dropped" {
  setup_npm_manifest
  npm_desired_rows() { :; }
  npm_registry_names() { :; }  # registry empty -> the entry is a delete
  printf 'Old\t@old/cli\n' >"$MANIFEST"
  printf '%s\n' "@old/cli" >"$WORLD"
  run reconcile_npm_manifest
  assert_success
  grep -qxF "remove @old/cli" "$CALLS"
  ! grep -q Old "$MANIFEST"
}

@test "npm: a deleted package that isn't installed is left alone and dropped" {
  setup_npm_manifest
  npm_desired_rows() { :; }
  npm_registry_names() { :; }
  printf 'Old\t@old/cli\n' >"$MANIFEST"
  run reconcile_npm_manifest
  assert_success
  ! grep -q remove "$CALLS"
  ! grep -q . "$MANIFEST"
}

@test "npm: a package still in the registry is never delete-removed" {
  setup_npm_manifest
  npm_desired_rows() { :; }                        # disabled -> not desired
  npm_registry_names() { printf '%s\n' "Codex"; }  # still present in the registry
  printf 'Codex\t@openai/codex\n' >"$MANIFEST"
  printf '%s\n' "@openai/codex" >"$WORLD"
  run reconcile_npm_manifest
  assert_success
  ! grep -q remove "$CALLS"   # delete-path skips (name still in registry)
  ! grep -q Codex "$MANIFEST" # dropped; remove_stale_npm handles the disabled removal
}

@test "npm: reconcile is set -e safe on a no-op" {
  setup_npm_manifest
  npm_desired_rows() { :; }
  npm_registry_names() { :; }
  strict() { set -euo pipefail; reconcile_npm_manifest; }
  run strict
  assert_success
}

# ====================================================================== script
setup_script() {
  render_to_file "$(script_tmpl 40-ai-tools)" "$BATS_TEST_TMPDIR/s.sh" full.toml
  source "$BATS_TEST_TMPDIR/s.sh"
  CALLS="$BATS_TEST_TMPDIR/calls"; WORLD="$BATS_TEST_TMPDIR/world"
  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  : >"$CALLS"; : >"$WORLD"; : >"$MANIFEST"
  TAB="$(printf '\t')"
  # Model reality by NAME: the stubbed "check" string is the tool name.
  script_installed() { grep -qxF "$1" "$WORLD"; }
  script_do_remove() { echo "remove $1" >>"$CALLS"; }
}

@test "script: rendered desired rows carry name|check|uninstall_cmd for the 4 tools" {
  render_to_file "$(script_tmpl 40-ai-tools)" "$BATS_TEST_TMPDIR/s.sh" full.toml
  source "$BATS_TEST_TMPDIR/s.sh"
  run script_desired_rows
  assert_success
  assert_line "opencode|opencode --version|rm -rf ~/.opencode/bin"
  assert_line --partial "Claude Code|claude --version|rm -f ~/.local/bin/claude"
}

@test "script: turning a module off makes its tools removal candidates" {
  render_to_file "$(script_tmpl 40-ai-tools)" "$BATS_TEST_TMPDIR/s.sh" ai-off.toml
  source "$BATS_TEST_TMPDIR/s.sh"
  run script_removal_rows
  assert_success
  assert_output --partial "Claude Code|"
  assert_output --partial "opencode|"
  refute_output --partial "pass-cli" # module=core, still enabled
}

@test "script: record adopts desired tools that are installed" {
  setup_script
  script_desired_rows() { printf '%s\n' "alpha|alpha|rm-alpha" "beta|beta|rm-beta"; }
  script_removal_rows() { :; }
  script_registry_names() { printf '%s\n' "alpha" "beta"; }
  printf '%s\n' alpha beta >"$WORLD" # both present
  run reconcile_script
  assert_success
  grep -qxF "alpha${TAB}alpha${TAB}rm-alpha" "$MANIFEST"
  grep -qxF "beta${TAB}beta${TAB}rm-beta" "$MANIFEST"
}

@test "script: an installed tool we never recorded is NEVER removed (ownership gate)" {
  setup_script
  script_desired_rows() { :; }
  script_removal_rows() { printf '%s\n' "orphan|orphan|rm-orphan"; }
  script_registry_names() { printf '%s\n' "orphan"; }
  printf '%s\n' orphan >"$WORLD" # present, but manifest is empty -> not ours
  run reconcile_script
  assert_success
  ! grep -q remove "$CALLS"
}

@test "script: a disabled tool we own is uninstalled and dropped from the manifest" {
  setup_script
  script_desired_rows() { :; }
  script_removal_rows() { printf '%s\n' "gamma|gamma|rm-gamma"; }
  script_registry_names() { printf '%s\n' "gamma"; } # still in registry (disabled)
  printf '%s\n' gamma >"$WORLD"
  printf 'gamma\tgamma\trm-gamma\n' >"$MANIFEST" # ours
  run reconcile_script
  assert_success
  grep -qxF "remove rm-gamma" "$CALLS"
  ! grep -q gamma "$MANIFEST"
}

@test "script: a tool deleted from the registry is removed via its stored recipe" {
  setup_script
  script_desired_rows() { :; }
  script_removal_rows() { :; }
  script_registry_names() { :; } # delta is gone from the registry entirely
  printf '%s\n' delta >"$WORLD"
  printf 'delta\tdelta\trm-delta\n' >"$MANIFEST"
  run reconcile_script
  assert_success
  assert_output --partial "deleted from registry"
  grep -qxF "remove rm-delta" "$CALLS"
}

@test "script: a failed remove keeps the tool tracked for retry" {
  setup_script
  script_desired_rows() { :; }
  script_removal_rows() { printf '%s\n' "gamma|gamma|rm-gamma"; }
  script_registry_names() { printf '%s\n' "gamma"; }
  printf '%s\n' gamma >"$WORLD"
  printf 'gamma\tgamma\trm-gamma\n' >"$MANIFEST"
  script_do_remove() { echo "remove $1" >>"$CALLS"; return 1; }
  run reconcile_script
  assert_success
  assert_output --partial "FAILED remove"
  grep -qxF "gamma${TAB}gamma${TAB}rm-gamma" "$MANIFEST" # kept
}

@test "script: set -e safe on a total no-op" {
  setup_script
  script_desired_rows() { printf '%s\n' "alpha|alpha|rm-alpha"; }
  script_removal_rows() { :; }
  script_registry_names() { printf '%s\n' "alpha"; }
  printf '%s\n' alpha >"$WORLD"
  printf 'alpha\talpha\trm-alpha\n' >"$MANIFEST"
  strict() { set -euo pipefail; reconcile_script; }
  run strict
  assert_success
}
