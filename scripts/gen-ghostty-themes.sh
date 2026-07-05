#!/usr/bin/env bash
# Regenerate the committed snapshot of Ghostty's built-in theme names.
#
# test/ghostty_theme.bats prefers a live check (`ghostty +list-themes`) but the
# CI runners have no Ghostty, so it falls back to this snapshot as the offline
# oracle. Run this on a machine with Ghostty installed after upgrading the app
# (a Ghostty release can add/rename built-ins):  make update-ghostty-themes
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$repo_root/test/fixtures/ghostty-themes.txt"

command -v ghostty >/dev/null 2>&1 ||
  {
    echo "ghostty not on PATH — run this on a machine with Ghostty installed" >&2
    exit 1
  }

# `+list-themes --plain` prints "<name> (resources|user)". Keep only the
# app-bundled built-ins (resources); user themes are per-machine, not portable.
ghostty +list-themes --plain |
  sed -n -E 's/ \(resources\)$//p' |
  LC_ALL=C sort -u >"$out"

echo "wrote $(grep -c '' "$out") built-in theme names to $out"
