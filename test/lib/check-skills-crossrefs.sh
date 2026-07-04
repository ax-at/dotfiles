#!/usr/bin/env bash
# test/lib/check-skills-crossrefs.sh
# skills.toml invariants that JSON Schema can't express. Renders the skills data
# to JSON via chezmoi (same engine the real template uses) and checks it with jq:
#   1. every top-level agent is a slug the `skills` CLI knows
#   2. every per-repo agent override is a known slug
#   3. no duplicate skill name across the whole file (the identity key for
#      install/remove -- must be unique even across different repos)
#   4. every `repo` is either "owner/repo" or a URL/git source
# Prints one line per violation and exits non-zero if any are found.
# Deps: chezmoi + jq only. The KNOWN_AGENTS list below was extracted from the
# `skills` CLI source (dist/cli.mjs agent configs) -- 72 slugs.
set -euo pipefail

CHEZMOI_BIN="${CHEZMOI_BIN:-chezmoi}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../home" && pwd)"

KNOWN_AGENTS='["adal","aider-desk","amp","antigravity","antigravity-cli","astrbot","augment","autohand-code","bob","claude-code","cline","codearts-agent","codebuddy","codemaker","codestudio","codex","command-code","continue","cortex","crush","cursor","deepagents","devin","dexto","droid","eve","firebender","forgecode","gemini-cli","github-copilot","goose","hermes-agent","iflow-cli","inference-sh","jazz","junie","kilo","kimi-code-cli","kiro-cli","kode","lingma","loaf","mcpjam","mistral-vibe","moxby","mux","neovate","ona","openclaw","opencode","openhands","pi","pochi","promptscript","qoder","qoder-cn","qwen-code","reasonix","replit","roo","rovodev","tabnine-cli","terramind","tinycloud","trae","trae-cn","universal","warp","windsurf","zed","zencoder","zenflow"]'

data="$("$CHEZMOI_BIN" execute-template --source "$SRC_DIR" \
  '{{ dict "repos" .repos "agents" .agents | toJson }}')"

errors="$(printf '%s' "$data" | jq -r --argjson known "$KNOWN_AGENTS" '
  ($known | INDEX(.)) as $ok
  | [ ( .agents[] | select($ok[.] | not)
        | "top-level agent \(.) is not a known skills-CLI slug" ),
      ( .repos[] as $r
        | ($r.agents // [])[] | select($ok[.] | not)
        | "\($r.repo): agent \(.) is not a known skills-CLI slug" ),
      ( .repos[]
        | select((.repo | test("^[^/[:space:]]+/[^/[:space:]]+$")
                          or test("^(https?://|git@)") or test("\\.git$")) | not)
        | "\(.repo): not owner/repo or a URL" )
    ]
  + ( [ .repos[].skills[] ] | group_by(.) | map(select(length > 1))
      | map("duplicate skill name: \(.[0])") )
  | .[]
')"

if [[ -n "$errors" ]]; then
  echo "$errors" >&2
  count="$(printf '%s\n' "$errors" | grep -c .)"
  echo "check-skills-crossrefs: $count skills invariant violation(s)" >&2
  exit 1
fi
echo "check-skills-crossrefs: skills invariants OK"
