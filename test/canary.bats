#!/usr/bin/env bats
# Canary (non-blocking, informational): confirms the UNDOCUMENTED ability to
# override .chezmoi.os via --override-data-file still works on the installed
# chezmoi. OS coverage does NOT depend on this — the CI matrix renders each OS
# natively. This exists so a chezmoi upgrade that breaks the override fails
# loudly here instead of silently, if you ever choose to rely on it locally.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

@test "canary: --override-data-file can still fake .chezmoi.os" {
  local ov="$BATS_TEST_TMPDIR/os.toml"
  printf '[chezmoi]\nos = "linux"\n' >"$ov"
  run "$CHEZMOI_BIN" execute-template --source "$SRC_DIR" \
    --override-data-file "$ov" '{{ .chezmoi.os }}'
  assert_success
  assert_output "linux"
}
