#!/usr/bin/env bats
# Render each .chezmoiscripts template (native OS) and shellcheck the output.
# This closes the gap where the raw .tmpl files can't be linted directly
# (Go-template syntax isn't valid shell).

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

@test "all rendered scripts pass shellcheck" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
  local failed=0
  for tmpl in "$SCRIPTS_DIR"/*.tmpl; do
    local out="$BATS_TEST_TMPDIR/$(basename "$tmpl" .tmpl).sh"
    if ! render "$tmpl" full.toml >"$out"; then
      echo "RENDER FAILED: $tmpl"; failed=1; continue
    fi
    if ! shellcheck --shell=bash "$out"; then
      echo "SHELLCHECK FAILED: $(basename "$tmpl")"; failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}
