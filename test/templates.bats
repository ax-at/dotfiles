#!/usr/bin/env bats
# Template rendering: assertion-based (field norm). OS-specific assertions run
# against the runner's NATIVE os (linux on ubuntu, darwin on macos).

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

setup() {
  PKGS="$(script_tmpl 20-packages)"
  MISE="$(script_tmpl 30-mise)"
  AI="$(script_tmpl 40-ai-tools)"
  ED="$(script_tmpl 50-editor-extensions)"
  MACOS="$(script_tmpl 70-macos-defaults)"
  OS="$([ "$(uname)" = "Darwin" ] && echo darwin || echo linux)"
  CODE_SETTINGS="$SRC_DIR/Library/Application Support/Code/User/settings.json.tmpl"
  CURSOR_SETTINGS="$SRC_DIR/Library/Application Support/Cursor/User/settings.json.tmpl"
}

# ---- Brewfile generation (20-packages) ------------------------------------

@test "packages: core brew formulae always present" {
  run render "$PKGS" full.toml
  assert_success
  assert_output --partial 'brew "git"'
  assert_output --partial 'brew "gh"'
}

@test "packages: casks appear on darwin, never on linux" {
  run render "$PKGS" full.toml
  assert_success
  if [ "$OS" = "darwin" ]; then
    assert_output --partial 'cask "ghostty"'
  else
    refute_output --partial 'cask "'
  fi
}

@test "packages: minimal profile drops optional formulae" {
  full_count="$(render "$PKGS" full.toml | grep -c '^brew ')"
  min_count="$(render "$PKGS" minimal.toml | grep -c '^brew ')"
  [ "$min_count" -lt "$full_count" ]
}

@test "packages: the test/lint toolchain is installed by the setup" {
  # These are what `make test` / `make lint` / CI depend on — a fresh machine
  # must get them so the suite is runnable after install.
  run render "$PKGS" full.toml
  assert_success
  for tool in shellcheck shfmt taplo actionlint jq bats-core; do
    assert_output --partial "brew \"$tool\""
  done
}

# ---- module gating --------------------------------------------------------

@test "ai-tools: toggling the module changes the rendered install_one calls" {
  on="$(render "$AI" full.toml | grep -c 'install_one ')"
  off="$(render "$AI" ai-off.toml | grep -c 'install_one ')"
  [ "$off" -lt "$on" ]
}

@test "mise: npm CLIs render as npm_install_if_missing calls" {
  run render "$MISE" full.toml
  assert_success
  assert_output --partial 'npm_install_if_missing '
}

@test "editors-off: main() early-exits (standalone 'exit 0')" {
  render "$ED" editors-off.toml | grep -qE '^[[:space:]]*exit 0[[:space:]]*$'
  run render "$ED" full.toml
  refute_output --regexp '^[[:space:]]*exit 0[[:space:]]*$'
}

@test "macos-defaults-off: script early-exits" {
  render "$MACOS" macos-defaults-off.toml | grep -qE '^[[:space:]]*exit 0[[:space:]]*$'
}

@test "zshrc: react-native env (ANDROID_HOME) is gated on the module" {
  run render "$SRC_DIR/dot_zshrc.tmpl" full.toml
  assert_success
  assert_output --partial 'ANDROID_HOME'
  run render "$SRC_DIR/dot_zshrc.tmpl" rn-off.toml
  assert_success
  refute_output --partial 'ANDROID_HOME'
}

# ---- OS-conditional non-script templates ----------------------------------

@test "chezmoiignore: Library/** ignored on linux only" {
  run render "$SRC_DIR/.chezmoiignore" full.toml
  assert_success
  if [ "$OS" = "linux" ]; then
    assert_output --partial 'Library/**'
  else
    refute_output --partial 'Library/**'
  fi
}

@test "gitconfig: identity substituted + work includeIf present" {
  run render "$SRC_DIR/dot_gitconfig.tmpl" full.toml
  assert_success
  assert_output --partial 'name = CI'
  assert_output --partial 'email = ci@example.com'
  assert_output --partial 'includeIf "gitdir:~/work/"'
}

@test "gitconfig-work: work identity substituted + ssh signing key" {
  # dot_gitconfig only points at this file via includeIf; this covers the file
  # the pointer resolves to. full.toml sets workName/workEmail to the CI values.
  run render "$SRC_DIR/dot_gitconfig-work.tmpl" full.toml
  assert_success
  assert_output --partial 'name = CI'
  assert_output --partial 'email = ci@example.com'
  assert_output --partial 'signingkey = ~/.ssh/id_ed25519.pub'
}

@test "ghostty config: static settings render; macos-option-as-alt is darwin-only" {
  run render "$SRC_DIR/dot_config/ghostty/config.tmpl" full.toml
  assert_success
  assert_output --partial 'font-family = "JetBrainsMono Nerd Font"'
  assert_output --partial 'theme = "catppuccin-mocha"'
  if [ "$OS" = "darwin" ]; then
    assert_output --partial 'macos-option-as-alt = true'
  else
    refute_output --partial 'macos-option-as-alt'
  fi
}

@test "chezmoiexternal: Karabiner asset is darwin-only (+ valid TOML)" {
  run render "$SRC_DIR/.chezmoiexternal.toml" full.toml
  assert_success
  if [ "$OS" = "darwin" ]; then
    assert_output --partial 'windows_shortcuts.json'
    assert_output --partial 'type = "file"'
  else
    refute_output --partial 'windows_shortcuts.json'
  fi
  # Rendered output must parse as TOML on every OS (empty is valid on linux).
  if command -v taplo >/dev/null 2>&1; then echo "$output" | taplo check -; fi
}

@test "zprofile: brew shellenv path matches the native OS" {
  run render "$SRC_DIR/dot_zprofile.tmpl" full.toml
  assert_success
  if [ "$OS" = "darwin" ]; then
    assert_output --partial '/opt/homebrew/bin/brew'
    refute_output --partial 'linuxbrew'
  else
    assert_output --partial '/home/linuxbrew/.linuxbrew/bin/brew'
    refute_output --partial '/opt/homebrew'
  fi
}

# ---- editor settings: shared partial renders valid JSON -------------------
# Code + Cursor are one-line wrappers around the .chezmoitemplates partial, so
# a broken partial (bad include, trailing comma) would ship to both editors
# silently. These lock that it renders valid JSON and stays DRY.

@test "editor settings (Code): valid JSON wired to the oxc formatter" {
  run render "$CODE_SETTINGS" full.toml
  assert_success
  assert_output --partial '"editor.defaultFormatter": "oxc.oxc-vscode"'
  if command -v jq >/dev/null 2>&1; then echo "$output" | jq empty; fi
}

@test "editor settings (Cursor): valid JSON from the same shared partial" {
  run render "$CURSOR_SETTINGS" full.toml
  assert_success
  if command -v jq >/dev/null 2>&1; then echo "$output" | jq empty; fi
}

@test "editor settings: Code and Cursor render byte-identical (one partial)" {
  render_to_file "$CODE_SETTINGS" "$BATS_TEST_TMPDIR/code.json" full.toml
  render_to_file "$CURSOR_SETTINGS" "$BATS_TEST_TMPDIR/cursor.json" full.toml
  diff "$BATS_TEST_TMPDIR/code.json" "$BATS_TEST_TMPDIR/cursor.json"
}

# ---- generated artifact + config template ---------------------------------

@test "TOOLS.md is up to date with the registry" {
  run bash -c "'$CHEZMOI_BIN' execute-template --source '$SRC_DIR' < '$REPO_ROOT/scripts/tools.md.tmpl' | diff - '$REPO_ROOT/TOOLS.md'"
  assert_success
}

@test "config template: init prompts map to module data" {
  run "$CHEZMOI_BIN" execute-template --init --no-tty --source "$SRC_DIR" \
    --promptString "Git name for WORK repos=CI" \
    --promptString "Git email for WORK repos (e.g. you@company.com)=ci@example.com" \
    --promptString "Git name for PERSONAL repos=CI" \
    --promptString "Git email for PERSONAL repos=ci@example.com" \
    --promptString "GitHub username=ci" \
    --promptBool "Install the React Native / Expo native toolchain=false" \
    --promptBool "Install AI coding tools (Claude Code, Codex, etc.)=true" \
    --promptBool "Install the Ubuntu/Linux-feel layer (Karabiner, LinearMouse)=true" \
    < "$SRC_DIR/.chezmoi.toml.tmpl"
  assert_success
  assert_output --partial 'react-native = false'
  assert_output --partial 'ai-tools     = true'
}
