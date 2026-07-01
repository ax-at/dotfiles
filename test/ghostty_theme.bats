#!/usr/bin/env bats
# Ghostty theme integrity.
#
# config.tmpl sets `theme = "<name>"`. If <name> doesn't resolve to a Ghostty
# built-in theme (or a user theme file we ship), the app can't find it and
# EVERY terminal launch errors with `theme "<name>" not found` — exactly how
# `catppuccin-mocha` (the wrong name for the built-in `Catppuccin Mocha`) got in.
#
# The check PREFERS live validation via `ghostty +list-themes` (the installed
# app is the source of truth for built-ins) and FALLS BACK to a committed
# snapshot of built-in names (scripts/gen-ghostty-themes.sh) when ghostty isn't
# installed — i.e. on the Tier-1/Tier-2 CI runners. So the suite gates PRs
# offline and still does real validation locally and in Tier-3.
#
# Note: `ghostty +validate-config` is NOT usable here — it exits 0 even for a
# non-existent theme, so membership in +list-themes is the only reliable oracle.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

GHOSTTY_CFG="$SRC_DIR/dot_config/ghostty/config.tmpl"
THEMES_SNAPSHOT="$FIXTURES_DIR/ghostty-themes.txt"
# User theme files we ship (if any) live here; a name matching a file here
# always resolves regardless of the built-in set.
USER_THEMES_DIR="$SRC_DIR/dot_config/ghostty/themes"

# configured_theme — the value of the `theme = "..."` line in the rendered config.
configured_theme() {
  render "$GHOSTTY_CFG" full.toml | sed -nE 's/^theme = "(.*)"$/\1/p'
}

# live_theme_names — theme names known to the installed ghostty, with the
# trailing " (resources)" / " (user)" source tag stripped.
live_theme_names() {
  ghostty +list-themes --plain 2>/dev/null | sed -E 's/ \((resources|user)\)$//'
}

@test "ghostty: config template and snapshot fixture both exist" {
  [ -f "$GHOSTTY_CFG" ]
  [ -f "$THEMES_SNAPSHOT" ]
}

@test "ghostty: the config actually sets a theme (guard against a vacuous pass)" {
  # If the parser returned nothing the membership check below would pass on an
  # empty string — make that failure loud instead.
  run configured_theme
  assert_success
  [ -n "$output" ]
}

@test "ghostty: referenced theme resolves (live when ghostty present, snapshot offline)" {
  local theme; theme="$(configured_theme)"

  # A theme we vendor as a user file always resolves.
  if [ -f "$USER_THEMES_DIR/$theme" ]; then return 0; fi

  if command -v ghostty >/dev/null 2>&1; then
    live_theme_names | grep -qxF "$theme" || {
      echo "theme '$theme' is not a ghostty built-in (per +list-themes) and no user theme file ships it" >&2
      return 1
    }
  else
    echo "# ghostty not installed — using offline snapshot $THEMES_SNAPSHOT" >&3
    grep -qxF "$theme" "$THEMES_SNAPSHOT" || {
      echo "theme '$theme' not in snapshot; if it's a new/renamed built-in, run: make update-ghostty-themes" >&2
      return 1
    }
  fi
}

@test "ghostty: regression — the wrong 'catppuccin-mocha' name is not used" {
  run configured_theme
  refute_output 'catppuccin-mocha'
}
