#!/usr/bin/env bash
# Regenerate TOOLS.md from the registry using chezmoi's template engine.
# Usage: ./scripts/gen-tools.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/home"
TMPL="$ROOT/scripts/tools.md.tmpl"
OUT="$ROOT/TOOLS.md"

command -v chezmoi >/dev/null 2>&1 || { echo "chezmoi not installed" >&2; exit 1; }

# Render the template against the registry data only (no init prompts).
chezmoi execute-template --source "$SRC" < "$TMPL" > "$OUT"
echo "Wrote $OUT"
