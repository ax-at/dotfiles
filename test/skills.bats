#!/usr/bin/env bats
# Agent-skills data + reconcile logic.
#   1. skills.toml structure (taplo schema) + cross-ref invariants (jq).
#   2. run_onchange_after_45-agent-skills reconcile(): render the script, source
#      it (main() is skipped by the BASH_SOURCE guard), stub the CLI layer, and
#      drive the add/remove diff against a fake manifest -- no real npx runs.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

SKILLS="$SRC_DIR/.chezmoidata/skills.toml"
SCHEMA="$REPO_ROOT/test/lib/skills.schema.json"

# ---- data integrity -------------------------------------------------------

@test "skills.toml matches the JSON schema (taplo)" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
  run taplo check --schema "file://$SCHEMA" "$SKILLS"
  assert_success
}

@test "skills cross-references are valid (agent slugs, dup names, repo shape)" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  run bash "$REPO_ROOT/test/lib/check-skills-crossrefs.sh"
  assert_success
  assert_output --partial "skills invariants OK"
}

# ---- reconcile() branch logic ---------------------------------------------

# Source the rendered script and point the manifest at a temp file. Tests then
# override desired_pairs / run_npx to inject a small, deterministic world.
setup() {
  render_to_file "$(script_tmpl 45-agent-skills)" "$BATS_TEST_TMPDIR/skills.sh" full.toml
  source "$BATS_TEST_TMPDIR/skills.sh"
  MANIFEST="$BATS_TEST_TMPDIR/applied"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$CALLS"
  # Log every CLI invocation instead of running it (exercises the real
  # skill_add/skill_remove flag logic; only the npx layer is stubbed). Defined
  # AFTER the source so it overrides the script's real run_npx. Tests may
  # redefine it again in their body to inject failures.
  run_npx() { echo "$*" >>"$CALLS"; }
}

@test "reconcile: adds missing, keeps present, removes stale" {
  desired_pairs() {
    printf '%s\n' \
      "claude-code	alpha	own/repo" \
      "pi	alpha	own/repo" \
      "claude-code	beta	own/repo2"
  }
  # alpha@claude-code already installed (keep); delta@universal stale (remove).
  printf '%s\n' "claude-code	alpha" "universal	delta" >"$MANIFEST"

  run reconcile
  assert_success

  # alpha@claude-code was NOT re-added; the two new ones were.
  ! grep -q 'add own/repo --skill alpha -g -a claude-code' "$CALLS"
  grep -q 'add own/repo --skill alpha -g -a pi' "$CALLS"
  grep -q 'add own/repo2 --skill beta -g -a claude-code' "$CALLS"
  # stale delta removed.
  grep -q 'remove delta -g -a universal' "$CALLS"

  # Manifest ends as exactly the desired set (sorted, unique), delta gone.
  run cat "$MANIFEST"
  assert_line "claude-code	alpha"
  assert_line "claude-code	beta"
  assert_line "pi	alpha"
  refute_line --partial "delta"
}

@test "reconcile: openclaw installs pass the unverified-risk flag; others don't" {
  desired_pairs() {
    printf '%s\n' \
      "openclaw	gamma	own/repo" \
      "claude-code	gamma	own/repo"
  }
  : >"$MANIFEST"

  run reconcile
  assert_success

  grep -q 'add own/repo --skill gamma -g -a openclaw -y --dangerously-accept-openclaw-risks' "$CALLS"
  grep -q 'add own/repo --skill gamma -g -a claude-code -y$' "$CALLS"
  ! grep -q 'claude-code -y --dangerously-accept-openclaw-risks' "$CALLS"
}

@test "reconcile: a failed add soft-fails (exit 0, excluded from manifest)" {
  desired_pairs() {
    printf '%s\n' \
      "claude-code	good	own/repo" \
      "claude-code	bad	own/repo"
  }
  : >"$MANIFEST"
  # Fail only the 'bad' skill's install; everything else succeeds.
  run_npx() {
    echo "$*" >>"$CALLS"
    case "$*" in *"--skill bad "*) return 1 ;; esac
    return 0
  }

  run reconcile
  assert_success                                   # soft-fail: never aborts
  assert_output --partial "FAILED add: bad"

  run cat "$MANIFEST"
  assert_line "claude-code	good"                 # good persisted
  refute_line "claude-code	bad"                  # bad excluded
}

@test "reconcile: a failed remove keeps the skill tracked in the manifest" {
  desired_pairs() { printf '%s\n' "claude-code	keep	own/repo"; }
  printf '%s\n' "claude-code	keep" "claude-code	drop" >"$MANIFEST"
  run_npx() {
    echo "$*" >>"$CALLS"
    case "$*" in "remove drop"*) return 1 ;; esac
    return 0
  }

  run reconcile
  assert_success
  assert_output --partial "FAILED remove: drop"

  run cat "$MANIFEST"
  assert_line "claude-code	keep"
  assert_line "claude-code	drop"                  # kept because removal failed
}

@test "SKILLS.md is up to date with skills.toml" {
  run bash -c "'$CHEZMOI_BIN' execute-template --source '$SRC_DIR' < '$REPO_ROOT/scripts/skills.md.tmpl' | diff - '$REPO_ROOT/SKILLS.md'"
  assert_success
}

@test "45-agent-skills renders to a no-op when ai-tools is off" {
  render_to_file "$(script_tmpl 45-agent-skills)" "$BATS_TEST_TMPDIR/off.sh" ai-off.toml
  run grep -c "reconcile()" "$BATS_TEST_TMPDIR/off.sh"
  assert_output "0"
}
