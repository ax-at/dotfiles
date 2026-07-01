# test/lib/helpers.bash
# Shared paths + a thin wrapper around `chezmoi execute-template`, sourced by
# every suite. Override the chezmoi binary with CHEZMOI_BIN if it isn't on PATH.

CHEZMOI_BIN="${CHEZMOI_BIN:-chezmoi}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$REPO_ROOT/home"
FIXTURES_DIR="$REPO_ROOT/test/fixtures"
SCRIPTS_DIR="$SRC_DIR/.chezmoiscripts"

# render <tmpl-path> [fixture-name]
# Renders a template to stdout. If a fixture name is given (e.g. "ai-off.toml"),
# it is passed as the chezmoi --config so its [data.*] block feeds the render.
render() {
  local tmpl="$1" fixture="${2:-}"
  if [[ -n "$fixture" ]]; then
    "$CHEZMOI_BIN" execute-template --source "$SRC_DIR" \
      --config "$FIXTURES_DIR/$fixture" --config-format toml <"$tmpl"
  else
    "$CHEZMOI_BIN" execute-template --source "$SRC_DIR" <"$tmpl"
  fi
}

# render_to_file <tmpl-path> <out-path> [fixture-name]
render_to_file() {
  render "$1" "${3:-}" >"$2"
}

# script_tmpl <basename-glob> — resolve a .chezmoiscripts template by glob,
# e.g. script_tmpl 40-ai-tools -> .../run_onchange_after_40-ai-tools.sh.tmpl
script_tmpl() {
  local match=("$SCRIPTS_DIR"/*"$1"*.tmpl)
  printf '%s\n' "${match[0]}"
}
