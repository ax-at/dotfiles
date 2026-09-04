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
  NPM_CONF="$SRC_DIR/dot_config/mise/conf.d/10-registry-npm.toml.tmpl"
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
    # No cask *package* line is emitted into the Brewfile on linux. Anchor to the
    # line start so the backend helpers' `brew … --cask "$2"` shell code (which
    # renders on every OS) isn't mistaken for a cask entry.
    refute_line --regexp '^cask "'
  fi
}

@test "packages: minimal profile drops optional formulae" {
  full_count="$(render "$PKGS" full.toml | grep -c '^brew ')"
  min_count="$(render "$PKGS" minimal.toml | grep -c '^brew ')"
  [ "$min_count" -lt "$full_count" ]
}

# Regression guard for the tap-trust bootstrap failure: registry entries whose
# pkg is a full `owner/tap/formula` path (e.g. hunk in modem-dev/tap) abort
# `brew bundle` non-interactively unless we opt into trusting the tap. If this
# env var is dropped, a fresh-machine install breaks again — but every other
# test still passes, so this locks it explicitly.
@test "packages: brew bundle opts into third-party tap trust" {
  run render "$PKGS" full.toml
  assert_success
  # The trigger: a curated tap-path formula must actually reach the Brewfile...
  assert_output --partial 'brew "modem-dev/tap/hunk"'
  # ...and the bundle run must trust it, or the whole bundle aborts.
  assert_output --partial 'HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew bundle'
}

# herdr is the runtime the agent CLIs (Claude Code, Codex, opencode) live in, and
# unlike them it comes from homebrew/core rather than a curl|bash installer — so
# it must reach the *Brewfile*, not 40-ai-tools' install_one list. It shares the
# ai-tools module with those CLIs, so the gate is asserted in both directions.
@test "packages: herdr is a brew formula gated on the ai-tools module" {
  run render "$PKGS" full.toml
  assert_success
  assert_output --partial 'brew "herdr"'
  run render "$PKGS" ai-off.toml
  assert_success
  refute_output --partial 'brew "herdr"'
}

@test "packages: ai-tools off makes herdr a removal candidate" {
  render_to_file "$PKGS" "$BATS_TEST_TMPDIR/off.sh" ai-off.toml
  source "$BATS_TEST_TMPDIR/off.sh"
  run removal_rows
  assert_success
  assert_line "brew|herdr"
}

@test "packages: the test/lint toolchain is installed by the setup" {
  # These are what `make test` / `make lint` / CI depend on — a fresh machine
  # must get them so the suite is runnable after install.
  run render "$PKGS" full.toml
  assert_success
  for tool in shellcheck shfmt taplo oxfmt actionlint jq bats-core; do
    assert_output --partial "brew \"$tool\""
  done
}

# ---- module gating --------------------------------------------------------

@test "ai-tools: toggling the module changes the rendered install_one calls" {
  on="$(render "$AI" full.toml | grep -c 'install_one ')"
  off="$(render "$AI" ai-off.toml | grep -c 'install_one ')"
  [ "$off" -lt "$on" ]
}

@test "ai-assistants: toggling the module gates dayflow cask" {
  if [ "$OS" = "darwin" ]; then
    run render "$PKGS" full.toml
    assert_output --partial 'cask "dayflow"'
    run render "$PKGS" ai-assistants-off.toml
    refute_output --partial 'cask "dayflow"'
  else
    run render "$PKGS" full.toml
    refute_output --partial 'cask "dayflow"'
  fi
}

@test "ai-productivity-tools: toggling the module gates fluidvoice cask" {
  if [ "$OS" = "darwin" ]; then
    run render "$PKGS" full.toml
    assert_output --partial 'cask "fluidvoice"'
    run render "$PKGS" ai-productivity-tools-off.toml
    refute_output --partial 'cask "fluidvoice"'
  else
    run render "$PKGS" full.toml
    refute_output --partial 'cask "fluidvoice"'
  fi
}

@test "mise conf.d: desired npm CLIs render as mise npm-backend rows" {
  run render "$NPM_CONF" full.toml
  assert_success
  assert_output --partial '"npm:eas-cli" = "latest"'
  assert_output --partial '"npm:vercel" = "latest"'
  assert_output --partial '"npm:screenpipe" = "latest"'
  assert_output --partial '"npm:@chrysb/alphaclaw" = "latest"'
}

@test "mise conf.d: no row for a disabled entry or a module-off one" {
  run render "$NPM_CONF" full.toml
  assert_success
  assert_output --partial '"npm:eas-cli" = "latest"'
  refute_output --partial '"npm:ctx7"'
  refute_output --partial '"npm:@aisuite/chub"'
  refute_output --partial '"npm:@pencil.dev/cli"'
  # screenpipe's module is ai-assistants, so the module gate needs its own fixture.
  run render "$NPM_CONF" ai-assistants-off.toml
  assert_success
  refute_output --partial '"npm:screenpipe"'
  assert_output --partial '"npm:eas-cli" = "latest"'
}

# mise resolves a tool by the exact id it was declared under and never canonicalizes.
# vercel is a real short name in mise's own registry, so declaring it bare here would
# install under installs/vercel/ while 30-mise queried npm:vercel, found nothing, and
# silently no-opped every removal path. Lock the key form.
@test "mise conf.d: tools are declared by backend id, never a bare short name" {
  run render "$NPM_CONF" full.toml
  assert_success
  # Both spellings: dropping the prefix alone leaves the key quoted.
  refute_output --partial '"vercel" ='
  refute_output --partial '"eas-cli" ='
  refute_line --regexp '^[[:space:]]*vercel[[:space:]]*='
  refute_line --regexp '^[[:space:]]*eas-cli[[:space:]]*='
}

# taplo.toml excludes **/*.tmpl, so the fragment has no lint coverage at all; a stray
# unquoted key or a broken range would only surface as a mise parse error on apply.
@test "mise conf.d: the rendered fragment parses as TOML" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
  # Not one pipeline: bats leaves pipefail off, and empty input is valid TOML, so a
  # failed render would sail through.
  run render "$NPM_CONF" full.toml
  assert_success
  echo "$output" | taplo check -
}

@test "mise: npm removal goes through mise's backend, not npm" {
  run render "$MISE" full.toml
  assert_success
  assert_output --partial 'mise uninstall --all "npm:$1"'
  # Both would be the PATH-probe install predicate coming back.
  refute_output --partial 'npm install -g'
  refute_output --partial 'npm_install_if_missing'
}

# `mise ls --installed <tool>` exits 0 whether or not the tool is there, so a
# status-based predicate reports everything as installed and silently disables the
# whole removal path. Drive the real function against both shapes of output.
@test "mise: npm presence is read from output, never the exit status" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/pred.sh" full.toml
  source "$BATS_TEST_TMPDIR/pred.sh"

  mise() { return 0; }
  run npm_installed eas-cli
  assert_failure
  mise() { echo "npm:eas-cli  23.2.0  ~/.config/mise/conf.d/10-registry-npm.toml  latest"; }
  run npm_installed eas-cli
  assert_success
}

@test "mise sweep: clears registry-owned names from a legacy root, nothing else" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/sweep.sh" full.toml
  source "$BATS_TEST_TMPDIR/sweep.sh"

  mkdir -p "$BATS_TEST_TMPDIR/root/lib/node_modules/vercel" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/@old/cli" \
    "$BATS_TEST_TMPDIR/root/lib/node_modules/@openai/codex"
  MANIFEST="$BATS_TEST_TMPDIR/manifest"
  # The second row has no tab. Plain `cut -f2` prints such a line whole, which would
  # hand the sweep a name nothing in the registry or the manifest ever claimed.
  printf 'Old\t@old/cli\nfallow\n' >"$MANIFEST"
  mkdir -p "$BATS_TEST_TMPDIR/root/lib/node_modules/fallow"
  : >"$BATS_TEST_TMPDIR/calls"
  # The stubs spell the paths out rather than closing over a variable: bash scopes
  # dynamically, so a name the caller also declares `local` resolves to the caller's
  # empty one and the sweep silently visits nothing.
  npm_registry_pkgs() { printf '%s\n' "vercel" "ctx7"; }
  npm_legacy_roots() { printf '%s\n' "$BATS_TEST_TMPDIR/root"; }
  npm_remove_from() { printf '%s\n' "$2" >>"$BATS_TEST_TMPDIR/calls"; }

  run sweep_legacy_npm
  assert_success
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "vercel"        # registry-owned and present
  assert_line "@old/cli"      # orphan of a deleted entry, reachable via the manifest
  refute_line "ctx7"          # registry-owned but not in this root
  refute_line "@openai/codex" # hand-installed: outside the union, unreachable
  refute_line "fallow"        # a malformed manifest row must not widen the union
}

# An unpinned `npm i -g` lands in whichever node tree was active, so missing one tree
# means the sweep silently leaves a shadowing copy behind. The prefix literal itself is
# locked by the zprofile agreement test below; main() is what assigns it in a real run.
@test "mise sweep: legacy roots are the pinned prefix plus every mise node tree" {
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/roots.sh" full.toml
  source "$BATS_TEST_TMPDIR/roots.sh"

  HOME="$BATS_TEST_TMPDIR/home"
  NPM_CONFIG_PREFIX="$HOME/.local/share/npm-global"
  local installs="$HOME/.local/share/mise/installs/node"
  mkdir -p "$installs/22.22.2/lib/node_modules" "$installs/24.19.0/lib/node_modules" \
    "$installs/20.10.0"

  run npm_legacy_roots
  assert_success
  assert_line "$NPM_CONFIG_PREFIX"
  assert_line "$installs/22.22.2"
  assert_line "$installs/24.19.0"
  refute_line "$installs/20.10.0" # never held a global install
}

# Regression guard for the "agents can't run python" class of bug: Homebrew's
# python3 is PEP-668 locked, so a mise-managed python is what keeps `python3` +
# `pip install` working for ad-hoc scripts (e.g. throwaway validators). Dropping
# any runtime here silently breaks a fresh machine while the suite stays green,
# so lock the whole set explicitly.
@test "mise: provisions the runtimes agents assume (incl. writable python3+pip)" {
  run cat "$SRC_DIR/dot_config/mise/config.toml"
  assert_success
  for tool in node pnpm ruby java python; do
    assert_output --partial "$tool ="
  done
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

@test "zshrc: hunk overrides the git-diff aliases with their exact flags" {
  run render "$SRC_DIR/dot_zshrc.tmpl" full.toml
  assert_success
  # Guarded so a machine without hunk falls back to plain `git diff`.
  assert_output --partial 'if command -v hunk >/dev/null 2>&1; then'
  # Each alias keeps the meaning of its original OMZ flags.
  assert_output --partial "alias gd='hunk diff'"
  assert_output --partial "alias gds='hunk diff --staged'"
  assert_output --partial "alias gdca='hunk diff --cached'"
  assert_output --partial "alias gdup='hunk diff @{upstream}'"
  # hunk has no --word-diff, so those aliases must NOT be pointed at it.
  refute_output --partial "alias gdw='hunk"
  refute_output --partial "alias gdcw='hunk"
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
  # Exact built-in name; validity (that it actually resolves) is covered by
  # test/ghostty_theme.bats.
  assert_output --partial 'theme = "Catppuccin Mocha"'
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

# Regression guard for the "pass-cli / claude not installed" class of bug: the
# script-method installers drop their binaries in ~/.local/bin, so that dir MUST
# be on PATH or a fresh shell can't see them even though they're installed. One
# unconditional line covers every such CLI (pass-cli, claude, and future ones).
@test "zprofile: ~/.local/bin is on PATH for script-installed CLIs (pass-cli, claude)" {
  run render "$SRC_DIR/dot_zprofile.tmpl" full.toml
  assert_success
  assert_output --partial 'export PATH="$HOME/.local/bin:$PATH"'
}

# The npm global prefix is a literal in two files that never see each other, and
# nothing at runtime forces them to agree. Extract both and compare, so neither
# can be edited alone.
@test "npm prefix: zprofile and 30-mise pin the same NPM_CONFIG_PREFIX" {
  render_to_file "$SRC_DIR/dot_zprofile.tmpl" "$BATS_TEST_TMPDIR/zprofile" full.toml
  render_to_file "$MISE" "$BATS_TEST_TMPDIR/mise.sh" full.toml
  npm_prefix_of() { sed -n 's/.*NPM_CONFIG_PREFIX="\([^"]*\)".*/\1/p' "$1" | head -1; }

  local from_shell from_script
  from_shell="$(npm_prefix_of "$BATS_TEST_TMPDIR/zprofile")"
  from_script="$(npm_prefix_of "$BATS_TEST_TMPDIR/mise.sh")"
  # Non-empty, or two missing exports would compare equal and pass vacuously.
  [ -n "$from_shell" ]
  assert_equal "$from_shell" "$from_script"
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
  # Isolate HOME + XDG so chezmoi can't read a real ~/.config/chezmoi/chezmoi.toml:
  # promptStringOnce/promptBoolOnce prefer already-persisted values over the
  # --prompt* overrides, so on a provisioned machine the dev's identity and
  # module toggles would leak into this render and fail the assertions below.
  local h="$BATS_TEST_TMPDIR/init-home"
  mkdir -p "$h"
  run env HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$h/.local/share" \
    "$CHEZMOI_BIN" execute-template --init --no-tty --source "$SRC_DIR" \
    --promptString "Git name for WORK repos=CI" \
    --promptString "Git email for WORK repos (e.g. you@company.com)=ci@example.com" \
    --promptString "Git name for PERSONAL repos=CI" \
    --promptString "Git email for PERSONAL repos=ci@example.com" \
    --promptString "GitHub username=ci" \
    --promptBool "Install the React Native / Expo native toolchain=false" \
    --promptBool "Install AI coding tools (Claude Code, Codex, etc.)=true" \
    --promptBool "Install AI assistants (e.g. screenpipe, Dayflow)=true" \
    --promptBool "Install AI productivity tools (e.g. FluidVoice)=true" \
    --promptBool "Install nanoclaw self-hosted agent host=false" \
    --promptBool "Install alphaclaw (OpenClaw setup UI + gateway manager)=false" \
    --promptBool "Install the Ubuntu/Linux-feel layer (Karabiner, LinearMouse)=true" \
    < "$SRC_DIR/.chezmoi.toml.tmpl"
  assert_success
  assert_output --partial 'react-native          = false'
  assert_output --partial 'ai-tools              = true'
  assert_output --partial 'ai-assistants         = true'
  assert_output --partial 'ai-productivity-tools = true'
}

# ---- theme coupling -------------------------------------------------------

# Ghostty is the theme source of truth (test/ghostty_theme.bats validates the
# name against the app itself); hunk and herdr are configured to match it. This
# guards the coupling that both of those configs only note in a comment: change
# Ghostty's theme and this fails until the followers are updated too.
@test "theme: hunk and herdr configs track Ghostty's Catppuccin Mocha" {
  run render "$SRC_DIR/dot_config/ghostty/config.tmpl" full.toml
  assert_success
  assert_output --partial 'theme = "Catppuccin Mocha"'
  # hunk uses the hyphenated built-in id, herdr the bare family name (its
  # Mocha variant) — both are the dark Catppuccin, spelled per each tool.
  run cat "$SRC_DIR/dot_config/hunk/config.toml"
  assert_success
  assert_output --partial 'theme = "catppuccin-mocha"'
  run cat "$SRC_DIR/dot_config/herdr/config.toml"
  assert_success
  assert_output --partial 'name = "catppuccin"'
}
