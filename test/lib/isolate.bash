# test/lib/isolate.bash
# Hermetic test environment, sourced from each suite's setup().
# Standard field practice: throwaway $HOME + a mock bin dir prepended to PATH.
# No tripwire — the side-effecting whole-scripts are never executed here; only
# the 3 extracted pure functions run, and every real binary they touch
# (code/cursor/mise/npm) is shadowed by a recording stub.

# Call once from setup(). After this, HOME and PATH are isolated to the
# per-test temp dir that bats auto-removes.
isolate() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # Neutralise anything that could reach the real user environment.
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_CACHE_HOME="$HOME/.cache"
  export SSH_AUTH_SOCK=""

  export MOCKBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCKBIN"
  export CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$CALLS_LOG"
  export PATH="$MOCKBIN:$PATH"

  # Default recording stubs for every real binary the tested functions call.
  make_stub npm
  make_stub mise # records e.g. "mise exec node -- npm install -g X"
  make_editor_stub code
  make_editor_stub cursor

  # Guard: refuse to run if isolation didn't take.
  [[ "$HOME" == "$BATS_TEST_TMPDIR"* ]] || fail "HOME not isolated: $HOME"
  [[ "$PATH" == "$MOCKBIN:"* ]] || fail "MOCKBIN not first on PATH"
}

# make_stub NAME [BODY]
# Creates an executable that records "NAME <args>" to CALLS_LOG, runs the
# optional BODY snippet, then exits 0. BODY is an ARGUMENT (never read from
# stdin) so a bodyless stub can't block on an inherited stdin/TTY.
make_stub() {
  local name="$1" body="${2:-}" path="$MOCKBIN/$1"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "printf '%s %s\\n' \"$name\" \"\$*\" >> \"\$CALLS_LOG\""
    [ -n "$body" ] && printf '%s\n' "$body"
    printf '%s\n' 'exit 0'
  } >"$path"
  chmod +x "$path"
}

# An editor stub (code/cursor): records calls, and on --list-extensions prints
# the newline-separated list in CODE_INSTALLED_EXTS (default: none installed).
make_editor_stub() {
  # Single quotes are intentional: the body is written verbatim into the stub
  # and CODE_INSTALLED_EXTS is expanded when the stub runs, not now.
  # shellcheck disable=SC2016
  make_stub "$1" 'case "${1:-}" in --list-extensions) printf "%s\n" ${CODE_INSTALLED_EXTS:-} ;; esac'
}

# remove_stub NAME — simulate a binary that is NOT on PATH.
remove_stub() { rm -f "$MOCKBIN/$1"; }

# calls — dump the recorded invocations.
calls() { cat "$CALLS_LOG" 2>/dev/null || true; }
