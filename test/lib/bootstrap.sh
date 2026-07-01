#!/usr/bin/env bash
# test/lib/bootstrap.sh
# Idempotently fetch bats-core + helper libs at pinned tags into test/lib/.
# These dirs are gitignored; this runs on first `make test` and in CI.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# repo -> pinned tag
clone_pinned() {
  local url="$1" tag="$2" dest="$3"
  if [ -d "$LIB_DIR/$dest/.git" ]; then
    echo "  ✓ $dest ($tag) already present"
    return
  fi
  echo "  -> fetching $dest ($tag)"
  git clone --quiet --depth 1 --branch "$tag" "$url" "$LIB_DIR/$dest"
}

echo "==> [bootstrap] test dependencies"
clone_pinned https://github.com/bats-core/bats-core.git v1.11.1 bats-core
clone_pinned https://github.com/bats-core/bats-support.git v0.3.0 bats-support
clone_pinned https://github.com/bats-core/bats-assert.git v2.1.0 bats-assert
echo "==> [bootstrap] done"
