#!/usr/bin/env bats
# Shell-function branch logic. Renders a script, sources it (main() is skipped
# by the BASH_SOURCE guard), then calls the pure functions against mocked
# binaries in a hermetic temp env. No side effects reach the real machine.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'
load 'lib/isolate'

setup() {
  isolate
  # Render the 3 sourceable scripts and source them.
  render_to_file "$(script_tmpl 40-ai-tools)" "$BATS_TEST_TMPDIR/ai.sh" full.toml
  render_to_file "$(script_tmpl 50-editor-extensions)" "$BATS_TEST_TMPDIR/ed.sh" full.toml
  render_to_file "$(script_tmpl 30-mise)" "$BATS_TEST_TMPDIR/mise.sh" full.toml
  source "$BATS_TEST_TMPDIR/ai.sh"
  source "$BATS_TEST_TMPDIR/ed.sh"
  source "$BATS_TEST_TMPDIR/mise.sh"
}

# ---- install_one (40-ai-tools) --------------------------------------------

@test "install_one: runs cmd only when check fails" {
  install_one "Absent" "false" "touch $BATS_TEST_TMPDIR/ran"
  [ -f "$BATS_TEST_TMPDIR/ran" ]
}

@test "install_one: skips cmd when check succeeds" {
  install_one "Present" "true" "touch $BATS_TEST_TMPDIR/ran"
  [ ! -f "$BATS_TEST_TMPDIR/ran" ]
}

# ---- install_into (50-editor-extensions) ----------------------------------

@test "install_into: installs missing extensions via the editor CLI" {
  CODE_INSTALLED_EXTS="" run install_into code "VS Code"
  assert_success
  grep -q 'code --install-extension oxc.oxc-vscode' "$CALLS_LOG"
}

@test "install_into: skips an already-installed extension" {
  export CODE_INSTALLED_EXTS="oxc.oxc-vscode"
  run install_into code "VS Code"
  assert_success
  assert_output --partial '✓ oxc.oxc-vscode'
  ! grep -q 'code --install-extension oxc.oxc-vscode' "$CALLS_LOG"
}

@test "install_into: skips entirely when the editor is not on PATH" {
  remove_stub code
  run install_into code "VS Code"
  assert_success
  assert_output --partial 'not on PATH'
  [ ! -s "$CALLS_LOG" ] || ! grep -q 'code --install-extension' "$CALLS_LOG"
}

# ---- npm_install_if_missing (30-mise) -------------------------------------

@test "npm_install_if_missing: installs when check fails" {
  npm_install_if_missing "vercel" "vercel --version"   # vercel not stubbed -> check fails
  grep -q 'mise exec node -- npm install -g vercel' "$CALLS_LOG"
}

@test "npm_install_if_missing: skips when check succeeds" {
  make_stub vercel   # now 'vercel --version' succeeds
  npm_install_if_missing "vercel" "vercel --version"
  ! grep -q 'npm install -g vercel' "$CALLS_LOG"
}
