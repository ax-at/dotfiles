#!/usr/bin/env bats
# AI-client plugins data + reconcile logic.
#   1. ai-plugins.toml structure (taplo schema) + the desired_rows the template
#      renders from the real data.
#   2. run_onchange_after_66-ai-plugins reconcile(): render the script, source it
#      (main() skipped by the BASH_SOURCE guard), model installed reality in a
#      fake WORLD file, stub the pm_* backends, and drive the add/remove diff --
#      no real CLIs run.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

PLUGINS="$SRC_DIR/.chezmoidata/ai-plugins.toml"
SCHEMA="$REPO_ROOT/test/lib/ai-plugins.schema.json"

# ---- data integrity -------------------------------------------------------

@test "ai-plugins.toml matches the JSON schema (taplo)" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
  run taplo check --schema "file://$SCHEMA" "$PLUGINS"
  assert_success
}

@test "desired_rows renders one row per (enabled plugin x client) from real data" {
  render_to_file "$(script_tmpl 66-ai-plugins)" "$BATS_TEST_TMPDIR/p.sh" full.toml
  source "$BATS_TEST_TMPDIR/p.sh"
  run desired_rows
  assert_success
  # posthog declares all four clients; each renders a pipe-delimited row.
  assert_line "claude|posthog|posthog||"
  assert_line "gemini|posthog|posthog|https://github.com/PostHog/ai-plugin|"
  assert_line "codex|posthog|posthog||PostHog/ai-plugin"
  assert_line "cursor|posthog|posthog|https://cursor.com/marketplace|"
}

# ---- reconcile() branch logic ---------------------------------------------

setup() {
  render_to_file "$(script_tmpl 66-ai-plugins)" "$BATS_TEST_TMPDIR/p.sh" full.toml
  source "$BATS_TEST_TMPDIR/p.sh"
  MANIFEST="$BATS_TEST_TMPDIR/applied"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  WORLD="$BATS_TEST_TMPDIR/world" # installed reality: "kind<TAB>id" lines
  ABSENT="" # space-separated kinds whose CLI is "missing"
  TAB="$(printf '\t')"
  : >"$CALLS"
  : >"$WORLD"
  : >"$MANIFEST"

  pm_cli_present() { case " $ABSENT " in *" $1 "*) return 1 ;; esac; return 0; }
  pm_is_installed() { grep -qxF "$1${TAB}$2" "$WORLD"; }
  pm_install() {
    echo "install $1 $2" >>"$CALLS"
    printf '%s\t%s\n' "$1" "$2" >>"$WORLD"
  }
  pm_uninstall() {
    echo "remove $1 $2" >>"$CALLS"
    grep -vxF "$1${TAB}$2" "$WORLD" >"$WORLD.t" 2>/dev/null || true
    mv "$WORLD.t" "$WORLD" 2>/dev/null || :
  }
  pm_auth_note() { :; }
}

@test "reconcile: installs missing, skips already-installed, tracks both" {
  desired_rows() {
    printf '%s\n' \
      "claude|posthog|posthog||" \
      "gemini|posthog|posthog|https://x|"
  }
  printf 'claude\tposthog\n' >"$WORLD" # claude already installed

  run reconcile
  assert_success
  grep -qxF "install gemini posthog" "$CALLS"
  ! grep -q "install claude" "$CALLS" # present -> not reinstalled

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  assert_line "gemini${TAB}posthog${TAB}posthog"
}

@test "reconcile: a client whose CLI is absent is skipped (not installed, not tracked)" {
  desired_rows() {
    printf '%s\n' \
      "claude|posthog|posthog||" \
      "codex|posthog|posthog||PostHog/ai-plugin"
  }
  ABSENT="codex"

  run reconcile
  assert_success
  assert_output --partial "codex CLI not present"
  grep -qxF "install claude posthog" "$CALLS"
  ! grep -q "install codex" "$CALLS"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  refute_line --partial "codex"
}

@test "reconcile: a plugin dropped from the toml is uninstalled (manifest-scoped)" {
  desired_rows() { printf '%s\n' "claude|posthog|posthog||"; }
  # Reality + manifest: gemini/posthog was ours but is no longer desired.
  printf 'claude\tposthog\ngemini\tposthog\n' >"$WORLD"
  printf 'claude\tposthog\tposthog\ngemini\tposthog\tposthog\n' >"$MANIFEST"

  run reconcile
  assert_success
  grep -qxF "remove gemini posthog" "$CALLS"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  refute_line --partial "gemini"
}

@test "reconcile: a hand-installed plugin (not in manifest) is never removed" {
  desired_rows() { printf '%s\n' "claude|posthog|posthog||"; }
  # Reality has a hand-added gemini plugin the user installed outside dotfiles.
  printf 'claude\tposthog\ngemini\thandmade\n' >"$WORLD"
  printf 'claude\tposthog\tposthog\n' >"$MANIFEST" # handmade was never ours

  run reconcile
  assert_success
  ! grep -q "remove" "$CALLS"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  refute_line --partial "handmade"
}

@test "reconcile: a failed install soft-fails (exit 0, excluded from manifest)" {
  desired_rows() {
    printf '%s\n' \
      "claude|posthog|posthog||" \
      "gemini|posthog|posthog|https://x|"
  }
  pm_install() {
    echo "install $1 $2" >>"$CALLS"
    case "$1" in gemini) return 1 ;; esac
    printf '%s\t%s\n' "$1" "$2" >>"$WORLD"
  }

  run reconcile
  assert_success # soft-fail: never aborts
  assert_output --partial "FAILED install: posthog/gemini"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog" # good persisted
  refute_line "gemini${TAB}posthog${TAB}posthog" # failed one excluded
}

@test "reconcile: a failed remove keeps the plugin tracked for retry" {
  desired_rows() { printf '%s\n' "claude|posthog|posthog||"; }
  printf 'claude\tposthog\ngemini\tposthog\n' >"$WORLD"
  printf 'claude\tposthog\tposthog\ngemini\tposthog\tposthog\n' >"$MANIFEST"
  pm_uninstall() { echo "remove $1 $2" >>"$CALLS"; return 1; }

  run reconcile
  assert_success
  assert_output --partial "FAILED remove: posthog/gemini"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  assert_line "gemini${TAB}posthog${TAB}posthog" # kept because removal failed
}

@test "reconcile: set -e safe on a total no-op (all present, nothing stale)" {
  desired_rows() { printf '%s\n' "claude|posthog|posthog||"; }
  printf 'claude\tposthog\n' >"$WORLD"
  printf 'claude\tposthog\tposthog\n' >"$MANIFEST"

  strict_reconcile() { set -euo pipefail; reconcile; }
  run strict_reconcile
  assert_success
  assert_output --partial "[ai-plugins] summary:"
  ! grep -q "install" "$CALLS"
  ! grep -q "remove" "$CALLS"
}

@test "reconcile: reality overrides a stale manifest (drift self-heal -> reinstall)" {
  desired_rows() { printf '%s\n' "claude|posthog|posthog||"; }
  # Manifest falsely claims installed; WORLD (reality) is empty.
  printf 'claude\tposthog\tposthog\n' >"$MANIFEST"

  run reconcile
  assert_success
  grep -qxF "install claude posthog" "$CALLS" # missing per reality -> reinstalled
  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
}

@test "66-ai-plugins renders to a no-op when ai-tools is off" {
  render_to_file "$(script_tmpl 66-ai-plugins)" "$BATS_TEST_TMPDIR/off.sh" ai-off.toml
  run grep -c "reconcile()" "$BATS_TEST_TMPDIR/off.sh"
  assert_output "0"
}
