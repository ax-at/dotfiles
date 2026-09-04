#!/usr/bin/env bats
# 30-mise: the registry's npm CLIs.
# Rendering (the conf.d fragment mise installs from) and behaviour (the sweep, the
# presence predicate, the manifest delete-path, main()). reconcile.bats owns the
# shared record/disable/delete machinery this script has in common with 20-packages.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

setup() {
  MISE="$(script_tmpl 30-mise)"
  NPM_CONF="$SRC_DIR/dot_config/mise/conf.d/10-registry-npm.toml.tmpl"
}

@test "mise conf.d: desired npm CLIs render as mise npm-backend rows" {
  run render "$NPM_CONF" full.toml
  assert_success
  assert_output --partial '"npm:eas-cli" = "latest"'
  assert_output --partial '"npm:vercel" = "latest"'
  assert_output --partial '"npm:screenpipe" = "latest"'
  assert_output --partial '"npm:@chrysb/alphaclaw" = "latest"'
}

@test "mise conf.d: no row for a disabled entry or a module-off one" {
  run render "$NPM_CONF" full.toml
  assert_success
  assert_output --partial '"npm:eas-cli" = "latest"'
  refute_output --partial '"npm:ctx7"'
  refute_output --partial '"npm:@aisuite/chub"'
  refute_output --partial '"npm:@pencil.dev/cli"'
  # screenpipe's module is ai-assistants, so the module gate needs its own fixture.
  run render "$NPM_CONF" ai-assistants-off.toml
  assert_success
  refute_output --partial '"npm:screenpipe"'
  assert_output --partial '"npm:eas-cli" = "latest"'
}

# mise resolves a tool by the exact id it was declared under and never canonicalizes.
# vercel is a real short name in mise's own registry, so declaring it bare here would
# install under installs/vercel/ while 30-mise queried npm:vercel, found nothing, and
# silently no-opped every removal path. Lock the key form.
@test "mise conf.d: tools are declared by backend id, never a bare short name" {
  run render "$NPM_CONF" full.toml
  assert_success
  # Both spellings: dropping the prefix alone leaves the key quoted.
  refute_output --partial '"vercel" ='
  refute_output --partial '"eas-cli" ='
  refute_line --regexp '^[[:space:]]*vercel[[:space:]]*='
  refute_line --regexp '^[[:space:]]*eas-cli[[:space:]]*='
}

# taplo.toml excludes **/*.tmpl, so the fragment has no lint coverage at all; a stray
# unquoted key or a broken range would only surface as a mise parse error on apply.
@test "mise conf.d: the rendered fragment parses as TOML" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
  # Not one pipeline: bats leaves pipefail off, and empty input is valid TOML, so a
  # failed render would sail through.
  run render "$NPM_CONF" full.toml
  assert_success
  echo "$output" | taplo check -
}

@test "mise: npm removal goes through mise's backend, not npm" {
  run render "$MISE" full.toml
  assert_success
  assert_output --partial 'mise uninstall --all "npm:$1"'
  # Both would be the PATH-probe install predicate coming back.
  refute_output --partial 'npm install -g'
  refute_output --partial 'npm_install_if_missing'
}

# `mise ls --installed <tool>` exits 0 whether or not the tool is there, so a
# status-based predicate reports everything as installed and silently disables the
# whole removal path. Drive the real function against both shapes of output.
@test "mise: npm presence is read from output, never the exit status" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/pred.sh" full.toml
  source "$BATS_TEST_TMPDIR/pred.sh"

  mise() { return 0; }
  run npm_installed eas-cli
  assert_failure
  mise() { echo "npm:eas-cli  23.2.0  ~/.config/mise/conf.d/10-registry-npm.toml  latest"; }
  run npm_installed eas-cli
  assert_success

  # mise keys a tool by the exact id it was declared under, so the predicate has to ask
  # for the same "npm:" id the conf.d fragment writes. Drop the prefix and mise answers
  # for nothing, every removal path silently no-ops, and only this assertion notices.
  mise() { printf '%s\n' "$*" >"$BATS_TEST_TMPDIR/args"; }
  npm_installed eas-cli || true
  run cat "$BATS_TEST_TMPDIR/args"
  assert_output --partial "npm:eas-cli"
}

@test "mise sweep: clears registry-owned names from a legacy root, nothing else" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/sweep.sh" full.toml
  source "$BATS_TEST_TMPDIR/sweep.sh"

  mkdir -p "$BATS_TEST_TMPDIR/root/lib/node_modules/vercel" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/@old/cli" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/@openai/codex"
  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  # The second row has no tab. Plain `cut -f2` prints such a line whole, which would
  # hand the sweep a name nothing in the registry or the manifest ever claimed.
  printf 'Old\t@old/cli\nfallow\n' >"$MANIFEST"
  mkdir -p "$BATS_TEST_TMPDIR/root/lib/node_modules/fallow"
  : >"$BATS_TEST_TMPDIR/calls"
  # The stubs spell the paths out rather than closing over a variable: bash scopes
  # dynamically, so a name the caller also declares `local` resolves to the caller's
  # empty one and the sweep silently visits nothing.
  npm_registry_pkgs() { printf '%s\n' "vercel" "ctx7"; }
  npm_legacy_roots() { printf '%s\n' "$BATS_TEST_TMPDIR/root"; }
  npm_remove_from() { printf '%s\n' "$2" >>"$BATS_TEST_TMPDIR/calls"; }

  run sweep_legacy_npm
  assert_success
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "vercel"        # registry-owned and present
  assert_line "@old/cli"      # orphan of a deleted entry, reachable via the manifest
  refute_line "ctx7"          # registry-owned but not in this root
  refute_line "@openai/codex" # hand-installed: outside the union, unreachable
  refute_line "fallow"        # a malformed manifest row must not widen the union
}

# An unpinned `npm i -g` lands in whichever node tree was active, so missing one tree
# means the sweep silently leaves a shadowing copy behind. The prefix comes from
# .chezmoidata/paths.toml, which .zprofile renders from too, so the two cannot drift.
@test "mise sweep: legacy roots are the pinned prefix plus every mise node tree" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/roots.sh" full.toml
  source "$BATS_TEST_TMPDIR/roots.sh"

  HOME="$BATS_TEST_TMPDIR/home"
  NPM_CONFIG_PREFIX="$HOME/.local/share/npm-global"
  local installs="$HOME/.local/share/mise/installs/node"
  mkdir -p "$installs/22.22.2/lib/node_modules" "$installs/24.19.0/lib/node_modules" \
    "$installs/20.10.0"

  run npm_legacy_roots
  assert_success
  assert_line "$NPM_CONFIG_PREFIX"
  assert_line "$installs/22.22.2"
  assert_line "$installs/24.19.0"
  refute_line "$installs/20.10.0" # never held a global install
}

# The sweep's candidate set is (these rows) union the manifest's pkg column, and every
# test above stubs this function by hand. Render the real one, or a template edit that
# drops the hasKey gate (leaking a linux-only entry onto macOS) or adds an .enabled gate
# (hiding a disabled entry's orphan from the sweep) would pass the whole suite.
@test "mise: registry pkgs for the sweep span every npm entry, enabled or not" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/pkgs.sh" full.toml
  source "$BATS_TEST_TMPDIR/pkgs.sh"
  run npm_registry_pkgs
  assert_success
  assert_line "eas-cli"
  assert_line "vercel"
  assert_line "screenpipe"
  # Disabled entries stay in the set: their orphans are exactly what the sweep exists
  # to reach, so narrowing this to the desired set would strand them forever.
  assert_line "ctx7"
  assert_line "@aisuite/chub"
  assert_line "@pencil.dev/cli"
  # Nothing from another method may widen it. git is brew, and a brew formula name
  # landing here would let the sweep delete from a node tree on a name npm never owned.
  refute_line "git"
  refute_line "chezmoi"
}

# mise keeps alias links (20, 24, latest, lts) beside the real trees. [ -d ] follows
# them, so without the -L guard every real tree is swept up to four times and the log
# names versions that were never installed.
@test "mise sweep: alias symlinks beside the node trees are not roots of their own" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/alias.sh" full.toml
  source "$BATS_TEST_TMPDIR/alias.sh"

  HOME="$BATS_TEST_TMPDIR/home"
  NPM_CONFIG_PREFIX="$HOME/.local/share/npm-global"
  local installs="$HOME/.local/share/mise/installs/node"
  mkdir -p "$installs/24.19.0/lib/node_modules"
  ln -s "$installs/24.19.0" "$installs/24"
  ln -s "$installs/24.19.0" "$installs/latest"

  run npm_legacy_roots
  assert_success
  assert_line "$installs/24.19.0"
  refute_line "$installs/24"
  refute_line "$installs/latest"
}

# `pkg = "npm"` is a plausible way to try to pin npm from the registry, and the sweep
# would then uninstall npm from the running node.
@test "mise sweep: node's own npm and corepack are never removal candidates" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/bundled.sh" full.toml
  source "$BATS_TEST_TMPDIR/bundled.sh"

  mkdir -p "$BATS_TEST_TMPDIR/root/lib/node_modules/npm" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/corepack" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/vercel"
  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  : >"$MANIFEST"
  : >"$BATS_TEST_TMPDIR/calls"
  npm_registry_pkgs() { printf '%s\n' "npm" "corepack" "vercel"; }
  npm_legacy_roots() { printf '%s\n' "$BATS_TEST_TMPDIR/root"; }
  npm_remove_from() { printf '%s\n' "$2" >>"$BATS_TEST_TMPDIR/calls"; }

  run sweep_legacy_npm
  assert_success
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "vercel"
  refute_line "npm"
  refute_line "corepack"
}

# The mise-side half of the keep-rule: its own uninstall failing is what keeps the row,
# independently of any legacy copy. npm_legacy_copy is stubbed false so this cannot
# pass for the filesystem's reasons instead.
@test "mise: a deleted entry whose mise uninstall FAILS keeps its row for retry" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/fail.sh" full.toml
  source "$BATS_TEST_TMPDIR/fail.sh"

  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  TAB="$(printf '\t')"
  printf 'Context7 CLI\tctx7\n' >"$MANIFEST"
  npm_registry_names() { :; }        # entry deleted from the registry
  npm_desired_rows() { :; }
  npm_legacy_copy() { return 1; }    # nothing on disk; only the exit code can keep it
  npm_installed() { return 0; }
  npm_remove() { return 1; }         # the uninstall fails

  run reconcile_npm_manifest
  assert_success                     # soft-fails, the apply continues
  assert_output --partial "FAILED remove: ctx7"
  run cat "$MANIFEST"
  assert_line "Context7 CLI${TAB}ctx7"

  # Same row, uninstall succeeds: nothing is left to reach, so the row goes.
  printf 'Context7 CLI\tctx7\n' >"$MANIFEST"
  npm_remove() { return 0; }
  run reconcile_npm_manifest
  assert_success
  [ ! -s "$MANIFEST" ]
}

@test "mise sweep: set -e safe on a total no-op" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/noop.sh" full.toml
  cat >"$BATS_TEST_TMPDIR/drive.sh" <<'DRIVE'
set -euo pipefail
source "$1"
MANIFEST="$2"
npm_registry_pkgs() { :; }
npm_legacy_roots() { :; }
npm_remove_from() { return 0; }
sweep_legacy_npm
[ "$NPM_SWEPT" -eq 0 ]
DRIVE
  run bash "$BATS_TEST_TMPDIR/drive.sh" "$BATS_TEST_TMPDIR/noop.sh" "$BATS_TEST_TMPDIR/manifest"
  assert_success
}

# The sibling reconciler has this for 20-packages. Nothing else runs 30-mise's own
# main(), so an unbound NPM_SWEPT or a sweep that trips set -e would ship green.
@test "mise: main() runs end-to-end under set -euo pipefail" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/m.sh" full.toml
  cat >"$BATS_TEST_TMPDIR/drive.sh" <<'DRIVE'
source "$1"
MANIFEST="$2"
HOME="$3"
mise() { case "$1" in activate) echo ":" ;; esac; }
npm_installed() { return 1; }
npm_remove_from() { return 0; }
# The sweep reads the manifest that reconcile rebuilds, so the order is load bearing:
# reversed, every deleted entry's orphan is dropped from the candidate set unswept.
# The comment saying so is not enforcement; this is.
ORDER=""
_sweep=$(declare -f sweep_legacy_npm); _rec=$(declare -f reconcile_npm_manifest)
eval "orig_sweep${_sweep#sweep_legacy_npm}"; eval "orig_rec${_rec#reconcile_npm_manifest}"
sweep_legacy_npm() { ORDER="$ORDER sweep"; orig_sweep "$@"; }
reconcile_npm_manifest() { ORDER="$ORDER reconcile"; orig_rec "$@"; }
main
[ "$ORDER" = " sweep reconcile" ] || { echo "BAD ORDER:$ORDER" >&2; exit 1; }
DRIVE
  mkdir -p "$BATS_TEST_TMPDIR/ehome"
  run bash "$BATS_TEST_TMPDIR/drive.sh" "$BATS_TEST_TMPDIR/m.sh" \
    "$BATS_TEST_TMPDIR/manifest" "$BATS_TEST_TMPDIR/ehome"
  assert_success
  assert_output --partial "[mise] done"
}

# Regression guard for the "agents can't run python" class of bug: Homebrew's
# python3 is PEP-668 locked, so a mise-managed python is what keeps `python3` +
# `pip install` working for ad-hoc scripts (e.g. throwaway validators). Dropping
# any runtime here silently breaks a fresh machine while the suite stays green,
# so lock the whole set explicitly.
@test "mise: provisions the runtimes agents assume (incl. writable python3+pip)" {
  run cat "$SRC_DIR/dot_config/mise/config.toml"
  assert_success
  for tool in node pnpm ruby java python; do
    assert_output --partial "$tool ="
  done
}
# The desired-set predicate is written twice, in two files that never see each other:
# the conf.d fragment decides what mise installs, npm_desired_rows decides what the
# manifest records. Drift means mise installs a CLI the manifest never adopts, or the
# manifest adopts one mise never installed, with nothing else failing.
@test "mise: the conf.d fragment and 30-mise agree on the desired npm set" {
  local fx
  for fx in full.toml minimal.toml ai-assistants-off.toml rn-off.toml; do
    render_to_file "$NPM_CONF" "$BATS_TEST_TMPDIR/frag" "$fx"
    sed -n 's/^"npm:\(.*\)" = "latest"$/\1/p' "$BATS_TEST_TMPDIR/frag" \
      | sort >"$BATS_TEST_TMPDIR/from_conf"
    render_to_file "$MISE" "$BATS_TEST_TMPDIR/m.sh" "$fx"
    (source "$BATS_TEST_TMPDIR/m.sh"; npm_desired_rows) \
      | cut -d'|' -f2 | sed '/^$/d' | sort >"$BATS_TEST_TMPDIR/from_script"
    diff "$BATS_TEST_TMPDIR/from_conf" "$BATS_TEST_TMPDIR/from_script" \
      || { echo "desired-set drift in $fx" >&2; return 1; }
  done
}

# Every projection reads one npm_rows table, so they cannot disagree about which
# entries exist. Lock the partition: desired and removal are disjoint halves of the
# registry set, keyed on the same pkg column.
@test "mise: the row projections partition the registry set" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/rows.sh" full.toml
  source "$BATS_TEST_TMPDIR/rows.sh"
  npm_rows() { printf '%s\n' "Wanted|wanted-pkg|1" "Dropped|dropped-pkg|0"; }

  run npm_registry_pkgs
  assert_line "wanted-pkg"
  assert_line "dropped-pkg"
  run npm_registry_names
  assert_line "Wanted"
  assert_line "Dropped"
  run npm_desired_rows
  assert_output "Wanted|wanted-pkg"
  run npm_removal_rows
  assert_output "dropped-pkg"
}

# Every sweep test stubs npm_remove_from, so nothing else locks that the real one
# targets the root it was handed. Without --prefix the sweep uninstalls from the
# ambient prefix once per root: it reports success while leaving every node-tree
# orphan in place, which is the failure it exists to prevent.
@test "mise sweep: npm_remove_from uninstalls from the ROOT it is given" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/rm.sh" full.toml
  source "$BATS_TEST_TMPDIR/rm.sh"
  mise() { printf '%s\n' "$*" >"$BATS_TEST_TMPDIR/args"; }
  npm_remove_from "/legacy/root" "vercel"
  run cat "$BATS_TEST_TMPDIR/args"
  assert_output --partial "--prefix /legacy/root"
  assert_output --partial "uninstall -g"
  assert_output --partial "vercel"
}

# The sweep failing is not the only way a legacy copy outlives its registry entry: a
# root the sweep never reached leaves one too, with no failure to record. The manifest
# row is the only handle on it either way, so the row survives on the copy, not on the
# sweep's opinion of it.
@test "mise: a deleted entry keeps its row while a legacy copy the sweep never touched remains" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/keep.sh" full.toml
  source "$BATS_TEST_TMPDIR/keep.sh"

  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  TAB="$(printf '\t')"
  printf 'Context7 CLI\tctx7\n' >"$MANIFEST"
  mkdir -p "$BATS_TEST_TMPDIR/root/lib/node_modules/ctx7"
  npm_registry_names() { :; }   # entry deleted from the registry
  npm_desired_rows() { :; }
  npm_installed() { return 1; } # mise never owned this copy, so no uninstall runs
  npm_legacy_roots() { printf '%s\n' "$BATS_TEST_TMPDIR/root"; }

  run reconcile_npm_manifest
  assert_success
  run cat "$MANIFEST"
  assert_line "Context7 CLI${TAB}ctx7"

  # Clear the copy and the row goes: nothing is left to reach.
  rm -rf "$BATS_TEST_TMPDIR/root/lib/node_modules/ctx7"
  run reconcile_npm_manifest
  assert_success
  [ ! -s "$MANIFEST" ]
}

# npm_legacy_copy answers "is there still something to remove", so anything it says yes
# to keeps a manifest row alive. Two names must always be no: an empty pkg (a tab-less
# manifest row parses to one, and lib/node_modules/ itself always exists, so the row
# would be immortal), and node's bundled packages, which sweep_legacy_npm is forbidden
# to remove — a yes there is a retry that can never succeed.
@test "mise: npm_legacy_copy says no to an empty pkg and to node's bundled packages" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/copy.sh" full.toml
  source "$BATS_TEST_TMPDIR/copy.sh"

  mkdir -p "$BATS_TEST_TMPDIR/root/lib/node_modules/npm" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/corepack" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/vercel"
  npm_legacy_roots() { printf '%s\n' "$BATS_TEST_TMPDIR/root"; }

  run npm_legacy_copy "vercel"
  assert_success
  run npm_legacy_copy ""
  assert_failure
  run npm_legacy_copy "npm"
  assert_failure
  run npm_legacy_copy "corepack"
  assert_failure
}

# A manifest row with no tab parses as name-only. Without a pkg guard the delete-path
# re-emits it every run, so a malformed row never leaves the manifest. sweep_legacy_npm
# already refuses such a row through `cut -s`; reconcile has to agree.
@test "mise: a malformed manifest row is dropped, not carried forever" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/bad.sh" full.toml
  source "$BATS_TEST_TMPDIR/bad.sh"

  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  printf 'fallow\n' >"$MANIFEST"
  npm_registry_names() { :; }
  npm_desired_rows() { :; }
  npm_legacy_roots() { :; }
  # Reality says yes to everything, so an unguarded empty pkg reaches the uninstall.
  npm_installed() { printf 'installed:%s\n' "$1" >>"$BATS_TEST_TMPDIR/calls"; return 0; }
  npm_remove() { printf 'remove:%s\n' "$1" >>"$BATS_TEST_TMPDIR/calls"; return 0; }
  : >"$BATS_TEST_TMPDIR/calls"

  run reconcile_npm_manifest
  assert_success
  [ ! -s "$MANIFEST" ]
  # `mise uninstall --all "npm:"` is a real command with an empty tool id. The row must
  # never get that far.
  run cat "$BATS_TEST_TMPDIR/calls"
  refute_output --partial "remove:"
  refute_output --partial "installed:"
}
