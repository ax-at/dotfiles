#!/usr/bin/env bats
# Agent-skills data + reconcile logic.
#   1. skills.toml structure (taplo schema) + cross-ref invariants (jq).
#   2. run_onchange_after_65-agent-skills reconcile(): render the script, source
#      it (main() is skipped by the BASH_SOURCE guard), model installed reality in
#      a fake WORLD file, stub the CLI layer, and drive the batched add/remove
#      diff -- no real npx runs.

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

# world_apply CMD ARGS... — mutate the fake WORLD (installed reality) the way the
# real CLI would: `add <repo> -s <skills> -a <agents>` inserts the skill×agent
# grid; `remove <skills> -a <agent>` deletes those pairs. Lets one stub back both
# installed_pairs (reads WORLD) and run_npx (writes WORLD), so CALLS and MANIFEST
# assertions stay consistent across reconcile's two reality reads.
world_apply() {
  local cmd="$1"
  shift
  local mode skills="" agents="" agent="" repo="" tok
  if [ "$cmd" = "add" ]; then
    repo="$1"
    shift
    mode=""
    for tok in "$@"; do
      case "$tok" in
        -s) mode=s ;; -a) mode=a ;; -g | -y) mode="" ;;
        *) [ "$mode" = s ] && skills="$skills $tok"; [ "$mode" = a ] && agents="$agents $tok" ;;
      esac
    done
    local sk ag
    for sk in $skills; do for ag in $agents; do printf '%s\t%s\n' "$ag" "$sk" >>"$WORLD"; done; done
  elif [ "$cmd" = "remove" ]; then
    mode=s
    for tok in "$@"; do
      case "$tok" in
        -s) mode=s ;; -a) mode=a ;; -g | -y) mode="" ;;
        *) [ "$mode" = s ] && skills="$skills $tok"; [ "$mode" = a ] && agent="$tok" ;;
      esac
    done
    local sk
    for sk in $skills; do
      grep -vF "$agent	$sk" "$WORLD" >"$WORLD.t" 2>/dev/null || true
      mv "$WORLD.t" "$WORLD" 2>/dev/null || :
    done
  fi
}

setup() {
  render_to_file "$(script_tmpl 65-agent-skills)" "$BATS_TEST_TMPDIR/skills.sh" full.toml
  source "$BATS_TEST_TMPDIR/skills.sh"
  MANIFEST="$BATS_TEST_TMPDIR/applied"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  WORLD="$BATS_TEST_TMPDIR/world" # installed reality
  TAB="$(printf '\t')"
  : >"$CALLS"
  : >"$WORLD"
  : >"$MANIFEST"
  # Reality reader backed by the fake WORLD (overrides the real jq-based one).
  installed_pairs() { grep -v '^$' "$WORLD" 2>/dev/null | sort -u || true; }
  # Default CLI stub: log every call and mutate WORLD. Tests may redefine run_npx
  # in their body to inject failures (calling world_apply for the success path).
  run_npx() {
    echo "$*" >>"$CALLS"
    world_apply "$@"
  }
}

@test "reconcile: one batched add per touched repo; present repo not re-added; stale removed" {
  desired_triples() {
    printf '%s\n' \
      "claude-code${TAB}alpha${TAB}own/repoA" \
      "pi${TAB}alpha${TAB}own/repoA" \
      "claude-code${TAB}beta${TAB}own/repoA" \
      "pi${TAB}beta${TAB}own/repoA" \
      "claude-code${TAB}gamma${TAB}own/repoB" \
      "claude-code${TAB}zeta${TAB}own/repoC"
  }
  # Reality: repoA's alpha@claude-code and repoC's zeta@claude-code already there.
  printf '%s\n' "claude-code${TAB}alpha" "claude-code${TAB}zeta" >"$WORLD"
  # Manifest: alpha (ours, present) + stale delta@universal (ours, undesired).
  printf '%s\n' "claude-code${TAB}alpha" "universal${TAB}delta" >"$MANIFEST"

  run reconcile
  assert_success

  # repoA and repoB each get ONE batched add (skills+agents sorted). repoC is
  # fully installed -> not re-added.
  grep -qxF "add own/repoA -s alpha beta -a claude-code pi -g -y" "$CALLS"
  grep -qxF "add own/repoB -s gamma -a claude-code -g -y" "$CALLS"
  ! grep -q 'add own/repoC' "$CALLS"
  # stale delta removed (batched per agent).
  grep -qxF "remove delta -g -a universal -y" "$CALLS"

  # Manifest ends as exactly the desired set; delta gone.
  run cat "$MANIFEST"
  assert_line "claude-code${TAB}alpha"
  assert_line "claude-code${TAB}beta"
  assert_line "pi${TAB}alpha"
  assert_line "pi${TAB}beta"
  assert_line "claude-code${TAB}gamma"
  assert_line "claude-code${TAB}zeta"
  refute_line --partial "delta"
}

@test "reconcile: set -e safe with nothing stale; rebuilds manifest + prints summary (regression)" {
  # Regression for the crash where reconcile ran under main()'s `set -euo pipefail`
  # and aborted at an empty-set command substitution BEFORE rebuilding the manifest
  # or printing a summary. Here nothing is stale (empty manifest) and one repo is
  # missing -- the run must complete, install, rebuild the manifest, and summarize.
  desired_triples() { printf '%s\n' "claude-code${TAB}alpha${TAB}own/repoA"; }
  : >"$MANIFEST" # empty manifest -> empty stale set (the trigger)
  : >"$WORLD"    # alpha missing -> gets added

  # Run reconcile with the same strict flags main() uses.
  strict_reconcile() { set -euo pipefail; reconcile; }
  run strict_reconcile
  assert_success # would exit 1 before the fix
  assert_output --partial "[agent-skills] summary:"

  # It reached the ADD and the manifest REBUILD (both downstream of the old crash).
  grep -qxF "add own/repoA -s alpha -a claude-code -g -y" "$CALLS"
  run cat "$MANIFEST"
  assert_line "claude-code${TAB}alpha"
}

@test "reconcile: set -e safe on a total no-op (all present, nothing stale)" {
  # The other empty-set path: nothing to add AND nothing to remove.
  desired_triples() { printf '%s\n' "claude-code${TAB}alpha${TAB}own/repoA"; }
  printf '%s\n' "claude-code${TAB}alpha" >"$WORLD"    # already installed
  printf '%s\n' "claude-code${TAB}alpha" >"$MANIFEST" # already tracked, desired

  strict_reconcile() { set -euo pipefail; reconcile; }
  run strict_reconcile
  assert_success
  assert_output --partial "[agent-skills] summary:"
  ! grep -q '^add ' "$CALLS"    # nothing added
  ! grep -q '^remove ' "$CALLS" # nothing removed
}

@test "reconcile: failure summary lists the failed op explicitly" {
  desired_triples() {
    printf '%s\n' \
      "claude-code${TAB}good${TAB}own/repoG" \
      "claude-code${TAB}bad${TAB}own/repoB"
  }
  run_npx() {
    echo "$*" >>"$CALLS"
    case "$*" in *repoB*) return 1 ;; esac
    world_apply "$@"
  }

  run reconcile
  assert_success
  assert_output --partial "operation(s) FAILED"
  assert_output --partial "- add own/repoB"
}

@test "reconcile: openclaw is a plain -a agent; no risk flag anywhere" {
  desired_triples() {
    printf '%s\n' \
      "claude-code${TAB}gamma${TAB}own/repo" \
      "openclaw${TAB}gamma${TAB}own/repo"
  }

  run reconcile
  assert_success

  grep -qxF "add own/repo -s gamma -a claude-code openclaw -g -y" "$CALLS"
  ! grep -q 'dangerously-accept-openclaw-risks' "$CALLS"
}

@test "reconcile: reality overrides a stale manifest (drift self-heal -> re-add)" {
  desired_triples() { printf '%s\n' "claude-code${TAB}alpha${TAB}own/repoA"; }
  # Manifest FALSELY claims alpha installed; WORLD (reality) is empty.
  printf '%s\n' "claude-code${TAB}alpha" >"$MANIFEST"

  run reconcile
  assert_success

  # Missing per reality -> re-added despite the manifest claim.
  grep -qxF "add own/repoA -s alpha -a claude-code -g -y" "$CALLS"
  run cat "$MANIFEST"
  assert_line "claude-code${TAB}alpha"
}

@test "reconcile: a hand-added skill is never removed and never tracked" {
  desired_triples() { printf '%s\n' "claude-code${TAB}alpha${TAB}own/repoA"; }
  # Reality: our alpha + a hand-added skill the user installed outside dotfiles.
  printf '%s\n' "claude-code${TAB}alpha" "claude-code${TAB}handmade" >"$WORLD"
  # Manifest only tracks alpha (handmade was never ours).
  printf '%s\n' "claude-code${TAB}alpha" >"$MANIFEST"

  run reconcile
  assert_success

  # Nothing to add (alpha present) and nothing to remove (handmade not ours).
  ! grep -q 'handmade' "$CALLS"
  run cat "$MANIFEST"
  assert_line "claude-code${TAB}alpha"
  refute_line --partial "handmade"
}

@test "reconcile: a failed add soft-fails (exit 0, excluded from manifest)" {
  desired_triples() {
    printf '%s\n' \
      "claude-code${TAB}good${TAB}own/repoG" \
      "claude-code${TAB}bad${TAB}own/repoB"
  }
  # repoB's add fails; repoG succeeds (mutates WORLD).
  run_npx() {
    echo "$*" >>"$CALLS"
    case "$*" in *repoB*) return 1 ;; esac
    world_apply "$@"
  }

  run reconcile
  assert_success # soft-fail: never aborts
  assert_output --partial "FAILED add: own/repoB"

  run cat "$MANIFEST"
  assert_line "claude-code${TAB}good" # good persisted
  refute_line "claude-code${TAB}bad"  # bad excluded (never landed)
}

@test "reconcile: a failed remove keeps the skill tracked in the manifest" {
  desired_triples() { printf '%s\n' "claude-code${TAB}keep${TAB}own/repoK"; }
  printf '%s\n' "claude-code${TAB}keep" "claude-code${TAB}drop" >"$WORLD"
  printf '%s\n' "claude-code${TAB}keep" "claude-code${TAB}drop" >"$MANIFEST"
  # Removal fails -> WORLD keeps drop -> stays tracked.
  run_npx() {
    echo "$*" >>"$CALLS"
    case "$*" in remove*) return 1 ;; esac
    world_apply "$@"
  }

  run reconcile
  assert_success
  assert_output --partial "FAILED remove: claude-code"

  run cat "$MANIFEST"
  assert_line "claude-code${TAB}keep"
  assert_line "claude-code${TAB}drop" # kept because removal failed
}

@test "installed_pairs: maps display names to slugs; universal implied by existence" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  # Restore the REAL installed_pairs (setup overrode it), stub only the CLI.
  source "$BATS_TEST_TMPDIR/skills.sh"
  TAB="$(printf '\t')"
  run_npx() {
    cat <<'JSON'
[{"name":"alpha","agents":["Claude Code","Hermes Agent"]},{"name":"beta","agents":[]}]
JSON
  }

  run installed_pairs
  assert_success
  assert_line "universal${TAB}alpha"    # implied by the entry existing
  assert_line "claude-code${TAB}alpha"
  assert_line "hermes-agent${TAB}alpha"
  assert_line "universal${TAB}beta"     # no agents[] -> universal only
  refute_line "claude-code${TAB}beta"
}

@test "SKILLS.md is up to date with skills.toml" {
  run bash -c "'$CHEZMOI_BIN' execute-template --source '$SRC_DIR' < '$REPO_ROOT/scripts/skills.md.tmpl' | diff - '$REPO_ROOT/SKILLS.md'"
  assert_success
}

@test "65-agent-skills renders to a no-op when ai-tools is off" {
  render_to_file "$(script_tmpl 65-agent-skills)" "$BATS_TEST_TMPDIR/off.sh" ai-off.toml
  run grep -c "reconcile()" "$BATS_TEST_TMPDIR/off.sh"
  assert_output "0"
}
