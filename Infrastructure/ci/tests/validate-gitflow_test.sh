#!/usr/bin/env bash
set -u

readonly POLICY="Infrastructure/ci/validate-gitflow.sh"
failures=0

run_policy() {
  BASE_REF="$1" HEAD_REF="$2" PR_DRAFT="$3" PR_TITLE="$4" \
    bash "$POLICY" 2>&1
}

expect_pass() {
  local name="$1"
  shift

  if output="$(run_policy "$@")"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s (expected success, got: %s)\n' "$name" "$output"
    failures=$((failures + 1))
  fi
}

expect_fail() {
  local name="$1"
  shift

  if output="$(run_policy "$@")"; then
    printf 'FAIL: %s (expected failure, got: %s)\n' "$name" "$output"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$name"
  fi
}

expect_pass 'feature branch targets develop' develop feature/cart false 'feat(cart): add cart'
expect_pass 'release branch targets main' main release/1.0.0 false 'chore(release): prepare 1.0.0'
expect_pass 'hotfix branch targets main' main hotfix/cve false 'fix(security): patch cve'
expect_fail 'feature branch cannot target main' main feature/cart false 'feat(cart): add cart'
expect_fail 'main cannot target develop' develop main false 'chore: sync main'
expect_fail 'draft pull request is rejected' develop feature/cart true 'feat(cart): add cart'
expect_fail 'non-Conventional title is rejected' develop feature/cart false 'Add cart'

if ((failures > 0)); then
  printf '%d test(s) failed\n' "$failures"
  exit 1
fi

printf 'All 7 tests passed\n'
