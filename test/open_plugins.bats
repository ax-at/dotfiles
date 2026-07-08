#!/usr/bin/env bats
# "Open" plugins (the `npx plugins` backend) data + reconcile logic.
#   1. ai-plugins.toml `open` sub-tables + the desired_rows the template renders
#      from the real data (schema is covered in ai_plugins.bats).
#   2. run_onchange_after_67-open-plugins reconcile(): render the script, source
#      it (main() skipped by the BASH_SOURCE guard), model installed reality in a
#      fake WORLD file, stub the pm_* backends, and drive the add/remove diff --
#      no real CLIs run.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

# ---- data integrity -------------------------------------------------------

@test "desired_rows renders one row per (enabled plugin x enabled open target) from real data" {
  render_to_file "$(script_tmpl 67-open-plugins)" "$BATS_TEST_TMPDIR/p.sh" full.toml
  source "$BATS_TEST_TMPDIR/p.sh"
  run desired_rows
  assert_success
  # vercel declares claude-code (id defaults to name) + a DISABLED cursor.
  assert_line "vercel|claude-code|vercel/vercel-plugin|vercel"
  # cursor target is enabled = false (auto-imported from Claude) -> no row.
  refute_line --partial "|cursor|"
  # posthog/supabase have no `open` sub-table, so they never appear in this backend.
  refute_line --partial "posthog"
  refute_line --partial "supabase"
}

@test "open backend requires bun enabled in registry.toml (cross-file invariant)" {
  # run_onchange_after_67 gates every install on bun (pm_cli_present needs node +
  # bun). The `open` backend in ai-plugins.toml therefore silently depends on a
  # package in a DIFFERENT file, registry.toml, staying enabled. Nothing else
  # couples them: disable bun to slim the Brewfile and the Vercel install quietly
  # degrades to a one-line soft-skip with no failure -- exactly the regression that
  # shipped once. This guard fails `make test` instead, pointing at the fix.
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"

  local has_open bun_enabled
  has_open="$(chezmoi execute-template --source "$SRC_DIR" \
    '{{ range .plugins }}{{ if hasKey . "open" }}open{{ end }}{{ end }}')"
  bun_enabled="$(chezmoi execute-template --source "$SRC_DIR" \
    '{{ range .packages }}{{ if eq .name "bun" }}{{ .enabled }}{{ end }}{{ end }}')"

  case "$has_open" in
    *open*)
      [ "$bun_enabled" = "true" ] \
        || fail "an 'open' plugin backend is declared in ai-plugins.toml but bun is not enabled in registry.toml -- the install will soft-skip (node/bun not present)"
      ;;
  esac
}

# ---- reconcile() branch logic ---------------------------------------------

setup() {
  render_to_file "$(script_tmpl 67-open-plugins)" "$BATS_TEST_TMPDIR/p.sh" full.toml
  source "$BATS_TEST_TMPDIR/p.sh"
  MANIFEST="$BATS_TEST_TMPDIR/applied"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  WORLD="$BATS_TEST_TMPDIR/world" # installed reality: "target<TAB>id" lines
  ABSENT="" # space-separated targets whose CLI/deps are "missing"
  TAB="$(printf '\t')"
  : >"$CALLS"
  : >"$WORLD"
  : >"$MANIFEST"

  pm_cli_present() { case " $ABSENT " in *" $1 "*) return 1 ;; esac; return 0; }
  pm_is_installed() { grep -qxF "$1${TAB}$2" "$WORLD"; }
  pm_install() {
    # args: TARGET REPO ID  (ID passed for symmetry; used here to model reality)
    echo "install $1 $3" >>"$CALLS"
    printf '%s\t%s\n' "$1" "$3" >>"$WORLD"
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
      "vercel|claude-code|vercel/vercel-plugin|vercel" \
      "acme|cursor|acme/plugin|acme-plugin"
  }
  printf 'claude-code\tvercel\n' >"$WORLD" # vercel already installed

  run reconcile
  assert_success
  grep -qxF "install cursor acme-plugin" "$CALLS"
  ! grep -q "install claude-code" "$CALLS" # present -> not reinstalled

  run cat "$MANIFEST"
  assert_line "vercel${TAB}claude-code${TAB}vercel"
  assert_line "acme${TAB}cursor${TAB}acme-plugin"
}

@test "reconcile: a target whose deps/CLI are absent is skipped (not installed, not tracked)" {
  desired_rows() {
    printf '%s\n' \
      "vercel|claude-code|vercel/vercel-plugin|vercel" \
      "acme|cursor|acme/plugin|acme-plugin"
  }
  ABSENT="cursor"

  run reconcile
  assert_success
  assert_output --partial "cursor not present"
  grep -qxF "install claude-code vercel" "$CALLS"
  ! grep -q "install cursor" "$CALLS"

  run cat "$MANIFEST"
  assert_line "vercel${TAB}claude-code${TAB}vercel"
  refute_line --partial "cursor"
}

@test "reconcile: a plugin dropped from the toml is uninstalled (manifest-scoped)" {
  desired_rows() { printf '%s\n' "vercel|claude-code|vercel/vercel-plugin|vercel"; }
  # Reality + manifest: acme/cursor was ours but is no longer desired.
  printf 'claude-code\tvercel\ncursor\tacme-plugin\n' >"$WORLD"
  printf 'vercel\tclaude-code\tvercel\nacme\tcursor\tacme-plugin\n' >"$MANIFEST"

  run reconcile
  assert_success
  grep -qxF "remove cursor acme-plugin" "$CALLS"

  run cat "$MANIFEST"
  assert_line "vercel${TAB}claude-code${TAB}vercel"
  refute_line --partial "acme"
}

@test "reconcile: a hand-installed plugin (not in manifest) is never removed" {
  desired_rows() { printf '%s\n' "vercel|claude-code|vercel/vercel-plugin|vercel"; }
  # Reality has a hand-added plugin the user installed outside dotfiles.
  printf 'claude-code\tvercel\nclaude-code\thandmade\n' >"$WORLD"
  printf 'vercel\tclaude-code\tvercel\n' >"$MANIFEST" # handmade was never ours

  run reconcile
  assert_success
  ! grep -q "remove" "$CALLS"

  run cat "$MANIFEST"
  assert_line "vercel${TAB}claude-code${TAB}vercel"
  refute_line --partial "handmade"
}

@test "reconcile: a failed install soft-fails (exit 0, excluded from manifest)" {
  desired_rows() {
    printf '%s\n' \
      "vercel|claude-code|vercel/vercel-plugin|vercel" \
      "acme|cursor|acme/plugin|acme-plugin"
  }
  pm_install() {
    echo "install $1 $3" >>"$CALLS"
    case "$1" in cursor) return 1 ;; esac
    printf '%s\t%s\n' "$1" "$3" >>"$WORLD"
  }

  run reconcile
  assert_success # soft-fail: never aborts
  assert_output --partial "FAILED install: acme/cursor"

  run cat "$MANIFEST"
  assert_line "vercel${TAB}claude-code${TAB}vercel" # good persisted
  refute_line "acme${TAB}cursor${TAB}acme-plugin"   # failed one excluded
}

@test "reconcile: a failed remove keeps the plugin tracked for retry" {
  desired_rows() { printf '%s\n' "vercel|claude-code|vercel/vercel-plugin|vercel"; }
  printf 'claude-code\tvercel\ncursor\tacme-plugin\n' >"$WORLD"
  printf 'vercel\tclaude-code\tvercel\nacme\tcursor\tacme-plugin\n' >"$MANIFEST"
  pm_uninstall() { echo "remove $1 $2" >>"$CALLS"; return 1; }

  run reconcile
  assert_success
  assert_output --partial "FAILED remove: acme/cursor"

  run cat "$MANIFEST"
  assert_line "vercel${TAB}claude-code${TAB}vercel"
  assert_line "acme${TAB}cursor${TAB}acme-plugin" # kept because removal failed
}

@test "reconcile: set -e safe on a total no-op (all present, nothing stale)" {
  desired_rows() { printf '%s\n' "vercel|claude-code|vercel/vercel-plugin|vercel"; }
  printf 'claude-code\tvercel\n' >"$WORLD"
  printf 'vercel\tclaude-code\tvercel\n' >"$MANIFEST"

  strict_reconcile() { set -euo pipefail; reconcile; }
  run strict_reconcile
  assert_success
  assert_output --partial "[open-plugins] summary:"
  ! grep -q "install" "$CALLS"
  ! grep -q "remove" "$CALLS"
}

@test "reconcile: reality overrides a stale manifest (drift self-heal -> reinstall)" {
  desired_rows() { printf '%s\n' "vercel|claude-code|vercel/vercel-plugin|vercel"; }
  # Manifest falsely claims installed; WORLD (reality) is empty.
  printf 'vercel\tclaude-code\tvercel\n' >"$MANIFEST"

  run reconcile
  assert_success
  grep -qxF "install claude-code vercel" "$CALLS" # missing per reality -> reinstalled
  run cat "$MANIFEST"
  assert_line "vercel${TAB}claude-code${TAB}vercel"
}

@test "67-open-plugins renders to a no-op when ai-tools is off" {
  render_to_file "$(script_tmpl 67-open-plugins)" "$BATS_TEST_TMPDIR/off.sh" ai-off.toml
  run grep -c "reconcile()" "$BATS_TEST_TMPDIR/off.sh"
  assert_output "0"
}

# ---- store-fingerprint (out-of-band deletion self-heal) -------------------
# 67's only reconcilable open target is claude-code, whose native store is claude's
# installed_plugins.json. The rendered script embeds a hash of its plugin keys so
# `run_onchange` re-runs when an open plugin is deleted out-of-band. Rendered with
# a fabricated HOME to drive the render-time `output` digest.

@test "67 drift heal: deleting a claude-code plugin flips the store fingerprint (content changes)" {
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/plugins"
  cat >"$HOME/.claude/plugins/installed_plugins.json" <<'JSON'
{ "version": 2, "plugins": { "demo@market": [ { "scope": "user" } ] } }
JSON
  run render_to_file "$(script_tmpl 67-open-plugins)" "$BATS_TEST_TMPDIR/with.sh" full.toml
  assert_success
  printf '%s\n' '{ "version": 2, "plugins": {} }' >"$HOME/.claude/plugins/installed_plugins.json"
  run render_to_file "$(script_tmpl 67-open-plugins)" "$BATS_TEST_TMPDIR/without.sh" full.toml
  assert_success
  run diff "$BATS_TEST_TMPDIR/with.sh" "$BATS_TEST_TMPDIR/without.sh"
  assert_failure
}

@test "67 drift heal: absent claude store renders without aborting apply (fresh machine)" {
  HOME="$BATS_TEST_TMPDIR/empty-home"
  mkdir -p "$HOME" # no ~/.claude yet
  run render_to_file "$(script_tmpl 67-open-plugins)" "$BATS_TEST_TMPDIR/fresh.sh" full.toml
  assert_success # a non-zero digest exit would abort the whole apply
  run grep -c "reconcile()" "$BATS_TEST_TMPDIR/fresh.sh"
  assert_success
}
