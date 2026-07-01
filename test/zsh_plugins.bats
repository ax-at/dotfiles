#!/usr/bin/env bats
# zsh plugin-bundle integrity.
#
# antidote resolves `ohmyzsh/ohmyzsh path:plugins/<name>` to a `source
# <name>/<name>.plugin.zsh` line in the generated ~/.zsh_plugins.zsh. If <name>
# isn't a real plugin the failure is silent at generation and then errors in
# EVERY new shell ("no such file or directory: .../<name>.plugin.zsh") — exactly
# how the pnpm + mysql entries slipped through.
#
# The core check PREFERS live GitHub validation (scripts/check-plugins-live.sh:
# official + community repos, always fresh) and FALLS BACK to a pinned Oh-My-Zsh
# snapshot when the network is unreachable or rate-limited — so the suite stays
# green offline and never flakes on a transient API error.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

PLUGINS_TXT="$SRC_DIR/dot_zsh_plugins.txt"
OMZ_SNAPSHOT="$FIXTURES_DIR/omz-plugins.txt"
LIVE_CHECK="$REPO_ROOT/scripts/check-plugins-live.sh"

# referenced_omz_plugins — the <name> from each `ohmyzsh/ohmyzsh path:plugins/<name>`
# line (ignores non-plugin OMZ paths like `path:lib/directories.zsh`).
referenced_omz_plugins() {
  grep -oE 'ohmyzsh/ohmyzsh[[:space:]]+path:plugins/[A-Za-z0-9._-]+' "$PLUGINS_TXT" \
    | sed -E 's#.*path:plugins/##'
}

# snapshot_check — offline fallback: assert every referenced OMZ plugin is in the
# committed snapshot. Returns 1 listing any that aren't.
snapshot_check() {
  local valid missing=() p
  valid="$(grep -vE '^[[:space:]]*(#|$)' "$OMZ_SNAPSHOT")"
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

@test "zsh-plugins: plugin list and OMZ snapshot fixture both exist" {
  [ -f "$PLUGINS_TXT" ]
  [ -f "$OMZ_SNAPSHOT" ]
}

@test "zsh-plugins: the guard actually has OMZ plugins to check" {
  # Guard against the parser silently returning nothing (which would make the
  # membership check vacuously pass).
  run referenced_omz_plugins
  assert_success
  assert_output --partial 'git'
}

@test "zsh-plugins: every referenced plugin resolves (live when online, snapshot offline)" {
  run bash "$LIVE_CHECK"
  case "$status" in
    0) : ;;                       # live validation passed (official + community)
    1) echo "$output" >&2; return 1 ;;   # a reference genuinely does not exist
    2)                            # offline / rate-limited / transient → snapshot
      echo "# live check inconclusive — using offline snapshot: $output" >&3
      snapshot_check ;;
    *) echo "unexpected exit $status from live check: $output" >&2; return 1 ;;
  esac
}

@test "zsh-plugins: regression — pnpm and mysql are not OMZ plugins, must stay unreferenced" {
  run referenced_omz_plugins
  refute_line 'pnpm'
  refute_line 'mysql'
}
