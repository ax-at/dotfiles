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
  for tool in shellcheck shfmt taplo actionlint jq; do
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

# ---- generated artifact + config template ---------------------------------

@test "TOOLS.md is up to date with the registry" {
  run bash -c "'$CHEZMOI_BIN' execute-template --source '$SRC_DIR' < '$REPO_ROOT/scripts/tools.md.tmpl' | diff - '$REPO_ROOT/TOOLS.md'"
  assert_success
}

@test "config template: init prompts map to module data" {
  run "$CHEZMOI_BIN" execute-template --init --source "$SRC_DIR" \
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
