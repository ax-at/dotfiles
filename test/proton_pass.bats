#!/usr/bin/env bats
# proton-pass-doctor: the Proton Pass secrets-pipeline health check.
#
# Same wrapper-logic pattern as shell_functions.bats: render the rc template,
# carve out the self-contained doctor block, source it, then drive each branch
# against a stubbed `pass-cli` in a hermetic env. What we prove here is that
# the wrapper *reports correctly* for every state pass-cli can be in. The live
# Proton resolution itself is out of scope — it needs a real authenticated
# session and a network, which no stub can stand in for without becoming a mock
# of the very thing under test.

load 'lib/bats-support/load'
load 'lib/bats-assert/load'
load 'lib/helpers'
load 'lib/isolate'

setup() {
  isolate
  # Render the rc template, then extract ONLY the directive-free doctor block so
  # it can be sourced in bash (the rest of .zshrc is zsh-specific).
  render_to_file "$SRC_DIR/dot_zshrc.tmpl" "$BATS_TEST_TMPDIR/zshrc.sh" full.toml
  awk '/# >>> proton-pass-doctor >>>/{f=1} f{print} /# <<< proton-pass-doctor <<</{f=0}' \
    "$BATS_TEST_TMPDIR/zshrc.sh" >"$BATS_TEST_TMPDIR/doctor.sh"
  [ -s "$BATS_TEST_TMPDIR/doctor.sh" ] || fail "proton-pass-doctor block not found in rendered .zshrc"

  # Hermetic PATH: pass-cli resolves ONLY to a stub in MOCKBIN, even on a
  # machine that has the real pass-cli installed (this repo's users do). /usr/bin
  # and /bin keep sh/env/coreutils available; the real pass-cli lives elsewhere
  # (e.g. Homebrew), so it can't leak in and make the not-installed test flaky.
  export PATH="$MOCKBIN:/usr/bin:/bin"
  source "$BATS_TEST_TMPDIR/doctor.sh"
}

@test "proton-pass-doctor: reports not-installed when pass-cli is absent" {
  run proton-pass-doctor
  assert_failure
  assert_output --partial 'pass-cli not installed'
}

@test "proton-pass-doctor: reports not-logged-in when the session is invalid" {
  make_stub pass-cli 'case "${1:-}" in info) exit 1 ;; esac'
  run proton-pass-doctor
  assert_failure
  assert_output --partial 'not logged in'
}

@test "proton-pass-doctor: flags an unresolved canary (session OK, ref not substituted)" {
  # info succeeds, but `run` execs the child WITHOUT substituting the pass://
  # ref — so the canary stays a literal pass:// string, exactly what a missing
  # or mistyped item looks like end to end.
  make_stub pass-cli 'case "${1:-}" in
  info) exit 0 ;;
  run) shift; [ "${1:-}" = "--" ] && shift; exec "$@" ;;
esac'
  run proton-pass-doctor
  assert_failure
  assert_output --partial 'did not resolve'
}

@test "proton-pass-doctor: OK when the canary resolves to a real value" {
  # `pass-cli run` substitutes the pass:// ref in the child's env before exec —
  # here to a non-empty, non-pass:// value, i.e. a genuinely resolved secret.
  make_stub pass-cli 'case "${1:-}" in
  info) exit 0 ;;
  run) shift; [ "${1:-}" = "--" ] && shift; export PROTON_PASS_CANARY=resolved-secret; exec "$@" ;;
esac'
  run proton-pass-doctor
  assert_success
  assert_output --partial 'secrets pipeline resolves'
}
