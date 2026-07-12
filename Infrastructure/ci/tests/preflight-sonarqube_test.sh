#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PREFLIGHT="$ROOT_DIR/Infrastructure/ci/preflight-sonarqube.sh"
SECRET_FIXTURE="secret-token-value"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cat >"$TMP_DIR/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail

case "${MOCK_CURL_MODE:-up}" in
  unreachable)
    echo "curl: (7) Failed to connect" >&2
    exit 7
    ;;
  starting)
    printf '{ "id": "node-1", "status" : "STARTING", "version": "2026.1" }\n'
    ;;
  secret_status)
    printf '{ "id": "node-1", "status" : "secret-token-value", "version": "2026.1" }\n'
    ;;
  up)
    printf '{\n  "id": "node-1",\n  "status" : "UP",\n  "version": "2026.1"\n}\n'
    ;;
esac
MOCK_CURL
chmod +x "$TMP_DIR/curl"

run_preflight() {
  env \
    SONAR_HOST_URL="${SONAR_HOST_URL-}" \
    SONAR_TOKEN="${SONAR_TOKEN-}" \
    CURL_BIN="$TMP_DIR/curl" \
    MOCK_CURL_MODE="${MOCK_CURL_MODE-up}" \
    bash "$PREFLIGHT"
}

assert_failure() {
  local expected="$1"
  local output

  if output="$(run_preflight 2>&1)"; then
    fail "preflight unexpectedly succeeded; wanted message containing: $expected"
  fi
  [[ "$output" == *"$expected"* ]] || fail "expected message containing '$expected', got: $output"
  [[ "$output" != *"$SECRET_FIXTURE"* ]] || fail "secret token leaked in output"
}

SONAR_HOST_URL=""
SONAR_TOKEN="$SECRET_FIXTURE"
assert_failure "SONAR_HOST_URL is required"

SONAR_HOST_URL="https://sonar.example.test"
SONAR_TOKEN=""
assert_failure "SONAR_TOKEN is required"

SONAR_HOST_URL="https://sonar.example.test"
SONAR_TOKEN="$SECRET_FIXTURE"
MOCK_CURL_MODE="unreachable"
assert_failure "Unable to reach SonarQube"

MOCK_CURL_MODE="starting"
assert_failure "SonarQube is not UP"

MOCK_CURL_MODE="secret_status"
assert_failure "SonarQube is not UP"

MOCK_CURL_MODE="up"
output="$(run_preflight 2>&1)" || fail "UP status was rejected: $output"
[[ "$output" == *"SonarQube preflight passed."* ]] || fail "success message was not emitted"
[[ "$output" != *"$SECRET_FIXTURE"* ]] || fail "secret token leaked in output"

echo "PASS: SonarQube preflight fixtures"
