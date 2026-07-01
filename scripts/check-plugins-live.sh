#!/usr/bin/env bash
# scripts/check-plugins-live.sh
# Validate every plugin in home/dot_zsh_plugins.txt against LIVE GitHub: the
# repo exists, and where a `path:` is given that path resolves. Unlike the
# offline snapshot in test/fixtures/omz-plugins.txt this stays fresh (catches
# upstream renames/removals) and covers the community repos (Aloxaf, hlissner,
# zsh-users) an Oh-My-Zsh-only snapshot can't.
#
# Tri-state exit so the bats guard can choose live-vs-snapshot without ever
# flaking on a network blip:
#   0  every reference resolves
#   1  a reference genuinely does not exist (repo/path/plugin 404)
#   2  could not check — offline, rate-limited, or a transient API error
#
# Honors $GITHUB_TOKEN / $GH_TOKEN for a higher API rate limit. Point
# $GH_API_BASE at another host to test the offline path. Deps: curl + jq.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_TXT="$REPO_ROOT/home/dot_zsh_plugins.txt"
API="${GH_API_BASE:-https://api.github.com}"
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

# api_body <url> -> response body on stdout; nonzero on any curl/HTTP failure.
api_body() {
  if [ -n "$token" ]; then
    curl -fsSL --connect-timeout 5 --max-time 20 \
      -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$1"
  else
    curl -fsSL --connect-timeout 5 --max-time 20 \
      -H "Accept: application/vnd.github+json" "$1"
  fi
}

# http_code <url> -> numeric HTTP status, or 000 when the request never landed.
http_code() {
  if [ -n "$token" ]; then
    curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 20 \
      -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$1" 2>/dev/null || echo 000
  else
    curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 20 \
      -H "Accept: application/vnd.github+json" "$1" 2>/dev/null || echo 000
  fi
}

# ---- connectivity + rate-limit probe (decides offline vs live) ------------
# /rate_limit is itself exempt from the limit, so it doubles as a liveness ping.
remaining="$(api_body "$API/rate_limit" 2>/dev/null | jq -r '.resources.core.remaining // empty' 2>/dev/null || true)"
if [ -z "$remaining" ]; then
  echo "check-plugins-live: no GitHub connectivity — inconclusive" >&2
  exit 2
fi
if [ "$remaining" -lt 8 ]; then
  echo "check-plugins-live: GitHub API budget nearly exhausted ($remaining left) — inconclusive" >&2
  exit 2
fi

# ---- parse entries (skip blank + comment lines) ---------------------------
# Each antidote line is `owner/repo [annotations...]`; take the repo and, if
# present, the `path:<p>` annotation. Parallel indexed arrays (bash 3.2-safe).
entry_repos=()
entry_paths=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '' | \#*) continue ;; esac
  repo="$(printf '%s' "$line" | awk '{print $1}')"
  case "$repo" in */*) : ;; *) continue ;; esac # only owner/repo shorthand
  path="$(printf '%s' "$line" | grep -oE 'path:[^[:space:]]+' | sed 's/^path://' || true)"
  entry_repos+=("$repo")
  entry_paths+=("$path")
done <"$PLUGINS_TXT"

if [ "${#entry_repos[@]}" -eq 0 ]; then
  echo "check-plugins-live: no plugin entries found in $PLUGINS_TXT" >&2
  exit 1
fi

errors=()
inconclusive=0

# ---- 1. every referenced repo exists (deduped) ----------------------------
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  case "$(http_code "$API/repos/$repo")" in
    200) : ;;
    404) errors+=("$repo: repository not found on GitHub") ;;
    *) inconclusive=$((inconclusive + 1)) ;;
  esac
done < <(printf '%s\n' "${entry_repos[@]}" | sort -u)

# ---- 2. Oh-My-Zsh plugin names: fetch the listing once, check locally ------
omz_plugins=""
omz_ok=0
if printf '%s\n' "${entry_paths[@]}" | grep -q '^plugins/'; then
  if omz_plugins="$(api_body "$API/repos/ohmyzsh/ohmyzsh/contents/plugins" | jq -r '.[] | select(.type=="dir") | .name')"; then
    omz_ok=1
  else
    inconclusive=$((inconclusive + 1))
  fi
fi

# ---- 3. per-entry path resolution -----------------------------------------
n=${#entry_repos[@]}
i=0
while [ "$i" -lt "$n" ]; do
  repo="${entry_repos[$i]}"
  path="${entry_paths[$i]}"
  i=$((i + 1))
  [ -n "$path" ] || continue
  case "$repo::$path" in
    "ohmyzsh/ohmyzsh::plugins/"*)
      name="${path#plugins/}"
      if [ "$omz_ok" -eq 1 ]; then
        grep -qxF "$name" <<<"$omz_plugins" ||
          errors+=("ohmyzsh/ohmyzsh: '$name' is not a current Oh-My-Zsh plugin")
      fi
      ;;
    *)
      case "$(http_code "$API/repos/$repo/contents/$path")" in
        200) : ;;
        404) errors+=("$repo: path '$path' does not exist on the default branch") ;;
        *) inconclusive=$((inconclusive + 1)) ;;
      esac
      ;;
  esac
done

# ---- verdict --------------------------------------------------------------
if [ "${#errors[@]}" -gt 0 ]; then
  printf '%s\n' "${errors[@]}" >&2
  echo "check-plugins-live: ${#errors[@]} invalid plugin reference(s)" >&2
  exit 1
fi
if [ "$inconclusive" -gt 0 ]; then
  echo "check-plugins-live: $inconclusive check(s) could not complete — inconclusive" >&2
  exit 2
fi
echo "check-plugins-live: all $n plugin reference(s) resolve on GitHub"
