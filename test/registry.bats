#!/usr/bin/env bats
# Registry data integrity: JSON-Schema structure (taplo) + cross-ref invariants.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'

REGISTRY="$SRC_DIR/.chezmoidata/registry.toml"
SCHEMA="$REPO_ROOT/test/lib/registry.schema.json"

@test "registry.toml matches the JSON schema (taplo)" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
  run taplo check --schema "file://$SCHEMA" "$REGISTRY"
  assert_success
}

@test "registry cross-references are valid (module refs, platform tables, dups)" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  run bash "$REPO_ROOT/test/lib/check-crossrefs.sh"
  assert_success
  assert_output --partial "registry invariants OK"
}
