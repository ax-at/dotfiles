#!/usr/bin/env bash
# Regenerate SKILLS.md from skills.toml using chezmoi's template engine.
# Usage: ./scripts/gen-skills.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/home"
TMPL="$ROOT/scripts/skills.md.tmpl"
OUT="$ROOT/SKILLS.md"

command -v chezmoi >/dev/null 2>&1 || {
  echo "chezmoi not installed" >&2
  exit 1
}

# Render the template against the registry data only (no init prompts).
chezmoi execute-template --source "$SRC" <"$TMPL" >"$OUT"
echo "Wrote $OUT"
