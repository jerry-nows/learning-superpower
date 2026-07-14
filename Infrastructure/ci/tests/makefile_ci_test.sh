#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
makefile_path="${MAKEFILE_PATH:-$repo_root/Makefile}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

dry_run() {
  make --no-print-directory -C "$repo_root" -f "$makefile_path" -n "$1" 2>&1
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

assert_target_contains ci-backend 'unformatted="$(mise exec -- gofmt -l .)"'
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
assert_target_contains ci-security 'zricethezav/gitleaks:v8.28.0'
assert_target_contains ci-security 'detect --source=/repo'
assert_target_contains ci-security 'aquasec/trivy:0.66.0'
assert_target_contains ci-security 'fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 /repo'

assert_target_contains migrate 'docker compose --env-file'
assert_target_contains migrate 'up --build --wait api'
assert_target_contains seed 'run --rm --no-deps seed'
assert_target_contains auth-e2e 'Infrastructure/scripts/auth-e2e.sh'
assert_target_contains auth-e2e 'ENV_FILE='

make_targets_database="$(make --no-print-directory -C "$repo_root" -f "$makefile_path" -np auth-e2e 2>/dev/null)" \
  || fail 'unable to inspect auth-e2e dependency graph'
grep -Eq '^auth-e2e:([[:space:]]+migrate)([[:space:]]+seed)([[:space:]]|$)' \
  <<<"$make_targets_database" || fail 'auth-e2e must depend on migrate and seed'

ci_all_database="$(make --no-print-directory -C "$repo_root" -f "$makefile_path" -np ci-all 2>/dev/null)" \
  || fail 'unable to inspect ci-all dependency graph'
grep -Eq '^ci-all:([[:space:]]+ci-validate)([[:space:]]+ci-backend)([[:space:]]+ci-ios)([[:space:]]+ci-security)([[:space:]]|$)' \
  <<<"$ci_all_database" || fail 'ci-all must depend on ci-validate ci-backend ci-ios ci-security'

if [[ -z "${SKIP_MUTATION_FIXTURES:-}" ]]; then
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  assert_image_mutation_rejected() {
    local name=$1
    local original=$2
    local replacement=$3
    local fixture="$temp_dir/$name.mk"
    local output

    sed "s|$original|$replacement|" "$repo_root/Makefile" >"$fixture"
    if output="$(SKIP_MUTATION_FIXTURES=1 MAKEFILE_PATH="$fixture" bash "$0" 2>&1)"; then
      fail "container image mutation was accepted: $replacement"
    fi
    [[ "$output" == *"missing command: $original"* ]] \
      || fail "container image mutation failed for an unexpected reason: $output"
  }

  assert_image_mutation_rejected gitleaks-latest \
    'zricethezav/gitleaks:v8.28.0' 'zricethezav/gitleaks:latest'
  assert_image_mutation_rejected gitleaks-arbitrary \
    'zricethezav/gitleaks:v8.28.0' 'zricethezav/gitleaks:v8.29.0'
  assert_image_mutation_rejected trivy-latest \
    'aquasec/trivy:0.66.0' 'aquasec/trivy:latest'
  assert_image_mutation_rejected trivy-malformed \
    'aquasec/trivy:0.66.0' 'aquasec/trivy:0.66'
fi

printf 'PASS: Makefile CI targets match the local quality-gate contract\n'
