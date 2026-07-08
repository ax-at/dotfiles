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
  # posthog declares claude/codex + a DISABLED cursor; each enabled
  # client renders a pipe-delimited row.
  assert_line "claude|posthog|posthog||"
  assert_line "codex|posthog|posthog||PostHog/ai-plugin"
  # vercel is hybrid: its native codex sub-table renders here (installed from the
  # built-in openai-curated marketplace); claude-code goes via the open backend
  # (script 67), so it does NOT render a claude row here.
  assert_line "codex|vercel|vercel||openai-curated"
  # supabase is claude-only (no codex-installable package upstream).
  assert_line "claude|supabase|supabase||"
}

@test "desired_rows omits a cursor sub-table with enabled = false" {
  render_to_file "$(script_tmpl 66-ai-plugins)" "$BATS_TEST_TMPDIR/p.sh" full.toml
  source "$BATS_TEST_TMPDIR/p.sh"
  run desired_rows
  assert_success
  # posthog's cursor is off (auto-imported) -> no cursor row, no manual step.
  refute_line --partial "cursor|posthog"
  # vercel has only a codex native sub-table here (claude-code goes via the open
  # backend, script 67); it must NOT render claude/cursor rows.
  refute_line --partial "claude|vercel"
  refute_line --partial "cursor|vercel"
  # supabase's cursor is off (auto-imported); it declares no codex sub-table.
  refute_line --partial "cursor|supabase"
  refute_line --partial "codex|supabase"
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
      "codex|posthog|posthog||PostHog/ai-plugin"
  }
  printf 'claude\tposthog\n' >"$WORLD" # claude already installed

  run reconcile
  assert_success
  grep -qxF "install codex posthog" "$CALLS"
  ! grep -q "install claude" "$CALLS" # present -> not reinstalled

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  assert_line "codex${TAB}posthog${TAB}posthog"
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
  # Reality + manifest: codex/posthog was ours but is no longer desired.
  printf 'claude\tposthog\ncodex\tposthog\n' >"$WORLD"
  printf 'claude\tposthog\tposthog\ncodex\tposthog\tposthog\n' >"$MANIFEST"

  run reconcile
  assert_success
  grep -qxF "remove codex posthog" "$CALLS"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  refute_line --partial "codex"
}

@test "reconcile: a hand-installed plugin (not in manifest) is never removed" {
  desired_rows() { printf '%s\n' "claude|posthog|posthog||"; }
  # Reality has a hand-added codex plugin the user installed outside dotfiles.
  printf 'claude\tposthog\ncodex\thandmade\n' >"$WORLD"
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
      "codex|posthog|posthog||PostHog/ai-plugin"
  }
  pm_install() {
    echo "install $1 $2" >>"$CALLS"
    case "$1" in codex) return 1 ;; esac
    printf '%s\t%s\n' "$1" "$2" >>"$WORLD"
  }

  run reconcile
  assert_success # soft-fail: never aborts
  assert_output --partial "FAILED install: posthog/codex"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog" # good persisted
  refute_line "codex${TAB}posthog${TAB}posthog" # failed one excluded
}

@test "reconcile: a failed remove keeps the plugin tracked for retry" {
  desired_rows() { printf '%s\n' "claude|posthog|posthog||"; }
  printf 'claude\tposthog\ncodex\tposthog\n' >"$WORLD"
  printf 'claude\tposthog\tposthog\ncodex\tposthog\tposthog\n' >"$MANIFEST"
  pm_uninstall() { echo "remove $1 $2" >>"$CALLS"; return 1; }

  run reconcile
  assert_success
  assert_output --partial "FAILED remove: posthog/codex"

  run cat "$MANIFEST"
  assert_line "claude${TAB}posthog${TAB}posthog"
  assert_line "codex${TAB}posthog${TAB}posthog" # kept because removal failed
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

# ---- store-fingerprint (out-of-band deletion self-heal) -------------------
# The rendered script embeds a hash of installed plugin IDENTITIES (claude's
# installed_plugins.json keys, codex config sections) so
# `run_onchange` re-runs when a plugin is deleted out-of-band. These render with a
# fabricated HOME to drive the render-time `output` digest; claude's record-file
# is the representative shape (a JSON key vanishing must flip the hash).

@test "66 drift heal: deleting a claude plugin flips the store fingerprint (content changes)" {
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/plugins"
  cat >"$HOME/.claude/plugins/installed_plugins.json" <<'JSON'
{ "version": 2, "plugins": { "demo@market": [ { "scope": "user" } ] } }
JSON
  run render_to_file "$(script_tmpl 66-ai-plugins)" "$BATS_TEST_TMPDIR/with.sh" full.toml
  assert_success
  # Same file, plugin key removed (what an uninstall does).
  printf '%s\n' '{ "version": 2, "plugins": {} }' >"$HOME/.claude/plugins/installed_plugins.json"
  run render_to_file "$(script_tmpl 66-ai-plugins)" "$BATS_TEST_TMPDIR/without.sh" full.toml
  assert_success
  run diff "$BATS_TEST_TMPDIR/with.sh" "$BATS_TEST_TMPDIR/without.sh"
  assert_failure
}

@test "66 drift heal: absent plugin records render without aborting apply (fresh machine)" {
  HOME="$BATS_TEST_TMPDIR/empty-home"
  mkdir -p "$HOME" # no ~/.claude, ~/.codex yet
  run render_to_file "$(script_tmpl 66-ai-plugins)" "$BATS_TEST_TMPDIR/fresh.sh" full.toml
  assert_success # a non-zero digest exit would abort the whole apply
  run grep -c "reconcile()" "$BATS_TEST_TMPDIR/fresh.sh"
  assert_success
}
