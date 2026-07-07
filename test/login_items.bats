#!/usr/bin/env bats
# Login-items reconcile for 75-login-items: add flagged+installed apps to the
# macOS "Open at Login" list, remove ones we previously added but no longer flag,
# never touch items we didn't create, and bail cleanly when Automation (TCC)
# access is blocked.
#
# The script is rendered, sourced (main() skipped by the BASH_SOURCE guard), its
# desired-row emitter overridden and its osascript backends stubbed to model the
# login-items list + installed apps in files — no real osascript runs.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

setup_li() {
  render_to_file "$(script_tmpl 75-login-items)" "$BATS_TEST_TMPDIR/l.sh" full.toml
  source "$BATS_TEST_TMPDIR/l.sh"
  CALLS="$BATS_TEST_TMPDIR/calls"      # "add PATH HIDDEN" / "delete NAME" lines
  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  EXISTING="$BATS_TEST_TMPDIR/existing" # login items present now, one name per line
  WORLD="$BATS_TEST_TMPDIR/world"       # installed bundles, one "X.app" per line
  : >"$CALLS"; : >"$MANIFEST"; : >"$EXISTING"; : >"$WORLD"
  li_list_names() { cat "$EXISTING"; }
  li_add() { echo "add $1 $2" >>"$CALLS"; }
  li_delete() { echo "delete $1" >>"$CALLS"; }
  resolve_bundle() { grep -qxF "$1" "$WORLD" && printf '/Applications/%s\n' "$1"; }
}

# --------------------------------------------------------- template projection
@test "rendered desired rows carry bundle|hidden, with overrides applied" {
  render_to_file "$(script_tmpl 75-login-items)" "$BATS_TEST_TMPDIR/l.sh" full.toml
  source "$BATS_TEST_TMPDIR/l.sh"
  run login_desired_rows
  assert_success
  assert_line "Raycast.app|true"        # plain true -> <name>.app, hidden
  assert_line "Proton Pass.app|true"    # spaces preserved
  assert_line "Ghostty.app|false"       # explicit bundle (name is 'ghostty') + visible
  assert_line "cmux.app|false"          # hidden=false override, bundle fallback
}

@test "turning a module off drops its apps from the desired rows" {
  render_to_file "$(script_tmpl 75-login-items)" "$BATS_TEST_TMPDIR/l.sh" linux-feel-off.toml
  source "$BATS_TEST_TMPDIR/l.sh"
  run login_desired_rows
  assert_success
  refute_output --partial "Karabiner-Elements.app" # linux-feel off
  refute_output --partial "LinearMouse.app"
  assert_line "Raycast.app|true"                   # productivity still on
}

# -------------------------------------------------------------------- add-path
@test "add: a flagged, installed app not yet present is added with its hidden flag" {
  setup_li
  login_desired_rows() { printf '%s\n' "Raycast.app|true" "Ghostty.app|false"; }
  printf '%s\n' "Raycast.app" "Ghostty.app" >"$WORLD"
  run reconcile_login_items
  assert_success
  grep -qxF "add /Applications/Raycast.app true" "$CALLS"
  grep -qxF "add /Applications/Ghostty.app false" "$CALLS"
  grep -qxF "Raycast" "$MANIFEST" # recorded as managed
  grep -qxF "Ghostty" "$MANIFEST"
}

@test "add: an app already a login item is not re-added but stays managed" {
  setup_li
  login_desired_rows() { printf '%s\n' "Raycast.app|true"; }
  printf '%s\n' "Raycast.app" >"$WORLD"
  printf '%s\n' "Raycast" >"$EXISTING" # already present
  run reconcile_login_items
  assert_success
  ! grep -q "^add" "$CALLS"
  grep -qxF "Raycast" "$MANIFEST"
}

@test "add: a failed li_add soft-fails (logged, still managed) and does not abort" {
  setup_li
  login_desired_rows() { printf '%s\n' "Raycast.app|true"; }
  printf '%s\n' "Raycast.app" >"$WORLD"
  li_add() {
    echo "add $1 $2" >>"$CALLS"
    return 1
  }
  strict() { set -euo pipefail; reconcile_login_items; } # main runs under set -e
  run strict
  assert_success
  assert_output --partial "FAILED to add Raycast"
  grep -qxF "add /Applications/Raycast.app true" "$CALLS" # attempt was made
  grep -qxF "Raycast" "$MANIFEST"                         # recorded managed before the attempt
}

@test "add: a flagged app that isn't installed is skipped, never added or removed" {
  setup_li
  login_desired_rows() { printf '%s\n' "cmux.app|false"; }
  printf '%s\n' "cmux" >"$MANIFEST" # previously managed, to prove it's not removed
  # WORLD empty -> not installed
  run reconcile_login_items
  assert_success
  assert_output --partial "skip cmux (not installed)"
  ! grep -q "^add" "$CALLS"
  ! grep -q "^delete" "$CALLS" # still flagged, so never a removal candidate
}

# ----------------------------------------------------------------- delete-path
@test "remove: a previously-managed app that is no longer flagged is deleted and dropped" {
  setup_li
  login_desired_rows() { :; }          # nothing flagged now
  printf '%s\n' "Raycast" >"$MANIFEST" # we managed it before
  printf '%s\n' "Raycast" >"$EXISTING" # still present
  run reconcile_login_items
  assert_success
  grep -qxF "delete Raycast" "$CALLS"
  ! grep -q Raycast "$MANIFEST" # dropped after successful removal
}

@test "remove: a failed li_delete keeps the item in the manifest for retry" {
  setup_li
  login_desired_rows() { :; }          # no longer flagged
  printf '%s\n' "Raycast" >"$MANIFEST" # managed before
  printf '%s\n' "Raycast" >"$EXISTING" # still present
  li_delete() {
    echo "delete $1" >>"$CALLS"
    return 1
  }
  strict() { set -euo pipefail; reconcile_login_items; }
  run strict
  assert_success
  assert_output --partial "FAILED to remove Raycast"
  grep -qxF "delete Raycast" "$CALLS"  # attempt was made
  grep -qxF "Raycast" "$MANIFEST"      # kept for a later re-fire
}

@test "no-clobber: a login item we never managed is left untouched" {
  setup_li
  login_desired_rows() { :; }
  printf '%s\n' "SomeUserApp" >"$EXISTING" # present, but never in our manifest
  run reconcile_login_items
  assert_success
  ! grep -q "^delete" "$CALLS"
}

@test "remove: a stale manifest entry already gone from the list is not deleted" {
  setup_li
  login_desired_rows() { :; }
  printf '%s\n' "Raycast" >"$MANIFEST" # managed before, but user removed it already
  # EXISTING empty -> not present anymore
  run reconcile_login_items
  assert_success
  ! grep -q "^delete" "$CALLS" # nothing to delete
  ! grep -q Raycast "$MANIFEST"
}

# --------------------------------------------------------------- consent / TCC
@test "consent: a -1743 Automation failure warns and makes no changes" {
  setup_li
  login_desired_rows() { printf '%s\n' "Raycast.app|true"; }
  printf '%s\n' "Raycast.app" >"$WORLD"
  li_list_names() {
    echo "execution error: Not authorized to send Apple events to System Events. (-1743)" >&2
    return 1
  }
  run reconcile_login_items
  assert_success
  assert_output --partial "SKIPPED"
  ! grep -q . "$CALLS" # neither add nor delete attempted
}

@test "consent: a non-TCC read failure also skips, surfacing the error" {
  setup_li
  login_desired_rows() { printf '%s\n' "Raycast.app|true"; }
  li_list_names() {
    echo "some other osascript failure" >&2
    return 1
  }
  run reconcile_login_items
  assert_success
  assert_output --partial "SKIPPED"
  assert_output --partial "some other osascript failure"
  ! grep -q . "$CALLS"
}

# ------------------------------------------------------------ set -e / lifecycle
@test "reconcile is set -e safe on a total no-op" {
  setup_li
  login_desired_rows() { :; }
  strict() { set -euo pipefail; reconcile_login_items; }
  run strict
  assert_success
}

@test "reconcile is set -e safe when a flagged app is not installed" {
  setup_li
  login_desired_rows() { printf '%s\n' "Notthere.app|true"; }
  # WORLD empty -> resolve_bundle returns nonzero/empty; must not abort under set -e.
  strict() { set -euo pipefail; reconcile_login_items; }
  run strict
  assert_success
  ! grep -q . "$MANIFEST"
}

# main() is what chezmoi actually executes; every test above drives a function
# directly (BASH_SOURCE guard skips main). This drives main() end-to-end with all
# backends stubbed, catching lifecycle regressions the function tests can't (e.g.
# an unbound var under set -u after main returns, or a broken uname guard).
@test "main() runs end-to-end with backends stubbed" {
  render_to_file "$(script_tmpl 75-login-items)" "$BATS_TEST_TMPDIR/l.sh" full.toml
  cat >"$BATS_TEST_TMPDIR/drive.sh" <<'DRIVE'
source "$1"
MANIFEST="$2"                 # top-level assignment in the script; re-point after source
li_list_names() { :; }
li_add() { :; }
li_delete() { :; }
resolve_bundle() { :; }
login_desired_rows() { :; }
main
DRIVE
  run bash "$BATS_TEST_TMPDIR/drive.sh" "$BATS_TEST_TMPDIR/l.sh" "$BATS_TEST_TMPDIR/manifest"
  assert_success
  refute_output --partial "unbound variable"
}
