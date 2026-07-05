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

@test "install_into: installs missing extensions in one batched editor CLI call" {
  CODE_INSTALLED_EXTS="" run install_into code "VS Code"
  assert_success
  # All missing extensions ship in a single `code` invocation, so match the
  # flag anywhere on the install line (only the first ext follows `code`).
  grep '^code ' "$CALLS_LOG" | grep -qF -- '--install-extension oxc.oxc-vscode'
}

@test "install_into: skips an already-installed extension" {
  export CODE_INSTALLED_EXTS="oxc.oxc-vscode"
  run install_into code "VS Code"
  assert_success
  assert_output --partial '✓ oxc.oxc-vscode'
  # oxc was already present, so it must not appear in the batched install call.
  ! grep '^code ' "$CALLS_LOG" | grep -qF -- '--install-extension oxc.oxc-vscode'
}

@test "install_into: skips entirely when the editor is not on PATH" {
  # isolate() only PREPENDS $MOCKBIN, so removing the stub still leaves a real
  # `code` (e.g. /opt/homebrew/bin/code) resolvable on a machine with VS Code
  # installed. Drop the extra PATH dirs for this call so the editor is genuinely
  # absent; /usr/bin:/bin keep coreutils available, then PATH is restored.
  remove_stub code
  local saved_path="$PATH"
  PATH="$MOCKBIN:/usr/bin:/bin"
  run install_into code "VS Code"
  PATH="$saved_path"
  assert_success
  assert_output --partial 'not on PATH'
  [ ! -s "$CALLS_LOG" ] || ! grep -q 'code --install-extension' "$CALLS_LOG"
}

@test "install_into: installs the Pencil extension into Antigravity IDE via agy-ide" {
  # Antigravity IDE is a VS Code fork whose CLI is `agy-ide` (Open VSX gallery).
  # Same shared list, same code path as code/cursor.
  CODE_INSTALLED_EXTS="" run install_into agy-ide "Antigravity IDE"
  assert_success
  grep '^agy-ide ' "$CALLS_LOG" | grep -qF -- '--install-extension highagency.pencildev'
}

@test "install_into: skips Antigravity IDE entirely when agy-ide is not on PATH" {
  remove_stub agy-ide
  local saved_path="$PATH"
  PATH="$MOCKBIN:/usr/bin:/bin"
  run install_into agy-ide "Antigravity IDE"
  PATH="$saved_path"
  assert_success
  assert_output --partial 'not on PATH'
  [ ! -s "$CALLS_LOG" ] || ! grep -q 'agy-ide --install-extension' "$CALLS_LOG"
}

# ---- npm_install_if_missing (30-mise) -------------------------------------

@test "npm_install_if_missing: installs when check fails" {
  # isolate() only PREPENDS $MOCKBIN, so a real globally-installed `vercel`
  # (e.g. mise's ~/.local/share/mise/installs/node/.../bin/vercel) still resolves
  # and would make the check SUCCEED, skipping the install. Narrow PATH so the
  # CLI is genuinely absent; $MOCKBIN stays first so the `mise` stub still records.
  local saved_path="$PATH"
  PATH="$MOCKBIN:/usr/bin:/bin"
  npm_install_if_missing "vercel" "vercel --version"   # vercel absent -> check fails
  PATH="$saved_path"
  grep -q 'mise exec node -- npm install -g vercel' "$CALLS_LOG"
}

@test "npm_install_if_missing: skips when check succeeds" {
  make_stub vercel   # now 'vercel --version' succeeds
  npm_install_if_missing "vercel" "vercel --version"
  ! grep -q 'npm install -g vercel' "$CALLS_LOG"
}
