#!/usr/bin/env bats
# nanoclaw uninstall guard — the recipe that reconcile (40-ai-tools, method=script)
# runs to remove ~/nanoclaw-v2 when the module is turned off or the block deleted.
#
# nanoclaw's clone is stateful/user-owned (.env, DBs, groups/), so its uninstall
# is NOT a blind rm: it removes the dir ONLY if it is a pristine checkout (empty
# `git status --porcelain --ignored`). This suite evals the REAL rendered
# uninstall_cmd (extracted from the registry, never a hardcoded copy) against a
# throwaway clone in each state it can be in, and proves the data-safety contract:
# every uncertainty fails to PRESERVE.
#
# reconcile.bats stubs `script_do_remove`, so it never exercises this string — this
# is the only place the guard's actual behaviour is checked.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'
load 'lib/isolate'

setup() {
  isolate # throwaway $HOME under BATS_TEST_TMPDIR — eval can never touch the real ~
  # Hermetic git identity (isolated $HOME has no gitconfig, so commits need one).
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
}

# The real guard, as the apply scripts see it (macos table; linux is identical).
guard() {
  local os="${1:-macos}"
  printf '%s' "{{ range .packages }}{{ if eq .name \"nanoclaw\" }}{{ (index . \"$os\").uninstall_cmd }}{{ end }}{{ end }}" \
    | "$CHEZMOI_BIN" execute-template --source "$SRC_DIR"
}

# A committed, clean checkout at $1 — models a fresh `git clone` (pristine).
mk_pristine() {
  mkdir -p "$1"
  git -C "$1" init -q
  echo readme >"$1/README.md"
  git -C "$1" add README.md
  git -C "$1" commit -q -m init
}

@test "nanoclaw: both OS tables define an identical, non-empty uninstall_cmd" {
  local m l
  m="$(guard macos)"
  l="$(guard linux)"
  [ -n "$m" ] || fail "macos uninstall_cmd is empty"
  [ "$m" = "$l" ] || fail "macos/linux uninstall_cmd differ:\n  macos=$m\n  linux=$l"
}

@test "nanoclaw uninstall: removes a pristine clone" {
  mk_pristine "$HOME/nanoclaw-v2"
  eval "$(guard)"
  [ ! -d "$HOME/nanoclaw-v2" ] || fail "a pristine clone should have been removed"
}

@test "nanoclaw uninstall: keeps an onboarded checkout (.env present, gitignored)" {
  mk_pristine "$HOME/nanoclaw-v2"
  echo '.env' >"$HOME/nanoclaw-v2/.gitignore"
  git -C "$HOME/nanoclaw-v2" add .gitignore
  git -C "$HOME/nanoclaw-v2" commit -q -m gitignore
  printf 'SECRET=1\n' >"$HOME/nanoclaw-v2/.env" # ignored -> only `git status --ignored` sees it
  eval "$(guard)"
  [ -d "$HOME/nanoclaw-v2" ] && [ -f "$HOME/nanoclaw-v2/.env" ] \
    || fail "an onboarded checkout (.env) must be preserved"
}

@test "nanoclaw uninstall: keeps a locally-modified checkout (no .env)" {
  mk_pristine "$HOME/nanoclaw-v2"
  echo 'my notes' >"$HOME/nanoclaw-v2/notes.txt" # untracked -> dirty
  eval "$(guard)"
  [ -d "$HOME/nanoclaw-v2" ] || fail "a locally-modified checkout must be preserved"
}

@test "nanoclaw uninstall: keeps a non-git directory (git fails -> fail safe)" {
  mkdir -p "$HOME/nanoclaw-v2"
  echo x >"$HOME/nanoclaw-v2/file"
  eval "$(guard)"
  [ -d "$HOME/nanoclaw-v2" ] || fail "a non-repo dir must be preserved when git errors"
}

@test "nanoclaw uninstall: fails safe (keeps) when \$HOME contains a space" {
  local g h="$BATS_TEST_TMPDIR/a b" # spaced HOME word-splits the unquoted paths
  g="$(guard)"
  mk_pristine "$h/nanoclaw-v2"
  ( export HOME="$h"; eval "$g" )
  [ -d "$h/nanoclaw-v2" ] \
    || fail "spaced \$HOME must fail safe: git -C word-splits -> errors -> keep, rm never runs"
}
