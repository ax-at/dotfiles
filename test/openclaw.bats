#!/usr/bin/env bats
# openclaw uninstall recipe — what reconcile (40-ai-tools, method=script) runs when
# the openclaw module is turned off or its block is deleted.
#
# openclaw installs via install-cli.sh to ~/.local/bin/openclaw and keeps its
# state/creds in ~/.openclaw. Its uninstall is DELIBERATELY partial + reversible:
# it stops the Gateway service (`openclaw uninstall --service`) and removes the CLI
# wrapper, but PRESERVES ~/.openclaw and the workspace. `openclaw uninstall` never
# removes the CLI itself (upstream docs), so the recipe rm's the wrapper; and it
# must exit 0 even when openclaw is already gone, or reconcile logs a false FAILED.
#
# This evals the REAL rendered uninstall_cmd (extracted from the registry, never a
# hardcoded copy). reconcile.bats stubs `script_do_remove`, so this is the only
# place the recipe's actual behaviour is checked.
#
# SAFETY: every test that evals the recipe either shadows `openclaw` with a
# recording stub (make_stub) or narrows PATH — so the suite can never touch a real
# openclaw on the machine running the tests.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'
load 'lib/isolate'

setup() {
  isolate # throwaway $HOME under BATS_TEST_TMPDIR — eval can never touch the real ~
}

# The real recipe, as the apply scripts see it (macos table; linux is identical).
recipe() {
  local os="${1:-macos}"
  printf '%s' "{{ range .packages }}{{ if eq .name \"openclaw\" }}{{ (index . \"$os\").uninstall_cmd }}{{ end }}{{ end }}" \
    | "$CHEZMOI_BIN" execute-template --source "$SRC_DIR"
}

@test "openclaw: both OS tables define an identical, non-empty uninstall_cmd" {
  local m l
  m="$(recipe macos)"
  l="$(recipe linux)"
  [ -n "$m" ] || fail "macos uninstall_cmd is empty"
  [ "$m" = "$l" ] || fail "macos/linux uninstall_cmd differ:\n  macos=$m\n  linux=$l"
}

@test "openclaw uninstall: stops the Gateway service and removes the CLI wrapper" {
  make_stub openclaw                     # shadows any real openclaw; records the call
  mkdir -p "$HOME/.local/bin"
  : >"$HOME/.local/bin/openclaw"         # the wrapper install-cli.sh drops
  eval "$(recipe)"
  [ ! -e "$HOME/.local/bin/openclaw" ] || fail "the CLI wrapper must be removed"
  grep -qF 'openclaw uninstall --service --yes --non-interactive' "$CALLS_LOG" \
    || fail "must stop the Gateway service via --service"
}

@test "openclaw uninstall: preserves ~/.openclaw state/creds and workspace (reversible)" {
  make_stub openclaw
  mkdir -p "$HOME/.local/bin" "$HOME/.openclaw/workspace"
  : >"$HOME/.local/bin/openclaw"
  printf '{"onboarded":true}\n' >"$HOME/.openclaw/openclaw.json" # creds/config
  echo notes >"$HOME/.openclaw/workspace/todo.md"
  eval "$(recipe)"
  [ -f "$HOME/.openclaw/openclaw.json" ] || fail "credentials/config must be preserved"
  [ -f "$HOME/.openclaw/workspace/todo.md" ] || fail "workspace must be preserved"
}

@test "openclaw uninstall: never removes ~/.openclaw via --state/--all" {
  # Static guard against a future edit widening the scope: --state or --all would
  # `rm -rf ~/.openclaw` (creds + workspace). The recipe must stop only the service.
  local r
  r="$(recipe)"
  [[ "$r" != *"--state"* ]] || fail "recipe must not pass --state (would rm -rf ~/.openclaw)"
  [[ "$r" != *"--all"* ]] || fail "recipe must not pass --all (would rm -rf ~/.openclaw + workspace)"
  [[ "$r" == *"--service"* ]] || fail "recipe should stop the Gateway service via --service"
}

@test "openclaw uninstall: exits 0 and is a no-op when the CLI is already gone" {
  local r
  r="$(recipe)"
  # openclaw lives in ~/.local/bin or a brew/npm prefix — none of these dirs — so a
  # real openclaw can never be reached; only coreutils resolve.
  PATH="$MOCKBIN:/usr/bin:/bin"
  run bash -c "$r"
  [ "$status" -eq 0 ] || fail "recipe must exit 0 when openclaw is absent (else reconcile logs a false FAILED remove)"
  ! grep -qF 'openclaw uninstall' "$CALLS_LOG" 2>/dev/null \
    || fail "must not call openclaw uninstall when the CLI is absent"
}

@test "openclaw uninstall: fails safe with a spaced \$HOME (quoted paths, exact wrapper only)" {
  make_stub openclaw
  local r h="$BATS_TEST_TMPDIR/a b" # spaced HOME would word-split unquoted paths
  r="$(recipe)"
  mkdir -p "$h/.local/bin" "$h/.openclaw"
  : >"$h/.local/bin/openclaw"
  : >"$h/.openclaw/openclaw.json"
  ( export HOME="$h"; eval "$r" )
  [ ! -e "$h/.local/bin/openclaw" ] || fail "quoted \$HOME must let rm target the exact wrapper"
  [ -f "$h/.openclaw/openclaw.json" ] || fail "spaced \$HOME must not disturb ~/.openclaw"
}
