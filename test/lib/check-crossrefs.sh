#!/usr/bin/env bash
# test/lib/check-crossrefs.sh
# Registry invariants that JSON Schema can't express. Renders the registry data
# to JSON via chezmoi (same engine the real templates use) and checks it with jq:
#   1. every package's `module` exists in [modules]
#   2. every declared platform has a matching [os] table with a `method`
#   3. npm/script methods have `check`; script also has `cmd`
#   4. no duplicate package `name`
# Prints one line per violation and exits non-zero if any are found.
# Deps: chezmoi + jq only.
set -euo pipefail

CHEZMOI_BIN="${CHEZMOI_BIN:-chezmoi}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../home" && pwd)"

data="$("$CHEZMOI_BIN" execute-template --source "$SRC_DIR" \
  '{{ dict "packages" .packages "modules" .modules | toJson }}')"

errors="$(printf '%s' "$data" | jq -r '
  .modules as $mods
  | [ .packages[] as $p
      | ( if ($mods | has($p.module)) then empty
          else "\($p.name): module \($p.module) not in [modules]" end ),
        ( $p.platforms[] as $os
          | if (($p[$os]) | type) != "object"
              then "\($p.name): platforms lists \($os) but has no [\($os)] table"
            elif (($p[$os].method) | type) != "string"
              then "\($p.name): [\($os)] table is missing a method"
            else empty end ),
        ( $p.platforms[] as $os
          | ($p[$os] // {}) as $t
          | if (($t.method == "npm" or $t.method == "script") and ($t.check | type) != "string")
              then "\($p.name)/\($os): method \($t.method) requires a check"
            elif ($t.method == "script" and ($t.cmd | type) != "string")
              then "\($p.name)/\($os): method script requires a cmd"
            else empty end )
    ]
  + ( [ .packages[].name ] | group_by(.) | map(select(length > 1))
      | map("duplicate package name: \(.[0])") )
  | .[]
')"

if [[ -n "$errors" ]]; then
  echo "$errors" >&2
  count="$(printf '%s\n' "$errors" | grep -c .)"
  echo "check-crossrefs: $count registry invariant violation(s)" >&2
  exit 1
fi
echo "check-crossrefs: registry invariants OK"
