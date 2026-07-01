#!/usr/bin/env bats
# zsh plugin-bundle integrity.
#
# antidote resolves `ohmyzsh/ohmyzsh path:plugins/<name>` to a `source
# <name>/<name>.plugin.zsh` line in the generated ~/.zsh_plugins.zsh. If <name>
# isn't a real Oh-My-Zsh plugin the failure is silent at generation time and
# then errors in EVERY new shell ("no such file or directory: .../<name>.plugin.zsh").
# That's exactly how the pnpm + mysql entries slipped through. This guard checks
# every referenced OMZ plugin against a committed snapshot of the real OMZ plugin
# set, so the mistake fails CI (offline) instead of the next terminal.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

PLUGINS_TXT="$SRC_DIR/dot_zsh_plugins.txt"
OMZ_SNAPSHOT="$FIXTURES_DIR/omz-plugins.txt"

# referenced_omz_plugins — the <name> from each `ohmyzsh/ohmyzsh path:plugins/<name>`
# line (ignores non-plugin OMZ paths like `path:lib/directories.zsh`).
referenced_omz_plugins() {
  grep -oE 'ohmyzsh/ohmyzsh[[:space:]]+path:plugins/[A-Za-z0-9._-]+' "$PLUGINS_TXT" \
    | sed -E 's#.*path:plugins/##'
}

@test "zsh-plugins: plugin list and OMZ snapshot fixture both exist" {
  [ -f "$PLUGINS_TXT" ]
  [ -f "$OMZ_SNAPSHOT" ]
}

@test "zsh-plugins: the guard actually has OMZ plugins to check" {
  # If parsing silently returns nothing the membership test below is vacuous —
  # assert we really extracted the entries so the guard can't rot into a no-op.
  run referenced_omz_plugins
  assert_success
  assert_output --partial 'git'
}

@test "zsh-plugins: every referenced OMZ plugin exists upstream (offline snapshot)" {
  local valid missing=()
  valid="$(grep -vE '^[[:space:]]*(#|$)' "$OMZ_SNAPSHOT")"
  local p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    grep -qxF "$p" <<<"$valid" || missing+=("$p")
  done < <(referenced_omz_plugins)
  if [ "${#missing[@]}" -ne 0 ]; then
    printf 'not a real Oh-My-Zsh plugin: %s\n' "${missing[@]}" >&2
    printf '(if it was added upstream after the snapshot, refresh test/fixtures/omz-plugins.txt)\n' >&2
    return 1
  fi
}

@test "zsh-plugins: regression — pnpm and mysql are not OMZ plugins, must stay unreferenced" {
  run referenced_omz_plugins
  refute_line 'pnpm'
  refute_line 'mysql'
}
