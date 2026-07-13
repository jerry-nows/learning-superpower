#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

dry_run() {
  make --no-print-directory -C "$repo_root" -n "$1" 2>&1
}

assert_target_contains() {
  local target=$1
  local expected=$2
  local output

  output="$(dry_run "$target")" || fail "make -n $target failed: $output"
  grep -Fq -- "$expected" <<<"$output" \
    || fail "$target is missing command: $expected"
}

for test_script in \
  validate-gitflow_test.sh \
  preflight-ios-runner_test.sh \
  preflight-sonarqube_test.sh \
  sonar_config_test.sh \
  sourcery_config_test.sh \
  xccov-to-sonarqube_test.sh \
  validate-workflows_test.sh; do
  assert_target_contains ci-validate "bash Infrastructure/ci/tests/$test_script"
done

assert_target_contains ci-backend 'unformatted="$(gofmt -l .)"'
assert_target_contains ci-backend 'go vet ./...'
assert_target_contains ci-backend 'go run honnef.co/go/tools/cmd/staticcheck@2025.1.1 ./...'
assert_target_contains ci-backend 'go test -race -coverprofile=coverage.out ./...'

assert_target_contains ci-ios 'Infrastructure/ci/preflight-ios-runner.sh'
assert_target_contains ci-ios 'mise exec -- swiftlint lint --strict'
assert_target_contains ci-ios 'make ios-test-packages'
assert_target_contains ci-ios '-resultBundlePath TestResults/CommerceApp.xcresult'
assert_target_contains ci-ios 'test CODE_SIGNING_ALLOWED=NO'
assert_target_contains ci-ios 'make ios-build-unsigned'

assert_target_contains ci-security 'docker run --rm'
assert_target_contains ci-security 'zricethezav/gitleaks:'
assert_target_contains ci-security 'detect --source=/repo'
assert_target_contains ci-security 'aquasec/trivy:'
assert_target_contains ci-security 'fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 /repo'

ci_all_database="$(make --no-print-directory -C "$repo_root" -np ci-all 2>/dev/null)" \
  || fail 'unable to inspect ci-all dependency graph'
grep -Eq '^ci-all:([[:space:]]+ci-validate)([[:space:]]+ci-backend)([[:space:]]+ci-ios)([[:space:]]+ci-security)([[:space:]]|$)' \
  <<<"$ci_all_database" || fail 'ci-all must depend on ci-validate ci-backend ci-ios ci-security'

printf 'PASS: Makefile CI targets match the local quality-gate contract\n'
