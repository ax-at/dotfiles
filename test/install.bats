#!/usr/bin/env bats
# The `install` bootstrap script (POSIX sh, not a template). shellcheck/shfmt
# cover its syntax via `make lint`; these tests lock behavioral invariants that
# linting can't see.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

# Regression guard for the idempotency bug: `chezmoi init --apply` only CLONES
# an absent source dir — it never pulls an already-cloned one. Without an
# explicit pull first, re-running install silently re-applies the stale
# snapshot. This asserts the pull-before-init block is still present + ordered.
@test "install pulls the source repo before init --apply (idempotency)" {
  local script="$REPO_ROOT/install"
  run grep -nE 'git .*pull|git -- pull' "$script"
  assert_success

  # And the pull must come BEFORE the init --apply handoff, or it's a no-op.
  local pull_line init_line
  pull_line="$(grep -nE 'git .*pull|git -- pull' "$script" | head -1 | cut -d: -f1)"
  init_line="$(grep -nE 'init --apply' "$script" | tail -1 | cut -d: -f1)"
  [ -n "$pull_line" ] && [ -n "$init_line" ]
  [ "$pull_line" -lt "$init_line" ]
}
